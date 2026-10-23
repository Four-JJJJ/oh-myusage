import OhMyUsageDomain
import Foundation

struct ClaudeAccountSlot: Codable, Equatable, Identifiable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var accountKey: String
    var displayName: String
    var lastSnapshot: UsageSnapshot
    var lastSeenAt: Date
    var isActive: Bool
}

final class ClaudeAccountSlotStore: @unchecked Sendable {
    private struct SlotFile: Codable {
        var slots: [ClaudeAccountSlot]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let staleInterval: TimeInterval
    /// Official refreshes persist slot state from the main actor every cycle,
    /// so JSON encoding and file IO live on this serial queue; MainActor callers
    /// only mutate in-memory state and enqueue writes.
    private let ioQueue = DispatchQueue(label: "OhMyUsage.claudeSlotStore.io", qos: .utility)
    /// Guards the in-memory slot state (read-modify-write atomicity). Never held
    /// while the IO queue executes a write.
    private let stateLock = NSLock()
    private var slots: [ClaudeAccountSlot]
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
            self.fileURL = directory.appendingPathComponent("claude_slots.json")
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

    func visibleSlots(now: Date = Date()) -> [ClaudeAccountSlot] {
        stateLock.lock()
        removeStaleSlotsLocked(now: now)
        let current = slots
        stateLock.unlock()
        return current.sorted(by: sortRule)
    }

    func remove(slotID: CodexSlotID, now: Date = Date()) -> [ClaudeAccountSlot] {
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

    func upsertActive(snapshot: UsageSnapshot, now: Date = Date()) -> [ClaudeAccountSlot] {
        let accountKey = Self.accountKey(from: snapshot)
        let displayName = Self.accountLabel(from: snapshot)
        let preferredSlotID = Self.explicitSlotID(from: snapshot)

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

        if let existing = slots.firstIndex(where: { $0.accountKey == accountKey }) {
            if let preferredSlotID {
                slots[existing].slotID = preferredSlotID
            }
            slots[existing].displayName = displayName
            slots[existing].lastSnapshot = snapshot
            slots[existing].lastSeenAt = now
            slots[existing].isActive = true
            enqueueSaveLocked()
            return slots.sorted(by: sortRule)
        }

        if accountKey == "unknown",
           let unknown = slots.firstIndex(where: { $0.accountKey == "unknown" }) {
            slots[unknown].displayName = displayName
            slots[unknown].lastSnapshot = snapshot
            slots[unknown].lastSeenAt = now
            slots[unknown].isActive = true
            enqueueSaveLocked()
            return slots.sorted(by: sortRule)
        }

        let occupied = Set(slots.map(\.slotID))
        let slotID = preferredSlotID ?? CodexSlotID.nextAvailable(excluding: occupied)
        slots.append(
            ClaudeAccountSlot(
                slotID: slotID,
                accountKey: accountKey,
                displayName: displayName,
                lastSnapshot: snapshot,
                lastSeenAt: now,
                isActive: true
            )
        )
        enqueueSaveLocked()
        return slots.sorted(by: sortRule)
    }

    func upsertInactive(
        snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        now: Date = Date()
    ) -> [ClaudeAccountSlot] {
        let accountKey = Self.accountKey(from: snapshot)
        let displayName = Self.accountLabel(from: snapshot)
        let resolvedSlotID = preferredSlotID ?? Self.explicitSlotID(from: snapshot)

        stateLock.lock()
        defer { stateLock.unlock() }

        removeStaleSlotsLocked(now: now)

        if let resolvedSlotID,
           let conflicting = slots.firstIndex(where: { $0.slotID == resolvedSlotID && $0.accountKey != accountKey }) {
            slots.remove(at: conflicting)
        }

        if let existing = slots.firstIndex(where: { $0.accountKey == accountKey }) {
            if let resolvedSlotID {
                slots[existing].slotID = resolvedSlotID
            }
            slots[existing].displayName = displayName
            slots[existing].lastSnapshot = snapshot
            slots[existing].lastSeenAt = now
            slots[existing].isActive = false
            enqueueSaveLocked()
            return slots.sorted(by: sortRule)
        }

        if accountKey == "unknown",
           let unknown = slots.firstIndex(where: { $0.accountKey == "unknown" }) {
            slots[unknown].displayName = displayName
            slots[unknown].lastSnapshot = snapshot
            slots[unknown].lastSeenAt = now
            slots[unknown].isActive = false
            enqueueSaveLocked()
            return slots.sorted(by: sortRule)
        }

        let occupied = Set(slots.map(\.slotID))
        let slotID = resolvedSlotID ?? CodexSlotID.nextAvailable(excluding: occupied)
        slots.append(
            ClaudeAccountSlot(
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
        if let explicitKey = snapshot.rawMeta["claude.accountKey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitKey.isEmpty {
            return explicitKey.lowercased()
        }

        if let fingerprint = normalized(snapshot.rawMeta["claude.credentialFingerprint"]) {
            return "fingerprint:\(fingerprint)"
        }

        if let email = normalized(snapshot.accountLabel ?? snapshot.rawMeta["claude.accountLabel"]) {
            return "email:\(email)"
        }

        return "unknown"
    }

    static func explicitSlotID(from snapshot: UsageSnapshot) -> CodexSlotID? {
        guard let rawValue = snapshot.rawMeta["claude.slotID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
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
        if let label = snapshot.rawMeta["claude.accountLabel"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        return "Unknown"
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private func sortRule(lhs: ClaudeAccountSlot, rhs: ClaudeAccountSlot) -> Bool {
        if lhs.isActive != rhs.isActive {
            return lhs.isActive && !rhs.isActive
        }
        if lhs.lastSeenAt != rhs.lastSeenAt {
            return lhs.lastSeenAt > rhs.lastSeenAt
        }
        return lhs.slotID < rhs.slotID
    }

    private func removeStaleSlotsLocked(now: Date) {
        let before = slots.count
        slots.removeAll { now.timeIntervalSince($0.lastSeenAt) > staleInterval }
        if slots.count != before {
            enqueueSaveLocked()
        }
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
            NSLog("[ClaudeAccountSlotStore] Failed to persist slots: \(error.localizedDescription)")
        }
    }

    /// IO-queue confined (cold start).
    private func loadSlotsOnIOQueue() -> [ClaudeAccountSlot] {
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

    private static func encodedData(for slots: [ClaudeAccountSlot]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(SlotFile(slots: slots))
    }
}
