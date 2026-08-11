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
    package var localSessionWatchKind: LocalSessionWatchKind?

    package init(
        id: String,
        isEnabled: Bool,
        pollIntervalSec: Int,
        localSessionWatchKind: LocalSessionWatchKind? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.pollIntervalSec = pollIntervalSec
        self.localSessionWatchKind = localSessionWatchKind
    }
}

package struct ProviderRefreshSchedulerConfig: Equatable, Sendable {
    package var backgroundProviderPollIntervalSeconds: Int
    package var localSessionSignalActiveSleepSeconds: TimeInterval
    package var localSessionSignalIdleSleepSeconds: TimeInterval
    package var inFlightProviderSleepSeconds: TimeInterval

    package init(
        backgroundProviderPollIntervalSeconds: Int,
        localSessionSignalActiveSleepSeconds: TimeInterval,
        localSessionSignalIdleSleepSeconds: TimeInterval,
        inFlightProviderSleepSeconds: TimeInterval = 5
    ) {
        self.backgroundProviderPollIntervalSeconds = backgroundProviderPollIntervalSeconds
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
    package typealias RefreshAction = @MainActor (_ providerID: String, _ forceRefresh: Bool) async -> Void
    package typealias SleepAction = @Sendable (_ seconds: TimeInterval) async throws -> Void

    private let descriptorProvider: DescriptorProvider
    private let providersProvider: ProvidersProvider
    private let activeProviderIDsProvider: ActiveProviderIDsProvider
    private let failureCountProvider: FailureCountProvider
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

            for providerID in dueProviderIDs {
                guard !Task.isCancelled else { return }
                guard let descriptor = descriptorProvider(providerID), descriptor.isEnabled else {
                    nextDueAtStorage.removeValue(forKey: providerID)
                    scheduledProviderIDsStorage.remove(providerID)
                    continue
                }

                startPollRefresh(
                    providerID: providerID,
                    descriptor: descriptor,
                    runID: runID,
                    startedAt: logicalNowStorage
                )
            }

            if dueProviderIDs.isEmpty {
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
            consecutiveFailures: failureCount
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

    private func pollBaseInterval(for descriptor: ProviderRefreshScheduleDescriptor) -> Int {
        let base = max(1, descriptor.pollIntervalSec)
        let activeIDs = activeProviderIDsProvider()
        if activeIDs.isEmpty || activeIDs.contains(descriptor.id) {
            return base
        }
        return max(1, config.backgroundProviderPollIntervalSeconds)
    }
}
