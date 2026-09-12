import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

struct CursorSessionAuth: Sendable {
    var databasePath: String
    var accessToken: String
    var refreshToken: String?
    var email: String?
    var membershipType: String?
}

/// Shared Cursor IDE session credentials from `state.vscdb`.
///
/// Used by `CursorProvider` and `GrokBotProvider` so both cards can refresh independently
/// while reading the same local login state. Credentials are never stored in Keychain.
struct CursorSessionAuthStore: Sendable {
    private static let authQuery = """
    SELECT key, value
    FROM ItemTable
    WHERE key IN (
        'cursorAuth/accessToken',
        'cursorAuth/refreshToken',
        'cursorAuth/cachedEmail',
        'cursorAuth/stripeMembershipType'
    );
    """

    private static let refreshClientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    private let session: URLSession
    private let sqlite: any SQLiteQuerying
    private let stateDatabasePath: String

    init(
        session: URLSession = .shared,
        sqlite: any SQLiteQuerying = DefaultSQLiteShell(),
        stateDatabasePath: String? = nil
    ) {
        self.session = session
        self.sqlite = sqlite
        self.stateDatabasePath = stateDatabasePath
            ?? "\(NSHomeDirectory())/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    func loadAuth() throws -> CursorSessionAuth {
        let dbPath = stateDatabasePath
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw ProviderError.missingCredential(dbPath)
        }

        let result = sqlite.snapshotQuery(databasePath: dbPath, query: Self.authQuery)
        guard result.succeeded else {
            throw ProviderError.commandFailed(
                "Failed to read Cursor state database at \(dbPath): \(result.errorMessage)"
            )
        }

        var values: [String: String] = [:]
        for row in result.rows where row.count >= 2 {
            let key = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value
        }

        guard let accessToken = values["cursorAuth/accessToken"], !accessToken.isEmpty else {
            throw ProviderError.missingCredential("cursorAuth/accessToken")
        }

        return CursorSessionAuth(
            databasePath: dbPath,
            accessToken: accessToken,
            refreshToken: Self.normalizedOptionalValue(values["cursorAuth/refreshToken"]),
            email: Self.normalizedOptionalValue(values["cursorAuth/cachedEmail"]),
            membershipType: Self.normalizedOptionalValue(values["cursorAuth/stripeMembershipType"])
        )
    }

    func refresh(auth: CursorSessionAuth) async throws -> CursorSessionAuth {
        guard let refreshToken = auth.refreshToken, !refreshToken.isEmpty else {
            throw ProviderError.unauthorized
        }
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Self.refreshClientID,
            "refresh_token": refreshToken,
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Cursor refresh invalid response")
        }
        if http.statusCode == 400 || http.statusCode == 401 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = OfficialValueParser.string(json["access_token"]) else {
            throw ProviderError.invalidResponse("Cursor refresh failed")
        }

        var updated = auth
        updated.accessToken = accessToken
        _ = sqlite.execute(
            databasePath: auth.databasePath,
            sql: "UPDATE ItemTable SET value = '\(accessToken.replacingOccurrences(of: "'", with: "''"))' WHERE key = 'cursorAuth/accessToken';"
        )
        return updated
    }

    func sessionCookieHeaderValue(accessToken: String) -> String {
        let subject = JWTInspector.subject(accessToken) ?? ""
        let userId = subject.components(separatedBy: "|").last ?? subject
        let rawToken = "\(userId)::\(accessToken)"
        let encoded = rawToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawToken
        return "WorkosCursorSessionToken=\(encoded)"
    }

    func shouldRefresh(accessToken: String) -> Bool {
        JWTInspector.expirationDate(accessToken).map { $0 <= Date() } ?? false
    }

    private static func normalizedOptionalValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
