import Foundation

@MainActor
final class UsageAnalyticsRefreshCoordinator {
    typealias SourceFingerprintLoader = @Sendable (_ claudeAllConfigDirs: [String]) -> UsageAnalyticsSourceFingerprint
    typealias SnapshotLoader = @Sendable (
        _ filter: UsageAnalyticsFilter,
        _ claudeAllConfigDirs: [String]
    ) -> UsageAnalyticsSnapshot

    private let repository: UsageAnalyticsRepository
    private let usesDefaultFingerprintLoader: Bool
    private let usesDefaultSnapshotLoader: Bool
    private let sourceFingerprintLoader: SourceFingerprintLoader
    private let snapshotLoader: SnapshotLoader
    private let cacheStore: UsageAnalyticsSnapshotCacheStore
    private let nowProvider: () -> Date
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        repository: UsageAnalyticsRepository = UsageAnalyticsRepository(),
        cacheStore: UsageAnalyticsSnapshotCacheStore = UsageAnalyticsSnapshotCacheStore(restoreAsynchronously: true),
        nowProvider: @escaping () -> Date = Date.init,
        sourceFingerprintLoader: SourceFingerprintLoader? = nil,
        snapshotLoader: SnapshotLoader? = nil
    ) {
        self.repository = repository
        self.usesDefaultFingerprintLoader = sourceFingerprintLoader == nil
        self.usesDefaultSnapshotLoader = snapshotLoader == nil
        self.cacheStore = cacheStore
        self.nowProvider = nowProvider
        self.sourceFingerprintLoader = sourceFingerprintLoader ?? { claudeAllConfigDirs in
            repository.sourceFingerprint(claudeAllConfigDirs: claudeAllConfigDirs)
        }
        self.snapshotLoader = snapshotLoader ?? { filter, claudeAllConfigDirs in
            repository.snapshot(
                filter: filter,
                claudeAllConfigDirs: claudeAllConfigDirs
            )
        }
    }

    func reset() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        cacheStore.removeAll()
        repository.invalidateRawCache()
    }

    func flushPersistence() async {
        refreshGeneration += 1
        refreshTask?.cancel()
        await refreshTask?.value
        refreshTask = nil
        await cacheStore.waitForPendingIO()
    }

    func refreshUsageAnalyticsIfNeeded(
        filter: UsageAnalyticsFilter,
        currentSnapshotFilter: UsageAnalyticsFilter,
        claudeAllConfigDirs: [String],
        force: Bool = false,
        onSnapshotChange: @escaping @MainActor (UsageAnalyticsSnapshot) -> Void,
        onLoadingChange: @escaping @MainActor (Bool) -> Void
    ) {
        let cachedEntry = cacheStore.entry(for: filter)
        let hasCachedSnapshot = cachedEntry?.snapshot != nil

        if let snapshot = cachedEntry?.snapshot {
            onSnapshotChange(snapshot)
        } else if currentSnapshotFilter != filter {
            onSnapshotChange(UsageAnalyticsSnapshot.empty(filter: filter))
        }

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let cacheStore = cacheStore
        let sourceFingerprintLoader = sourceFingerprintLoader
        let repository = repository
        let usesDefaultFingerprintLoader = usesDefaultFingerprintLoader
        let usesDefaultSnapshotLoader = usesDefaultSnapshotLoader
        let snapshotLoader = snapshotLoader
        let nowProvider = nowProvider
        onLoadingChange(force || !hasCachedSnapshot)

        refreshTask = Task { @MainActor [weak self] in
            await cacheStore.waitForPendingIO()
            guard !Task.isCancelled else { return }
            if !hasCachedSnapshot, let restored = cacheStore.entry(for: filter)?.snapshot {
                onSnapshotChange(restored)
            }
            let fingerprintWorker = Task.detached(priority: .utility) {
                if force && usesDefaultFingerprintLoader {
                    return repository.sourceFingerprint(claudeAllConfigDirs: claudeAllConfigDirs, bypassCache: true)
                }
                return sourceFingerprintLoader(claudeAllConfigDirs)
            }
            let fingerprint = await withTaskCancellationHandler {
                await fingerprintWorker.value
            } onCancel: { fingerprintWorker.cancel() }

            guard !Task.isCancelled else { return }
            guard let self, generation == self.refreshGeneration else { return }

            let validationDate = nowProvider()
            if !force,
               let entry = cacheStore.entry(for: filter),
               entry.sourceFingerprint == fingerprint,
               entry.snapshot.isPartial == false,
               validationDate.timeIntervalSince(entry.snapshot.generatedAt) < 60,
               cacheStore.isEntryTemporallyFresh(
                   for: filter,
                   now: validationDate,
                   calendar: .current
               ) {
                cacheStore.markValidated(
                    filter: filter,
                    sourceFingerprint: fingerprint,
                    at: validationDate
                )
                onLoadingChange(false)
                refreshTask = nil
                return
            }

            if !hasCachedSnapshot {
                onLoadingChange(true)
            }

            let snapshot: UsageAnalyticsSnapshot
            if usesDefaultSnapshotLoader {
                do {
                    snapshot = try await repository.snapshotAsync(filter: filter,
                        claudeAllConfigDirs: claudeAllConfigDirs, bypassCache: force)
                } catch {
                    guard !Task.isCancelled else { return }
                    onLoadingChange(false)
                    refreshTask = nil
                    return
                }
            } else {
                let snapshotWorker = Task.detached(priority: .utility) {
                    snapshotLoader(filter, claudeAllConfigDirs)
                }
                snapshot = await withTaskCancellationHandler {
                    await snapshotWorker.value
                } onCancel: { snapshotWorker.cancel() }
            }

            guard !Task.isCancelled else { return }
            guard generation == self.refreshGeneration else { return }

            cacheStore.save(snapshot: snapshot, sourceFingerprint: fingerprint)
            onSnapshotChange(snapshot)
            onLoadingChange(false)
            refreshTask = nil
        }
    }
}
