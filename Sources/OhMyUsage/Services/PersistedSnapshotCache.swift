import CryptoKit
import Foundation
import OhMyUsageDomain

/// Whitelisted, credential-free projection of a `UsageSnapshot` that is safe to
/// persist to disk (optimization doc §8.1).
///
/// The struct intentionally mirrors only quota / balance / window fields,
/// freshness + health metadata, and source labels. `UsageSnapshot` itself is
/// never serialized wholesale so future fields (extras, rawMeta, notes, …)
/// cannot leak credential material into the cache file. Never add token-like,
/// cookie-like, OAuth-JSON-like, or raw-log fields here.
struct PersistedSnapshotCachePayload: Codable, Equatable, Sendable {
    var source: String
    var status: SnapshotStatus
    var fetchHealth: FetchHealth
    var valueFreshness: ValueFreshness
    var remaining: Double?
    var used: Double?
    var limit: Double?
    var unit: String
    var updatedAt: Date
    var sourceLabel: String
    var accountLabel: String?
    var authSourceLabel: String?
    var diagnosticCode: String?
    var quotaWindows: [PersistedSnapshotQuotaWindow]
}

/// Explicit whitelist of `UsageQuotaWindow` fields (quota/reset metadata only).
struct PersistedSnapshotQuotaWindow: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var remainingPercent: Double
    var usedPercent: Double
    var resetAt: Date?
    var kind: UsageQuotaKind
    var resetSource: UsageQuotaResetSource
    var observedAt: Date?
    var serverClockSkew: TimeInterval?
    var confidence: UsageQuotaResetConfidence
    var windowIdentity: String?
}

/// One persisted main snapshot. The cache key is `providerID + accountFingerprint`,
/// so each provider/account combination keeps at most one entry.
struct PersistedSnapshotCacheEntry: Codable, Equatable, Sendable {
    var providerID: String
    var accountFingerprint: String
    var savedAt: Date
    var payload: PersistedSnapshotCachePayload

    init(providerID: String, accountFingerprint: String, savedAt: Date, payload: PersistedSnapshotCachePayload) {
        self.providerID = providerID
        self.accountFingerprint = accountFingerprint
        self.savedAt = savedAt
        self.payload = payload
    }

    /// Builds the whitelisted payload from a live snapshot. Credential-bearing
    /// fields (extras, rawMeta, note) are deliberately dropped here.
    init(providerID: String, snapshot: UsageSnapshot, savedAt: Date) {
        self.init(
            providerID: providerID,
            accountFingerprint: PersistedSnapshotCache.accountFingerprint(for: snapshot),
            savedAt: savedAt,
            payload: PersistedSnapshotCachePayload(
                source: snapshot.source,
                status: snapshot.status,
                fetchHealth: snapshot.fetchHealth,
                valueFreshness: snapshot.valueFreshness,
                remaining: snapshot.remaining,
                used: snapshot.used,
                limit: snapshot.limit,
                unit: snapshot.unit,
                updatedAt: snapshot.updatedAt,
                sourceLabel: snapshot.sourceLabel,
                accountLabel: snapshot.accountLabel,
                authSourceLabel: snapshot.authSourceLabel,
                diagnosticCode: snapshot.diagnosticCode,
                quotaWindows: snapshot.quotaWindows.map(PersistedSnapshotQuotaWindow.init)
            )
        )
    }

    /// Rebuilds a displayable snapshot. Restored values are always marked as
    /// `.cachedFallback` so the UI can distinguish them from live data.
    var restoredSnapshot: UsageSnapshot {
        UsageSnapshot(
            source: payload.source,
            status: payload.status,
            fetchHealth: payload.fetchHealth,
            valueFreshness: .cachedFallback,
            remaining: payload.remaining,
            used: payload.used,
            limit: payload.limit,
            unit: payload.unit,
            updatedAt: payload.updatedAt,
            note: "",
            quotaWindows: payload.quotaWindows.map(\.usageQuotaWindow),
            sourceLabel: payload.sourceLabel,
            accountLabel: payload.accountLabel,
            authSourceLabel: payload.authSourceLabel,
            diagnosticCode: payload.diagnosticCode
        )
    }
}

private extension PersistedSnapshotQuotaWindow {
    init(_ window: UsageQuotaWindow) {
        self.init(
            id: window.id,
            title: window.title,
            remainingPercent: window.remainingPercent,
            usedPercent: window.usedPercent,
            resetAt: window.resetAt,
            kind: window.kind,
            resetSource: window.resetSource,
            observedAt: window.observedAt,
            serverClockSkew: window.serverClockSkew,
            confidence: window.confidence,
            windowIdentity: window.windowIdentity
        )
    }

    var usageQuotaWindow: UsageQuotaWindow {
        UsageQuotaWindow(
            id: id,
            title: title,
            remainingPercent: remainingPercent,
            usedPercent: usedPercent,
            resetAt: resetAt,
            kind: kind,
            resetSource: resetSource,
            observedAt: observedAt,
            serverClockSkew: serverClockSkew,
            confidence: confidence,
            windowIdentity: windowIdentity
        )
    }
}

/// Top-level on-disk envelope. Bump `currentSchemaVersion` on incompatible
/// changes; readers ignore files with any other version instead of crashing.
private struct PersistedSnapshotCacheEnvelope: Codable, Sendable {
    var schemaVersion: Int
    var entries: [PersistedSnapshotCacheEntry]
}

/// Durable cache of the latest main `UsageSnapshot` per provider/account.
///
/// Guarantees (optimization doc §8.1):
/// - Stores only the whitelisted payload fields; never credentials, tokens,
///   cookies, OAuth JSON, or raw log/chat content.
/// - Atomic writes; all reads/writes serialized through one IO queue so concurrent
///   provider refreshes cannot clobber each other.
/// - Incompatible schema versions and corrupt files are ignored (empty cache),
///   never fatal.
/// - Bounded size: at most `maxEntryCount` entries and `maxEncodedFileBytes`
///   on disk; overflow drops the oldest entries first.
/// - Cache key is `providerID + irreversible account fingerprint`, so accounts
///   never overwrite each other's snapshots.
final class PersistedSnapshotCache: @unchecked Sendable {
    struct WriteGeneration: Equatable, Sendable {
        var reset: UInt64
        var provider: UInt64
    }

    static let currentSchemaVersion = 1
    static let maxEntryCount = 64
    static let maxEncodedFileBytes = 512 * 1024

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "OhMyUsage.snapshot-cache", qos: .utility)
    private var loadedEntries: [PersistedSnapshotCacheEntry]?
    private struct PendingWrite {
        var providerID: String
        var snapshot: UsageSnapshot
        var savedAt: Date
        var generation: WriteGeneration
        var revision: UInt64
    }
    private var pendingWrites: [String: PendingWrite] = [:]
    private var drainScheduled = false
    private var drainID: UInt64 = 0
    private var nextRevision: UInt64 = 0
    private var acceptedRevisions: [String: UInt64] = [:]
    private var resetGeneration: UInt64 = 0
    private var providerGenerations: [String: UInt64] = [:]

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("OhMyUsage", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("provider_snapshots.json")
        }
    }

    var fileLocation: URL { fileURL }

    // MARK: - Reading

    /// Loads all valid entries. Corrupt files, incompatible schema versions,
    /// and IO failures yield an empty cache (never throw, never crash).
    func loadAll() -> [PersistedSnapshotCacheEntry] {
        readEntries()
    }

    /// Latest entry (by `savedAt`) per provider ID when the provider has only
    /// one known account fingerprint. Multiple fingerprints are ambiguous on
    /// cold start because the current credential is intentionally not read
    /// here; skip them instead of displaying another account's quota.
    func loadLatestSnapshots() -> [String: PersistedSnapshotCacheEntry] {
        let grouped = Dictionary(grouping: readEntries(), by: \.providerID)
        var latest: [String: PersistedSnapshotCacheEntry] = [:]
        for (providerID, entries) in grouped {
            guard Set(entries.map(\.accountFingerprint)).count == 1,
                  let newest = entries.max(by: { $0.savedAt < $1.savedAt }) else {
                continue
            }
            latest[providerID] = newest
        }
        return latest
    }

    // MARK: - Writing

    /// Upserts the main snapshot for `providerID` under the snapshot's account
    /// fingerprint. Serialized; safe to call from any queue/thread.
    func save(
        providerID: String,
        snapshot: UsageSnapshot,
        savedAt: Date = Date(),
        expectedGeneration: WriteGeneration? = nil
    ) {
        guard !providerID.isEmpty else { return }
        ioQueue.sync {
            saveOnIOQueue(providerID: providerID, snapshot: snapshot, savedAt: savedAt, expectedGeneration: expectedGeneration)
        }
    }

    /// Captures ordering on the caller before dispatch, not when a worker happens to run.
    func enqueueSave(providerID: String, snapshot: UsageSnapshot, savedAt: Date = Date()) {
        guard !providerID.isEmpty else { return }
        lock.lock()
        nextRevision &+= 1
        let revision = nextRevision
        let generation = WriteGeneration(reset: resetGeneration, provider: providerGenerations[providerID, default: 0])
        let key = providerID + ":" + Self.accountFingerprint(for: snapshot)
        pendingWrites[key] = PendingWrite(providerID: providerID, snapshot: snapshot, savedAt: savedAt, generation: generation, revision: revision)
        if !drainScheduled {
            drainScheduled = true
            let id = drainID
            ioQueue.async { [self] in drainPendingWrites(expectedID: id) }
        }
        lock.unlock()
    }

    private func drainPendingWrites(expectedID: UInt64? = nil) {
        lock.lock()
        if let expectedID, expectedID != drainID { lock.unlock(); return }
        let batch = pendingWrites.values.sorted { $0.revision < $1.revision }
        pendingWrites.removeAll()
        drainScheduled = false
        lock.unlock()
        for write in batch {
            saveOnIOQueue(providerID: write.providerID, snapshot: write.snapshot, savedAt: write.savedAt, expectedGeneration: write.generation, revision: write.revision)
        }
    }

    func flush() { ioQueue.sync { drainPendingWrites() } }

    private func saveOnIOQueue(providerID: String, snapshot: UsageSnapshot, savedAt: Date, expectedGeneration: WriteGeneration?, revision: UInt64? = nil) {
        lock.lock()
        let current = WriteGeneration(reset: resetGeneration, provider: providerGenerations[providerID, default: 0])
        let valid = expectedGeneration == nil || expectedGeneration == current
        lock.unlock()
        guard valid else { return }
        let entry = PersistedSnapshotCacheEntry(providerID: providerID, snapshot: snapshot, savedAt: savedAt)
        let key = providerID + ":" + entry.accountFingerprint
        if let revision {
            guard revision > acceptedRevisions[key, default: 0] else { return }
            acceptedRevisions[key] = revision
        }
        writeEntries(upserting: entry, enforceTimestampOrder: revision == nil)
    }

    /// Generation captured before dispatching an asynchronous write. Any
    /// credential/reset invalidation advances it so stale queued writes become
    /// no-ops instead of resurrecting an old account snapshot.
    func currentGeneration(for providerID: String) -> WriteGeneration {
        lock.lock()
        defer { lock.unlock() }
        return WriteGeneration(
            reset: resetGeneration,
            provider: providerGenerations[providerID, default: 0]
        )
    }

    /// Removes every account snapshot for one provider.
    func remove(providerID: String) {
        guard !providerID.isEmpty else { return }
        lock.lock()
        providerGenerations[providerID, default: 0] &+= 1
        pendingWrites = pendingWrites.filter { $0.value.providerID != providerID }
        // Fence all pending batches around deletion, preserving other providers.
        drainID &+= 1
        drainScheduled = false
        let id = drainID
        ioQueue.async { [self] in
            let retained = readEntriesLocked().filter { $0.providerID != providerID }
            loadedEntries = retained
            if retained.isEmpty { try? fileManager.removeItem(at: fileURL) }
            else { persistLocked(retained) }
            drainPendingWrites(expectedID: id)
        }
        lock.unlock()
    }

    /// Invalidates pending writes immediately; deletion remains ordered behind existing IO.
    func removeAll() {
        lock.lock()
        resetGeneration &+= 1
        providerGenerations.removeAll()
        pendingWrites.removeAll()
        drainID &+= 1
        drainScheduled = false
        ioQueue.async { [self] in
            loadedEntries = []
            acceptedRevisions.removeAll()
            try? fileManager.removeItem(at: fileURL)
        }
        lock.unlock()
    }

    // MARK: - Account fingerprint

    /// Stable, irreversible account fingerprint for the cache key.
    ///
    /// Identity inputs reuse the fingerprint/identity fields that providers
    /// already attach to snapshots (`codex.identityKey`,
    /// `codex.credentialFingerprint`, `claude.credentialFingerprint`, account
    /// IDs). The chosen value is always hashed with SHA-256 before storage, so
    /// the cache never contains the raw account identifier either.
    static func accountFingerprint(for snapshot: UsageSnapshot) -> String {
        let rawMeta = snapshot.rawMeta
        let identityInputs: [String?] = [
            rawMeta["codex.identityKey"],
            rawMeta["codex.credentialFingerprint"],
            rawMeta["claude.credentialFingerprint"],
            rawMeta["codex.accountId"],
            rawMeta["claude.accountId"],
            rawMeta["claude.configDir"],
            snapshot.accountLabel
        ]
        let identity = identityInputs.lazy
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "default"
        return fingerprint(from: identity)
    }

    static func fingerprint(from identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - File IO (serial queue only)

    private func readEntries() -> [PersistedSnapshotCacheEntry] {
        ioQueue.sync {
            loadedEntries = nil
            return readEntriesLocked()
        }
    }

    private func readEntriesLocked() -> [PersistedSnapshotCacheEntry] {
        if let loadedEntries { return loadedEntries }
        guard fileManager.fileExists(atPath: fileURL.path),
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maxEncodedFileBytes,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maxEncodedFileBytes + 1),
              data.count <= Self.maxEncodedFileBytes else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(PersistedSnapshotCacheEnvelope.self, from: data),
              envelope.schemaVersion == Self.currentSchemaVersion else {
            NSLog("[PersistedSnapshotCache] Ignoring cache file with incompatible or corrupt contents")
            return []
        }
        let entries = Self.boundedEntries(envelope.entries.filter { !$0.providerID.isEmpty && !$0.accountFingerprint.isEmpty })
        loadedEntries = entries
        return entries
    }

    private func writeEntries(upserting entry: PersistedSnapshotCacheEntry, enforceTimestampOrder: Bool) {
        var entries = readEntriesLocked()
        if enforceTimestampOrder, let current = entries.first(where: { $0.providerID == entry.providerID && $0.accountFingerprint == entry.accountFingerprint }), current.savedAt > entry.savedAt { return }
        entries.removeAll {
            $0.providerID == entry.providerID && $0.accountFingerprint == entry.accountFingerprint
        }
        entries.append(entry)
        persistLocked(entries)
    }

    private func persistLocked(_ newEntries: [PersistedSnapshotCacheEntry]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            var entries = Self.boundedEntries(newEntries)
            var data = try Self.encodedEnvelopeData(entries: entries)
            while data.count > Self.maxEncodedFileBytes, !entries.isEmpty {
                _ = entries.remove(at: Self.oldestEntryIndex(in: entries))
                if entries.isEmpty { break }
                data = try Self.encodedEnvelopeData(entries: entries)
            }
            if data.count > Self.maxEncodedFileBytes {
                // A single oversized entry cannot be stored safely; keep the
                // file valid but empty rather than writing unbounded data.
                data = try Self.encodedEnvelopeData(entries: [])
            }

            try data.write(to: fileURL, options: .atomic)
            loadedEntries = entries
        } catch {
            NSLog("[PersistedSnapshotCache] Failed to persist snapshots")
        }
    }

    /// Keeps at most `maxEntryCount` entries, dropping the oldest first.
    static func boundedEntries(_ entries: [PersistedSnapshotCacheEntry]) -> [PersistedSnapshotCacheEntry] {
        guard entries.count > maxEntryCount else { return entries }
        let sorted = entries.sorted { lhs, rhs in
            if lhs.savedAt != rhs.savedAt {
                return lhs.savedAt > rhs.savedAt
            }
            return lhs.providerID < rhs.providerID
        }
        return Array(sorted.prefix(maxEntryCount))
    }

    private static func oldestEntryIndex(in entries: [PersistedSnapshotCacheEntry]) -> Int {
        var oldestIndex = entries.startIndex
        for index in entries.indices where entries[index].savedAt < entries[oldestIndex].savedAt {
            oldestIndex = index
        }
        return oldestIndex
    }

    private static func encodedEnvelopeData(entries: [PersistedSnapshotCacheEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(
            PersistedSnapshotCacheEnvelope(schemaVersion: currentSchemaVersion, entries: entries)
        )
    }
}
