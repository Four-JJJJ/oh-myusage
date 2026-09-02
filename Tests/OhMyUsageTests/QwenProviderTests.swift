import OhMyUsageDomain
import XCTest
import OhMyUsageProviders
@testable import OhMyUsage

final class QwenProviderTests: XCTestCase {
    // MARK: - Catalog wiring

    func testQwenCatalogDefaults() {
        let plan = ProviderDescriptor.defaultOfficialQwen()
        XCTAssertEqual(plan.id, "qwen-official")
        XCTAssertEqual(plan.type, .qwen)
        XCTAssertEqual(plan.baseURL, "https://platform.qianwenai.com")
        XCTAssertEqual(plan.officialConfig?.webMode, .autoImport)
        XCTAssertEqual(plan.officialConfig?.manualCookieAccount, QwenProvider.manualCookieAccount)

        let balance = ProviderDescriptor.defaultOfficialQwenBalance()
        XCTAssertEqual(balance.id, "qwen-balance-official")
        XCTAssertEqual(balance.type, .qwenBalance)
        XCTAssertEqual(balance.baseURL, "https://platform.qianwenai.com")
        XCTAssertEqual(balance.officialConfig?.manualCookieAccount, QwenProvider.manualCookieAccount)
    }

    // MARK: - URL helpers

    func testGatewayOriginDerivation() {
        XCTAssertEqual(
            QwenProvider.gatewayOrigin(consoleOrigin: "https://platform.qianwenai.com"),
            "https://platform-home.qianwenai.com"
        )
        XCTAssertEqual(
            QwenProvider.gatewayOrigin(consoleOrigin: ""),
            "https://platform-home.qianwenai.com"
        )
        XCTAssertEqual(
            QwenProvider.gatewayOrigin(consoleOrigin: "https://example.com"),
            "https://example.com"
        )
    }

    func testCookieHostContainsDerivation() {
        XCTAssertEqual(
            QwenProvider.cookieHostContains(consoleOrigin: "https://platform.qianwenai.com"),
            "qianwenai.com"
        )
        XCTAssertEqual(
            QwenProvider.cookieHostContains(consoleOrigin: "https://qianwenai.com"),
            "qianwenai.com"
        )
    }

    // MARK: - Cookie normalization

    func testNormalizeCookieHeader() {
        XCTAssertEqual(
            QwenProvider.normalizeCookieHeader("Cookie: a=1; b=2"),
            "a=1; b=2"
        )
        XCTAssertEqual(QwenProvider.normalizeCookieHeader("  a=1  "), "a=1")
        XCTAssertNil(QwenProvider.normalizeCookieHeader(""))
        XCTAssertNil(QwenProvider.normalizeCookieHeader("no-equals-sign"))
    }

    // MARK: - Gateway envelope

    func testEnvelopeSuccessShapes() {
        XCTAssertTrue(QwenProvider.isEnvelopeSuccess(["successResponse": true]))
        XCTAssertTrue(QwenProvider.isEnvelopeSuccess(["code": "200"]))
        XCTAssertFalse(QwenProvider.isEnvelopeSuccess(["successResponse": false]))
        XCTAssertFalse(QwenProvider.isEnvelopeSuccess(["code": "401"]))
        XCTAssertFalse(QwenProvider.isEnvelopeSuccess([:]))
    }

    func testEnvelopeDataPrefersLowercaseThenUppercase() {
        XCTAssertEqual(
            QwenProvider.envelopeData(["data": ["a": 1], "Data": ["b": 2]])?["a"] as? Int,
            1
        )
        XCTAssertEqual(
            QwenProvider.envelopeData(["Data": ["b": 2]])?["b"] as? Int,
            2
        )
    }

    // MARK: - Coding plan parsing

    func testCodingPlanParsesWeeklyWindowAndPlan() throws {
        let usage: [String: Any] = [
            "data": [
                "per1WeekPercentage": 0.35,
                "per1WeekResetTime": 1_760_000_000_000.0
            ]
        ]
        let subscription: [String: Any] = [
            "data": [
                "specType": "standard",
                "status": "valid",
                "endTime": 1_770_000_000_000.0
            ]
        ]

        let snapshot = try QwenProvider.parseCodingPlanSnapshot(
            usageRoot: usage,
            subscriptionRoot: subscription,
            addonRoot: [:],
            descriptor: ProviderDescriptor.defaultOfficialQwen()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        let weekly = snapshot.quotaWindows[0]
        XCTAssertEqual(weekly.kind, .weekly)
        XCTAssertEqual(weekly.usedPercent, 35, accuracy: 0.001)
        XCTAssertEqual(weekly.remainingPercent, 65, accuracy: 0.001)
        XCTAssertNotNil(weekly.resetAt)
        XCTAssertEqual(snapshot.extras["planType"], "Standard")
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertTrue(snapshot.note.contains("Plan Standard"))
    }

    func testCodingPlanParsesPercentFormPercentage() throws {
        // 上游若直接下发百分数（35 表示 35%），按百分数解析。
        let usage: [String: Any] = ["per1WeekPercentage": 35]

        let snapshot = try QwenProvider.parseCodingPlanSnapshot(
            usageRoot: usage,
            subscriptionRoot: [:],
            addonRoot: [:],
            descriptor: ProviderDescriptor.defaultOfficialQwen()
        )

        XCTAssertEqual(snapshot.quotaWindows.first?.usedPercent ?? -1, 35, accuracy: 0.001)
    }

    func testCodingPlanParsesAddonCreditPacks() throws {
        let addons: [String: Any] = [
            "data": [
                "items": [
                    ["orderId": "1", "remainingCredits": "8000", "totalCredits": "20000", "endTime": 1_770_000_000_000.0],
                    ["orderId": "2", "remainingCredits": 2000, "totalCredits": 20000, "endTime": 1_780_000_000_000.0]
                ]
            ]
        ]

        let snapshot = try QwenProvider.parseCodingPlanSnapshot(
            usageRoot: [:],
            subscriptionRoot: [:],
            addonRoot: addons,
            descriptor: ProviderDescriptor.defaultOfficialQwen()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        let credits = snapshot.quotaWindows[0]
        XCTAssertEqual(credits.kind, .credits)
        XCTAssertEqual(credits.remainingPercent, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["addonRemainingCredits"], "10000")
    }

    func testCodingPlanThrowsWhenNothingAvailable() {
        XCTAssertThrowsError(
            try QwenProvider.parseCodingPlanSnapshot(
                usageRoot: [:],
                subscriptionRoot: [:],
                addonRoot: [:],
                descriptor: ProviderDescriptor.defaultOfficialQwen()
            )
        ) { error in
            guard case ProviderError.unavailable = error else {
                return XCTFail("expected unavailable, got \(error)")
            }
        }
    }

    // MARK: - Balance parsing

    func testBalanceParsesAvailableAmountWithThousandsSeparator() throws {
        let root: [String: Any] = [
            "Data": ["AvailableAmount": "1,234.56"]
        ]

        let snapshot = try QwenProvider.parseBalanceSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialQwenBalance()
        )

        XCTAssertEqual(snapshot.remaining ?? -1, 1234.56, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
    }

    func testBalanceParsesNestedDataContainers() throws {
        // BssOpenAPI 常见形态：envelope.data 内再包一层 Data。
        let root: [String: Any] = [
            "data": ["Data": ["AvailableAmount": 88.5]]
        ]

        let snapshot = try QwenProvider.parseBalanceSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialQwenBalance()
        )

        XCTAssertEqual(snapshot.remaining ?? -1, 88.5, accuracy: 0.001)
    }

    func testBalanceZeroAmountWarns() throws {
        let snapshot = try QwenProvider.parseBalanceSnapshot(
            root: ["data": ["AvailableAmount": "0.00"]],
            descriptor: ProviderDescriptor.defaultOfficialQwenBalance()
        )

        XCTAssertEqual(snapshot.remaining ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.status, .warning)
    }

    func testBalanceMissingFieldsThrows() {
        XCTAssertThrowsError(
            try QwenProvider.parseBalanceSnapshot(
                root: ["data": [:]],
                descriptor: ProviderDescriptor.defaultOfficialQwenBalance()
            )
        ) { error in
            guard case ProviderError.invalidResponse(let message) = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
            XCTAssertTrue(message.contains("AvailableAmount"))
        }
    }

    // MARK: - 余额卡设置页展示

    func testPureBalanceProviderSetCoversAllAPICards() {
        XCTAssertTrue(SettingsView.isPureBalanceProvider(.qwenBalance))
        XCTAssertTrue(SettingsView.isPureBalanceProvider(.zaiBalance))
        XCTAssertTrue(SettingsView.isPureBalanceProvider(.kimiBalance))
        XCTAssertFalse(SettingsView.isPureBalanceProvider(.qwen))
        XCTAssertFalse(SettingsView.isPureBalanceProvider(.zai))
    }

    func testPureBalanceValueTextShowsAmountNotPercent() {
        let descriptor = ProviderDescriptor.defaultOfficialQwenBalance()
        let snapshot = UsageSnapshot(
            source: descriptor.id,
            status: .ok,
            remaining: 88.5,
            used: nil,
            limit: nil,
            unit: "CNY",
            updatedAt: Date(),
            note: "Balance 88.50"
        )
        XCTAssertEqual(SettingsView.pureBalanceValueText(provider: descriptor, snapshot: snapshot), "88.50")
        XCTAssertEqual(SettingsView.pureBalanceValueText(provider: descriptor, snapshot: nil), "-")
    }

    func testPureBalanceHealthPercentMatchesMenuCardThresholds() {
        func snapshot(_ remaining: Double) -> UsageSnapshot {
            UsageSnapshot(
                source: "qwen-balance-official",
                status: .ok,
                remaining: remaining,
                used: nil,
                limit: nil,
                unit: "CNY",
                updatedAt: Date(),
                note: ""
            )
        }
        XCTAssertEqual(SettingsView.pureBalanceHealthPercent(snapshot: snapshot(100)), 100)
        XCTAssertEqual(SettingsView.pureBalanceHealthPercent(snapshot: snapshot(20)), 20)
        XCTAssertEqual(SettingsView.pureBalanceHealthPercent(snapshot: snapshot(0)), 0)
        XCTAssertEqual(SettingsView.pureBalanceHealthPercent(snapshot: nil), 0)
    }
}

// MARK: - Cookie access policy (browser strategy 7.7)

extension QwenProviderTests {
    private static func makeFetchDescriptor() -> ProviderDescriptor {
        var descriptor = ProviderDescriptor.defaultOfficialQwen()
        descriptor.id = "qwen-fetch-\(UUID().uuidString)"
        descriptor.enabled = true
        descriptor.officialConfig?.manualCookieAccount = "official/qwen/cookie-header-\(UUID().uuidString)"
        return descriptor
    }

    private static func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QwenMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func installGatewayHandler(expectedCookie: String) {
        QwenMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), expectedCookie)
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "OhMyUsage")
            let ok = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/tool/user/info.json" {
                return (ok, Data(#"{"successResponse":true,"data":{"secToken":"test-sec-token","nickName":"tester"}}"#.utf8))
            }
            return (ok, Data(#"{"successResponse":true,"data":{"per1WeekPercentage":0.25,"per1WeekResetTime":1800000000000}}"#.utf8))
        }
    }

    func testQwenBackgroundPollUsesVaultCookieWithoutBrowserDetection() async throws {
        let keychain = makeTestKeychain()
        let descriptor = Self.makeFetchDescriptor()
        let account = try XCTUnwrap(descriptor.officialConfig?.manualCookieAccount)
        XCTAssertTrue(keychain.saveToken("sid=vault-cookie; uid=1", service: KeychainService.defaultServiceName, account: account))

        Self.installGatewayHandler(expectedCookie: "sid=vault-cookie; uid=1")
        defer { QwenMockURLProtocol.requestHandler = nil }

        let spy = IntentRecordingBrowserCookieDetector()
        let provider = QwenProvider(
            descriptor: descriptor,
            session: Self.makeMockSession(),
            keychain: keychain,
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.extras["webCookieSource"], "Manual")
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 0, "Background polls must not touch browser cookie stores when the vault cookie is present")
        XCTAssertEqual(spy.recordedIntents.count, 0)
    }

    func testQwenBackgroundPollWithoutVaultCookieUsesBackgroundIntentOnly() async throws {
        let keychain = makeTestKeychain()
        let descriptor = Self.makeFetchDescriptor()

        QwenMockURLProtocol.requestHandler = { _ in
            XCTFail("No cookie should fail before any network request")
            let response = HTTPURLResponse(url: URL(string: "https://platform-home.qianwenai.com/tool/user/info.json")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { QwenMockURLProtocol.requestHandler = nil }

        let spy = IntentRecordingBrowserCookieDetector()
        let provider = QwenProvider(
            descriptor: descriptor,
            session: Self.makeMockSession(),
            keychain: keychain,
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff()
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected missing credential failure")
        } catch {}
        XCTAssertEqual(spy.recordedIntents.map(qwenIntentName), ["background"])

        // A second background poll must not scan again: the missing-cookie
        // result is cached and the backoff keeps retrying bounded.
        do {
            _ = try await provider.fetch()
            XCTFail("Expected missing credential failure")
        } catch {}
        XCTAssertEqual(spy.recordedIntents.map(qwenIntentName), ["background"])
    }

    func testQwenForceRefreshImportsBrowserCookieIntoVault() async throws {
        let keychain = makeTestKeychain()
        let descriptor = Self.makeFetchDescriptor()
        let account = try XCTUnwrap(descriptor.officialConfig?.manualCookieAccount)

        Self.installGatewayHandler(expectedCookie: "sid=fresh-browser-cookie; uid=2")
        defer { QwenMockURLProtocol.requestHandler = nil }

        let spy = IntentRecordingBrowserCookieDetector()
        spy.cookieHeaderResult = BrowserCookieHeader(header: "sid=fresh-browser-cookie; uid=2", source: "Auto:Test")
        let provider = QwenProvider(
            descriptor: descriptor,
            session: Self.makeMockSession(),
            keychain: keychain,
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff()
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.extras["webCookieSource"], "Auto:Test")
        XCTAssertEqual(spy.recordedIntents.map(qwenIntentName), ["interactiveImport"], "User-initiated force refresh is the interactive import path")
        XCTAssertEqual(
            keychain.readToken(service: KeychainService.defaultServiceName, account: account),
            "sid=fresh-browser-cookie; uid=2",
            "Imported cookies are persisted into the app vault under the manual cookie account"
        )

        // Background polls now prefer the vault copy and never re-scan browsers.
        let background = try await provider.fetch()
        XCTAssertEqual(background.extras["webCookieSource"], "Manual")
        XCTAssertEqual(spy.recordedIntents.map(qwenIntentName), ["interactiveImport"])
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)
    }

    private func qwenIntentName(_ intent: BrowserCredentialAccessIntent) -> String {
        switch intent {
        case .background: return "background"
        case .interactiveImport: return "interactiveImport"
        case .authRecovery: return "authRecovery"
        }
    }
}

// MARK: - Session context caching (plan §8.4 Qwen)

extension QwenProviderTests {
    private final class RequestCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]

        func increment(_ key: String) {
            lock.lock()
            counts[key, default: 0] += 1
            lock.unlock()
        }

        func count(_ key: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return counts[key] ?? 0
        }
    }

    private final class GatewayMode: @unchecked Sendable {
        private let lock = NSLock()
        private var authorized = true

        var gatewayAuthorized: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return authorized
            }
            set {
                lock.lock()
                authorized = newValue
                lock.unlock()
            }
        }
    }

    private static func httpResponse(_ request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func sid(from cookieHeader: String) -> String {
        for pair in cookieHeader.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("sid=") {
                return String(trimmed.dropFirst(4))
            }
        }
        return "unknown"
    }

    /// Counting handler: `sec_token`/`nickName` are derived from the request's
    /// `sid` cookie so per-account payloads are distinguishable.
    private static func installSessionCountingHandler(
        counter: RequestCounter,
        mode: GatewayMode? = nil
    ) {
        QwenMockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let sid = Self.sid(from: request.value(forHTTPHeaderField: "Cookie") ?? "")
            if path == "/tool/user/info.json" {
                counter.increment("userInfo|\(sid)")
                let payload = #"{"successResponse":true,"data":{"secToken":"sec-\#(sid)","nickName":"\#(sid)-user"}}"#
                return (Self.httpResponse(request, status: 200), Data(payload.utf8))
            }
            counter.increment("gateway|\(sid)")
            if let mode, !mode.gatewayAuthorized {
                // Gateway envelope carrying a 401-class code (string form is
                // what the envelope error classifier reads).
                return (Self.httpResponse(request, status: 200), Data(#"{"code":"401","message":"login required"}"#.utf8))
            }
            return (
                Self.httpResponse(request, status: 200),
                Data(#"{"successResponse":true,"data":{"per1WeekPercentage":0.25,"per1WeekResetTime":1800000000000}}"#.utf8)
            )
        }
    }

    private static func makeSessionTestProvider(
        descriptor: ProviderDescriptor,
        keychain: KeychainService,
        spy: IntentRecordingBrowserCookieDetector
    ) -> QwenProvider {
        QwenProvider(
            descriptor: descriptor,
            session: Self.makeMockSession(),
            keychain: keychain,
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff()
        )
    }

    private static func saveVaultCookie(_ cookie: String, descriptor: ProviderDescriptor, keychain: KeychainService) throws -> String {
        let account = try XCTUnwrap(descriptor.officialConfig?.manualCookieAccount)
        XCTAssertTrue(keychain.saveToken(cookie, service: KeychainService.defaultServiceName, account: account))
        return account
    }

    func testSecondFetchWithUnchangedCookieSkipsSessionContextRequest() async throws {
        let keychain = makeTestKeychain()
        let descriptor = Self.makeFetchDescriptor()
        try Self.saveVaultCookie("sid=vault-cookie; uid=1", descriptor: descriptor, keychain: keychain)

        let counter = RequestCounter()
        Self.installSessionCountingHandler(counter: counter)
        defer { QwenMockURLProtocol.requestHandler = nil }

        let spy = IntentRecordingBrowserCookieDetector()
        let provider = Self.makeSessionTestProvider(descriptor: descriptor, keychain: keychain, spy: spy)

        let first = try await provider.fetch()
        XCTAssertEqual(first.accountLabel, "vault-cookie-user")
        XCTAssertEqual(first.extras["webCookieSource"], "Manual")
        XCTAssertEqual(counter.count("userInfo|vault-cookie"), 1)
        XCTAssertEqual(counter.count("gateway|vault-cookie"), 3, "usage + subscription + addon list")

        let second = try await provider.fetch()
        XCTAssertEqual(second.accountLabel, "vault-cookie-user", "the cached account label survives the second fetch")
        XCTAssertEqual(second.extras["webCookieSource"], "Manual")
        XCTAssertEqual(counter.count("userInfo|vault-cookie"), 1, "an unchanged cookie must not refetch the session context")
        XCTAssertEqual(counter.count("gateway|vault-cookie"), 6, "quota data is always fetched live")
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 0, "background polls never rescan browser cookie stores while the vault cookie works")
        XCTAssertEqual(spy.recordedIntents.count, 0)
    }

    func testSessionContextRefetchedWhenCookieValueChanges() async throws {
        let keychain = makeTestKeychain()
        let descriptor = Self.makeFetchDescriptor()
        let account = try Self.saveVaultCookie("sid=cookie-v1; uid=1", descriptor: descriptor, keychain: keychain)

        let counter = RequestCounter()
        Self.installSessionCountingHandler(counter: counter)
        defer { QwenMockURLProtocol.requestHandler = nil }

        let provider = Self.makeSessionTestProvider(
            descriptor: descriptor,
            keychain: keychain,
            spy: IntentRecordingBrowserCookieDetector()
        )

        let first = try await provider.fetch()
        XCTAssertEqual(first.accountLabel, "cookie-v1-user")
        XCTAssertEqual(counter.count("userInfo|cookie-v1"), 1)

        XCTAssertTrue(keychain.saveToken("sid=cookie-v2; uid=1", service: KeychainService.defaultServiceName, account: account))
        let second = try await provider.fetch()
        XCTAssertEqual(second.accountLabel, "cookie-v2-user", "a new cookie fingerprint refreshes the session context")
        XCTAssertEqual(counter.count("userInfo|cookie-v1"), 1)
        XCTAssertEqual(counter.count("userInfo|cookie-v2"), 1)
        XCTAssertEqual(counter.count("gateway|cookie-v2"), 3)
    }

    func testSessionContextCacheDoesNotCrossAccounts() async throws {
        let keychain = makeTestKeychain()
        var descriptorA = Self.makeFetchDescriptor()
        descriptorA.id = "qwen-fetch-account-a"
        try Self.saveVaultCookie("sid=alpha; uid=1", descriptor: descriptorA, keychain: keychain)
        var descriptorB = Self.makeFetchDescriptor()
        descriptorB.id = "qwen-fetch-account-b"
        try Self.saveVaultCookie("sid=beta; uid=2", descriptor: descriptorB, keychain: keychain)

        let counter = RequestCounter()
        Self.installSessionCountingHandler(counter: counter)
        defer { QwenMockURLProtocol.requestHandler = nil }

        let providerA = Self.makeSessionTestProvider(
            descriptor: descriptorA,
            keychain: keychain,
            spy: IntentRecordingBrowserCookieDetector()
        )
        let providerB = Self.makeSessionTestProvider(
            descriptor: descriptorB,
            keychain: keychain,
            spy: IntentRecordingBrowserCookieDetector()
        )

        let firstA = try await providerA.fetch()
        XCTAssertEqual(firstA.accountLabel, "alpha-user")
        let firstB = try await providerB.fetch()
        XCTAssertEqual(firstB.accountLabel, "beta-user", "account B must not reuse account A's session context")
        let secondA = try await providerA.fetch()
        XCTAssertEqual(secondA.accountLabel, "alpha-user", "account A keeps serving its own cached context")

        XCTAssertEqual(counter.count("userInfo|alpha"), 1)
        XCTAssertEqual(counter.count("userInfo|beta"), 1)
        XCTAssertEqual(counter.count("gateway|alpha"), 6)
        XCTAssertEqual(counter.count("gateway|beta"), 3)
    }

    func testCachedSessionContextRefreshedOnceAfterAuthFailure() async throws {
        let keychain = makeTestKeychain()
        let descriptor = Self.makeFetchDescriptor()
        try Self.saveVaultCookie("sid=vault-cookie; uid=1", descriptor: descriptor, keychain: keychain)

        let counter = RequestCounter()
        let mode = GatewayMode()
        Self.installSessionCountingHandler(counter: counter, mode: mode)
        defer { QwenMockURLProtocol.requestHandler = nil }

        let provider = Self.makeSessionTestProvider(
            descriptor: descriptor,
            keychain: keychain,
            spy: IntentRecordingBrowserCookieDetector()
        )

        _ = try await provider.fetch()
        XCTAssertEqual(counter.count("userInfo|vault-cookie"), 1)

        mode.gatewayAuthorized = false
        do {
            _ = try await provider.fetch()
            XCTFail("Expected the rejected session to fail the fetch")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail = error else {
                return XCTFail("expected unauthorizedDetail, got \(error)")
            }
        }
        XCTAssertEqual(counter.count("userInfo|vault-cookie"), 2, "the cached context is refreshed exactly once before giving up")
        XCTAssertEqual(counter.count("gateway|vault-cookie"), 5, "first fetch round (3) + one usage attempt per retry round")

        mode.gatewayAuthorized = true
        let third = try await provider.fetch()
        XCTAssertEqual(third.status, .ok)
        XCTAssertEqual(counter.count("userInfo|vault-cookie"), 2, "the retry's fresh context is cached, so no further refetch")
        XCTAssertEqual(counter.count("gateway|vault-cookie"), 8, "the third fetch adds one full coding-plan round (usage + subscription + addon)")
    }

    func testSessionCacheKeysCarryFingerprintNotCookieMaterial() {
        let key = QwenProvider.sessionCacheKey(kind: "secToken", descriptorID: "qwen-1", fingerprint: "deadbeef")
        XCTAssertEqual(key, "qwen|session|secToken|qwen-1|deadbeef")

        let cookie = "sid=secret-session-value; uid=1"
        let fingerprint = CredentialFingerprint.sha256Hex(cookie)
        XCTAssertEqual(fingerprint.count, 64, "SHA-256 hex digest")
        XCTAssertEqual(CredentialFingerprint.sha256Hex(cookie), fingerprint, "fingerprints are stable for change detection")
        XCTAssertNotEqual(CredentialFingerprint.sha256Hex("sid=other-session; uid=1"), fingerprint)
        XCTAssertFalse(fingerprint.contains("secret-session-value"), "the fingerprint must not embed the cookie")
        XCTAssertFalse(key.contains(cookie))

        let secKey = QwenProvider.sessionCacheKey(kind: "secToken", descriptorID: "qwen-1", fingerprint: fingerprint)
        let labelKey = QwenProvider.sessionCacheKey(kind: "accountLabel", descriptorID: "qwen-1", fingerprint: fingerprint)
        XCTAssertNotEqual(secKey, labelKey, "sec_token and the account label use independent cache keys")
    }

    func testSessionCacheTTLsFollowFetchPlan() {
        let plan = ProviderFetchPlanRegistry().plan(for: .qwen)
        XCTAssertEqual(plan.activeTTL, 300, "the web-only provider active TTL is pinned to the fetch plan (300s)")
        XCTAssertEqual(ProviderFetchPlanRegistry().plan(for: .qwenBalance).activeTTL, 300)
        XCTAssertGreaterThan(plan.metadataTTL, plan.activeTTL, "the account label TTL must be longer than the sec_token TTL")
        XCTAssertGreaterThanOrEqual(plan.metadataTTL, 86_400)
    }
}

private final class IntentRecordingBrowserCookieDetector: BrowserCookieDetecting {
    var detectCookieHeaderCallCount = 0
    var detectNamedCookieCallCount = 0
    var cookieHeaderResult: BrowserCookieHeader?
    private(set) var recordedIntents: [BrowserCredentialAccessIntent] = []

    func detectCookieHeader(
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        detectCookieHeaderCallCount += 1
        recordedIntents.append(accessIntent)
        return cookieHeaderResult
    }

    func detectNamedCookie(
        name: String,
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        detectNamedCookieCallCount += 1
        recordedIntents.append(accessIntent)
        return nil
    }
}

private final class QwenMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
