import Foundation

/// Owns the UsageAnalytics session boundary: refresh coordinator wiring.
/// Filter / snapshot / loading projections remain on AppViewModel so Observation keeps working.
@MainActor
final class AppUsageAnalyticsModel {
    typealias FilterGetter = () -> UsageAnalyticsFilter
    typealias SnapshotGetter = () -> UsageAnalyticsSnapshot
    typealias SnapshotSetter = (UsageAnalyticsSnapshot) -> Void
    typealias LoadingSetter = (Bool) -> Void
    typealias ClaudeAllConfigDirsProvider = () -> [String]

    private let coordinator: UsageAnalyticsRefreshCoordinator
    private var getFilter: FilterGetter?
    private var getSnapshot: SnapshotGetter?
    private var setSnapshot: SnapshotSetter?
    private var setLoading: LoadingSetter?
    private var claudeAllConfigDirs: ClaudeAllConfigDirsProvider?

    init(coordinator: UsageAnalyticsRefreshCoordinator = UsageAnalyticsRefreshCoordinator()) {
        self.coordinator = coordinator
    }

    /// Bind host projections and helpers after the ViewModel is fully initialized.
    func bind(
        getFilter: @escaping FilterGetter,
        getSnapshot: @escaping SnapshotGetter,
        setSnapshot: @escaping SnapshotSetter,
        setLoading: @escaping LoadingSetter,
        claudeAllConfigDirs: @escaping ClaudeAllConfigDirsProvider
    ) {
        self.getFilter = getFilter
        self.getSnapshot = getSnapshot
        self.setSnapshot = setSnapshot
        self.setLoading = setLoading
        self.claudeAllConfigDirs = claudeAllConfigDirs
    }

    func refreshUsageAnalytics() {
        refreshUsageAnalyticsIfNeeded(force: true)
    }

    func refreshUsageAnalyticsIfNeeded(force: Bool = false) {
        let filter = requireGetFilter()()
        let snapshot = requireGetSnapshot()()
        coordinator.refreshUsageAnalyticsIfNeeded(
            filter: filter,
            currentSnapshotFilter: snapshot.filter,
            claudeAllConfigDirs: requireClaudeAllConfigDirs()(),
            force: force,
            onSnapshotChange: { snapshot in
                self.requireSetSnapshot()(snapshot)
            },
            onLoadingChange: { isLoading in
                self.requireSetLoading()(isLoading)
            }
        )
    }

    private func requireGetFilter() -> FilterGetter {
        guard let getFilter else {
            preconditionFailure("AppUsageAnalyticsModel.bind must be called before use")
        }
        return getFilter
    }

    private func requireGetSnapshot() -> SnapshotGetter {
        guard let getSnapshot else {
            preconditionFailure("AppUsageAnalyticsModel.bind must be called before use")
        }
        return getSnapshot
    }

    private func requireSetSnapshot() -> SnapshotSetter {
        guard let setSnapshot else {
            preconditionFailure("AppUsageAnalyticsModel.bind must be called before use")
        }
        return setSnapshot
    }

    private func requireSetLoading() -> LoadingSetter {
        guard let setLoading else {
            preconditionFailure("AppUsageAnalyticsModel.bind must be called before use")
        }
        return setLoading
    }

    private func requireClaudeAllConfigDirs() -> ClaudeAllConfigDirsProvider {
        guard let claudeAllConfigDirs else {
            preconditionFailure("AppUsageAnalyticsModel.bind must be called before use")
        }
        return claudeAllConfigDirs
    }
}

extension AppViewModel {
    func refreshUsageAnalytics() {
        usageAnalyticsModel.refreshUsageAnalytics()
    }

    func refreshUsageAnalyticsIfNeeded(force: Bool = false) {
        usageAnalyticsModel.refreshUsageAnalyticsIfNeeded(force: force)
    }
}
