import CryptoKit
import Foundation

/// Doc §8.4 (Claude web segments): usage, overage and account metadata, plus the
/// organization id, are cached separately with independent TTLs so long-lived
/// metadata is not re-downloaded on every usage poll. Entries are keyed by the
/// fingerprint of the web cookie header, so cached data never crosses accounts.
actor OfficialWebSegmentCache {
    private struct Entry {
        let payload: Data
        let expiresAt: Date
    }

    private let now: @Sendable () -> Date
    private var entries: [String: Entry] = [:]

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func data(for key: String) -> Data? {
        let currentDate = now()
        purgeExpiredLocked(now: currentDate)
        guard let entry = entries[key], entry.expiresAt > currentDate else { return nil }
        return entry.payload
    }

    func string(for key: String) -> String? {
        guard let data = data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func store(_ data: Data, for key: String, ttl: TimeInterval) {
        let currentDate = now()
        entries[key] = Entry(
            payload: data,
            expiresAt: currentDate.addingTimeInterval(max(0, ttl))
        )
        purgeExpiredLocked(now: currentDate)
    }

    func storeString(_ value: String, for key: String, ttl: TimeInterval) {
        store(Data(value.utf8), for: key, ttl: ttl)
    }

    private func purgeExpiredLocked(now currentDate: Date) {
        entries = entries.filter { _, entry in
            entry.expiresAt > currentDate
        }
    }

    /// Stable, non-reversible per-account cache key component derived from the
    /// web cookie header. The raw cookie value is never stored in cache keys.
    nonisolated static func credentialIdentity(for cookieHeader: String) -> String {
        let trimmed = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "anonymous" }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
