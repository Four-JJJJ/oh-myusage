import Foundation

/// Owns the Update session boundary: coordinator + UpdateStore get/set wiring.
/// Store remains in AppViewModel/sessionStore so Observation projections keep working.
@MainActor
final class AppUpdateModel {
    private let coordinator: AppUpdateCoordinator
    private var getState: AppUpdateCoordinator.UpdateStateGetter?
    private var setState: AppUpdateCoordinator.UpdateStateSetter?
    private var effectiveInstalledVersion: (@MainActor () -> String)?
    private var localizedText: (@MainActor (String, String) -> String)?

    init(
        appUpdateService: any AppUpdateServicing,
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring,
        updateInstallBufferDelaySeconds: TimeInterval,
        updateCheckStatusClearDelaySeconds: TimeInterval
    ) {
        self.coordinator = AppUpdateCoordinator(
            appUpdateService: appUpdateService,
            postUpdateReleaseNotesStore: postUpdateReleaseNotesStore,
            updateInstallBufferDelaySeconds: updateInstallBufferDelaySeconds,
            updateCheckStatusClearDelaySeconds: updateCheckStatusClearDelaySeconds
        )
    }

    /// Bind store access and helpers after the host ViewModel is fully initialized.
    func bind(
        getState: @escaping AppUpdateCoordinator.UpdateStateGetter,
        setState: @escaping AppUpdateCoordinator.UpdateStateSetter,
        effectiveInstalledVersion: @escaping @MainActor () -> String,
        localizedText: @escaping @MainActor (String, String) -> String
    ) {
        self.getState = getState
        self.setState = setState
        self.effectiveInstalledVersion = effectiveInstalledVersion
        self.localizedText = localizedText
    }

    var settingsDisplayState: SettingsUpdateDisplayState {
        coordinator.settingsDisplayState(
            for: requireState(),
            localizedText: requireLocalizedText()
        )
    }

    var menuDisplayState: MenuUpdateDisplayState {
        coordinator.menuDisplayState(
            for: requireState(),
            localizedText: requireLocalizedText()
        )
    }

    var updateActionTitle: String {
        coordinator.updateActionTitle(
            for: requireState(),
            localizedText: requireLocalizedText()
        )
    }

    var updateStatusSummary: String? {
        coordinator.updateStatusSummary(
            for: requireState(),
            localizedText: requireLocalizedText()
        )
    }

    var isUpdateActionEnabled: Bool {
        coordinator.isActionEnabled(for: requireState())
    }

    func checkForAppUpdate(force: Bool = false) {
        let getState = requireGetState()
        let setState = requireSetState()
        coordinator.checkForAppUpdate(
            force: force,
            effectiveInstalledVersion: requireEffectiveInstalledVersion(),
            getState: getState,
            setState: setState
        )
    }

    func openLatestReleaseDownload() {
        performUpdateAction(allowCheckForUpdateFallback: true)
    }

    func performMenuUpdateAction() {
        let state = requireState()
        guard state.availableUpdate != nil || state.preparedUpdate != nil else { return }
        performUpdateAction(allowCheckForUpdateFallback: false)
    }

    private func performUpdateAction(allowCheckForUpdateFallback: Bool) {
        let getState = requireGetState()
        let setState = requireSetState()
        coordinator.performUpdateAction(
            allowCheckForUpdateFallback: allowCheckForUpdateFallback,
            getState: getState,
            setState: setState,
            checkForUpdateAction: { self.checkForAppUpdate(force: true) }
        )
    }

    private func requireState() -> UpdateStore {
        requireGetState()()
    }

    private func requireGetState() -> AppUpdateCoordinator.UpdateStateGetter {
        guard let getState else {
            preconditionFailure("AppUpdateModel.bind must be called before use")
        }
        return getState
    }

    private func requireSetState() -> AppUpdateCoordinator.UpdateStateSetter {
        guard let setState else {
            preconditionFailure("AppUpdateModel.bind must be called before use")
        }
        return setState
    }

    private func requireEffectiveInstalledVersion() -> String {
        guard let effectiveInstalledVersion else {
            preconditionFailure("AppUpdateModel.bind must be called before use")
        }
        return effectiveInstalledVersion()
    }

    private func requireLocalizedText() -> @MainActor (String, String) -> String {
        guard let localizedText else {
            preconditionFailure("AppUpdateModel.bind must be called before use")
        }
        return localizedText
    }
}

extension AppViewModel {
    var settingsUpdateDisplayState: SettingsUpdateDisplayState {
        updateModel.settingsDisplayState
    }

    var menuUpdateDisplayState: MenuUpdateDisplayState {
        updateModel.menuDisplayState
    }

    var updateActionTitle: String {
        updateModel.updateActionTitle
    }

    var updateStatusSummary: String? {
        updateModel.updateStatusSummary
    }

    var isUpdateActionEnabled: Bool {
        updateModel.isUpdateActionEnabled
    }

    func checkForAppUpdate(force: Bool = false) {
        updateModel.checkForAppUpdate(force: force)
    }

    func openLatestReleaseDownload() {
        updateModel.openLatestReleaseDownload()
    }

    func performMenuUpdateAction() {
        updateModel.performMenuUpdateAction()
    }
}
