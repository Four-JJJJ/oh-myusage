import OhMyUsageDomain
import Foundation
import Dispatch
import CryptoKit
import OhMyUsageProviders

final class CodexProvider: UsageProvider, @unchecked Sendable {
    private static let cache = FetchedAtOfficialSnapshotCache()
    private static let gate = SerialOfficialFetchGate()
    private static let webReadBackoff = WebOverlayRetryBackoff()

    private let cacheTTL: TimeInterval = 15
    private let refreshAge: TimeInterval = 8 * 24 * 60 * 60
    private let webRetryBackoffInterval: TimeInterval = 15 * 60
    let descriptor: ProviderDescriptor
    private let session: URLSession
    private let keychain: any TokenCredentialStoring
    private let browserCookieService: any BrowserCookieDetecting
    private let webReadBackoff: WebOverlayRetryBackoff
    private let cache: any OfficialSnapshotCaching
    private let gate: any OfficialFetchGating
    private let homeDirectory: () -> String
    private let environment: () -> [String: String]

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: any TokenCredentialStoring,
        browserCookieService: any BrowserCookieDetecting,
        webReadBackoff: WebOverlayRetryBackoff = CodexProvider.webReadBackoff,
        cache: any OfficialSnapshotCaching = CodexProvider.cache,
        gate: any OfficialFetchGating = CodexProvider.gate,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCookieService = browserCookieService
        self.webReadBackoff = webReadBackoff
        self.cache = cache
        self.gate = gate
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        let lookupCacheKey = cacheKeyForCurrentContext()
        return try await OfficialProviderFetchRuntime.fetch(
            forceRefresh: forceRefresh,
            cacheLookupKey: lookupCacheKey,
            ttl: cacheTTL,
            cache: cache,
            gate: gate,
            cacheStoreKey: { [self] in cacheKeyForCurrentContext() },
            load: { [self] in try await loadSnapshot(forceRefresh: forceRefresh) }
        )
    }

    private func loadSnapshot(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .codex)
        let includeWebOverlay = shouldIncludeWebOverlay(for: official)
        switch official.sourceMode {
        case .api:
            return try await loadFromAPI(includeWebOverlay: includeWebOverlay, forceRefresh: forceRefresh)
        case .cli:
            return try await loadFromCLI(forceRefresh: forceRefresh)
        case .web:
            return try await loadFromWeb(forceRefresh: forceRefresh)
        case .auto:
            do {
                return try await loadFromAPI(includeWebOverlay: includeWebOverlay, forceRefresh: forceRefresh)
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
        var didRefreshBeforeRequest = false
        if needsRefresh(lastRefresh: credentials.lastRefresh) {
            do {
                credentials = try await refresh(credentials: credentials)
                didRefreshBeforeRequest = true
            } catch let error as ProviderError {
                if case .unauthorized = error {
                    throw error
                }
            } catch {
                // Best effort; use existing token before failing hard.
            }
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await requestUsage(
                authorization: .bearer(credentials.accessToken),
                accountId: credentials.accountId
            )
        } catch let error as ProviderError {
            guard case .unauthorized = error, !didRefreshBeforeRequest else {
                throw error
            }
            credentials = try await refresh(credentials: credentials)
            (data, response) = try await requestUsage(
                authorization: .bearer(credentials.accessToken),
                accountId: credentials.accountId
            )
        }
        var snapshot = try Self.parseUsageSnapshot(
            data: data,
            response: response,
            descriptor: descriptor,
            sourceLabel: "API",
            accountLabel: credentials.accountLabel
        )
        Self.applyCodexIdentityMetadata(
            to: &snapshot,
            accountID: credentials.accountId,
            subject: credentials.accountSubject,
            accountLabel: credentials.accountLabel,
            fingerprint: Self.credentialFingerprint(credentials.accessToken)
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
        let rpcSnapshot = try runCodexRPCSnapshot()
        var snapshot = rpcSnapshot
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .codex)

        if shouldIncludeWebOverlay(for: official),
           let webSnapshot = try? await loadWebSnapshot(forceRefresh: forceRefresh) {
            snapshot = OfficialProviderWebOverlayRuntime.merge(
                primary: snapshot,
                overlay: webSnapshot,
                sourceLabel: "CLI-RPC+Web"
            )
        }

        return snapshot
    }

    private func loadFromWeb(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await loadWebSnapshot(forceRefresh: forceRefresh)
    }

    private func loadWebSnapshot(forceRefresh: Bool) async throws -> UsageSnapshot {
        let cookie = try await resolveCodexCookieHeader(forceRefresh: forceRefresh)
        let (data, response) = try await requestUsage(
            authorization: .cookie(cookie.header),
            accountId: nil
        )
        var snapshot = try Self.parseUsageSnapshot(
            data: data,
            response: response,
            descriptor: descriptor,
            sourceLabel: "Web",
            accountLabel: nil
        )
        snapshot.extras["webCookieSource"] = cookie.source
        Self.applyCodexIdentityMetadata(
            to: &snapshot,
            accountID: nil,
            subject: nil,
            accountLabel: nil,
            fingerprint: Self.credentialFingerprint(cookie.header)
        )
        return snapshot
    }

    private func loadCredentials() throws -> CodexCredentials {
        for path in resolveAuthPaths() {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let credentials = parseCredentials(json: json, source: .file(path)) else {
                continue
            }
            return credentials
        }

        if let raw = SecurityCredentialReader.readGenericPassword(service: "Codex Auth"),
           let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let credentials = parseCredentials(json: json, source: .keychain) {
            return credentials
        }

        throw ProviderError.missingCredential("~/.codex/auth.json")
    }

    private func parseCredentials(json: [String: Any], source: CodexCredentialSource) -> CodexCredentials? {
        guard let tokens = json["tokens"] as? [String: Any] else { return nil }
        guard let accessToken = OfficialValueParser.string(tokens["access_token"] ?? tokens["accessToken"]),
              !accessToken.isEmpty else {
            return nil
        }
        let refreshToken = OfficialValueParser.string(tokens["refresh_token"] ?? tokens["refreshToken"])
        let accountId = OfficialValueParser.string(tokens["account_id"] ?? tokens["accountId"])
        let idToken = OfficialValueParser.string(tokens["id_token"] ?? tokens["idToken"])
        let lastRefresh = OfficialValueParser.isoDate(OfficialValueParser.string(json["last_refresh"]))
        return CodexCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: accountId,
            idToken: idToken,
            lastRefresh: lastRefresh,
            source: source
        )
    }

    private func resolveAuthPaths() -> [String] {
        Self.resolvedAuthPaths(
            homeDirectory: homeDirectory(),
            environment: environment()
        )
    }

    static func resolvedAuthPaths(homeDirectory: String, environment: [String: String]) -> [String] {
        CodexAuthPathResolver.resolveAuthPaths(
            homeDirectory: homeDirectory,
            environment: environment
        )
    }

    private func needsRefresh(lastRefresh: Date?) -> Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > refreshAge
    }

    private func cacheKeyForCurrentContext() -> String {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .codex)
        var components = [
            descriptor.id,
            "source=\(official.sourceMode.rawValue)",
            "web=\(official.webMode.rawValue)"
        ]

        if official.sourceMode != .web, let credentialIdentity = currentCredentialCacheIdentity() {
            components.append("credential=\(credentialIdentity)")
        }
        if official.webMode != .disabled {
            if let cookieIdentity = currentManualCookieCacheIdentity(for: official) {
                components.append("cookie=\(cookieIdentity)")
            } else if let manualCookieAccount = official.manualCookieAccount,
                      !manualCookieAccount.isEmpty {
                components.append("cookieAccount=\(manualCookieAccount)")
            }
        }

        return components.joined(separator: "|")
    }

    private func currentCredentialCacheIdentity() -> String? {
        guard let credentials = try? loadCredentials() else { return nil }
        var components: [String] = []
        if let accountID = CodexIdentity.trimmed(credentials.accountId) {
            components.append("account=\(accountID)")
        }
        if let subject = CodexIdentity.trimmed(credentials.accountSubject) {
            components.append("subject=\(subject)")
        }
        if let fingerprint = Self.credentialFingerprint(credentials.accessToken) {
            components.append("fingerprint=\(fingerprint)")
        }
        return components.isEmpty ? nil : components.joined(separator: ",")
    }

    private func currentManualCookieCacheIdentity(for official: OfficialProviderConfig) -> String? {
        guard let account = official.manualCookieAccount,
              !account.isEmpty,
              let header = keychain.readToken(service: TokenCredentialStoreServiceNames.defaultServiceName, account: account),
              !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return Self.credentialFingerprint(header)
    }

    private func refresh(credentials: CodexCredentials) async throws -> CodexCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw ProviderError.unauthorized
        }

        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OfficialProviderAuthRuntime.urlEncodedFormData([
            "grant_type": "refresh_token",
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "refresh_token": refreshToken,
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
        updated.idToken = OfficialValueParser.string(refresh.json["id_token"]) ?? credentials.idToken
        updated.lastRefresh = Date()

        if case let .file(path) = credentials.source {
            persist(credentials: updated, toFile: path)
        }

        return updated
    }

    private func persist(credentials: CodexCredentials, toFile path: String) {
        OfficialProviderAuthRuntime.updateJSONObjectFile(path: path) { json in
            var tokens = (json["tokens"] as? [String: Any]) ?? [:]
            tokens["access_token"] = credentials.accessToken
            tokens["refresh_token"] = credentials.refreshToken
            tokens["account_id"] = credentials.accountId
            tokens["id_token"] = credentials.idToken
            json["tokens"] = tokens
            json["last_refresh"] = ISO8601DateFormatter().string(from: credentials.lastRefresh ?? Date())
        }
    }

    private enum UsageAuthorization {
        case bearer(String)
        case cookie(String)
    }

    private func requestUsage(authorization: UsageAuthorization, accountId: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        switch authorization {
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .cookie(let header):
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }

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
        return (data, http)
    }

    internal static func parseUsageSnapshot(
        data: Data,
        response: HTTPURLResponse,
        descriptor: ProviderDescriptor,
        sourceLabel: String,
        accountLabel: String?,
        receivedAt: Date = Date()
    ) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("usage decode failed")
        }

        let rateLimit = root["rate_limit"] as? [String: Any]
        let primary = rateLimit?["primary_window"] as? [String: Any]
        let secondary = rateLimit?["secondary_window"] as? [String: Any]
        let review = (root["code_review_rate_limit"] as? [String: Any])?["primary_window"] as? [String: Any]

        let primaryUsed = OfficialValueParser.double(primary?["used_percent"])
            ?? OfficialValueParser.double(response.value(forHTTPHeaderField: "x-codex-primary-used-percent"))
        let secondaryUsed = OfficialValueParser.double(secondary?["used_percent"])
            ?? OfficialValueParser.double(response.value(forHTTPHeaderField: "x-codex-secondary-used-percent"))
        let clockSkew = OfficialValueParser.clockSkew(response: response, localReceiveAt: receivedAt)

        var windows: [UsageQuotaWindow] = []
        if let primaryUsed {
            windows.append(.init(
                id: "\(descriptor.id)-session",
                title: "5h",
                remainingPercent: max(0, 100 - primaryUsed),
                usedPercent: primaryUsed,
                resetAt: OfficialValueParser.applyClockSkew(
                    OfficialValueParser.epochDate(seconds: primary?["reset_at"]),
                    skew: clockSkew
                ),
                kind: .session
            ))
        }
        if let secondaryUsed {
            windows.append(.init(
                id: "\(descriptor.id)-weekly",
                title: "Weekly",
                remainingPercent: max(0, 100 - secondaryUsed),
                usedPercent: secondaryUsed,
                resetAt: OfficialValueParser.applyClockSkew(
                    OfficialValueParser.epochDate(seconds: secondary?["reset_at"]),
                    skew: clockSkew
                ),
                kind: .weekly
            ))
        }
        if let reviewUsed = OfficialValueParser.double(review?["used_percent"]) {
            windows.append(.init(
                id: "\(descriptor.id)-reviews",
                title: "Reviews",
                remainingPercent: max(0, 100 - reviewUsed),
                usedPercent: reviewUsed,
                resetAt: OfficialValueParser.applyClockSkew(
                    OfficialValueParser.epochDate(seconds: review?["reset_at"]),
                    skew: clockSkew
                ),
                kind: .reviews
            ))
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("missing Codex usage windows")
        }

        let remaining = windows.map(\.remainingPercent).min()
        let used = windows.first(where: { $0.kind == .session })?.usedPercent ?? (remaining.map { 100 - $0 })
        let plan = OfficialValueParser.string(root["plan_type"]) ?? "unknown"
        let credits = OfficialValueParser.double((root["credits"] as? [String: Any])?["balance"])
            ?? OfficialValueParser.double(response.value(forHTTPHeaderField: "x-codex-credits-balance"))
        var extras: [String: String] = ["planType": plan]
        if let credits {
            extras["creditsBalance"] = String(format: "%.2f", credits)
        }
        let note = buildNote(plan: plan, windows: windows, credits: credits)
        let status: SnapshotStatus = (remaining ?? 100) <= descriptor.threshold.lowRemaining ? .warning : .ok
        return UsageSnapshot(
            source: descriptor.id,
            status: status,
            remaining: remaining,
            used: used,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: note,
            quotaWindows: windows,
            sourceLabel: sourceLabel,
            accountLabel: accountLabel,
            extras: extras,
            rawMeta: [
                "planType": plan,
                "creditsBalance": extras["creditsBalance"] ?? ""
            ]
        )
    }

    private static func buildNote(plan: String, windows: [UsageQuotaWindow], credits: Double?) -> String {
        var parts = ["Plan \(plan)"]
        for window in windows.prefix(3) {
            parts.append("\(window.title) \(Int(window.remainingPercent.rounded()))%")
        }
        if let credits {
            parts.append("Credits \(String(format: "%.2f", credits))")
        }
        return parts.joined(separator: " | ")
    }

    private static func applyCodexIdentityMetadata(
        to snapshot: inout UsageSnapshot,
        accountID: String?,
        subject: String?,
        accountLabel: String?,
        fingerprint: String?
    ) {
        if let accountID = CodexIdentity.trimmed(accountID) {
            snapshot.rawMeta["codex.accountId"] = accountID
            snapshot.rawMeta["codex.teamId"] = accountID
        }
        if let subject = CodexIdentity.trimmed(subject) {
            snapshot.rawMeta["codex.subject"] = subject
        }
        if let accountLabel = CodexIdentity.trimmed(accountLabel) {
            snapshot.rawMeta["codex.accountLabel"] = accountLabel
            if snapshot.accountLabel == nil || snapshot.accountLabel?.isEmpty == true {
                snapshot.accountLabel = accountLabel
            }
        }
        if let fingerprint = CodexIdentity.trimmed(fingerprint) {
            snapshot.rawMeta["codex.credentialFingerprint"] = fingerprint
        }

        let identity = CodexIdentity.from(snapshot: snapshot)
        snapshot.rawMeta["codex.tenantKey"] = identity.tenantKey
        snapshot.rawMeta["codex.principalKey"] = identity.principalKey
        snapshot.rawMeta["codex.identityKey"] = identity.identityKey
    }

    private func resolveCodexCookieHeader(forceRefresh: Bool) async throws -> BrowserCookieHeader {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .codex)
        return try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: official,
            descriptorID: descriptor.id,
            keychain: keychain,
            browserCookieService: browserCookieService,
            webReadBackoff: webReadBackoff,
            webRetryBackoffInterval: webRetryBackoffInterval,
            forceRefresh: forceRefresh,
            strategy: OfficialBrowserCookieImportStrategy(
                providerKey: "codex",
                hostContains: "chatgpt.com",
                namedCookie: nil,
                autoImportMissingCredential: "chatgpt.com cookie",
                manualCredentialFallback: "official/codex/cookie-header",
                normalizeManualHeader: { raw in
                    let header = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    return header.isEmpty ? nil : header
                },
                normalizeDetectedHeader: { header in
                    let normalized = header.trimmingCharacters(in: .whitespacesAndNewlines)
                    return normalized.isEmpty ? nil : normalized
                }
            )
        )
    }

    private func shouldIncludeWebOverlay(for official: OfficialProviderConfig) -> Bool {
        guard official.webMode != .disabled else { return false }
        guard OfficialProviderWebOverlayRuntime.hasStoredManualCookie(
            official: official,
            keychain: keychain,
            normalizeManualHeader: { raw in
                let header = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return header.isEmpty ? nil : header
            }
        ) else {
            // Avoid triggering browser keychain prompts in background polling.
            // Auto import still works when user explicitly uses web source mode.
            return false
        }
        return true
    }

    private func runCodexRPCSnapshot() throws -> UsageSnapshot {
        var responses = try runCodexRPC(keepAliveSeconds: 3.0)
        if responses["2"] == nil || responses["3"] == nil {
            responses = try runCodexRPC(keepAliveSeconds: 10.0)
        }
        if responses["2"] == nil || responses["3"] == nil {
            responses = try runCodexRPC(keepAliveSeconds: 18.0)
        }

        guard let accountResult = responses["2"] else {
            throw ProviderError.invalidResponse("missing account/read response")
        }

        guard let limitsResult = responses["3"] else {
            throw ProviderError.invalidResponse("missing account/rateLimits/read response")
        }

        let accountData = try JSONSerialization.data(withJSONObject: accountResult)
        let limitsData = try JSONSerialization.data(withJSONObject: limitsResult)

        let account = try JSONDecoder().decode(CodexAccountReadResult.self, from: accountData)
        let limits = try JSONDecoder().decode(CodexRateLimitsReadResult.self, from: limitsData)

        let primaryUsed = limits.rateLimits.primary.usedPercent
        let secondaryUsed = limits.rateLimits.secondary.usedPercent
        let primaryRemaining = max(0, 100 - primaryUsed)
        let secondaryRemaining = max(0, 100 - secondaryUsed)
        let status: SnapshotStatus = min(primaryRemaining, secondaryRemaining) <= descriptor.threshold.lowRemaining ? .warning : .ok
        let plan = account.account.planType ?? "unknown"

        let windows = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-session",
                title: "5h",
                remainingPercent: primaryRemaining,
                usedPercent: primaryUsed,
                resetAt: Date(timeIntervalSince1970: limits.rateLimits.primary.resetsAt),
                kind: .session
            ),
            UsageQuotaWindow(
                id: "\(descriptor.id)-weekly",
                title: "Weekly",
                remainingPercent: secondaryRemaining,
                usedPercent: secondaryUsed,
                resetAt: Date(timeIntervalSince1970: limits.rateLimits.secondary.resetsAt),
                kind: .weekly
            )
        ]

        var snapshot = UsageSnapshot(
            source: descriptor.id,
            status: status,
            remaining: min(primaryRemaining, secondaryRemaining),
            used: primaryUsed,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Plan \(plan) | 5h \(Int(primaryRemaining))% | Weekly \(Int(secondaryRemaining))%",
            quotaWindows: windows,
            sourceLabel: "CLI-RPC",
            accountLabel: account.account.email,
            extras: [
                "planType": plan,
                "creditsBalance": limits.rateLimits.credits.balance
            ],
            rawMeta: [
                "planType": plan,
                "creditsBalance": limits.rateLimits.credits.balance,
                "codex.accountLabel": account.account.email ?? ""
            ]
        )
        Self.applyCodexIdentityMetadata(
            to: &snapshot,
            accountID: nil,
            subject: nil,
            accountLabel: account.account.email,
            fingerprint: nil
        )
        return snapshot
    }

    private func runCodexRPC(keepAliveSeconds: TimeInterval) throws -> [String: [String: Any]] {
        guard let codexPath = resolveCodexExecutablePath() else {
            throw ProviderError.unavailable("Unable to locate codex CLI. Set CODEX_CLI_PATH or install Codex.app.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        try process.run()

        let messages = [
            #"{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"OhMyUsage","version":"0.2"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
            #"{"jsonrpc":"2.0","id":"2","method":"account/read","params":{}}"#,
            #"{"jsonrpc":"2.0","id":"3","method":"account/rateLimits/read","params":{}}"#
        ]

        let payload = messages.joined(separator: "\n") + "\n"
        if let data = payload.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }

        Thread.sleep(forTimeInterval: keepAliveSeconds)
        try? inputPipe.fileHandleForWriting.close()

        var forceTerminated = false
        let waitResult = terminated.wait(timeout: .now() + max(14.0, keepAliveSeconds + 8.0))
        if waitResult == .timedOut {
            forceTerminated = true
            process.terminate()
            if terminated.wait(timeout: .now() + 1.0) == .timedOut {
                process.interrupt()
                _ = terminated.wait(timeout: .now() + 1.0)
            }
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard let outputText = String(data: outputData, encoding: .utf8) else {
            throw ProviderError.invalidResponse("stdout is not UTF-8")
        }

        var resultsByID: [String: [String: Any]] = [:]

        for line in outputText.split(separator: "\n") {
            guard line.first == "{" else { continue }
            guard let data = String(line).data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ProviderError.invalidResponse(message)
            }

            let id: String?
            if let stringID = json["id"] as? String {
                id = stringID
            } else if let intID = json["id"] as? Int {
                id = String(intID)
            } else if let numericID = json["id"] as? NSNumber {
                id = numericID.stringValue
            } else {
                id = nil
            }

            guard let id,
                  let result = json["result"] as? [String: Any] else {
                continue
            }

            resultsByID[id] = result
        }

        if process.terminationStatus != 0 && !forceTerminated {
            let stderr = String(data: errData, encoding: .utf8) ?? "unknown stderr"
            throw ProviderError.commandFailed(stderr)
        }

        if resultsByID["2"] == nil || resultsByID["3"] == nil {
            if forceTerminated {
                throw ProviderError.timeout("codex app-server timeout")
            }
            throw ProviderError.invalidResponse("missing account/read or account/rateLimits/read response")
        }

        return resultsByID
    }

    private func resolveCodexExecutablePath() -> String? {
        let manager = FileManager.default

        let explicit = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"]
        let staticCandidates: [String] = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]

        let envPath = ProcessInfo.processInfo.environment["PATH"]
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let pathCandidates = envPath
            .split(separator: ":")
            .map { "\($0)/codex" }

        let candidates = [explicit].compactMap { $0 } + staticCandidates + pathCandidates
        for path in candidates where manager.isExecutableFile(atPath: path) {
            if isGuiLauncher(path) {
                continue
            }
            return path
        }
        return nil
    }

    private func isGuiLauncher(_ path: String) -> Bool {
        path.contains("/Applications/Codex.app/Contents/MacOS/codex")
    }

    private static func credentialFingerprint(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

private struct CodexCredentials {
    var accessToken: String
    var refreshToken: String?
    var accountId: String?
    var idToken: String?
    var lastRefresh: Date?
    var source: CodexCredentialSource

    var accountLabel: String? {
        guard let idToken else { return nil }
        return JWTInspector.email(idToken)
    }

    var accountSubject: String? {
        guard let idToken else { return nil }
        return JWTInspector.subject(idToken)
    }
}

private enum CodexCredentialSource {
    case file(String)
    case keychain
}

private struct CodexAccountReadResult: Decodable {
    let account: CodexAccount
}

private struct CodexAccount: Decodable {
    let email: String?
    let planType: String?
}

private struct CodexRateLimitsReadResult: Decodable {
    let rateLimits: CodexRateLimitSet
}

private struct CodexRateLimitSet: Decodable {
    let primary: CodexRateLimitWindowPayload
    let secondary: CodexRateLimitWindowPayload
    let credits: CodexCreditsPayload
}

private struct CodexRateLimitWindowPayload: Decodable {
    let usedPercent: Double
    let resetsAt: TimeInterval
}

private struct CodexCreditsPayload: Decodable {
    let balance: String
}
