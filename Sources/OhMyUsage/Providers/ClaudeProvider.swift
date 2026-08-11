import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class ClaudeProvider: UsageProvider, @unchecked Sendable {
    private static let cache = FetchedAtOfficialSnapshotCache()
    private static let gate = SerialOfficialFetchGate()
    private static let webReadBackoff = WebOverlayRetryBackoff()

    private let cacheTTL: TimeInterval = 15
    private let webRetryBackoffInterval: TimeInterval = 15 * 60
    private let session: URLSession
    private let keychain: any TokenCredentialStoring
    private let browserCookieService: any BrowserCookieDetecting
    private let webReadBackoff: WebOverlayRetryBackoff
    private let cache: any OfficialSnapshotCaching
    private let gate: any OfficialFetchGating
    private let homeDirectory: () -> String
    private let shell: any ShellCommandRunning

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: any TokenCredentialStoring,
        browserCookieService: any BrowserCookieDetecting,
        webReadBackoff: WebOverlayRetryBackoff = ClaudeProvider.webReadBackoff,
        cache: any OfficialSnapshotCaching = ClaudeProvider.cache,
        gate: any OfficialFetchGating = ClaudeProvider.gate,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        shell: any ShellCommandRunning = DefaultShellCommandRunner()
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCookieService = browserCookieService
        self.webReadBackoff = webReadBackoff
        self.cache = cache
        self.gate = gate
        self.homeDirectory = homeDirectory
        self.shell = shell
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await OfficialProviderFetchRuntime.fetch(
            forceRefresh: forceRefresh,
            cacheLookupKey: descriptor.id,
            ttl: cacheTTL,
            cache: cache,
            gate: gate,
            load: { [self] in try await loadSnapshot(forceRefresh: forceRefresh) }
        )
    }

    private func loadSnapshot(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .claude)
        switch official.sourceMode {
        case .api:
            return try await loadFromAPI(includeWebOverlay: official.webMode != .disabled, forceRefresh: forceRefresh)
        case .cli:
            return try await loadFromCLI(forceRefresh: forceRefresh)
        case .web:
            return try await loadFromWeb(forceRefresh: forceRefresh)
        case .auto:
            do {
                return try await loadFromAPI(includeWebOverlay: official.webMode != .disabled, forceRefresh: forceRefresh)
            } catch {
                do {
                    return try await loadFromCLI(forceRefresh: forceRefresh)
                } catch {
                    return try await loadFromWeb(forceRefresh: forceRefresh)
                }
            }
        }
    }

    private func loadFromAPI(includeWebOverlay: Bool, forceRefresh: Bool) async throws -> UsageSnapshot {
        var credentials = try loadCredentials()
        guard !credentials.inferenceOnly else {
            throw ProviderError.unauthorizedDetail("inference-only token cannot read Claude quota")
        }

        if needsRefresh(expiresAtMs: credentials.expiresAtMs) {
            credentials = try await refresh(credentials: credentials)
        }

        let (data, usageResponse) = try await requestOAuthUsage(accessToken: credentials.accessToken)
        var snapshot = try Self.parseClaudeSnapshot(
            root: data,
            response: usageResponse,
            descriptor: descriptor,
            sourceLabel: "API",
            accountLabel: credentials.accountLabel,
            planHint: credentials.subscriptionType
        )

        if includeWebOverlay, let webSnapshot = try? await loadWebSnapshot(forceRefresh: forceRefresh) {
            snapshot = OfficialProviderWebOverlayRuntime.merge(
                primary: snapshot,
                overlay: webSnapshot,
                sourceLabel: "API+Web"
            )
        }
        return snapshot
    }

    private func loadFromCLI(forceRefresh: Bool) async throws -> UsageSnapshot {
        let snapshot = try runClaudeCLIUsage()
        if descriptor.officialConfig?.webMode != .disabled,
           let webSnapshot = try? await loadWebSnapshot(forceRefresh: forceRefresh) {
            return OfficialProviderWebOverlayRuntime.merge(
                primary: snapshot,
                overlay: webSnapshot,
                sourceLabel: "CLI+Web"
            )
        }
        return snapshot
    }

    private func loadFromWeb(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await loadWebSnapshot(forceRefresh: forceRefresh)
    }

    private func loadCredentials() throws -> ClaudeCredentials {
        let home = homeDirectory()
        let path = "\(home)/.claude/.credentials.json"
        if FileManager.default.fileExists(atPath: path),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let credentials = parseClaudeCredentials(json: json, source: .file(path)) {
            return credentials
        }

        if let raw = SecurityCredentialReader.readGenericPassword(service: "Claude Code-credentials"),
           let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let credentials = parseClaudeCredentials(json: json, source: .keychain) {
            return credentials
        }

        if let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return ClaudeCredentials(
                accessToken: token,
                refreshToken: nil,
                expiresAtMs: nil,
                subscriptionType: nil,
                scopes: [],
                source: .environment,
                inferenceOnly: true
            )
        }

        throw ProviderError.missingCredential("~/.claude/.credentials.json")
    }

    private func parseClaudeCredentials(json: [String: Any], source: ClaudeCredentialSource) -> ClaudeCredentials? {
        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = OfficialValueParser.string(oauth["accessToken"]) else {
            return nil
        }
        let refreshToken = OfficialValueParser.string(oauth["refreshToken"])
        let expiresAtMs = OfficialValueParser.double(oauth["expiresAt"])
        let subscriptionType = OfficialValueParser.string(oauth["subscriptionType"])
        let scopes = (oauth["scopes"] as? [String]) ?? []
        let inferenceOnly = !scopes.isEmpty && !scopes.contains("user:profile")
        return ClaudeCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAtMs: expiresAtMs,
            subscriptionType: subscriptionType,
            scopes: scopes,
            source: source,
            inferenceOnly: inferenceOnly
        )
    }

    private func needsRefresh(expiresAtMs: Double?) -> Bool {
        guard let expiresAtMs else { return false }
        let nowMs = Date().timeIntervalSince1970 * 1000
        return nowMs + 5 * 60 * 1000 >= expiresAtMs
    }

    private func refresh(credentials: ClaudeCredentials) async throws -> ClaudeCredentials {
        guard let refreshToken = credentials.refreshToken else {
            throw ProviderError.unauthorized
        }

        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "scope": "user:profile user:inference user:sessions:claude_code user:mcp_servers"
        ])

        let refresh = try await OfficialProviderAuthRuntime.requestOAuthRefresh(
            session: session,
            request: request,
            invalidResponseMessage: "refresh invalid response",
            missingAccessTokenMessage: "missing refresh access_token",
            httpErrorMessage: { "refresh http \($0)" }
        )

        var updated = credentials
        updated.accessToken = refresh.accessToken
        updated.refreshToken = OfficialValueParser.string(refresh.json["refresh_token"]) ?? credentials.refreshToken
        if let expiresIn = OfficialValueParser.double(refresh.json["expires_in"]) {
            updated.expiresAtMs = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
        }
        if case let .file(path) = credentials.source {
            persist(credentials: updated, path: path)
        }
        return updated
    }

    private func persist(credentials: ClaudeCredentials, path: String) {
        OfficialProviderAuthRuntime.updateJSONObjectFile(path: path) { json in
            var oauth = (json["claudeAiOauth"] as? [String: Any]) ?? [:]
            oauth["accessToken"] = credentials.accessToken
            oauth["refreshToken"] = credentials.refreshToken
            oauth["expiresAt"] = credentials.expiresAtMs
            oauth["subscriptionType"] = credentials.subscriptionType
            json["claudeAiOauth"] = oauth
        }
    }

    private func requestOAuthUsage(accessToken: String) async throws -> ([String: Any], HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("oauth usage decode failed")
        }
        return (json, http)
    }

    private func loadWebSnapshot(forceRefresh: Bool) async throws -> UsageSnapshot {
        let cookie = try await resolveClaudeCookieHeader(forceRefresh: forceRefresh)

        if let token = extractCookieValue(name: "sessionKey", from: cookie.header),
           let oauthSnapshot = try? await loadWebOAuthSnapshot(token: token, source: cookie.source) {
            return oauthSnapshot
        }

        guard let orgId = try await fetchClaudeOrganizationID(cookieHeader: cookie.header) else {
            throw ProviderError.invalidResponse("missing Claude organization")
        }
        let usageRoot = try await requestClaudeWebJSON(path: "/api/organizations/\(orgId)/usage", cookieHeader: cookie.header)
        var snapshot = try Self.parseClaudeSnapshot(
            root: usageRoot,
            descriptor: descriptor,
            sourceLabel: "Web",
            accountLabel: nil,
            planHint: nil
        )
        if let overage = try? await requestClaudeWebJSON(path: "/api/organizations/\(orgId)/overage_spend_limit", cookieHeader: cookie.header) {
            applyOverage(root: overage, to: &snapshot)
        }
        if let account = try? await requestClaudeWebJSON(path: "/api/account", cookieHeader: cookie.header),
           let email = OfficialValueParser.string(account["email"]) {
            snapshot.accountLabel = email
        }
        snapshot.extras["webCookieSource"] = cookie.source
        return snapshot
    }

    private func loadWebOAuthSnapshot(token: String, source: String) async throws -> UsageSnapshot {
        let (root, usageResponse) = try await requestOAuthUsage(accessToken: token)
        var snapshot = try Self.parseClaudeSnapshot(
            root: root,
            response: usageResponse,
            descriptor: descriptor,
            sourceLabel: "Web",
            accountLabel: nil,
            planHint: nil
        )
        snapshot.extras["webCookieSource"] = source
        return snapshot
    }

    private func resolveClaudeCookieHeader(forceRefresh: Bool) async throws -> BrowserCookieHeader {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .claude)
        return try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: official,
            descriptorID: descriptor.id,
            keychain: keychain,
            browserCookieService: browserCookieService,
            webReadBackoff: webReadBackoff,
            webRetryBackoffInterval: webRetryBackoffInterval,
            forceRefresh: forceRefresh,
            strategy: OfficialBrowserCookieImportStrategy(
                providerKey: "claude",
                hostContains: "claude.ai",
                namedCookie: "sessionKey",
                autoImportMissingCredential: "claude.ai session cookie",
                manualCredentialFallback: "official/claude/cookie-header",
                normalizeManualHeader: { stored in
                    let normalized = stored.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalized.isEmpty else { return nil }
                    return normalized.contains("=") ? normalized : "sessionKey=\(normalized)"
                },
                normalizeDetectedHeader: { header in
                    let normalized = header.trimmingCharacters(in: .whitespacesAndNewlines)
                    return normalized.isEmpty ? nil : normalized
                }
            )
        )
    }

    private func fetchClaudeOrganizationID(cookieHeader: String) async throws -> String? {
        let root = try await requestClaudeWebAny(path: "/api/organizations", cookieHeader: cookieHeader)
        if let array = root as? [[String: Any]] {
            for item in array {
                if let value = OfficialValueParser.string(item["uuid"] ?? item["id"] ?? item["organization_uuid"]) {
                    return value
                }
            }
        }
        if let dict = root as? [String: Any],
           let items = dict["organizations"] as? [[String: Any]] {
            for item in items {
                if let value = OfficialValueParser.string(item["uuid"] ?? item["id"] ?? item["organization_uuid"]) {
                    return value
                }
            }
        }
        return nil
    }

    private func requestClaudeWebJSON(path: String, cookieHeader: String) async throws -> [String: Any] {
        let root = try await requestClaudeWebAny(path: path, cookieHeader: cookieHeader)
        guard let dict = root as? [String: Any] else {
            throw ProviderError.invalidResponse("expected json object for \(path)")
        }
        return dict
    }

    private func requestClaudeWebAny(path: String, cookieHeader: String) async throws -> Any {
        guard let url = URL(string: "https://claude.ai\(path)") else {
            throw ProviderError.invalidResponse("invalid Claude URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func runClaudeCLIUsage() throws -> UsageSnapshot {
        guard let executable = resolveClaudeExecutablePath() else {
            throw ProviderError.unavailable("Unable to locate claude CLI.")
        }
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")

        let result = shell.run(
            executable: executable,
            arguments: ["/usage", "--allowed-tools", ""],
            input: nil,
            timeout: 25,
            environment: env,
            currentDirectory: NSHomeDirectory()
        )

        guard let result else {
            throw ProviderError.commandFailed("claude /usage failed to start")
        }
        let combinedOutput = "\(result.stdout)\n\(result.stderr)"
        if Self.looksLikeMissingClaudeSubscription(text: combinedOutput) {
            throw ProviderError.unavailable("Claude subscription required")
        }
        guard result.status == 0 || !result.stdout.isEmpty else {
            throw ProviderError.commandFailed(result.stderr.isEmpty ? "claude /usage failed" : result.stderr)
        }

        do {
            return try Self.parseClaudeCLIOutput(result.stdout, descriptor: descriptor)
        } catch {
            let lower = result.stdout.lowercased()
            if lower.contains("cost") || lower.contains("api usage billing") || lower.contains("subscription required") {
                let costResult = shell.run(
                    executable: executable,
                    arguments: ["/cost", "--allowed-tools", ""],
                    input: nil,
                    timeout: 25,
                    environment: env,
                    currentDirectory: NSHomeDirectory()
                )
                if let costResult, !costResult.stdout.isEmpty {
                    return Self.parseClaudeCostOutput(costResult.stdout, descriptor: descriptor)
                }
            }
            throw error
        }
    }

    internal static func parseClaudeCLIOutput(_ text: String, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        let clean = stripANSICodes(text)
        if clean.lowercased().contains("token_expired") {
            throw ProviderError.unauthorized
        }
        if looksLikeMissingClaudeSubscription(text: clean) {
            throw ProviderError.unavailable("Claude subscription required")
        }

        guard let sessionRemaining = extractClaudePercent(label: "Current session", text: clean) else {
            throw ProviderError.invalidResponse("missing Claude current session usage")
        }

        let weeklyRemaining = extractClaudePercent(label: "Current week", text: clean)
        let sessionReset = extractClaudeReset(label: "Current session", text: clean)
        let weeklyReset = extractClaudeReset(label: "Current week", text: clean)

        var windows: [UsageQuotaWindow] = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-session",
                title: "Session",
                remainingPercent: Double(sessionRemaining),
                usedPercent: Double(max(0, 100 - sessionRemaining)),
                resetAt: sessionReset,
                kind: .session
            )
        ]
        if let weeklyRemaining {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-weekly",
                    title: "Weekly",
                    remainingPercent: Double(weeklyRemaining),
                    usedPercent: Double(max(0, 100 - weeklyRemaining)),
                    resetAt: weeklyReset,
                    kind: .weekly
                )
            )
        }

        let remaining = windows.map(\.remainingPercent).min() ?? Double(sessionRemaining)
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Session \(sessionRemaining)% | Weekly \(weeklyRemaining ?? 0)%",
            quotaWindows: windows,
            sourceLabel: "CLI",
            accountLabel: nil,
            extras: [:],
            rawMeta: [:]
        )
    }

    internal static func parseClaudeCostOutput(_ text: String, descriptor: ProviderDescriptor) -> UsageSnapshot {
        let clean = stripANSICodes(text)
        let totalCost = extractDollarValue(after: "Total cost:", text: clean) ?? 0
        return UsageSnapshot(
            source: descriptor.id,
            status: .ok,
            remaining: nil,
            used: totalCost,
            limit: nil,
            unit: "USD",
            updatedAt: Date(),
            note: "Extra usage cost $\(String(format: "%.2f", totalCost))",
            quotaWindows: [],
            sourceLabel: "CLI",
            accountLabel: nil,
            extras: ["extraUsageCostUSD": String(format: "%.2f", totalCost)],
            rawMeta: [:]
        )
    }

    internal static func parseClaudeSnapshot(
        root: [String: Any],
        response: HTTPURLResponse? = nil,
        descriptor: ProviderDescriptor,
        sourceLabel: String,
        accountLabel: String?,
        planHint: String?,
        receivedAt: Date = Date()
    ) throws -> UsageSnapshot {
        var windows: [UsageQuotaWindow] = []
        let clockSkew = response.flatMap { OfficialValueParser.clockSkew(response: $0, localReceiveAt: receivedAt) }

        if let fiveHour = root["five_hour"] as? [String: Any],
           let used = OfficialValueParser.double(fiveHour["utilization"] ?? fiveHour["used_percent"]) {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-session",
                    title: "5h",
                    remainingPercent: max(0, 100 - used),
                    usedPercent: used,
                    resetAt: OfficialValueParser.applyClockSkew(
                        OfficialValueParser.isoDate(OfficialValueParser.string(fiveHour["resets_at"])),
                        skew: clockSkew
                    ),
                    kind: .session
                )
            )
        }
        if let sevenDay = root["seven_day"] as? [String: Any],
           let used = OfficialValueParser.double(sevenDay["utilization"] ?? sevenDay["used_percent"]) {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-weekly",
                    title: "Weekly",
                    remainingPercent: max(0, 100 - used),
                    usedPercent: used,
                    resetAt: OfficialValueParser.applyClockSkew(
                        OfficialValueParser.isoDate(OfficialValueParser.string(sevenDay["resets_at"])),
                        skew: clockSkew
                    ),
                    kind: .weekly
                )
            )
        }

        var parsedSevenDayKeys: [String] = []
        for key in root.keys.sorted() where key.hasPrefix("seven_day_") {
            guard let item = root[key] as? [String: Any],
                  let used = OfficialValueParser.double(item["utilization"] ?? item["used_percent"]) else {
                continue
            }
            parsedSevenDayKeys.append(key)
            let title = normalizedSevenDayWindowTitle(for: key)
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-\(key)",
                    title: title,
                    remainingPercent: max(0, 100 - used),
                    usedPercent: used,
                    resetAt: OfficialValueParser.applyClockSkew(
                        OfficialValueParser.isoDate(OfficialValueParser.string(item["resets_at"])),
                        skew: clockSkew
                    ),
                    kind: .modelWeekly
                )
            )
        }

        let extraUsage = root["extra_usage"] as? [String: Any]
        let extraCost = OfficialValueParser.double(extraUsage?["used_credits"])
        let extraLimit = OfficialValueParser.double(extraUsage?["monthly_limit"])

        if looksLikeMissingClaudeSubscription(root: root, windows: windows, planHint: planHint, extraCost: extraCost, extraLimit: extraLimit) {
            throw ProviderError.unavailable("Claude subscription required")
        }

        guard !windows.isEmpty || extraCost != nil else {
            throw ProviderError.invalidResponse("missing Claude usage windows")
        }

        let remaining = windows.map(\.remainingPercent).min()
        let note = buildClaudeNote(windows: windows, extraCost: extraCost, extraLimit: extraLimit, planHint: planHint)
        var extras: [String: String] = [:]
        if let planHint {
            extras["planType"] = planHint
        }
        if let extraCost {
            extras["extraUsageCost"] = String(format: "%.2f", extraCost)
        }
        if let extraLimit {
            extras["extraUsageLimit"] = String(format: "%.2f", extraLimit)
        }
        var rawMeta = extras
        if !parsedSevenDayKeys.isEmpty {
            rawMeta["claude.parsedSevenDayKeys"] = parsedSevenDayKeys.joined(separator: ",")
        }
        if parsedSevenDayKeys.contains("seven_day_sonnet_only") {
            rawMeta["claude.window.sonnetOnly"] = "present"
        }
        if parsedSevenDayKeys.contains("seven_day_claude_design") {
            rawMeta["claude.window.claudeDesign"] = "present"
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: (remaining ?? 100) <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: remaining.map { 100 - $0 },
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: note,
            quotaWindows: windows,
            sourceLabel: sourceLabel,
            accountLabel: accountLabel,
            extras: extras,
            rawMeta: rawMeta
        )
    }

    private func applyOverage(root: [String: Any], to snapshot: inout UsageSnapshot) {
        if let used = OfficialValueParser.double(root["used_credits"] ?? root["used"]),
           snapshot.extras["extraUsageCost"] == nil {
            snapshot.extras["extraUsageCost"] = String(format: "%.2f", used)
        }
        if let limit = OfficialValueParser.double(root["monthly_limit"] ?? root["limit"]),
           snapshot.extras["extraUsageLimit"] == nil {
            snapshot.extras["extraUsageLimit"] = String(format: "%.2f", limit)
        }
    }

    private static func buildClaudeNote(windows: [UsageQuotaWindow], extraCost: Double?, extraLimit: Double?, planHint: String?) -> String {
        var parts: [String] = []
        if let planHint {
            parts.append("Plan \(planHint)")
        }
        for window in windows.prefix(3) {
            parts.append("\(window.title) \(Int(window.remainingPercent.rounded()))%")
        }
        if let extraCost {
            if let extraLimit, extraLimit > 0 {
                parts.append("Extra \(String(format: "%.0f", extraCost))/\(String(format: "%.0f", extraLimit))")
            } else {
                parts.append("Extra \(String(format: "%.0f", extraCost))")
            }
        }
        return parts.joined(separator: " | ")
    }

    private static func normalizedSevenDayWindowTitle(for key: String) -> String {
        switch key {
        case "seven_day_sonnet_only":
            return "Sonnet only"
        case "seven_day_claude_design":
            return "Claude Design"
        default:
            let raw = key.replacingOccurrences(of: "seven_day_", with: "")
            let words = raw
                .split(separator: "_")
                .map { segment in
                    let lower = segment.lowercased()
                    if lower == "claude" {
                        return "Claude"
                    }
                    return lower.prefix(1).uppercased() + lower.dropFirst()
                }
            return words.joined(separator: " ")
        }
    }

    private func resolveClaudeExecutablePath() -> String? {
        let manager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["CLAUDE_CLI_PATH"],
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
            "/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude"
        ].compactMap { $0 }
        let envCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map { "\($0)/claude" }
        for path in candidates + envCandidates where manager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func extractClaudePercent(label: String, text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        let target = label.lowercased()
        for (index, line) in lines.enumerated() where line.lowercased().contains(target) {
            let window = lines.dropFirst(index).prefix(12)
            for candidate in window {
                if let match = candidate.range(of: #"([0-9]{1,3})%\s+(left|used)"#, options: .regularExpression) {
                    let raw = String(candidate[match])
                    if let number = Int(raw.components(separatedBy: "%").first ?? "") {
                        if raw.lowercased().contains("used") {
                            return max(0, 100 - number)
                        }
                        return number
                    }
                }
            }
        }
        return nil
    }

    private static func extractClaudeReset(label: String, text: String) -> Date? {
        let lines = text.components(separatedBy: .newlines)
        let target = label.lowercased()
        for (index, line) in lines.enumerated() where line.lowercased().contains(target) {
            let window = lines.dropFirst(index).prefix(12)
            for candidate in window {
                guard candidate.lowercased().contains("reset") else { continue }
                if let date = OfficialValueParser.isoDate(extractISODate(from: candidate)) {
                    return date
                }
            }
        }
        return nil
    }

    private static func extractISODate(from text: String) -> String? {
        if let match = text.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z"#, options: .regularExpression) {
            return String(text[match])
        }
        return nil
    }

    private static func extractDollarValue(after label: String, text: String) -> Double? {
        guard let range = text.range(of: label) else { return nil }
        let suffix = text[range.upperBound...]
        if let match = suffix.range(of: #"\$([0-9]+(?:\.[0-9]+)?)"#, options: .regularExpression) {
            return Double(String(suffix[match]).replacingOccurrences(of: "$", with: ""))
        }
        return nil
    }

    private static func looksLikeMissingClaudeSubscription(text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "subscription required",
            "subscription plan",
            "requires subscription",
            "no active subscription",
            "upgrade to claude",
            "upgrade your plan",
            "billing required"
        ]
        return markers.contains(where: { lower.contains($0) })
    }

    private static func looksLikeMissingClaudeSubscription(
        root: [String: Any],
        windows: [UsageQuotaWindow],
        planHint: String?,
        extraCost: Double?,
        extraLimit: Double?
    ) -> Bool {
        if let planHint, !planHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if extraCost != nil || extraLimit != nil {
            return false
        }

        if containsSubscriptionMarker(in: root) {
            return true
        }

        guard !windows.isEmpty else { return false }
        let allUnused = windows.allSatisfy { $0.usedPercent <= 0.001 && $0.remainingPercent >= 99.999 }
        let noResetDates = windows.allSatisfy { $0.resetAt == nil }
        return allUnused && noResetDates
    }

    private static func containsSubscriptionMarker(in value: Any) -> Bool {
        if let string = value as? String {
            return looksLikeMissingClaudeSubscription(text: string)
        }
        if let dict = value as? [String: Any] {
            return dict.contains { containsSubscriptionMarker(in: $0.key) || containsSubscriptionMarker(in: $0.value) }
        }
        if let array = value as? [Any] {
            return array.contains(where: containsSubscriptionMarker)
        }
        return false
    }

    private func extractCookieValue(name: String, from header: String) -> String? {
        let parts = header.split(separator: ";")
        for part in parts {
            let item = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.hasPrefix("\(name)=") else { continue }
            return String(item.dropFirst(name.count + 1))
        }
        return nil
    }
}

private struct ClaudeCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAtMs: Double?
    var subscriptionType: String?
    var scopes: [String]
    var source: ClaudeCredentialSource
    var inferenceOnly: Bool

    var accountLabel: String? {
        nil
    }
}

private enum ClaudeCredentialSource {
    case file(String)
    case keychain
    case environment
}
