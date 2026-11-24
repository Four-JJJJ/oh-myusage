import Foundation
import OhMyUsageDomain
import OhMyUsageProviders
import XCTest
@testable import OhMyUsage

/// Request-count and caching behavior of `GeminiProvider` (optimization doc
/// §8.4 Gemini / §8.5): `loadCodeAssist` + `retrieveUserQuota` both stay part
/// of a full load, the Code Assist context is cached per account with a TTL
/// longer than the quota data, and refreshed OAuth tokens land in the shared
/// credential vault instead of the plaintext credential file.
final class GeminiProviderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gemini-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Full load keeps both required requests

    func testColdLoadIssuesBothLoadCodeAssistAndQuotaRequests() async throws {
        let home = try makeHome(email: "cold@example.com")
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.absoluteString {
            case "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist":
                counter.increment("loadCodeAssist")
                return (Self.httpOK(url), Data(#"{"currentTier":{"id":"pro"}}"#.utf8))
            case "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota":
                counter.increment("quota")
                return (Self.httpOK(url), Data(Self.quotaBody(percent: 40).utf8))
            default:
                XCTFail("unexpected request: \(url.absoluteString)")
                return (Self.httpOK(url), Data())
            }
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let provider = makeProvider(home: home, contextCache: GeminiCodeAssistContextCache())
        let snapshot = try await provider.fetch()

        XCTAssertEqual(counter.value("loadCodeAssist"), 1, "full load must issue loadCodeAssist exactly once")
        XCTAssertEqual(counter.value("quota"), 1, "full load must issue retrieveUserQuota exactly once")
        XCTAssertEqual(snapshot.remaining ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "pro")
    }

    // MARK: - Context cache reduces repeated requests

    func testRepeatedRefreshReusesCodeAssistContextWithoutReissuingLoadCodeAssist() async throws {
        let home = try makeHome(email: "repeat@example.com")
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.absoluteString {
            case "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist":
                counter.increment("loadCodeAssist")
                return (Self.httpOK(url), Data(#"{"currentTier":{"id":"pro"}}"#.utf8))
            case "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota":
                counter.increment("quota")
                return (Self.httpOK(url), Data(Self.quotaBody(percent: 40).utf8))
            default:
                XCTFail("unexpected request: \(url.absoluteString)")
                return (Self.httpOK(url), Data())
            }
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        // Snapshot TTL 0 forces a fresh quota load on every fetch, while the
        // Code Assist context cache (1h) stays fresh.
        let provider = makeProvider(
            home: home,
            contextCache: GeminiCodeAssistContextCache(),
            cacheTTL: 0
        )

        _ = try await provider.fetch()
        let second = try await provider.fetch()

        XCTAssertEqual(counter.value("loadCodeAssist"), 1, "context cache hit must not re-issue loadCodeAssist")
        XCTAssertEqual(counter.value("quota"), 2, "quota data must be reloaded while the context stays cached")
        XCTAssertEqual(second.extras["planType"], "pro", "plan metadata must survive from the cached context")
    }

    func testForceRefreshReloadsCodeAssistContext() async throws {
        let home = try makeHome(email: "force@example.com")
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.absoluteString {
            case "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist":
                counter.increment("loadCodeAssist")
                return (Self.httpOK(url), Data(#"{"currentTier":{"id":"pro"}}"#.utf8))
            case "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota":
                counter.increment("quota")
                return (Self.httpOK(url), Data(Self.quotaBody(percent: 40).utf8))
            default:
                XCTFail("unexpected request: \(url.absoluteString)")
                return (Self.httpOK(url), Data())
            }
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let provider = makeProvider(home: home, contextCache: GeminiCodeAssistContextCache())

        _ = try await provider.fetch()
        _ = try await provider.fetch(forceRefresh: true)

        XCTAssertEqual(counter.value("loadCodeAssist"), 2, "force refresh performs a full load including loadCodeAssist")
        XCTAssertEqual(counter.value("quota"), 2)
    }

    // MARK: - Plan metadata TTL vs quota TTL

    func testPlanMetadataAndContextTTLsAreLongerThanQuotaTTL() {
        XCTAssertGreaterThan(
            GeminiProvider.planMetadataTTL,
            15,
            "plan metadata TTL must be longer than the quota data TTL"
        )
        XCTAssertGreaterThanOrEqual(
            GeminiProvider.contextTTL,
            GeminiProvider.planMetadataTTL,
            "account/project context must live at least as long as the plan metadata"
        )
    }

    func testExpiredPlanMetadataReloadsPlanButReusesCachedProjectLabel() async throws {
        let home = try makeHome(email: "ttl@example.com")
        let counter = ProviderRequestCounter()
        let clock = MutableClock(now: Date())
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.absoluteString {
            case "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist":
                counter.increment("loadCodeAssist")
                return (
                    Self.httpOK(url),
                    Data(#"{"currentTier":{"id":"pro"},"cloudaicompanionProject":"proj-123"}"#.utf8)
                )
            case "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota":
                counter.increment("quota")
                return (Self.httpOK(url), Data(Self.quotaBody(percent: 40).utf8))
            case "https://cloudresourcemanager.googleapis.com/v1/projects/proj-123":
                counter.increment("projectName")
                return (Self.httpOK(url), Data(#"{"name":"My Project"}"#.utf8))
            default:
                XCTFail("unexpected request: \(url.absoluteString)")
                return (Self.httpOK(url), Data())
            }
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        // plan metadata 60s < context 1h; snapshot TTL 0 so every fetch loads.
        let contextCache = GeminiCodeAssistContextCache(
            contextTTL: 3600,
            planMetadataTTL: 60,
            now: { clock.now() }
        )
        let provider = makeProvider(home: home, contextCache: contextCache, cacheTTL: 0)

        let first = try await provider.fetch()
        XCTAssertEqual(counter.value("loadCodeAssist"), 1)
        XCTAssertEqual(counter.value("projectName"), 1, "cold load resolves the project label once")
        XCTAssertEqual(first.extras["project"], "My Project")

        // Past the plan metadata TTL but within the context TTL: the plan is
        // refreshed via loadCodeAssist, the project label is reused.
        clock.advance(by: 120)
        let second = try await provider.fetch()
        XCTAssertEqual(counter.value("loadCodeAssist"), 2, "stale plan metadata must trigger one loadCodeAssist refresh")
        XCTAssertEqual(counter.value("projectName"), 1, "project label must be reused from the fresh context")
        XCTAssertEqual(counter.value("quota"), 2)
        XCTAssertEqual(second.extras["project"], "My Project")
        XCTAssertEqual(second.extras["planType"], "pro")

        // Past the context TTL as well: full context reload.
        clock.advance(by: 4000)
        _ = try await provider.fetch()
        XCTAssertEqual(counter.value("loadCodeAssist"), 3)
        XCTAssertEqual(counter.value("projectName"), 2, "expired context re-resolves the project label")
        XCTAssertEqual(counter.value("quota"), 3)
    }

    // MARK: - No cross-account reuse

    func testCodeAssistContextCacheDoesNotCrossAccounts() async throws {
        let homeA = try makeHome(email: "account-a@example.com", accessToken: "token-a")
        let homeB = try makeHome(email: "account-b@example.com", accessToken: "token-b")
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            switch url.absoluteString {
            case "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist":
                counter.increment("loadCodeAssist")
                let tier = authorization == "Bearer token-b" ? "standard" : "pro"
                return (Self.httpOK(url), Data(#"{"currentTier":{"id":"\#(tier)"}}"#.utf8))
            case "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota":
                counter.increment("quota")
                let percent = authorization == "Bearer token-b" ? 70.0 : 40.0
                return (Self.httpOK(url), Data(Self.quotaBody(percent: percent).utf8))
            default:
                XCTFail("unexpected request: \(url.absoluteString)")
                return (Self.httpOK(url), Data())
            }
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        // One process-wide cache instance shared by both providers.
        let sharedContextCache = GeminiCodeAssistContextCache()
        let sharedSnapshotCache = SnapshotTimestampOfficialSnapshotCache()
        let providerA = makeProvider(
            home: homeA,
            cache: sharedSnapshotCache,
            contextCache: sharedContextCache,
            cacheTTL: 0
        )
        let providerB = makeProvider(
            home: homeB,
            cache: sharedSnapshotCache,
            contextCache: sharedContextCache,
            cacheTTL: 0
        )

        let snapshotA = try await providerA.fetch()
        let snapshotB = try await providerB.fetch()

        XCTAssertEqual(counter.value("loadCodeAssist"), 2, "each account must load its own Code Assist context")
        XCTAssertEqual(snapshotA.extras["planType"], "pro")
        XCTAssertEqual(snapshotB.extras["planType"], "standard", "account B must not inherit account A's cached context")
        XCTAssertEqual(snapshotA.remaining ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshotB.remaining ?? -1, 30, accuracy: 0.001)
    }

    // MARK: - Vault persistence of refreshed tokens

    func testOAuthRefreshPersistsTokenToVaultInsteadOfPlaintextFile() async throws {
        let email = "refresh@example.com"
        let home = try makeHome(
            email: email,
            accessToken: "expired-access-token",
            expiryDate: Date().addingTimeInterval(-3600),
            includeClientSecrets: true
        )
        let credentialsFile = home.appendingPathComponent(".gemini/oauth_creds.json")
        let originalFileContents = try String(contentsOf: credentialsFile, encoding: .utf8)

        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.absoluteString {
            case "https://oauth2.googleapis.com/token":
                counter.increment("tokenRefresh")
                let body = #"{"access_token":"refreshed-access-token","expires_in":3600,"id_token":"\#(Self.makeJWT(email: email))"}"#
                return (Self.httpOK(url), Data(body.utf8))
            case "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist":
                counter.increment("loadCodeAssist")
                return (Self.httpOK(url), Data(#"{"currentTier":{"id":"pro"}}"#.utf8))
            case "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota":
                counter.increment("quota")
                return (Self.httpOK(url), Data(Self.quotaBody(percent: 40).utf8))
            default:
                XCTFail("unexpected request: \(url.absoluteString)")
                return (Self.httpOK(url), Data())
            }
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let keychain = RecordingTokenCredentialStore()
        let provider = makeProvider(
            home: home,
            contextCache: GeminiCodeAssistContextCache(),
            keychain: keychain
        )

        _ = try await provider.fetch()

        XCTAssertEqual(counter.value("tokenRefresh"), 1)
        XCTAssertEqual(keychain.saves.count, 1, "refreshed token must be persisted exactly once")
        let save = try XCTUnwrap(keychain.saves.first)
        XCTAssertEqual(save.service, GeminiProvider.credentialServiceName)
        XCTAssertEqual(save.account, GeminiProvider.oauthVaultAccount)
        let savedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(save.token.utf8)) as? [String: Any]
        )
        XCTAssertEqual(savedJSON["access_token"] as? String, "refreshed-access-token")
        XCTAssertEqual(savedJSON["refresh_token"] as? String, "refresh-token-a")

        let fileAfterRefresh = try String(contentsOf: credentialsFile, encoding: .utf8)
        XCTAssertEqual(
            fileAfterRefresh,
            originalFileContents,
            "refreshed tokens must never be written to the plaintext credential file"
        )
        XCTAssertFalse(fileAfterRefresh.contains("refreshed-access-token"))

        // Second fetch reads the vaulted credentials (fresh expiry) and the
        // still-fresh snapshot, so no further refresh or network happens.
        _ = try await provider.fetch()
        XCTAssertEqual(counter.value("tokenRefresh"), 1, "vaulted expiry must prevent repeated OAuth refreshes")
        XCTAssertEqual(counter.value("quota"), 1)
        XCTAssertEqual(counter.value("loadCodeAssist"), 1)
    }

    // MARK: - Modern Gemini CLI Keychain & JSONC settings

    func testModernKeychainCredentialsWorkWithoutSettingsOrOAuthFiles() async throws {
        let home = temporaryDirectory.appendingPathComponent("keychain-only-\(UUID().uuidString)", isDirectory: true)
        let geminiDir = home.appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try writeText(
            #"{"active":"keychain-user@example.com","old":[]}"#,
            to: geminiDir.appendingPathComponent("google_accounts.json")
        )

        let keychainPayload = """
        {
          "serverName": "main-account",
          "token": {
            "accessToken": "keychain-access-token",
            "refreshToken": "keychain-refresh-token",
            "tokenType": "Bearer",
            "expiresAt": 4102444800000
          }
        }
        """

        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer keychain-access-token")
            switch url.absoluteString {
            case "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist":
                return (Self.httpOK(url), Data(#"{"currentTier":{"id":"pro"}}"#.utf8))
            case "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota":
                return (Self.httpOK(url), Data(Self.quotaBody(percent: 25).utf8))
            default:
                XCTFail("unexpected request: \(url.absoluteString)")
                return (Self.httpOK(url), Data())
            }
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        var descriptor = ProviderDescriptor.defaultOfficialGemini()
        descriptor.officialConfig?.sourceMode = .cli
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]

        let provider = GeminiProvider(
            descriptor: descriptor,
            session: URLSession(configuration: configuration),
            cache: SnapshotTimestampOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { home.path },
            environment: { [:] },
            contextCache: GeminiCodeAssistContextCache(),
            externalKeychainReader: { service, account, _ in
                guard service == GeminiProvider.cliKeychainServiceName,
                      account == GeminiProvider.cliKeychainMainAccount else {
                    return nil
                }
                return keychainPayload
            },
            cacheTTL: 0
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 75, accuracy: 0.001)
        XCTAssertEqual(snapshot.accountLabel, "keychain-user@example.com")
        XCTAssertEqual(snapshot.extras["planType"], "pro")
    }

    func testJSONCSettingsWithCommentsAndTrailingCommasParseCleanly() {
        let jsonc = """
        {
          // Comment with "quotes" and // slashes
          "security": {
            /* Block comment */
            "auth": {
              "selectedType": "oauth-personal",
            },
          },
        }
        """
        let cleaned = GeminiProvider.stripJSONCommentsAndTrailingCommas(jsonc)
        let parsed = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any]
        let security = parsed?["security"] as? [String: Any]
        let auth = security?["auth"] as? [String: Any]
        XCTAssertEqual(auth?["selectedType"] as? String, "oauth-personal")
    }

    // MARK: - Gemini Web (`gemini.google.com/usage`) & Auto Fallback

    func testParseWebUsageSnapshotExtractsFiveHourWeeklyAndTier() throws {
        let rawBody = """
        )]}'
        [
          {
            "data": {
              "viewer": {
                "email": "web-pro@example.com",
                "rpcs": {
                  "getUsageInfo": {
                    "subscriptionTier": "TIER1",
                    "pools": [
                      {
                        "poolType": "GXU_FIVE_HOURLY",
                        "percentageUsed": 0.35,
                        "gxu": { "windowRefreshesAt": "2026-11-24T06:00:00Z" }
                      },
                      {
                        "poolType": "GXU_WEEKLY",
                        "percentageUsed": 0.60,
                        "gxu": { "windowRefreshesAt": "2026-11-28T00:00:00Z" }
                      }
                    ]
                  }
                }
              }
            }
          }
        ]
        """

        let snapshot = try GeminiProvider.parseWebUsageSnapshot(
            rawBody: rawBody,
            descriptor: .defaultOfficialGemini(),
            cookieSource: "Auto:Chrome"
        )

        XCTAssertEqual(snapshot.sourceLabel, "Web")
        XCTAssertEqual(snapshot.accountLabel, "web-pro@example.com")
        XCTAssertEqual(snapshot.extras["planType"], "pro")
        XCTAssertEqual(snapshot.extras["webCookieSource"], "Auto:Chrome")
        XCTAssertEqual(snapshot.remaining ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 65, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.remainingPercent ?? -1, 40, accuracy: 0.001)
    }

    func testAutoModeFallsBackToGeminiWebAndSkipsSignedOutBrowserProfiles() async throws {
        let emptyHome = temporaryDirectory.appendingPathComponent("auto-web-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)

        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.host, "gemini.google.com")
            let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
            if cookie.contains("__Secure-1PSID=signed-out-profile") {
                return (Self.httpOK(url), Data(#")]}'[{"data":{"viewer":null}}]"#.utf8))
            }
            XCTAssertTrue(cookie.contains("__Secure-1PSID=active-pro-profile"))
            let payload = """
            )]}'
            [{"data":{"viewer":{"rpcs":{"getUsageInfo":{"subscriptionTier":"TIER1","pools":[
              {"poolType":"GXU_FIVE_HOURLY","percentageUsed":0.2,"gxu":{"windowRefreshesAt":"2026-11-24T08:00:00Z"}},
              {"poolType":"GXU_WEEKLY","percentageUsed":0.5,"gxu":{"windowRefreshesAt":"2026-11-29T00:00:00Z"}}
            ]}}}}}]
            """
            return (Self.httpOK(url), Data(payload.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let keychain = RecordingTokenCredentialStore()
        let cookieDetector = MultiSessionStubBrowserCookieDetector(candidates: [
            BrowserCookieHeader(header: "NID=anonymous-only", source: "Auto:Arc"),
            BrowserCookieHeader(header: "__Secure-1PSID=signed-out-profile; SID=old", source: "Auto:Chrome#1"),
            BrowserCookieHeader(header: "__Secure-1PSID=active-pro-profile; SID=live", source: "Auto:Chrome#2")
        ])

        var descriptor = ProviderDescriptor.defaultOfficialGemini()
        descriptor.officialConfig?.sourceMode = .auto
        descriptor.officialConfig?.webMode = .autoImport

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]

        let provider = GeminiProvider(
            descriptor: descriptor,
            session: URLSession(configuration: configuration),
            cache: SnapshotTimestampOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { emptyHome.path },
            environment: { [:] },
            contextCache: GeminiCodeAssistContextCache(),
            keychain: keychain,
            browserCookieService: cookieDetector,
            externalKeychainReader: { _, _, _ in nil },
            webReadBackoff: WebOverlayRetryBackoff(),
            cacheTTL: 0
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.sourceLabel, "Web")
        XCTAssertEqual(snapshot.remaining ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["webCookieSource"], "Auto:Chrome#2")
        XCTAssertEqual(
            keychain.readToken(service: GeminiProvider.credentialServiceName, account: GeminiProvider.manualCookieAccount),
            "__Secure-1PSID=active-pro-profile; SID=live"
        )
    }

    func testLegacyGeminiConfigMigratesDisabledWebModeOnceWhilePreservingExplicitDisable() {
        var legacy = ProviderDescriptor(
            id: "gemini-official",
            name: "Official Gemini",
            family: .official,
            type: .gemini,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://cloudcode-pa.googleapis.com",
            officialConfig: OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        )

        let migrated = AppConfig(language: .zhHans, providers: [legacy]).migratedWithSiteDefaults()
        let upgradedGemini = migrated.providers.first(where: { $0.id == "gemini-official" })
        XCTAssertEqual(upgradedGemini?.officialConfig?.webMode, .autoImport)
        XCTAssertEqual(upgradedGemini?.officialConfig?.manualCookieAccount, GeminiProvider.manualCookieAccount)

        // If user explicitly disables webMode after migration (`manualCookieAccount` already set), keep `.disabled`.
        legacy.officialConfig?.manualCookieAccount = GeminiProvider.manualCookieAccount
        legacy.officialConfig?.webMode = .disabled
        let reMigrated = AppConfig(language: .zhHans, providers: [legacy]).migratedWithSiteDefaults()
        let preservedGemini = reMigrated.providers.first(where: { $0.id == "gemini-official" })
        XCTAssertEqual(preservedGemini?.officialConfig?.webMode, .disabled)
    }

    // MARK: - Helpers

    private func makeProvider(
        home: URL,
        cache: any OfficialSnapshotCaching = SnapshotTimestampOfficialSnapshotCache(),
        contextCache: GeminiCodeAssistContextCache,
        keychain: (any TokenCredentialStoring)? = nil,
        cacheTTL: TimeInterval = 15
    ) -> GeminiProvider {
        var descriptor = ProviderDescriptor.defaultOfficialGemini()
        descriptor.id = "gemini-official"
        descriptor.officialConfig?.sourceMode = .api

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]

        return GeminiProvider(
            descriptor: descriptor,
            session: URLSession(configuration: configuration),
            cache: cache,
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { home.path },
            shell: DefaultShellCommandRunner(),
            contextCache: contextCache,
            keychain: keychain,
            cacheTTL: cacheTTL
        )
    }

    private func makeHome(
        email: String,
        accessToken: String = "access-token",
        expiryDate: Date? = Date(timeIntervalSince1970: 4_102_444_800),
        includeClientSecrets: Bool = false
    ) throws -> URL {
        let geminiDirectory = temporaryDirectory
            .appendingPathComponent("\(email)-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: geminiDirectory, withIntermediateDirectories: true)
        try writeText(#"{"selectedAuthType":"oauth-personal"}"#, to: geminiDirectory.appendingPathComponent("settings.json"))

        var oauthJSON: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": "refresh-token-a",
            "id_token": Self.makeJWT(email: email),
        ]
        if let expiryDate {
            oauthJSON["expiry_date"] = Int64(expiryDate.timeIntervalSince1970 * 1000)
        }
        if includeClientSecrets {
            oauthJSON["client_id"] = "test-client-id"
            oauthJSON["client_secret"] = "test-client-secret"
        }
        let data = try JSONSerialization.data(withJSONObject: oauthJSON)
        try writeText(String(data: data, encoding: .utf8) ?? "", to: geminiDirectory.appendingPathComponent("oauth_creds.json"))
        return geminiDirectory.deletingLastPathComponent()
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func httpOK(_ url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    private static func quotaBody(percent: Double) -> String {
        """
        {
          "quotas": [
            {"quotaId": "gemini-2.5-pro", "usage": {"utilization": \(percent), "resetAt": "2026-04-11T08:00:00Z"}},
            {"quotaId": "gemini-2.5-flash", "usage": {"utilization": 20, "resetAt": "2026-04-11T02:00:00Z"}}
          ]
        }
        """
    }

    private static func makeJWT(email: String) -> String {
        let payload = Data(#"{"email":"\#(email)"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }
}

/// Thread-safe request counter shared with the mock URL protocol handler.
final class ProviderRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]

    func increment(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key, default: 0] += 1
    }

    func value(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return values[key] ?? 0
    }
}

/// Injectable clock for TTL-controlled caches.
private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date) {
        current = now
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}

/// `TokenCredentialStoring` stub that records vault writes and serves them
/// back from memory (no plaintext files involved).
private final class RecordingTokenCredentialStore: TokenCredentialStoring, @unchecked Sendable {
    struct SaveRecord: Equatable {
        let token: String
        let service: String
        let account: String
    }

    private let lock = NSLock()
    private var storage: [String: String] = [:]
    private(set) var saves: [SaveRecord] = []

    func readToken(service: String, account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage["\(service)::\(account)"]
    }

    @discardableResult
    func saveToken(_ token: String, service: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage["\(service)::\(account)"] = token
        saves.append(SaveRecord(token: token, service: service, account: account))
        return true
    }

    @discardableResult
    func deleteToken(service: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage["\(service)::\(account)"] = nil
        return true
    }
}

private final class OfficialMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = OfficialMockURLProtocol.requestHandler else {
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

private final class MultiSessionStubBrowserCookieDetector: BrowserCookieDetecting {
    let candidates: [BrowserCookieHeader]

    init(candidates: [BrowserCookieHeader]) {
        self.candidates = candidates
    }

    func detectCookieHeader(
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        candidates.first
    }

    func detectNamedCookie(
        name: String,
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        nil
    }

    func detectCookieHeaders(
        matchingHosts: [String],
        fallbackHostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> [BrowserCookieHeader] {
        candidates
    }
}
