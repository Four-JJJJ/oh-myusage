import CryptoKit
import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class GeminiProvider: UsageProvider, @unchecked Sendable {
    private static let cache = SnapshotTimestampOfficialSnapshotCache()
    private static let gate = PassthroughOfficialFetchGate()
    private static let contextCache = GeminiCodeAssistContextCache()

    /// Account/project context from `loadCodeAssist`. Deliberately much longer
    /// than the quota snapshot TTL (§8.4): repeated refreshes re-issue only
    /// `retrieveUserQuota`.
    static let contextTTL: TimeInterval = 6 * 60 * 60
    /// Plan tier metadata TTL. Longer than the quota data TTL (§8.4) so the
    /// slow-changing tier is not refetched on every quota refresh.
    static let planMetadataTTL: TimeInterval = 30 * 60
    /// Vault account for the refreshed OAuth token inside the app's shared
    /// credential store (service `oh-myusage`), following the Codex / Claude
    /// `official/<provider>/oauth-json` convention.
    static let oauthVaultAccount = "official/gemini/oauth-json"
    static let credentialServiceName = TokenCredentialStoreServiceNames.defaultServiceName

    private let cacheTTL: TimeInterval
    private let refreshBuffer: TimeInterval = 5 * 60
    private let session: URLSession
    private let cache: any OfficialSnapshotCaching
    private let gate: any OfficialFetchGating
    private let contextCache: GeminiCodeAssistContextCache
    private let keychain: (any TokenCredentialStoring)?
    private let homeDirectory: () -> String
    private let shell: any ShellCommandRunning

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        cache: any OfficialSnapshotCaching = GeminiProvider.cache,
        gate: any OfficialFetchGating = GeminiProvider.gate,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        shell: any ShellCommandRunning = DefaultShellCommandRunner(),
        contextCache: GeminiCodeAssistContextCache = GeminiProvider.contextCache,
        keychain: (any TokenCredentialStoring)? = nil,
        cacheTTL: TimeInterval = 15
    ) {
        self.descriptor = descriptor
        self.session = session
        self.cache = cache
        self.gate = gate
        self.homeDirectory = homeDirectory
        self.shell = shell
        self.contextCache = contextCache
        self.keychain = keychain
        self.cacheTTL = cacheTTL
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await OfficialProviderFetchRuntime.fetch(
            forceRefresh: forceRefresh,
            cacheLookupKey: snapshotCacheKey(),
            ttl: cacheTTL,
            cache: cache,
            gate: gate,
            load: { [self] in try await loadSnapshot(forceRefresh: forceRefresh) }
        )
    }

    /// Snapshot cache key scoped to the discovered account identity so cached
    /// snapshots are never reused across accounts (§8.2 / §8.5).
    private func snapshotCacheKey() -> String {
        guard let credentials = try? loadCredentials() else {
            return descriptor.id
        }
        if let accountLabel = credentials.accountLabel, !accountLabel.isEmpty {
            return "\(descriptor.id)|account=\(accountLabel)"
        }
        if let fingerprint = Self.credentialFingerprint(credentials.refreshToken ?? credentials.accessToken) {
            return "\(descriptor.id)|fingerprint=\(fingerprint)"
        }
        return descriptor.id
    }

    private func loadSnapshot(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .gemini)
        switch official.sourceMode {
        case .api, .auto:
            return try await loadFromAPI(forceRefresh: forceRefresh)
        case .cli:
            throw ProviderError.unavailable("Gemini 官方来源当前仅支持 API 凭证发现")
        case .web:
            throw ProviderError.unavailable("Gemini 官方来源当前不支持网页 Cookie 检测")
        }
    }

    private func loadFromAPI(forceRefresh: Bool) async throws -> UsageSnapshot {
        let settings = try loadSettings()
        switch settings.authType {
        case "api-key":
            throw ProviderError.unavailable("Gemini API key 模式无法稳定获取官方订阅配额")
        case "vertex-ai":
            throw ProviderError.unavailable("Gemini Vertex AI 模式不属于个人官方订阅配额")
        default:
            break
        }

        let result = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
            initialState: try loadCredentials(),
            shouldRefresh: { [self] credentials in
                needsRefresh(credentials.expiresAt)
            },
            request: { [self] credentials in
                try await requestSnapshot(
                    accessToken: credentials.accessToken,
                    settings: settings,
                    credentials: credentials,
                    allowCachedContext: !forceRefresh
                )
            },
            refresh: { [self] credentials in
                try await refresh(credentials: credentials)
            }
        )
        return result.response
    }

    private func requestSnapshot(
        accessToken: String,
        settings: GeminiSettings,
        credentials: GeminiCredentials,
        allowCachedContext: Bool
    ) async throws -> UsageSnapshot {
        let contextKey = Self.contextCacheKey(credentials: credentials, selectedProject: settings.selectedProject)
        let cachedContext = allowCachedContext
            ? await contextCache.contextIfFresh(forKey: contextKey)
            : nil
        let cachedPlan: String? = cachedContext == nil
            ? nil
            : await contextCache.planIfFresh(forKey: contextKey)

        // Context and plan metadata both fresh: only the quota request is issued.
        // `loadCodeAssist` stays part of every full load (both requests are
        // required, they are not merged).
        if let cachedContext, let plan = cachedPlan {
            return try await requestQuotaSnapshot(
                accessToken: accessToken,
                credentials: credentials,
                projectID: cachedContext.projectID,
                projectLabel: cachedContext.projectLabel,
                plan: plan
            )
        }

        let codeAssist = try await requestJSON(
            url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!,
            accessToken: accessToken,
            body: loadCodeAssistBody(projectID: settings.selectedProject)
        )
        let resolvedProjectID = resolveProjectID(settings: settings, codeAssistRoot: codeAssist)
        let plan = Self.parsePlan(from: codeAssist) ?? "unknown"

        var projectLabel = resolvedProjectID
        if let projectID = resolvedProjectID {
            if let cachedContext,
               cachedContext.projectID == projectID,
               let cachedLabel = cachedContext.projectLabel {
                projectLabel = cachedLabel
            } else if let resolved = try? await resolveProjectName(accessToken: accessToken, projectID: projectID) {
                projectLabel = resolved
            }
        }

        await contextCache.store(
            GeminiCodeAssistContext(projectID: resolvedProjectID, projectLabel: projectLabel, plan: plan),
            forKey: contextKey
        )

        return try await requestQuotaSnapshot(
            accessToken: accessToken,
            credentials: credentials,
            projectID: resolvedProjectID,
            projectLabel: projectLabel,
            plan: plan
        )
    }

    private func requestQuotaSnapshot(
        accessToken: String,
        credentials: GeminiCredentials,
        projectID: String?,
        projectLabel: String?,
        plan: String
    ) async throws -> UsageSnapshot {
        let quotaRoot = try await requestJSON(
            url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!,
            accessToken: accessToken,
            body: retrieveQuotaBody(projectID: projectID)
        )
        return try Self.parseQuotaSnapshot(
            root: quotaRoot,
            plan: plan,
            descriptor: descriptor,
            sourceLabel: "API",
            accountLabel: credentials.accountLabel,
            projectLabel: projectLabel
        )
    }

    private func loadSettings() throws -> GeminiSettings {
        let path = "\(homeDirectory())/.gemini/settings.json"
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProviderError.missingCredential(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Gemini settings decode failed")
        }
        let security = json["security"] as? [String: Any]
        let auth = security?["auth"] as? [String: Any]
        let authType = Self.firstNonEmptyString([
            json["selectedAuthType"],
            json["authType"],
            json["auth_type"],
            auth?["selectedType"],
            auth?["selectedAuthType"],
            auth?["authType"],
            auth?["auth_type"],
        ]) ?? "oauth-personal"
        let selectedProject = Self.firstNonEmptyString([
            json["selectedProject"],
            json["project"],
            json["projectId"],
            json["project_id"],
            json["cloudaicompanionProject"],
            auth?["selectedProject"],
            auth?["project"],
            auth?["projectId"],
            auth?["project_id"],
            auth?["cloudaicompanionProject"],
        ])
        return GeminiSettings(
            authType: authType,
            selectedProject: selectedProject
        )
    }

    private func loadCodeAssistBody(projectID: String?) -> [String: Any] {
        var metadata: [String: Any] = [
            "ideType": "IDE_UNSPECIFIED",
            "platform": "PLATFORM_UNSPECIFIED",
            "pluginType": "GEMINI",
        ]
        var body: [String: Any] = [
            "metadata": metadata,
        ]
        if let projectID, !projectID.isEmpty {
            body["cloudaicompanionProject"] = projectID
            metadata["duetProject"] = projectID
            body["metadata"] = metadata
        }
        return body
    }

    private func retrieveQuotaBody(projectID: String?) -> [String: Any] {
        guard let projectID, !projectID.isEmpty else { return [:] }
        return ["project": projectID]
    }

    private func resolveProjectID(settings: GeminiSettings, codeAssistRoot: [String: Any]) -> String? {
        if let selectedProject = settings.selectedProject, !selectedProject.isEmpty {
            return selectedProject
        }
        if let project = Self.firstNonEmptyString([
            codeAssistRoot["cloudaicompanionProject"],
            codeAssistRoot["project"],
            codeAssistRoot["projectId"],
            codeAssistRoot["project_id"],
        ]), !project.isEmpty {
            return project
        }
        if let project = codeAssistRoot["cloudaicompanionProject"] as? [String: Any],
           let projectID = OfficialValueParser.string(project["id"] ?? project["projectId"] ?? project["project_id"]),
           !projectID.isEmpty {
            return projectID
        }
        return nil
    }

    /// Fixed read priority: app vault (refreshed copy of the same OAuth grant)
    /// → local credential file. The vaulted copy is only trusted when its
    /// refresh token matches the file, so a CLI re-login always wins.
    private func loadCredentials() throws -> GeminiCredentials {
        let fileCredentials = try loadFileCredentials()
        guard let keychain else { return fileCredentials }
        guard let raw = keychain.readToken(service: Self.credentialServiceName, account: Self.oauthVaultAccount),
              let vaulted = Self.parseCredentialsJSON(raw, filePath: fileCredentials.filePath),
              let vaultRefreshToken = vaulted.refreshToken,
              !vaultRefreshToken.isEmpty,
              vaultRefreshToken == fileCredentials.refreshToken else {
            return fileCredentials
        }
        return vaulted
    }

    private func loadFileCredentials() throws -> GeminiCredentials {
        let path = "\(homeDirectory())/.gemini/oauth_creds.json"
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProviderError.missingCredential(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Gemini oauth credentials decode failed")
        }
        guard let credentials = Self.parseCredentialsJSON(json: json, filePath: path) else {
            throw ProviderError.invalidResponse("missing Gemini access_token")
        }
        return credentials
    }

    private static func parseCredentialsJSON(json: [String: Any], filePath: String) -> GeminiCredentials? {
        guard let accessToken = OfficialValueParser.string(json["access_token"] ?? json["accessToken"]),
              !accessToken.isEmpty else {
            return nil
        }
        return GeminiCredentials(
            accessToken: accessToken,
            refreshToken: OfficialValueParser.string(json["refresh_token"] ?? json["refreshToken"]),
            expiresAt: parseExpiry(json: json),
            idToken: OfficialValueParser.string(json["id_token"] ?? json["idToken"]),
            filePath: filePath
        )
    }

    private static func parseCredentialsJSON(_ raw: String, filePath: String) -> GeminiCredentials? {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else {
            return nil
        }
        return parseCredentialsJSON(json: json, filePath: filePath)
    }

    private static func parseExpiry(json: [String: Any]) -> Date? {
        if let raw = OfficialValueParser.double(json["expiry_date"] ?? json["expiryDate"]) {
            return raw > 1_000_000_000_000
                ? Date(timeIntervalSince1970: raw / 1000)
                : Date(timeIntervalSince1970: raw)
        }
        if let raw = OfficialValueParser.string(json["expires_at"] ?? json["expiresAt"]) {
            return OfficialValueParser.isoDate(raw)
        }
        return nil
    }

    private func needsRefresh(_ expiresAt: Date?) -> Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(refreshBuffer) >= expiresAt
    }

    private func refresh(credentials: GeminiCredentials) async throws -> GeminiCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw ProviderError.unauthorized
        }
        guard let client = resolveClientSecrets() else {
            throw ProviderError.unavailable("未找到 Gemini CLI OAuth client 配置，无法刷新令牌")
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": client.id,
            "client_secret": client.secret,
        ]
        request.httpBody = OfficialProviderAuthRuntime.urlEncodedFormData(form)

        let refresh = try await OfficialProviderAuthRuntime.requestOAuthRefresh(
            session: session,
            request: request,
            invalidResponseMessage: "Gemini refresh invalid response",
            missingAccessTokenMessage: "missing Gemini refresh access_token",
            httpErrorMessage: { "Gemini refresh http \($0)" }
        )

        var updated = credentials
        updated.accessToken = refresh.accessToken
        updated.idToken = OfficialValueParser.string(refresh.json["id_token"]) ?? updated.idToken
        if let expiresIn = OfficialValueParser.double(refresh.json["expires_in"]) {
            updated.expiresAt = Date().addingTimeInterval(expiresIn)
        }
        persistToVault(credentials: updated)
        return updated
    }

    /// Persists the refreshed OAuth token into the app's shared credential vault
    /// (service `oh-myusage`, account `official/gemini/oauth-json`) through the
    /// `TokenCredentialStoring` port. Refreshed tokens are never written back to
    /// the plaintext `~/.gemini/oauth_creds.json` and never logged (§8.4).
    private func persistToVault(credentials: GeminiCredentials) {
        guard let keychain else { return }
        var payload: [String: Any] = ["access_token": credentials.accessToken]
        if let refreshToken = credentials.refreshToken, !refreshToken.isEmpty {
            payload["refresh_token"] = refreshToken
        }
        if let idToken = credentials.idToken, !idToken.isEmpty {
            payload["id_token"] = idToken
        }
        if let expiresAt = credentials.expiresAt {
            payload["expiry_date"] = Int64(expiresAt.timeIntervalSince1970 * 1000)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        _ = keychain.saveToken(raw, service: Self.credentialServiceName, account: Self.oauthVaultAccount)
    }

    /// In-memory context cache key scoped to the account identity and the
    /// selected project, so cached Code Assist context is never reused across
    /// accounts or project selections (§8.5).
    private static func contextCacheKey(credentials: GeminiCredentials, selectedProject: String?) -> String {
        var components = ["gemini", "code-assist"]
        if let accountLabel = credentials.accountLabel, !accountLabel.isEmpty {
            components.append("account=\(accountLabel)")
        } else if let fingerprint = credentialFingerprint(credentials.refreshToken ?? credentials.accessToken) {
            components.append("fingerprint=\(fingerprint)")
        } else {
            components.append("account=unknown")
        }
        if let selectedProject, !selectedProject.isEmpty {
            components.append("project=\(selectedProject)")
        }
        return components.joined(separator: "|")
    }

    private static func credentialFingerprint(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func resolveClientSecrets() -> (id: String, secret: String)? {
        if let fromCredentials = loadClientSecretsFromOAuthCredentials() {
            return fromCredentials
        }

        for path in candidateClientSourcePaths() {
            guard FileManager.default.fileExists(atPath: path),
                  let source = try? String(contentsOfFile: path, encoding: .utf8),
                  let parsed = Self.parseClientSecrets(in: source) else {
                continue
            }
            return parsed
        }

        return nil
    }

    private func loadClientSecretsFromOAuthCredentials() -> (id: String, secret: String)? {
        let path = "\(homeDirectory())/.gemini/oauth_creds.json"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let candidateRoots: [[String: Any]] = [
            json,
            json["installed"] as? [String: Any],
            json["web"] as? [String: Any],
            json["oauth"] as? [String: Any],
            json["oauth_client"] as? [String: Any],
            json["oauthClient"] as? [String: Any],
            json["client"] as? [String: Any],
        ].compactMap { $0 }

        for root in candidateRoots {
            guard let clientID = OfficialValueParser.string(root["client_id"] ?? root["clientId"]),
                  let clientSecret = OfficialValueParser.string(root["client_secret"] ?? root["clientSecret"]),
                  !clientID.isEmpty,
                  !clientSecret.isEmpty else {
                continue
            }
            return (clientID, clientSecret)
        }

        return nil
    }

    private func candidateClientSourcePaths() -> [String] {
        var paths: [String] = []
        func appendUnique(_ path: String) {
            guard !path.isEmpty else { return }
            if !paths.contains(path) {
                paths.append(path)
            }
        }

        func appendBundleSources(in bundleDirectory: URL) {
            let bundlePath = bundleDirectory.path
            appendUnique(bundleDirectory.appendingPathComponent("gemini.js").path)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: bundlePath) else {
                return
            }
            for name in entries.sorted() where name.hasPrefix("chunk-") && name.hasSuffix(".js") {
                appendUnique(bundleDirectory.appendingPathComponent(name).path)
            }
        }

        var executableCandidates: [String] = []
        if let discovered = shell.run(executable: "/usr/bin/which", arguments: ["gemini"], timeout: 5)?
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines),
           !discovered.isEmpty {
            executableCandidates.append(discovered)
        }
        executableCandidates.append("/opt/homebrew/bin/gemini")
        executableCandidates.append("/usr/local/bin/gemini")

        for executablePath in executableCandidates {
            guard FileManager.default.fileExists(atPath: executablePath) else { continue }
            let binaryURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()

            appendUnique(binaryURL.path)
            let binaryDirectory = binaryURL.deletingLastPathComponent()
            appendUnique(binaryDirectory.appendingPathComponent("../lib/auth/oauth2.js").standardizedFileURL.path)
            appendUnique(binaryDirectory.appendingPathComponent("../dist/auth/oauth2.js").standardizedFileURL.path)
            appendUnique(binaryDirectory.appendingPathComponent("../build/auth/oauth2.js").standardizedFileURL.path)
            appendUnique(binaryDirectory.appendingPathComponent("oauth2.js").standardizedFileURL.path)
            appendBundleSources(in: binaryDirectory)
        }

        appendBundleSources(in: URL(fileURLWithPath: "/opt/homebrew/lib/node_modules/@google/gemini-cli/bundle", isDirectory: true))
        appendBundleSources(in: URL(fileURLWithPath: "/usr/local/lib/node_modules/@google/gemini-cli/bundle", isDirectory: true))
        appendBundleSources(in: URL(fileURLWithPath: "\(NSHomeDirectory())/.npm-global/lib/node_modules/@google/gemini-cli/bundle", isDirectory: true))

        return paths
    }

    internal static func parseClientSecrets(in source: String) -> (id: String, secret: String)? {
        if let clientID = firstMatch(in: source, pattern: #"OAUTH_CLIENT_ID\s*=\s*["']([^"']+)["']"#),
           let clientSecret = firstMatch(in: source, pattern: #"OAUTH_CLIENT_SECRET\s*=\s*["']([^"']+)["']"#) {
            return (clientID, clientSecret)
        }

        if let clientID = firstMatch(in: source, pattern: #"client[_-]?id["']?\s*[:=]\s*["']([^"']+)["']"#),
           let clientSecret = firstMatch(in: source, pattern: #"client[_-]?secret["']?\s*[:=]\s*["']([^"']+)["']"#) {
            return (clientID, clientSecret)
        }

        return nil
    }

    private static func firstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: source.utf16.count)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        let value = String(source[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func requestJSON(
        url: URL,
        accessToken: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Gemini non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Gemini http \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Gemini response decode failed")
        }
        return json
    }

    private func resolveProjectName(accessToken: String, projectID: String) async throws -> String {
        guard let url = URL(string: "https://cloudresourcemanager.googleapis.com/v1/projects/\(projectID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectID)") else {
            return projectID
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return projectID
        }
        return OfficialValueParser.string(json["name"] ?? json["projectName"]) ?? projectID
    }

    internal static func parseQuotaSnapshot(
        root: [String: Any],
        codeAssistRoot: [String: Any],
        descriptor: ProviderDescriptor,
        sourceLabel: String,
        accountLabel: String?,
        projectLabel: String?
    ) throws -> UsageSnapshot {
        try parseQuotaSnapshot(
            root: root,
            plan: parsePlan(from: codeAssistRoot) ?? "unknown",
            descriptor: descriptor,
            sourceLabel: sourceLabel,
            accountLabel: accountLabel,
            projectLabel: projectLabel
        )
    }

    internal static func parseQuotaSnapshot(
        root: [String: Any],
        plan: String,
        descriptor: ProviderDescriptor,
        sourceLabel: String,
        accountLabel: String?,
        projectLabel: String?
    ) throws -> UsageSnapshot {
        let quotas = extractQuotaEntries(from: root)
        guard !quotas.isEmpty else {
            throw ProviderError.invalidResponse("missing Gemini quota entries")
        }

        var grouped: [String: GeminiQuotaEntry] = [:]
        for entry in quotas {
            let key = entry.groupKey
            if let current = grouped[key] {
                if entry.remainingPercent < current.remainingPercent {
                    grouped[key] = entry
                }
            } else {
                grouped[key] = entry
            }
        }

        let sorted = grouped.values.sorted { lhs, rhs in
            lhs.sortRank == rhs.sortRank ? lhs.title < rhs.title : lhs.sortRank < rhs.sortRank
        }

        let windows = sorted.map { entry in
            UsageQuotaWindow(
                id: "\(descriptor.id)-\(entry.groupKey)",
                title: entry.title,
                remainingPercent: entry.remainingPercent,
                usedPercent: entry.usedPercent,
                resetAt: entry.resetAt,
                kind: .custom
            )
        }

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        var extras: [String: String] = ["planType": plan]
        if let projectLabel, !projectLabel.isEmpty {
            extras["project"] = projectLabel
        }
        let rawMeta = buildRawModelMeta(entries: quotas)

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: buildNote(plan: plan, windows: windows, projectLabel: projectLabel),
            quotaWindows: windows,
            sourceLabel: sourceLabel,
            accountLabel: accountLabel,
            extras: extras,
            rawMeta: rawMeta
        )
    }

    private static func parsePlan(from root: [String: Any]) -> String? {
        let currentTier = root["currentTier"] as? [String: Any]
        let paidTier = root["paidTier"] as? [String: Any]
        let raw = firstNonEmptyString([
            root["tierId"],
            root["tier"],
            root["plan"],
            root["codeAssistTier"],
            currentTier?["id"],
            currentTier?["name"],
            paidTier?["id"],
            paidTier?["name"],
        ])
        guard let raw else { return nil }
        switch raw.lowercased() {
        case let value where value.contains("pro"):
            return "pro"
        case let value where value.contains("standard"):
            return "standard"
        case let value where value.contains("free"):
            return "free"
        default:
            return raw
        }
    }

    private static func extractQuotaEntries(from root: [String: Any]) -> [GeminiQuotaEntry] {
        let keys = ["quotaInfos", "quota_infos", "quotas", "modelQuotas", "quotaInfo", "buckets", "quotaBuckets", "quota_buckets"]
        var entries: [GeminiQuotaEntry] = []

        for key in keys {
            guard let items = root[key] as? [Any] else { continue }
            for item in items {
                if let entry = parseQuotaEntry(item) {
                    entries.append(entry)
                }
            }
        }

        if entries.isEmpty {
            for (_, value) in root {
                if let items = value as? [Any] {
                    for item in items {
                        if let entry = parseQuotaEntry(item) {
                            entries.append(entry)
                        }
                    }
                }
            }
        }

        return entries
    }

    private static func parseQuotaEntry(_ value: Any) -> GeminiQuotaEntry? {
        guard let item = value as? [String: Any] else { return nil }
        let rawTitle = OfficialValueParser.string(
            item["displayName"] ??
                item["modelName"] ??
                item["modelId"] ??
                item["model_id"] ??
                item["quotaId"] ??
                item["name"] ??
                item["title"] ??
                item["id"]
        ) ?? "Quota"
        let modelID = OfficialValueParser.string(
            item["modelId"] ??
                item["model_id"] ??
                item["quotaId"] ??
                item["id"] ??
                item["name"]
        ) ?? rawTitle

        let lower = rawTitle.lowercased()
        let groupKey: String
        let normalizedTitle: String
        let sortRank: Int
        if lower.contains("flash") {
            groupKey = "flash"
            normalizedTitle = "Flash"
            sortRank = 1
        } else if lower.contains("pro") {
            groupKey = "pro"
            normalizedTitle = "Pro"
            sortRank = 0
        } else {
            groupKey = "other-\(rawTitle.replacingOccurrences(of: " ", with: "-").lowercased())"
            normalizedTitle = rawTitle
            sortRank = 2
        }

        let candidateDictionaries = [
            item,
            item["usage"] as? [String: Any],
            item["quota"] as? [String: Any],
            item["window"] as? [String: Any],
            item["bucket"] as? [String: Any],
        ].compactMap { $0 }

        var usedPercent: Double?
        var resetAt: Date?
        for dict in candidateDictionaries {
            usedPercent = usedPercent ?? parseUsedPercent(dict: dict)
            resetAt = resetAt ?? parseResetAt(dict: dict)
        }

        guard let usedPercent else { return nil }
        return GeminiQuotaEntry(
            modelID: modelID,
            rawTitle: rawTitle,
            title: normalizedTitle,
            groupKey: groupKey,
            usedPercent: min(100, max(0, usedPercent)),
            remainingPercent: max(0, 100 - usedPercent),
            resetAt: resetAt,
            sortRank: sortRank
        )
    }

    private static func parseUsedPercent(dict: [String: Any]) -> Double? {
        let keys = ["utilization", "usedPercent", "used_percent", "percentage", "percentUsed", "percent", "usageRatio"]
        for key in keys {
            guard let value = OfficialValueParser.double(dict[key]) else { continue }
            return value <= 1 ? value * 100 : value
        }

        let remainingFractionKeys = ["remainingFraction", "remaining_fraction", "remainingRatio", "remaining_ratio", "fractionRemaining"]
        for key in remainingFractionKeys {
            guard let value = OfficialValueParser.double(dict[key]) else { continue }
            let remainingPercent = value <= 1 ? value * 100 : value
            return 100 - remainingPercent
        }

        let remaining = OfficialValueParser.double(
            dict["remainingAmount"] ??
                dict["remaining_amount"] ??
                dict["remaining"]
        )
        let limit = OfficialValueParser.double(
            dict["limitAmount"] ??
                dict["limit_amount"] ??
                dict["quotaAmount"] ??
                dict["quota_amount"] ??
                dict["totalAmount"] ??
                dict["total_amount"] ??
                dict["limit"] ??
                dict["quota"] ??
                dict["total"]
        )
        if let remaining, let limit, limit > 0 {
            return (1 - (remaining / limit)) * 100
        }
        return nil
    }

    private static func parseResetAt(dict: [String: Any]) -> Date? {
        if let raw = OfficialValueParser.string(
            dict["resetsAt"] ??
                dict["resetAt"] ??
                dict["reset_at"] ??
                dict["nextResetAt"] ??
                dict["resetTime"] ??
                dict["reset_time"]
        ) {
            return OfficialValueParser.isoDate(raw) ?? OfficialValueParser.epochDate(seconds: raw)
        }
        return OfficialValueParser.epochDate(seconds: dict["reset_at"])
    }

    private static func firstNonEmptyString(_ values: [Any?]) -> String? {
        for value in values {
            guard let text = OfficialValueParser.string(value) else { continue }
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private static func buildNote(plan: String, windows: [UsageQuotaWindow], projectLabel: String?) -> String {
        let details = windows
            .map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }
            .joined(separator: " | ")
        if let projectLabel, !projectLabel.isEmpty {
            return "Plan \(plan) | \(projectLabel) | \(details)"
        }
        return "Plan \(plan) | \(details)"
    }

    private static func buildRawModelMeta(entries: [GeminiQuotaEntry]) -> [String: String] {
        var output: [String: String] = [:]
        let formatter = ISO8601DateFormatter()
        let sorted = entries.sorted { lhs, rhs in
            if lhs.modelID == rhs.modelID {
                return lhs.rawTitle < rhs.rawTitle
            }
            return lhs.modelID < rhs.modelID
        }
        output["gemini.rawModel.count"] = String(sorted.count)
        for (index, entry) in sorted.enumerated() {
            let prefix = "gemini.rawModel.\(index)"
            output["\(prefix).id"] = entry.modelID
            output["\(prefix).title"] = entry.rawTitle
            output["\(prefix).remainingPercent"] = String(format: "%.2f", entry.remainingPercent)
            output["\(prefix).usedPercent"] = String(format: "%.2f", entry.usedPercent)
            if let resetAt = entry.resetAt {
                output["\(prefix).resetAt"] = formatter.string(from: resetAt)
            }
        }
        return output
    }
}

private struct GeminiSettings {
    var authType: String
    var selectedProject: String?
}

private struct GeminiCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var idToken: String?
    var filePath: String

    var accountLabel: String? {
        guard let idToken else { return nil }
        return decodeJWTEmail(idToken)
    }

    private func decodeJWTEmail(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return OfficialValueParser.string(json["email"])
    }
}

private struct GeminiQuotaEntry {
    let modelID: String
    let rawTitle: String
    let title: String
    let groupKey: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetAt: Date?
    let sortRank: Int
}

/// Account/project context resolved from `loadCodeAssist` (§8.4). Cached
/// in-process per account + selected project so repeated refreshes only
/// re-issue `retrieveUserQuota`.
struct GeminiCodeAssistContext: Equatable, Sendable {
    let projectID: String?
    let projectLabel: String?
    let plan: String
}

/// Process-wide in-process cache for `GeminiCodeAssistContext`. The context
/// (project / account info) and the plan tier metadata each carry their own
/// TTL; both are far longer than the quota snapshot TTL (§8.4).
actor GeminiCodeAssistContextCache {
    private struct Entry {
        let context: GeminiCodeAssistContext
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let contextTTL: TimeInterval
    private let planMetadataTTL: TimeInterval
    private let now: @Sendable () -> Date

    init(
        contextTTL: TimeInterval = GeminiProvider.contextTTL,
        planMetadataTTL: TimeInterval = GeminiProvider.planMetadataTTL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.contextTTL = max(0, contextTTL)
        self.planMetadataTTL = max(0, planMetadataTTL)
        self.now = now
    }

    func contextIfFresh(forKey key: String) -> GeminiCodeAssistContext? {
        guard let entry = entries[key],
              now().timeIntervalSince(entry.fetchedAt) <= contextTTL else {
            return nil
        }
        return entry.context
    }

    func planIfFresh(forKey key: String) -> String? {
        guard let entry = entries[key],
              now().timeIntervalSince(entry.fetchedAt) <= planMetadataTTL else {
            return nil
        }
        return entry.context.plan
    }

    func store(_ context: GeminiCodeAssistContext, forKey key: String) {
        entries[key] = Entry(context: context, fetchedAt: now())
    }
}
