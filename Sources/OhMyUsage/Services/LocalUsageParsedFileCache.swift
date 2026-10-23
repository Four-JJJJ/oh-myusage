// Bounded memoization of parsed source-file contents: parse results are cached
// per file snapshot and reused across fetches until the underlying file changes.

import Foundation

final class LocalUsageParsedFileCache<Value>: @unchecked Sendable {
    private struct CacheKey: Hashable {
        var path: String
        var context: String
    }

    private struct Entry {
        var snapshot: LocalUsageFileSnapshot
        var values: [Value]
        var parsedAt: Date
    }

    private let lock = NSLock()
    private let maxEntries: Int
    private let maxCachedValues: Int
    private var entries: [CacheKey: Entry] = [:]
    private var accessOrder: [CacheKey] = []
    private var cachedValueCount = 0

    init(maxEntries: Int = 512, maxCachedValues: Int? = nil) {
        self.maxEntries = max(1, maxEntries)
        self.maxCachedValues = max(1, maxCachedValues ?? max(1, maxEntries) * 256)
    }

    func values(
        for snapshot: LocalUsageFileSnapshot,
        context: String = "",
        parse: () -> [Value]
    ) -> [Value] {
        let key = CacheKey(path: snapshot.path, context: context)

        lock.lock()
        if let entry = entries[key], entry.snapshot == snapshot,
           Date().timeIntervalSince(entry.parsedAt) < 30 * 60 {
            let values = entry.values
            markAccessedLocked(key)
            lock.unlock()
            return values
        }
        removeEntryLocked(for: key)
        lock.unlock()

        let parsed = parse()
        guard !Task.isCancelled else { return parsed }

        lock.lock()
        // Another caller may have populated the same key while parsing happened
        // outside the lock. Replace that entry without leaking its count.
        removeEntryLocked(for: key)
        guard parsed.count <= maxCachedValues else {
            lock.unlock()
            return parsed
        }
        entries[key] = Entry(snapshot: snapshot, values: parsed, parsedAt: Date())
        cachedValueCount += parsed.count
        markAccessedLocked(key)
        pruneIfNeeded()
        lock.unlock()

        return parsed
    }

    func removeAllEntries() {
        lock.lock()
        entries.removeAll(keepingCapacity: false)
        accessOrder.removeAll(keepingCapacity: false)
        cachedValueCount = 0
        lock.unlock()
    }

    private func markAccessedLocked(_ key: CacheKey) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func removeEntryLocked(for key: CacheKey) {
        if let removed = entries.removeValue(forKey: key) {
            cachedValueCount = max(0, cachedValueCount - removed.values.count)
        }
        accessOrder.removeAll { $0 == key }
    }

    private func pruneIfNeeded() {
        accessOrder.removeAll { entries[$0] == nil }
        while entries.count > maxEntries || (cachedValueCount > maxCachedValues && entries.count > 1) {
            guard let key = accessOrder.first else { return }
            removeEntryLocked(for: key)
        }
    }
}
