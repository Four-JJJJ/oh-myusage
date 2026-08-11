import Foundation

public enum SQLiteShell {
    public enum ReadMode: Equatable {
        case direct
        case readOnlySnapshot
    }

    public struct QueryResult {
        public let databasePath: String
        public let executedPath: String
        public let mode: ReadMode
        public let status: Int32
        public let stdout: String
        public let stderr: String
        public let rows: [[String]]

        public init(
            databasePath: String,
            executedPath: String,
            mode: ReadMode,
            status: Int32,
            stdout: String,
            stderr: String,
            rows: [[String]]
        ) {
            self.databasePath = databasePath
            self.executedPath = executedPath
            self.mode = mode
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
            self.rows = rows
        }

        public var succeeded: Bool {
            status == 0
        }

        public var singleValue: String? {
            guard succeeded else { return nil }
            return rows.first?.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var errorMessage: String {
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
            return "sqlite3 exited with status \(status)"
        }
    }

    public static func rows(databasePath: String, query: String, separator: String = "\t") -> [[String]] {
        let result = Self.query(databasePath: databasePath, query: query, separator: separator)
        guard result.succeeded else {
            return []
        }
        return result.rows
    }

    public static func singleValue(databasePath: String, query: String) -> String? {
        Self.query(databasePath: databasePath, query: query, separator: "\t").singleValue
    }

    public static func query(databasePath: String, query: String, separator: String = "\t") -> QueryResult {
        performQuery(databasePath: databasePath, query: query, separator: separator, mode: .direct)
    }

    public static func snapshotQuery(databasePath: String, query: String, separator: String = "\t") -> QueryResult {
        performQuery(databasePath: databasePath, query: query, separator: separator, mode: .readOnlySnapshot)
    }

    @discardableResult
    public static func execute(databasePath: String, sql: String) -> Bool {
        guard FileManager.default.fileExists(atPath: databasePath),
              let result = ShellCommand.run(
                executable: "/usr/bin/sqlite3",
                arguments: [databasePath, sql],
                timeout: 10
              ) else {
            return false
        }
        return result.status == 0
    }

    private static func performQuery(
        databasePath: String,
        query: String,
        separator: String,
        mode: ReadMode
    ) -> QueryResult {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            return QueryResult(
                databasePath: databasePath,
                executedPath: databasePath,
                mode: mode,
                status: 1,
                stdout: "",
                stderr: "database file does not exist at \(databasePath)",
                rows: []
            )
        }

        switch mode {
        case .direct:
            return runQuery(databasePath: databasePath, executedPath: databasePath, query: query, separator: separator, mode: mode)
        case .readOnlySnapshot:
            do {
                let snapshot = try createSnapshot(for: databasePath)
                defer { try? FileManager.default.removeItem(atPath: snapshot.directoryPath) }
                return runQuery(
                    databasePath: databasePath,
                    executedPath: snapshot.databasePath,
                    query: query,
                    separator: separator,
                    mode: mode
                )
            } catch {
                return QueryResult(
                    databasePath: databasePath,
                    executedPath: databasePath,
                    mode: mode,
                    status: -1,
                    stdout: "",
                    stderr: "Failed to create sqlite snapshot for \(databasePath): \(error.localizedDescription)",
                    rows: []
                )
            }
        }
    }

    private static func runQuery(
        databasePath: String,
        executedPath: String,
        query: String,
        separator: String,
        mode: ReadMode
    ) -> QueryResult {
        guard let result = ShellCommand.run(
            executable: "/usr/bin/sqlite3",
            arguments: ["-separator", separator, executedPath, query],
            timeout: 10
        ) else {
            return QueryResult(
                databasePath: databasePath,
                executedPath: executedPath,
                mode: mode,
                status: -1,
                stdout: "",
                stderr: "sqlite3 command failed to start",
                rows: []
            )
        }

        let rows: [[String]]
        if result.status == 0 {
            rows = result.stdout
                .split(separator: "\n")
                .map { line in line.components(separatedBy: separator) }
        } else {
            rows = []
        }

        return QueryResult(
            databasePath: databasePath,
            executedPath: executedPath,
            mode: mode,
            status: result.status,
            stdout: result.stdout,
            stderr: result.stderr,
            rows: rows
        )
    }

    private struct SnapshotHandle {
        let directoryPath: String
        let databasePath: String
    }

    private static func createSnapshot(for databasePath: String) throws -> SnapshotHandle {
        let fileManager = FileManager.default
        let baseURL = URL(fileURLWithPath: databasePath)
        let snapshotDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sqlite_snapshot_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        let snapshotDatabaseURL = snapshotDirectory.appendingPathComponent(baseURL.lastPathComponent, isDirectory: false)
        try fileManager.copyItem(at: baseURL, to: snapshotDatabaseURL)

        for suffix in ["-wal", "-shm"] {
            let sourcePath = databasePath + suffix
            guard fileManager.fileExists(atPath: sourcePath) else { continue }
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let targetURL = URL(fileURLWithPath: snapshotDatabaseURL.path + suffix)
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }

        return SnapshotHandle(
            directoryPath: snapshotDirectory.path,
            databasePath: snapshotDatabaseURL.path
        )
    }
}
