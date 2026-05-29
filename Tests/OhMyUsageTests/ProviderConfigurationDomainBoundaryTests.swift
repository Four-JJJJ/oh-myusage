import Foundation
import OhMyUsageDomain
import XCTest

final class ProviderConfigurationDomainBoundaryTests: XCTestCase {
    func testProviderConfigurationIsPublicDomainCodableEquatableSendableValue() throws {
        assertCodableEquatableSendable(ProviderConfiguration.self)
        assertCodableEquatableSendable(ProviderSettings.self)

        let configuration = ProviderConfiguration(
            id: "codex-official",
            name: "Official Codex",
            family: .official,
            type: .codex,
            settings: ProviderSettings(
                enabled: true,
                pollIntervalSec: 180,
                threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
                auth: AuthConfig(kind: .localCodex),
                showInMenuBar: true,
                baseURL: "https://chatgpt.com",
                officialConfig: OfficialProviderConfig(quotaDisplayMode: .used)
            )
        )

        let roundTripped = try JSONDecoder().decode(
            ProviderConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        XCTAssertEqual(roundTripped, configuration)
        XCTAssertEqual(roundTripped.settings.officialConfig?.quotaDisplayMode, .used)
    }

    func testProviderConfigurationDoesNotPersistPresentationOrRuntimeFields() throws {
        let json = """
        {
          "id": "relay-example",
          "name": "Relay Example",
          "family": "thirdParty",
          "type": "relay",
          "enabled": true,
          "pollIntervalSec": 120,
          "threshold": {
            "lowRemaining": 10,
            "maxConsecutiveFailures": 3,
            "notifyOnAuthError": true
          },
          "auth": {
            "kind": "bearer",
            "keychainService": "OhMyUsage",
            "keychainAccount": "relay.example/sk-token"
          },
          "showInMenuBar": true,
          "baseURL": "https://relay.example",
          "displayName": "Runtime display name",
          "icon": "menu_relay_icon",
          "settingsSpec": { "sections": [] },
          "factory": "RelayProviderFactory",
          "providerRuntime": { "lastRefreshStarted": 1700000000 }
        }
        """

        let configuration = try JSONDecoder().decode(
            ProviderConfiguration.self,
            from: Data(json.utf8)
        )
        let encoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any]
        )

        XCTAssertEqual(configuration.id, "relay-example")
        XCTAssertNil(encoded["displayName"])
        XCTAssertNil(encoded["icon"])
        XCTAssertNil(encoded["settingsSpec"])
        XCTAssertNil(encoded["factory"])
        XCTAssertNil(encoded["providerRuntime"])
    }

    func testAuthConfigAndAlertRuleAreDomainCodableValues() throws {
        let auth = try JSONDecoder().decode(
            AuthConfig.self,
            from: Data(
                """
                {
                  "kind": "bearer",
                  "keychainService": "com.example.usage",
                  "keychainAccount": "account@example.com"
                }
                """.utf8
            )
        )
        let alert = try JSONDecoder().decode(
            AlertRule.self,
            from: Data(
                """
                {
                  "lowRemaining": 15,
                  "maxConsecutiveFailures": 2,
                  "notifyOnAuthError": true
                }
                """.utf8
            )
        )

        XCTAssertEqual(auth.kind, .bearer)
        XCTAssertEqual(auth.keychainService, "com.example.usage")
        XCTAssertEqual(auth.keychainAccount, "account@example.com")
        XCTAssertEqual(alert.lowRemaining, 15)
        XCTAssertEqual(alert.maxConsecutiveFailures, 2)
        XCTAssertTrue(alert.notifyOnAuthError)
    }

    func testOfficialProviderConfigKeepsStageOneDecodeDefaultsInDomain() throws {
        let config = try JSONDecoder().decode(
            OfficialProviderConfig.self,
            from: Data("{}".utf8)
        )

        XCTAssertEqual(config.sourceMode, .auto)
        XCTAssertEqual(config.webMode, .disabled)
        XCTAssertNil(config.manualCookieAccount)
        XCTAssertNil(config.oauthAccountImportEnabled)
        XCTAssertTrue(config.autoDiscoveryEnabled)
        XCTAssertEqual(config.quotaDisplayMode, .remaining)
        XCTAssertNil(config.traeValueDisplayMode)
        XCTAssertTrue(config.showPlanTypeInMenuBar)
        XCTAssertTrue(config.showExpirationTimeInMenuBar)
    }

    func testRelayProviderConfigKeepsStageOneDecodeDefaultsInDomain() throws {
        let config = try JSONDecoder().decode(
            RelayProviderConfig.self,
            from: Data(
                """
                {
                  "baseURL": "https://relay.example.com",
                  "balanceAuth": {
                    "kind": "bearer",
                    "keychainService": "relay-service",
                    "keychainAccount": "relay-account"
                  }
                }
                """.utf8
            )
        )

        XCTAssertNil(config.adapterID)
        XCTAssertEqual(config.baseURL, "https://relay.example.com")
        XCTAssertTrue(config.tokenChannelEnabled)
        XCTAssertFalse(config.balanceChannelEnabled)
        XCTAssertEqual(config.balanceAuth.kind, .bearer)
        XCTAssertNil(config.balanceCredentialMode)
        XCTAssertEqual(config.quotaDisplayMode, .remaining)
        XCTAssertTrue(config.showExpirationTimeInMenuBar)
        XCTAssertNil(config.manualOverrides)
    }

    func testRelayManifestAndOpenRelayCompatibilityValuesAreDomainCodableValues() throws {
        let manifest = try JSONDecoder().decode(
            RelayAdapterManifest.self,
            from: Data(
                """
                {
                  "id": "new-api",
                  "displayName": "New API",
                  "match": {
                    "hostPatterns": ["relay.example.com"],
                    "defaultTokenChannelEnabled": true,
                    "defaultBalanceChannelEnabled": false
                  },
                  "authStrategies": [
                    { "kind": "savedBearer" }
                  ],
                  "balanceRequest": {
                    "method": "GET",
                    "path": "/api/quota"
                  },
                  "extract": {
                    "remaining": "$.remaining"
                  }
                }
                """.utf8
            )
        )
        let openConfig = try JSONDecoder().decode(
            OpenProviderConfig.self,
            from: Data(
                """
                {
                  "tokenUsageEnabled": true,
                  "accountBalance": {
                    "enabled": true,
                    "auth": { "kind": "bearer" },
                    "authHeader": "Authorization",
                    "authScheme": "Bearer",
                    "endpointPath": "/api/balance",
                    "userIDHeader": "New-Api-User",
                    "remainingJSONPath": "$.remaining",
                    "unit": "token"
                  }
                }
                """.utf8
            )
        )

        XCTAssertEqual(manifest.id, "new-api")
        XCTAssertEqual(manifest.displayMode, .balance)
        XCTAssertTrue(manifest.supportsBrowserFallback)
        XCTAssertTrue(manifest.supportsSeparateBalanceAuth)
        XCTAssertEqual(manifest.balanceRequest.method, "GET")
        XCTAssertEqual(manifest.tokenRequest?.usagePath, nil)
        XCTAssertEqual(openConfig.accountBalance?.auth.kind, .bearer)
        XCTAssertEqual(openConfig.accountBalance?.unit, "token")
    }

    private func assertCodableEquatableSendable<T: Codable & Equatable & Sendable>(_ type: T.Type) {}
}
