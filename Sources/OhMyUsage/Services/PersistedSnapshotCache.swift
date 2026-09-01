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
/// - Atomic writes; all reads/writes serialized through one lock so concurrent
///   provider refreshes cannot clobber each other.
/// - Incompatible schema versions and corrupt files are ignored (empty cache),
///   never fatal.
/// - Bounded size: at most `maxEntryCount` entries and `maxEncodedFileBytes`
///   on disk; overflow drops the oldest entries first.
/// - Cache key is `providerID + irreversible account fingerprint`, so accounts
///   never overwrite each other's snapshots.
final class PersistedSnapshotCache: @unchecked Sendable {
    static let currentSchemaVersion = 1
    static let maxEntryCount = 64
    static let maxEncodedFileBytes = 512 * 1024

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

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

    /// Latest entry (by `savedAt`) per provider ID. Restored sessions should
    /// use this so a provider with multiple historical account entries resumes
    /// with the account that was active most recently.
    func loadLatestSnapshots() -> [String: PersistedSnapshotCacheEntry] {
        var latest: [String: PersistedSnapshotCacheEntry] = [:]
        for entry in readEntries() {
            guard let current = latest[entry.providerID] else {
                latest[entry.providerID] = entry
                continue
            }
            if entry.savedAt > current.savedAt {
                latest[entry.providerID] = entry
            }
        }
        return latest
    }

    // MARK: - Writing

    /// Upserts the main snapshot for `providerID` under the snapshot's account
    /// fingerprint. Serialized; safe to call from any queue/thread.
    func save(providerID: String, snapshot: UsageSnapshot, savedAt: Date = Date()) {
        guard !providerID.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        writeEntries(upserting: PersistedSnapshotCacheEntry(providerID: providerID, snapshot: snapshot, savedAt: savedAt))
    }

    /// Removes every cached entry (used by reset flows).
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL)
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

    // MARK: - File IO (lock held)

    private func readEntries() -> [PersistedSnapshotCacheEntry] {
        lock.lock()
        defer { lock.unlock() }
        return readEntriesLocked()
    }

    private func readEntriesLocked() -> [PersistedSnapshotCacheEntry] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(PersistedSnapshotCacheEnvelope.self, from: data),
              envelope.schemaVersion == Self.currentSchemaVersion else {
            NSLog("[PersistedSnapshotCache] Ignoring cache file with incompatible or corrupt contents")
            return []
        }
        return envelope.entries
    }

    private func writeEntries(upserting entry: PersistedSnapshotCacheEntry) {
        var entries = readEntriesLocked()
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
        } catch {
            NSLog("[PersistedSnapshotCache] Failed to persist snapshots: \(error.localizedDescription)")
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
