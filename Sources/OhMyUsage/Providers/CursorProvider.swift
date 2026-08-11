import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class CursorProvider: UsageProvider, @unchecked Sendable {
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

    private let session: URLSession
    private let sqlite: any SQLiteQuerying
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        sqlite: any SQLiteQuerying = DefaultSQLiteShell()
    ) {
        self.descriptor = descriptor
        self.session = session
        self.sqlite = sqlite
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .cursor)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Cursor 官方来源当前仅支持 API 检测")
        }

        let result = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
            initialState: try loadAuth(),
            shouldRefresh: { auth in
                JWTInspector.expirationDate(auth.accessToken).map { $0 <= Date() } ?? false
            },
            request: { auth in
                try await self.requestSnapshot(auth: auth)
            },
            refresh: { auth in
                try await self.refresh(auth: auth)
            }
        )
        return result.response
    }

    private func requestSnapshot(auth: CursorAuth) async throws -> UsageSnapshot {
        let subject = JWTInspector.subject(auth.accessToken) ?? ""
        let userId = subject.components(separatedBy: "|").last ?? subject
        let encodedToken = "\(userId)::\(auth.accessToken)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "\(userId)::\(auth.accessToken)"

        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("WorkosCursorSessionToken=\(encodedToken)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Cursor non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Cursor http \(http.statusCode)")
        }

        return try Self.parseSnapshot(
            data: data,
            descriptor: descriptor,
            accountLabel: auth.email
        )
    }

    private func loadAuth() throws -> CursorAuth {
        let dbPath = "\(NSHomeDirectory())/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
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

        let refreshToken = Self.normalizedOptionalValue(values["cursorAuth/refreshToken"])
        let email = Self.normalizedOptionalValue(values["cursorAuth/cachedEmail"])
        let membershipType = Self.normalizedOptionalValue(values["cursorAuth/stripeMembershipType"])

        return CursorAuth(
            databasePath: dbPath,
            accessToken: accessToken,
            refreshToken: refreshToken,
            email: email,
            membershipType: membershipType
        )
    }

    private func refresh(auth: CursorAuth) async throws -> CursorAuth {
        guard let refreshToken = auth.refreshToken, !refreshToken.isEmpty else {
            throw ProviderError.unauthorized
        }
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB",
            "refresh_token": refreshToken,
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Cursor refresh invalid response")
        }
        if http.statusCode == 400 || http.statusCode == 401 {
            throw ProviderError.unauthorized
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

    internal static func parseSnapshot(data: Data, descriptor: ProviderDescriptor, accountLabel: String?) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Cursor usage decode failed")
        }
        let membership = OfficialValueParser.string(root["membershipType"]) ?? "unknown"
        let resetAt = OfficialValueParser.isoDate(OfficialValueParser.string(root["billingCycleEnd"]))
        let individual = root["individualUsage"] as? [String: Any]

        var windows: [UsageQuotaWindow] = []
        if let plan = individual?["plan"] as? [String: Any],
           (plan["enabled"] as? Bool) == true {
            let autoPercentUsed = OfficialValueParser.double(plan["autoPercentUsed"])
            let apiPercentUsed = OfficialValueParser.double(plan["apiPercentUsed"])

            // Cursor dashboard now tracks two included pools:
            // autoPercentUsed → Cursor Models (Grok / Composer)
            // apiPercentUsed → Other Models (third-party API)
            if autoPercentUsed != nil || apiPercentUsed != nil {
                if let autoPercentUsed {
                    windows.append(
                        percentWindow(
                            id: "\(descriptor.id)-cursor-models",
                            title: "Cursor Models",
                            usedPercent: autoPercentUsed,
                            resetAt: resetAt
                        )
                    )
                }
                if let apiPercentUsed {
                    windows.append(
                        percentWindow(
                            id: "\(descriptor.id)-other-models",
                            title: "Other Models",
                            usedPercent: apiPercentUsed,
                            resetAt: resetAt
                        )
                    )
                }
            } else {
                let used = OfficialValueParser.double(plan["used"]) ?? 0
                let limit = OfficialValueParser.double(plan["limit"] ?? (plan["breakdown"] as? [String: Any])?["total"]) ?? 0
                if limit > 0 {
                    let remainingPercent = max(0, (limit - used) / limit * 100)
                    windows.append(
                        UsageQuotaWindow(
                            id: "\(descriptor.id)-monthly",
                            title: "Monthly",
                            remainingPercent: remainingPercent,
                            usedPercent: max(0, 100 - remainingPercent),
                            resetAt: resetAt,
                            kind: .custom
                        )
                    )
                }
            }
        }
        if let onDemand = individual?["onDemand"] as? [String: Any],
           (onDemand["enabled"] as? Bool) == true,
           let used = OfficialValueParser.double(onDemand["used"]),
           let limit = OfficialValueParser.double(onDemand["limit"]), limit > 0 {
            let remainingPercent = max(0, (limit - used) / limit * 100)
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-ondemand",
                    title: "On-Demand",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: resetAt,
                    kind: .custom
                )
            )
        }
        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("missing Cursor quota windows")
        }
        let remaining = windows.map(\.remainingPercent).min() ?? 0
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Plan \(membership) | " + windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: accountLabel,
            extras: ["planType": membership],
            rawMeta: [:]
        )
    }

    private static func percentWindow(
        id: String,
        title: String,
        usedPercent: Double,
        resetAt: Date?
    ) -> UsageQuotaWindow {
        let clampedUsed = min(100, max(0, usedPercent))
        return UsageQuotaWindow(
            id: id,
            title: title,
            remainingPercent: max(0, 100 - clampedUsed),
            usedPercent: clampedUsed,
            resetAt: resetAt,
            kind: .custom
        )
    }

    private static func normalizedOptionalValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CursorAuth {
    var databasePath: String
    var accessToken: String
    var refreshToken: String?
    var email: String?
    var membershipType: String?
}
