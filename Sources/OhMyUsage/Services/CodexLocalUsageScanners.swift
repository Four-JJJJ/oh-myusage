import Foundation
import OhMyUsageApplication
import SQLite3

enum CodexSessionTokenEventScanner {
    static func parse(filePath: String) -> [ParsedTokenEvent] {
        var state = SessionTokenScannerState()
        var output: [ParsedTokenEvent] = []

        CodexLocalUsageJSONLScanner.scanLines(atPath: filePath) { line in
            guard line.contains("\"type\":\"") else {
                return
            }
            let isEventMsg = line.contains("\"type\":\"event_msg\"")
            let isTurnContext = line.contains("\"type\":\"turn_context\"")
            let isSessionMeta = line.contains("\"type\":\"session_meta\"")
            guard isEventMsg || isTurnContext || isSessionMeta else {
                return
            }
            if isEventMsg, !line.contains("\"token_count\"") {
                return
            }

            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = object["type"] as? String else {
                return
            }

            if type == "session_meta" {
                return
            }

            if type == "turn_context" {
                let payload = object["payload"] as? [String: Any]
                let info = payload?["info"] as? [String: Any]
                state.currentModel = CodexLocalUsageEventParser.normalizedModelID(
                    CodexLocalUsageEventParser.stringValue(payload?["model"])
                        ?? CodexLocalUsageEventParser.stringValue(info?["model"])
                )
                return
            }

            guard type == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  CodexLocalUsageEventParser.stringValue(payload["type"]) == "token_count",
                  let timestampText = CodexLocalUsageEventParser.stringValue(object["timestamp"]),
                  let eventAt = CodexLocalUsageEventParser.parseISODate(timestampText) else {
                return
            }

            let info = payload["info"] as? [String: Any]
            let model = CodexLocalUsageEventParser.normalizedModelID(
                CodexLocalUsageEventParser.stringValue(info?["model"])
                    ?? CodexLocalUsageEventParser.stringValue(info?["model_name"])
                    ?? CodexLocalUsageEventParser.stringValue(payload["model"])
                    ?? state.currentModel
            )

            var deltaTokens = 0
            var deltaComponents = TokenComponents()
            if let totalUsage = info?["total_token_usage"] as? [String: Any],
               let snapshotComponents = CodexLocalUsageEventParser.sessionTokenComponents(from: totalUsage) {
                let snapshotTotal = snapshotComponents.totalTokens
                let signature = "T|\(timestampText)|\(snapshotTotal)"
                guard state.seenTokenSnapshots.insert(signature).inserted else {
                    return
                }

                if snapshotTotal >= state.previousTotalTokens {
                    deltaTokens = snapshotTotal - state.previousTotalTokens
                    deltaComponents = snapshotComponents.delta(
                        from: state.previousTokenComponents,
                        fallbackTotal: deltaTokens
                    )
                } else {
                    deltaTokens = 0
                    deltaComponents = TokenComponents()
                }
                state.previousTotalTokens = snapshotTotal
                state.previousTokenComponents = snapshotComponents
            } else if let lastUsage = info?["last_token_usage"] as? [String: Any],
                      let lastComponents = CodexLocalUsageEventParser.sessionTokenComponents(from: lastUsage) {
                let lastTokens = lastComponents.totalTokens
                let signature = "L|\(timestampText)|\(lastTokens)"
                guard state.seenTokenSnapshots.insert(signature).inserted else {
                    return
                }

                deltaTokens = max(0, lastTokens)
                deltaComponents = lastComponents
                state.previousTotalTokens += deltaTokens
                state.previousTokenComponents = state.previousTokenComponents.adding(deltaComponents)
            } else {
                return
            }

            guard deltaTokens > 0 else {
                return
            }

            output.append(
                ParsedTokenEvent(
                    signature: "session|\(filePath)|\(timestampText)|\(deltaTokens)|\(model)",
                    eventAt: eventAt,
                    modelID: model,
                    totalTokens: deltaTokens,
                    inputTokens: deltaComponents.inputTokens,
                    outputTokens: deltaComponents.outputTokens,
                    cacheReadTokens: deltaComponents.cacheReadTokens,
                    cacheWriteTokens: deltaComponents.cacheWriteTokens,
                    accountID: nil,
                    email: nil
                )
            )
        }
        return output
    }
}

struct CodexIdentityLogEventScanner {
    var maxRowCount: Int

    func scan(databasePath: String, startOfLast30Days: Date) -> IdentityLogScanResult {
        let startEpoch = Int64(startOfLast30Days.timeIntervalSince1970)
        let query = """
        SELECT ts, feedback_log_body
        FROM (
            SELECT ts, feedback_log_body
            FROM logs
            WHERE ts IS NOT NULL
              AND ts >= ?
              AND feedback_log_body IS NOT NULL
              AND (
                ltrim(feedback_log_body) LIKE 'event.name=codex.sse_event%'
                OR ltrim(feedback_log_body) LIKE 'event.name="codex.sse_event"%'
              )
            ORDER BY ts DESC
            LIMIT ?
        )
        ORDER BY ts ASC;
        """

        var database: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            return Self.emptyResult()
        }
        defer {
            sqlite3_close(database)
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return Self.emptyResult()
        }
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, startEpoch)
        sqlite3_bind_int(statement, 2, Int32(maxRowCount))

        var matchedRows = 0
        var dedupedEvents: [String: ParsedTokenEvent] = [:]
        var parsedEvents = 0
        var latestParsedEventAt: Date?
        var recoveredByConversationResponses = 0
        var recoveredByConversationTokens = 0
        var unattributedResponses = 0
        var unattributedTokens = 0
        var conversationIdentity: [String: ConversationIdentity] = [:]

        while !Task.isCancelled {
            let stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_ROW else {
                break
            }

            matchedRows += 1

            guard let timestampText = Self.sqliteColumnText(statement, index: 0),
                  let rowEventAt = Self.parseTimestampDate(timestampText),
                  let body = Self.sqliteColumnText(statement, index: 1) else {
                continue
            }
            if rowEventAt < startOfLast30Days {
                continue
            }

            guard let metadata = CodexLocalUsageEventParser.parseCodexSSEMetadata(from: body) else {
                continue
            }

            if let conversationID = metadata.conversationID,
               metadata.hasIdentity {
                conversationIdentity[conversationID] = ConversationIdentity(
                    accountID: metadata.accountID,
                    email: metadata.email
                )
            }

            guard metadata.kind == "response.completed" else {
                continue
            }

            guard var event = CodexLocalUsageEventParser.parseCompletedEvent(from: body, fallbackEventAt: rowEventAt) else {
                continue
            }
            parsedEvents += 1
            if event.eventAt < startOfLast30Days {
                continue
            }
            if latestParsedEventAt == nil || event.eventAt > (latestParsedEventAt ?? .distantPast) {
                latestParsedEventAt = event.eventAt
            }

            if !event.hasIdentity,
               let conversationID = metadata.conversationID,
               let recovered = conversationIdentity[conversationID] {
                event.accountID = event.accountID ?? recovered.accountID
                event.email = event.email ?? recovered.email
                if event.hasIdentity {
                    recoveredByConversationResponses += 1
                    recoveredByConversationTokens += event.totalTokens
                }
            }

            if !event.hasIdentity {
                unattributedResponses += 1
                unattributedTokens += event.totalTokens
            }

            if let conversationID = metadata.conversationID,
               event.hasIdentity {
                conversationIdentity[conversationID] = ConversationIdentity(
                    accountID: event.accountID,
                    email: event.email
                )
            }

            if let existing = dedupedEvents[event.signature] {
                if existing.totalTokens == event.totalTokens {
                    dedupedEvents[event.signature] = existing.mergedIdentity(with: event)
                    continue
                }
                event.signature += "#tok=\(event.totalTokens)"
            }

            if let existing = dedupedEvents[event.signature],
               existing.totalTokens == event.totalTokens {
                dedupedEvents[event.signature] = existing.mergedIdentity(with: event)
            } else {
                dedupedEvents[event.signature] = event
            }
        }

        return IdentityLogScanResult(
            events: Array(dedupedEvents.values),
            diagnostics: CodexLocalUsageDiagnostics(
                matchedRows: matchedRows,
                parsedEvents: parsedEvents,
                attributableEvents: 0,
                recoveredByConversationResponses: recoveredByConversationResponses,
                recoveredByConversationTokens: recoveredByConversationTokens,
                unattributedResponses: unattributedResponses,
                unattributedTokens: unattributedTokens,
                latestEventAt: latestParsedEventAt,
                source: .strict
            )
        )
    }

    private static func emptyResult() -> IdentityLogScanResult {
        IdentityLogScanResult(
            events: [],
            diagnostics: CodexLocalUsageDiagnostics(
                matchedRows: 0,
                parsedEvents: 0,
                attributableEvents: 0,
                recoveredByConversationResponses: 0,
                recoveredByConversationTokens: 0,
                unattributedResponses: 0,
                unattributedTokens: 0,
                latestEventAt: nil,
                source: .strict
            )
        )
    }

    private static func parseTimestampDate(_ raw: String) -> Date? {
        guard let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        if value > 1_000_000_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000_000_000)
        }
        if value > 1_000_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000_000)
        }
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000)
        }
        return Date(timeIntervalSince1970: value)
    }

    private static func sqliteColumnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }
}

enum CodexLocalUsageJSONLScanner {
    static func scanLines(
        atPath path: String,
        maxLineBytes: Int = RuntimeDiagnosticsLimits.jsonlMaxLineBytes,
        onLine: (String) -> Void
    ) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return
        }
        defer {
            try? handle.close()
        }

        let newline = Data([0x0A])
        var buffer = Data()
        var droppingOversizedLine = false

        while !Task.isCancelled {
            let chunk = try? handle.read(upToCount: 64 * 1024)
            guard let chunk else {
                break
            }
            if chunk.isEmpty {
                if !droppingOversizedLine,
                   !buffer.isEmpty,
                   buffer.count <= maxLineBytes,
                   let line = String(data: buffer, encoding: .utf8) {
                    onLine(line)
                }
                break
            }

            if droppingOversizedLine {
                guard let range = chunk.range(of: newline) else {
                    continue
                }
                droppingOversizedLine = false
                buffer = Data(chunk.suffix(from: range.upperBound))
            } else {
                buffer.append(chunk)
            }

            while !Task.isCancelled, let range = buffer.range(of: newline) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)

                guard !lineData.isEmpty, lineData.count <= maxLineBytes,
                      let line = String(data: lineData, encoding: .utf8) else {
                    continue
                }
                onLine(line)
            }

            if buffer.count > maxLineBytes {
                buffer.removeAll(keepingCapacity: false)
                droppingOversizedLine = true
            }
        }
    }
}

private struct SessionTokenScannerState {
    var currentModel: String?
    var previousTotalTokens: Int = 0
    var previousTokenComponents = TokenComponents()
    var seenTokenSnapshots: Set<String> = []
}

private struct ConversationIdentity {
    var accountID: String?
    var email: String?
}
