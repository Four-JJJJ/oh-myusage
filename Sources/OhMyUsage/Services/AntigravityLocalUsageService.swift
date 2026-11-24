import Foundation
import OhMyUsageApplication

struct AntigravityRollingWindowSummary: Equatable, Sendable {
    var fiveHourTokens: Int
    var fiveHourRequests: Int
    var fiveHourOldestEventAt: Date?
    var sevenDayTokens: Int
    var sevenDayRequests: Int
    var latestModelID: String?
    var latestEventAt: Date?
}

final class AntigravityLocalUsageService {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let brainRootPaths: [String]
    private let installationMarkerPaths: [String]

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        brainRootPaths: [String]? = nil,
        homeDirectory: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        let resolvedRoots = brainRootPaths ?? Self.resolvedBrainRoots(
            homeDirectory: homeDirectory,
            environment: environment
        )
        self.brainRootPaths = resolvedRoots
        self.installationMarkerPaths = Self.resolvedInstallationMarkers(
            homeDirectory: homeDirectory,
            environment: environment,
            brainRoots: resolvedRoots
        )
    }

    static func resolvedGeminiRoot(
        homeDirectory: String,
        environment: [String: String]
    ) -> String {
        if let customHome = environment["GEMINI_CLI_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customHome.isEmpty {
            let expanded = (customHome as NSString).expandingTildeInPath
            let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            if standardized.hasSuffix("/.gemini") {
                return standardized
            }
            let nested = URL(fileURLWithPath: standardized, isDirectory: true)
                .appendingPathComponent(".gemini", isDirectory: true)
                .path
            if FileManager.default.fileExists(atPath: nested) {
                return nested
            }
            return standardized
        }
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".gemini", isDirectory: true)
            .path
    }

    static func resolvedBrainRoots(
        homeDirectory: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        let geminiRoot = resolvedGeminiRoot(homeDirectory: homeDirectory, environment: environment)
        return [
            "\(geminiRoot)/antigravity/brain",
            "\(geminiRoot)/antigravity-ide/brain",
            "\(geminiRoot)/antigravity-cli/brain"
        ]
    }

    private static func resolvedInstallationMarkers(
        homeDirectory: String,
        environment: [String: String],
        brainRoots: [String]
    ) -> [String] {
        let geminiRoot = resolvedGeminiRoot(homeDirectory: homeDirectory, environment: environment)
        var paths = brainRoots
        paths.append("\(geminiRoot)/antigravity")
        paths.append("\(geminiRoot)/antigravity-cli")
        paths.append("\(geminiRoot)/antigravity-ide")
        paths.append("/Applications/Antigravity.app")
        paths.append("\(homeDirectory)/Applications/Antigravity.app")
        return paths
    }

    func hasRecognizedInstallation() -> Bool {
        for path in installationMarkerPaths where fileManager.fileExists(atPath: path) {
            return true
        }
        return false
    }

    static func transcriptFileURLs(
        in brainRoots: [String],
        cutoff: Date? = nil,
        fileManager: FileManager = .default
    ) -> [URL] {
        var seen: Set<String> = []
        var output: [URL] = []

        for rawRoot in brainRoots {
            let rootPath = URL(fileURLWithPath: (rawRoot as NSString).expandingTildeInPath)
                .standardizedFileURL
                .path
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let conversationNames = try? fileManager.contentsOfDirectory(atPath: rootPath) else {
                continue
            }
            for name in conversationNames.sorted() where !name.hasPrefix(".") {
                let transcriptURL = URL(fileURLWithPath: rootPath, isDirectory: true)
                    .appendingPathComponent(name, isDirectory: true)
                    .appendingPathComponent(".system_generated/logs/transcript.jsonl", isDirectory: false)
                    .standardizedFileURL
                guard seen.insert(transcriptURL.path).inserted else { continue }
                guard let values = try? transcriptURL.resourceValues(
                    forKeys: [.isRegularFileKey, .contentModificationDateKey]
                ),
                      values.isRegularFile == true else {
                    continue
                }
                if let cutoff,
                   let modifiedAt = values.contentModificationDate,
                   modifiedAt < cutoff {
                    continue
                }
                output.append(transcriptURL)
            }
        }
        return output
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
            sourcePath: brainRootPaths.first ?? "\(NSHomeDirectory())/.gemini/antigravity/brain"
        )
    }

    func fetchRollingWindowSummary(now overrideNow: Date? = nil) throws -> AntigravityRollingWindowSummary {
        let now = overrideNow ?? nowProvider()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
        let events = try fetchEvents(since: sevenDaysAgo)

        var fiveHourTokens = 0
        var fiveHourRequests = 0
        var fiveHourOldest: Date?
        var sevenDayTokens = 0
        var sevenDayRequests = 0
        var latestEvent: LocalUsageEvent?

        for event in events where event.eventAt <= now.addingTimeInterval(60) {
            if event.eventAt >= sevenDaysAgo {
                sevenDayTokens += event.totalTokens
                sevenDayRequests += 1
            }
            if event.eventAt >= fiveHoursAgo {
                fiveHourTokens += event.totalTokens
                fiveHourRequests += 1
                if let currentOldest = fiveHourOldest {
                    if event.eventAt < currentOldest {
                        fiveHourOldest = event.eventAt
                    }
                } else {
                    fiveHourOldest = event.eventAt
                }
            }
            if let currentLatest = latestEvent {
                if event.eventAt >= currentLatest.eventAt {
                    latestEvent = event
                }
            } else {
                latestEvent = event
            }
        }

        return AntigravityRollingWindowSummary(
            fiveHourTokens: fiveHourTokens,
            fiveHourRequests: fiveHourRequests,
            fiveHourOldestEventAt: fiveHourOldest,
            sevenDayTokens: sevenDayTokens,
            sevenDayRequests: sevenDayRequests,
            latestModelID: latestEvent?.modelID,
            latestEventAt: latestEvent?.eventAt
        )
    }

    func fetchEvents(since: Date) throws -> [LocalUsageEvent] {
        let cutoff = calendar.date(byAdding: .day, value: -1, to: since) ?? since
        let files = Self.transcriptFileURLs(
            in: brainRootPaths,
            cutoff: cutoff,
            fileManager: fileManager
        )
        var eventsBySignature: [String: LocalUsageEvent] = [:]
        for fileURL in files {
            if Task.isCancelled { break }
            let conversationID = Self.conversationID(forTranscriptURL: fileURL)
            for event in parseTranscriptFile(path: fileURL.path, conversationID: conversationID, since: since) {
                eventsBySignature[event.signature] = event
            }
        }
        return Array(eventsBySignature.values)
    }

    private static func conversationID(forTranscriptURL url: URL) -> String {
        // .../<conversation-id>/.system_generated/logs/transcript.jsonl
        let conversationURL = url
            .deletingLastPathComponent() // logs
            .deletingLastPathComponent() // .system_generated
            .deletingLastPathComponent() // <conversation-id>
        let name = conversationURL.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private func parseTranscriptFile(
        path: String,
        conversationID: String,
        since: Date
    ) -> [LocalUsageEvent] {
        var eventsByID: [String: LocalUsageEvent] = [:]
        var lineIndex = 0
        Self.scanJSONLLines(atPath: path) { line in
            defer { lineIndex += 1 }
            guard line.contains("tokens") else { return }
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            guard let event = Self.event(
                from: root,
                conversationID: conversationID,
                fallbackIndex: lineIndex,
                since: since
            ) else {
                return
            }
            eventsByID[event.signature] = event
        }
        return Array(eventsByID.values)
    }

    private static func scanJSONLLines(
        atPath path: String,
        maxLineBytes: Int = RuntimeDiagnosticsLimits.jsonlMaxLineBytes,
        onLine: (String) -> Void
    ) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }

        let newline = Data([0x0A])
        var buffer = Data()
        var droppingOversizedLine = false

        while !Task.isCancelled {
            let chunk = try? handle.read(upToCount: 64 * 1024)
            guard let chunk, !chunk.isEmpty else {
                if !droppingOversizedLine,
                   !buffer.isEmpty,
                   buffer.count <= maxLineBytes,
                   let line = String(data: buffer, encoding: .utf8) {
                    onLine(line)
                }
                break
            }

            var slice = chunk[...]
            while let range = slice.range(of: newline) {
                let prefix = slice[..<range.lowerBound]
                if droppingOversizedLine {
                    droppingOversizedLine = false
                    buffer.removeAll(keepingCapacity: true)
                } else if buffer.count + prefix.count <= maxLineBytes {
                    buffer.append(contentsOf: prefix)
                    if let line = String(data: buffer, encoding: .utf8) {
                        onLine(line)
                    }
                    buffer.removeAll(keepingCapacity: true)
                } else {
                    buffer.removeAll(keepingCapacity: true)
                }
                slice = slice[range.upperBound...]
            }

            if !slice.isEmpty && !droppingOversizedLine {
                if buffer.count + slice.count > maxLineBytes {
                    buffer.removeAll(keepingCapacity: true)
                    droppingOversizedLine = true
                } else {
                    buffer.append(contentsOf: slice)
                }
            }
        }
    }

    internal static func event(
        from root: [String: Any],
        conversationID: String,
        fallbackIndex: Int,
        since: Date
    ) -> LocalUsageEvent? {
        if let eventKind = LocalUsageJSONParsing.stringValue(root["event"])?.lowercased(),
           eventKind == "result" {
            // Headless stream `result` envelopes contain cumulative session totals;
            // per-step `step_update` / `PLANNER_RESPONSE` rows already carry each turn.
            return nil
        }

        let stepUpdate = root["step_update"] as? [String: Any]
        if let state = LocalUsageJSONParsing.stringValue(stepUpdate?["state"] ?? root["status"])?.uppercased(),
           state == "ACTIVE" || state == "RUNNING" {
            return nil
        }

        let usageSource = (root["usage"] as? [String: Any])
            ?? (stepUpdate?["usage"] as? [String: Any])
            ?? root

        let input = LocalUsageJSONParsing.firstInt(
            in: usageSource,
            keys: ["input_tokens", "inputTokens"]
        ) ?? 0
        let cached = LocalUsageJSONParsing.firstInt(
            in: usageSource,
            keys: ["cache_read_tokens", "cacheReadTokens", "cached_tokens"]
        ) ?? 0
        let cacheWrite = LocalUsageJSONParsing.firstInt(
            in: usageSource,
            keys: ["cache_write_tokens", "cacheWriteTokens", "cache_creation_input_tokens"]
        ) ?? 0
        let rawOutput = LocalUsageJSONParsing.firstInt(
            in: usageSource,
            keys: ["output_tokens", "outputTokens"]
        ) ?? 0
        let thinking = LocalUsageJSONParsing.firstInt(
            in: usageSource,
            keys: ["thinking_tokens", "thinkingTokens", "reasoning_tokens"]
        ) ?? 0
        // In headless stream-json, `output_tokens` already includes `thinking_tokens` when
        // `total_tokens == input_tokens + output_tokens`; in transcript.jsonl `thinking_tokens`
        // is omitted (`output_tokens` is total output). Guard against double-counting.
        let reportedTotal = LocalUsageJSONParsing.firstInt(
            in: usageSource,
            keys: ["total_tokens", "totalTokens"]
        )
        let output: Int
        if let reportedTotal, reportedTotal == input + rawOutput {
            output = rawOutput
        } else if thinking > 0, rawOutput < thinking {
            output = rawOutput + thinking
        } else {
            output = rawOutput
        }

        let total = input + output + cached + cacheWrite
        guard total > 0 else { return nil }

        let eventAt = LocalUsageJSONParsing.parseTimestamp(root["created_at"])
            ?? LocalUsageJSONParsing.parseTimestamp(root["timestamp"])
            ?? LocalUsageJSONParsing.parseTimestamp(stepUpdate?["created_at"])
        guard let eventAt, eventAt >= since else { return nil }

        let modelID = LocalUsageJSONParsing.stringValue(root["model"])
            ?? LocalUsageJSONParsing.stringValue(stepUpdate?["model"])
            ?? "antigravity"
        let stepKey: String
        if let stepIndex = LocalUsageJSONParsing.firstInt(
            in: stepUpdate ?? root,
            keys: ["step_index", "stepIndex"]
        ) {
            stepKey = "step-\(stepIndex)"
        } else if let id = LocalUsageJSONParsing.stringValue(root["id"]) {
            stepKey = id
        } else {
            stepKey = "line-\(fallbackIndex)"
        }

        return LocalUsageEvent(
            signature: "antigravity|\(conversationID)|\(stepKey)",
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: total,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cached,
            cacheWriteTokens: cacheWrite
        )
    }
}
