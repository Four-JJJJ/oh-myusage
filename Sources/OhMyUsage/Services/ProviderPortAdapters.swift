import Foundation
import OhMyUsageInfrastructure
import OhMyUsageProviders

extension KeychainService: TokenCredentialStoring {}

/// Providers keep depending on the `TokenCredentialStoring` port; the shared broker
/// satisfies it (and the Infrastructure `CredentialStoring` port) via these adapters.
extension CredentialBroker: TokenCredentialStoring {}
extension CredentialBroker: CredentialStoring {}

extension KimiBrowserCookieService: KimiBrowserCookieDetecting {}

extension BrowserCredentialService: BrowserCredentialProviding {}

struct DefaultShellCommandRunner: ShellCommandRunning {
    func run(
        executable: String,
        arguments: [String],
        input: String?,
        timeout: TimeInterval,
        environment: [String: String]?,
        currentDirectory: String?
    ) -> (status: Int32, stdout: String, stderr: String)? {
        ShellCommand.run(
            executable: executable,
            arguments: arguments,
            input: input,
            timeout: timeout,
            environment: environment,
            currentDirectory: currentDirectory
        )
    }
}

struct DefaultLocalJSONFileReader: LocalJSONFileReading {
    func dictionary(atPath path: String) -> [String: Any]? {
        LocalJSONFileReader.dictionary(atPath: path)
    }

    func text(atPath path: String) -> String? {
        LocalJSONFileReader.text(atPath: path)
    }
}

struct DefaultSQLiteShell: SQLiteQuerying {
    func rows(databasePath: String, query: String, separator: String) -> [[String]] {
        SQLiteShell.rows(databasePath: databasePath, query: query, separator: separator)
    }

    func query(databasePath: String, query: String, separator: String) -> SQLiteShell.QueryResult {
        SQLiteShell.query(databasePath: databasePath, query: query, separator: separator)
    }

    func snapshotQuery(databasePath: String, query: String, separator: String) -> SQLiteShell.QueryResult {
        SQLiteShell.snapshotQuery(databasePath: databasePath, query: query, separator: separator)
    }

    func execute(databasePath: String, sql: String) -> Bool {
        SQLiteShell.execute(databasePath: databasePath, sql: sql)
    }
}
