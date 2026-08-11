import Foundation

/// Provider-side port for sqlite3 shell queries.
public protocol SQLiteQuerying: Sendable {
    func rows(databasePath: String, query: String, separator: String) -> [[String]]
    func query(databasePath: String, query: String, separator: String) -> SQLiteShell.QueryResult
    func snapshotQuery(databasePath: String, query: String, separator: String) -> SQLiteShell.QueryResult
    func execute(databasePath: String, sql: String) -> Bool
}

public extension SQLiteQuerying {
    func rows(databasePath: String, query: String) -> [[String]] {
        rows(databasePath: databasePath, query: query, separator: "\t")
    }

    func query(databasePath: String, query sql: String) -> SQLiteShell.QueryResult {
        self.query(databasePath: databasePath, query: sql, separator: "\t")
    }

    func snapshotQuery(databasePath: String, query sql: String) -> SQLiteShell.QueryResult {
        self.snapshotQuery(databasePath: databasePath, query: sql, separator: "\t")
    }
}
