// Local usage history facade: query/entry/state value models, the MainActor
// repository that orchestrates refresh, pruning, restore, and persistence of
// cached local usage summaries, and the disk cache IO queue backing it.

import Foundation
import OSLog
import OhMyUsageApplication
import OhMyUsageDomain

struct LocalUsageHistoryQuery: Codable, Equatable, Hashable, Sendable {
    var providerType: ProviderType
    var providerID: String
    var scope: LocalUsageTrendScope
    var identityKey: String

    init(
        providerType: ProviderType,
        providerID: String,
        scope: LocalUsageTrendScope,
        identityKey: String
    ) {
        self.providerType = providerType
        self.providerID = providerID
        self.scope = scope
        self.identityKey = identityKey
    }
}

struct LocalUsageSourceFingerprint: Codable, Equatable, Sendable {
    var roots: [String]
    var fileCount: Int
    var totalSize: UInt64
    var latestModificationTime: Date?
    var metadataDigest: String? = nil
}

struct LocalUsageHistoryEntry: Codable, Equatable, Sendable {
    var query: LocalUsageHistoryQuery
    var summary: LocalUsageSummary?
    var refreshedAt: Date
    var sourceFingerprint: LocalUsageSourceFingerprint?
    var lastFingerprintCheckedAt: Date?
    var lastError: String?
    var isStaleFallback: Bool
    var lastAttemptAt: Date? = nil
    var retryNotBefore: Date? = nil
}

struct LocalUsageHistoryState: Equatable, Sendable {
    var summary: LocalUsageSummary?
    var error: String?
    var isLoading: Bool
    var lastRefreshedAt: Date?
    var sourceFingerprint: LocalUsageSourceFingerprint?
    var lastFingerprintCheckedAt: Date?
    var isStaleFallback: Bool
}

struct LocalUsageHistoryLoadResult: Sendable {
    var summary: LocalUsageSummary
    var sourceFingerprint: LocalUsageSourceFingerprint
}

@MainActor
final class LocalUsageHistoryRepository {
    typealias FingerprintProvider = @Sendable () -> LocalUsageSourceFingerprint
    typealias AsyncLoader = @Sendable (_ sourceFingerprint: LocalUsageSourceFingerprint) async throws -> LocalUsageHistoryLoadResult
    typealias Loader = @Sendable (_ sourceFingerprint: LocalUsageSourceFingerprint) throws -> LocalUsageHistoryLoadResult


    private let fileURL: URL
    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private var entries: [LocalUsageHistoryQuery: LocalUsageHistoryEntry] = [:]
    private var loadingTasks: [LocalUsageHistoryQuery: Task<Void, Never>] = [:]
    private let io: LocalUsageHistoryCacheIO
    private let asynchronousIO: Bool
    private var touchedQueries: Set<LocalUsageHistoryQuery> = []
    private var restoreTask: Task<Void, Never>?
    private var restoreRevision = 0
    private var restoreInFlight = false
    private var removedProvidersDuringRestore: Set<String> = []
    private var taskTokens: [LocalUsageHistoryQuery: UUID] = [:]
    var onRestore: (@MainActor () -> Void)?

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        asynchronousIO: Bool = true,
        beforeCacheRead: @escaping @Sendable () -> Void = {},
        cacheDiagnostic: @escaping @Sendable (String) -> Void = { category in
            Logger(subsystem: "OhMyUsage", category: "LocalUsageHistoryCache").notice("cache event: \(category, privacy: .public)")
        }
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        let rootDirectory: URL
        if let baseDirectoryURL {
            rootDirectory = baseDirectoryURL
        } else {
            rootDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }
        self.fileURL = rootDirectory
            .appendingPathComponent("OhMyUsage", isDirectory: true)
            .appendingPathComponent("local_usage_history_cache.json")
        self.asynchronousIO = asynchronousIO
        self.io = LocalUsageHistoryCacheIO(fileURL: fileURL, fileManager: fileManager,
            beforeRead: beforeCacheRead, diagnostic: cacheDiagnostic)
        restoreFromDisk()
    }

    func snapshot(for query: LocalUsageHistoryQuery) -> LocalUsageHistoryState {
        let entry = entries[query]
        return LocalUsageHistoryState(
            summary: entry?.summary,
            error: entry?.lastError,
            isLoading: loadingTasks[query] != nil,
            lastRefreshedAt: entry?.summary == nil ? nil : entry?.refreshedAt,
            sourceFingerprint: entry?.sourceFingerprint,
            lastFingerprintCheckedAt: entry?.lastFingerprintCheckedAt,
            isStaleFallback: entry?.isStaleFallback ?? false
        )
    }

    func refreshIfNeeded(
        query: LocalUsageHistoryQuery,
        force: Bool = false,
        ttl: TimeInterval = RuntimeDiagnosticsLimits.localUsageTrendCacheEntryTTL,
        fingerprintProbeInterval: TimeInterval = RuntimeDiagnosticsLimits.localUsageTrendFingerprintProbeInterval,
        fingerprintProvider: @escaping FingerprintProvider,
        loader: @escaping Loader,
        asyncLoader: AsyncLoader? = nil,
        onStateChange: @escaping @MainActor () -> Void
    ) {
        prune(now: nowProvider())
        guard loadingTasks[query] == nil else { return }

        let now = nowProvider()
        if !force, let deadline = entries[query]?.retryNotBefore, now < deadline { return }
        if !force,
           let entry = entries[query],
           entry.lastError == nil,
           let summary = entry.summary,
           now.timeIntervalSince(entry.refreshedAt) < ttl,
           now.timeIntervalSince(entry.refreshedAt) < maximumLoadAge(for: query),
           isSummaryTemporallyFresh(summary, now: now),
           !shouldProbeFingerprint(entry: entry, now: now, interval: fingerprintProbeInterval) {
            return
        }

        let token = UUID()
        taskTokens[query] = token
        loadingTasks[query] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if taskTokens[query] == token {
                    loadingTasks.removeValue(forKey: query)
                    taskTokens.removeValue(forKey: query)
                }
            }
            await restoreTask?.value
            guard !Task.isCancelled, taskTokens[query] == token else { return }
            if restoreInFlight { touchedQueries.insert(query) }
            onStateChange()

            let fingerprintWorker = Task.detached(priority: .utility) {
                fingerprintProvider()
            }
            let fingerprint = await withTaskCancellationHandler {
                await fingerprintWorker.value
            } onCancel: { fingerprintWorker.cancel() }
            guard !Task.isCancelled, taskTokens[query] == token else { onStateChange(); return }

            if !force,
               var entry = entries[query],
               let summary = entry.summary,
               entry.lastError == nil,
               entry.sourceFingerprint == fingerprint,
               nowProvider().timeIntervalSince(entry.refreshedAt) < maximumLoadAge(for: query),
               isSummaryTemporallyFresh(summary, now: nowProvider()) {
                let validatedAt = nowProvider()
                entry.lastFingerprintCheckedAt = validatedAt
                entry.lastError = nil
                entry.isStaleFallback = false
                entries[query] = entry
                loadingTasks.removeValue(forKey: query)
                prune(now: entry.refreshedAt)
                persist()
                onStateChange()
                return
            }

            let loaderWorker = Task.detached(priority: .utility) {
                do {
                    try Task.checkCancellation()
                    let result: LocalUsageHistoryLoadResult
                    if let asyncLoader { result = try await asyncLoader(fingerprint) }
                    else { result = try loader(fingerprint) }
                    try Task.checkCancellation()
                    return Result<LocalUsageHistoryLoadResult, Error>.success(result)
                } catch { return Result<LocalUsageHistoryLoadResult, Error>.failure(error) }
            }
            let result = await withTaskCancellationHandler {
                await loaderWorker.value
            } onCancel: { loaderWorker.cancel() }
            guard !Task.isCancelled, taskTokens[query] == token else { onStateChange(); return }

            loadingTasks.removeValue(forKey: query)
            let refreshedAt = nowProvider()
            switch result {
            case .success(let loadResult):
                entries[query] = LocalUsageHistoryEntry(
                    query: query,
                    summary: RuntimeBoundedState.slimmedLocalUsageSummaryForCache(loadResult.summary),
                    refreshedAt: refreshedAt,
                    sourceFingerprint: loadResult.sourceFingerprint,
                    lastFingerprintCheckedAt: refreshedAt,
                    lastError: nil,
                    isStaleFallback: false,
                    lastAttemptAt: refreshedAt
                )
            case .failure(let error):
                if var existing = entries[query], existing.summary != nil {
                    existing.lastAttemptAt = refreshedAt
                    existing.retryNotBefore = refreshedAt.addingTimeInterval(30)
                    existing.lastFingerprintCheckedAt = refreshedAt
                    existing.lastError = error.localizedDescription
                    existing.isStaleFallback = true
                    entries[query] = existing
                } else {
                    entries[query] = LocalUsageHistoryEntry(
                        query: query,
                        summary: nil,
                        refreshedAt: refreshedAt,
                        sourceFingerprint: fingerprint,
                        lastFingerprintCheckedAt: refreshedAt,
                        lastError: error.localizedDescription,
                        isStaleFallback: false,
                        lastAttemptAt: refreshedAt,
                        retryNotBefore: refreshedAt.addingTimeInterval(30)
                    )
                }
            }

            prune(now: refreshedAt)
            persist()
            onStateChange()
        }

        onStateChange()
    }

    func restoreFromDisk() {
        restoreRevision += 1
        let revision = restoreRevision
        restoreInFlight = true
        if !asynchronousIO {
            mergeRestored(io.restore())
            touchedQueries.removeAll(keepingCapacity: false)
            restoreInFlight = false
            return
        }
        restoreTask = Task { @MainActor [weak self, io] in
            let restored = await withCheckedContinuation { continuation in
                io.queue.async { continuation.resume(returning: io.restore()) }
            }
            guard let self, self.restoreRevision == revision else { return }
            self.mergeRestored(restored)
            self.touchedQueries.removeAll(keepingCapacity: false)
            self.restoreInFlight = false
        }
    }

    private func mergeRestored(_ restored: [LocalUsageHistoryEntry]) {
        for entry in restored where !touchedQueries.contains(entry.query) && !removedProvidersDuringRestore.contains(entry.query.providerID) {
            if let existing = entries[entry.query], existing.refreshedAt >= entry.refreshedAt { continue }
            entries[entry.query] = entry
        }
        prune(now: nowProvider())
        if !removedProvidersDuringRestore.isEmpty {
            removedProvidersDuringRestore.removeAll(keepingCapacity: false)
            persist()
        }
        onRestore?()
    }

    func persist() {
        let snapshot = sortedEntries()
        if asynchronousIO {
            io.enqueue(snapshot)
        } else {
            io.persist(snapshot)
        }
    }

    func cancelRefresh(for query: LocalUsageHistoryQuery) {
        loadingTasks.removeValue(forKey: query)?.cancel()
        taskTokens.removeValue(forKey: query)
    }

    func cancelAllRefreshes() {
        for task in loadingTasks.values { task.cancel() }
        loadingTasks.removeAll(keepingCapacity: false)
        taskTokens.removeAll(keepingCapacity: false)
    }

    func removeEntries(providerID: String) {
        if restoreInFlight { removedProvidersDuringRestore.insert(providerID) }
        for query in Array(loadingTasks.keys) where query.providerID == providerID { cancelRefresh(for: query) }
        entries = entries.filter { $0.key.providerID != providerID }
        touchedQueries = touchedQueries.filter { $0.providerID != providerID }
        // Persist only after the pending restore merges unrelated providers.
        if !restoreInFlight { persist() }
    }

    func reset() {
        restoreRevision += 1
        restoreInFlight = false
        removedProvidersDuringRestore.removeAll(keepingCapacity: false)
        cancelAllRefreshes()
        entries.removeAll(keepingCapacity: false)
        touchedQueries.removeAll(keepingCapacity: false)
        persist()
    }

    func shutdown() async {
        cancelAllRefreshes()
        await flushPersistence()
    }

    /// Await this at orderly shutdown/tests; abrupt termination can lose queued cache writes.
    func flushPersistence() async {
        guard asynchronousIO else { return }
        await restoreTask?.value
        await withCheckedContinuation { continuation in
            io.queue.async { continuation.resume() }
        }
    }

    private func prune(now: Date) {
        let ttl = max(30, RuntimeDiagnosticsLimits.localUsageTrendCacheEntryTTL)
        let cutoff = now.addingTimeInterval(-ttl)
        entries = entries.filter { _, entry in
            entry.refreshedAt >= cutoff || entry.summary != nil
        }

        let maxEntries = max(1, RuntimeDiagnosticsLimits.localUsageTrendCacheMaxEntries)
        guard entries.count > maxEntries else { return }

        let keepQueries = Set(
            entries.values
                .sorted { lhs, rhs in
                    if lhs.refreshedAt != rhs.refreshedAt {
                        return lhs.refreshedAt > rhs.refreshedAt
                    }
                    return sortKey(lhs.query) < sortKey(rhs.query)
                }
                .prefix(maxEntries)
                .map(\.query)
        )
        entries = entries.filter { keepQueries.contains($0.key) }
    }

    private func sortedEntries() -> [LocalUsageHistoryEntry] {
        entries.values.sorted { lhs, rhs in
            if lhs.refreshedAt != rhs.refreshedAt {
                return lhs.refreshedAt > rhs.refreshedAt
            }
            return sortKey(lhs.query) < sortKey(rhs.query)
        }
    }

    private func sortKey(_ query: LocalUsageHistoryQuery) -> String {
        [query.providerType.rawValue, query.providerID, query.scope.rawValue, query.identityKey].joined(separator: "\u{0}")
    }

    private func shouldProbeFingerprint(
        entry: LocalUsageHistoryEntry,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard entry.sourceFingerprint != nil else { return true }
        let reference = entry.lastFingerprintCheckedAt ?? entry.refreshedAt
        return now.timeIntervalSince(reference) >= max(5, interval)
    }

    private func maximumLoadAge(for query: LocalUsageHistoryQuery) -> TimeInterval {
        query.providerType == .cursor ? 60 : 30 * 60
    }

    private func isSummaryTemporallyFresh(_ summary: LocalUsageSummary, now: Date) -> Bool {
        Calendar.current.isDate(summary.generatedAt, equalTo: now, toGranularity: .hour)
    }

}

private final class LocalUsageHistoryCacheIO: @unchecked Sendable {
    struct Payload: Codable {
        var schemaVersion: Int? = 2
        var entries: [LocalUsageHistoryEntry]
    }

    let queue = DispatchQueue(label: "OhMyUsage.localUsageHistory.cache", qos: .utility)
    private let fileURL: URL
    private let fileManager: FileManager
    private let beforeRead: @Sendable () -> Void
    private let diagnostic: @Sendable (String) -> Void
    private var lastPersistedEntries: [LocalUsageHistoryEntry]?
    private let pendingLock = NSLock()
    private var pending: [LocalUsageHistoryEntry]?
    private var writeScheduled = false
    // 24 slimmed entries fit well below this budget, including model breakdowns.
    static let maximumBytes = 16 * 1024 * 1024

    init(fileURL: URL, fileManager: FileManager,
         beforeRead: @escaping @Sendable () -> Void, diagnostic: @escaping @Sendable (String) -> Void) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.beforeRead = beforeRead
        self.diagnostic = diagnostic
    }

    func enqueue(_ entries: [LocalUsageHistoryEntry]) {
        pendingLock.lock()
        pending = entries
        let schedule = !writeScheduled
        writeScheduled = true
        pendingLock.unlock()
        guard schedule else { return }
        queue.async { [self] in
            while true {
                pendingLock.lock()
                guard let snapshot = pending else {
                    writeScheduled = false
                    pendingLock.unlock()
                    return
                }
                pending = nil
                pendingLock.unlock()
                persist(snapshot)
            }
        }
    }

    func restore() -> [LocalUsageHistoryEntry] {
        beforeRead()
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumBytes + 1), data.count <= Self.maximumBytes else {
            diagnostic("restoreSizeOrReadFailure")
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data),
              payload.schemaVersion == nil || payload.schemaVersion == 2 else {
            diagnostic("restoreSchemaOrDecodeFailure")
            return []
        }
        var restored: [LocalUsageHistoryQuery: LocalUsageHistoryEntry] = [:]
        for entry in payload.entries where Self.isValid(entry) {
            // First wins ties; newest successful refresh wins duplicate keys.
            if let old = restored[entry.query], old.refreshedAt >= entry.refreshedAt { continue }
            restored[entry.query] = entry
        }
        if restored.count < payload.entries.count { diagnostic("restoreDiscardedEntries") }
        return Array(restored.values)
    }

    func persist(_ entries: [LocalUsageHistoryEntry]) {
        guard entries != lastPersistedEntries || !fileManager.fileExists(atPath: fileURL.path) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(Payload(entries: entries))
            guard data.count <= Self.maximumBytes else { return }
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lastPersistedEntries = entries
        } catch {
            diagnostic("persistFailure")
            // This reconstructible display cache never invalidates the in-memory result.
            return
        }
    }

    private static func isValid(_ entry: LocalUsageHistoryEntry) -> Bool {
        guard !entry.query.providerID.isEmpty, !entry.query.identityKey.isEmpty,
              entry.refreshedAt.timeIntervalSinceReferenceDate.isFinite,
              entry.sourceFingerprint.map({ $0.fileCount >= 0 && $0.roots.count <= 1024 }) ?? true else { return false }
        guard let summary = entry.summary else { return true }
        let periods = [summary.today, summary.yesterday, summary.last30Days]
        return summary.generatedAt.timeIntervalSinceReferenceDate.isFinite &&
            periods.allSatisfy {
                $0.totalTokens >= 0 && $0.responses >= 0 && $0.inputTokens >= 0 && $0.outputTokens >= 0 &&
                $0.cacheReadTokens >= 0 && $0.cacheWriteTokens >= 0 && $0.byModel.count <= 1024 &&
                $0.byModel.allSatisfy { $0.totalTokens >= 0 && $0.responses >= 0 }
            } &&
            summary.hourly24.count <= 48 && summary.daily7.count <= 32 &&
            (summary.hourly24 + summary.daily7).allSatisfy { $0.totalTokens >= 0 && $0.responses >= 0 }
    }
}
