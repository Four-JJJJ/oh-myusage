import Foundation
import OhMyUsageApplication

final class GeminiLocalUsageService {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let tmpRootPath: String

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        tmpRootPath: String? = nil
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.tmpRootPath = tmpRootPath ?? "\(NSHomeDirectory())/.gemini/tmp"
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
            sourcePath: tmpRootPath
        )
    }

    func fetchEvents(since: Date) throws -> [LocalUsageEvent] {
        let files = LocalUsageFileEnumerationCache().files(
            identifier: "gemini-session-files",
            roots: [tmpRootPath],
            cutoff: calendar.date(byAdding: .day, value: -1, to: since) ?? since,
            fileManager: fileManager,
            includeFile: { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasPrefix("session-") && (name.hasSuffix(".jsonl") || name.hasSuffix(".json"))
            }
        )
        var events: [LocalUsageEvent] = []
        for file in files {
            events.append(contentsOf: parseSessionFile(path: file.path, since: since))
        }
        return events
    }

    private func parseSessionFile(path: String, since: Date) -> [LocalUsageEvent] {
        if path.lowercased().hasSuffix(".jsonl") {
            return parseJSONL(path: path, since: since)
        }
        return parseJSONDocument(path: path, since: since)
    }

    private func parseJSONL(path: String, since: Date) -> [LocalUsageEvent] {
        var eventsByID: [String: LocalUsageEvent] = [:]
        var fallbackIndex = 0
        CodexLocalUsageJSONLScanner.scanLines(atPath: path) { line in
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            let type = LocalUsageJSONParsing.stringValue(root["type"])?.lowercased()
            if type == "session_metadata" || type == "$set" {
                return
            }
            guard let event = Self.event(
                from: root,
                fallbackID: "\(path)|\(fallbackIndex)",
                since: since
            ) else {
                return
            }
            fallbackIndex += 1
            eventsByID[event.signature] = event
        }
        return Array(eventsByID.values)
    }

    private func parseJSONDocument(path: String, since: Date) -> [LocalUsageEvent] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let messages = (root["messages"] as? [[String: Any]]) ?? []
        return messages.enumerated().compactMap { index, message in
            Self.event(from: message, fallbackID: "\(path)|\(index)", since: since)
        }
    }

    private static func event(
        from root: [String: Any],
        fallbackID: String,
        since: Date
    ) -> LocalUsageEvent? {
        let tokens = (root["tokens"] as? [String: Any])
            ?? ((root["usage"] as? [String: Any]))
        guard let tokens else { return nil }

        let cached = LocalUsageJSONParsing.firstInt(
            in: tokens,
            keys: ["cached", "cached_tokens", "cache_read_input_tokens"]
        ) ?? 0
        let rawInput = LocalUsageJSONParsing.firstInt(
            in: tokens,
            keys: ["input", "input_tokens", "prompt_tokens"]
        ) ?? 0
        let input = rawInput >= cached ? rawInput - cached : rawInput
        let output = (LocalUsageJSONParsing.firstInt(in: tokens, keys: ["output", "output_tokens"]) ?? 0)
            + (LocalUsageJSONParsing.firstInt(in: tokens, keys: ["thoughts", "reasoning_tokens"]) ?? 0)
            + (LocalUsageJSONParsing.firstInt(in: tokens, keys: ["tool", "tool_tokens"]) ?? 0)
        let total = input + output + cached
        guard total > 0 else { return nil }

        let eventAt = LocalUsageJSONParsing.parseTimestamp(root["timestamp"])
            ?? LocalUsageJSONParsing.parseTimestamp(root["startTime"])
        guard let eventAt, eventAt >= since else { return nil }

        let modelID = LocalUsageJSONParsing.stringValue(root["model"]) ?? "gemini"
        let messageID = LocalUsageJSONParsing.stringValue(root["id"]) ?? fallbackID
        return LocalUsageEvent(
            signature: "gemini|\(messageID)",
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: total,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cached
        )
    }
}
