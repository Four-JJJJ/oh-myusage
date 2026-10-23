import Foundation
import XCTest
@testable import OhMyUsage

final class ClaudeAccountProfileStoreTests: XCTestCase {
    func testSaveProfileFromConfigDirectoryParsesMetadata() throws {
        let store = makeStore()
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-dir-a",
                email: "dir-a@example.com",
                accessToken: "access-dir-a"
            )
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Dir A",
            note: nil,
            source: .configDir,
            configDir: configDir,
            credentialsJSON: nil,
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.slotID, .a)
        XCTAssertEqual(profile.source, .configDir)
        XCTAssertEqual(profile.accountId, "acc-dir-a")
        XCTAssertEqual(profile.accountEmail, "dir-a@example.com")
        XCTAssertNotNil(profile.credentialFingerprint)
        XCTAssertTrue(profile.credentialsJSON?.contains("access-dir-a") == true)
    }

    func testSaveProfileFromManualCredentialsParsesMetadata() throws {
        let store = makeStore()
        let credentials = sampleCredentialsJSON(
            accountID: "acc-manual-a",
            email: "manual-a@example.com",
            accessToken: "access-manual-a"
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Manual A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: credentials,
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.slotID, .a)
        XCTAssertEqual(profile.source, .manualCredentials)
        XCTAssertEqual(profile.accountId, "acc-manual-a")
        XCTAssertEqual(profile.accountEmail, "manual-a@example.com")
        XCTAssertEqual(
            profile.credentialFingerprint,
            try ClaudeAccountProfileStore.parseCredentialsJSON(credentials).credentialFingerprint
        )
    }

    func testSaveProfileFallsBackToClaudeConfigEmailWhenCredentialsMissingEmail() throws {
        let store = makeStore()
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-config-fallback",
                email: nil,
                accessToken: "access-config-fallback"
            ),
            claudeJSON: sampleClaudeConfigJSON(email: "config-fallback@example.com")
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Config Fallback",
            note: nil,
            source: .configDir,
            configDir: configDir,
            credentialsJSON: nil,
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.accountEmail, "config-fallback@example.com")
    }

    func testManualCredentialsWithConfigDirFallsBackToClaudeConfigEmail() throws {
        let store = makeStore()
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-manual-config",
                email: nil,
                accessToken: "access-manual-config"
            ),
            claudeJSON: sampleClaudeConfigJSON(email: "manual-config@example.com")
        )
        let manualCredentials = sampleCredentialsJSON(
            accountID: "acc-manual-config",
            email: nil,
            accessToken: "access-manual-config"
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Manual Config",
            note: nil,
            source: .manualCredentials,
            configDir: configDir,
            credentialsJSON: manualCredentials,
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.accountEmail, "manual-config@example.com")
    }

    func testManualCredentialsWithoutConfigDirDoesNotFallbackEmail() throws {
        let store = makeStore()
        let manualCredentials = sampleCredentialsJSON(
            accountID: "acc-manual-only",
            email: nil,
            accessToken: "access-manual-only"
        )

        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Manual Only",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: manualCredentials,
            currentFingerprint: nil
        )

        XCTAssertNil(profile.accountEmail)
    }

    func testNextAvailableSlotIDAdvancesPastImportedProfiles() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-a",
                email: "a@example.com",
                accessToken: "access-a"
            ),
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: CodexSlotID(rawValue: "C"),
            displayName: "C",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-c",
                email: "c@example.com",
                accessToken: "access-c"
            ),
            currentFingerprint: nil
        )

        XCTAssertEqual(store.nextAvailableSlotID().rawValue, "B")
    }

    func testFingerprintDedupMovesProfileIntoChosenSlot() throws {
        let store = makeStore()
        let shared = sampleCredentialsJSON(
            accountID: "acc-shared",
            email: "shared@example.com",
            accessToken: "access-shared"
        )

        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: shared,
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: .b,
            displayName: "B",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: shared,
            currentFingerprint: nil
        )

        let profiles = store.profiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .b)
    }

    func testSameEmailDifferentFingerprintDoesNotMerge() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-a",
                email: "shared@example.com",
                accessToken: "access-a"
            ),
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: .b,
            displayName: "B",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-b",
                email: "shared@example.com",
                accessToken: "access-b"
            ),
            currentFingerprint: nil
        )

        let profiles = store.profiles()
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(Set(profiles.map(\.slotID.rawValue)), ["A", "B"])
        XCTAssertEqual(Set(profiles.compactMap(\.credentialFingerprint)).count, 2)
    }

    func testCaptureCurrentCredentialsStoresAThenBThenC() {
        let store = makeStore()

        _ = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-a",
                email: "a@example.com",
                accessToken: "access-a"
            ),
            defaultConfigDir: nil
        )
        _ = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-b",
                email: "b@example.com",
                accessToken: "access-b"
            ),
            defaultConfigDir: nil
        )
        let profiles = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-c",
                email: "c@example.com",
                accessToken: "access-c"
            ),
            defaultConfigDir: nil
        )

        XCTAssertEqual(profiles.map(\.slotID.rawValue), ["A", "B", "C"])
        XCTAssertEqual(profiles.filter(\.isCurrentSystemAccount).count, 1)
        XCTAssertEqual(profiles.first(where: \.isCurrentSystemAccount)?.slotID.rawValue, "C")
    }

    func testCaptureCurrentCredentialsSameAccountDifferentAccessTokenDoesNotCreateNewProfile() throws {
        let store = makeStore()
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-same",
                email: "same@example.com",
                accessToken: "access-token-v1"
            )
        )

        let firstProfiles = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-same",
                email: "same@example.com",
                accessToken: "access-token-v1"
            ),
            defaultConfigDir: configDir
        )
        XCTAssertEqual(firstProfiles.count, 1)

        let secondJSON = sampleCredentialsJSON(
            accountID: "acc-same",
            email: "same@example.com",
            accessToken: "access-token-v2"
        )
        let secondProfiles = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: secondJSON,
            defaultConfigDir: configDir
        )

        XCTAssertEqual(secondProfiles.count, 1)
        XCTAssertEqual(secondProfiles.first?.slotID, firstProfiles.first?.slotID)
        XCTAssertEqual(secondProfiles.first?.accountId, "acc-same")
        XCTAssertEqual(
            secondProfiles.first?.credentialFingerprint,
            try ClaudeAccountProfileStore.parseCredentialsJSON(secondJSON).credentialFingerprint
        )
    }

    func testCompactAutoCapturedProfilesMergesSameAccountAndReturnsRemovedSlots() throws {
        let store = makeStore()
        let credentialsA = sampleCredentialsJSON(
            accountID: "acc-compact",
            email: "compact@example.com",
            accessToken: "compact-token-a"
        )
        let credentialsB = sampleCredentialsJSON(
            accountID: "acc-compact",
            email: "compact@example.com",
            accessToken: "compact-token-b"
        )
        let configDirA = makeConfigDirectory(credentialsJSON: credentialsA)
        let configDirB = makeConfigDirectory(credentialsJSON: credentialsB)
        let fingerprintB = try ClaudeAccountProfileStore.parseCredentialsJSON(credentialsB).credentialFingerprint

        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            source: .configDir,
            configDir: configDirA,
            credentialsJSON: nil,
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: .b,
            displayName: "B",
            note: nil,
            source: .configDir,
            configDir: configDirB,
            credentialsJSON: nil,
            currentFingerprint: nil
        )

        let result = store.compactAutoCapturedProfiles(
            defaultConfigDir: configDirA,
            currentFingerprint: fingerprintB
        )

        XCTAssertTrue(result.didCompact)
        XCTAssertEqual(result.profiles.count, 1)
        XCTAssertEqual(result.profiles.first?.slotID, .b)
        XCTAssertEqual(result.profiles.first?.accountId, "acc-compact")
        XCTAssertEqual(result.removedSlotIDs, [.a])
        XCTAssertTrue(result.profiles.first?.isCurrentSystemAccount == true)
    }

    func testRemovedCurrentFingerprintIsNotAutoCapturedAgainImmediately() throws {
        let store = makeStore()
        let credentialsJSON = sampleCredentialsJSON(
            accountID: "acc-current",
            email: "current@example.com",
            accessToken: "access-current"
        )
        let fingerprint = try ClaudeAccountProfileStore.parseCredentialsJSON(credentialsJSON).credentialFingerprint

        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Current",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: credentialsJSON,
            currentFingerprint: fingerprint
        )
        _ = store.removeProfile(slotID: .a)
        let profiles = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: credentialsJSON,
            defaultConfigDir: nil
        )

        XCTAssertTrue(profiles.isEmpty)
    }

    func testMetadataUpdateForConfigProfileDoesNotReadMissingCredentialsFile() throws {
        let store = makeStore()
        let credentialsJSON = sampleCredentialsJSON(
            accountID: "acc-metadata",
            email: "metadata@example.com",
            accessToken: "access-metadata"
        )
        let configDir = makeConfigDirectory(credentialsJSON: credentialsJSON)
        let fingerprint = try ClaudeAccountProfileStore.parseCredentialsJSON(credentialsJSON).credentialFingerprint

        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Claude A",
            note: nil,
            source: .configDir,
            configDir: configDir,
            credentialsJSON: nil,
            currentFingerprint: fingerprint
        )
        let before = try XCTUnwrap(store.profile(slotID: .a))
        try FileManager.default.removeItem(
            atPath: ClaudeAccountProfileStore.credentialsFilePath(configDirectory: configDir)
        )

        let updated = try XCTUnwrap(
            store.updateProfileMetadataIfCredentialInputsUnchanged(
                slotID: .a,
                displayName: "Claude A",
                note: "工作账号",
                source: .configDir,
                configDir: configDir,
                credentialsJSON: nil
            )
        )

        XCTAssertEqual(updated.note, "工作账号")
        XCTAssertEqual(updated.source, before.source)
        XCTAssertEqual(updated.configDir, before.configDir)
        XCTAssertEqual(updated.credentialsJSON, before.credentialsJSON)
        XCTAssertEqual(updated.accountId, before.accountId)
        XCTAssertEqual(updated.accountEmail, before.accountEmail)
        XCTAssertEqual(updated.credentialFingerprint, before.credentialFingerprint)
        XCTAssertEqual(updated.lastImportedAt, before.lastImportedAt)
        XCTAssertEqual(updated.isCurrentSystemAccount, before.isCurrentSystemAccount)
        XCTAssertEqual(store.profile(slotID: .a)?.note, "工作账号")
    }

    func testMetadataUpdateNormalizesEmptyNote() throws {
        let store = makeStore()
        let credentialsJSON = sampleCredentialsJSON(
            accountID: "acc-empty-note",
            email: "empty-note@example.com",
            accessToken: "access-empty-note"
        )

        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Manual A",
            note: "旧备注",
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: credentialsJSON,
            currentFingerprint: nil
        )

        let updated = try XCTUnwrap(
            store.updateProfileMetadataIfCredentialInputsUnchanged(
                slotID: .a,
                displayName: "Manual A",
                note: "  \n\t  ",
                source: .manualCredentials,
                configDir: nil,
                credentialsJSON: "\n\(credentialsJSON)\n"
            )
        )

        XCTAssertNil(updated.note)
        XCTAssertNil(store.profile(slotID: .a)?.note)
    }

    func testMetadataUpdateDoesNotRunWhenCredentialInputsChange() throws {
        let store = makeStore()
        let firstCredentials = sampleCredentialsJSON(
            accountID: "acc-first",
            email: "first@example.com",
            accessToken: "access-first"
        )
        let secondCredentials = sampleCredentialsJSON(
            accountID: "acc-second",
            email: "second@example.com",
            accessToken: "access-second"
        )

        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Manual A",
            note: "旧备注",
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: firstCredentials,
            currentFingerprint: nil
        )
        let before = try XCTUnwrap(store.profile(slotID: .a))

        let updated = try store.updateProfileMetadataIfCredentialInputsUnchanged(
            slotID: .a,
            displayName: "Manual A",
            note: "新备注",
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: secondCredentials
        )

        XCTAssertNil(updated)
        XCTAssertEqual(store.profile(slotID: .a), before)
    }

    func testProfilesBackfillEmailFromClaudeConfigForLegacyStoredProfile() throws {
        let storeFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-profile-legacy-\(UUID().uuidString).json")
        let configDir = makeConfigDirectory(
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-legacy",
                email: nil,
                accessToken: "legacy-access-token"
            ),
            claudeJSON: sampleClaudeConfigJSON(email: "legacy-backfilled@example.com")
        )
        let credentialsJSON = sampleCredentialsJSON(
            accountID: "acc-legacy",
            email: nil,
            accessToken: "legacy-access-token"
        )
        let fingerprint = try ClaudeAccountProfileStore.parseCredentialsJSON(credentialsJSON).credentialFingerprint
        let importedAt = Date(timeIntervalSince1970: 1_745_280_000)
        let importedAtISO = ISO8601DateFormatter().string(from: importedAt)
        let legacyRoot: [String: Any] = [
            "profiles": [
                [
                    "slotID": "A",
                    "displayName": "Claude A",
                    "note": NSNull(),
                    "source": "configDir",
                    "configDir": configDir,
                    "credentialsJSON": credentialsJSON,
                    "accountId": "acc-legacy",
                    "accountEmail": NSNull(),
                    "credentialFingerprint": fingerprint,
                    "lastImportedAt": importedAtISO,
                    "isCurrentSystemAccount": false
                ]
            ]
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyRoot, options: [.prettyPrinted, .sortedKeys])
        try legacyData.write(to: storeFile, options: .atomic)

        let store = ClaudeAccountProfileStore(fileURL: storeFile)
        let profiles = store.profiles()

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .a)
        XCTAssertEqual(profiles.first?.accountEmail, "legacy-backfilled@example.com")
        XCTAssertEqual(profiles.first?.credentialFingerprint, fingerprint)
    }

    func testSupportsQuotaMonitoringReturnsTrueWhenUserProfileScopeExists() throws {
        let profile = ClaudeAccountProfile(
            slotID: .a,
            displayName: "Claude A",
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-monitorable",
                email: "monitorable@example.com",
                accessToken: "access-monitorable"
            ),
            accountId: "acc-monitorable",
            accountEmail: "monitorable@example.com",
            credentialFingerprint: "fingerprint-a",
            lastImportedAt: Date(),
            isCurrentSystemAccount: false
        )

        XCTAssertTrue(ClaudeAccountProfileStore.supportsQuotaMonitoring(profile: profile))
    }

    func testSupportsQuotaMonitoringReturnsFalseForInferenceOnlyScopes() {
        let profile = ClaudeAccountProfile(
            slotID: .a,
            displayName: "Claude A",
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleInferenceOnlyCredentialsJSON(
                accountID: "acc-proxy",
                email: "proxy@example.com",
                accessToken: "access-proxy"
            ),
            accountId: "acc-proxy",
            accountEmail: "proxy@example.com",
            credentialFingerprint: "fingerprint-b",
            lastImportedAt: Date(),
            isCurrentSystemAccount: true
        )

        XCTAssertFalse(ClaudeAccountProfileStore.supportsQuotaMonitoring(profile: profile))
    }

    func testUnchangedReSyncDoesNotRewriteProfileFile() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        let store = ClaudeAccountProfileStore(fileURL: path)
        let credentialsJSON = sampleCredentialsJSON(
            accountID: "acc-steady",
            email: "steady@example.com",
            accessToken: "access-steady"
        )

        _ = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: credentialsJSON,
            defaultConfigDir: nil
        )
        store.flushPendingDiskWrites()
        let firstWrite = try fileFingerprint(at: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        // Re-syncing the exact same credential must not touch the file.
        _ = store.captureCurrentCredentialsIfNeeded(
            credentialsJSON: credentialsJSON,
            defaultConfigDir: nil
        )
        store.flushPendingDiskWrites()
        XCTAssertEqual(try fileFingerprint(at: path), firstWrite)

        // A new store instance seeds its dedupe fingerprint from the on-disk
        // state, so an unchanged no-op commit still skips the disk write.
        let reloaded = ClaudeAccountProfileStore(fileURL: path)
        _ = reloaded.removeProfile(slotID: CodexSlotID(rawValue: "Z"))
        reloaded.flushPendingDiskWrites()
        XCTAssertEqual(try fileFingerprint(at: path), firstWrite)

        // Changed content must still reach the disk.
        _ = store.updateStoredCredentials(
            slotID: .a,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-steady",
                email: "steady@example.com",
                accessToken: "access-rotated"
            )
        )
        store.flushPendingDiskWrites()
        XCTAssertNotEqual(try fileFingerprint(at: path), firstWrite)
    }

    func testSaveThenReloadRoundTripsThroughDiskAfterFlush() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        let store = ClaudeAccountProfileStore(fileURL: path)
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Persisted",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: sampleCredentialsJSON(
                accountID: "acc-persist",
                email: "persist@example.com",
                accessToken: "access-persist"
            ),
            currentFingerprint: nil
        )
        store.flushPendingDiskWrites()

        let reloaded = ClaudeAccountProfileStore(fileURL: path)
        XCTAssertEqual(reloaded.profiles().map(\.slotID), [.a])
        XCTAssertEqual(reloaded.profile(slotID: .a)?.accountId, "acc-persist")
        XCTAssertEqual(reloaded.profile(slotID: .a)?.displayName, "Persisted")
    }

    // MARK: - Vault-backed token storage (P0-2)

    func testVaultMigrationMovesLegacyFileTokenIntoVaultAndStripsFile() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        let legacyToken = sampleCredentialsJSON(
            accountID: "acc-vault",
            email: "vault@example.com",
            accessToken: "legacy-claude-access"
        )
        // Seed a legacy (pre-vault) profile file that still embeds the token.
        let seedStore = ClaudeAccountProfileStore(fileURL: path)
        _ = try seedStore.saveProfile(
            slotID: .a,
            displayName: "Vault Migrated",
            note: "keep-me",
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: legacyToken,
            currentFingerprint: nil
        )
        seedStore.flushPendingDiskWrites()
        XCTAssertTrue(try String(contentsOf: path, encoding: .utf8).contains("legacy-claude-access"))

        let vault = try makeVault()
        let store = ClaudeAccountProfileStore(fileURL: path, oauthVault: vault)
        store.flushPendingDiskWrites()

        XCTAssertEqual(vault.readProfileOAuthJSON(provider: .claude, slotID: .a), legacyToken)

        let fileText = try String(contentsOf: path, encoding: .utf8)
        XCTAssertFalse(fileText.contains("legacy-claude-access"))
        XCTAssertTrue(fileText.contains("Vault Migrated"))
        XCTAssertTrue(fileText.contains("acc-vault"))

        // The in-memory copy keeps the resolved token for switch/refresh callers.
        let profile = try XCTUnwrap(store.profile(slotID: .a))
        XCTAssertEqual(profile.credentialsJSON, legacyToken)
        XCTAssertEqual(profile.accountId, "acc-vault")
        XCTAssertEqual(profile.accountEmail, "vault@example.com")
        XCTAssertEqual(profile.displayName, "Vault Migrated")
        XCTAssertEqual(profile.note, "keep-me")
        XCTAssertNotNil(profile.credentialFingerprint)
        XCTAssertEqual(try store.resolvedCredentialsJSON(for: profile), legacyToken)
    }

    func testVaultMigrationIsIdempotentAcrossReloads() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        let legacyToken = sampleCredentialsJSON(
            accountID: "acc-idempotent",
            email: "idempotent@example.com",
            accessToken: "idempotent-claude-access"
        )
        let seedStore = ClaudeAccountProfileStore(fileURL: path)
        _ = try seedStore.saveProfile(
            slotID: .a,
            displayName: "Idempotent",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: legacyToken,
            currentFingerprint: nil
        )
        seedStore.flushPendingDiskWrites()

        let vault = try makeVault()
        let firstPass = ClaudeAccountProfileStore(fileURL: path, oauthVault: vault)
        firstPass.flushPendingDiskWrites()
        let fingerprintAfterMigration = try fileFingerprint(at: path)

        // Re-loading the already-migrated file must not rewrite it and must
        // keep resolving the token from the vault.
        let reloaded = ClaudeAccountProfileStore(fileURL: path, oauthVault: vault)
        reloaded.flushPendingDiskWrites()
        XCTAssertEqual(try fileFingerprint(at: path), fingerprintAfterMigration)
        XCTAssertEqual(vault.readProfileOAuthJSON(provider: .claude, slotID: .a), legacyToken)
        XCTAssertEqual(reloaded.profile(slotID: .a)?.credentialsJSON, legacyToken)
        XCTAssertEqual(reloaded.profile(slotID: .a)?.displayName, "Idempotent")
    }

    func testVaultWriteFailureKeepsTokenInFileForRetry() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        let legacyToken = sampleCredentialsJSON(
            accountID: "acc-fail",
            email: "fail@example.com",
            accessToken: "failing-vault-claude"
        )
        let seedStore = ClaudeAccountProfileStore(fileURL: path)
        _ = try seedStore.saveProfile(
            slotID: .a,
            displayName: "Failing",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: legacyToken,
            currentFingerprint: nil
        )
        seedStore.flushPendingDiskWrites()

        let failingVault = OfficialOAuthVaultStore(
            keychain: FailingTokenCredentialStore(),
            defaults: makeTestDefaultsForTeardown()
        )
        let store = ClaudeAccountProfileStore(fileURL: path, oauthVault: failingVault)
        store.flushPendingDiskWrites()

        // The file is NOT stripped when the vault write fails — the token stays
        // available and behavior does not regress.
        var fileText = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(fileText.contains("failing-vault-claude"))
        XCTAssertEqual(store.profile(slotID: .a)?.credentialsJSON, legacyToken)

        // New saves also fall back to the file while the vault is failing.
        let fallbackToken = sampleCredentialsJSON(
            accountID: "acc-fallback",
            email: "fallback@example.com",
            accessToken: "fallback-claude-access"
        )
        _ = try store.saveProfile(
            slotID: .b,
            displayName: "Fallback",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: fallbackToken,
            currentFingerprint: nil
        )
        store.flushPendingDiskWrites()
        fileText = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(fileText.contains("fallback-claude-access"))
        XCTAssertNil(failingVault.readProfileOAuthJSON(provider: .claude, slotID: .b))

        // A healthy vault on the next load migrates both tokens losslessly.
        let healthyVault = try makeVault()
        let recovered = ClaudeAccountProfileStore(fileURL: path, oauthVault: healthyVault)
        recovered.flushPendingDiskWrites()
        let recoveredText = try String(contentsOf: path, encoding: .utf8)
        XCTAssertFalse(recoveredText.contains("failing-vault-claude"))
        XCTAssertFalse(recoveredText.contains("fallback-claude-access"))
        XCTAssertEqual(healthyVault.readProfileOAuthJSON(provider: .claude, slotID: .a), legacyToken)
        XCTAssertEqual(healthyVault.readProfileOAuthJSON(provider: .claude, slotID: .b), fallbackToken)
    }

    func testSaveProfileWithVaultStoresTokenInVaultOnly() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        let vault = try makeVault()
        let store = ClaudeAccountProfileStore(fileURL: path, oauthVault: vault)
        let token = sampleCredentialsJSON(
            accountID: "acc-new",
            email: "new@example.com",
            accessToken: "vault-only-claude"
        )

        let profile = try store.saveProfile(
            slotID: .b,
            displayName: "Vault Only",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: token,
            currentFingerprint: nil
        )
        store.flushPendingDiskWrites()

        XCTAssertEqual(vault.readProfileOAuthJSON(provider: .claude, slotID: .b), token)
        let fileText = try String(contentsOf: path, encoding: .utf8)
        XCTAssertFalse(fileText.contains("vault-only-claude"))
        XCTAssertTrue(fileText.contains("Vault Only"))
        // The returned (in-memory) profile still carries the full token.
        XCTAssertEqual(profile.credentialsJSON, token)
        XCTAssertEqual(store.profile(slotID: .b)?.credentialsJSON, token)
    }

    func testUpdateStoredCredentialsRotatesVaultTokenAndKeepsFileTokenFree() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        let vault = try makeVault()
        let store = ClaudeAccountProfileStore(fileURL: path, oauthVault: vault)
        let originalToken = sampleCredentialsJSON(
            accountID: "acc-rotate",
            email: "rotate@example.com",
            accessToken: "original-claude-access"
        )
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Rotate",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: originalToken,
            currentFingerprint: nil
        )
        store.flushPendingDiskWrites()

        let rotatedToken = sampleCredentialsJSON(
            accountID: "acc-rotate",
            email: "rotate@example.com",
            accessToken: "rotated-claude-access"
        )
        let updated = try XCTUnwrap(store.updateStoredCredentials(slotID: .a, credentialsJSON: rotatedToken))
        store.flushPendingDiskWrites()

        XCTAssertEqual(vault.readProfileOAuthJSON(provider: .claude, slotID: .a), rotatedToken)
        XCTAssertEqual(updated.credentialsJSON, rotatedToken)
        let fileText = try String(contentsOf: path, encoding: .utf8)
        XCTAssertFalse(fileText.contains("original-claude-access"))
        XCTAssertFalse(fileText.contains("rotated-claude-access"))
    }

    func testMetadataOnlyProfileResolvesTokenFromProviderVaultFallback() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        let token = sampleCredentialsJSON(
            accountID: "acc-fallback",
            email: "fallback@example.com",
            accessToken: "fallback-current-claude"
        )
        let originalVault = try makeVault()
        let seedStore = ClaudeAccountProfileStore(fileURL: path, oauthVault: originalVault)
        _ = try seedStore.saveProfile(
            slotID: .a,
            displayName: "Fallback",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: token,
            currentFingerprint: nil
        )
        seedStore.flushPendingDiskWrites()

        // Fresh vault whose only content is the provider-wide "current" entry
        // with a fingerprint matching the stored profile.
        let recoveryVault = try makeVault()
        XCTAssertTrue(recoveryVault.saveOAuthJSON(provider: .claude, rawJSON: token))

        let store = ClaudeAccountProfileStore(fileURL: path, oauthVault: recoveryVault)
        XCTAssertEqual(store.profile(slotID: .a)?.credentialsJSON, token)
        // The per-slot entry was backfilled from the provider-wide copy.
        XCTAssertEqual(recoveryVault.readProfileOAuthJSON(provider: .claude, slotID: .a), token)
    }

    func testRemoveProfileKeepsVaultTokenEntry() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        let vault = try makeVault()
        let store = ClaudeAccountProfileStore(fileURL: path, oauthVault: vault)
        let token = sampleCredentialsJSON(
            accountID: "acc-remove",
            email: "remove@example.com",
            accessToken: "remove-claude-access"
        )
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Remove",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: token,
            currentFingerprint: nil
        )
        store.flushPendingDiskWrites()

        _ = store.removeProfile(slotID: .a)
        store.flushPendingDiskWrites()

        // Conservative on purpose: removing a profile never destroys the last
        // copy of the credential.
        XCTAssertEqual(vault.readProfileOAuthJSON(provider: .claude, slotID: .a), token)
        XCTAssertNil(store.profile(slotID: .a))
    }

    private func makeVault() throws -> OfficialOAuthVaultStore {
        OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: makeTestDefaultsForTeardown())
    }

    /// Isolated `UserDefaults` domain that is removed when the test finishes.
    private func makeTestDefaultsForTeardown() -> UserDefaults {
        let (defaults, suiteName) = makeTestDefaults()
        addTeardownBlock { removeTestDefaults(named: suiteName) }
        return defaults
    }

    /// Identifies a physical write: `PrivateProfileFile` always writes through
    /// a fresh staging file and renames it, so an actual disk write necessarily
    /// changes the inode (and the mtime).
    private struct WriteFingerprint: Equatable {
        var inode: Int
        var modificationDate: Date
    }

    private func fileFingerprint(at url: URL) throws -> WriteFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return WriteFingerprint(
            inode: try XCTUnwrap(attributes[.systemFileNumber] as? Int),
            modificationDate: try XCTUnwrap(attributes[.modificationDate] as? Date)
        )
    }

    private func makeStore() -> ClaudeAccountProfileStore {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-profile-tests-\(UUID().uuidString).json")
        return ClaudeAccountProfileStore(fileURL: path)
    }

    private func makeConfigDirectory(credentialsJSON: String, claudeJSON: String? = nil) -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-profile-dir-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let credentialsURL = directory.appendingPathComponent(".credentials.json")
        try? credentialsJSON.data(using: .utf8)?.write(to: credentialsURL, options: .atomic)
        if let claudeJSON {
            let claudeConfigURL = directory.appendingPathComponent("claude.json")
            try? claudeJSON.data(using: .utf8)?.write(to: claudeConfigURL, options: .atomic)
        }
        return directory.path
    }

    private func sampleCredentialsJSON(
        accountID: String?,
        email: String?,
        accessToken: String,
        refreshToken: String = "refresh-token",
        expiresAtMs: Double = 4_102_444_800_000
    ) -> String {
        var root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "refreshToken": refreshToken,
                "expiresAt": expiresAtMs,
                "subscriptionType": "pro",
                "scopes": ["user:profile"]
            ]
        ]
        if let accountID {
            root["accountId"] = accountID
        }
        if let email {
            root["email"] = email
        }
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func sampleClaudeConfigJSON(email: String) -> String {
        let root: [String: Any] = [
            "user": [
                "email": email
            ],
            "ui": [
                "theme": "dark"
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func sampleInferenceOnlyCredentialsJSON(
        accountID: String,
        email: String,
        accessToken: String
    ) -> String {
        let root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "subscriptionType": "pro",
                "scopes": ["user:inference"]
            ],
            "accountId": accountID,
            "email": email
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
