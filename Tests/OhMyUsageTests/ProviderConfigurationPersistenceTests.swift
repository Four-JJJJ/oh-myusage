import Foundation
import OhMyUsageDomain
@testable import OhMyUsage
import XCTest

final class ProviderConfigurationPersistenceTests: XCTestCase {
    func testDecodesLegacyProviderDescriptorJSONIntoProviderConfiguration() throws {
        let data = Data(Self.legacyRelayProviderDescriptorJSON.utf8)

        let descriptor = try JSONDecoder().decode(ProviderDescriptor.self, from: data)
        let configuration = try JSONDecoder().decode(ProviderConfiguration.self, from: data)

        XCTAssertEqual(configuration.id, descriptor.id)
        XCTAssertEqual(configuration.name, descriptor.name)
        XCTAssertEqual(configuration.family, descriptor.family)
        XCTAssertEqual(configuration.type, descriptor.type)
        XCTAssertEqual(configuration.settings.enabled, descriptor.enabled)
        XCTAssertEqual(configuration.settings.pollIntervalSec, descriptor.pollIntervalSec)
        XCTAssertEqual(configuration.settings.threshold, descriptor.threshold)
        XCTAssertEqual(configuration.settings.auth, descriptor.auth)
        XCTAssertEqual(configuration.settings.showInMenuBar, descriptor.showInMenuBar)
        XCTAssertEqual(configuration.settings.baseURL, descriptor.baseURL)
        XCTAssertEqual(configuration.settings.relayConfig, descriptor.relayConfig)
        XCTAssertEqual(configuration.settings.openConfig, descriptor.openConfig)
        XCTAssertNil(configuration.settings.officialConfig)
    }

    func testReencodingProviderConfigurationKeepsCorePersistentFields() throws {
        let data = Data(Self.legacyRelayProviderDescriptorJSON.utf8)
        let configuration = try JSONDecoder().decode(ProviderConfiguration.self, from: data)
        let encodedData = try JSONEncoder().encode(configuration)
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )
        let auth = try XCTUnwrap(encoded["auth"] as? [String: Any])
        let relayConfig = try XCTUnwrap(encoded["relayConfig"] as? [String: Any])
        let balanceAuth = try XCTUnwrap(relayConfig["balanceAuth"] as? [String: Any])
        let manualOverrides = try XCTUnwrap(relayConfig["manualOverrides"] as? [String: Any])
        let staticHeaders = try XCTUnwrap(manualOverrides["staticHeaders"] as? [String: Any])

        XCTAssertEqual(encoded["id"] as? String, "relay-example")
        XCTAssertEqual(encoded["name"] as? String, "Relay Example")
        XCTAssertEqual(encoded["family"] as? String, "thirdParty")
        XCTAssertEqual(encoded["type"] as? String, "relay")
        XCTAssertEqual(encoded["enabled"] as? Bool, true)
        XCTAssertEqual(encoded["pollIntervalSec"] as? Int, 120)
        XCTAssertEqual(encoded["showInMenuBar"] as? Bool, false)
        XCTAssertEqual(encoded["baseURL"] as? String, "https://relay.example")
        XCTAssertEqual(auth["keychainAccount"] as? String, "relay.example/sk-token")
        XCTAssertEqual(relayConfig["adapterID"] as? String, "new-api")
        XCTAssertEqual(relayConfig["quotaDisplayMode"] as? String, "used")
        XCTAssertEqual(balanceAuth["keychainAccount"] as? String, "relay.example/system-token")
        XCTAssertEqual(manualOverrides["remainingExpression"] as? String, "$.data.quota")
        XCTAssertEqual(manualOverrides["usedExpression"] as? String, "$.data.used")
        XCTAssertEqual(manualOverrides["limitExpression"] as? String, "$.data.limit")
        XCTAssertEqual(manualOverrides["successExpression"] as? String, "$.success")
        XCTAssertEqual(staticHeaders["X-Workspace"] as? String, "workspace-1")
    }

    func testDecodesOfficialProviderDescriptorStatusRelevantFields() throws {
        let configuration = try JSONDecoder().decode(
            ProviderConfiguration.self,
            from: Data(Self.officialProviderDescriptorJSON.utf8)
        )

        XCTAssertEqual(configuration.id, "claude-official")
        XCTAssertEqual(configuration.family, .official)
        XCTAssertEqual(configuration.type, .claude)
        XCTAssertEqual(configuration.settings.enabled, true)
        XCTAssertEqual(configuration.settings.showInMenuBar, true)
        XCTAssertEqual(configuration.settings.auth.keychainAccount, "official/claude/oauth-token")
        XCTAssertEqual(configuration.settings.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(configuration.settings.officialConfig?.webMode, .autoImport)
        XCTAssertEqual(configuration.settings.officialConfig?.manualCookieAccount, "official/claude/session-cookie")
        XCTAssertEqual(configuration.settings.officialConfig?.oauthAccountImportEnabled, true)
        XCTAssertEqual(configuration.settings.officialConfig?.quotaDisplayMode, .used)
        XCTAssertEqual(configuration.settings.officialConfig?.showPlanTypeInMenuBar, false)
        XCTAssertEqual(configuration.settings.officialConfig?.showExpirationTimeInMenuBar, true)
    }

    func testKimiLegacyConfigIsNotCoveredByDomainProviderConfigurationYet() throws {
        let configuration = try JSONDecoder().decode(
            ProviderConfiguration.self,
            from: Data(Self.kimiLegacyProviderDescriptorJSON.utf8)
        )
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any]
        )

        XCTAssertEqual(configuration.id, "kimi-official")
        XCTAssertNil(encoded["kimiConfig"], "Kimi legacy fields stay out of the Domain configuration boundary in this stage.")
    }

    private static let legacyRelayProviderDescriptorJSON = """
    {
      "id": "relay-example",
      "name": "Relay Example",
      "family": "thirdParty",
      "type": "relay",
      "enabled": true,
      "pollIntervalSec": 120,
      "threshold": {
        "lowRemaining": 12.5,
        "maxConsecutiveFailures": 4,
        "notifyOnAuthError": true
      },
      "auth": {
        "kind": "bearer",
        "keychainService": "OhMyUsage",
        "keychainAccount": "relay.example/sk-token"
      },
      "showInMenuBar": false,
      "baseURL": "https://relay.example",
      "relayConfig": {
        "adapterID": "new-api",
        "baseURL": "https://relay.example",
        "tokenChannelEnabled": true,
        "balanceChannelEnabled": true,
        "balanceAuth": {
          "kind": "bearer",
          "keychainService": "OhMyUsage",
          "keychainAccount": "relay.example/system-token"
        },
        "balanceCredentialMode": "manualPreferred",
        "quotaDisplayMode": "used",
        "manualOverrides": {
          "authHeader": "Authorization",
          "authScheme": "Bearer",
          "userID": "42",
          "userIDHeader": "New-Api-User",
          "requestMethod": "POST",
          "requestBodyJSON": "{\\"scope\\":\\"quota\\"}",
          "endpointPath": "/api/quota",
          "remainingExpression": "$.data.quota",
          "usedExpression": "$.data.used",
          "limitExpression": "$.data.limit",
          "successExpression": "$.success",
          "unitExpression": "tokens",
          "accountLabelExpression": "$.data.account",
          "staticHeaders": {
            "X-Workspace": "workspace-1"
          }
        }
      },
      "openConfig": {
        "tokenUsageEnabled": true,
        "accountBalance": {
          "enabled": true,
          "auth": {
            "kind": "bearer",
            "keychainService": "OhMyUsage",
            "keychainAccount": "relay.example/open-balance"
          },
          "authHeader": "Authorization",
          "authScheme": "Bearer",
          "endpointPath": "/open/balance",
          "remainingJSONPath": "$.remaining",
          "usedJSONPath": "$.used",
          "limitJSONPath": "$.limit",
          "successJSONPath": "$.success",
          "unit": "token"
        }
      }
    }
    """

    private static let officialProviderDescriptorJSON = """
    {
      "id": "claude-official",
      "name": "Official Claude",
      "family": "official",
      "type": "claude",
      "enabled": true,
      "pollIntervalSec": 180,
      "threshold": {
        "lowRemaining": 20,
        "maxConsecutiveFailures": 2,
        "notifyOnAuthError": true
      },
      "auth": {
        "kind": "bearer",
        "keychainService": "OhMyUsage",
        "keychainAccount": "official/claude/oauth-token"
      },
      "showInMenuBar": true,
      "baseURL": "https://claude.ai",
      "officialConfig": {
        "sourceMode": "auto",
        "webMode": "autoImport",
        "manualCookieAccount": "official/claude/session-cookie",
        "oauthAccountImportEnabled": true,
        "autoDiscoveryEnabled": true,
        "quotaDisplayMode": "used",
        "showPlanTypeInMenuBar": false
      }
    }
    """

    private static let kimiLegacyProviderDescriptorJSON = """
    {
      "id": "kimi-official",
      "name": "Kimi",
      "family": "official",
      "type": "kimi",
      "enabled": true,
      "pollIntervalSec": 180,
      "threshold": {
        "lowRemaining": 20,
        "maxConsecutiveFailures": 2,
        "notifyOnAuthError": true
      },
      "auth": {
        "kind": "bearer",
        "keychainService": "OhMyUsage",
        "keychainAccount": "kimi.com/kimi-auth-manual"
      },
      "kimiConfig": {
        "usesLocalBrowserSession": true
      }
    }
    """
}
