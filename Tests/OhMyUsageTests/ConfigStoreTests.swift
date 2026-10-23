import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class ConfigStoreTests: XCTestCase {
    func testSaveWritesPrimaryBackupAndRecoveryAndLoadReturnsPersistedConfig() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        var config = AppConfig.default
        config.language = .en
        config.claudeStatusBarDisplaySlotID = .b
        if let codexIndex = config.providers.firstIndex(where: { $0.id == "codex-official" }) {
            config.providers[codexIndex].enabled = true
        }

        try store.save(config)
        let directory = root.appendingPathComponent("OhMyUsage", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.backup.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.recovery.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.last-known-good.json").path))

        let loaded = try store.load()
        XCTAssertEqual(loaded.language, .en)
        XCTAssertEqual(loaded.claudeStatusBarDisplaySlotID, .b)
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
    }

    func testLoadCreatesDefaultConfigWhenNoHistoryExists() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        let loaded = try store.load()
        let directory = appSupportDirectory(in: root)

        XCTAssertEqual(loaded, AppConfig.default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.backup.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.recovery.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.last-known-good.json").path))
    }

    func testLoadGoldenPrimaryConfigSyncsMissingShadowSnapshots() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let directory = appSupportDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let primaryURL = directory.appendingPathComponent("config.json")
        try fixtureData("golden-primary-config.json").write(to: primaryURL, options: .atomic)

        let loaded = try store.load()

        XCTAssertEqual(loaded.language, .en)
        XCTAssertEqual(loaded.resourceMode, .background10Minutes)
        XCTAssertEqual(loaded.claudeStatusBarDisplaySlotID, .b)
        XCTAssertEqual(loaded.statusBarProviderID, "open-golden-primary-relay")
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", "open-golden-primary-relay"])
        XCTAssertEqual(loaded.statusBarAppearanceMode, .dark)
        XCTAssertEqual(loaded.statusBarDisplayStyle, .barNamePercent)
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "claude-official" && $0.enabled }))
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "open-golden-primary-relay" && $0.enabled }))

        for filename in ["config.backup.json", "config.recovery.json", "config.last-known-good.json"] {
            let url = directory.appendingPathComponent(filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(filename) should be created from primary")
            let decoded = try AppConfig.decodeWithDiagnostics(from: Data(contentsOf: url))
            XCTAssertFalse(decoded.diagnostics.hadLossyProviderDecoding)
            XCTAssertEqual(decoded.config.statusBarProviderID, "open-golden-primary-relay")
            XCTAssertTrue(decoded.config.providers.contains(where: { $0.id == "open-golden-primary-relay" && $0.enabled }))
        }
    }

    func testLoadRecoversEnabledOfficialProvidersFromPersistedProfilesWhenConfigMissing() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        let codexProfilesURL = appSupportDirectory(in: root).appendingPathComponent("codex_profiles.json")
        let codexProfileStore = CodexAccountProfileStore(fileURL: codexProfilesURL)
        _ = try codexProfileStore.saveProfile(
            slotID: .a,
            displayName: "Codex A",
            note: nil,
            authJSON: #"{"tokens":{"access_token":"codex-test-token"}}"#,
            currentFingerprint: nil
        )
        // Profile persistence is asynchronous (store IO queue); fence it so the
        // recovery policy below observes the persisted file on disk.
        codexProfileStore.flushPendingDiskWrites()

        let claudeProfilesURL = appSupportDirectory(in: root).appendingPathComponent("claude_profiles.json")
        let claudeProfileStore = ClaudeAccountProfileStore(fileURL: claudeProfilesURL)
        _ = try claudeProfileStore.saveProfile(
            slotID: .a,
            displayName: "Claude A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: #"{"accessToken":"claude-test-token","email":"test@example.com"}"#,
            currentFingerprint: nil
        )
        claudeProfileStore.flushPendingDiskWrites()

        let loaded = try store.load()
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "claude-official" && $0.enabled }))
        XCTAssertEqual(loaded.statusBarProviderID, "codex-official")

        let configURL = appSupportDirectory(in: root).appendingPathComponent("config.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testLoadRecoversFromBackupWhenPrimaryConfigCorrupted() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        var config = AppConfig.default
        config.language = .en
        try store.save(config)

        let directory = root.appendingPathComponent("OhMyUsage", isDirectory: true)
        let primaryURL = directory.appendingPathComponent("config.json")
        try Data("not-json".utf8).write(to: primaryURL, options: .atomic)

        let loaded = try store.load()
        XCTAssertEqual(loaded.language, .en)

        let restoredData = try Data(contentsOf: primaryURL)
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: restoredData))
    }

    func testLoadRecoversFromRecoverySnapshotWhenPrimaryAndBackupCorrupted() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        var config = AppConfig.default
        config.statusBarMultiUsageEnabled = true
        config.statusBarProviderID = "codex-official"
        config.statusBarMultiProviderIDs = ["codex-official", "claude-official"]
        config.claudeStatusBarDisplaySlotID = .b
        config.statusBarAppearanceMode = .dark
        config.statusBarDisplayStyle = .barNamePercent
        if let codexIndex = config.providers.firstIndex(where: { $0.id == "codex-official" }) {
            config.providers[codexIndex].enabled = true
        }
        if let claudeIndex = config.providers.firstIndex(where: { $0.id == "claude-official" }) {
            config.providers[claudeIndex].enabled = true
        }
        try store.save(config)

        let directory = root.appendingPathComponent("OhMyUsage", isDirectory: true)
        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        let lastKnownGoodURL = directory.appendingPathComponent("config.last-known-good.json")
        try Data("not-json".utf8).write(to: primaryURL, options: .atomic)
        try Data("still-not-json".utf8).write(to: backupURL, options: .atomic)

        let loaded = try store.load()
        XCTAssertEqual(loaded.statusBarProviderID, "codex-official")
        XCTAssertEqual(loaded.claudeStatusBarDisplaySlotID, .b)
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", "claude-official"])
        XCTAssertEqual(loaded.statusBarAppearanceMode, .dark)
        XCTAssertEqual(loaded.statusBarDisplayStyle, .barNamePercent)

        let restoredPrimary = try Data(contentsOf: primaryURL)
        let restoredBackup = try Data(contentsOf: backupURL)
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: restoredPrimary))
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: restoredBackup))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lastKnownGoodURL.path))
    }

    func testLoadRecoversFromLastKnownGoodWhenPrimaryAndShadowsMissing() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let config = makeConfigWithRelayAndStatusBarState()
        try store.save(config)

        let directory = appSupportDirectory(in: root)
        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        let recoveryURL = directory.appendingPathComponent("config.recovery.json")
        let lastKnownGoodURL = directory.appendingPathComponent("config.last-known-good.json")

        try FileManager.default.removeItem(at: primaryURL)
        try FileManager.default.removeItem(at: backupURL)
        try FileManager.default.removeItem(at: recoveryURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded.statusBarProviderID, "open-custom-relay-persisted")
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", "open-custom-relay-persisted"])
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lastKnownGoodURL.path))
    }

    func testLoadPrefersLossyCurrentConfigBeforeRestoringLastKnownGoodSnapshot() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let config = makeConfigWithRelayAndStatusBarState()
        try store.save(config)

        let directory = appSupportDirectory(in: root)
        let lossyData = Data(makeLossyConfigJSON().utf8)
        try lossyData.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.backup.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.recovery.json"), options: .atomic)

        let loaded = try store.load()
        let restoredData = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        let restored = try AppConfig.decodeWithDiagnostics(from: restoredData)
        let preservedURL = directory.appendingPathComponent("config.preserved-fallback-candidate.json")

        XCTAssertTrue(restored.diagnostics.hadLossyProviderDecoding)
        XCTAssertEqual(loaded.statusBarProviderID, "codex-official")
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official"])
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertFalse(loaded.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), lossyData)
    }

    func testBootstrapSaveDoesNotOverwriteLastKnownGoodSnapshot() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let fullConfig = makeConfigWithRelayAndStatusBarState()
        try store.save(fullConfig)

        var minimal = AppConfig.default
        if let codexIndex = minimal.providers.firstIndex(where: { $0.id == "codex-official" }) {
            minimal.providers[codexIndex].enabled = true
        }
        minimal.statusBarProviderID = "codex-official"
        minimal.statusBarMultiUsageEnabled = false
        minimal.statusBarMultiProviderIDs = ["codex-official"]
        minimal.launchAtLoginEnabled = true

        try store.saveDuringBootstrap(minimal)

        let directory = appSupportDirectory(in: root)
        let primary = try AppConfig.decodeWithDiagnostics(
            from: Data(contentsOf: directory.appendingPathComponent("config.json"))
        ).config
        let lastKnownGood = try AppConfig.decodeWithDiagnostics(
            from: Data(contentsOf: directory.appendingPathComponent("config.last-known-good.json"))
        ).config

        XCTAssertEqual(primary.statusBarProviderID, "codex-official")
        XCTAssertFalse(primary.statusBarMultiUsageEnabled)
        XCTAssertEqual(primary.statusBarMultiProviderIDs, ["codex-official"])
        XCTAssertEqual(lastKnownGood.statusBarProviderID, "open-custom-relay-persisted")
        XCTAssertTrue(lastKnownGood.statusBarMultiUsageEnabled)
        XCTAssertEqual(lastKnownGood.statusBarMultiProviderIDs, ["codex-official", "open-custom-relay-persisted"])
        XCTAssertTrue(lastKnownGood.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
    }

    func testLoadPersistsPreservedFallbackCandidateWhenLossyConfigLoadsInPlace() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let directory = appSupportDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let lossyData = Data(makeLossyConfigJSON().utf8)
        try lossyData.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.backup.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.recovery.json"), options: .atomic)

        let codexSlotStore = CodexAccountSlotStore(
            staleInterval: .greatestFiniteMagnitude,
            fileURL: directory.appendingPathComponent("codex_slots.json")
        )
        _ = codexSlotStore.upsertActive(
            snapshot: makeSnapshot(
                source: "codex-official",
                accountLabel: "codex@example.com",
                rawMeta: [
                    "codex.accountKey": "tenant:account:codex|principal:email:codex@example.com",
                    "codex.slotID": "A"
                ]
            ),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        // Slot persistence is asynchronous (store IO queue); fence it so the
        // recovery policy below observes the persisted file on disk.
        codexSlotStore.flushPendingDiskWrites()

        let loaded = try store.load()
        let preservedURL = directory.appendingPathComponent("config.preserved-fallback-candidate.json")

        XCTAssertEqual(loaded.statusBarProviderID, "codex-official")
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), lossyData)
    }

    func testSecondLoadRestoresGoldenLastKnownGoodAfterLossyCandidateIsPreserved() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let directory = appSupportDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let lossyData = try fixtureData("lossy-current-config.json")
        try lossyData.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.backup.json"), options: .atomic)
        try lossyData.write(to: directory.appendingPathComponent("config.recovery.json"), options: .atomic)
        try fixtureData("golden-primary-config.json")
            .write(to: directory.appendingPathComponent("config.last-known-good.json"), options: .atomic)

        let firstLoad = try store.load()
        let preservedURL = directory.appendingPathComponent("config.preserved-fallback-candidate.json")

        XCTAssertTrue(store.lastLoadWasLossy)
        XCTAssertEqual(firstLoad.statusBarProviderID, "codex-official")
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), lossyData)

        let secondLoad = try store.load()
        let rewrittenPrimary = try AppConfig.decodeWithDiagnostics(
            from: Data(contentsOf: directory.appendingPathComponent("config.json"))
        )

        XCTAssertFalse(store.lastLoadWasLossy)
        XCTAssertEqual(secondLoad.statusBarProviderID, "open-golden-primary-relay")
        XCTAssertTrue(secondLoad.statusBarMultiUsageEnabled)
        XCTAssertEqual(secondLoad.statusBarMultiProviderIDs, ["codex-official", "open-golden-primary-relay"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: preservedURL.path))
        XCTAssertFalse(rewrittenPrimary.diagnostics.hadLossyProviderDecoding)
        XCTAssertEqual(rewrittenPrimary.config.statusBarProviderID, "open-golden-primary-relay")
    }

    func testLoadPrefersPreservedFallbackCandidateBeforeDerivedPrimaryConfig() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let fullConfig = makeConfigWithRelayAndStatusBarState()
        let directory = appSupportDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var minimal = AppConfig.default
        if let codexIndex = minimal.providers.firstIndex(where: { $0.id == "codex-official" }) {
            minimal.providers[codexIndex].enabled = true
        }
        minimal.statusBarProviderID = "codex-official"
        minimal.statusBarMultiProviderIDs = ["codex-official"]
        let minimalData = try JSONEncoder.prettySorted.encode(minimal)
        try minimalData.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
        try minimalData.write(to: directory.appendingPathComponent("config.backup.json"), options: .atomic)
        try minimalData.write(to: directory.appendingPathComponent("config.recovery.json"), options: .atomic)

        let fullData = try JSONEncoder.prettySorted.encode(fullConfig)
        try fullData.write(to: directory.appendingPathComponent("config.preserved-fallback-candidate.json"), options: .atomic)

        let loaded = try store.load()
        let rewrittenPrimary = try AppConfig.decodeWithDiagnostics(
            from: Data(contentsOf: directory.appendingPathComponent("config.json"))
        ).config

        XCTAssertEqual(loaded.statusBarProviderID, "open-custom-relay-persisted")
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", "open-custom-relay-persisted"])
        XCTAssertTrue(rewrittenPrimary.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.preserved-fallback-candidate.json").path))
    }

    func testLoadRecoversFromLastKnownGoodWhenPrimaryBackupAndRecoveryCorrupted() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let config = makeConfigWithRelayAndStatusBarState()
        try store.save(config)

        let directory = appSupportDirectory(in: root)
        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        let recoveryURL = directory.appendingPathComponent("config.recovery.json")

        try Data("not-json".utf8).write(to: primaryURL, options: .atomic)
        try Data("still-not-json".utf8).write(to: backupURL, options: .atomic)
        try Data("definitely-not-json".utf8).write(to: recoveryURL, options: .atomic)

        let loaded = try store.load()

        XCTAssertEqual(loaded.statusBarProviderID, "open-custom-relay-persisted")
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", "open-custom-relay-persisted"])
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "open-custom-relay-persisted" && $0.enabled }))
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: primaryURL)))
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: backupURL)))
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: recoveryURL)))
    }

    func testLoadRecoversEnabledOfficialProvidersFromPersistedSlotsWhenPrimaryAndBackupCorrupted() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let directory = appSupportDirectory(in: root)

        let codexSlotStore = CodexAccountSlotStore(
            staleInterval: .greatestFiniteMagnitude,
            fileURL: directory.appendingPathComponent("codex_slots.json")
        )
        _ = codexSlotStore.upsertActive(
            snapshot: makeSnapshot(
                source: "codex-official",
                accountLabel: "codex@example.com",
                rawMeta: [
                    "codex.accountKey": "tenant:account:codex|principal:email:codex@example.com",
                    "codex.slotID": "A"
                ]
            ),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let claudeSlotStore = ClaudeAccountSlotStore(
            staleInterval: .greatestFiniteMagnitude,
            fileURL: directory.appendingPathComponent("claude_slots.json")
        )
        _ = claudeSlotStore.upsertActive(
            snapshot: makeSnapshot(
                source: "claude-official",
                accountLabel: "claude@example.com",
                rawMeta: [
                    "claude.accountKey": "claude:claude@example.com",
                    "claude.slotID": "A"
                ]
            ),
            now: Date(timeIntervalSince1970: 1_700_000_100)
        )
        // Slot persistence is asynchronous (store IO queue); fence it so the
        // recovery policy below observes the persisted files on disk.
        codexSlotStore.flushPendingDiskWrites()
        claudeSlotStore.flushPendingDiskWrites()

        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        try Data("not-json".utf8).write(to: primaryURL, options: .atomic)
        try Data("still-not-json".utf8).write(to: backupURL, options: .atomic)

        let loaded = try store.load()
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "codex-official" && $0.enabled }))
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "claude-official" && $0.enabled }))

        let restoredData = try Data(contentsOf: primaryURL)
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: restoredData))
    }

    func testLoadImportsLegacyRelayProvidersAndTopLevelSettingsFromAIBalanceMonitor() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        var currentConfig = AppConfig.default
        if let codexIndex = currentConfig.providers.firstIndex(where: { $0.id == "codex-official" }) {
            currentConfig.providers[codexIndex].enabled = true
        }
        try store.save(currentConfig)

        let legacyCodexRelay = makeLegacyRelayProvider(
            id: "open-legacy-codex-relay",
            name: "Codex 中转",
            baseURL: "https://dragoncode.codes"
        )
        let legacyMiMoRelay = makeLegacyRelayProvider(
            id: "open-legacy-mimo-relay",
            name: "MiMo 中转",
            baseURL: "https://platform.xiaomimimo.com"
        )

        var legacyProviders = AppConfig.default.providers
        legacyProviders.insert(legacyMiMoRelay, at: 0)
        legacyProviders.insert(legacyCodexRelay, at: 0)
        let legacyConfig = AppConfig(
            language: .en,
            launchAtLoginEnabled: true,
            showOfficialAccountEmailInMenuBar: true,
            statusBarProviderID: legacyCodexRelay.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: ["codex-official", legacyCodexRelay.id],
            statusBarAppearanceMode: .dark,
            statusBarDisplayStyle: .barNamePercent,
            providers: legacyProviders
        )
        try writeLegacyConfig(legacyConfig, in: root)

        let loaded = try store.load()

        XCTAssertEqual(loaded.language, .en)
        XCTAssertTrue(loaded.showOfficialAccountEmailInMenuBar)
        XCTAssertEqual(loaded.statusBarProviderID, legacyCodexRelay.id)
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", legacyCodexRelay.id])
        XCTAssertEqual(loaded.statusBarAppearanceMode, .dark)
        XCTAssertEqual(loaded.statusBarDisplayStyle, .barNamePercent)
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == legacyCodexRelay.id && $0.enabled }))
        XCTAssertNil(loaded.providers.first(where: { $0.id == legacyMiMoRelay.id }))
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "xiaomi-mimo-official" && $0.enabled }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyImportMarkerURL(in: root).path))
        XCTAssertEqual(legacyImportBackupDirectories(in: root).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyAppSupportDirectory(in: root).path))
    }

    func testLoadImportsLegacy186ConfigFromAIPlanMonitorDirectory() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let legacyProviderID = "open-legacy-dragoncode-relay"
        let legacyJSON = #"""
        {
          "language": "en",
          "launchAtLoginEnabled": true,
          "statusBarProviderID": "\#(legacyProviderID)",
          "statusBarMultiUsageEnabled": true,
          "statusBarMultiProviderIDs": ["\#(legacyProviderID)"],
          "statusBarAppearanceMode": "dark",
          "statusBarDisplayStyle": "barNamePercent",
          "providers": [
            {
              "id": "\#(legacyProviderID)",
              "name": "Codex Relay",
              "family": "thirdParty",
              "type": "relay",
              "enabled": true,
              "pollIntervalSec": 60,
              "threshold": {
                "lowRemaining": 10,
                "maxConsecutiveFailures": 2,
                "notifyOnAuthError": true
              },
              "auth": {
                "kind": "bearer",
                "keychainService": "AI Plan Monitor",
                "keychainAccount": "dragoncode.codes/auth_token"
              },
              "baseURL": "https://dragoncode.codes",
              "relayConfig": {
                "adapterID": "dragoncode",
                "baseURL": "https://dragoncode.codes",
                "tokenChannelEnabled": true,
                "balanceChannelEnabled": true,
                "balanceAuth": {
                  "kind": "bearer",
                  "keychainService": "AIPlanMonitor",
                  "keychainAccount": "dragoncode.codes/auth_token"
                },
                "balanceCredentialMode": "manualPreferred"
              }
            }
          ]
        }
        """#
        try writeLegacyConfigData(Data(legacyJSON.utf8), in: root, directoryName: "AIPlanMonitor")

        let loaded = try store.load()
        let importedRelay = try XCTUnwrap(loaded.providers.first(where: { $0.id == legacyProviderID }))

        XCTAssertEqual(loaded.language, .en)
        XCTAssertEqual(loaded.statusBarProviderID, legacyProviderID)
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, [legacyProviderID])
        XCTAssertEqual(loaded.statusBarAppearanceMode, .dark)
        XCTAssertEqual(loaded.statusBarDisplayStyle, .barNamePercent)
        XCTAssertEqual(importedRelay.auth.keychainService, KeychainService.defaultServiceName)
        XCTAssertEqual(importedRelay.relayConfig?.balanceAuth.keychainService, KeychainService.defaultServiceName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyImportMarkerURL(in: root, source: "aiplanmonitor").path))
        XCTAssertEqual(legacyImportBackupDirectories(in: root, source: "aiplanmonitor").count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: legacyAppSupportDirectory(in: root, directoryName: "AIPlanMonitor").path
            )
        )
    }

    func testLoadCopiesMissingLegacySupplementalFiles() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        try store.save(.default)
        try writeLegacyConfig(.default, in: root)

        let legacyDirectory = legacyAppSupportDirectory(in: root)
        let legacyProfilesData = Data("legacy-codex-profiles".utf8)
        let legacyHistoryData = Data("legacy-local-history".utf8)
        try legacyProfilesData.write(to: legacyDirectory.appendingPathComponent("codex_profiles.json"), options: .atomic)
        try legacyHistoryData.write(to: legacyDirectory.appendingPathComponent("local_usage_history_cache.json"), options: .atomic)

        _ = try store.load()

        let currentDirectory = appSupportDirectory(in: root)
        XCTAssertEqual(
            try Data(contentsOf: currentDirectory.appendingPathComponent("codex_profiles.json")),
            legacyProfilesData
        )
        XCTAssertEqual(
            try Data(contentsOf: currentDirectory.appendingPathComponent("local_usage_history_cache.json")),
            legacyHistoryData
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    func testLoadDoesNotReimportLegacyProvidersAfterMarkerIsWritten() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        try store.save(.default)

        let legacyRelay = makeLegacyRelayProvider(
            id: "open-legacy-dragoncode-relay",
            name: "Codex 中转",
            baseURL: "https://dragoncode.codes"
        )
        let legacyConfig = AppConfig(
            providers: [legacyRelay] + AppConfig.default.providers
        )
        try writeLegacyConfig(legacyConfig, in: root)

        let firstLoad = try store.load()
        let secondLoad = try store.load()

        let expectedIdentity = try XCTUnwrap(legacyRelay.legacyRelayImportIdentity)
        XCTAssertEqual(firstLoad.providers.filter { $0.legacyRelayImportIdentity == expectedIdentity }.count, 1)
        XCTAssertEqual(secondLoad.providers.filter { $0.legacyRelayImportIdentity == expectedIdentity }.count, 1)
        XCTAssertEqual(legacyImportBackupDirectories(in: root).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyAppSupportDirectory(in: root).path))
    }

    func testLoadCleansResidualLegacyDirectoryWhenMarkerAlreadyExists() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        try store.save(.default)

        try writeLegacyImportMarker(in: root)
        let legacyRelay = makeLegacyRelayProvider(
            id: "open-legacy-dragoncode-residual",
            name: "Residual Codex Relay",
            baseURL: "https://dragoncode.codes"
        )
        try writeLegacyConfig(
            AppConfig(providers: [legacyRelay] + AppConfig.default.providers),
            in: root
        )

        let loaded = try store.load()

        XCTAssertFalse(loaded.providers.contains(where: { $0.id == legacyRelay.id }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyAppSupportDirectory(in: root).path))
        XCTAssertTrue(legacyImportBackupDirectories(in: root).isEmpty)
    }

    func testLoadKeepsMigratedConfigWhenLegacyDirectoryCleanupFails() throws {
        let root = try makeTempDirectory()
        defer { try? setPermissions(0o755, for: root) }
        let store = ConfigStore(baseDirectoryURL: root)
        try store.save(.default)

        let legacyRelay = makeLegacyRelayProvider(
            id: "open-legacy-dragoncode-cleanup-fails",
            name: "Codex 中转",
            baseURL: "https://dragoncode.codes"
        )
        let legacyConfig = AppConfig(
            statusBarProviderID: legacyRelay.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: [legacyRelay.id],
            providers: [legacyRelay] + AppConfig.default.providers
        )
        try writeLegacyConfig(legacyConfig, in: root)
        try setPermissions(0o555, for: root)

        let loaded = try store.load()

        XCTAssertTrue(loaded.providers.contains(where: { $0.id == legacyRelay.id && $0.enabled }))
        XCTAssertEqual(loaded.statusBarProviderID, legacyRelay.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyAppSupportDirectory(in: root).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyImportMarkerURL(in: root).path))
    }

    func testLoadKeepsCurrentProviderForDuplicateLegacyRelayIdentity() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)

        var currentProviders = AppConfig.default.providers
        if let codexIndex = currentProviders.firstIndex(where: { $0.id == "codex-official" }) {
            currentProviders[codexIndex].enabled = true
        }
        var currentRelay = makeLegacyRelayProvider(
            id: "open-current-dragoncode-relay",
            name: "当前 Codex 中转",
            baseURL: "https://dragoncode.codes"
        )
        currentRelay.relayConfig?.manualOverrides = nil
        currentProviders.insert(currentRelay, at: 0)
        let currentConfig = AppConfig(providers: currentProviders)
        try store.save(currentConfig)

        var legacyRelay = makeLegacyRelayProvider(
            id: "open-legacy-dragoncode-relay-1776234471",
            name: "旧版 Codex 中转",
            baseURL: "https://dragoncode.codes"
        )
        legacyRelay.relayConfig?.manualOverrides = RelayManualOverride(
            authHeader: "Authorization",
            authScheme: "Bearer",
            userID: nil,
            userIDHeader: "New-Api-User",
            requestMethod: "GET",
            requestBodyJSON: nil,
            endpointPath: "/api/v1/auth/me",
            remainingExpression: "data.balance",
            usedExpression: nil,
            limitExpression: nil,
            successExpression: nil,
            unitExpression: "balance",
            accountLabelExpression: nil,
            staticHeaders: ["X-Legacy-Trace": "1"]
        )
        let legacyConfig = AppConfig(
            statusBarProviderID: legacyRelay.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: ["codex-official", legacyRelay.id],
            providers: [legacyRelay] + AppConfig.default.providers
        )
        try writeLegacyConfig(legacyConfig, in: root)

        let loaded = try store.load()

        let currentIdentity = try XCTUnwrap(currentRelay.legacyRelayImportIdentity)
        let matchingProviders = loaded.providers.filter { $0.legacyRelayImportIdentity == currentIdentity }
        XCTAssertEqual(matchingProviders.count, 1)
        XCTAssertEqual(matchingProviders.first?.id, currentRelay.id)
        XCTAssertEqual(matchingProviders.first?.name, currentRelay.name)
        XCTAssertEqual(
            matchingProviders.first?.relayConfig?.manualOverrides?.staticHeaders?["X-Legacy-Trace"],
            "1"
        )
        XCTAssertEqual(loaded.statusBarProviderID, currentRelay.id)
        XCTAssertTrue(loaded.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, ["codex-official", currentRelay.id])
    }

    func testLoadSkipsInvalidLegacyConfigWithoutMutatingCurrentConfig() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let currentConfig = makeConfigWithRelayAndStatusBarState()
        try store.save(currentConfig)

        let legacyDirectory = legacyAppSupportDirectory(in: root)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: legacyDirectory.appendingPathComponent("config.json"), options: .atomic)

        let loaded = try store.load()

        XCTAssertEqual(loaded, currentConfig)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyImportMarkerURL(in: root).path))
        XCTAssertTrue(legacyImportBackupDirectories(in: root).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    func testLegacyImportFromGoldenFixtureDoesNotOverwriteNonDefaultCurrentSettings() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        let currentConfig = makeConfigWithRelayAndStatusBarState()
        try store.save(currentConfig)
        try writeLegacyConfigData(
            fixtureData("legacy-aibalancemonitor-nondefault-settings.json"),
            in: root,
            directoryName: "AIBalanceMonitor"
        )

        let loaded = try store.load()

        XCTAssertEqual(loaded.language, currentConfig.language)
        XCTAssertEqual(loaded.launchAtLoginEnabled, currentConfig.launchAtLoginEnabled)
        XCTAssertEqual(loaded.showOfficialAccountEmailInMenuBar, currentConfig.showOfficialAccountEmailInMenuBar)
        XCTAssertEqual(loaded.statusBarProviderID, currentConfig.statusBarProviderID)
        XCTAssertEqual(loaded.statusBarMultiUsageEnabled, currentConfig.statusBarMultiUsageEnabled)
        XCTAssertEqual(loaded.statusBarMultiProviderIDs, currentConfig.statusBarMultiProviderIDs)
        XCTAssertEqual(loaded.statusBarAppearanceMode, currentConfig.statusBarAppearanceMode)
        XCTAssertEqual(loaded.statusBarDisplayStyle, currentConfig.statusBarDisplayStyle)
        XCTAssertTrue(loaded.providers.contains(where: { $0.id == "open-legacy-golden-relay" && $0.enabled }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyImportMarkerURL(in: root).path))
        XCTAssertEqual(legacyImportBackupDirectories(in: root).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyAppSupportDirectory(in: root).path))
    }

    func testResetRemovesPrimaryAndBackup() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(baseDirectoryURL: root)
        try store.save(.default)

        let directory = root.appendingPathComponent("OhMyUsage", isDirectory: true)
        let primaryURL = directory.appendingPathComponent("config.json")
        let backupURL = directory.appendingPathComponent("config.backup.json")
        let recoveryURL = directory.appendingPathComponent("config.recovery.json")
        let lastKnownGoodURL = directory.appendingPathComponent("config.last-known-good.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lastKnownGoodURL.path))

        try store.reset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lastKnownGoodURL.path))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("config-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixtureData(_ name: String, filePath: String = #filePath) throws -> Data {
        let fixturesURL = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("ConfigStore", isDirectory: true)
        return try Data(contentsOf: fixturesURL.appendingPathComponent(name))
    }

    private func appSupportDirectory(in root: URL) -> URL {
        root.appendingPathComponent("OhMyUsage", isDirectory: true)
    }

    private func legacyAppSupportDirectory(in root: URL, directoryName: String = "AIBalanceMonitor") -> URL {
        root.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func legacyImportMarkerURL(in root: URL, source: String = "aibalancemonitor") -> URL {
        appSupportDirectory(in: root).appendingPathComponent("legacy-import-\(source).done")
    }

    private func legacyImportBackupDirectories(in root: URL, source: String = "aibalancemonitor") -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: appSupportDirectory(in: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory && url.lastPathComponent.hasPrefix("legacy-import-backup-\(source)-")
        }
    }

    private func writeLegacyConfig(_ config: AppConfig, in root: URL, directoryName: String = "AIBalanceMonitor") throws {
        let data = try JSONEncoder.prettySorted.encode(config)
        try writeLegacyConfigData(data, in: root, directoryName: directoryName)
    }

    private func writeLegacyConfigData(_ data: Data, in root: URL, directoryName: String) throws {
        let directory = legacyAppSupportDirectory(in: root, directoryName: directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("config.json"), options: .atomic)
    }

    private func writeLegacyImportMarker(in root: URL, source: String = "aibalancemonitor") throws {
        let markerURL = legacyImportMarkerURL(in: root, source: source)
        try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("importedAt=test\n".utf8).write(to: markerURL, options: .atomic)
    }

    private func setPermissions(_ permissions: Int16, for url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: url.path
        )
    }

    private func makeConfigWithRelayAndStatusBarState() -> AppConfig {
        var providers = AppConfig.default.providers
        if let codexIndex = providers.firstIndex(where: { $0.id == "codex-official" }) {
            providers[codexIndex].enabled = true
        }

        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Persisted Relay",
            baseURL: "https://relay.persisted.example"
        )
        relay.id = "open-custom-relay-persisted"
        relay.enabled = true
        providers.insert(relay, at: 1)

        return AppConfig(
            language: .en,
            launchAtLoginEnabled: true,
            showOfficialAccountEmailInMenuBar: true,
            claudeStatusBarDisplaySlotID: .b,
            statusBarProviderID: relay.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: ["codex-official", relay.id],
            statusBarAppearanceMode: .dark,
            statusBarDisplayStyle: .barNamePercent,
            providers: providers
        )
    }

    private func makeLegacyRelayProvider(
        id: String,
        name: String,
        baseURL: String
    ) -> ProviderDescriptor {
        var relay = ProviderDescriptor.makeOpenRelay(name: name, baseURL: baseURL)
        relay.id = id
        relay.enabled = true
        return relay.normalized()
    }

    private func makeLossyConfigJSON() -> String {
        #"""
        {
          "language":"en",
          "launchAtLoginEnabled":true,
          "statusBarProviderID":"codex-official",
          "statusBarMultiUsageEnabled":true,
          "statusBarMultiProviderIDs":["codex-official","open-custom-relay-persisted"],
          "providers":[
            {
              "id":"legacy-opencode-go",
              "name":"Legacy OpenCode Go",
              "family":"official",
              "type":"openCodeGo",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"bearer"}
            },
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
    }

    private func makeSnapshot(
        source: String,
        accountLabel: String,
        rawMeta: [String: String]
    ) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            note: "Persisted snapshot",
            sourceLabel: "Test",
            accountLabel: accountLabel,
            extras: [:],
            rawMeta: rawMeta
        )
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
