import Foundation
import OhMyUsageProviders

struct CursorSessionCredentials: Sendable {
    enum Source: String, Sendable {
        case grokBotApp
        case cursorIDE

        var authSourceLabel: String {
            switch self {
            case .grokBotApp:
                return "Grok Bot"
            case .cursorIDE:
                return "Cursor"
            }
        }
    }

    var accessToken: String
    var refreshToken: String?
    var email: String?
    var membershipType: String?
    var source: Source
    var databasePath: String?
}

struct CursorSessionAuth {
    static let oauthClientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    static let refreshURL = URL(string: "https://api2.cursor.sh/oauth/token")!

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

    let session: URLSession
    let sqlite: any SQLiteQuerying
    let stateDatabasePath: String
    let grokBotStore: GrokBotDesktopCredentialStore?

    init(
        session: URLSession,
        sqlite: any SQLiteQuerying,
        stateDatabasePath: String,
        grokBotStore: GrokBotDesktopCredentialStore? = nil
    ) {
        self.session = session
        self.sqlite = sqlite
        self.stateDatabasePath = stateDatabasePath
        self.grokBotStore = grokBotStore
    }

    static func defaultIDEStateDatabasePath(homeDirectory: String = NSHomeDirectory()) -> String {
        homeDirectory + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    static func workosCookieHeader(accessToken: String) -> String {
        let subject = JWTInspector.subject(accessToken) ?? ""
        let userId = subject.components(separatedBy: "|").last ?? subject
        let encodedToken = "\(userId)::\(accessToken)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? "\(userId)::\(accessToken)"
        return "WorkosCursorSessionToken=\(encodedToken)"
    }

    func loadIDE() throws -> CursorSessionCredentials {
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

        return CursorSessionCredentials(
            accessToken: accessToken,
            refreshToken: Self.normalizedOptionalValue(values["cursorAuth/refreshToken"]),
            email: Self.normalizedOptionalValue(values["cursorAuth/cachedEmail"]),
            membershipType: Self.normalizedOptionalValue(values["cursorAuth/stripeMembershipType"]),
            source: .cursorIDE,
            databasePath: dbPath
        )
    }

    /// Prefers the Grok Bot desktop login, then falls back to the Cursor IDE session.
    func loadForGrokBot() throws -> CursorSessionCredentials {
        var grokBotError: Error?
        if let grokBotStore {
            do {
                return try grokBotStore.load()
            } catch {
                grokBotError = error
            }
        }
        do {
            return try loadIDE()
        } catch {
            if let grokBotError {
                throw grokBotError
            }
            throw error
        }
    }

    func refresh(_ credentials: CursorSessionCredentials) async throws -> CursorSessionCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw ProviderError.unauthorized
        }
        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Self.oauthClientID,
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

        var updated = credentials
        updated.accessToken = accessToken
        if credentials.source == .cursorIDE, let databasePath = credentials.databasePath {
            _ = sqlite.execute(
                databasePath: databasePath,
                sql: "UPDATE ItemTable SET value = '\(accessToken.replacingOccurrences(of: "'", with: "''"))' WHERE key = 'cursorAuth/accessToken';"
            )
        }
        return updated
    }

    static func needsRefresh(accessToken: String, now: Date = Date()) -> Bool {
        JWTInspector.expirationDate(accessToken).map { $0 <= now } ?? false
    }

    static func displayPlanName(grokPlanLabel: String?, membershipType: String?) -> String {
        if let grokPlanLabel = OfficialValueParser.planLabel(grokPlanLabel) {
            return grokPlanLabel
        }
        guard let membership = OfficialValueParser.planLabel(membershipType) else {
            return "unknown"
        }
        switch membership.lowercased() {
        case "pro":
            return "Cursor Pro"
        case "pro_plus", "proplus", "pro+":
            return "Cursor Pro+"
        case "ultra":
            return "Cursor Ultra"
        case "free", "hobby":
            return "Cursor Free"
        case "team", "teams":
            return "Cursor Teams"
        case "enterprise":
            return "Cursor Enterprise"
        default:
            if membership.lowercased().contains("grok") || membership.lowercased().contains("cursor") {
                return membership
            }
            return "Cursor \(membership)"
        }
    }

    private static func normalizedOptionalValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
