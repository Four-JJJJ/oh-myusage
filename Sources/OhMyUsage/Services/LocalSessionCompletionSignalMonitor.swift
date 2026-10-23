import Foundation
import OhMyUsageApplication
import SQLite3

struct LocalSessionCompletionSignalDiagnostics: Equatable, Sendable {
    var codexSQLiteProbeCount = 0
    var codexCacheHitCount = 0
    var claudeEnumerationCount = 0
    var claudeThrottleHitCount = 0
    var lastClaudeCandidateFileCount = 0
    var lastClaudeTrackedFileCount = 0
    var lastClaudeParsedFileCount = 0
    var lastClaudeCachedFileSkipCount = 0

    mutating func resetClaudeLastScan() {
        lastClaudeCandidateFileCount = 0
        lastClaudeTrackedFileCount = 0
        lastClaudeParsedFileCount = 0
        lastClaudeCachedFileSkipCount = 0
    }
}

/// Watches local Codex/Claude session activity for freshly completed turns.
/// Scans perform synchronous file and SQLite IO (stat, per-scan connections,
/// directory enumeration, JSONL parsing), so this is an actor: probes run
/// serialized on a background executor and never block the main thread. Each
/// scan opens and closes its own SQLite connection, and actor serialization
/// guarantees a connection is never shared across concurrent threads.
actor LocalSessionCompletionSignalMonitor: LocalSessionCompletionSignalSource {
    private struct ClaudeFileState {
        var modifiedAtRef: TimeInterval
        var fileSize: UInt64
        var latestSignalAt: Date?
    }

    private struct ClaudeCandidateFile {
        var path: String
        var modifiedAtRef: TimeInterval
        var fileSize: UInt64
    }

    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private let codexLogsPath: String
    private let claudeProjectsRoot: String
    private let claudeRecentFileWindow: TimeInterval
    private let claudeEnumerationInterval: TimeInterval
    private let claudeMaxTrackedFiles: Int
    private var claudeFileStates: [String: ClaudeFileState] = [:]
    private var lastCodexLogsSnapshot: [LocalUsageFileSnapshot]?
    private var cachedCodexLatestCompletionAt: Date?
    private var lastClaudeEnumerationAt: Date?
    private var cachedClaudeLatestCompletionAt: Date?
    private(set) var diagnostics = LocalSessionCompletionSignalDiagnostics()

    init(
        fileManager: FileManager = .default,
        codexLogsPath: String? = nil,
        claudeProjectsRoot: String? = nil,
        claudeRecentFileWindow: TimeInterval = 3 * 24 * 60 * 60,
        claudeEnumerationInterval: TimeInterval = 60,
        claudeMaxTrackedFiles: Int = RuntimeDiagnosticsLimits.claudeSignalMaxTrackedFiles,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.codexLogsPath = codexLogsPath ?? "\(NSHomeDirectory())/.codex/logs_2.sqlite"
        self.claudeProjectsRoot = claudeProjectsRoot ?? "\(NSHomeDirectory())/.claude/projects"
        self.claudeRecentFileWindow = max(60, claudeRecentFileWindow)
        self.claudeEnumerationInterval = max(5, claudeEnumerationInterval)
        self.claudeMaxTrackedFiles = max(1, claudeMaxTrackedFiles)
    }

    func latestCodexCompletionAt() -> Date? {
        guard let fileSnapshot = codexLogSnapshots() else {
            lastCodexLogsSnapshot = nil
            cachedCodexLatestCompletionAt = nil
            return nil
        }
        if fileSnapshot == lastCodexLogsSnapshot {
            diagnostics.codexCacheHitCount += 1
            return cachedCodexLatestCompletionAt
        }
        lastCodexLogsSnapshot = fileSnapshot
        diagnostics.codexSQLiteProbeCount += 1

        let query = """
        SELECT ts
        FROM logs
        WHERE ts IS NOT NULL
          AND feedback_log_body IS NOT NULL
          AND (
            ltrim(feedback_log_body) LIKE 'event.name=codex.sse_event%'
            OR ltrim(feedback_log_body) LIKE 'event.name="codex.sse_event"%'
          )
          AND (
            feedback_log_body LIKE '%event.kind=response.completed%'
            OR feedback_log_body LIKE '%event.kind="response.completed"%'
          )
        ORDER BY ts DESC
        LIMIT 1;
        """

        var database: OpaquePointer?
        guard sqlite3_open_v2(codexLogsPath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            lastCodexLogsSnapshot = nil
            return cachedCodexLatestCompletionAt
        }
        defer {
            sqlite3_close(database)
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            lastCodexLogsSnapshot = nil
            return cachedCodexLatestCompletionAt
        }
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            cachedCodexLatestCompletionAt = nil
            return nil
        }

        if let raw = Self.sqliteColumnText(statement, index: 0),
           let parsed = Self.parseTimestampDate(raw) {
            cachedCodexLatestCompletionAt = parsed
            return parsed
        }

        let fallback = sqlite3_column_double(statement, 0)
        guard fallback.isFinite, fallback > 0 else {
            cachedCodexLatestCompletionAt = nil
            return nil
        }
        let parsed = Self.parseEpochTimestamp(fallback)
        cachedCodexLatestCompletionAt = parsed
        return parsed
    }

    private func codexLogSnapshots() -> [LocalUsageFileSnapshot]? {
        guard fileManager.fileExists(atPath: codexLogsPath),
              let primary = fileSnapshot(path: codexLogsPath) else {
            return nil
        }

        let sidecars = ["\(codexLogsPath)-wal", "\(codexLogsPath)-shm"]
            .compactMap { fileSnapshot(path: $0) }
        return ([primary] + sidecars).sorted { $0.path < $1.path }
    }

    private func fileSnapshot(path: String) -> LocalUsageFileSnapshot? {
        guard fileManager.fileExists(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        return LocalUsageFileSnapshot(
            path: path,
            fileSize: UInt64(max(0, values.fileSize ?? 0)),
            modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate
        )
    }

    func latestClaudeCompletionAt() -> Date? {
        guard fileManager.fileExists(atPath: claudeProjectsRoot) else {
            claudeFileStates.removeAll()
            lastClaudeEnumerationAt = nil
            cachedClaudeLatestCompletionAt = nil
            diagnostics.resetClaudeLastScan()
            return nil
        }

        let now = nowProvider()
        if let lastClaudeEnumerationAt,
           now.timeIntervalSince(lastClaudeEnumerationAt) < claudeEnumerationInterval {
            diagnostics.claudeThrottleHitCount += 1
            return cachedClaudeLatestCompletionAt
        }
        lastClaudeEnumerationAt = now
        diagnostics.claudeEnumerationCount += 1

        let cutoff = nowProvider().addingTimeInterval(-claudeRecentFileWindow)
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: claudeProjectsRoot, isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            diagnostics.resetClaudeLastScan()
            return cachedClaudeLatestCompletionAt
        }

        var candidateFileCount = 0
        var trackedCandidates: [ClaudeCandidateFile] = []
        trackedCandidates.reserveCapacity(claudeMaxTrackedFiles)

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "jsonl" else {
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff else {
                continue
            }

            let path = fileURL.path
            candidateFileCount += 1
            insertTrackedClaudeCandidate(
                ClaudeCandidateFile(
                    path: path,
                    modifiedAtRef: modifiedAt.timeIntervalSinceReferenceDate,
                    fileSize: UInt64(max(0, values.fileSize ?? 0))
                ),
                into: &trackedCandidates
            )
        }

        diagnostics.lastClaudeCandidateFileCount = candidateFileCount
        diagnostics.lastClaudeTrackedFileCount = trackedCandidates.count
        diagnostics.lastClaudeParsedFileCount = 0
        diagnostics.lastClaudeCachedFileSkipCount = 0
        let visiblePaths = Set(trackedCandidates.map(\.path))

        for candidate in trackedCandidates {
            if let cached = claudeFileStates[candidate.path],
               cached.modifiedAtRef == candidate.modifiedAtRef,
               cached.fileSize == candidate.fileSize {
                diagnostics.lastClaudeCachedFileSkipCount += 1
                continue
            }
            diagnostics.lastClaudeParsedFileCount += 1
            let parsed = Self.latestClaudeAssistantUsageTimestamp(filePath: candidate.path)
            claudeFileStates[candidate.path] = ClaudeFileState(
                modifiedAtRef: candidate.modifiedAtRef,
                fileSize: candidate.fileSize,
                latestSignalAt: parsed
            )
        }

        claudeFileStates = claudeFileStates.filter { visiblePaths.contains($0.key) }
        cachedClaudeLatestCompletionAt = claudeFileStates.values.reduce(nil) { partial, state in
            Self.maxDate(partial, state.latestSignalAt)
        }
        return cachedClaudeLatestCompletionAt
    }

    private func insertTrackedClaudeCandidate(
        _ candidate: ClaudeCandidateFile,
        into trackedCandidates: inout [ClaudeCandidateFile]
    ) {
        trackedCandidates.append(candidate)
        trackedCandidates.sort(by: Self.isNewerClaudeCandidate)
        if trackedCandidates.count > claudeMaxTrackedFiles {
            trackedCandidates.removeLast(trackedCandidates.count - claudeMaxTrackedFiles)
        }
    }

    private static func isNewerClaudeCandidate(
        _ lhs: ClaudeCandidateFile,
        than rhs: ClaudeCandidateFile
    ) -> Bool {
        if lhs.modifiedAtRef != rhs.modifiedAtRef {
            return lhs.modifiedAtRef > rhs.modifiedAtRef
        }
        return lhs.path < rhs.path
    }

    private static func latestClaudeAssistantUsageTimestamp(filePath: String) -> Date? {
        var latest: Date?

        scanJSONLLines(atPath: filePath) { line in
            guard line.contains("\"type\":\"assistant\""), line.contains("\"usage\"") else {
                return
            }
            guard let data = line.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  stringValue(root["type"]) == "assistant",
                  let message = root["message"] as? [String: Any],
                  message["usage"] as? [String: Any] != nil,
                  let timestamp = parseISODate(stringValue(root["timestamp"])) else {
                return
            }

            latest = maxDate(latest, timestamp)
        }

        return latest
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.none, .none):
            return nil
        case (.some(let lhs), .none):
            return lhs
        case (.none, .some(let rhs)):
            return rhs
        case (.some(let lhs), .some(let rhs)):
            return lhs >= rhs ? lhs : rhs
        }
    }

    private static func scanJSONLLines(
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

                guard !lineData.isEmpty,
                      lineData.count <= maxLineBytes,
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

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String {
            return trimmed(value)
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func parseISODate(_ raw: String?) -> Date? {
        guard let raw = trimmed(raw) else { return nil }
        if let date = isoFormatterWithFractional.date(from: raw) {
            return date
        }
        return isoFormatterBasic.date(from: raw)
    }

    nonisolated(unsafe) private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoFormatterBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseTimestampDate(_ raw: String) -> Date? {
        guard let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return parseEpochTimestamp(value)
    }

    private static func parseEpochTimestamp(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else {
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

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
