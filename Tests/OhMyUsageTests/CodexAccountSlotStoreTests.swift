import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class CodexAccountSlotStoreTests: XCTestCase {
    func testAccountKeyPriority() {
        var snapshot = makeSnapshot(accountID: "acc-1", accountLabel: "a@test.com", subject: "sub-1")
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "tenant:account:acc-1|principal:subject:sub-1")

        snapshot = makeSnapshot(accountID: nil, accountLabel: "a@test.com", subject: "sub-1", fingerprint: "abc12345")
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "tenant:default|principal:subject:sub-1")

        snapshot = makeSnapshot(accountID: nil, accountLabel: "a@test.com", subject: "sub-1")
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "tenant:default|principal:subject:sub-1")

        snapshot = makeSnapshot(accountID: nil, accountLabel: nil, subject: "sub-1")
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "tenant:default|principal:subject:sub-1")

        snapshot = makeSnapshot(accountID: nil, accountLabel: nil, subject: nil, fingerprint: "abc12345")
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "tenant:default|principal:fingerprint:abc12345")

        snapshot = makeSnapshot(accountID: nil, accountLabel: "a@test.com", subject: nil, fingerprint: nil)
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "tenant:default|principal:email:a@test.com")

        snapshot = makeSnapshot(accountID: nil, accountLabel: nil, subject: nil)
        XCTAssertEqual(CodexAccountSlotStore.accountKey(from: snapshot), "unknown")
    }

    func testNewAccountsKeepGrowingIntoAdditionalSlots() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 1_000)

        _ = store.upsertActive(snapshot: makeSnapshot(accountID: "a"), now: base)
        _ = store.upsertActive(snapshot: makeSnapshot(accountID: "b"), now: base.addingTimeInterval(10))
        let slots = store.upsertActive(snapshot: makeSnapshot(accountID: "c"), now: base.addingTimeInterval(20))

        XCTAssertEqual(slots.count, 3)
        let keys = Set(slots.map(\.accountKey))
        XCTAssertTrue(keys.contains("tenant:account:a|principal:unknown"))
        XCTAssertTrue(keys.contains("tenant:account:b|principal:unknown"))
        XCTAssertTrue(keys.contains("tenant:account:c|principal:unknown"))
        XCTAssertEqual(Set(slots.map(\.slotID.rawValue)), ["A", "B", "C"])
    }

    func testSwitchKeepsInactiveSlotSnapshotForCountdown() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 2_000)

        let aSnap = makeSnapshot(accountID: "a", sessionReset: base.addingTimeInterval(1_800))
        _ = store.upsertActive(snapshot: aSnap, now: base)
        let bSnap = makeSnapshot(accountID: "b", sessionReset: base.addingTimeInterval(3_600))
        let slots = store.upsertActive(snapshot: bSnap, now: base.addingTimeInterval(60))

        XCTAssertEqual(slots.count, 2)
        let inactive = slots.first(where: { $0.accountKey == "tenant:account:a|principal:unknown" })
        XCTAssertNotNil(inactive)
        XCTAssertEqual(inactive?.isActive, false)
        XCTAssertEqual(inactive?.lastSnapshot.quotaWindows.first?.resetAt, aSnap.quotaWindows.first?.resetAt)
    }

    func testUnknownIdentityUsesSingleSlot() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 3_000)

        _ = store.upsertActive(snapshot: makeSnapshot(accountID: nil, accountLabel: nil, subject: nil), now: base)
        let slots = store.upsertActive(snapshot: makeSnapshot(accountID: nil, accountLabel: nil, subject: nil), now: base.addingTimeInterval(10))
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.accountKey, "unknown")
    }

    func testFingerprintIdentityKeepsSeparateSlotsWithoutAccountMetadata() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 3_500)

        _ = store.upsertActive(
            snapshot: makeSnapshot(accountID: nil, accountLabel: nil, subject: nil, fingerprint: "finger-a", sessionReset: base.addingTimeInterval(1_800)),
            now: base
        )
        let slots = store.upsertActive(
            snapshot: makeSnapshot(accountID: nil, accountLabel: nil, subject: nil, fingerprint: "finger-b", sessionReset: base.addingTimeInterval(3_600)),
            now: base.addingTimeInterval(30)
        )

        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(
            Set(slots.map(\.accountKey)),
            ["tenant:default|principal:fingerprint:finger-a", "tenant:default|principal:fingerprint:finger-b"]
        )
        let inactive = slots.first(where: { $0.accountKey == "tenant:default|principal:fingerprint:finger-a" })
        XCTAssertEqual(inactive?.lastSnapshot.quotaWindows.first?.resetAt, base.addingTimeInterval(1_800))
    }

    func testEmailIdentityMergesFingerprintRotation() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 3_800)

        _ = store.upsertActive(
            snapshot: makeSnapshot(
                accountID: nil,
                accountLabel: "shared@example.com",
                subject: nil,
                fingerprint: "finger-a",
                sessionReset: base.addingTimeInterval(1_200)
            ),
            now: base
        )
        let slots = store.upsertActive(
            snapshot: makeSnapshot(
                accountID: nil,
                accountLabel: "shared@example.com",
                subject: nil,
                fingerprint: "finger-b",
                sessionReset: base.addingTimeInterval(3_600)
            ),
            now: base.addingTimeInterval(45)
        )

        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.accountKey, "tenant:default|principal:email:shared@example.com")
        XCTAssertEqual(slots.first?.lastSnapshot.quotaWindows.first?.resetAt, base.addingTimeInterval(3_600))
    }

    func testExplicitSlotIDIsHonoredForImportedProfiles() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 3_900)

        var snapshot = makeSnapshot(accountID: "acc-42", sessionReset: base.addingTimeInterval(900))
        snapshot.rawMeta["codex.slotID"] = "D"

        let slots = store.upsertActive(snapshot: snapshot, now: base)

        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.slotID.rawValue, "D")
    }

    func testStaleSlotsAreHidden() throws {
        let store = makeStore(staleInterval: 100)
        let now = Date(timeIntervalSince1970: 4_000)
        _ = store.upsertActive(snapshot: makeSnapshot(accountID: "a"), now: now.addingTimeInterval(-500))

        let visible = store.visibleSlots(now: now)
        XCTAssertTrue(visible.isEmpty)
    }

    func testUpsertInactivePreservesExistingSessionCountdownWhenResponseResetsToFreshFiveHours() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 5_000)
        let accountID = "acc-stabilize"

        let previousSnapshot = makeSnapshot(
            accountID: accountID,
            sessionRemaining: 42,
            sessionUsed: 58,
            sessionReset: base.addingTimeInterval(1_800)
        )
        _ = store.upsertInactive(snapshot: previousSnapshot, now: base)

        let incomingSnapshot = makeSnapshot(
            accountID: accountID,
            sessionRemaining: 100,
            sessionUsed: 0,
            sessionReset: base.addingTimeInterval(30 + 5 * 60 * 60)
        )
        let slots = store.upsertInactive(snapshot: incomingSnapshot, now: base.addingTimeInterval(30))

        XCTAssertEqual(slots.count, 1)
        let sessionWindow = try XCTUnwrap(slots[0].lastSnapshot.quotaWindows.first(where: { $0.kind == .session }))
        XCTAssertEqual(sessionWindow.remainingPercent, 42, accuracy: 0.0001)
        XCTAssertEqual(sessionWindow.usedPercent, 58, accuracy: 0.0001)
        XCTAssertEqual(sessionWindow.resetAt, previousSnapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        XCTAssertEqual(slots[0].lastSnapshot.rawMeta["codex.sessionWindowStabilized"], "true")
    }

    func testUpsertActiveTrustsFreshSessionResetEvenBeforePreviousCountdownEnds() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 5_200)
        let accountID = "acc-active-reset"

        let previousSnapshot = makeSnapshot(
            accountID: accountID,
            sessionRemaining: 42,
            sessionUsed: 58,
            sessionReset: base.addingTimeInterval(1_800)
        )
        _ = store.upsertActive(snapshot: previousSnapshot, now: base)

        let incomingSnapshot = makeSnapshot(
            accountID: accountID,
            sessionRemaining: 100,
            sessionUsed: 0,
            sessionReset: base.addingTimeInterval(30 + 5 * 60 * 60)
        )
        let slots = store.upsertActive(snapshot: incomingSnapshot, now: base.addingTimeInterval(30))

        XCTAssertEqual(slots.count, 1)
        let sessionWindow = try XCTUnwrap(slots[0].lastSnapshot.quotaWindows.first(where: { $0.kind == .session }))
        XCTAssertEqual(sessionWindow.remainingPercent, 100, accuracy: 0.0001)
        XCTAssertEqual(sessionWindow.usedPercent, 0, accuracy: 0.0001)
        XCTAssertEqual(sessionWindow.resetAt, incomingSnapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        XCTAssertNil(slots[0].lastSnapshot.rawMeta["codex.sessionWindowStabilized"])
    }

    func testUpsertInactiveCanBypassSessionCountdownStabilization() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 5_350)
        let accountID = "acc-manual-refresh"

        let previousSnapshot = makeSnapshot(
            accountID: accountID,
            sessionRemaining: 15,
            sessionUsed: 85,
            sessionReset: base.addingTimeInterval(2_700)
        )
        _ = store.upsertInactive(snapshot: previousSnapshot, now: base)

        let incomingSnapshot = makeSnapshot(
            accountID: accountID,
            sessionRemaining: 100,
            sessionUsed: 0,
            sessionReset: base.addingTimeInterval(45 + 5 * 60 * 60)
        )
        let slots = store.upsertInactive(
            snapshot: incomingSnapshot,
            now: base.addingTimeInterval(45),
            allowSessionWindowStabilization: false
        )

        XCTAssertEqual(slots.count, 1)
        let sessionWindow = try XCTUnwrap(slots[0].lastSnapshot.quotaWindows.first(where: { $0.kind == .session }))
        XCTAssertEqual(sessionWindow.remainingPercent, 100, accuracy: 0.0001)
        XCTAssertEqual(sessionWindow.usedPercent, 0, accuracy: 0.0001)
        XCTAssertEqual(sessionWindow.resetAt, incomingSnapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        XCTAssertNil(slots[0].lastSnapshot.rawMeta["codex.sessionWindowStabilized"])
    }

    func testUpsertInactiveAcceptsNewSessionCountdownAfterPreviousWindowExpires() throws {
        let store = makeStore(staleInterval: 10_000)
        let base = Date(timeIntervalSince1970: 5_500)
        let accountID = "acc-expired"

        let previousSnapshot = makeSnapshot(
            accountID: accountID,
            sessionRemaining: 20,
            sessionUsed: 80,
            sessionReset: base.addingTimeInterval(20)
        )
        _ = store.upsertInactive(snapshot: previousSnapshot, now: base)

        let incomingSnapshot = makeSnapshot(
            accountID: accountID,
            sessionRemaining: 100,
            sessionUsed: 0,
            sessionReset: base.addingTimeInterval(60 + 5 * 60 * 60)
        )
        let slots = store.upsertInactive(snapshot: incomingSnapshot, now: base.addingTimeInterval(60))

        XCTAssertEqual(slots.count, 1)
        let sessionWindow = try XCTUnwrap(slots[0].lastSnapshot.quotaWindows.first(where: { $0.kind == .session }))
        XCTAssertEqual(sessionWindow.remainingPercent, 100, accuracy: 0.0001)
        XCTAssertEqual(sessionWindow.usedPercent, 0, accuracy: 0.0001)
        XCTAssertEqual(sessionWindow.resetAt, incomingSnapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        XCTAssertNil(slots[0].lastSnapshot.rawMeta["codex.sessionWindowStabilized"])
    }

    func testIdenticalConsecutiveSavesSkipTheSecondDiskWrite() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-slot-tests-\(UUID().uuidString).json")
        let store = CodexAccountSlotStore(staleInterval: 10_000, fileURL: path)
        let now = Date(timeIntervalSince1970: 6_000)
        let snapshot = makeSnapshot(accountID: "dedupe")

        _ = store.upsertActive(snapshot: snapshot, now: now)
        store.flushPendingDiskWrites()
        let firstWrite = try fileFingerprint(at: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        // Same snapshot + same timestamp ⇒ identical encoded payload; the
        // store must skip the second disk write (inode + mtime untouched).
        _ = store.upsertActive(snapshot: snapshot, now: now)
        store.flushPendingDiskWrites()
        XCTAssertEqual(try fileFingerprint(at: path), firstWrite)

        // Changed content must still reach the disk.
        _ = store.upsertActive(snapshot: makeSnapshot(accountID: "dedupe-2"), now: now)
        store.flushPendingDiskWrites()
        XCTAssertNotEqual(try fileFingerprint(at: path), firstWrite)
    }

    func testSaveThenReloadRoundTripsThroughDiskAfterFlush() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-slot-tests-\(UUID().uuidString).json")
        let store = CodexAccountSlotStore(staleInterval: 10_000, fileURL: path)
        let now = Date(timeIntervalSince1970: 6_100)
        let snapshot = makeSnapshot(accountID: "persist-me")

        _ = store.upsertActive(snapshot: snapshot, now: now)
        store.flushPendingDiskWrites()

        let reloaded = CodexAccountSlotStore(staleInterval: 10_000, fileURL: path)
        XCTAssertEqual(reloaded.visibleSlots(now: now).count, 1)
        XCTAssertEqual(
            reloaded.visibleSlots(now: now).first?.accountKey,
            store.visibleSlots(now: now).first?.accountKey
        )
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

    private func makeStore(staleInterval: TimeInterval) -> CodexAccountSlotStore {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-slot-tests-\(UUID().uuidString).json")
        return CodexAccountSlotStore(staleInterval: staleInterval, fileURL: path)
    }

    private func makeSnapshot(
        accountID: String?,
        accountLabel: String? = nil,
        subject: String? = nil,
        fingerprint: String? = nil,
        sessionRemaining: Double = 30,
        sessionUsed: Double = 70,
        sessionReset: Date? = nil
    ) -> UsageSnapshot {
        var rawMeta: [String: String] = [:]
        if let accountID { rawMeta["codex.accountId"] = accountID }
        if let subject { rawMeta["codex.subject"] = subject }
        if let accountLabel { rawMeta["codex.accountLabel"] = accountLabel }
        if let fingerprint { rawMeta["codex.credentialFingerprint"] = fingerprint }

        return UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: min(sessionRemaining, 60),
            used: sessionUsed,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: sessionRemaining,
                    usedPercent: sessionUsed,
                    resetAt: sessionReset,
                    kind: .session
                ),
                UsageQuotaWindow(
                    id: "weekly",
                    title: "Weekly",
                    remainingPercent: 60,
                    usedPercent: 40,
                    resetAt: sessionReset?.addingTimeInterval(86_400),
                    kind: .weekly
                ),
            ],
            sourceLabel: "API",
            accountLabel: accountLabel,
            extras: [:],
            rawMeta: rawMeta
        )
    }
}
