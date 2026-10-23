import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

/// Grok Bot weekly usage provider.
///
/// Grok Bot is metered on the Cursor account. Cursor paid plans include a weekly
/// Bot grant; SuperGrok / X Premium+ can grant usage onto the same Cursor
/// account. Credentials prefer the Grok Bot desktop app, then the Cursor IDE.
final class GrokBotProvider: UsageProvider, @unchecked Sendable {
    private static let connectRPCBaseURL = "https://api2.cursor.sh/aiserver.v1.DashboardService"
    private static let restSandURL = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!
    private static let restUsageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    private static let noAllowanceMessage = "当前账号没有 Grok Bot 额度。请使用 Cursor 付费计划，或在 Grok Bot 中关联 SuperGrok。"

    let descriptor: ProviderDescriptor
    private let session: URLSession
    private let auth: CursorSessionAuth

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        sqlite: any SQLiteQuerying = DefaultSQLiteShell(),
        stateDatabasePath: String? = nil,
        grokBotStore: GrokBotDesktopCredentialStore? = .default()
    ) {
        self.descriptor = descriptor
        self.session = session
        self.auth = CursorSessionAuth(
            session: session,
            sqlite: sqlite,
            stateDatabasePath: stateDatabasePath ?? CursorSessionAuth.defaultIDEStateDatabasePath(),
            grokBotStore: grokBotStore
        )
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        _ = forceRefresh
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .grokBot)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Grok Bot 官方来源当前仅支持 API 检测")
        }

        let result = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
            initialState: try auth.loadForGrokBot(),
            shouldRefresh: { CursorSessionAuth.needsRefresh(accessToken: $0.accessToken) },
            request: { [self] credentials in
                try await requestSnapshot(credentials: credentials)
            },
            refresh: { [self] credentials in
                try await auth.refresh(credentials)
            }
        )
        return result.response
    }

    private func requestSnapshot(credentials: CursorSessionCredentials) async throws -> UsageSnapshot {
        do {
            return try await fetchViaConnectRPC(credentials: credentials)
        } catch let error as ProviderError {
            switch error {
            case .unauthorized, .rateLimited, .unavailable:
                throw error
            default:
                return try await fetchViaREST(credentials: credentials)
            }
        } catch {
            return try await fetchViaREST(credentials: credentials)
        }
    }

    private func fetchViaConnectRPC(credentials: CursorSessionCredentials) async throws -> UsageSnapshot {
        async let sandTask = requestConnectRPC(method: "GetSandUsageStatus", accessToken: credentials.accessToken)
        async let periodTask = requestConnectRPC(method: "GetCurrentPeriodUsage", accessToken: credentials.accessToken)
        let sand = try await sandTask
        let period = try? await periodTask
        return try Self.parseSnapshot(
            sand: sand,
            period: period,
            descriptor: descriptor,
            credentials: credentials,
            planNameOverride: nil
        )
    }

    private func fetchViaREST(credentials: CursorSessionCredentials) async throws -> UsageSnapshot {
        let cookie = CursorSessionAuth.workosCookieHeader(accessToken: credentials.accessToken)
        let sand = try await requestRESTJSON(
            url: Self.restSandURL,
            method: "POST",
            cookie: cookie,
            origin: "https://cursor.com",
            body: Data("{}".utf8)
        )
        var membership = credentials.membershipType
        if OfficialValueParser.nonPlaceholderString(sand["grokPlanLabel"]) == nil {
            if let summary = try? await requestRESTJSON(
                url: Self.restUsageSummaryURL,
                method: "GET",
                cookie: cookie,
                origin: nil,
                body: nil
            ) {
                membership = OfficialValueParser.planLabel(summary["membershipType"]) ?? membership
            }
        }
        return try Self.parseSnapshot(
            sand: sand,
            period: nil,
            descriptor: descriptor,
            credentials: credentials,
            planNameOverride: membership
        )
    }

    private func requestConnectRPC(method: String, accessToken: String) async throws -> [String: Any] {
        guard let url = URL(string: Self.connectRPCBaseURL + "/" + method) else {
            throw ProviderError.invalidResponse("invalid Grok Bot RPC URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("sand", forHTTPHeaderField: "x-cursor-client-type")
        request.setValue("0.1.0", forHTTPHeaderField: "x-cursor-client-version")
        request.setValue("prod", forHTTPHeaderField: "x-sand-box-namespace")
        request.setValue("true", forHTTPHeaderField: "x-ghost-mode")
        let identity = Self.connectRPCIdentity()
        request.setValue(identity.checksum, forHTTPHeaderField: "x-cursor-checksum")
        request.setValue(identity.requestID, forHTTPHeaderField: "x-request-id")
        return try await sendJSON(request)
    }

    private func requestRESTJSON(
        url: URL,
        method: String,
        cookie: String,
        origin: String?,
        body: Data?
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return try await sendJSON(request)
    }

    private func sendJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Grok Bot non-http response")
        }
        try HTTPResponseValidation.validate(http, urlDescription: "Grok Bot", body: data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Grok Bot decode failed")
        }
        return root
    }

    internal static func parseSnapshot(
        sand: [String: Any],
        period: [String: Any]?,
        descriptor: ProviderDescriptor,
        credentials: CursorSessionCredentials,
        planNameOverride: String?
    ) throws -> UsageSnapshot {
        if let hasLimit = sand["hasNonZeroIncludedLimit"] as? Bool, hasLimit == false {
            throw ProviderError.unavailable(noAllowanceMessage)
        }

        guard let usedPercentRaw = OfficialValueParser.double(sand["usagePercent"]) else {
            throw ProviderError.invalidResponse("missing Grok Bot usagePercent")
        }
        let usedPercent = min(100, max(0, usedPercentRaw))
        let remainingPercent = max(0, 100 - usedPercent)
        let resetAt = parseTimestamp(sand["nextResetTimestampUtc"])
        let planName = CursorSessionAuth.displayPlanName(
            grokPlanLabel: OfficialValueParser.planLabel(sand["grokPlanLabel"]),
            membershipType: planNameOverride ?? credentials.membershipType
        )

        var windows: [UsageQuotaWindow] = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-weekly",
                title: "Weekly",
                remainingPercent: remainingPercent,
                usedPercent: usedPercent,
                resetAt: resetAt,
                kind: .weekly
            )
        ]

        let spend = period?["spendLimitUsage"] as? [String: Any]
        let onDemandUsed = OfficialValueParser.double(spend?["individualUsed"] ?? spend?["totalSpend"]) ?? 0
        let onDemandLimit = OfficialValueParser.double(spend?["individualLimit"]) ?? 0
        if onDemandLimit > 0 {
            let onDemandUsedPercent = min(100, max(0, onDemandUsed / onDemandLimit * 100))
            let onDemandReset = parseTimestamp(period?["billingCycleEnd"]) ?? resetAt
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-ondemand",
                    title: "On-Demand",
                    remainingPercent: max(0, 100 - onDemandUsedPercent),
                    usedPercent: onDemandUsedPercent,
                    resetAt: onDemandReset,
                    kind: .extraUsage
                )
            )
        }

        let remaining = windows.map(\.remainingPercent).min() ?? remainingPercent
        var extras: [String: String] = [:]
        if OfficialValueParser.planLabel(planName) != nil {
            extras["planType"] = planName
        }
        extras["authSource"] = credentials.source.authSourceLabel
        if onDemandLimit > 0 {
            extras["onDemandUsed"] = formatUnits(onDemandUsed)
            extras["onDemandLimit"] = formatUnits(onDemandLimit)
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: usedPercent,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: {
                let usageNote = windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | ")
                if OfficialValueParser.planLabel(planName) != nil {
                    return "Plan \(planName) | \(usageNote)"
                }
                return usageNote
            }(),
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: credentials.email,
            authSourceLabel: credentials.source.authSourceLabel,
            extras: extras,
            rawMeta: [
                "grokBot.planLabel": planName,
                "grokBot.authSource": credentials.source.rawValue
            ]
        )
    }

    internal static func parseTimestamp(_ raw: Any?) -> Date? {
        if let string = OfficialValueParser.string(raw) {
            if let date = OfficialValueParser.isoDate(string) {
                return date
            }
            if let number = Double(string) {
                return parseEpoch(number)
            }
        }
        if let number = OfficialValueParser.double(raw) {
            return parseEpoch(number)
        }
        return nil
    }

    private static func parseEpoch(_ number: Double) -> Date? {
        if number > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: number / 1000)
        }
        if number > 1_000_000_000 {
            return Date(timeIntervalSince1970: number)
        }
        return nil
    }

    private static func formatUnits(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private static func connectRPCIdentity(now: Date = Date()) -> (requestID: String, checksum: String) {
        let requestID = UUID().uuidString.lowercased()
        let mid = UUID().uuidString.lowercased()
        let nowMs = Int64((now.timeIntervalSince1970 * 1000).rounded())
        let ks = nowMs / 1_000_000
        var bytes: [UInt8] = [
            UInt8((ks >> 40) & 0xff),
            UInt8((ks >> 32) & 0xff),
            UInt8((ks >> 24) & 0xff),
            UInt8((ks >> 16) & 0xff),
            UInt8((ks >> 8) & 0xff),
            UInt8(ks & 0xff)
        ]
        var previous: UInt8 = 165
        for index in bytes.indices {
            let combined = UInt16(bytes[index] ^ previous) + UInt16(index % 256)
            bytes[index] = UInt8(combined & 0xff)
            previous = bytes[index]
        }
        let encoded = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return (requestID, encoded + mid)
    }
}
