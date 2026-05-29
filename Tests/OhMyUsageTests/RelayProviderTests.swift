import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class RelayProviderTests: XCTestCase {
    func testDecodeRelayConfigWithoutQuotaDisplayModeDefaultsToRemaining() throws {
        let json = #"""
        {
          "baseURL":"https://relay.example.com",
          "tokenChannelEnabled":true,
          "balanceChannelEnabled":true,
          "balanceAuth":{
            "kind":"bearer",
            "keychainService":"OhMyUsage",
            "keychainAccount":"relay.example.com/system-token"
          }
        }
        """#

        let decoded = try JSONDecoder().decode(RelayProviderConfig.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.quotaDisplayMode, .remaining)
        XCTAssertTrue(decoded.showExpirationTimeInMenuBar)
    }

    func testLegacyOpenConfigNormalizesToRelayAdapter() {
        let descriptor = ProviderDescriptor(
            id: "open-ailinyu",
            name: "open.ailinyu.de",
            type: .open,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: "OhMyUsage", keychainAccount: "open.ailinyu.de/sk-token"),
            baseURL: "https://open.ailinyu.de",
            openConfig: OpenProviderConfig(
                tokenUsageEnabled: false,
                accountBalance: RelayAccountBalanceConfig(
                    enabled: true,
                    auth: AuthConfig(kind: .bearer, keychainService: "OhMyUsage", keychainAccount: "open.ailinyu.de/session-cookie"),
                    authHeader: "Cookie",
                    authScheme: "",
                    requestMethod: "GET",
                    requestBodyJSON: nil,
                    endpointPath: "/api/user/self",
                    userID: "example-user-id",
                    userIDHeader: "New-Api-User",
                    remainingJSONPath: "data.quota",
                    usedJSONPath: "data.used_quota",
                    limitJSONPath: "data.request_quota",
                    successJSONPath: "success",
                    unit: "quota"
                )
            )
        )

        let normalized = descriptor.normalized()
        XCTAssertEqual(normalized.type, .relay)
        XCTAssertEqual(normalized.relayConfig?.adapterID, "ailinyu")
        XCTAssertNil(normalized.openConfig)
        XCTAssertEqual(normalized.relayConfig?.balanceAuth.keychainAccount, "open.ailinyu.de/session-cookie")
    }

    func testUnknownLegacyRelayFallsBackToGenericManifestAndKeepsAccount() {
        let descriptor = ProviderDescriptor(
            id: "custom-relay",
            name: "Custom",
            type: .open,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: "OhMyUsage", keychainAccount: "relay.example/sk-token"),
            baseURL: "https://relay.example.com",
            openConfig: OpenProviderConfig(
                tokenUsageEnabled: true,
                accountBalance: RelayAccountBalanceConfig(
                    enabled: true,
                    auth: AuthConfig(kind: .bearer, keychainService: "OhMyUsage", keychainAccount: "relay.example/system-token"),
                    authHeader: "Authorization",
                    authScheme: "Bearer",
                    requestMethod: "GET",
                    requestBodyJSON: nil,
                    endpointPath: "/api/custom/balance",
                    userID: nil,
                    userIDHeader: "New-Api-User",
                    remainingJSONPath: "data.remaining",
                    usedJSONPath: nil,
                    limitJSONPath: nil,
                    successJSONPath: nil,
                    unit: "USD"
                )
            )
        )

        let normalized = descriptor.normalized()
        XCTAssertEqual(normalized.type, .relay)
        XCTAssertEqual(normalized.relayConfig?.adapterID, "generic-newapi")
        XCTAssertEqual(normalized.relayConfig?.balanceAuth.keychainAccount, "relay.example/system-token")
    }

    func testNormalizeKeepsExplicitGenericTemplateForDeepseekHost() {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        var descriptor = makeRelayDescriptor(
            service: service,
            adapterID: "generic-newapi",
            baseURL: "https://platform.deepseek.com/usage?month=4"
        )
        descriptor.relayConfig?.manualOverrides = RelayManualOverride(
            authHeader: "Authorization",
            authScheme: "Bearer",
            userID: nil,
            userIDHeader: "New-Api-User",
            requestMethod: "GET",
            requestBodyJSON: nil,
            endpointPath: "/api/user/self",
            remainingExpression: "data.quota",
            usedExpression: "data.used_quota",
            limitExpression: "data.request_quota",
            successExpression: "success",
            unitExpression: "quota",
            accountLabelExpression: nil,
            staticHeaders: nil
        )

        let normalized = descriptor.normalized()
        XCTAssertEqual(normalized.baseURL, "https://platform.deepseek.com")
        XCTAssertEqual(normalized.relayConfig?.baseURL, "https://platform.deepseek.com")
        XCTAssertEqual(normalized.relayConfig?.adapterID, "generic-newapi")
        XCTAssertEqual(normalized.relayConfig?.manualOverrides?.remainingExpression, "data.quota")
    }

    func testRegistryMatchesBundledManifest() {
        let manifest = RelayAdapterRegistry.shared.manifest(for: "https://hongmacc.com")
        XCTAssertEqual(manifest.id, "hongmacc")
    }

    func testRegistryFiltersLegacyRelayExampleManifestByHostPattern() {
        let sample = RelayAdapterManifest(
            id: "relay-example-template",
            displayName: "Relay Example",
            match: RelayAdapterMatch(
                hostPatterns: ["relay.example.com"],
                defaultDisplayName: "Relay Example",
                defaultTokenChannelEnabled: false,
                defaultBalanceChannelEnabled: true
            ),
            authStrategies: [.init(kind: .savedBearer)],
            balanceRequest: RelayRequestManifest(path: "/api/user/self"),
            extract: RelayExtractManifest(remaining: "data.quota")
        )
        let registry = RelayAdapterRegistry(builtInManifests: [RelayAdapterRegistry.genericManifest, sample])
        let ids = Set(registry.availableManifests().map(\.id))

        XCTAssertTrue(ids.contains("generic-newapi"))
        XCTAssertFalse(ids.contains("relay-example-template"))
    }

    func testRegistryFiltersLegacyRelayExampleManifestByDisplayName() {
        let sample = RelayAdapterManifest(
            id: "custom-template",
            displayName: "Relay Example Backup",
            match: RelayAdapterMatch(
                hostPatterns: ["api.custom.example.com"],
                defaultDisplayName: "Relay Example Backup",
                defaultTokenChannelEnabled: false,
                defaultBalanceChannelEnabled: true
            ),
            authStrategies: [.init(kind: .savedBearer)],
            balanceRequest: RelayRequestManifest(path: "/api/user/self"),
            extract: RelayExtractManifest(remaining: "data.quota")
        )
        let registry = RelayAdapterRegistry(builtInManifests: [RelayAdapterRegistry.genericManifest, sample])
        let ids = Set(registry.availableManifests().map(\.id))

        XCTAssertTrue(ids.contains("generic-newapi"))
        XCTAssertFalse(ids.contains("custom-template"))
    }

    func testRegistryFiltersLegacyRelayExampleManifestWhenHostPatternIsURL() {
        let sample = RelayAdapterManifest(
            id: "custom-template-url-host",
            displayName: "Legacy Sample",
            match: RelayAdapterMatch(
                hostPatterns: ["https://relay.example.com/path?from=legacy"],
                defaultDisplayName: "Legacy Sample",
                defaultTokenChannelEnabled: false,
                defaultBalanceChannelEnabled: true
            ),
            authStrategies: [.init(kind: .savedBearer)],
            balanceRequest: RelayRequestManifest(path: "/api/user/self"),
            extract: RelayExtractManifest(
                remaining: "data.quota",
                used: "data.used_quota"
            )
        )
        let registry = RelayAdapterRegistry(builtInManifests: [RelayAdapterRegistry.genericManifest, sample])
        let ids = Set(registry.builtInManifests().map(\.id))

        XCTAssertTrue(ids.contains("generic-newapi"))
        XCTAssertFalse(ids.contains("custom-template-url-host"))
    }

    func testGenericNewAPIManifestUsesAccessTokenAndUserIDDefaults() {
        let manifest = RelayAdapterRegistry.shared.manifest(for: "https://relay.example.com", preferredID: "generic-newapi")

        XCTAssertEqual(manifest.match.defaultTokenChannelEnabled, false)
        XCTAssertEqual(manifest.match.defaultBalanceChannelEnabled, true)
        XCTAssertEqual(manifest.setup?.requiredInputs, [.displayName, .baseURL, .balanceAuth, .userID])
        XCTAssertEqual(manifest.balanceRequest.path, "/api/user/self")
        XCTAssertEqual(manifest.balanceRequest.userIDHeader, "New-Api-User")
        XCTAssertEqual(manifest.extract.remaining, "data.quota")
        XCTAssertEqual(manifest.extract.used, "data.used_quota")
        XCTAssertEqual(manifest.extract.limit, "add(data.quota,data.used_quota)")
        XCTAssertEqual(manifest.extract.unit, "quota")
        XCTAssertEqual(manifest.extract.accountLabel, "coalesce(data.group,\"默认套餐\")")
        XCTAssertEqual(manifest.postprocessID, .quotaDisplayStatus)
    }

    func testRegistryMatchesDeepseekManifest() {
        let manifest = RelayAdapterRegistry.shared.manifest(for: "https://platform.deepseek.com")
        XCTAssertEqual(manifest.id, "deepseek")
    }

    func testRegistryMatchesXiaomimimoManifest() {
        let manifest = RelayAdapterRegistry.shared.manifest(for: "https://platform.xiaomimimo.com")
        XCTAssertEqual(manifest.id, "xiaomimimo")
    }

    func testRegistryMatchesXiaomimimoTokenPlanManifestWhenPreferred() {
        let manifest = RelayAdapterRegistry.shared.manifest(
            for: "https://platform.xiaomimimo.com",
            preferredID: "xiaomimimo-token-plan"
        )
        XCTAssertEqual(manifest.id, "xiaomimimo-token-plan")
        XCTAssertEqual(manifest.displayMode, .quotaPercent)
    }

    func testRegistryMatchesMoonshotManifest() {
        let manifest = RelayAdapterRegistry.shared.manifest(for: "https://platform.moonshot.cn")
        XCTAssertEqual(manifest.id, "moonshot")
    }

    func testCustomRelayNameSurvivesNormalizationForKnownTemplate() {
        let descriptor = ProviderDescriptor.makeOpenRelay(
            name: "Moonshot 主账号",
            baseURL: "https://platform.moonshot.cn",
            preferredAdapterID: "moonshot"
        )

        let normalized = descriptor.normalized()
        XCTAssertEqual(normalized.name, "Moonshot 主账号")
        XCTAssertEqual(normalized.relayConfig?.adapterID, "moonshot")
    }

    func testRegistryMatchesMinimaxManifest() {
        let manifest = RelayAdapterRegistry.shared.manifest(for: "https://platform.minimaxi.com")
        XCTAssertEqual(manifest.id, "minimax")
        XCTAssertEqual(manifest.setup?.requiredInputs, [.balanceAuth, .userID])
    }

    func testRegistryLoadsSetupMetadataForKnownTemplate() {
        let manifest = RelayAdapterRegistry.shared.manifest(for: "https://platform.deepseek.com")
        XCTAssertEqual(manifest.setup?.recommendedBaseURL, "https://platform.deepseek.com")
        XCTAssertEqual(manifest.setup?.requiredInputs, [.balanceAuth])
        let hint = manifest.setup?.balanceAuthHint?.zhHans ?? ""
        XCTAssertTrue(hint.contains("Bearer Token"))
        XCTAssertTrue(hint.contains("登录态令牌"))
    }

    func testRegistryDecoratesDisplayModeAndDiagnosticHints() {
        let manifest = RelayAdapterRegistry.shared.manifest(for: "https://open.ailinyu.de")
        XCTAssertEqual(manifest.displayMode, .hybrid)
        XCTAssertTrue(manifest.supportsBrowserFallback)
        XCTAssertTrue(manifest.supportsSeparateBalanceAuth)
        XCTAssertNotNil(manifest.setup?.diagnosticHints?.zhHans)
    }

    func testMoonshotTemplatePrefersCookieStrategy() {
        let manifest = RelayAdapterRegistry.shared.manifest(for: "https://platform.moonshot.cn")
        XCTAssertEqual(manifest.authStrategies.map(\.kind), [.savedBearer, .browserBearer, .savedCookieHeader, .browserCookieHeader])
    }

    func testMakeOpenRelayPreservesExplicitPreferredTemplate() {
        let descriptor = ProviderDescriptor.makeOpenRelay(
            name: "Custom DeepSeek",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "deepseek",
            keychainService: "OhMyUsageTests"
        )

        XCTAssertEqual(descriptor.relayConfig?.adapterID, "deepseek")

        let normalized = descriptor.normalized()
        XCTAssertEqual(normalized.relayConfig?.adapterID, "deepseek")
        XCTAssertEqual(normalized.baseURL, "https://relay.example.com")
        XCTAssertEqual(normalized.relayConfig?.balanceAuth.keychainAccount, "relay.example.com/system-access-token")
    }

    func testFetchFallsBackFromSavedBearerToBrowserBearer() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("bad-token", service: service, account: "relay.example.com/system-token"))
        var browserBearerLookupCount = 0

        RelayMockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            if auth == "Bearer bad-token" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"error":"expired"}"#.utf8))
            }
            XCTAssertEqual(auth, "Bearer good-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/status":
                return (response, Data(#"{"success":true,"data":{"quota_per_unit":50000,"quota_display_type":"USD","display_in_currency":true}}"#.utf8))
            default:
                return (response, Data(#"{"success":true,"data":{"quota":6000000,"used_quota":1500000}}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = RelayProvider(
            descriptor: genericNewAPIDescriptor(
                service: service,
                baseURL: "https://relay.example.com",
                userID: "user-123"
            ),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in
                    browserBearerLookupCount += 1
                    return [BrowserDetectedCredential(value: "good-token", source: "browser")]
                }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 120, accuracy: 0.001)
        XCTAssertEqual(snapshot.rawMeta["account.authSource"], "browserBearer:browser")
        XCTAssertEqual(snapshot.rawMeta["relay.recovery.succeeded"], "true")
        XCTAssertEqual(snapshot.rawMeta["relay.recovery.trigger"], "credentialRejected")
        XCTAssertEqual(snapshot.rawMeta["relay.recovery.source"], "browserBearer:browser")
        XCTAssertEqual(snapshot.rawMeta["relay.savedCredentialSource"], "browserBearer:browser")
        XCTAssertNotNil(snapshot.rawMeta["relay.recovery.at"])
        XCTAssertEqual(snapshot.fetchHealth, .ok)
        XCTAssertEqual(snapshot.valueFreshness, .live)
        XCTAssertEqual(snapshot.authSourceLabel, "browserBearer:browser")
        XCTAssertEqual(browserBearerLookupCount, 1)
        XCTAssertEqual(
            keychain.readToken(service: service, account: "relay.example.com/system-token"),
            "good-token"
        )
    }

    func testManualPreferredWithValidSavedCredentialSkipsBrowserLookup() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("saved-token", service: service, account: "relay.example.com/system-token"))

        var browserBearerLookupCount = 0
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer saved-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/status":
                return (response, Data(#"{"success":true,"data":{"quota_per_unit":50000,"quota_display_type":"USD","display_in_currency":true}}"#.utf8))
            default:
                return (response, Data(#"{"success":true,"data":{"quota":4500000,"used_quota":500000}}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = RelayProvider(
            descriptor: genericNewAPIDescriptor(
                service: service,
                baseURL: "https://relay.example.com",
                userID: "user-123"
            ),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in
                    browserBearerLookupCount += 1
                    return [BrowserDetectedCredential(value: "browser-token", source: "browser")]
                },
                cookieHeaderOverride: { _ in
                    XCTFail("manualPreferred + valid saved credential should not read browser cookie")
                    return nil
                }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 90, accuracy: 0.001)
        XCTAssertEqual(snapshot.rawMeta["account.authSource"], "savedBearer")
        XCTAssertEqual(browserBearerLookupCount, 0)
    }

    func testBrowserPreferredBackgroundPollingUsesSavedCredentialWithoutLiveBrowserLookup() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("saved-token", service: service, account: "relay.example.com/system-token"))

        var descriptor = genericNewAPIDescriptor(
            service: service,
            baseURL: "https://relay.example.com",
            userID: "user-123"
        )
        descriptor.relayConfig?.balanceCredentialMode = .browserPreferred

        var browserBearerLookupCount = 0
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer saved-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/status":
                return (response, Data(#"{"success":true,"data":{"quota_per_unit":50000,"quota_display_type":"USD","display_in_currency":true}}"#.utf8))
            default:
                return (response, Data(#"{"success":true,"data":{"quota":4500000,"used_quota":500000}}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in
                    browserBearerLookupCount += 1
                    return [BrowserDetectedCredential(value: "browser-token", source: "browser")]
                }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 90, accuracy: 0.001)
        XCTAssertEqual(snapshot.rawMeta["account.authSource"], "savedBearer")
        XCTAssertEqual(browserBearerLookupCount, 0)
    }

    func testAuthRecoveryFailureBackoffSkipsRepeatedBrowserLookups() async {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let host = "recovery-backoff-\(UUID().uuidString).example"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("bad-token", service: service, account: "\(host)/system-token"))
        var browserBearerLookupCount = 0

        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bad-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":"expired"}"#.utf8))
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = RelayProvider(
            descriptor: genericNewAPIDescriptor(
                service: service,
                baseURL: "https://\(host)",
                userID: "user-123"
            ),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in
                    browserBearerLookupCount += 1
                    return []
                }
            )
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected auth failure")
        } catch {}
        XCTAssertEqual(browserBearerLookupCount, 1)

        do {
            _ = try await provider.fetch()
            XCTFail("Expected auth failure")
        } catch {}
        XCTAssertEqual(browserBearerLookupCount, 1)
    }

    func testGenericNewAPIFetchConvertsQuotaUsingStatusDisplaySettings() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("access-token", service: service, account: "relay.example.com/system-token"))

        var descriptor = makeRelayDescriptor(service: service, adapterID: "generic-newapi", baseURL: "https://relay.example.com")
        descriptor.relayConfig?.manualOverrides = RelayManualOverride(
            authHeader: "Authorization",
            authScheme: "Bearer",
            userID: "user-123",
            userIDHeader: "New-Api-User",
            requestMethod: "GET",
            requestBodyJSON: nil,
            endpointPath: "/api/user/self",
            remainingExpression: nil,
            usedExpression: nil,
            limitExpression: nil,
            successExpression: nil,
            unitExpression: nil,
            accountLabelExpression: nil,
            staticHeaders: nil
        )

        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "New-Api-User"), "user-123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/user/self":
                let payload = #"{"success":true,"data":{"group":"Pro","quota":1500000,"used_quota":500000,"request_count":12}}"#
                return (response, Data(payload.utf8))
            case "/api/status":
                let payload = #"{"success":true,"data":{"quota_per_unit":50000,"quota_display_type":"USD","display_in_currency":true}}"#
                return (response, Data(payload.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 30, accuracy: 0.000001)
        XCTAssertEqual(snapshot.used ?? -1, 10, accuracy: 0.000001)
        XCTAssertEqual(snapshot.limit ?? -1, 40, accuracy: 0.000001)
        XCTAssertEqual(snapshot.unit, "$")
        XCTAssertEqual(snapshot.accountLabel, "Pro")
        XCTAssertEqual(snapshot.rawMeta["account.userID"], "user-123")
        XCTAssertEqual(snapshot.rawMeta["account.requestCount"], "12")
        XCTAssertEqual(snapshot.rawMeta["account.rawUsedQuota"], "500000.0")
        XCTAssertEqual(snapshot.rawMeta["account.displayType"], "USD")
        XCTAssertEqual(snapshot.rawMeta["account.quotaPerUnit"], "50000.0")
        XCTAssertTrue(snapshot.note.contains("Requests 12"))
    }

    func testGenericNewAPIFetchUsesSiteQuotaPerUnitForFourjStyleBalance() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("access-token", service: service, account: "token.fourj.space/system-token"))

        let descriptor = genericNewAPIDescriptor(
            service: service,
            baseURL: "https://token.fourj.space",
            userID: "user-123"
        )

        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "New-Api-User"), "user-123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/user/self":
                let payload = #"{"success":true,"data":{"group":"Pro","quota":100000000,"used_quota":25000000}}"#
                return (response, Data(payload.utf8))
            case "/api/status":
                let payload = #"{"success":true,"data":{"quota_per_unit":500000,"quota_display_type":"CNY","display_in_currency":true,"usd_exchange_rate":1}}"#
                return (response, Data(payload.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 200, accuracy: 0.000001)
        XCTAssertEqual(snapshot.used ?? -1, 50, accuracy: 0.000001)
        XCTAssertEqual(snapshot.limit ?? -1, 250, accuracy: 0.000001)
        XCTAssertEqual(snapshot.unit, "¥")
        XCTAssertEqual(snapshot.rawMeta["account.displayType"], "CNY")
        XCTAssertEqual(snapshot.rawMeta["account.quotaPerUnit"], "500000.0")
    }

    func testGenericNewAPIFetchKeepsOneToOneStatusScale() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("access-token", service: service, account: "relay.example.com/system-token"))

        let descriptor = genericNewAPIDescriptor(
            service: service,
            baseURL: "https://relay.example.com",
            userID: "user-123"
        )

        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/user/self":
                let payload = #"{"success":true,"data":{"quota":100,"used_quota":20}}"#
                return (response, Data(payload.utf8))
            case "/api/status":
                let payload = #"{"success":true,"data":{"quota_per_unit":1,"quota_display_type":"USD","display_in_currency":true}}"#
                return (response, Data(payload.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 100, accuracy: 0.000001)
        XCTAssertEqual(snapshot.used ?? -1, 20, accuracy: 0.000001)
        XCTAssertEqual(snapshot.limit ?? -1, 120, accuracy: 0.000001)
        XCTAssertEqual(snapshot.unit, "$")
        XCTAssertEqual(snapshot.rawMeta["account.quotaPerUnit"], "1.0")
    }

    func testGenericNewAPIOverrideMigrationAppliesRawExpressions() {
        var descriptor = makeRelayDescriptor(
            service: "OhMyUsageTests",
            adapterID: "generic-newapi",
            baseURL: "https://relay.example.com"
        )
        descriptor.relayConfig?.manualOverrides = RelayManualOverride(
            authHeader: "Authorization",
            authScheme: "Bearer",
            userID: "1",
            userIDHeader: "New-Api-User",
            requestMethod: "GET",
            requestBodyJSON: nil,
            endpointPath: "/api/user/self",
            remainingExpression: "div(data.quota,50000)",
            usedExpression: "div(data.used_quota,50000)",
            limitExpression: "div(add(data.quota,data.used_quota),50000)",
            successExpression: "success",
            unitExpression: "USD",
            accountLabelExpression: nil,
            staticHeaders: nil
        )

        let normalized = descriptor.normalized()
        XCTAssertEqual(normalized.relayConfig?.manualOverrides?.remainingExpression, "data.quota")
        XCTAssertEqual(normalized.relayConfig?.manualOverrides?.usedExpression, "data.used_quota")
        XCTAssertEqual(normalized.relayConfig?.manualOverrides?.limitExpression, "add(data.quota,data.used_quota)")
        XCTAssertEqual(normalized.relayConfig?.manualOverrides?.unitExpression, "quota")
        XCTAssertEqual(normalized.relayConfig?.manualOverrides?.userID, "1")
    }

    func testFetchSupportsSumAndCoalesceExpressions() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ok-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"meta":{"ok":1},"items":[{"quota":2.5},{"quota":4.5}]}"#
            return (response, Data(json.utf8))
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let manifest = RelayAdapterManifest(
            id: "sum-test",
            displayName: "Sum Test",
            match: RelayAdapterMatch(
                hostPatterns: ["sum.example.com"],
                defaultDisplayName: "Sum Test",
                defaultTokenChannelEnabled: false,
                defaultBalanceChannelEnabled: true
            ),
            authStrategies: [RelayAuthStrategy(kind: .savedBearer)],
            balanceRequest: RelayRequestManifest(
                method: "GET",
                path: "/balance",
                authHeader: "Authorization",
                authScheme: "Bearer"
            ),
            tokenRequest: nil,
            extract: RelayExtractManifest(
                success: "coalesce(meta.ok, success)",
                remaining: "sum(items.*.quota)",
                unit: "\"credits\""
            ),
            postprocessID: nil
        )

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("ok-token", service: service, account: "sum.example.com/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "sum-test", baseURL: "https://sum.example.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(),
            registry: RelayAdapterRegistry(builtInManifests: [manifest, RelayAdapterRegistry.genericManifest])
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 7, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "credits")
    }

    func testFetchSupportsAddExpression() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ok-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"data":{"a":[{"v":"2.5"}],"b":[{"v":"1.5"},{"v":"3.0"}]}}"#
            return (response, Data(json.utf8))
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let manifest = RelayAdapterManifest(
            id: "add-test",
            displayName: "Add Test",
            match: RelayAdapterMatch(
                hostPatterns: ["add.example.com"],
                defaultDisplayName: "Add Test",
                defaultTokenChannelEnabled: false,
                defaultBalanceChannelEnabled: true
            ),
            authStrategies: [RelayAuthStrategy(kind: .savedBearer)],
            balanceRequest: RelayRequestManifest(
                method: "GET",
                path: "/balance",
                authHeader: "Authorization",
                authScheme: "Bearer"
            ),
            tokenRequest: nil,
            extract: RelayExtractManifest(
                remaining: "add(sum(data.a.*.v),sum(data.b.*.v))",
                unit: "\"credits\""
            ),
            postprocessID: nil
        )

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("ok-token", service: service, account: "add.example.com/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "add-test", baseURL: "https://add.example.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(),
            registry: RelayAdapterRegistry(builtInManifests: [manifest, RelayAdapterRegistry.genericManifest])
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 7.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "credits")
    }

    func testExpiredSavedBearerReturnsUnauthorizedDetail() async throws {
        let expiredToken = makeJWT(exp: Int(Date().timeIntervalSince1970) - 60)
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let host = "expired-bearer.invalid"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken(expiredToken, service: service, account: "\(host)/system-token"))

        let manifest = RelayAdapterManifest(
            id: "expired-bearer-only",
            displayName: "Expired Bearer Only",
            match: RelayAdapterMatch(
                hostPatterns: [host],
                defaultDisplayName: "Expired Bearer Only",
                defaultTokenChannelEnabled: false,
                defaultBalanceChannelEnabled: true
            ),
            authStrategies: [RelayAuthStrategy(kind: .savedBearer)],
            balanceRequest: RelayRequestManifest(
                method: "GET",
                path: "/api/user/self",
                authHeader: "Authorization",
                authScheme: "Bearer"
            ),
            tokenRequest: nil,
            extract: RelayExtractManifest(
                success: "success",
                remaining: "data.quota"
            ),
            postprocessID: nil
        )

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "expired-bearer-only", baseURL: "https://\(host)"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(bearerCandidatesOverride: { _ in [] }),
            registry: RelayAdapterRegistry(builtInManifests: [manifest, RelayAdapterRegistry.genericManifest])
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorized detail for expired JWT")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertTrue(message.contains("expired"))
        }
    }

    func testPostprocessConvertsAilinyuQuotaToDisplayAmount() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "New-Api-User"), "777")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/api/status" {
                let json = #"{"data":{"quota_per_unit":2,"quota_display_type":"CNY","usd_exchange_rate":7}}"#
                return (response, Data(json.utf8))
            }
            let json = #"{"success":true,"data":{"quota":100,"used_quota":20,"request_quota":120}}"#
            return (response, Data(json.utf8))
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("cookie=value", service: service, account: "open.ailinyu.de/session-cookie"))

        var descriptor = makeRelayDescriptor(
            service: service,
            adapterID: "ailinyu",
            baseURL: "https://open.ailinyu.de"
        )
        descriptor.relayConfig?.balanceAuth.keychainAccount = "open.ailinyu.de/session-cookie"
        descriptor.relayConfig?.manualOverrides = RelayManualOverride(
            authHeader: "Cookie",
            authScheme: "",
            userID: "777"
        )

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { _ in nil }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 350, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "¥")
    }

    func testHongmaccAutoProbeFallsBackToKeyBalance() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ok-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/user/assets":
                // Missing quotaCards path so provider should probe next endpoint.
                return (response, Data(#"{"data":{"assets":[]}}"#.utf8))
            case "/api/user/key-balance":
                return (response, Data(#"{"quota":{"remainingQuota":"87.23","usedCost":"42.76","totalCostLimit":"130.00"}}"#.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("ok-token", service: service, account: "hongmacc.com/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "hongmacc", baseURL: "https://hongmacc.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 87.23, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.rawMeta["account.endpointPath"], "/api/user/key-balance")
    }

    func testXiaomimimoAutoProbeFallsBackToBalanceEndpoint() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "platform_serviceToken=abc123; userId=10001")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/userProfile":
                return (response, Data(#"{"data":{"nickname":"mimo-user"}}"#.utf8))
            case "/api/v1/balance":
                return (response, Data(#"{"data":{"availableBalance":"88.56","monthlyUsage":"1.44"}}"#.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("platform_serviceToken=abc123; userId=10001", service: service, account: "platform.xiaomimimo.com/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "xiaomimimo", baseURL: "https://platform.xiaomimimo.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 88.56, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.rawMeta["account.endpointPath"], "/api/v1/balance")
    }

    func testXiaomimimoCarriesTokenPlanAcrossProbeRequests() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "platform_serviceToken=abc123; userId=10001")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/userProfile":
                return (
                    response,
                    Data(#"{"data":{"nickname":"mimo-user","currentTokenPlan":{"plan_name":"token-plan-standard"}}}"#.utf8)
                )
            case "/api/v1/balance":
                return (
                    response,
                    Data(#"{"payload":{"wallet":{"available_amount":"88.56"},"usage":{"monthly_spend":"1.44"}}}"#.utf8)
                )
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("platform_serviceToken=abc123; userId=10001", service: service, account: "platform.xiaomimimo.com/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "xiaomimimo", baseURL: "https://platform.xiaomimimo.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 88.56, accuracy: 0.001)
        XCTAssertEqual(snapshot.used ?? -1, 1.44, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "Standard")
        XCTAssertEqual(snapshot.rawMeta["planType"], "Standard")
        XCTAssertEqual(snapshot.rawMeta["account.planType"], "Standard")
        XCTAssertTrue(snapshot.note.contains("Plan Standard"))
    }

    func testXiaomimimoTokenPlanFetchBuildsQuotaWindow() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "api-platform_serviceToken=abc123; userId=10001")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/tokenPlan/detail":
                return (
                    response,
                    Data(#"{"code":0,"message":"","data":{"planCode":"standard","planName":"Standard","currentPeriodEnd":"2026-05-28 23:59:59","expired":false,"enableAutoRenew":false}}"#.utf8)
                )
            case "/api/v1/tokenPlan/usage":
                return (
                    response,
                    Data(#"{"code":0,"message":"","data":{"usage":{"percent":0.0,"items":[{"name":"plan_total_token","used":0,"limit":11000000000,"percent":0.0},{"name":"compensation_total_token","used":48014368,"limit":3285714286,"percent":1.0}]}}}"#.utf8)
                )
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "api-platform_serviceToken=abc123; userId=10001",
                service: service,
                account: "platform.xiaomimimo.com/session-cookie"
            )
        )

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(
                service: service,
                adapterID: "xiaomimimo-token-plan",
                baseURL: "https://platform.xiaomimimo.com",
                balanceAccount: "platform.xiaomimimo.com/session-cookie"
            ),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        let expectedUsedPercent = (48_014_368.0 / 14_285_714_286.0) * 100
        let expectedRemainingPercent = 100 - expectedUsedPercent

        XCTAssertEqual(snapshot.unit, "%")
        XCTAssertEqual(snapshot.remaining ?? -1, expectedRemainingPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.used ?? -1, expectedUsedPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.limit ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "Standard")
        XCTAssertEqual(snapshot.rawMeta["account.tokenPlanCurrentPeriodEnd"], "2026-05-28 23:59:59")
        XCTAssertEqual(snapshot.rawMeta["account.quotaValueText.token-plan-total"], "48,014,368 / 14,285,714,286")
        XCTAssertEqual(snapshot.rawMeta["account.tokenPlanUsageName"], "plan_total_token,compensation_total_token")
        XCTAssertEqual(snapshot.rawMeta["account.tokenPlanUsageItemCount"], "2")
        XCTAssertEqual(snapshot.rawMeta["account.tokenPlanRemaining"], "14237699918")
        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.title, "Total Usage")
        XCTAssertEqual(snapshot.quotaWindows.first?.usedPercent ?? -1, expectedUsedPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.quotaWindows.first?.remainingPercent ?? -1, expectedRemainingPercent, accuracy: 0.000001)
    }

    func testXiaomimimoTokenPlanUsesDerivedPercentWhenItemPercentIsZero() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "api-platform_serviceToken=abc123; userId=10001")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/tokenPlan/detail":
                return (
                    response,
                    Data(#"{"code":0,"message":"","data":{"planCode":"standard","planName":"Standard","currentPeriodEnd":"2026-05-28 23:59:59","expired":false,"enableAutoRenew":false}}"#.utf8)
                )
            case "/api/v1/tokenPlan/usage":
                return (
                    response,
                    Data(#"{"code":0,"message":"","data":{"usage":{"percent":0.0,"items":[{"name":"plan_total_token","used":7804244,"limit":200000000,"percent":0.0},{"name":"compensation_total_token","used":0,"limit":0,"percent":0}]}}}"#.utf8)
                )
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "api-platform_serviceToken=abc123; userId=10001",
                service: service,
                account: "platform.xiaomimimo.com/session-cookie"
            )
        )

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(
                service: service,
                adapterID: "xiaomimimo-token-plan",
                baseURL: "https://platform.xiaomimimo.com",
                balanceAccount: "platform.xiaomimimo.com/session-cookie"
            ),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        let expectedUsedPercent = 3.902122
        let expectedRemainingPercent = 100 - expectedUsedPercent

        XCTAssertEqual(snapshot.used ?? -1, expectedUsedPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.remaining ?? -1, expectedRemainingPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.quotaWindows.first?.usedPercent ?? -1, expectedUsedPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.quotaWindows.first?.remainingPercent ?? -1, expectedRemainingPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.rawMeta["account.quotaValueText.token-plan-total"], "7,804,244 / 200,000,000")
        XCTAssertEqual(snapshot.rawMeta["account.tokenPlanUsedPercentSource"], "usedLimitDerived")
        XCTAssertEqual(Double(snapshot.rawMeta["account.tokenPlanUsedPercentRaw"] ?? "") ?? -1, 0, accuracy: 0.000001)
        XCTAssertEqual(Double(snapshot.rawMeta["account.tokenPlanUsedPercentDerived"] ?? "") ?? -1, expectedUsedPercent, accuracy: 0.000001)
    }

    func testXiaomimimoTokenPlanPrefersDerivedPercentWhenAPIReportsFraction() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "api-platform_serviceToken=abc123; userId=10001")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/tokenPlan/detail":
                return (
                    response,
                    Data(#"{"code":0,"message":"","data":{"planCode":"standard","planName":"Standard","currentPeriodEnd":"2026-05-28 23:59:59","expired":false,"enableAutoRenew":false}}"#.utf8)
                )
            case "/api/v1/tokenPlan/usage":
                return (
                    response,
                    Data(#"{"code":0,"message":"","data":{"usage":{"percent":0.03902122,"items":[{"name":"plan_total_token","used":7804244,"limit":200000000,"percent":0.03902122}]}}}"#.utf8)
                )
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "api-platform_serviceToken=abc123; userId=10001",
                service: service,
                account: "platform.xiaomimimo.com/session-cookie"
            )
        )

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(
                service: service,
                adapterID: "xiaomimimo-token-plan",
                baseURL: "https://platform.xiaomimimo.com",
                balanceAccount: "platform.xiaomimimo.com/session-cookie"
            ),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        let expectedUsedPercent = 3.902122

        XCTAssertEqual(snapshot.used ?? -1, expectedUsedPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.quotaWindows.first?.usedPercent ?? -1, expectedUsedPercent, accuracy: 0.000001)
        XCTAssertEqual(Double(snapshot.rawMeta["account.tokenPlanUsedPercentRaw"] ?? "") ?? -1, 0.03902122, accuracy: 0.000001)
        XCTAssertEqual(Double(snapshot.rawMeta["account.tokenPlanUsedPercentDerived"] ?? "") ?? -1, expectedUsedPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.rawMeta["account.tokenPlanUsedPercentSource"], "usedLimitDerived")
    }

    func testXiaomimimoTokenPlanFallsBackToPositiveLimitItemWhenNamesChange() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "api-platform_serviceToken=abc123; userId=10001")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/tokenPlan/detail":
                return (
                    response,
                    Data(#"{"code":0,"message":"","data":{"planCode":"standard","planName":"Standard","currentPeriodEnd":"2026-05-28 23:59:59","expired":false,"enableAutoRenew":false}}"#.utf8)
                )
            case "/api/v1/tokenPlan/usage":
                return (
                    response,
                    Data(#"{"code":0,"message":"","data":{"usage":{"items":[{"name":"placeholder_item","used":0,"limit":0,"percent":0},{"name":"mystery_package","used":7804244,"limit":200000000,"percent":0.03902122}]}}}"#.utf8)
                )
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "api-platform_serviceToken=abc123; userId=10001",
                service: service,
                account: "platform.xiaomimimo.com/session-cookie"
            )
        )

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(
                service: service,
                adapterID: "xiaomimimo-token-plan",
                baseURL: "https://platform.xiaomimimo.com",
                balanceAccount: "platform.xiaomimimo.com/session-cookie"
            ),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        let expectedUsedPercent = 3.902122

        XCTAssertEqual(snapshot.used ?? -1, expectedUsedPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.quotaWindows.first?.usedPercent ?? -1, expectedUsedPercent, accuracy: 0.000001)
        XCTAssertEqual(snapshot.rawMeta["account.tokenPlanUsageName"], "mystery_package")
        XCTAssertEqual(snapshot.rawMeta["account.quotaValueText.token-plan-total"], "7,804,244 / 200,000,000")
    }

    func testXiaomimimoCookieAutoDetectionFallsBackToParentDomain() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "api-platform_serviceToken=cookie123; userid=20002")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/userProfile":
                return (response, Data(#"{"data":{"nickname":"mimo-user"}}"#.utf8))
            case "/api/v1/balance":
                return (response, Data(#"{"data":{"availableBalance":"66.60"}}"#.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        var descriptor = makeRelayDescriptor(service: service, adapterID: "xiaomimimo", baseURL: "https://platform.xiaomimimo.com")
        descriptor.relayConfig?.balanceCredentialMode = .browserPreferred

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                cookieHeaderOverride: { host in
                    guard host == "xiaomimimo.com" else { return nil }
                    return BrowserDetectedCredential(value: "api-platform_serviceToken=cookie123; userid=20002", source: "browser")
                }
            )
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.remaining ?? -1, 66.60, accuracy: 0.001)
        XCTAssertEqual(snapshot.rawMeta["account.authSource"], "browserCookieHeader:browser")
    }

    func testXiaomimimoIgnoresBearerLikeSavedCookieAndUsesBrowserCookie() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "api-platform_serviceToken=freshCookie; userid=30003")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/userProfile":
                return (response, Data(#"{"data":{"nickname":"mimo-user"}}"#.utf8))
            case "/api/v1/balance":
                return (response, Data(#"{"data":{"availableBalance":"77.70"}}"#.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "Bearer not-a-cookie-token",
                service: service,
                account: "platform.xiaomimimo.com/system-token"
            )
        )
        var descriptor = makeRelayDescriptor(service: service, adapterID: "xiaomimimo", baseURL: "https://platform.xiaomimimo.com")
        descriptor.relayConfig?.balanceCredentialMode = .browserPreferred

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                cookieHeaderOverride: { host in
                    guard host == "platform.xiaomimimo.com" else { return nil }
                    return BrowserDetectedCredential(value: "api-platform_serviceToken=freshCookie; userid=30003", source: "browser")
                }
            )
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.remaining ?? -1, 77.70, accuracy: 0.001)
        XCTAssertEqual(snapshot.rawMeta["account.authSource"], "browserCookieHeader:browser")
    }

    func testXiaomimimoBalanceProbeSupportsNestedResultPayload() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "api-platform_serviceToken=cookie123; userId=10001")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/userProfile":
                return (response, Data(#"{"data":{"nickname":"mimo-user"}}"#.utf8))
            case "/api/v1/balance":
                return (response, Data(#"{"data":{"result":{"available_amount":"5.00","monthly_spend":"0.25","total_amount":"20.00"}}}"#.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "api-platform_serviceToken=cookie123; userId=10001",
                service: service,
                account: "platform.xiaomimimo.com/system-token"
            )
        )

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "xiaomimimo", baseURL: "https://platform.xiaomimimo.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 5.00, accuracy: 0.001)
        XCTAssertEqual(snapshot.used ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(snapshot.limit ?? -1, 20.00, accuracy: 0.001)
    }

    func testXiaomimimoBalanceProbeSupportsRecursiveFallbackKeys() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "api-platform_serviceToken=cookie456; userId=10002")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/userProfile":
                return (response, Data(#"{"data":{"nickname":"mimo-user"}}"#.utf8))
            case "/api/v1/balance":
                return (response, Data(#"{"payload":{"wallet":{"available_amount":"6.66"},"usage":{"monthly_spend":"1.11"},"quota":{"total_amount":"30.00"}}}"#.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "api-platform_serviceToken=cookie456; userId=10002",
                service: service,
                account: "platform.xiaomimimo.com/system-token"
            )
        )

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "xiaomimimo", baseURL: "https://platform.xiaomimimo.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 6.66, accuracy: 0.001)
        XCTAssertEqual(snapshot.used ?? -1, 1.11, accuracy: 0.001)
        XCTAssertEqual(snapshot.limit ?? -1, 30.00, accuracy: 0.001)
        XCTAssertEqual(snapshot.rawMeta["account.remainingPath"], "xiaomimimoRecursiveFallback")
    }

    func testXiaomimimoUnauthorizedShowsHelpfulLoginExpiredMessage() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        var descriptor = makeRelayDescriptor(
            service: service,
            adapterID: "xiaomimimo",
            baseURL: "https://platform.xiaomimimo.com"
        )
        descriptor.relayConfig?.balanceCredentialMode = .browserPreferred

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                cookieHeaderOverride: { _ in
                    return BrowserDetectedCredential(
                        value: "api-platform_serviceToken=staleCookie; userId=10001",
                        source: "browser"
                    )
                }
            )
        )

        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            switch error {
            case .unauthorizedDetail(let message):
                XCTAssertTrue(message.contains("xiaomimimo login expired"))
            case .missingCredential(let account):
                XCTAssertEqual(account, "platform.xiaomimimo.com/system-token")
            default:
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
        }
    }

    func testXiaomimimoBrowserOnlyWithoutBrowserCookieShowsHelpfulPreflightMessage() async throws {
        RelayMockURLProtocol.requestHandler = { _ in
            XCTFail("Preflight should stop before any network request")
            let response = HTTPURLResponse(url: URL(string: "https://platform.xiaomimimo.com/api/v1/userProfile")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        var descriptor = makeRelayDescriptor(service: service, adapterID: "xiaomimimo", baseURL: "https://platform.xiaomimimo.com")
        descriptor.relayConfig?.balanceCredentialMode = .browserOnly

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { _ in nil }
            )
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertTrue(message.contains("No live XiaomiMIMO login"))
        }
    }

    func testMinimaxTemplateInjectsGroupIDIntoAbsoluteAccountEndpoint() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "www.minimaxi.com")
            XCTAssertEqual(request.url?.path, "/account/query_balance")
            XCTAssertEqual(request.url?.query, "GroupId=2026882600953450775")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "SESSION=minimax-cookie")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://platform.minimaxi.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://platform.minimaxi.com/")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"available_amount":"12.34","base_resp":{"status_code":0,"status_msg":"success"}}"#.utf8))
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "SESSION=minimax-cookie",
                service: service,
                account: "platform.minimaxi.com/system-token"
            )
        )

        var descriptor = makeRelayDescriptor(
            service: service,
            adapterID: "minimax",
            baseURL: "https://platform.minimaxi.com"
        )
        descriptor.relayConfig?.manualOverrides = RelayManualOverride(
            userID: "2026882600953450775"
        )

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 12.34, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.rawMeta["relay.adapterID"], "minimax")
        XCTAssertEqual(snapshot.rawMeta["account.userID"], "2026882600953450775")
    }

    func testMinimaxMissingGroupIDShowsHelpfulPreflightMessage() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "SESSION=minimax-cookie",
                service: service,
                account: "platform.minimaxi.com/system-token"
            )
        )

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "minimax", baseURL: "https://platform.minimaxi.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertTrue(message.contains("GroupId"))
        }
    }

    func testMinimaxAutoProbeFallsBackToQueryBalanceEndpoint() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "SESSION=minimax-cookie")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch (request.url?.host, request.url?.path, request.url?.query) {
            case ("www.minimaxi.com", "/account/query_balance", "GroupId=2026882600953450775"):
                return (response, Data(#"{"data":{"groupName":"minimax-team"}}"#.utf8))
            case ("www.minimaxi.com", "/backend/account", "GroupId=2026882600953450775"):
                return (response, Data(#"{"account_info":{"name":"minimax-team"},"base_resp":{"status_code":0,"status_msg":"success"}}"#.utf8))
            case ("www.minimaxi.com", "/backend/query_balance", "GroupId=2026882600953450775"):
                return (response, Data(#"{"data":{"availableBalance":"9.99","monthlySpend":"1.23"}}"#.utf8))
            default:
                let notFound = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (notFound, Data("404 page not found".utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "SESSION=minimax-cookie",
                service: service,
                account: "platform.minimaxi.com/system-token"
            )
        )

        var descriptor = makeRelayDescriptor(
            service: service,
            adapterID: "minimax",
            baseURL: "https://platform.minimaxi.com"
        )
        descriptor.relayConfig?.manualOverrides = RelayManualOverride(
            userID: "2026882600953450775"
        )

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 9.99, accuracy: 0.001)
        XCTAssertEqual(snapshot.used ?? -1, 1.23, accuracy: 0.001)
        XCTAssertEqual(snapshot.rawMeta["account.endpointPath"], "/https://www.minimaxi.com/backend/query_balance?GroupId=2026882600953450775")
    }

    func testMoonshotQueryPathAndProbeFallbackExtractsBalance() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer moon-token")
            XCTAssertEqual(request.url?.path, "/api")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.query {
            case "endpoint=userInfo":
                // Missing balance fields to force fallback probe request.
                return (response, Data(#"{"data":{"nickname":"moon-user"}}"#.utf8))
            case "endpoint=organizationAccountInfo":
                return (response, Data(#"{"data":{"balance":"6056.65","monthlySpend":"12.30","totalLimit":"7000"}}"#.utf8))
            default:
                XCTFail("Unexpected query \(request.url?.query ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("moon-token", service: service, account: "platform.moonshot.cn/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "moonshot", baseURL: "https://platform.moonshot.cn"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { _ in nil }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 6056.65, accuracy: 0.0001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.rawMeta["account.endpointPath"], "/api?endpoint=organizationAccountInfo")
        XCTAssertEqual(snapshot.rawMeta["relay.adapterID"], "moonshot")
    }

    func testMoonshotUserInfoOIDFallbackExtractsOrganizationBalance() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer moon-token")
            XCTAssertEqual(request.url?.path, "/api")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.query {
            case "endpoint=userInfo":
                return (response, Data(#"{"data":{"currentOrganizationId":"org-test-001","nickname":"moon-user"}}"#.utf8))
            case "endpoint=organizationAccountInfo&oid=org-test-001":
                return (response, Data(#"{"data":{"balance":"4321.00","monthlySpend":"99.50","totalLimit":"5000"}}"#.utf8))
            default:
                XCTFail("Unexpected query \(request.url?.query ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("moon-token", service: service, account: "platform.moonshot.cn/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "moonshot", baseURL: "https://platform.moonshot.cn"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { _ in nil }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 4321.00, accuracy: 0.0001)
        XCTAssertEqual(snapshot.rawMeta["account.endpointPath"], "/api?endpoint=organizationAccountInfo&oid=org-test-001")
        XCTAssertEqual(snapshot.rawMeta["account.organizationID"], "org-test-001")
    }

    func testMoonshotSavedCookieUsesCookieHeaderInsteadOfAuthorization() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=moon-cookie")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.query {
            case "endpoint=userInfo":
                return (response, Data(#"{"data":{"nickname":"moon-user"}}"#.utf8))
            case "endpoint=organizationAccountInfo":
                return (response, Data(#"{"data":{"balance":"12.34"}}"#.utf8))
            default:
                XCTFail("Unexpected query \(request.url?.query ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("session=moon-cookie", service: service, account: "platform.moonshot.cn/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "moonshot", baseURL: "https://platform.moonshot.cn"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { _ in nil }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 12.34, accuracy: 0.0001)
        XCTAssertEqual(snapshot.rawMeta["account.authSource"], "savedCookieHeader")
    }

    func testMoonshotOrganizationsArrayOIDFallbackSupportsCurAccUseShape() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.query {
            case "endpoint=userInfo":
                return (response, Data(#"{"code":0,"data":{"organizations":[{"organization":{"id":"org-live-shape"}}]}}"#.utf8))
            case "endpoint=organizationAccountInfo":
                let missingOrg = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (missingOrg, Data(#"{"code":"organization_not_found","message":"组织不存在","status":404}"#.utf8))
            case "endpoint=organizationAccountInfo&oid=org-live-shape":
                return (response, Data(#"{"code":0,"data":{"cur":158833,"acc":5000000,"use":6341167}}"#.utf8))
            default:
                XCTFail("Unexpected query \(request.url?.query ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("moon-token", service: service, account: "platform.moonshot.cn/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "moonshot", baseURL: "https://platform.moonshot.cn"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { _ in nil }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 1.58833, accuracy: 0.000001)
        XCTAssertEqual(snapshot.used ?? -1, 63.41167, accuracy: 0.000001)
        XCTAssertEqual(snapshot.limit ?? -1, 50.0, accuracy: 0.000001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.rawMeta["account.organizationID"], "org-live-shape")
        XCTAssertEqual(snapshot.rawMeta["account.valueScale"], "100000")
        XCTAssertEqual(snapshot.rawMeta["account.rawRemaining"], "158833.0")
    }

    func testMoonshotOrganizationAccountInfoFallsBackViaOrganizationListWithoutUserInfoOID() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.query {
            case "endpoint=userInfo":
                return (response, Data(#"{"data":{"nickname":"moon-user"}}"#.utf8))
            case "endpoint=organizationAccountInfo":
                return (response, Data(#"{"data":{"organizations":[{"organization":{"id":"org-probe-002"}}]}}"#.utf8))
            case "endpoint=organizationAccountInfo&oid=org-probe-002":
                return (response, Data(#"{"data":{"balance":"123.45","monthlySpend":"6.78","totalLimit":"200.00"}}"#.utf8))
            default:
                XCTFail("Unexpected query \(request.url?.query ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("moon-token", service: service, account: "platform.moonshot.cn/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "moonshot", baseURL: "https://platform.moonshot.cn"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { _ in nil }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 123.45, accuracy: 0.0001)
        XCTAssertEqual(snapshot.used ?? -1, 6.78, accuracy: 0.0001)
        XCTAssertEqual(snapshot.limit ?? -1, 200.00, accuracy: 0.0001)
        XCTAssertEqual(snapshot.rawMeta["account.organizationID"], "org-probe-002")
    }

    func testMoonshotAnalyticsOnlyCookieShowsHelpfulError() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(
            keychain.saveToken(
                "INGRESSCOOKIE=abc|def; _ga=GA1.1.1.1; _clck=test; _clsk=test",
                service: service,
                account: "platform.moonshot.cn/system-token"
            )
        )

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "moonshot", baseURL: "https://platform.moonshot.cn"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { _ in nil }
            )
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected helpful unauthorizedDetail for analytics-only cookie")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertTrue(message.contains("full Cookie header"))
        }
    }

    func testMoonshotBrowserPreferredUsesBrowserBearerBeforeExpiredSavedToken() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-browser-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.query {
            case "endpoint=userInfo":
                return (response, Data(#"{"data":{"currentOrganizationId":"org-browser-001"}}"#.utf8))
            case "endpoint=organizationAccountInfo&oid=org-browser-001":
                return (response, Data(#"{"data":{"balance":"20.50"}}"#.utf8))
            default:
                XCTFail("Unexpected query \(request.url?.query ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken(makeJWT(exp: Int(Date().timeIntervalSince1970) - 60), service: service, account: "platform.moonshot.cn/system-token"))

        var descriptor = makeRelayDescriptor(service: service, adapterID: "moonshot", baseURL: "https://platform.moonshot.cn")
        descriptor.relayConfig?.balanceCredentialMode = .browserPreferred

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { host in
                    guard host == "platform.moonshot.cn" else { return [] }
                    return [BrowserDetectedCredential(value: "fresh-browser-token", source: "browser")]
                },
                cookieHeaderOverride: { _ in nil }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 20.50, accuracy: 0.001)
        XCTAssertEqual(snapshot.rawMeta["account.authSource"], "browserBearer:browser")
    }

    func testBrowserOnlyModeIgnoresSavedCookieAndUsesBrowserCookie() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "api-platform_serviceToken=fresh-browser-cookie; userid=40004")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/v1/userProfile":
                return (response, Data(#"{"data":{"nickname":"mimo-user"}}"#.utf8))
            case "/api/v1/balance":
                return (response, Data(#"{"data":{"availableBalance":"18.80"}}"#.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (response, Data(#"{}"#.utf8))
            }
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("api-platform_serviceToken=stale-cookie; userid=11111", service: service, account: "platform.xiaomimimo.com/system-token"))

        var descriptor = makeRelayDescriptor(service: service, adapterID: "xiaomimimo", baseURL: "https://platform.xiaomimimo.com")
        descriptor.relayConfig?.balanceCredentialMode = .browserOnly

        let provider = RelayProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                cookieHeaderOverride: { host in
                    guard host == "platform.xiaomimimo.com" else { return nil }
                    return BrowserDetectedCredential(value: "api-platform_serviceToken=fresh-browser-cookie; userid=40004", source: "browser")
                }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 18.80, accuracy: 0.001)
        XCTAssertEqual(snapshot.rawMeta["account.authSource"], "browserCookieHeader:browser")
    }

    func testDeepseekSummaryExtractsWalletBalance() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ok-token")
            XCTAssertEqual(request.url?.path, "/api/v0/users/get_user_summary")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"""
            {
              "code": 0,
              "msg": "",
              "data": {
                "biz_code": 0,
                "biz_msg": "",
                "biz_data": {
                  "current_token": 10000000,
                  "monthly_usage": 0,
                  "total_usage": 0,
                  "normal_wallets": [
                    { "currency": "CNY", "balance": "9.4236872000000000", "token_estimation": "3141229" }
                  ],
                  "bonus_wallets": [
                    { "currency": "CNY", "balance": "0", "token_estimation": "0" }
                  ],
                  "total_available_token_estimation": "3141229",
                  "monthly_costs": [
                    { "currency": "CNY", "amount": "0" }
                  ],
                  "monthly_token_usage": 0
                }
              }
            }
            """#
            return (response, Data(json.utf8))
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("ok-token", service: service, account: "platform.deepseek.com/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "deepseek", baseURL: "https://platform.deepseek.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 9.4236872, accuracy: 0.000001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.rawMeta["relay.adapterID"], "deepseek")
    }

    func testDeepseekFallsBackToBearerPlusCookieWhenBearerOnlyReturnsHTML() async throws {
        RelayMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v0/users/get_user_summary")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let auth = request.value(forHTTPHeaderField: "Authorization")
            let cookie = request.value(forHTTPHeaderField: "Cookie")
            XCTAssertEqual(auth, "Bearer ok-token")
            if cookie == nil {
                return (response, Data("<html>challenge</html>".utf8))
            }
            let json = #"""
            {
              "code": 0,
              "msg": "",
              "data": {
                "biz_code": 0,
                "biz_msg": "",
                "biz_data": {
                  "normal_wallets": [{ "currency": "CNY", "balance": "9.42" }],
                  "bonus_wallets": [{ "currency": "CNY", "balance": "0.58" }],
                  "monthly_costs": [{ "currency": "CNY", "amount": "0.1" }]
                }
              }
            }
            """#
            return (response, Data(json.utf8))
        }
        defer { RelayMockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("ok-token", service: service, account: "platform.deepseek.com/system-token"))

        let provider = RelayProvider(
            descriptor: makeRelayDescriptor(service: service, adapterID: "deepseek", baseURL: "https://platform.deepseek.com"),
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { host in
                    guard host == "platform.deepseek.com" else { return nil }
                    return BrowserDetectedCredential(value: "session=abc123", source: "browser")
                }
            )
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 10.0, accuracy: 0.000001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.rawMeta["account.authSource"], "savedBearer+cookie:browser")
    }

    private func makeRelayDescriptor(
        service: String,
        adapterID: String,
        baseURL: String,
        balanceAccount: String? = nil
    ) -> ProviderDescriptor {
        let host = URL(string: baseURL)?.host ?? "relay.example"
        return ProviderDescriptor(
            id: "relay-test-\(adapterID)",
            name: "Relay Test",
            type: .relay,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: service, keychainAccount: "\(host)/sk-token"),
            baseURL: baseURL,
            relayConfig: RelayProviderConfig(
                adapterID: adapterID,
                baseURL: baseURL,
                tokenChannelEnabled: false,
                balanceChannelEnabled: true,
                balanceAuth: AuthConfig(
                    kind: .bearer,
                    keychainService: service,
                    keychainAccount: balanceAccount ?? "\(host)/system-token"
                ),
                manualOverrides: nil
            )
        )
    }

    private func genericNewAPIDescriptor(
        service: String,
        baseURL: String,
        userID: String
    ) -> ProviderDescriptor {
        var descriptor = makeRelayDescriptor(
            service: service,
            adapterID: "generic-newapi",
            baseURL: baseURL
        )
        descriptor.relayConfig?.manualOverrides = RelayManualOverride(
            authHeader: "Authorization",
            authScheme: "Bearer",
            userID: userID,
            userIDHeader: "New-Api-User",
            requestMethod: nil,
            requestBodyJSON: nil,
            endpointPath: nil,
            remainingExpression: nil,
            usedExpression: nil,
            limitExpression: nil,
            successExpression: nil,
            unitExpression: nil,
            accountLabelExpression: nil,
            staticHeaders: nil
        )
        return descriptor
    }

    private func makeJWT(exp: Int) -> String {
        let header = #"{"alg":"HS256","typ":"JWT"}"#
        let payload = #"{"exp":\#(exp)}"#
        return "\(b64url(header)).\(b64url(payload)).signature"
    }

    private func b64url(_ input: String) -> String {
        Data(input.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class RelayMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = RelayMockURLProtocol.requestHandler else {
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
