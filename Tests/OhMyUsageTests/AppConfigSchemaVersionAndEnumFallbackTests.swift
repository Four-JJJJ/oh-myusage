import OhMyUsageDomain
import OhMyUsageProviders
import XCTest
@testable import OhMyUsage

/// P2-5: schemaVersion anchoring and user-editable enum fields falling back
/// to defaults (with diagnostics) instead of invalidating the whole config.
final class AppConfigSchemaVersionAndEnumFallbackTests: XCTestCase {
    // MARK: - schemaVersion

    func testLegacyConfigWithoutSchemaVersionDecodesAsSchemaVersionOne() throws {
        let json = #"{"language":"zh-Hans","providers":[]}"#

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.schemaVersion, 1)
        XCTAssertEqual(decoded.diagnostics, .none)
    }

    func testExplicitOlderSchemaVersionIsPreservedOnDecode() throws {
        let json = #"{"schemaVersion":2,"language":"en","providers":[]}"#

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.schemaVersion, 2)
    }

    func testEncodingAlwaysStampsCurrentSchemaVersion() throws {
        let legacyJSON = #"{"providers":[]}"#
        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.config.schemaVersion, 1)

        let encoded = try JSONEncoder().encode(decoded.config)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AppConfig.currentSchemaVersion)

        let redecoded = try AppConfig.decodeWithDiagnostics(from: encoded)
        XCTAssertEqual(redecoded.config.schemaVersion, AppConfig.currentSchemaVersion)
    }

    func testSavedSnapshotCarriesCurrentSchemaVersion() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(baseDirectoryURL: root)

        try store.save(.default)

        let saved = try Data(contentsOf: appSupportDirectory(in: root).appendingPathComponent("config.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AppConfig.currentSchemaVersion)
    }

    // MARK: - Top-level enum fallbacks

    func testUnknownLanguageFallsBackToDefaultWithDiagnostic() throws {
        let json = #"{"language":"zh-hant","providers":[]}"#

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.language, .zhHans)
        XCTAssertEqual(decoded.diagnostics.unknownEnumFields, ["language=zh-hant"])
        XCTAssertTrue(decoded.diagnostics.hadUnknownEnumFallback)
        XCTAssertFalse(decoded.diagnostics.hadLossyProviderDecoding)
        XCTAssertEqual(decoded.diagnostics.droppedProviderEntryCount, 0)
    }

    func testUnknownResourceModeFallsBackWithDiagnostic() throws {
        let json = #"{"resourceMode":"background20m","providers":[]}"#

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.resourceMode, .background5Minutes)
        XCTAssertEqual(decoded.diagnostics.unknownEnumFields, ["resourceMode=background20m"])
    }

    func testLegacyResourceModeAliasesStillDecodeSilently() throws {
        let expectations = [
            ("responsive", ResourceMode.background3Minutes),
            ("balanced", ResourceMode.background5Minutes),
            ("lowPower", ResourceMode.background15Minutes),
            ("background10m", ResourceMode.background10Minutes)
        ]
        for (rawValue, expected) in expectations {
            let json = #"{"resourceMode":"\#(rawValue)","providers":[]}"#
            let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))
            XCTAssertEqual(decoded.config.resourceMode, expected, rawValue)
            XCTAssertTrue(decoded.diagnostics.unknownEnumFields.isEmpty, rawValue)
        }
    }

    func testUnknownStatusBarAppearanceAndDisplayModesFallBackWithDiagnostics() throws {
        let json = #"{"statusBarAppearanceMode":"neon","statusBarDisplayStyle":"hologram","providers":[]}"#

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.statusBarAppearanceMode, .followWallpaper)
        XCTAssertEqual(decoded.config.statusBarDisplayStyle, .iconPercent)
        XCTAssertEqual(
            decoded.diagnostics.unknownEnumFields,
            ["statusBarAppearanceMode=neon", "statusBarDisplayStyle=hologram"]
        )
    }

    func testKnownTopLevelEnumValuesDecodeWithoutDiagnostics() throws {
        let json = #"""
        {"language":"en","resourceMode":"background10m","statusBarAppearanceMode":"dark","statusBarDisplayStyle":"barNamePercent","providers":[]}
        """#

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.language, .en)
        XCTAssertEqual(decoded.config.resourceMode, .background10Minutes)
        XCTAssertEqual(decoded.config.statusBarAppearanceMode, .dark)
        XCTAssertEqual(decoded.config.statusBarDisplayStyle, .barNamePercent)
        XCTAssertTrue(decoded.diagnostics.unknownEnumFields.isEmpty)
    }

    func testMalformedEnumValueFallsBackToDefault() throws {
        let json = #"{"language":5,"providers":[]}"#

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.language, .zhHans)
        XCTAssertEqual(decoded.diagnostics.unknownEnumFields, ["language=<malformed value>"])
    }

    func testUnknownEnumConfigSelfHealsOnReEncode() throws {
        let json = #"{"language":"klingon","statusBarDisplayStyle":"tinyBar","providers":[]}"#
        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))
        XCTAssertTrue(decoded.diagnostics.hadUnknownEnumFallback)

        let encoded = try JSONEncoder().encode(decoded.config)
        let redecoded = try AppConfig.decodeWithDiagnostics(from: encoded)

        XCTAssertEqual(redecoded.config.language, .zhHans)
        XCTAssertEqual(redecoded.config.statusBarDisplayStyle, .iconPercent)
        XCTAssertTrue(redecoded.diagnostics.unknownEnumFields.isEmpty)
    }

    // MARK: - Provider entry enum fallbacks

    func testUnknownOfficialSourceModeKeepsProviderEntryWithDefault() throws {
        let json = configJSON(withProviderJSON: #"""
        {
          "id":"codex-official",
          "name":"Official Codex",
          "family":"official",
          "type":"codex",
          "enabled":true,
          "pollIntervalSec":120,
          "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
          "auth":{"kind":"localCodex"},
          "baseURL":"https://chatgpt.com",
          "officialConfig":{
            "sourceMode":"cliOAuth",
            "webMode":"disabled",
            "quotaDisplayMode":"remaining"
          }
        }
        """#)

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.providers.count, 1)
        XCTAssertEqual(decoded.config.providers.first?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(decoded.diagnostics.unknownEnumFields, ["providers[0].officialConfig.sourceMode=cliOAuth"])
        XCTAssertFalse(decoded.diagnostics.hadLossyProviderDecoding)
    }

    func testUnknownOfficialWebModeAndQuotaDisplayModeFallBack() throws {
        let json = configJSON(withProviderJSON: #"""
        {
          "id":"codex-official",
          "name":"Official Codex",
          "family":"official",
          "type":"codex",
          "enabled":true,
          "pollIntervalSec":120,
          "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
          "auth":{"kind":"localCodex"},
          "baseURL":"https://chatgpt.com",
          "officialConfig":{
            "sourceMode":"auto",
            "webMode":"autoMagic",
            "quotaDisplayMode":"pieChart"
          }
        }
        """#)

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.providers.count, 1)
        XCTAssertEqual(decoded.config.providers.first?.officialConfig?.webMode, .disabled)
        XCTAssertEqual(decoded.config.providers.first?.officialConfig?.quotaDisplayMode, .remaining)
        XCTAssertEqual(
            decoded.diagnostics.unknownEnumFields,
            [
                "providers[0].officialConfig.webMode=autoMagic",
                "providers[0].officialConfig.quotaDisplayMode=pieChart"
            ]
        )
    }

    func testUnknownTraeValueDisplayModeResolvesToNormalizedDefault() throws {
        let json = configJSON(withProviderJSON: #"""
        {
          "id":"trae-official",
          "name":"Official Trae",
          "family":"official",
          "type":"trae",
          "enabled":true,
          "pollIntervalSec":60,
          "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
          "auth":{"kind":"bearer"},
          "baseURL":"https://api-sg-central.trae.ai",
          "officialConfig":{
            "sourceMode":"auto",
            "webMode":"disabled",
            "quotaDisplayMode":"remaining",
            "traeValueDisplayMode":"volume"
          }
        }
        """#)

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.providers.count, 1)
        XCTAssertEqual(decoded.config.providers.first?.officialConfig?.traeValueDisplayMode, .percent)
        XCTAssertEqual(
            decoded.diagnostics.unknownEnumFields,
            ["providers[0].officialConfig.traeValueDisplayMode=volume"]
        )
    }

    func testUnknownRelayQuotaDisplayModeAndBalanceCredentialModeKeepRelayEntry() throws {
        let json = configJSON(withProviderJSON: #"""
        {
          "id":"open-future-relay",
          "name":"Future Relay",
          "family":"thirdParty",
          "type":"relay",
          "enabled":true,
          "pollIntervalSec":60,
          "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
          "auth":{"kind":"bearer"},
          "baseURL":"https://future-relay.test",
          "relayConfig":{
            "baseURL":"https://future-relay.test",
            "balanceAuth":{"kind":"bearer"},
            "quotaDisplayMode":"donut",
            "balanceCredentialMode":"hybrid"
          }
        }
        """#)

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.providers.count, 1)
        XCTAssertEqual(decoded.config.providers.first?.relayConfig?.quotaDisplayMode, .remaining)
        // Removing the unknown optional value lets normalization apply its own
        // default (.manualPreferred) instead of failing the entry.
        XCTAssertEqual(decoded.config.providers.first?.relayConfig?.balanceCredentialMode, .manualPreferred)
        XCTAssertEqual(
            decoded.diagnostics.unknownEnumFields,
            [
                "providers[0].relayConfig.quotaDisplayMode=donut",
                "providers[0].relayConfig.balanceCredentialMode=hybrid"
            ]
        )
    }

    func testUnknownKimiAuthModeFallsBackToAuto() throws {
        // Third-party Kimi entries keep their kimiConfig through normalization;
        // official Kimi drops it in favor of officialConfig.
        let json = configJSON(withProviderJSON: #"""
        {
          "id":"kimi-custom",
          "name":"Custom Kimi",
          "family":"thirdParty",
          "type":"kimi",
          "enabled":true,
          "pollIntervalSec":60,
          "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
          "auth":{"kind":"bearer"},
          "kimiConfig":{
            "authMode":"sso",
            "manualTokenAccount":"kimi.com/kimi-auth-manual",
            "autoCookieEnabled":true,
            "browserOrder":["chrome"]
          }
        }
        """#)

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.providers.count, 1)
        XCTAssertEqual(decoded.config.providers.first?.kimiConfig?.authMode, .auto)
        XCTAssertEqual(decoded.diagnostics.unknownEnumFields, ["providers[0].kimiConfig.authMode=sso"])
    }

    func testUnknownKimiBrowserKindsAreFilteredFromBrowserOrder() throws {
        let json = configJSON(withProviderJSON: #"""
        {
          "id":"kimi-custom",
          "name":"Custom Kimi",
          "family":"thirdParty",
          "type":"kimi",
          "enabled":true,
          "pollIntervalSec":60,
          "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
          "auth":{"kind":"bearer"},
          "kimiConfig":{
            "authMode":"auto",
            "manualTokenAccount":"kimi.com/kimi-auth-manual",
            "autoCookieEnabled":true,
            "browserOrder":["chrome","nebula","arc"]
          }
        }
        """#)

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertEqual(decoded.config.providers.count, 1)
        XCTAssertEqual(decoded.config.providers.first?.kimiConfig?.browserOrder, [.chrome, .arc])
        XCTAssertEqual(decoded.diagnostics.unknownEnumFields, ["providers[0].kimiConfig.browserOrder=nebula"])
    }

    func testUnknownProviderTypeStillDropsEntryViaLossyPath() throws {
        let json = configJSON(withProviderJSON: #"""
        {
          "id":"future-provider",
          "name":"Future Provider",
          "family":"official",
          "type":"someNewProviderType",
          "enabled":true,
          "pollIntervalSec":60,
          "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
          "auth":{"kind":"bearer"}
        }
        """#)

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertTrue(decoded.config.providers.isEmpty)
        XCTAssertTrue(decoded.diagnostics.hadLossyProviderDecoding)
        XCTAssertEqual(decoded.diagnostics.droppedProviderEntryCount, 1)
        XCTAssertTrue(decoded.diagnostics.unknownEnumFields.isEmpty)
    }

    func testUnknownAuthKindStillDropsEntryViaLossyPath() throws {
        let json = configJSON(withProviderJSON: #"""
        {
          "id":"open-auth-relay",
          "name":"Auth Relay",
          "family":"thirdParty",
          "type":"relay",
          "enabled":true,
          "pollIntervalSec":60,
          "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
          "auth":{"kind":"oauthMagic"},
          "baseURL":"https://future-relay.test",
          "relayConfig":{
            "baseURL":"https://future-relay.test",
            "balanceAuth":{"kind":"bearer"}
          }
        }
        """#)

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertTrue(decoded.config.providers.isEmpty)
        XCTAssertTrue(decoded.diagnostics.hadLossyProviderDecoding)
        XCTAssertEqual(decoded.diagnostics.droppedProviderEntryCount, 1)
        XCTAssertTrue(decoded.diagnostics.unknownEnumFields.isEmpty)
    }

    func testUnknownEnumPlusStructuralDamageStillDropsEntryWithoutDiagnostics() throws {
        // Unknown enum value AND a structurally broken field in the same entry:
        // the enum fallback must not rescue an entry that is broken for other
        // reasons, and no fallback diagnostic is reported for a dropped entry.
        let json = configJSON(withProviderJSON: #"""
        {
          "id":"codex-official",
          "name":"Official Codex",
          "family":"official",
          "type":"codex",
          "enabled":true,
          "pollIntervalSec":120,
          "threshold":{"lowRemaining":"twenty","maxConsecutiveFailures":2,"notifyOnAuthError":true},
          "auth":{"kind":"localCodex"},
          "baseURL":"https://chatgpt.com",
          "officialConfig":{
            "sourceMode":"cliOAuth",
            "webMode":"disabled"
          }
        }
        """#)

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertTrue(decoded.config.providers.isEmpty)
        XCTAssertEqual(decoded.diagnostics.droppedProviderEntryCount, 1)
        XCTAssertTrue(decoded.diagnostics.unknownEnumFields.isEmpty)
    }

    // MARK: - Structural damage stays invalid

    func testTruncatedJSONStillFailsToDecode() throws {
        let json = #"{"language":"zh-Hans","providers":[{""#

        XCTAssertThrowsError(try AppConfig.decodeWithDiagnostics(from: Data(json.utf8)))
    }

    func testTypeMismatchedNonEnumFieldStillFailsToDecode() throws {
        let json = #"{"launchAtLoginEnabled":"yes","providers":[]}"#

        XCTAssertThrowsError(try AppConfig.decodeWithDiagnostics(from: Data(json.utf8)))
    }

    func testTypeMismatchedSchemaVersionStillFailsToDecode() throws {
        let json = #"{"schemaVersion":"three","providers":[]}"#

        XCTAssertThrowsError(try AppConfig.decodeWithDiagnostics(from: Data(json.utf8)))
    }

    // MARK: - ConfigStore integration

    func testConfigStoreLoadsConfigWithUnknownEnumAsUsable() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = appSupportDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primaryJSON = #"""
        {
          "language":"zh-Hans",
          "statusBarDisplayStyle":"hologram",
          "providers":[
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":120,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            }
          ]
        }
        """#
        try Data(primaryJSON.utf8).write(to: directory.appendingPathComponent("config.json"), options: .atomic)

        let store = ConfigStore(baseDirectoryURL: root)
        let loaded = try store.load()

        XCTAssertEqual(loaded.statusBarDisplayStyle, .iconPercent)
        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertFalse(store.lastLoadWasLossy)
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptArchiveURL(in: directory).path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.preserved-fallback-candidate.json").path)
        )
    }

    func testConfigStoreStillArchivesTruncatedConfigAndFallsBackToDefault() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = appSupportDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let truncated = Data(#"{"language":"zh-Hans","providers":[{""#.utf8)
        try truncated.write(to: directory.appendingPathComponent("config.json"), options: .atomic)

        let loaded = try ConfigStore(baseDirectoryURL: root).load()

        XCTAssertEqual(loaded, AppConfig.default)
        let archived = try FileManager.default.contentsOfDirectory(at: corruptArchiveURL(in: directory), includingPropertiesForKeys: nil)
            .map { try Data(contentsOf: $0) }
        XCTAssertEqual(archived, [truncated])
    }

    // MARK: - Helpers

    private func configJSON(withProviderJSON providerJSON: String) -> String {
        #"""
        {
          "language":"zh-Hans",
          "providers":[
        \#(providerJSON)
          ]
        }
        """#
    }

    private func makeTempDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func appSupportDirectory(in root: URL) -> URL {
        root.appendingPathComponent("OhMyUsage", isDirectory: true)
    }

    private func corruptArchiveURL(in directory: URL) -> URL {
        directory.appendingPathComponent("config.corrupt-archive", isDirectory: true)
    }
}
