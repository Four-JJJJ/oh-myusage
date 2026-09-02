import OhMyUsageDomain
import OhMyUsageApplication
import Foundation
import OhMyUsageProviders

@MainActor
final class AppProviderRefreshCoordinator {
    typealias ProviderStateGetter = @MainActor () -> ProviderStateStore
    typealias ProviderStateSetter = @MainActor (ProviderStateStore) -> Void
    typealias BeforeRefreshAction = @MainActor (_ descriptor: ProviderDescriptor) -> Void
    typealias SnapshotTransformAction = @MainActor (_ descriptor: ProviderDescriptor, _ fetched: UsageSnapshot) -> UsageSnapshot
    typealias PostOfficialRefreshAction = @MainActor (_ descriptor: ProviderDescriptor, _ forceRefresh: Bool) async -> Void
    typealias PersistBaselineEntriesAction = @MainActor (_ entries: [String: ThirdPartyBalanceBaselineTracker.Entry]) -> Void
    /// Persists the latest main snapshot for a provider after a successful refresh
    /// (doc §8.2). Implementations must not block the refresh path.
    typealias PersistSnapshotAction = @MainActor (_ descriptor: ProviderDescriptor, _ snapshot: UsageSnapshot) -> Void
    typealias AfterRefreshAction = @MainActor () -> Void
    typealias StatusBarNotifyAction = @MainActor () -> Void
    typealias TextProvider = @MainActor (_ key: L10nKey) -> String
    typealias LocalizedTextProvider = @MainActor (_ zhHans: String, _ en: String) -> String
    typealias LanguageProvider = @MainActor () -> AppLanguage
    typealias SnapshotBounder = @MainActor (_ snapshot: UsageSnapshot) -> UsageSnapshot
    /// Injectable network seam (doc §9.5). Defaults to always-online; the real
    /// `NWPathMonitor` wiring is owned by the composition layer.
    typealias IsNetworkOnlineProvider = @Sendable () -> Bool

    private let providerFactory: any ProviderFactorying
    private let notifications: NotificationService
    private var inFlightRefreshTasks: [String: Task<Void, Never>] = [:]
    private let isNetworkOnline: IsNetworkOnlineProvider
    private let fetchPlanRegistry = ProviderFetchPlanRegistry()
    /// Upper bound on concurrently executing provider refreshes (doc §9.3).
    private var maxConcurrentRefreshes: Int
    private var activeRefreshSlotCount = 0
    private struct RefreshSlotWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var waitingRefreshSlotContinuations: [RefreshSlotWaiter] = []

    init(
        providerFactory: any ProviderFactorying,
        notifications: NotificationService,
        isNetworkOnline: @escaping IsNetworkOnlineProvider = { true },
        maxConcurrentRefreshes: Int = 2
    ) {
        self.providerFactory = providerFactory
        self.notifications = notifications
        self.isNetworkOnline = isNetworkOnline
        self.maxConcurrentRefreshes = max(1, maxConcurrentRefreshes)
    }

    /// Refreshes the configured concurrency cap (follows the active resource
    /// mode's `maxConcurrentRefreshes`).
    func updateMaxConcurrentRefreshes(_ value: Int) {
        maxConcurrentRefreshes = max(1, value)
    }

    /// Global concurrency gate (doc §9.3). All provider refresh paths funnel
    /// through `runExclusiveRefresh`, so acquiring a slot here caps every
    /// caller (poll, manual, displayed, scope fan-out). Nothing in a refresh
    /// action re-enters `runExclusiveRefresh`, so a waiting-based gate cannot
    /// deadlock.
    private func acquireRefreshSlot() async -> Bool {
        guard !Task.isCancelled else { return false }
        if activeRefreshSlotCount < maxConcurrentRefreshes {
            activeRefreshSlotCount += 1
            return true
        }
        let waiterID = UUID()
        // 槽位由释放方直接移交（release 不递减），被取消的等待者返回 false。
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waitingRefreshSlotContinuations.append(
                    RefreshSlotWaiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelRefreshSlotWaiter(id: waiterID)
            }
        }
    }

    private func cancelRefreshSlotWaiter(id: UUID) {
        guard let index = waitingRefreshSlotContinuations.firstIndex(where: { $0.id == id }) else {
            return
        }
        waitingRefreshSlotContinuations.remove(at: index).continuation.resume(returning: false)
    }

    private func releaseRefreshSlot() {
        if !waitingRefreshSlotContinuations.isEmpty {
            // 直接把槽位移交给队首等待者，保持计数不变。
            waitingRefreshSlotContinuations.removeFirst().continuation.resume(returning: true)
            return
        }
        activeRefreshSlotCount = max(0, activeRefreshSlotCount - 1)
    }

    /// Per-provider in-flight gate shared by poll / refreshNow / displayed / local-session paths
    /// (all enter via `refreshProvider`).
    ///
    /// Strategy: if a refresh for `providerID` is already running, await that task and return
    /// without starting another fetch — including when the new caller requested `forceRefresh`.
    /// No cancel+rerun; joiners reuse the in-flight result. The global concurrency cap is
    /// enforced around the action body; joiners waiting on `existing.value` hold no slot.
    func runExclusiveRefresh(
        providerID: String,
        action: @escaping @MainActor () async -> Void
    ) async {
        if let existing = inFlightRefreshTasks[providerID] {
            await existing.value
            return
        }

        let task = Task { @MainActor in
            guard await self.acquireRefreshSlot() else { return }
            defer { self.releaseRefreshSlot() }
            guard !Task.isCancelled else { return }
            await action()
        }
        inFlightRefreshTasks[providerID] = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if inFlightRefreshTasks[providerID] == task {
            inFlightRefreshTasks.removeValue(forKey: providerID)
        }
    }

    func refreshScheduleDescriptors(from providers: [ProviderDescriptor]) -> [ProviderRefreshScheduleDescriptor] {
        providers.map(refreshScheduleDescriptor(for:))
    }

    func refreshScheduleDescriptor(for provider: ProviderDescriptor) -> ProviderRefreshScheduleDescriptor {
        let localSessionWatchKind: LocalSessionWatchKind?
        if provider.enabled && provider.family == .official {
            switch provider.type {
            case .codex:
                localSessionWatchKind = .codex
            case .claude:
                localSessionWatchKind = .claude
            default:
                localSessionWatchKind = nil
            }
        } else {
            localSessionWatchKind = nil
        }

        // Fetch-plan TTLs (doc §8.3/§9.3) ride on the descriptor so the
        // scheduler can combine user cadence, plan floors, and visibility.
        let plan = fetchPlanRegistry.plan(for: provider.type)
        return ProviderRefreshScheduleDescriptor(
            id: provider.id,
            isEnabled: provider.enabled,
            pollIntervalSec: provider.pollIntervalSec,
            activeTTLSeconds: TimeInterval(plan.activeTTL),
            backgroundTTLSeconds: TimeInterval(plan.backgroundTTL),
            localSessionWatchKind: localSessionWatchKind
        )
    }

    /// Resolves a `RefreshScope` (doc §9.4) to enabled provider IDs.
    ///
    /// `.visible` follows the current menu bar panel population,
    /// `.selected(providerID)` covers a single settings-page provider, and
    /// `.all` covers every enabled provider. IDs are deduplicated and keep
    /// config order.
    nonisolated static func enabledProviderIDs(
        for scope: RefreshScope,
        providers: [ProviderDescriptor],
        visibleProviderIDs: Set<String>
    ) -> [String] {
        var seenIDs: Set<String> = []
        var resolvedIDs: [String] = []

        func appendIfEnabled(_ descriptor: ProviderDescriptor) {
            guard descriptor.enabled, seenIDs.insert(descriptor.id).inserted else { return }
            resolvedIDs.append(descriptor.id)
        }

        switch scope {
        case .visible:
            for descriptor in providers where visibleProviderIDs.contains(descriptor.id) {
                appendIfEnabled(descriptor)
            }
        case .selected(let providerID):
            for descriptor in providers where descriptor.id == providerID {
                appendIfEnabled(descriptor)
            }
        case .all:
            for descriptor in providers {
                appendIfEnabled(descriptor)
            }
        }
        return resolvedIDs
    }

    func refreshDisplayedStatusBarProviders(
        providers: [ProviderDescriptor],
        forceRefresh: Bool,
        refreshAction: @escaping @MainActor (_ descriptor: ProviderDescriptor, _ forceRefresh: Bool) async -> Void
    ) {
        var providersToRefresh: [ProviderDescriptor] = []
        var seenProviderIDs: Set<String> = []
        for provider in providers where provider.enabled {
            if seenProviderIDs.insert(provider.id).inserted {
                providersToRefresh.append(provider)
            }
        }
        guard !providersToRefresh.isEmpty else { return }

        Task { @MainActor in
            var tasks: [Task<Void, Never>] = []
            tasks.reserveCapacity(providersToRefresh.count)
            for descriptor in providersToRefresh {
                tasks.append(Task { @MainActor in
                    await refreshAction(descriptor, forceRefresh)
                })
            }
            for task in tasks {
                await task.value
            }
        }
    }

    func refreshProvider(
        descriptor: ProviderDescriptor,
        forceRefresh: Bool,
        getState: @escaping ProviderStateGetter,
        setState: @escaping ProviderStateSetter,
        beforeRefresh: @escaping BeforeRefreshAction,
        transformFetchedSnapshot: @escaping SnapshotTransformAction,
        postOfficialRefresh: @escaping PostOfficialRefreshAction,
        persistBaselineEntries: @escaping PersistBaselineEntriesAction,
        persistSnapshot: @escaping PersistSnapshotAction = { _, _ in },
        afterRefresh: @escaping AfterRefreshAction,
        notifyStatusBarDisplayConfigChanged: @escaping StatusBarNotifyAction,
        text: @escaping TextProvider,
        localizedText: @escaping LocalizedTextProvider,
        language: @escaping LanguageProvider,
        boundedSnapshot: @escaping SnapshotBounder
    ) async {
        await runExclusiveRefresh(providerID: descriptor.id) {
            await self.performRefreshProvider(
                descriptor: descriptor,
                forceRefresh: forceRefresh,
                getState: getState,
                setState: setState,
                beforeRefresh: beforeRefresh,
                transformFetchedSnapshot: transformFetchedSnapshot,
                postOfficialRefresh: postOfficialRefresh,
                persistBaselineEntries: persistBaselineEntries,
                persistSnapshot: persistSnapshot,
                afterRefresh: afterRefresh,
                notifyStatusBarDisplayConfigChanged: notifyStatusBarDisplayConfigChanged,
                text: text,
                localizedText: localizedText,
                language: language,
                boundedSnapshot: boundedSnapshot
            )
        }
    }

    private func performRefreshProvider(
        descriptor: ProviderDescriptor,
        forceRefresh: Bool,
        getState: @escaping ProviderStateGetter,
        setState: @escaping ProviderStateSetter,
        beforeRefresh: @escaping BeforeRefreshAction,
        transformFetchedSnapshot: @escaping SnapshotTransformAction,
        postOfficialRefresh: @escaping PostOfficialRefreshAction,
        persistBaselineEntries: @escaping PersistBaselineEntriesAction,
        persistSnapshot: @escaping PersistSnapshotAction,
        afterRefresh: @escaping AfterRefreshAction,
        notifyStatusBarDisplayConfigChanged: @escaping StatusBarNotifyAction,
        text: @escaping TextProvider,
        localizedText: @escaping LocalizedTextProvider,
        language: @escaping LanguageProvider,
        boundedSnapshot: @escaping SnapshotBounder
    ) async {
        defer { afterRefresh() }
        beforeRefresh(descriptor)
        let provider = providerFactory.makeProvider(for: descriptor)

        do {
            let fetched = try await fetchProviderSnapshot(using: provider, forceRefresh: forceRefresh)
            let snapshot = transformFetchedSnapshot(descriptor, fetched)
            let bounded = boundedSnapshot(snapshot)

            mutateState(getState, setState) { state in
                state.snapshots[descriptor.id] = bounded
                if descriptor.family == .thirdParty {
                    _ = state.thirdPartyBalanceBaselineTracker.record(
                        remaining: Self.resolvedThirdPartyRemainingForBaseline(
                            remaining: snapshot.remaining,
                            used: snapshot.used,
                            limit: snapshot.limit
                        ),
                        for: descriptor.id,
                        at: snapshot.updatedAt
                    )
                }
                state.errors.removeValue(forKey: descriptor.id)
                state.consecutiveFailures[descriptor.id] = 0
                state.lastUpdatedAt = Date()
                state.activeAlerts.remove("fail:\(descriptor.id)")
                state.activeAlerts.remove("auth:\(descriptor.id)")
            }
            if descriptor.family == .thirdParty {
                persistBaselineEntries(getState().thirdPartyBalanceBaselineTracker.snapshotEntries())
            }
            persistSnapshot(descriptor, bounded)
            notifyStatusBarDisplayConfigChanged()
            if descriptor.family == .official {
                await postOfficialRefresh(descriptor, forceRefresh)
            }

            handleLowRemainingAlerts(
                for: descriptor,
                snapshot: snapshot,
                getState: getState,
                setState: setState,
                text: text,
                localizedText: localizedText,
                language: language
            )
        } catch {
            if Self.isCancellationError(error) || Task.isCancelled {
                return
            }

            if Self.isRateLimitedError(error),
               let updatedSnapshot = cachedRateLimitedSnapshot(
                    for: descriptor.id,
                    error: error,
                    getState: getState,
                    boundedSnapshot: boundedSnapshot
               ) {
                mutateState(getState, setState) { state in
                    state.snapshots[descriptor.id] = updatedSnapshot
                    state.errors.removeValue(forKey: descriptor.id)
                    state.consecutiveFailures[descriptor.id] = 0
                    state.lastUpdatedAt = Date()
                }
                notifyStatusBarDisplayConfigChanged()
                return
            }

            let health = Self.classifyFetchHealth(error)
            let message = error.localizedDescription
            let shouldRefreshStatusBarDisplay = mutateState(getState, setState) { state -> Bool in
                state.errors[descriptor.id] = message
                state.consecutiveFailures[descriptor.id, default: 0] += 1

                if descriptor.isRelay || descriptor.family == .official {
                    if var previous = state.snapshots[descriptor.id] {
                        previous.fetchHealth = health
                        previous.valueFreshness = .cachedFallback
                        previous.updatedAt = Date()
                        previous.diagnosticCode = Self.diagnosticCode(for: health)
                        previous.note = RuntimeBoundedState.appendSnapshotNote(
                            existing: previous.note,
                            appending: message
                        )
                        state.snapshots[descriptor.id] = boundedSnapshot(previous)
                        return true
                    }
                    if let emptySnapshot = Self.emptySnapshotForFetchFailure(
                        descriptor: descriptor,
                        health: health,
                        message: message
                    ) {
                        state.snapshots[descriptor.id] = boundedSnapshot(emptySnapshot)
                        return true
                    }
                }
                return false
            }

            if shouldRefreshStatusBarDisplay {
                notifyStatusBarDisplayConfigChanged()
            }

            let state = getState()
            let failureCount = state.consecutiveFailures[descriptor.id, default: 0]
            if AlertEngine.shouldAlertFailures(consecutiveFailures: failureCount, rule: descriptor.threshold) {
                let key = "fail:\(descriptor.id)"
                if !state.activeAlerts.contains(key) {
                    notifications.notify(
                        title: text(.providerUnreachable),
                        body: Localizer.providerFailedBody(
                            providerName: descriptor.name,
                            failures: failureCount,
                            language: language()
                        ),
                        identifier: key
                    )
                    _ = mutateState(getState, setState) { state in
                        state.activeAlerts.insert(key)
                    }
                }
            }

            if descriptor.threshold.notifyOnAuthError,
               AlertEngine.isAuthError(error) {
                let key = "auth:\(descriptor.id)"
                if !getState().activeAlerts.contains(key) {
                    notifications.notify(
                        title: text(.authError),
                        body: Localizer.authErrorBody(
                            providerName: descriptor.name,
                            language: language()
                        ),
                        identifier: key
                    )
                    _ = mutateState(getState, setState) { state in
                        state.activeAlerts.insert(key)
                    }
                }
            }
        }
    }

    private func cachedRateLimitedSnapshot(
        for providerID: String,
        error: Error,
        getState: ProviderStateGetter,
        boundedSnapshot: SnapshotBounder
    ) -> UsageSnapshot? {
        guard var previous = getState().snapshots[providerID] else { return nil }
        previous.status = .warning
        previous.fetchHealth = .rateLimited
        previous.valueFreshness = .cachedFallback
        previous.updatedAt = Date()
        previous.diagnosticCode = "rate-limited"
        previous.note = RuntimeBoundedState.appendSnapshotNote(
            existing: previous.note,
            appending: "rate limited, showing cached value"
        )
        return boundedSnapshot(previous)
    }

    private func fetchProviderSnapshot(
        using provider: any UsageProvider,
        forceRefresh: Bool
    ) async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
            try await provider.fetch(forceRefresh: forceRefresh)
        }.value
    }

    private func handleLowRemainingAlerts(
        for descriptor: ProviderDescriptor,
        snapshot: UsageSnapshot,
        getState: ProviderStateGetter,
        setState: ProviderStateSetter,
        text: TextProvider,
        localizedText: LocalizedTextProvider,
        language: LanguageProvider
    ) {
        let genericKey = "low:\(descriptor.id)"
        let displaysUsedQuota = descriptor.displaysUsedQuota && (snapshot.used != nil || !snapshot.quotaWindows.isEmpty)
        let lowWindows = AlertEngine.lowQuotaWindows(
            snapshot: snapshot,
            rule: descriptor.threshold,
            displaysUsedQuota: displaysUsedQuota
        )

        if !lowWindows.isEmpty {
            mutateState(getState, setState) { state in
                state.activeAlerts.remove(genericKey)
                let activeWindowKeys = Set(lowWindows.map { "low:\(descriptor.id):\($0.id)" })
                for existingKey in state.activeAlerts.filter({ $0.hasPrefix("low:\(descriptor.id):") && !activeWindowKeys.contains($0) }) {
                    state.activeAlerts.remove(existingKey)
                }
            }

            for window in lowWindows {
                let key = "low:\(descriptor.id):\(window.id)"
                if !getState().activeAlerts.contains(key) {
                    notifications.notify(
                        title: text(.lowBalanceWarning),
                        body: Localizer.lowQuotaWindowBody(
                            providerName: descriptor.name,
                            windowTitle: window.title,
                            remaining: String(
                                Int((displaysUsedQuota ? window.usedPercent : window.remainingPercent).rounded())
                            ),
                            language: language(),
                            displaysUsedQuota: displaysUsedQuota
                        ),
                        identifier: key
                    )
                    _ = mutateState(getState, setState) { state in
                        state.activeAlerts.insert(key)
                    }
                }
            }
            return
        }

        mutateState(getState, setState) { state in
            for existingKey in state.activeAlerts.filter({ $0.hasPrefix("low:\(descriptor.id):") }) {
                state.activeAlerts.remove(existingKey)
            }
        }

        if AlertEngine.shouldAlertLowRemaining(
            snapshot: snapshot,
            rule: descriptor.threshold,
            displaysUsedQuota: displaysUsedQuota
        ) {
            if !getState().activeAlerts.contains(genericKey) {
                notifications.notify(
                    title: text(.lowBalanceWarning),
                    body: Localizer.lowBalanceBody(
                        providerName: descriptor.name,
                        remaining: format(
                            displaysUsedQuota ? (snapshot.used ?? snapshot.remaining) : snapshot.remaining,
                            text: text
                        ),
                        unit: snapshot.unit,
                        language: language(),
                        displaysUsedQuota: displaysUsedQuota
                    ),
                    identifier: genericKey
                )
                _ = mutateState(getState, setState) { state in
                    state.activeAlerts.insert(genericKey)
                }
            }
        } else {
            _ = mutateState(getState, setState) { state in
                state.activeAlerts.remove(genericKey)
            }
        }
    }

    private func format(_ value: Double?, text: TextProvider) -> String {
        guard let value else { return text(.unlimited) }
        return String(format: "%.2f", value)
    }

    private func mutateState(
        _ getState: ProviderStateGetter,
        _ setState: ProviderStateSetter,
        _ mutate: (inout ProviderStateStore) -> Void
    ) {
        var state = getState()
        mutate(&state)
        setState(state)
    }

    private func mutateState<T>(
        _ getState: ProviderStateGetter,
        _ setState: ProviderStateSetter,
        _ mutate: (inout ProviderStateStore) -> T
    ) -> T {
        var state = getState()
        let output = mutate(&state)
        setState(state)
        return output
    }
}

extension AppProviderRefreshCoordinator {
    /// Snapshot age beyond which a startup refresh is allowed, even if the
    /// provider's own poll interval is very short (doc §8.2: startup only
    /// refreshes displayed providers whose data is already stale).
    nonisolated static let startupRefreshStalenessFloorSeconds: TimeInterval = 60

    /// Startup / menu-open refresh scope: only displayed providers whose
    /// snapshot is missing, empty, or older than their staleness window.
    /// `extraStalenessSecondsByID` lets callers widen the staleness window per
    /// provider (e.g. the fetch plan's `activeTTL` for menu-open refreshes).
    func displayedProvidersForStartupRefresh(
        providers: [ProviderDescriptor],
        snapshots: [String: UsageSnapshot],
        now: Date = Date(),
        extraStalenessSecondsByID: [String: TimeInterval] = [:]
    ) -> [ProviderDescriptor] {
        providers.filter { descriptor in
            Self.needsStartupRefresh(
                descriptor: descriptor,
                snapshot: snapshots[descriptor.id],
                now: now,
                extraStalenessSeconds: extraStalenessSecondsByID[descriptor.id] ?? 0
            )
        }
    }

    nonisolated static func needsStartupRefresh(
        descriptor: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        now: Date,
        extraStalenessSeconds: TimeInterval = 0
    ) -> Bool {
        guard descriptor.enabled else { return false }
        guard let snapshot else { return true }
        if snapshot.valueFreshness == .empty { return true }
        let stalenessSeconds = max(
            TimeInterval(max(descriptor.pollIntervalSec, 1)),
            startupRefreshStalenessFloorSeconds,
            max(0, extraStalenessSeconds)
        )
        return now.timeIntervalSince(snapshot.updatedAt) >= stalenessSeconds
    }

    nonisolated static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    nonisolated static func isRateLimitedError(_ error: Error) -> Bool {
        if let providerError = error as? ProviderError,
           case .rateLimited = providerError {
            return true
        }

        return isRateLimitedDiagnosticMessage(error.localizedDescription)
    }

    nonisolated static func isRateLimitedDiagnosticMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("rate limited") || lowered.contains("429")
    }

    nonisolated static func classifyFetchHealth(_ error: Error) -> FetchHealth {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .missingCredential, .unauthorized, .unauthorizedDetail:
                return .authExpired
            case .rateLimited:
                return .rateLimited
            case .invalidResponse:
                return .endpointMisconfigured
            case .timeout:
                return .unreachable
            case .commandFailed, .unavailable:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorUserAuthenticationRequired,
                 NSURLErrorNoPermissionsToReadFile:
                return .authExpired
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDNSLookupFailed:
                return .unreachable
            default:
                break
            }
        }

        let description = nsError.localizedDescription.lowercased()
        if description.contains("unauthorized") || description.contains("expired") || description.contains("forbidden") {
            return .authExpired
        }
        if description.contains("rate limited") || description.contains("429") {
            return .rateLimited
        }
        if description.contains("invalid") || description.contains("missing") || description.contains("path") || description.contains("base url") {
            return .endpointMisconfigured
        }
        return .unreachable
    }

    nonisolated static func diagnosticCode(for health: FetchHealth) -> String {
        switch health {
        case .ok:
            return "ok"
        case .authExpired:
            return "auth-expired"
        case .rateLimited:
            return "rate-limited"
        case .endpointMisconfigured:
            return "endpoint-misconfigured"
        case .unreachable:
            return "unreachable"
        }
    }

    nonisolated static func emptySnapshotForFetchFailure(
        descriptor: ProviderDescriptor,
        health: FetchHealth,
        message: String,
        now: Date = Date()
    ) -> UsageSnapshot? {
        if descriptor.isRelay {
            return UsageSnapshot(
                source: descriptor.id,
                status: .error,
                fetchHealth: health,
                valueFreshness: .empty,
                remaining: nil,
                used: nil,
                limit: nil,
                unit: descriptor.relayViewConfig?.accountBalance?.unit ?? "quota",
                updatedAt: now,
                note: message,
                sourceLabel: "Third-Party",
                accountLabel: nil,
                authSourceLabel: nil,
                diagnosticCode: diagnosticCode(for: health)
            )
        }

        guard descriptor.family == .official else {
            return nil
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: .error,
            fetchHealth: health,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: now,
            note: message,
            sourceLabel: "Official",
            accountLabel: nil,
            authSourceLabel: nil,
            diagnosticCode: diagnosticCode(for: health)
        )
    }

    nonisolated static func resolvedThirdPartyRemainingForBaseline(
        remaining: Double?,
        used: Double?,
        limit: Double?
    ) -> Double? {
        ThirdPartyBalanceBaselineTracker.resolvedRemainingForBaseline(
            remaining: remaining,
            used: used,
            limit: limit
        )
    }
}
