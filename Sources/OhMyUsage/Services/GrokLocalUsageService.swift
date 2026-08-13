import Foundation
import OhMyUsageApplication

final class GrokLocalUsageService {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let sessionsRootPath: String

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        sessionsRootPath: String? = nil,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        if let sessionsRootPath {
            self.sessionsRootPath = sessionsRootPath
        } else {
            self.sessionsRootPath = Self.resolvedSessionsRoot(
                homeDirectory: homeDirectory(),
                environment: environment()
            )
        }
    }

    static func resolvedSessionsRoot(homeDirectory: String, environment: [String: String]) -> String {
        if let grokHome = environment["GROK_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !grokHome.isEmpty {
            var base = grokHome
            while base.hasSuffix("/") {
                base.removeLast()
            }
            return base + "/sessions"
        }
        return homeDirectory + "/.grok/sessions"
    }

    func fetchSummary() throws -> LocalUsageSummary {
        let now = nowProvider()
        let startOfLast30Days = calendar.date(
            byAdding: .day,
            value: -29,
            to: calendar.startOfDay(for: now)
        ) ?? now
        return LocalUsageSummaryBuilder.build(
            events: try fetchEvents(since: startOfLast30Days),
            calendar: calendar,
            now: now,
            sourcePath: sessionsRootPath
        )
    }

    func fetchEvents(since: Date) throws -> [LocalUsageEvent] {
        let files = LocalUsageFileEnumerationCache().files(
            identifier: "grok-session-summary",
            roots: [sessionsRootPath],
            cutoff: calendar.date(byAdding: .day, value: -1, to: since) ?? since,
            fileManager: fileManager,
            includeFile: { $0.lastPathComponent == "summary.json" }
        )
        var events: [LocalUsageEvent] = []
        for file in files {
            events.append(contentsOf: parseSession(summaryPath: file.path, since: since))
        }
        return events
    }

    private func parseSession(summaryPath: String, since: Date) -> [LocalUsageEvent] {
        let sessionDirectory = URL(fileURLWithPath: summaryPath).deletingLastPathComponent()
        let sessionID = sessionDirectory.lastPathComponent
        let summary = readJSON(at: sessionDirectory.appendingPathComponent("summary.json").path)
        let modelID = LocalUsageJSONParsing.stringValue(summary?["current_model_id"])
            ?? LocalUsageJSONParsing.stringValue(summary?["model"])
            ?? "grok"
        let fallbackDate = LocalUsageJSONParsing.parseTimestamp(summary?["updated_at"])
            ?? LocalUsageJSONParsing.parseTimestamp(summary?["created_at"])
            ?? fileManager.modificationDate(atPath: summaryPath)

        let updatesPath = sessionDirectory.appendingPathComponent("updates.jsonl").path
        let turnEvents = parseUpdates(
            path: updatesPath,
            sessionID: sessionID,
            modelID: modelID,
            since: since
        )
        if !turnEvents.isEmpty {
            return turnEvents
        }

        let signals = readJSON(at: sessionDirectory.appendingPathComponent("signals.json").path)
        let contextTokens = LocalUsageJSONParsing.firstInt(
            in: signals ?? [:],
            keys: ["contextTokensUsed", "context_tokens_used", "totalTokens"]
        ) ?? 0
        guard contextTokens > 0, let eventAt = fallbackDate, eventAt >= since else {
            return []
        }
        return [
            LocalUsageEvent(
                signature: "grok|\(sessionID)|signals|\(contextTokens)",
                eventAt: eventAt,
                modelID: modelID,
                totalTokens: contextTokens,
                inputTokens: contextTokens
            )
        ]
    }

    private func parseUpdates(
        path: String,
        sessionID: String,
        modelID: String,
        since: Date
    ) -> [LocalUsageEvent] {
        struct TurnState {
            var promptID: String
            var firstTokens: Int
            var lastTokens: Int
            var eventAt: Date
        }

        var turns: [String: TurnState] = [:]
        var anonymousIndex = 0
        CodexLocalUsageJSONLScanner.scanLines(atPath: path) { line in
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let meta = Self.meta(from: root),
                  let totalTokens = meta.totalTokens,
                  totalTokens > 0 else {
                return
            }
            let eventAt = LocalUsageJSONParsing.parseTimestamp(root["timestamp"])
                ?? LocalUsageJSONParsing.parseTimestamp(meta.timestamp)
                ?? Date.distantPast
            let promptID = meta.promptID ?? "anon-\(anonymousIndex)"
            if meta.promptID == nil {
                anonymousIndex += 1
            }
            if var existing = turns[promptID] {
                existing.lastTokens = totalTokens
                if eventAt > existing.eventAt {
                    existing.eventAt = eventAt
                }
                turns[promptID] = existing
            } else {
                turns[promptID] = TurnState(
                    promptID: promptID,
                    firstTokens: totalTokens,
                    lastTokens: totalTokens,
                    eventAt: eventAt
                )
            }
        }

        return turns.values.compactMap { turn in
            let output = max(0, turn.lastTokens - turn.firstTokens)
            let input = max(0, turn.firstTokens)
            let total = input + output
            guard total > 0 else { return nil }
            let eventAt = turn.eventAt == .distantPast ? since : turn.eventAt
            guard eventAt >= since else { return nil }
            return LocalUsageEvent(
                signature: "grok|\(sessionID)|\(turn.promptID)|\(Int(eventAt.timeIntervalSince1970))",
                eventAt: eventAt,
                modelID: modelID,
                totalTokens: total,
                inputTokens: input,
                outputTokens: output
            )
        }
    }

    private func readJSON(at path: String) -> [String: Any]? {
        guard fileManager.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private struct GrokUpdateMeta {
        var promptID: String?
        var totalTokens: Int?
        var timestamp: Any?
    }

    private static func meta(from root: [String: Any]) -> GrokUpdateMeta? {
        let params = root["params"] as? [String: Any]
        let update = params?["update"] as? [String: Any]
        let candidates: [[String: Any]] = [
            params?["_meta"] as? [String: Any],
            update?["_meta"] as? [String: Any],
            root["_meta"] as? [String: Any]
        ].compactMap { $0 }
        for meta in candidates {
            let totalTokens = LocalUsageJSONParsing.firstInt(
                in: meta,
                keys: ["totalTokens", "total_tokens", "contextTokens"]
            )
            let promptID = LocalUsageJSONParsing.stringValue(meta["promptId"])
                ?? LocalUsageJSONParsing.stringValue(meta["prompt_id"])
            if totalTokens != nil || promptID != nil {
                return GrokUpdateMeta(
                    promptID: promptID,
                    totalTokens: totalTokens,
                    timestamp: meta["timestamp"] ?? root["timestamp"]
                )
            }
        }
        return nil
    }
}

private extension FileManager {
    func modificationDate(atPath path: String) -> Date? {
        (try? attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }
}
