import Foundation
import OhMyUsageApplication

final class KimiLocalUsageService {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let defaultSessionsRootPath: String?
    private let onWireFileParsed: ((String) -> Void)?

    private static let wireFileEnumerationCache = LocalUsageFileEnumerationCache()
    private static let parsedWireFileCache = LocalUsageParsedFileCache<LocalUsageEvent>(maxEntries: 2_048)

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        defaultSessionsRootPath: String? = nil,
        onWireFileParsed: ((String) -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.defaultSessionsRootPath = defaultSessionsRootPath
        self.onWireFileParsed = onWireFileParsed
    }

    func fetchSummary(
        scope: LocalUsageTrendScope = .allAccounts,
        sessionsRootPath: String? = nil
    ) throws -> LocalUsageSummary {
        _ = scope // v1: Kimi 仅支持全部账号，当前账号按全部账号处理。

        let sessionsRoot = resolvedSessionsRoot(explicitPath: sessionsRootPath)
        let now = nowProvider()
        let startOfLast30Days = calendar.date(
            byAdding: .day,
            value: -29,
            to: calendar.startOfDay(for: now)
        ) ?? now
        let events = scanSessionEvents(
            sessionsRoot: sessionsRoot,
            startOfLast30Days: startOfLast30Days
        )

        return LocalUsageSummaryBuilder.build(
            events: events,
            calendar: calendar,
            now: now,
            sourcePath: sessionsRoot
        )
    }

    func fetchEvents(
        scope: LocalUsageTrendScope = .allAccounts,
        sessionsRootPath: String? = nil,
        since: Date
    ) throws -> [LocalUsageEvent] {
        _ = scope
        return scanSessionEvents(
            sessionsRoot: resolvedSessionsRoot(explicitPath: sessionsRootPath),
            startOfLast30Days: since
        )
        .filter { $0.eventAt >= since }
    }

    private func resolvedSessionsRoot(explicitPath: String?) -> String {
        if let explicitPath {
            return explicitPath
        }
        if let defaultSessionsRootPath {
            return defaultSessionsRootPath
        }
        let home = NSHomeDirectory()
        let kimiCodeSessions = "\(home)/.kimi-code/sessions"
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: kimiCodeSessions, isDirectory: &isDir), isDir.boolValue {
            return kimiCodeSessions
        }
        return "\(home)/.kimi/sessions"
    }

    private func scanSessionEvents(
        sessionsRoot: String,
        startOfLast30Days: Date
    ) -> [LocalUsageEvent] {
        let cutoff = calendar.date(byAdding: .day, value: -1, to: startOfLast30Days) ?? startOfLast30Days
        let files = wireJSONLFiles(root: sessionsRoot, cutoff: cutoff)
        if files.isEmpty {
            return []
        }

        var output: [LocalUsageEvent] = []
        output.reserveCapacity(2048)
        let parseContext = "start=\(Int(startOfLast30Days.timeIntervalSinceReferenceDate))"

        for file in files {
            let events = Self.parsedWireFileCache.values(for: file, context: parseContext) {
                onWireFileParsed?(file.path)
                return parseWireFile(filePath: file.path, startOfLast30Days: startOfLast30Days)
            }
            output.append(contentsOf: events)
        }

        return output
    }

    private func wireJSONLFiles(root: String, cutoff: Date) -> [LocalUsageFileSnapshot] {
        Self.wireFileEnumerationCache.files(
            identifier: "kimi-wire-jsonl",
            roots: [root],
            cutoff: cutoff,
            fileManager: fileManager,
            includeFile: { $0.lastPathComponent == "wire.jsonl" }
        )
    }

    private func parseWireFile(
        filePath: String,
        startOfLast30Days: Date
    ) -> [LocalUsageEvent] {
        let sessionID = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .lastPathComponent
        var previousSnapshotTokens = 0
        var previousComponents = LocalUsageTokenComponents()
        var seenSnapshots: Set<String> = []
        var output: [LocalUsageEvent] = []
        var lineIndex = 0

        scanJSONLLines(atPath: filePath) { line in
            defer { lineIndex += 1 }
            // v2 journals (kimi-code Node CLI) persist one `usage.record` op per
            // LLM call whose usage is already a per-call delta; legacy journals
            // carry cumulative StatusUpdate snapshots instead.
            let looksLikeV2UsageRecord = line.contains("\"usage.record\"")
            let looksLikeV1StatusUpdate = line.contains("\"StatusUpdate\"") && line.contains("\"token_usage\"")
            guard looksLikeV2UsageRecord || looksLikeV1StatusUpdate else {
                return
            }

            guard let data = line.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return
            }

            if looksLikeV2UsageRecord,
               Self.stringValue(root["type"]) == "usage.record" {
                guard let eventAt = Self.parseTimestampDate(root["time"]),
                      eventAt >= startOfLast30Days,
                      let usage = root["usage"] as? [String: Any] else {
                    return
                }

                let components = Self.tokenComponents(from: usage)
                let total = components.totalTokens
                guard total > 0 else {
                    return
                }

                let signature = "kimi-v2|\(sessionID)|\(lineIndex)|\(Int(eventAt.timeIntervalSince1970))|\(total)"
                guard seenSnapshots.insert(signature).inserted else {
                    return
                }

                output.append(
                    LocalUsageEvent(
                        signature: signature,
                        eventAt: eventAt,
                        modelID: Self.stringValue(root["model"]) ?? "unknown",
                        totalTokens: total,
                        inputTokens: components.inputTokens,
                        outputTokens: components.outputTokens,
                        cacheReadTokens: components.cacheReadTokens,
                        cacheWriteTokens: components.cacheWriteTokens
                    )
                )
                return
            }

            guard looksLikeV1StatusUpdate,
                  let eventAt = Self.parseTimestampDate(root["timestamp"]),
                  eventAt >= startOfLast30Days,
                  let message = root["message"] as? [String: Any],
                  Self.stringValue(message["type"]) == "StatusUpdate",
                  let payload = message["payload"] as? [String: Any],
                  let usage = payload["token_usage"] as? [String: Any] else {
                return
            }

            let snapshotComponents = Self.tokenComponents(from: usage)
            let snapshotTotal = snapshotComponents.totalTokens
            guard snapshotTotal > 0 else {
                return
            }

            let snapshotSignature = "\(sessionID)|\(root["timestamp"] ?? "")|\(snapshotTotal)"
            guard seenSnapshots.insert(snapshotSignature).inserted else {
                return
            }

            let delta = max(0, snapshotTotal - previousSnapshotTokens)
            let deltaComponents = snapshotComponents.delta(from: previousComponents, fallbackTotal: delta)
            previousSnapshotTokens = snapshotTotal
            previousComponents = snapshotComponents
            guard delta > 0 else {
                return
            }

            let modelID = Self.stringValue(payload["model"])
                ?? Self.stringValue(message["model"])
                ?? "unknown"
            let messageID = Self.stringValue(payload["message_id"]) ?? "unknown-message"

            output.append(
                LocalUsageEvent(
                    signature: "kimi|\(sessionID)|\(messageID)|\(Int(eventAt.timeIntervalSince1970))|\(snapshotTotal)",
                    eventAt: eventAt,
                    modelID: modelID,
                    totalTokens: delta,
                    inputTokens: deltaComponents.inputTokens,
                    outputTokens: deltaComponents.outputTokens,
                    cacheReadTokens: deltaComponents.cacheReadTokens,
                    cacheWriteTokens: deltaComponents.cacheWriteTokens
                )
            )
        }
        return output
    }

    private func scanJSONLLines(
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

        while true {
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

            while let range = buffer.range(of: newline) {
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

    private static func tokenComponents(from usage: [String: Any]) -> LocalUsageTokenComponents {
        let input = firstInt(
            in: usage,
            keys: ["input_other", "input_tokens", "input", "inputOther"]
        ) ?? 0
        let output = firstInt(
            in: usage,
            keys: ["output", "output_tokens"]
        ) ?? 0
        let cacheRead = firstInt(
            in: usage,
            keys: ["input_cache_read", "cache_read_input_tokens", "inputCacheRead"]
        ) ?? 0
        let cacheWrite = firstInt(
            in: usage,
            keys: ["input_cache_creation", "cache_creation_input_tokens", "inputCacheCreation"]
        ) ?? 0

        let components = LocalUsageTokenComponents(
            inputTokens: max(0, input),
            outputTokens: max(0, output),
            cacheReadTokens: max(0, cacheRead),
            cacheWriteTokens: max(0, cacheWrite)
        )
        if components.totalTokens > 0 {
            return components
        }

        let fallbackTotal = usage.values.reduce(0) { partial, value in
            partial + max(0, intValue(value) ?? 0)
        }
        return LocalUsageTokenComponents(outputTokens: fallbackTotal)
    }

    private static func firstInt(in usage: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = intValue(usage[key]) {
                return value
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value.rounded()) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func parseTimestampDate(_ raw: Any?) -> Date? {
        let epochValue: Double?
        if let value = raw as? Double {
            epochValue = value
        } else if let value = raw as? Int {
            epochValue = Double(value)
        } else if let value = raw as? NSNumber {
            epochValue = value.doubleValue
        } else if let value = raw as? String {
            epochValue = Double(value)
        } else {
            epochValue = nil
        }
        guard let epoch = epochValue else { return nil }
        // v2 wire journals stamp `time` in epoch milliseconds; legacy logs use seconds.
        return Date(timeIntervalSince1970: epoch > 1_000_000_000_000 ? epoch / 1000 : epoch)
    }
}
