import CryptoKit
import Foundation

/// Irreversible change-detection fingerprint for credential material.
///
/// Only the SHA-256 digest ever participates in cache keys or equality
/// checks, so provider caches can detect "the cookie/token changed" without
/// ever storing, logging, or comparing the raw secret. The digest cannot be
/// reversed into the credential and is safe to keep in process memory.
enum CredentialFingerprint {
    static func sha256Hex(_ secret: String) -> String {
        let digest = SHA256.hash(data: Data(secret.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Small bounded in-memory TTL cache shared by provider instances.
///
/// Providers are recreated on every refresh (`ProviderFactory.makeProvider`),
/// so fetch-level caches (session context, per-channel results) must live in
/// process-wide instances keyed by a stable identity
/// (descriptor id + irreversible credential fingerprint). Entries never
/// persist to disk and are purged lazily once expired.
final class ProviderValueCache<Value: Sendable>: @unchecked Sendable {
    private struct Entry {
        let value: Value
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private let maxEntries: Int
    private let now: () -> Date
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    /// - Parameters:
    ///   - ttl: how long an entry stays fresh; `0` disables reuse.
    ///   - maxEntries: upper bound that keeps long-running processes honest.
    ///   - now: injectable clock for tests.
    init(ttl: TimeInterval, maxEntries: Int = 32, now: @escaping () -> Date = Date.init) {
        self.ttl = max(0, ttl)
        self.maxEntries = max(1, maxEntries)
        self.now = now
    }

    /// Returns the cached value, or `nil` when the key is missing or expired.
    /// For `Value` = `Optional<...>` the outer optional signals presence and
    /// the inner one is the stored value (a cached `nil` is a hit).
    func value(for key: String) -> Value? {
        let currentDate = now()
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else {
            return nil
        }
        guard entry.expiresAt > currentDate else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func store(_ value: Value, for key: String) {
        let currentDate = now()
        lock.lock()
        entries[key] = Entry(value: value, expiresAt: currentDate.addingTimeInterval(ttl))
        purgeExpiredLocked(now: currentDate)
        evictOverflowLocked()
        lock.unlock()
    }

    func removeValue(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }

    private func purgeExpiredLocked(now: Date) {
        entries = entries.filter { _, entry in
            entry.expiresAt > now
        }
    }

    private func evictOverflowLocked() {
        guard entries.count > maxEntries else { return }
        let overflow = entries.count - maxEntries
        let evicted = entries
            .sorted { lhs, rhs in
                if lhs.value.expiresAt != rhs.value.expiresAt {
                    return lhs.value.expiresAt < rhs.value.expiresAt
                }
                return lhs.key < rhs.key
            }
            .prefix(overflow)
            .map(\.key)
        for key in evicted {
            entries.removeValue(forKey: key)
        }
    }
}
