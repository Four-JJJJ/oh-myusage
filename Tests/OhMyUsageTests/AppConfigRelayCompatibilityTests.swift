import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class AppConfigRelayCompatibilityTests: XCTestCase {
    func testDecodedLegacyOpenAndDragonProvidersNormalizeToRelayDescriptors() throws {
        let json = """
        {
          "language": "zh-Hans",
          "providers": [
            {
              "id": "open-legacy",
              "name": "Legacy Open Relay",
              "family": "thirdParty",
              "type": "open",
              "enabled": true,
              "pollIntervalSec": 0,
              "threshold": {"lowRemaining": 10, "maxConsecutiveFailures": 2, "notifyOnAuthError": true},
              "auth": {"kind": "bearer", "keychainService": "LegacyService", "keychainAccount": "legacy.example/sk-token"},
              "baseURL": "legacy.example/path?ignored=1",
              "openConfig": {
                "tokenUsageEnabled": false,
                "accountBalance": {
                  "enabled": true,
                  "auth": {"kind": "bearer", "keychainAccount": "legacy.example/balance-token"},
                  "authHeader": "X-Legacy-Token",
                  "authScheme": "",
                  "requestMethod": "POST",
                  "requestBodyJSON": "{\\"kind\\":\\"balance\\"}",
                  "endpointPath": "/legacy/balance",
                  "userID": "u-1",
                  "userIDHeader": "X-User",
                  "remainingJSONPath": "payload.remaining",
                  "usedJSONPath": "payload.used",
                  "limitJSONPath": "payload.limit",
                  "successJSONPath": "ok",
                  "unit": "credits"
                }
              }
            },
            {
              "id": "dragoncode",
              "name": "Legacy Dragon",
              "family": "thirdParty",
              "type": "dragon",
              "enabled": true,
              "pollIntervalSec": 0,
              "threshold": {"lowRemaining": 10, "maxConsecutiveFailures": 2, "notifyOnAuthError": true},
              "auth": {"kind": "bearer", "keychainAccount": "dragoncode.codes/auth_token"},
              "baseURL": "https://dragoncode.codes"
            }
          ]
        }
        """

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        let open = try XCTUnwrap(config.providers.first { $0.id == "open-legacy" })
        let dragon = try XCTUnwrap(config.providers.first { $0.id == "dragoncode" })

        XCTAssertEqual(open.type, .relay)
        XCTAssertEqual(open.baseURL, "https://legacy.example")
        XCTAssertNil(open.openConfig)
        XCTAssertEqual(open.relayConfig?.baseURL, "https://legacy.example")
        XCTAssertFalse(open.relayConfig?.tokenChannelEnabled ?? true)
        XCTAssertTrue(open.relayConfig?.balanceChannelEnabled ?? false)
        XCTAssertEqual(open.relayConfig?.balanceAuth.keychainService, "LegacyService")
        XCTAssertEqual(open.relayConfig?.balanceAuth.keychainAccount, "legacy.example/balance-token")
        XCTAssertEqual(open.relayConfig?.manualOverrides?.authHeader, "X-Legacy-Token")
        XCTAssertEqual(open.relayConfig?.manualOverrides?.requestMethod, "POST")
        XCTAssertEqual(open.relayConfig?.manualOverrides?.endpointPath, "/legacy/balance")
        XCTAssertEqual(open.relayConfig?.manualOverrides?.remainingExpression, "payload.remaining")
        XCTAssertEqual(open.relayConfig?.manualOverrides?.unitExpression, "credits")
        XCTAssertEqual(open.pollIntervalSec, 60)

        XCTAssertEqual(dragon.type, .relay)
        XCTAssertEqual(dragon.relayConfig?.adapterID, "dragoncode")
        XCTAssertEqual(dragon.relayConfig?.balanceAuth.keychainAccount, "dragoncode.codes/auth_token")
        XCTAssertNil(dragon.openConfig)
        XCTAssertEqual(dragon.pollIntervalSec, 60)
    }

    func testLegacyDefaultProviderConstructorsAreIsolatedFromCurrentDefaults() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let facadesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+CatalogFacades.swift")
        let legacyDefaultsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+LegacyDefaults.swift")
        let facadesSource = try String(contentsOf: facadesURL, encoding: .utf8)
        let legacyDefaultsSource = try String(contentsOf: legacyDefaultsURL, encoding: .utf8)

        XCTAssertFalse(facadesSource.contains("defaultDragon"))
        XCTAssertFalse(facadesSource.contains("defaultHongmacc"))
        XCTAssertTrue(legacyDefaultsSource.contains("legacyDefaultDragon"))
        XCTAssertTrue(legacyDefaultsSource.contains("legacyDefaultHongmacc"))
        XCTAssertTrue(legacyDefaultsSource.contains("Legacy migration/test fixtures only"))
    }

    func testRelayDescriptorResolverBuildsDefaultConfigThroughInjectedRegistry() {
        let manifest = RelayAdapterManifest(
            id: "compat-template",
            displayName: "Compatibility Relay",
            match: RelayAdapterMatch(
                hostPatterns: ["relay.compat.test"],
                defaultDisplayName: "Compatibility Relay",
                defaultTokenChannelEnabled: false,
                defaultBalanceChannelEnabled: true
            ),
            authStrategies: [.init(kind: .savedBearer)],
            balanceRequest: RelayRequestManifest(path: "/compat/balance"),
            extract: RelayExtractManifest(remaining: "data.remaining", unit: "credits")
        )
        let resolver = RelayProviderDescriptorResolver(
            registry: RelayAdapterRegistry(builtInManifests: [RelayAdapterRegistry.genericManifest, manifest])
        )

        let config = resolver.defaultRelayConfig(
            id: "relay-compat",
            baseURL: "relay.compat.test/path?from=legacy",
            auth: AuthConfig(kind: .bearer, keychainService: "CompatService", keychainAccount: "relay.compat.test/sk-token")
        )

        XCTAssertEqual(config.adapterID, "compat-template")
        XCTAssertEqual(config.baseURL, "https://relay.compat.test")
        XCTAssertFalse(config.tokenChannelEnabled)
        XCTAssertTrue(config.balanceChannelEnabled)
        XCTAssertEqual(config.balanceAuth.keychainService, "CompatService")
        XCTAssertEqual(config.balanceAuth.keychainAccount, "relay.compat.test/system-access-token")
        XCTAssertEqual(config.balanceCredentialMode, RelayCredentialMode.manualPreferred)
        XCTAssertNil(config.manualOverrides)
    }

    func testDecodedLegacySimplifiedRelayConfigFalseNormalizesToCurrentBehavior() throws {
        let json = """
        {
          "language": "zh-Hans",
          "launchAtLoginEnabled": false,
          "simplifiedRelayConfig": false,
          "providers": []
        }
        """

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))

        XCTAssertTrue(config.simplifiedRelayConfig)
    }

    func testInitializerIgnoresLegacySimplifiedRelayConfigFalse() {
        let config = AppConfig(simplifiedRelayConfig: false, providers: [])

        XCTAssertTrue(config.simplifiedRelayConfig)
    }
}
