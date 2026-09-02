import OhMyUsageDomain
import OhMyUsageApplication
import Foundation

/// Owns the ProviderRefresh session boundary: coordinator + refresh scheduler wiring.
///
/// Ownership boundary (deliberately not nested `@Observable`):
/// - Physical `ProviderStateStore` remains on `AppSessionStore` via `AppViewModel` so Observation projections keep working.
/// - **Sole write entry** for provider runtime state is this model (and `AppProviderRefreshCoordinator` through the bound setState).
/// - `AppViewModel` projections (`snapshots` / `errors` / …) are read-only forwards; do not assign them or `providerStateStorage` from outside this model.
@MainActor
final class AppProviderRefreshModel {
    typealias ProviderStateGetter = AppProviderRefreshCoordinator.ProviderStateGetter
    typealias ProviderStateSetter = AppProviderRefreshCoordinator.ProviderStateSetter

    let coordinator: AppProviderRefreshCoordinator
    var refreshScheduler: ProviderRefreshScheduler?

    /// Injectable network seam (doc §9.5). Defaults to always-online; the
    /// real `NWPathMonitor` wiring is owned by the composition layer.
    typealias IsNetworkOnlineProvider = @Sendable () -> Bool
    private let isNetworkOnline: IsNetworkOnlineProvider
    private let fetchPlanRegistry = ProviderFetchPlanRegistry()

    private weak var host: AppViewModel?
    private var localSessionRefreshCoordinator: LocalSessionRefreshCoordinator?
    private var getState: ProviderStateGetter?
    private var setState: ProviderStateSetter?

    init(
        providerFactory: any ProviderFactorying,
        notifications: NotificationService,
        isNetworkOnline: @escaping IsNetworkOnlineProvider = { true }
    ) {
        self.isNetworkOnline = isNetworkOnline
        self.coordinator = AppProviderRefreshCoordinator(
            providerFactory: providerFactory,
            notifications: notifications,
            isNetworkOnline: isNetworkOnline
        )
    }

    /// Bind the host ViewModel, store accessors, and local-session coordinator after they are fully initialized.
    func bind(
        host: AppViewModel,
        localSessionRefreshCoordinator: LocalSessionRefreshCoordinator,
        getState: @escaping ProviderStateGetter,
        setState: @escaping ProviderStateSetter
    ) {
        self.host = host
        self.localSessionRefreshCoordinator = localSessionRefreshCoordinator
        self.getState = getState
        self.setState = setState
    }

    /// Read the current provider runtime state (Observation storage stays on the host).
    var providerState: ProviderStateStore {
        requireGetState()()
    }

    /// Replace the entire provider runtime state. Prefer `mutateProviderState` for partial updates.
    func replaceProviderState(_ state: ProviderStateStore) {
        requireSetState()(state)
    }

    /// Sole supported mutation entry for provider runtime state outside the refresh coordinator.
    func mutateProviderState(_ body: (inout ProviderStateStore) -> Void) {
        var state = requireGetState()()
        body(&state)
        requireSetState()(state)
    }

    func installRefreshScheduler() {
        refreshScheduler?.stop()
        refreshScheduler = makeRefreshScheduler()
    }

    func remakeRefreshScheduler() {
        refreshScheduler?.stop()
        refreshScheduler = makeRefreshScheduler()
    }

    func stopPolling() {
        refreshScheduler?.stop()
    }

    var pollTaskCount: Int {
        refreshScheduler?.pollTaskCount ?? 0
    }

    func restartPolling() {
        let host = requireHost()
        refreshScheduler?.restart(
            providers: coordinator.refreshScheduleDescriptors(from: host.config.providers)
        )
    }

    /// User-initiated refresh with an explicit scope (doc §9.4).
    ///
    /// Manual refreshes bypass snapshot TTLs (`forceRefresh`), but still go
    /// through the per-provider in-flight gate (same-provider requests join
    /// the running task) and the global concurrency cap.
    func refreshNow(scope: RefreshScope = .all) {
        let host = requireHost()
        let providers = host.config.providers
        let visibleProviderIDs = Set(host.statusBarProvidersForDisplay().map(\.id))
        let scopedProviderIDs = AppProviderRefreshCoordinator.enabledProviderIDs(
            for: scope,
            providers: providers,
            visibleProviderIDs: visibleProviderIDs
        )
        let scopedProviders = scopedProviderIDs.compactMap { host.descriptor(for: $0) }
        guard !scopedProviders.isEmpty else { return }
        refreshScheduler?.refreshNow(
            providers: coordinator.refreshScheduleDescriptors(from: scopedProviders)
        )
    }

    /// Menu bar panel opened (doc §9.4): refresh only visible providers, and
    /// only those whose snapshot is already stale for the active tier. The
    /// staleness window is at least the fetch plan's `activeTTL` (plus the
    /// coordinator's user-cadence / 60s floor), so opening the menu never
    /// fans out over fresh or non-visible providers.
    func refreshVisibleProvidersForMenuOpen() {
        let host = requireHost()
        let visibleProviders = host.statusBarProvidersForDisplay()
        guard !visibleProviders.isEmpty else { return }
        guard isNetworkOnline() else { return }

        let extraStalenessSecondsByID = Dictionary(
            uniqueKeysWithValues: visibleProviders.map { descriptor in
                (
                    descriptor.id,
                    TimeInterval(fetchPlanRegistry.plan(for: descriptor.type).activeTTL)
                )
            }
        )
        let staleProviders = coordinator.displayedProvidersForStartupRefresh(
            providers: visibleProviders,
            snapshots: providerState.snapshots,
            extraStalenessSecondsByID: extraStalenessSecondsByID
        )
        guard !staleProviders.isEmpty else { return }
        coordinator.refreshDisplayedStatusBarProviders(
            providers: staleProviders,
            forceRefresh: false
        ) { [weak self] descriptor, forceRefresh in
            await self?.refreshProvider(descriptor, forceRefresh: forceRefresh)
        }
    }

    func refreshDisplayedStatusBarProviders(forceRefresh: Bool = false) {
        let host = requireHost()
        coordinator.refreshDisplayedStatusBarProviders(
            providers: host.statusBarProvidersForDisplay(),
            forceRefresh: forceRefresh
        ) { [weak self] descriptor, forceRefresh in
            await self?.refreshProvider(descriptor, forceRefresh: forceRefresh)
        }
    }

    /// Startup refresh (doc §8.2): only providers currently shown in the menu
    /// bar whose snapshot is missing or already stale. Fresh restored-cache
    /// snapshots are left untouched so startup does not fan out requests.
    func refreshDisplayedStatusBarProvidersForStartup() {
        let host = requireHost()
        let staleProviders = coordinator.displayedProvidersForStartupRefresh(
            providers: host.statusBarProvidersForDisplay(),
            snapshots: providerState.snapshots
        )
        guard !staleProviders.isEmpty else { return }
        coordinator.refreshDisplayedStatusBarProviders(
            providers: staleProviders,
            forceRefresh: false
        ) { [weak self] descriptor, forceRefresh in
            await self?.refreshProvider(descriptor, forceRefresh: forceRefresh)
        }
    }

    func refreshProvider(_ descriptor: ProviderDescriptor, forceRefresh: Bool = false) async {
        let host = requireHost()
        let getState = requireGetState()
        let setState = requireSetState()
        await coordinator.refreshProvider(
            descriptor: descriptor,
            forceRefresh: forceRefresh,
            getState: getState,
            setState: setState,
            beforeRefresh: { descriptor in
                if descriptor.type == .codex, descriptor.family == .official {
                    host.syncCodexProfilesCurrentState()
                }
                if descriptor.type == .claude, descriptor.family == .official {
                    host.syncClaudeProfilesCurrentState()
                }
            },
            transformFetchedSnapshot: { descriptor, fetched in
                if descriptor.type == .codex, descriptor.family == .official {
                    let snapshot = host.markCodexSnapshotActive(fetched)
                    host.codexSlots = host.codexSlotStore.upsertActive(snapshot: snapshot)
                    return snapshot
                }
                if descriptor.type == .claude, descriptor.family == .official {
                    let snapshot = host.markClaudeSnapshotActive(fetched)
                    host.claudeSlots = host.claudeSlotStore.upsertActive(snapshot: snapshot)
                    return snapshot
                }
                return fetched
            },
            postOfficialRefresh: { descriptor, forceRefresh in
                guard descriptor.family == .official else { return }
                if forceRefresh {
                    await host.refreshOfficialProfileCardsAfterManualRefresh(for: descriptor)
                } else {
                    await host.refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for: descriptor)
                }
            },
            persistBaselineEntries: { entries in
                host.thirdPartyBalanceBaselineStore.save(entries)
            },
            persistSnapshot: { [weak self] descriptor, snapshot in
                self?.persistSnapshotToCache(descriptor: descriptor, snapshot: snapshot)
            },
            afterRefresh: {
                host.pruneThirdPartyBalanceBaselines()
            },
            notifyStatusBarDisplayConfigChanged: {
                host.notifyStatusBarDisplayConfigChanged()
            },
            text: { key in
                host.text(key)
            },
            localizedText: { zhHans, en in
                host.localizedText(zhHans, en)
            },
            language: {
                host.config.language
            },
            boundedSnapshot: { snapshot in
                host.boundedSnapshot(snapshot)
            }
        )
    }

    /// Fire-and-forget persistence of the latest main snapshot (doc §8.2).
    /// Runs off the main actor so the refresh path is never blocked by file IO.
    private func persistSnapshotToCache(descriptor: ProviderDescriptor, snapshot: UsageSnapshot) {
        guard let cache = host?.persistedSnapshotCache else { return }
        let providerID = descriptor.id
        let generation = cache.currentGeneration(for: providerID)
        Task.detached(priority: .utility) {
            cache.save(
                providerID: providerID,
                snapshot: snapshot,
                expectedGeneration: generation
            )
        }
    }

    private func makeRefreshScheduler() -> ProviderRefreshScheduler {
        let localSessionRefreshCoordinator = requireLocalSessionRefreshCoordinator()
        let schedulerConfig = requireHost().config.resourceMode.refreshSchedulerConfig
        // The concurrency cap follows the active resource mode (doc §9.3).
        coordinator.updateMaxConcurrentRefreshes(schedulerConfig.maxConcurrentRefreshes)
        return ProviderRefreshScheduler(
            descriptorProvider: { [weak self] providerID in
                guard let self,
                      let host = self.host,
                      let descriptor = host.descriptor(for: providerID) else {
                    return nil
                }
                return self.coordinator.refreshScheduleDescriptor(for: descriptor)
            },
            providersProvider: { [weak self] in
                guard let self, let host = self.host else { return [] }
                return self.coordinator.refreshScheduleDescriptors(from: host.config.providers)
            },
            activeProviderIDsProvider: { [weak self] in
                Set(self?.host?.statusBarProvidersForDisplay().map(\.id) ?? [])
            },
            failureCountProvider: { [weak self] providerID in
                self?.providerState.consecutiveFailures[providerID, default: 0] ?? 0
            },
            // 429 backoff (doc §9.6): the last 429 marks the snapshot's fetch
            // health (cached-snapshot path keeps the failure counter at 0) or
            // leaves a rate-limited error message behind.
            isRateLimitedProvider: { [weak self] providerID in
                guard let self else { return false }
                let state = self.providerState
                if state.snapshots[providerID]?.fetchHealth == .rateLimited {
                    return true
                }
                if let message = state.errors[providerID],
                   AppProviderRefreshCoordinator.isRateLimitedDiagnosticMessage(message) {
                    return true
                }
                return false
            },
            isNetworkOnline: isNetworkOnline,
            refreshAction: { [weak self] providerID, forceRefresh in
                guard let self,
                      let host = self.host,
                      let descriptor = host.descriptor(for: providerID) else {
                    return
                }
                await self.refreshProvider(descriptor, forceRefresh: forceRefresh)
            },
            localSessionRefreshCoordinator: localSessionRefreshCoordinator,
            config: schedulerConfig
        )
    }

    private func requireHost() -> AppViewModel {
        guard let host else {
            preconditionFailure("AppProviderRefreshModel.bind must be called before use")
        }
        return host
    }

    private func requireLocalSessionRefreshCoordinator() -> LocalSessionRefreshCoordinator {
        guard let localSessionRefreshCoordinator else {
            preconditionFailure("AppProviderRefreshModel.bind must be called before use")
        }
        return localSessionRefreshCoordinator
    }

    private func requireGetState() -> ProviderStateGetter {
        guard let getState else {
            preconditionFailure("AppProviderRefreshModel.bind must be called before use")
        }
        return getState
    }

    private func requireSetState() -> ProviderStateSetter {
        guard let setState else {
            preconditionFailure("AppProviderRefreshModel.bind must be called before use")
        }
        return setState
    }
}

extension AppViewModel {
    func restartPolling() {
        providerRefreshModel.restartPolling()
    }

    /// Refresh with an explicit scope (doc §9.4). The default `.all` preserves
    /// the existing "refresh every enabled provider" behavior for callers that
    /// do not pass a scope.
    func refreshNow(scope: RefreshScope = .all) {
        providerRefreshModel.refreshNow(scope: scope)
    }

    /// Settings provider-detail refresh (doc §9.4): refresh a single selected
    /// provider, bypassing snapshot TTLs. Joins the in-flight task when the
    /// provider is already refreshing.
    func refreshSelectedProvider(_ providerID: String) async {
        guard let descriptor = descriptor(for: providerID) else { return }
        await providerRefreshModel.refreshProvider(descriptor, forceRefresh: true)
    }

    func refreshProvider(_ descriptor: ProviderDescriptor, forceRefresh: Bool = false) async {
        await providerRefreshModel.refreshProvider(descriptor, forceRefresh: forceRefresh)
    }

    nonisolated static func diagnosticCode(for health: FetchHealth) -> String {
        AppProviderRefreshCoordinator.diagnosticCode(for: health)
    }

    nonisolated static func emptySnapshotForFetchFailure(
        descriptor: ProviderDescriptor,
        health: FetchHealth,
        message: String,
        now: Date = Date()
    ) -> UsageSnapshot? {
        AppProviderRefreshCoordinator.emptySnapshotForFetchFailure(
            descriptor: descriptor,
            health: health,
            message: message,
            now: now
        )
    }

    nonisolated static func resolvedThirdPartyRemainingForBaseline(
        remaining: Double?,
        used: Double?,
        limit: Double?
    ) -> Double? {
        AppProviderRefreshCoordinator.resolvedThirdPartyRemainingForBaseline(
            remaining: remaining,
            used: used,
            limit: limit
        )
    }
}
