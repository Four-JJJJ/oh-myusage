import OhMyUsageDomain
import Foundation
import XCTest
@testable import OhMyUsage

final class CodexAccountProfileStoreTests: XCTestCase {
    func testSaveProfileParsesCodexMetadata() throws {
        let store = makeStore()
        let profile = try store.saveProfile(
            slotID: .a,
            displayName: "Main",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-1", email: "user@example.com"),
            currentFingerprint: nil
        )

        XCTAssertEqual(profile.displayName, "Main")
        XCTAssertEqual(profile.accountId, "acc-1")
        XCTAssertEqual(profile.accountEmail, "user@example.com")
        XCTAssertEqual(profile.accountSubject, "sub-acc-1")
        XCTAssertEqual(profile.tenantKey, "account:acc-1")
        XCTAssertEqual(profile.identityKey, "tenant:account:acc-1|principal:subject:sub-acc-1")
        XCTAssertNotNil(profile.credentialFingerprint)
    }

    func testSaveProfileRejectsMissingAccessToken() {
        let store = makeStore()
        XCTAssertThrowsError(
            try store.saveProfile(
                slotID: .a,
                displayName: "Broken",
                note: nil,
                authJSON: #"{"tokens":{"refresh_token":"x"}}"#,
                currentFingerprint: nil
            )
        )
    }

    func testNextAvailableSlotIDAdvancesPastImportedProfiles() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-1", email: "a@example.com"),
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: CodexSlotID(rawValue: "C"),
            displayName: "C",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-3", email: "c@example.com"),
            currentFingerprint: nil
        )

        XCTAssertEqual(store.nextAvailableSlotID().rawValue, "B")
    }

    func testCaptureCurrentAuthStoresIntoFirstAvailableAutoSlot() {
        let store = makeStore()

        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .a)
        XCTAssertEqual(profiles.first?.displayName, "Codex A")
        XCTAssertTrue(profiles.first?.isCurrentSystemAccount == true)
    }

    func testCaptureCurrentAuthWithNilInputKeepsSavedProfiles() {
        let store = makeStore()
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )

        let profiles = store.captureCurrentAuthIfNeeded(authJSON: nil)

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.accountId, "acc-auto-a")
        XCTAssertFalse(profiles.first?.isCurrentSystemAccount ?? true)
    }

    func testCaptureCurrentAuthWithInvalidInputKeepsSavedProfiles() {
        let store = makeStore()
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )

        let profiles = store.captureCurrentAuthIfNeeded(authJSON: "not-valid-json")

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.accountId, "acc-auto-a")
        XCTAssertFalse(profiles.first?.isCurrentSystemAccount ?? true)
    }

    func testCaptureCurrentAuthStoresSecondDistinctAccountIntoSlotB() {
        let store = makeStore()

        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-b", email: "auto-b@example.com")
        )

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles.map(\.slotID), [.a, .b])
        XCTAssertEqual(profiles.first(where: { $0.slotID == .b })?.displayName, "Codex B")
        XCTAssertTrue(profiles.first(where: { $0.slotID == .b })?.isCurrentSystemAccount == true)
        XCTAssertFalse(profiles.first(where: { $0.slotID == .a })?.isCurrentSystemAccount == true)
    }

    func testCaptureCurrentAuthKeepsSameEmailDifferentTeamsAsSeparateProfiles() {
        let store = makeStore()
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-a",
                email: "shared@example.com",
                subject: "sub-shared"
            )
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-b",
                email: "shared@example.com",
                subject: "sub-shared"
            )
        )

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(Set(profiles.compactMap(\.accountId)), ["team-a", "team-b"])
    }

    func testCaptureCurrentAuthStoresThirdDistinctAccountIntoSlotC() {
        let store = makeStore()

        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-b", email: "auto-b@example.com")
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-c", email: "auto-c@example.com")
        )

        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(profiles.map(\.slotID.rawValue), ["A", "B", "C"])
        XCTAssertEqual(profiles.first(where: { $0.slotID.rawValue == "C" })?.displayName, "Codex C")
    }

    func testCaptureCurrentAuthUpdatesMatchingSlotWithoutCreatingNewOne() {
        let store = makeStore()
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )

        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "acc-auto-a",
                email: "auto-a@example.com",
                accessToken: "rotated-access-token"
            )
        )

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .a)
        XCTAssertTrue(profiles.first?.authJSON.contains("rotated-access-token") == true)
    }

    func testUpdateStoredAuthJSONUpdatesSlotMetadata() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "team-old", email: "old@example.com"),
            currentFingerprint: nil
        )

        let updated = store.updateStoredAuthJSON(
            slotID: .a,
            authJSON: sampleAuthJSON(
                accountID: "team-new",
                email: "new@example.com",
                subject: "sub-new",
                accessToken: "rotated-token"
            )
        )

        XCTAssertEqual(updated?.slotID, .a)
        XCTAssertEqual(updated?.accountId, "team-new")
        XCTAssertEqual(updated?.accountEmail, "new@example.com")
        XCTAssertEqual(updated?.accountSubject, "sub-new")
        XCTAssertTrue(updated?.authJSON.contains("rotated-token") == true)
    }

    func testCaptureCurrentAuthDoesNotMergeDifferentTeamsEvenWhenFingerprintMatches() {
        let store = makeStore()
        let sharedToken = "same-access-token"
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-a",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-b",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(Set(profiles.compactMap(\.accountId)), ["team-a", "team-b"])
    }

    func testCurrentSystemAccountUsesIdentityWhenFingerprintIsSharedAcrossTeams() {
        let store = makeStore()
        let sharedToken = "same-access-token"
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-a",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-b",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )

        XCTAssertEqual(profiles.filter(\.isCurrentSystemAccount).count, 1)
        XCTAssertEqual(profiles.first(where: \.isCurrentSystemAccount)?.accountId, "team-b")
    }

    func testSnapshotMatchingPrefersTeamScopedIdentityOverFingerprintFallback() {
        let store = makeStore()
        let sharedToken = "same-access-token"
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-a",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(
                accountID: "team-b",
                email: "shared@example.com",
                subject: "sub-shared",
                accessToken: sharedToken
            )
        )
        let snapshot = makeSnapshot(
            accountID: "team-b",
            accountLabel: "shared@example.com",
            subject: "sub-shared",
            fingerprint: try? CodexAccountProfileStore.parseAuthJSON(
                sampleAuthJSON(accountID: "team-a", email: "shared@example.com", subject: "sub-shared", accessToken: sharedToken)
            ).credentialFingerprint
        )

        guard let index = CodexAccountProfileStore.matchingIndex(for: snapshot, in: profiles) else {
            return XCTFail("expected snapshot to match a profile")
        }

        XCTAssertEqual(profiles[index].accountId, "team-b")
    }

    func testRemoveProfileDeletesSlot() {
        let store = makeStore()
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-a", email: "auto-a@example.com")
        )
        _ = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-auto-b", email: "auto-b@example.com")
        )

        let profiles = store.removeProfile(slotID: .a)

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.slotID, .b)
    }

    func testRemoveProfileCanDeleteCurrentSystemAccount() throws {
        let store = makeStore()
        let authJSON = sampleAuthJSON(accountID: "acc-current", email: "current@example.com")
        let fingerprint = try CodexAccountProfileStore.parseAuthJSON(authJSON).credentialFingerprint
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Current",
            note: nil,
            authJSON: authJSON,
            currentFingerprint: fingerprint
        )

        let profiles = store.removeProfile(slotID: .a)

        XCTAssertTrue(profiles.isEmpty)
    }

    func testExplicitSaveMovesMatchingAccountIntoChosenSlotWithoutOverwritingOthers() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Codex A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-a", email: "a@example.com"),
            currentFingerprint: nil
        )
        _ = try store.saveProfile(
            slotID: .b,
            displayName: "Codex B",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-b", email: "b@example.com"),
            currentFingerprint: nil
        )

        _ = try store.saveProfile(
            slotID: CodexSlotID(rawValue: "C"),
            displayName: "Codex C",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-a", email: "a@example.com", accessToken: "rotated-a"),
            currentFingerprint: nil
        )

        let profiles = store.profiles()
        XCTAssertEqual(profiles.map(\.slotID.rawValue), ["B", "C"])
        XCTAssertEqual(profiles.first(where: { $0.slotID.rawValue == "C" })?.accountId, "acc-a")
        XCTAssertEqual(profiles.first(where: { $0.slotID == .b })?.accountId, "acc-b")
    }

    func testSaveProfileWithAccountOnlyPayloadDoesNotOverwriteExistingPrincipalProfile() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Codex A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "team-shared", email: "a@example.com"),
            currentFingerprint: nil
        )

        _ = try store.saveProfile(
            slotID: .b,
            displayName: "Codex B",
            note: nil,
            authJSON: sampleAuthJSONWithoutIDToken(accountID: "team-shared", accessToken: "token-without-principal"),
            currentFingerprint: nil
        )

        let profiles = store.profiles()
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles.map(\.slotID), [.a, .b])
        XCTAssertEqual(profiles.first(where: { $0.slotID == .a })?.accountEmail, "a@example.com")
    }

    func testMatchingProfileByAuthJSONReturnsExistingSlotForSameIdentity() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Codex A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-a", email: "a@example.com"),
            currentFingerprint: nil
        )

        let matched = store.matchingProfile(
            authJSON: sampleAuthJSON(
                accountID: "acc-a",
                email: "a@example.com",
                accessToken: "rotated-a"
            )
        )
        XCTAssertEqual(matched?.slotID, .a)
    }

    func testRemovedCurrentFingerprintIsNotAutoCapturedAgainImmediately() throws {
        let store = makeStore()
        let authJSON = sampleAuthJSON(accountID: "acc-current", email: "current@example.com")
        let fingerprint = try CodexAccountProfileStore.parseAuthJSON(authJSON).credentialFingerprint
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Current",
            note: nil,
            authJSON: authJSON,
            currentFingerprint: fingerprint
        )

        _ = store.removeProfile(slotID: .a)
        let profiles = store.captureCurrentAuthIfNeeded(authJSON: authJSON)

        XCTAssertTrue(profiles.isEmpty)
    }

    func testManualSaveThenFailedSyncThenNewLoginPreservesExistingProfiles() throws {
        let store = makeStore()
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Manual A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-a", email: "a@example.com"),
            currentFingerprint: nil
        )

        _ = store.captureCurrentAuthIfNeeded(authJSON: "not-valid-json")
        let profiles = store.captureCurrentAuthIfNeeded(
            authJSON: sampleAuthJSON(accountID: "acc-b", email: "b@example.com")
        )

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(Set(profiles.compactMap(\.accountId)), ["acc-a", "acc-b"])
        XCTAssertTrue(profiles.first(where: { $0.accountId == "acc-b" })?.isCurrentSystemAccount ?? false)
        XCTAssertFalse(profiles.first(where: { $0.accountId == "acc-a" })?.isCurrentSystemAccount ?? true)
    }

    func testUnchangedReSyncDoesNotRewriteProfileFile() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-profile-tests-\(UUID().uuidString).json")
        let store = CodexAccountProfileStore(fileURL: path)
        let authJSON = sampleAuthJSON(accountID: "acc-steady", email: "steady@example.com")

        _ = store.captureCurrentAuthIfNeeded(authJSON: authJSON)
        store.flushPendingDiskWrites()
        let firstWrite = try fileFingerprint(at: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        // Re-syncing the exact same credential must not touch the file.
        _ = store.captureCurrentAuthIfNeeded(authJSON: authJSON)
        store.flushPendingDiskWrites()
        XCTAssertEqual(try fileFingerprint(at: path), firstWrite)

        // A new store instance seeds its dedupe fingerprint from the on-disk
        // state, so an unchanged no-op commit still skips the disk write.
        let reloaded = CodexAccountProfileStore(fileURL: path)
        _ = reloaded.removeProfile(slotID: CodexSlotID(rawValue: "Z"))
        reloaded.flushPendingDiskWrites()
        XCTAssertEqual(try fileFingerprint(at: path), firstWrite)

        // Changed content must still reach the disk.
        _ = store.updateStoredAuthJSON(
            slotID: .a,
            authJSON: sampleAuthJSON(accountID: "acc-steady", email: "steady@example.com", accessToken: "rotated-token")
        )
        store.flushPendingDiskWrites()
        XCTAssertNotEqual(try fileFingerprint(at: path), firstWrite)
    }

    func testSaveThenReloadRoundTripsThroughDiskAfterFlush() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-profile-tests-\(UUID().uuidString).json")
        let store = CodexAccountProfileStore(fileURL: path)
        _ = try store.saveProfile(
            slotID: .a,
            displayName: "Persisted",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-persist", email: "persist@example.com"),
            currentFingerprint: nil
        )
        store.flushPendingDiskWrites()

        let reloaded = CodexAccountProfileStore(fileURL: path)
        XCTAssertEqual(reloaded.profiles().map(\.slotID), [.a])
        XCTAssertEqual(reloaded.profile(slotID: .a)?.accountId, "acc-persist")
        XCTAssertEqual(reloaded.profile(slotID: .a)?.displayName, "Persisted")
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

    private func makeStore() -> CodexAccountProfileStore {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-profile-tests-\(UUID().uuidString).json")
        return CodexAccountProfileStore(fileURL: path)
    }

    private func sampleAuthJSON(
        accountID: String?,
        email: String,
        subject: String? = nil,
        accessToken: String? = nil
    ) -> String {
        let subjectValue = subject ?? "sub-\(accountID ?? "default")"
        let payload = Data(#"{"email":"\#(email)","sub":"\#(subjectValue)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let accountLine: String
        if let accountID {
            accountLine = #"""
            "account_id": "\#(accountID)",
            """#
        } else {
            accountLine = ""
        }
        let accountSuffix = accountID ?? "default"
        return #"""
        {
          "tokens": {
            "access_token": "\#(accessToken ?? "access-token-\(accountSuffix)")",
            "refresh_token": "refresh-token-\#(accountSuffix)",
            \#(accountLine)
            "id_token": "header.\#(payload).signature"
          }
        }
        """#
    }

    private func sampleAuthJSONWithoutIDToken(
        accountID: String?,
        accessToken: String
    ) -> String {
        let accountLine: String
        if let accountID {
            accountLine = #"""
            "account_id": "\#(accountID)",
            """#
        } else {
            accountLine = ""
        }
        let accountSuffix = accountID ?? "default"
        return #"""
        {
          "tokens": {
            "access_token": "\#(accessToken)",
            "refresh_token": "refresh-token-\#(accountSuffix)",
            \#(accountLine)
            "token_type": "Bearer"
          }
        }
        """#
    }

    private func makeSnapshot(
        accountID: String?,
        accountLabel: String?,
        subject: String?,
        fingerprint: String?
    ) -> UsageSnapshot {
        var rawMeta: [String: String] = [:]
        if let accountID {
            rawMeta["codex.accountId"] = accountID
            rawMeta["codex.teamId"] = accountID
        }
        if let accountLabel {
            rawMeta["codex.accountLabel"] = accountLabel
        }
        if let subject {
            rawMeta["codex.subject"] = subject
        }
        if let fingerprint {
            rawMeta["codex.credentialFingerprint"] = fingerprint
        }

        return UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: 50,
            used: 50,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "",
            quotaWindows: [],
            sourceLabel: "API",
            accountLabel: accountLabel,
            extras: [:],
            rawMeta: rawMeta
        )
    }
}
