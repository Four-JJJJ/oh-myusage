import OhMyUsageDomain
import Foundation

struct CodexSlotID: RawRepresentable, Codable, Hashable, Comparable, Identifiable {
    var rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = trimmed.isEmpty ? "A" : trimmed.uppercased()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let a = CodexSlotID(rawValue: "A")
    static let b = CodexSlotID(rawValue: "B")

    static func generated(index: Int) -> CodexSlotID {
        CodexSlotID(rawValue: excelColumnName(for: index))
    }

    static func nextAvailable(excluding existing: Set<CodexSlotID>) -> CodexSlotID {
        var index = 0
        while true {
            let candidate = CodexSlotID.generated(index: index)
            if !existing.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    static func < (lhs: CodexSlotID, rhs: CodexSlotID) -> Bool {
        let left = sortComponents(for: lhs.rawValue)
        let right = sortComponents(for: rhs.rawValue)
        if left.numeric != right.numeric {
            return left.numeric < right.numeric
        }
        return left.raw < right.raw
    }

    private static func sortComponents(for rawValue: String) -> (numeric: Int, raw: String) {
        let normalized = rawValue.uppercased()
        if let excelIndex = excelColumnIndex(for: normalized) {
            return (excelIndex, normalized)
        }
        if let numeric = Int(normalized) {
            return (numeric, normalized)
        }
        return (Int.max, normalized)
    }

    private static func excelColumnName(for index: Int) -> String {
        var value = max(0, index)
        var result = ""
        repeat {
            let remainder = value % 26
            let scalar = UnicodeScalar(65 + remainder)!
            result = String(Character(scalar)) + result
            value = (value / 26) - 1
        } while value >= 0
        return result
    }

    private static func excelColumnIndex(for rawValue: String) -> Int? {
        guard rawValue.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return nil }
        var result = 0
        for character in rawValue {
            guard let scalar = character.unicodeScalars.first else { return nil }
            result = result * 26 + Int(scalar.value) - 64
        }
        return result - 1
    }
}

struct CodexAccountSlot: Codable, Equatable, Identifiable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var accountKey: String
    var displayName: String
    var lastSnapshot: UsageSnapshot
    var lastSeenAt: Date
    var isActive: Bool
}

final class CodexAccountSlotStore: @unchecked Sendable {
    private static let codexSessionWindowDuration: TimeInterval = 5 * 60 * 60
    private static let codexSessionWindowTolerance: TimeInterval = 90
    private static let codexWindowPercentEpsilon: Double = 0.001

    private struct SlotFile: Codable {
        var slots: [CodexAccountSlot]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let staleInterval: TimeInterval
    /// Official refreshes persist slot state from the main actor every cycle,
    /// so JSON encoding and file IO live on this serial queue; MainActor callers
    /// only mutate in-memory state and enqueue writes.
    private let ioQueue = DispatchQueue(label: "OhMyUsage.codexSlotStore.io", qos: .utility)
    /// Guards the in-memory slot state (read-modify-write atomicity). Never held
    /// while the IO queue executes a write.
    private let stateLock = NSLock()
    private var slots: [CodexAccountSlot]
    /// IO-queue confined: the last payload successfully written to disk. Saves
    /// whose encoded content matches it are skipped entirely.
    private var lastWrittenData: Data?

    init(
        fileManager: FileManager = .default,
        staleInterval: TimeInterval = 7 * 24 * 60 * 60,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("OhMyUsage", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("codex_slots.json")
        }
        self.staleInterval = staleInterval
        self.slots = []
        // One-time cold-start read, serialized on the IO queue so every disk
        // access for this store is queue-confined. The loaded state also seeds
        // the dedupe fingerprint so a no-op first save never rewrites the file.
        ioQueue.sync {
            self.slots = self.loadSlotsOnIOQueue()
            self.lastWrittenData = Self.encodedData(for: self.slots)
        }
    }

    func reset() {
        stateLock.lock()
        slots = []
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.fileURL)
            self.lastWrittenData = nil
        }
        stateLock.unlock()
    }

    /// Order fence for save-then-load semantics across store instances: blocks
    /// until every enqueued write/removal has completed on the IO queue.
    func flushPendingDiskWrites() {
        ioQueue.sync {}
    }

    func visibleSlots(now: Date = Date()) -> [CodexAccountSlot] {
        stateLock.lock()
        removeStaleSlotsLocked(now: now)
        let current = slots
        stateLock.unlock()
        return current.sorted(by: sortRule)
    }

    func remove(slotID: CodexSlotID, now: Date = Date()) -> [CodexAccountSlot] {
        stateLock.lock()
        removeStaleSlotsLocked(now: now)
        let originalCount = slots.count
        slots.removeAll { $0.slotID == slotID }
        if slots.count != originalCount {
            enqueueSaveLocked()
        }
        let current = slots
        stateLock.unlock()
        return current.sorted(by: sortRule)
    }

    func upsertActive(
        snapshot: UsageSnapshot,
        now: Date = Date(),
        allowSessionWindowStabilization: Bool = false
    ) -> [CodexAccountSlot] {
        let accountKey = Self.accountKey(from: snapshot)
        let displayName = Self.accountLabel(from: snapshot)
        let preferredSlotID = Self.explicitSlotID(from: snapshot)
        let legacyKeys = Self.legacyAccountKeys(from: snapshot)

        stateLock.lock()
        defer { stateLock.unlock() }

        removeStaleSlotsLocked(now: now)

        for index in slots.indices {
            slots[index].isActive = false
        }

        if let preferredSlotID,
           let conflicting = slots.firstIndex(where: { $0.slotID == preferredSlotID && $0.accountKey != accountKey }) {
            slots.remove(at: conflicting)
        }

        if accountKey != "unknown",
           let legacy = slots.firstIndex(where: {
               Self.isLegacyAccountKey($0.accountKey) && legacyKeys.contains($0.accountKey.lowercased())
           }) {
            slots[legacy].accountKey = accountKey
        }

        if let existing = slots.firstIndex(where: { $0.accountKey == accountKey }) {
            let stabilizedSnapshot = Self.maybeStabilizeCodexSessionWindow(
                incoming: snapshot,
                previous: slots[existing].lastSnapshot,
                now: now,
                allowSessionWindowStabilization: allowSessionWindowStabilization
            )
            if let preferredSlotID {
                slots[existing].slotID = preferredSlotID
            }
            slots[existing].displayName = displayName
            slots[existing].lastSnapshot = stabilizedSnapshot
            slots[existing].lastSeenAt = now
            slots[existing].isActive = true
            enqueueSaveLocked()
            return slots.sorted(by: sortRule)
        }

        // Unknown identity should stay single-slot to avoid fake account splits.
        if accountKey == "unknown", let unknownIndex = slots.firstIndex(where: { $0.accountKey == "unknown" }) {
            let stabilizedSnapshot = Self.maybeStabilizeCodexSessionWindow(
                incoming: snapshot,
                previous: slots[unknownIndex].lastSnapshot,
                now: now,
                allowSessionWindowStabilization: allowSessionWindowStabilization
            )
            slots[unknownIndex].displayName = displayName
            slots[unknownIndex].lastSnapshot = stabilizedSnapshot
            slots[unknownIndex].lastSeenAt = now
            slots[unknownIndex].isActive = true
            enqueueSaveLocked()
            return slots.sorted(by: sortRule)
        }

        let occupied = Set(slots.map(\.slotID))
        let slotID = preferredSlotID ?? CodexSlotID.nextAvailable(excluding: occupied)

        let slot = CodexAccountSlot(
            slotID: slotID,
            accountKey: accountKey,
            displayName: displayName,
            lastSnapshot: snapshot,
            lastSeenAt: now,
            isActive: true
        )
        slots.append(slot)
        enqueueSaveLocked()
        return slots.sorted(by: sortRule)
    }

    func upsertInactive(
        snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        now: Date = Date(),
        allowSessionWindowStabilization: Bool = true
    ) -> [CodexAccountSlot] {
        let accountKey = Self.accountKey(from: snapshot)
        let displayName = Self.accountLabel(from: snapshot)
        let resolvedSlotID = preferredSlotID ?? Self.explicitSlotID(from: snapshot)
        let legacyKeys = Self.legacyAccountKeys(from: snapshot)

        stateLock.lock()
        defer { stateLock.unlock() }

        removeStaleSlotsLocked(now: now)

        if let resolvedSlotID,
           let conflicting = slots.firstIndex(where: { $0.slotID == resolvedSlotID && $0.accountKey != accountKey }) {
            slots.remove(at: conflicting)
        }

        if accountKey != "unknown",
           let legacy = slots.firstIndex(where: {
               Self.isLegacyAccountKey($0.accountKey) && legacyKeys.contains($0.accountKey.lowercased())
           }) {
            slots[legacy].accountKey = accountKey
        }

        if let existing = slots.firstIndex(where: { $0.accountKey == accountKey }) {
            let stabilizedSnapshot = Self.maybeStabilizeCodexSessionWindow(
                incoming: snapshot,
                previous: slots[existing].lastSnapshot,
                now: now,
                allowSessionWindowStabilization: allowSessionWindowStabilization
            )
            if let resolvedSlotID {
                slots[existing].slotID = resolvedSlotID
            }
            slots[existing].displayName = displayName
            slots[existing].lastSnapshot = stabilizedSnapshot
            slots[existing].lastSeenAt = now
            slots[existing].isActive = false
            enqueueSaveLocked()
            return slots.sorted(by: sortRule)
        }

        if accountKey == "unknown", let unknownIndex = slots.firstIndex(where: { $0.accountKey == "unknown" }) {
            let stabilizedSnapshot = Self.maybeStabilizeCodexSessionWindow(
                incoming: snapshot,
                previous: slots[unknownIndex].lastSnapshot,
                now: now,
                allowSessionWindowStabilization: allowSessionWindowStabilization
            )
            slots[unknownIndex].displayName = displayName
            slots[unknownIndex].lastSnapshot = stabilizedSnapshot
            slots[unknownIndex].lastSeenAt = now
            slots[unknownIndex].isActive = false
            enqueueSaveLocked()
            return slots.sorted(by: sortRule)
        }

        let occupied = Set(slots.map(\.slotID))
        let slotID = resolvedSlotID ?? CodexSlotID.nextAvailable(excluding: occupied)
        slots.append(
            CodexAccountSlot(
                slotID: slotID,
                accountKey: accountKey,
                displayName: displayName,
                lastSnapshot: snapshot,
                lastSeenAt: now,
                isActive: false
            )
        )
        enqueueSaveLocked()
        return slots.sorted(by: sortRule)
    }

    static func accountKey(from snapshot: UsageSnapshot) -> String {
        if let explicitKey = snapshot.rawMeta["codex.accountKey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitKey.isEmpty {
            return explicitKey.lowercased()
        }

        if let identityKey = CodexIdentity.normalizedIdentityKey(snapshot.rawMeta["codex.identityKey"]) {
            return identityKey
        }

        return CodexIdentity.from(snapshot: snapshot).identityKey
    }

    static func explicitSlotID(from snapshot: UsageSnapshot) -> CodexSlotID? {
        guard let rawValue = snapshot.rawMeta["codex.slotID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return CodexSlotID(rawValue: rawValue)
    }

    static func accountLabel(from snapshot: UsageSnapshot) -> String {
        if let label = snapshot.accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        if let label = snapshot.rawMeta["codex.accountLabel"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        return "Unknown"
    }

    private func sortRule(lhs: CodexAccountSlot, rhs: CodexAccountSlot) -> Bool {
        if lhs.isActive != rhs.isActive {
            return lhs.isActive && !rhs.isActive
        }
        if lhs.lastSeenAt != rhs.lastSeenAt {
            return lhs.lastSeenAt > rhs.lastSeenAt
        }
        return lhs.slotID < rhs.slotID
    }

    /// Must be called with `stateLock` held so the enqueue order always matches
    /// the mutation order. Encoding and the disk write happen on the IO queue.
    private func enqueueSaveLocked() {
        let snapshot = slots
        ioQueue.async { [weak self] in
            self?.writeIfNeeded(Self.encodedData(for: snapshot))
        }
    }

    /// IO-queue confined. Skips the write when the payload matches the last
    /// successfully persisted one, so refresh cycles with unchanged slot state
    /// never touch the disk.
    private func writeIfNeeded(_ data: Data?) {
        guard let data, data != lastWrittenData else { return }
        do {
            // Slot files persist full snapshots including account metadata, so
            // they are written with the same 0600 staging write as the profiles.
            try PrivateProfileFile(url: fileURL, fileManager: fileManager).write(data)
            lastWrittenData = data
        } catch {
            NSLog("[CodexAccountSlotStore] Failed to persist slots: \(error.localizedDescription)")
        }
    }

    /// IO-queue confined (cold start).
    private func loadSlotsOnIOQueue() -> [CodexAccountSlot] {
        let dir = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(SlotFile.self, from: data) {
            return decoded.slots
        }
        return []
    }

    private static func encodedData(for slots: [CodexAccountSlot]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(SlotFile(slots: slots))
    }

    private func removeStaleSlotsLocked(now: Date) {
        let before = slots.count
        slots.removeAll { now.timeIntervalSince($0.lastSeenAt) > staleInterval }
        if slots.count != before {
            enqueueSaveLocked()
        }
    }

    static func legacyAccountKeys(from snapshot: UsageSnapshot) -> Set<String> {
        var keys: Set<String> = []
        if let accountID = CodexIdentity.normalizedAccountID(CodexIdentity.teamID(from: snapshot)) {
            keys.insert("account:\(accountID)")
        }
        if let fingerprint = CodexIdentity.normalizedFingerprint(snapshot.rawMeta["codex.credentialFingerprint"]) {
            keys.insert("fingerprint:\(fingerprint)")
        }
        if let subject = CodexIdentity.normalizedSubject(snapshot.rawMeta["codex.subject"]) {
            keys.insert("subject:\(subject)")
        }
        if let email = CodexIdentity.normalizedEmail(snapshot.accountLabel ?? snapshot.rawMeta["codex.accountLabel"]) {
            keys.insert("email:\(email)")
        }
        if keys.isEmpty {
            keys.insert("unknown")
        }
        return keys
    }

    static func isLegacyAccountKey(_ accountKey: String) -> Bool {
        let key = accountKey.lowercased()
        return key == "unknown"
            || key.hasPrefix("account:")
            || key.hasPrefix("subject:")
            || key.hasPrefix("fingerprint:")
            || key.hasPrefix("email:")
    }

    private static func maybeStabilizeCodexSessionWindow(
        incoming: UsageSnapshot,
        previous: UsageSnapshot,
        now: Date,
        allowSessionWindowStabilization: Bool
    ) -> UsageSnapshot {
        guard allowSessionWindowStabilization else {
            return incoming
        }
        return stabilizeCodexSessionWindowIfNeeded(
            incoming: incoming,
            previous: previous,
            now: now
        )
    }

    private static func stabilizeCodexSessionWindowIfNeeded(
        incoming: UsageSnapshot,
        previous: UsageSnapshot,
        now: Date
    ) -> UsageSnapshot {
        guard isCodexSnapshot(incoming), isCodexSnapshot(previous) else {
            return incoming
        }
        guard let incomingSessionIndex = incoming.quotaWindows.firstIndex(where: { $0.kind == .session }),
              let previousSession = previous.quotaWindows.first(where: { $0.kind == .session }),
              let incomingResetAt = incoming.quotaWindows[incomingSessionIndex].resetAt,
              let previousResetAt = previousSession.resetAt else {
            return incoming
        }

        let incomingSession = incoming.quotaWindows[incomingSessionIndex]
        guard incomingSession.usedPercent <= codexWindowPercentEpsilon,
              incomingSession.remainingPercent >= (100 - codexWindowPercentEpsilon) else {
            return incoming
        }

        let expectedFullWindowResetAt = now.addingTimeInterval(codexSessionWindowDuration)
        guard abs(incomingResetAt.timeIntervalSince(expectedFullWindowResetAt)) <= codexSessionWindowTolerance else {
            return incoming
        }
        guard previousResetAt > now else {
            return incoming
        }
        guard incomingResetAt.timeIntervalSince(previousResetAt) > codexSessionWindowTolerance else {
            return incoming
        }

        var stabilized = incoming
        stabilized.quotaWindows[incomingSessionIndex].remainingPercent = previousSession.remainingPercent
        stabilized.quotaWindows[incomingSessionIndex].usedPercent = previousSession.usedPercent
        stabilized.quotaWindows[incomingSessionIndex].resetAt = previousResetAt
        stabilized.quotaWindows[incomingSessionIndex].resetSource = .localEstimate
        stabilized.quotaWindows[incomingSessionIndex].confidence = .estimated
        stabilized.quotaWindows[incomingSessionIndex].observedAt = now
        stabilized.quotaWindows[incomingSessionIndex].windowIdentity = previousSession.windowIdentity
            ?? UsageQuotaWindow.defaultWindowIdentity(for: stabilized.quotaWindows[incomingSessionIndex])
        stabilized.remaining = stabilized.quotaWindows.map(\.remainingPercent).min()
        if let sessionWindow = stabilized.quotaWindows.first(where: { $0.kind == .session }) {
            stabilized.used = sessionWindow.usedPercent
        }
        stabilized.rawMeta["codex.sessionWindowStabilized"] = "true"
        return stabilized
    }

    private static func isCodexSnapshot(_ snapshot: UsageSnapshot) -> Bool {
        if snapshot.source == "codex-official" {
            return true
        }
        if snapshot.source.hasPrefix("codex-placeholder-") {
            return true
        }
        if snapshot.rawMeta.keys.contains(where: { $0.hasPrefix("codex.") }) {
            return true
        }
        return snapshot.quotaWindows.contains(where: { $0.kind == .session && $0.title == "5h" })
    }
}
