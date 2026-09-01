import Foundation

package enum LocalSessionWatchKind: Equatable, Sendable {
    case codex
    case claude
}

package protocol LocalSessionCompletionSignalSource {
    func latestCodexCompletionAt() -> Date?
    func latestClaudeCompletionAt() -> Date?
}

package struct ProviderRefreshScheduleDescriptor: Equatable, Sendable {
    package var id: String
    package var isEnabled: Bool
    package var pollIntervalSec: Int
    /// Fetch-plan active TTL (doc §8.3/§9.3): a visible provider is never
    /// polled more aggressively than this. `nil` means no plan floor.
    package var activeTTLSeconds: TimeInterval?
    /// Fetch-plan background TTL (doc §8.3/§9.3): the minimum spacing between
    /// background scheduler refreshes while the provider is not visible.
    package var backgroundTTLSeconds: TimeInterval?
    package var localSessionWatchKind: LocalSessionWatchKind?

    package init(
        id: String,
        isEnabled: Bool,
        pollIntervalSec: Int,
        activeTTLSeconds: TimeInterval? = nil,
        backgroundTTLSeconds: TimeInterval? = nil,
        localSessionWatchKind: LocalSessionWatchKind? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.pollIntervalSec = pollIntervalSec
        self.activeTTLSeconds = activeTTLSeconds
        self.backgroundTTLSeconds = backgroundTTLSeconds
        self.localSessionWatchKind = localSessionWatchKind
    }
}

package struct ProviderRefreshSchedulerConfig: Equatable, Sendable {
    package var backgroundProviderPollIntervalSeconds: Int
    /// Poll floor for visible (active) providers (doc §9.3). `0` disables the
    /// scheduler-level active floor; user config and plan activeTTL still apply.
    package var activeProviderPollIntervalSeconds: Int
    /// Upper bound on concurrent refresh executions (doc §9.3). Due items
    /// beyond the cap are deferred to a later cycle, never dropped.
    package var maxConcurrentRefreshes: Int
    package var localSessionSignalActiveSleepSeconds: TimeInterval
    package var localSessionSignalIdleSleepSeconds: TimeInterval
    package var inFlightProviderSleepSeconds: TimeInterval

    package init(
        backgroundProviderPollIntervalSeconds: Int,
        activeProviderPollIntervalSeconds: Int = 180,
        maxConcurrentRefreshes: Int = 2,
        localSessionSignalActiveSleepSeconds: TimeInterval,
        localSessionSignalIdleSleepSeconds: TimeInterval,
        inFlightProviderSleepSeconds: TimeInterval = 5
    ) {
        self.backgroundProviderPollIntervalSeconds = backgroundProviderPollIntervalSeconds
        self.activeProviderPollIntervalSeconds = max(0, activeProviderPollIntervalSeconds)
        self.maxConcurrentRefreshes = max(1, maxConcurrentRefreshes)
        self.localSessionSignalActiveSleepSeconds = localSessionSignalActiveSleepSeconds
        self.localSessionSignalIdleSleepSeconds = localSessionSignalIdleSleepSeconds
        self.inFlightProviderSleepSeconds = max(1, inFlightProviderSleepSeconds)
    }
}

package final class LocalSessionRefreshCoordinator {
    private let signalSource: LocalSessionCompletionSignalSource
    private let minimumEventRefreshGap: TimeInterval
    private let nowProvider: () -> Date
    private var lastProcessedSignalAt: [String: Date] = [:]
    private var lastTriggeredRefreshAt: [String: Date] = [:]

    package init(
        signalSource: LocalSessionCompletionSignalSource,
        minimumEventRefreshGap: TimeInterval = 15,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.signalSource = signalSource
        self.minimumEventRefreshGap = max(1, minimumEventRefreshGap)
        self.nowProvider = nowProvider
    }

    package func refreshCandidates(from providers: [ProviderRefreshScheduleDescriptor]) -> [String] {
        let now = nowProvider()
        var output: [String] = []

        for descriptor in providers where descriptor.isEnabled {
            guard let signalAt = latestSignal(for: descriptor.localSessionWatchKind) else {
                continue
            }
            let lastProcessed = lastProcessedSignalAt[descriptor.id] ?? .distantPast
            guard signalAt > lastProcessed else {
                continue
            }
            if let lastTriggered = lastTriggeredRefreshAt[descriptor.id],
               now.timeIntervalSince(lastTriggered) < minimumEventRefreshGap {
                continue
            }

            lastProcessedSignalAt[descriptor.id] = signalAt
            lastTriggeredRefreshAt[descriptor.id] = now
            output.append(descriptor.id)
        }

        return output
    }

    private func latestSignal(for watchKind: LocalSessionWatchKind?) -> Date? {
        switch watchKind {
        case .codex:
            return signalSource.latestCodexCompletionAt()
        case .claude:
            return signalSource.latestClaudeCompletionAt()
        case nil:
            return nil
        }
    }
}

@MainActor
package final class ProviderRefreshScheduler {
    package typealias DescriptorProvider = @MainActor (_ providerID: String) -> ProviderRefreshScheduleDescriptor?
    package typealias ProvidersProvider = @MainActor () -> [ProviderRefreshScheduleDescriptor]
    package typealias ActiveProviderIDsProvider = @MainActor () -> Set<String>
    package typealias FailureCountProvider = @MainActor (_ providerID: String) -> Int
    package typealias IsRateLimitedProvider = @MainActor (_ providerID: String) -> Bool
    package typealias IsNetworkOnlineProvider = @Sendable () -> Bool
    package typealias RefreshAction = @MainActor (_ providerID: String, _ forceRefresh: Bool) async -> Void
    package typealias SleepAction = @Sendable (_ seconds: TimeInterval) async throws -> Void

    private let descriptorProvider: DescriptorProvider
    private let providersProvider: ProvidersProvider
    private let activeProviderIDsProvider: ActiveProviderIDsProvider
    private let failureCountProvider: FailureCountProvider
    private let isRateLimitedProvider: IsRateLimitedProvider
    private let isNetworkOnline: IsNetworkOnlineProvider
    private let refreshAction: RefreshAction
    private let localSessionRefreshCoordinator: LocalSessionRefreshCoordinator
    private let startupJitterProvider: @Sendable () -> TimeInterval
    private let sleepAction: SleepAction
    private let config: ProviderRefreshSchedulerConfig
    private var pollLoopTask: Task<Void, Never>?
    private var pollRunID: UUID?
    private var scheduledProviderIDsStorage: Set<String> = []
    private var providerOrderStorage: [String] = []
    private var nextDueAtStorage: [String: Date] = [:]
    private var inFlightRefreshTasks: [String: Task<Void, Never>] = [:]
    private var logicalNowStorage = Date()
    private var localSessionMonitorTask: Task<Void, Never>?

    package init(
        descriptorProvider: @escaping DescriptorProvider,
        providersProvider: @escaping ProvidersProvider,
        activeProviderIDsProvider: @escaping ActiveProviderIDsProvider = { [] },
        failureCountProvider: @escaping FailureCountProvider,
        isRateLimitedProvider: @escaping IsRateLimitedProvider = { _ in false },
        isNetworkOnline: @escaping IsNetworkOnlineProvider = { true },
        refreshAction: @escaping RefreshAction,
        localSessionRefreshCoordinator: LocalSessionRefreshCoordinator,
        config: ProviderRefreshSchedulerConfig,
        startupJitterProvider: @escaping @Sendable () -> TimeInterval = { Double.random(in: 0...20) },
        sleepAction: @escaping SleepAction = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.descriptorProvider = descriptorProvider
        self.providersProvider = providersProvider
        self.activeProviderIDsProvider = activeProviderIDsProvider
        self.failureCountProvider = failureCountProvider
        self.isRateLimitedProvider = isRateLimitedProvider
        self.isNetworkOnline = isNetworkOnline
        self.refreshAction = refreshAction
        self.localSessionRefreshCoordinator = localSessionRefreshCoordinator
        self.config = config
        self.startupJitterProvider = startupJitterProvider
        self.sleepAction = sleepAction
    }

    package var pollTaskCount: Int {
        scheduledProviderIDsStorage.isEmpty ? 0 : 1
    }

    package var scheduledProviderIDs: Set<String> {
        scheduledProviderIDsStorage
    }

    package func restart(providers: [ProviderRefreshScheduleDescriptor]) {
        stop()

        var seenProviderIDs = Set<String>()
        let enabledProviderIDs = providers.compactMap { provider -> String? in
            guard provider.isEnabled, seenProviderIDs.insert(provider.id).inserted else {
                return nil
            }
            return provider.id
        }

        let runID = UUID()
        let logicalNow = Date()
        pollRunID = runID
        logicalNowStorage = logicalNow
        providerOrderStorage = enabledProviderIDs
        scheduledProviderIDsStorage = Set(enabledProviderIDs)
        nextDueAtStorage = Dictionary(uniqueKeysWithValues: enabledProviderIDs.map { providerID in
            let jitterSeconds = max(0, startupJitterProvider())
            return (providerID, logicalNow.addingTimeInterval(jitterSeconds))
        })
        if !enabledProviderIDs.isEmpty {
            pollLoopTask = Task { @MainActor [weak self] in
                await self?.pollLoop(runID: runID)
            }
        }

        restartLocalSessionSignalMonitor(providers: providers)
    }

    package func stop() {
        pollLoopTask?.cancel()
        pollLoopTask = nil
        pollRunID = nil
        scheduledProviderIDsStorage.removeAll()
        providerOrderStorage.removeAll()
        nextDueAtStorage.removeAll()
        logicalNowStorage = Date()
        inFlightRefreshTasks.values.forEach { $0.cancel() }
        inFlightRefreshTasks.removeAll()
        localSessionMonitorTask?.cancel()
        localSessionMonitorTask = nil
    }

    deinit {
        pollLoopTask?.cancel()
        inFlightRefreshTasks.values.forEach { $0.cancel() }
        localSessionMonitorTask?.cancel()
    }

    package func refreshNow(providers: [ProviderRefreshScheduleDescriptor]) {
        let enabled = providers.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            var tasks: [Task<Void, Never>] = []
            tasks.reserveCapacity(enabled.count)
            for descriptor in enabled {
                let providerID = descriptor.id
                tasks.append(Task { @MainActor in
                    await self.refreshAction(providerID, true)
                })
            }
            for task in tasks {
                await task.value
            }
        }
    }

    private func pollLoop(runID: UUID) async {
        while !Task.isCancelled, pollRunID == runID {
            logicalNowStorage = max(logicalNowStorage, Date())
            providerOrderStorage = providerOrderStorage.filter { providerID in
                guard let descriptor = descriptorProvider(providerID), descriptor.isEnabled else {
                    nextDueAtStorage.removeValue(forKey: providerID)
                    scheduledProviderIDsStorage.remove(providerID)
                    inFlightRefreshTasks[providerID]?.cancel()
                    inFlightRefreshTasks.removeValue(forKey: providerID)
                    return false
                }
                return true
            }
            let activeProviderIDSet = Set(providerOrderStorage)
            nextDueAtStorage = nextDueAtStorage.filter { activeProviderIDSet.contains($0.key) }

            guard !nextDueAtStorage.isEmpty, !providerOrderStorage.isEmpty else {
                pollLoopTask = nil
                return
            }

            guard let earliestDueAt = nextDueAtStorage.values.min() else {
                pollLoopTask = nil
                return
            }

            let sleepSeconds = max(0, earliestDueAt.timeIntervalSince(logicalNowStorage))
            if sleepSeconds > 0 {
                do {
                    try await sleepAction(sleepSeconds)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                logicalNowStorage = max(Date(), earliestDueAt)
                continue
            }

            let dueProviderIDs = providerOrderStorage.filter { providerID in
                guard inFlightRefreshTasks[providerID] == nil,
                      let dueAt = nextDueAtStorage[providerID] else {
                    return false
                }
                return dueAt <= logicalNowStorage
            }

            if !dueProviderIDs.isEmpty, !isNetworkOnline() {
                // Offline seam (doc §9.5): ordinary background refreshes are
                // paused while offline. Due items keep their (already past)
                // due dates and are retried on a later cycle; manual refreshes
                // do not go through this path.
                do {
                    try await sleepAction(config.inFlightProviderSleepSeconds)
                } catch {
                    return
                }
                continue
            }

            let availableRefreshSlots = max(
                0,
                config.maxConcurrentRefreshes - inFlightRefreshTasks.count
            )
            var startedRefreshCount = 0
            var deferredRefreshCount = 0
            for providerID in dueProviderIDs {
                guard !Task.isCancelled else { return }
                guard let descriptor = descriptorProvider(providerID), descriptor.isEnabled else {
                    nextDueAtStorage.removeValue(forKey: providerID)
                    scheduledProviderIDsStorage.remove(providerID)
                    continue
                }
                guard startedRefreshCount < availableRefreshSlots else {
                    // Concurrency cap (doc §9.3): defer the due item to a later
                    // cycle instead of dropping it.
                    deferredRefreshCount += 1
                    continue
                }

                startPollRefresh(
                    providerID: providerID,
                    descriptor: descriptor,
                    runID: runID,
                    startedAt: logicalNowStorage
                )
                startedRefreshCount += 1
            }

            if dueProviderIDs.isEmpty || deferredRefreshCount > 0 {
                do {
                    try await sleepAction(config.inFlightProviderSleepSeconds)
                } catch {
                    return
                }
                continue
            }

            // Let fast refreshes write back their real backoff before the loop computes the next sleep.
            await Task.yield()
            await Task.yield()
        }
    }

    private func startPollRefresh(
        providerID: String,
        descriptor: ProviderRefreshScheduleDescriptor,
        runID: UUID,
        startedAt: Date
    ) {
        guard inFlightRefreshTasks[providerID] == nil else { return }

        let placeholderInterval = TimeInterval(pollBaseInterval(for: descriptor))
        nextDueAtStorage[providerID] = startedAt.addingTimeInterval(placeholderInterval)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshAction(providerID, false)
            finishPollRefresh(providerID: providerID, runID: runID)
        }
        inFlightRefreshTasks[providerID] = task
    }

    private func finishPollRefresh(providerID: String, runID: UUID) {
        guard pollRunID == runID else { return }
        inFlightRefreshTasks.removeValue(forKey: providerID)

        guard let descriptor = descriptorProvider(providerID), descriptor.isEnabled else {
            nextDueAtStorage.removeValue(forKey: providerID)
            scheduledProviderIDsStorage.remove(providerID)
            providerOrderStorage.removeAll { $0 == providerID }
            return
        }

        let failureCount = failureCountProvider(providerID)
        let baseInterval = pollBaseInterval(for: descriptor)
        let delay = TimeInterval(BackoffPolicy.delaySeconds(
            baseInterval: baseInterval,
            consecutiveFailures: failureCount,
            isRateLimited: isRateLimitedProvider(providerID)
        ))
        let refreshedAt = max(logicalNowStorage, Date())
        nextDueAtStorage[providerID] = refreshedAt.addingTimeInterval(delay)
    }

    private func restartLocalSessionSignalMonitor(providers: [ProviderRefreshScheduleDescriptor]) {
        localSessionMonitorTask?.cancel()
        localSessionMonitorTask = nil
        guard !localSessionWatchTargets(from: providers).isEmpty else {
            return
        }
        localSessionMonitorTask = Task { @MainActor [weak self] in
            await self?.localSessionSignalLoop()
        }
    }

    private func localSessionSignalLoop() async {
        var idleCycles = 0
        while !Task.isCancelled {
            let watchTargets = localSessionWatchTargets(from: providersProvider())
            if watchTargets.isEmpty {
                return
            }

            let refreshTargetIDs = localSessionRefreshCoordinator.refreshCandidates(from: watchTargets)
            if refreshTargetIDs.isEmpty {
                idleCycles += 1
            } else {
                idleCycles = 0
                for providerID in refreshTargetIDs {
                    await refreshAction(providerID, false)
                }
            }

            let sleepSeconds = idleCycles <= 2
                ? config.localSessionSignalActiveSleepSeconds
                : config.localSessionSignalIdleSleepSeconds
            do {
                try await sleepAction(sleepSeconds)
            } catch {
                return
            }
        }
    }

    private func localSessionWatchTargets(
        from providers: [ProviderRefreshScheduleDescriptor]
    ) -> [ProviderRefreshScheduleDescriptor] {
        let activeProviderIDs = activeProviderIDsProvider()
        return providers.filter {
            $0.isEnabled
                && $0.localSessionWatchKind != nil
                && activeProviderIDs.contains($0.id)
        }
    }

    /// Final poll interval for a provider (doc §9.3): a combination of the
    /// user's configured cadence, the provider fetch plan TTLs carried on the
    /// descriptor, and the visibility policy. Providers are never forced onto
    /// one shared interval.
    ///
    /// - Visible (active) provider: the user cadence, never more aggressive
    ///   than the plan's `activeTTL` or the scheduler's active floor.
    /// - Background provider: at least the scheduler's background interval,
    ///   the plan's `backgroundTTL` (the minimum background spacing), and the
    ///   user's configured cadence.
    private func pollBaseInterval(for descriptor: ProviderRefreshScheduleDescriptor) -> Int {
        let userInterval = max(1, descriptor.pollIntervalSec)
        let activeProviderIDs = activeProviderIDsProvider()
        let planActiveFloor = planFloorSeconds(descriptor.activeTTLSeconds)
        let planBackgroundFloor = planFloorSeconds(descriptor.backgroundTTLSeconds)
        if activeProviderIDs.isEmpty || activeProviderIDs.contains(descriptor.id) {
            return max(
                userInterval,
                planActiveFloor,
                max(0, config.activeProviderPollIntervalSeconds)
            )
        }
        return max(
            max(1, config.backgroundProviderPollIntervalSeconds),
            planBackgroundFloor,
            userInterval
        )
    }

    private func planFloorSeconds(_ ttlSeconds: TimeInterval?) -> Int {
        guard let ttlSeconds else { return 0 }
        return max(0, Int(ttlSeconds.rounded(.up)))
    }
}
