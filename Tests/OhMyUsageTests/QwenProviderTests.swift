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
