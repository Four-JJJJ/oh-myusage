import Foundation
import OhMyUsageDomain

public protocol OfficialSnapshotCaching: Actor {
    func snapshotIfFresh(for key: String, ttl: TimeInterval) -> UsageSnapshot?
    func store(_ snapshot: UsageSnapshot, for key: String)
    func snapshotAny(for key: String) -> UsageSnapshot?
    func store(_ snapshot: UsageSnapshot, for key: String, generation: UInt64)
}

public extension OfficialSnapshotCaching {
    func store(_ snapshot: UsageSnapshot, for key: String, generation: UInt64) {
        store(snapshot, for: key)
    }
}

public protocol OfficialFetchGating: Actor {
    func withPermit<T>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T
}

private final class OfficialCacheGeneration: @unchecked Sendable {
    static let shared = OfficialCacheGeneration()
    private let lock = NSLock()
    private var generation: UInt64 = 0
    func current() -> UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
    func invalidate() { lock.lock(); generation &+= 1; lock.unlock() }
}

public enum OfficialProviderFetchRuntime {
    /// Credential changes invalidate even caches retained by static provider instances.
    public static var cacheGeneration: UInt64 { OfficialCacheGeneration.shared.current() }
    public static func invalidateCaches() { OfficialCacheGeneration.shared.invalidate() }

    public static func fetch(
        forceRefresh: Bool,
        cacheLookupKey: String,
        ttl: TimeInterval,
        cache: any OfficialSnapshotCaching,
        gate: any OfficialFetchGating,
        cacheStoreKey: (@Sendable () -> String)? = nil,
        load: @Sendable @escaping () async throws -> UsageSnapshot
    ) async throws -> UsageSnapshot {
        try await gate.withPermit {
            if !forceRefresh,
               let cached = await cache.snapshotIfFresh(for: cacheLookupKey, ttl: ttl) {
                return cached
            }

            try Task.checkCancellation()
            let generation = OfficialCacheGeneration.shared.current()
            do {
                let snapshot = try await load()
                try Task.checkCancellation()
                let storeKey = cacheStoreKey?() ?? cacheLookupKey
                if generation == OfficialCacheGeneration.shared.current() {
                    await cache.store(snapshot, for: storeKey, generation: generation)
                }
                return snapshot
            } catch {
                if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled { throw error }
                if !forceRefresh,
                   let stale = await cache.snapshotAny(for: cacheLookupKey) {
                    var fallback = OfficialSnapshotFallback.make(from: stale)
                    if let limited = error as? ProviderRateLimitError {
                        fallback.fetchHealth = .rateLimited
                        fallback.rawMeta["provider.retryNotBefore"] = String(limited.retryNotBefore.timeIntervalSince1970)
                    }
                    return fallback
                }
                throw error
            }
        }
    }
}

private struct BoundedOfficialSnapshots {
    struct Entry {
        var snapshot: UsageSnapshot
        var timestamp: Date
        var access: UInt64
        var generation: UInt64
    }
    var entries: [String: Entry] = [:]
    var sequence: UInt64 = 0
    var generation = OfficialCacheGeneration.shared.current()
    let capacity: Int
    let maximumStaleAge: TimeInterval
    let now: @Sendable () -> Date

    mutating func lookup(_ key: String, maximumAge: TimeInterval) -> UsageSnapshot? {
        prune()
        guard var entry = entries[key] else { return nil }
        let age = now().timeIntervalSince(entry.timestamp)
        guard age >= 0, age <= maximumAge else { return nil }
        sequence &+= 1
        entry.access = sequence
        entries[key] = entry
        return entry.snapshot
    }

    mutating func store(_ snapshot: UsageSnapshot, key: String, timestamp: Date, loadGeneration: UInt64? = nil) {
        prune()
        sequence &+= 1
        let entryGeneration = loadGeneration ?? OfficialCacheGeneration.shared.current()
        guard entryGeneration == OfficialCacheGeneration.shared.current() else { return }
        entries[key] = Entry(snapshot: snapshot, timestamp: timestamp, access: sequence, generation: entryGeneration)
        while entries.count > capacity {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            entries.removeValue(forKey: oldest)
        }
    }

    mutating func prune() {
        let currentGeneration = OfficialCacheGeneration.shared.current()
        if generation != currentGeneration { entries.removeAll(); generation = currentGeneration }
        let cutoff = now().addingTimeInterval(-maximumStaleAge)
        entries = entries.filter { $0.value.timestamp >= cutoff && $0.value.generation == currentGeneration }
    }
}

public actor FetchedAtOfficialSnapshotCache: OfficialSnapshotCaching {
    private var storage: BoundedOfficialSnapshots

    public init(capacity: Int = 64, maximumStaleAge: TimeInterval = 24 * 3600, now: @escaping @Sendable () -> Date = Date.init) {
        storage = BoundedOfficialSnapshots(capacity: max(1, capacity), maximumStaleAge: max(0, maximumStaleAge), now: now)
    }

    public func snapshotIfFresh(for key: String, ttl: TimeInterval) -> UsageSnapshot? {
        storage.lookup(key, maximumAge: max(0, ttl))
    }
    public func store(_ snapshot: UsageSnapshot, for key: String) {
        storage.store(snapshot, key: key, timestamp: storage.now())
    }
    public func store(_ snapshot: UsageSnapshot, for key: String, generation: UInt64) {
        storage.store(snapshot, key: key, timestamp: storage.now(), loadGeneration: generation)
    }
    public func snapshotAny(for key: String) -> UsageSnapshot? {
        storage.lookup(key, maximumAge: storage.maximumStaleAge)
    }
    public func removeAll() { storage.entries.removeAll() }
    public func remove(for key: String) { storage.entries.removeValue(forKey: key) }
}

public actor SnapshotTimestampOfficialSnapshotCache: OfficialSnapshotCaching {
    private var storage: BoundedOfficialSnapshots

    public init(capacity: Int = 64, maximumStaleAge: TimeInterval = 24 * 3600, now: @escaping @Sendable () -> Date = Date.init) {
        storage = BoundedOfficialSnapshots(capacity: max(1, capacity), maximumStaleAge: max(0, maximumStaleAge), now: now)
    }
    public func snapshotIfFresh(for key: String, ttl: TimeInterval) -> UsageSnapshot? {
        storage.lookup(key, maximumAge: max(0, ttl))
    }
    public func store(_ snapshot: UsageSnapshot, for key: String) {
        storage.store(snapshot, key: key, timestamp: snapshot.updatedAt)
    }
    public func store(_ snapshot: UsageSnapshot, for key: String, generation: UInt64) {
        storage.store(snapshot, key: key, timestamp: snapshot.updatedAt, loadGeneration: generation)
    }
    public func snapshotAny(for key: String) -> UsageSnapshot? {
        storage.lookup(key, maximumAge: storage.maximumStaleAge)
    }
    public func removeAll() { storage.entries.removeAll() }
    public func remove(for key: String) { storage.entries.removeValue(forKey: key) }
}

public actor SerialOfficialFetchGate: OfficialFetchGating {
    private var inFlight = false
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []

    public init() {}

    public func withPermit<T>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !inFlight {
            inFlight = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            inFlight = false
            return
        }
        let next = waiters.removeFirst()
        next.1.resume()
    }
}

public actor PassthroughOfficialFetchGate: OfficialFetchGating {
    public init() {}

    public func withPermit<T>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await operation()
    }
}
