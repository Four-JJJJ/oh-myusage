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

    private weak var host: AppViewModel?
    private var localSessionRefreshCoordinator: LocalSessionRefreshCoordinator?
    private var getState: ProviderStateGetter?
    private var setState: ProviderStateSetter?

    init(
        providerFactory: any ProviderFactorying,
        notifications: NotificationService
    ) {
        self.coordinator = AppProviderRefreshCoordinator(
            providerFactory: providerFactory,
            notifications: notifications
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

    func refreshNow() {
        let host = requireHost()
        refreshScheduler?.refreshNow(
            providers: coordinator.refreshScheduleDescriptors(from: host.config.providers)
        )
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

    private func makeRefreshScheduler() -> ProviderRefreshScheduler {
        let localSessionRefreshCoordinator = requireLocalSessionRefreshCoordinator()
        let schedulerConfig = requireHost().config.resourceMode.refreshSchedulerConfig
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

    func refreshNow() {
        providerRefreshModel.refreshNow()
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
