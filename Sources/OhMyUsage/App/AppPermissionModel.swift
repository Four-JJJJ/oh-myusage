import AppKit
import Foundation
import UserNotifications

/// Owns the Permission session boundary: coordinator + PermissionStore get/set wiring.
/// Store remains in AppViewModel/sessionStore so Observation projections keep working.
@MainActor
final class AppPermissionModel {
    typealias PermissionStateGetter = () -> PermissionStore
    typealias PermissionStateSetter = (PermissionStore) -> Void

    private let coordinator: AppPermissionCoordinator
    private var getState: PermissionStateGetter?
    private var setState: PermissionStateSetter?
    private var requestPermissionIfNeeded: (@MainActor () -> Void)?
    private var fetchNotificationAuthorizationStatus: (@MainActor () async -> UNAuthorizationStatus)?
    private var checkSecureStorageReady: (@MainActor () async -> Bool)?
    private var onSecureStorageBecameReady: (@MainActor () -> Void)?
    private var prepareSecureStoreAccess: (@MainActor () -> Bool)?
    private var presentSecureStorageAccessUI: (@MainActor () -> Void)?

    private var notificationPermissionPollingTask: Task<Void, Never>?
    private var permissionRefreshTask: Task<Void, Never>?

    init(coordinator: AppPermissionCoordinator = AppPermissionCoordinator()) {
        self.coordinator = coordinator
    }

    /// Bind store access and host dependencies after the ViewModel is fully initialized.
    func bind(
        getState: @escaping PermissionStateGetter,
        setState: @escaping PermissionStateSetter,
        requestPermissionIfNeeded: @escaping @MainActor () -> Void,
        fetchNotificationAuthorizationStatus: @escaping @MainActor () async -> UNAuthorizationStatus,
        checkSecureStorageReady: @escaping @MainActor () async -> Bool,
        onSecureStorageBecameReady: @escaping @MainActor () -> Void,
        prepareSecureStoreAccess: @escaping @MainActor () -> Bool,
        presentSecureStorageAccessUI: @escaping @MainActor () -> Void
    ) {
        self.getState = getState
        self.setState = setState
        self.requestPermissionIfNeeded = requestPermissionIfNeeded
        self.fetchNotificationAuthorizationStatus = fetchNotificationAuthorizationStatus
        self.checkSecureStorageReady = checkSecureStorageReady
        self.onSecureStorageBecameReady = onSecureStorageBecameReady
        self.prepareSecureStoreAccess = prepareSecureStoreAccess
        self.presentSecureStorageAccessUI = presentSecureStorageAccessUI
    }

    var hasNotificationPermission: Bool {
        switch requireState().notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    func shouldShowPermissionGuide(
        hasEnabledProviders: Bool,
        hasPersistedOfficialMonitoringState: Bool
    ) -> Bool {
        let state = requireState()
        return AppPermissionCoordinator.shouldShowPermissionGuide(
            hasEnabledProviders: hasEnabledProviders,
            hasPersistedOfficialMonitoringState: hasPersistedOfficialMonitoringState,
            hasNotificationPermission: hasNotificationPermission,
            secureStorageReady: state.secureStorageReady,
            fullDiskAccessRelevant: state.fullDiskAccessRelevant,
            fullDiskAccessRequested: state.fullDiskAccessRequested,
            fullDiskAccessGranted: state.fullDiskAccessGranted
        )
    }

    var canRunLocalDiscoveryFromOnboarding: Bool {
        let state = requireState()
        guard state.secureStorageReady else { return false }
        if state.fullDiskAccessRelevant || state.fullDiskAccessRequested {
            return state.fullDiskAccessGranted
        }
        return true
    }

    func requestNotificationPermission() {
        notificationPermissionPollingTask?.cancel()
        notificationPermissionPollingTask = coordinator.requestNotificationPermission(
            requestPermissionIfNeeded: { self.requireRequestPermissionIfNeeded()() },
            fetchNotificationAuthorizationStatus: { await self.requireFetchNotificationAuthorizationStatus()() },
            updateNotificationAuthorizationStatus: { status in
                var state = self.requireState()
                state.notificationAuthorizationStatus = status
                self.requireSetState()(state)
            },
            refreshPermissionStatuses: { self.refreshPermissionStatuses(force: true) }
        )
    }

    @discardableResult
    func prepareSecureStorageAccess() -> Bool {
        requirePresentSecureStorageAccessUI()()
        let ok = requirePrepareSecureStoreAccess()()
        if ok {
            requireOnSecureStorageBecameReady()()
        }
        refreshPermissionStatuses(force: true)
        return ok
    }

    func openNotificationSettings() {
        openSystemSettings(
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.notifications"
            ]
        )
    }

    func openKeychainAccessSettings() {
        // 保留接口兼容旧调用，但不再主动拉起系统应用，避免钥匙串授权时打断当前窗口焦点。
    }

    func openFullDiskAccessSettings() {
        var state = requireState()
        state.fullDiskAccessRequested = true
        requireSetState()(state)
        openSystemSettings(
            urlCandidates: [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            ]
        )
    }

    func refreshPermissionStatusesIfNeeded(referenceDate: Date = Date()) {
        let state = requireState()
        guard referenceDate.timeIntervalSince(state.lastPermissionStatusRefreshAt) >= 5 else { return }
        refreshPermissionStatuses(force: false)
    }

    func refreshPermissionStatusesNow() {
        refreshPermissionStatuses(force: true)
    }

    func refreshPermissionStatuses(force: Bool) {
        var state = requireState()
        if !force, Date().timeIntervalSince(state.lastPermissionStatusRefreshAt) < 5 {
            return
        }
        state.lastPermissionStatusRefreshAt = Date()
        requireSetState()(state)

        permissionRefreshTask?.cancel()
        let previousSecureStorageReady = state.secureStorageReady
        permissionRefreshTask = coordinator.refreshPermissionStatuses(
            checkSecureStorageReady: { await self.requireCheckSecureStorageReady()() },
            fetchNotificationAuthorizationStatus: { await self.requireFetchNotificationAuthorizationStatus()() },
            previousSecureStorageReady: previousSecureStorageReady,
            updateSecureStorageReady: { ready in
                var next = self.requireState()
                next.secureStorageReady = ready
                self.requireSetState()(next)
            },
            onSecureStorageBecameReady: { self.requireOnSecureStorageBecameReady()() },
            applyFullDiskProbe: { granted, relevant in
                var next = self.requireState()
                next.fullDiskAccessGranted = granted
                next.fullDiskAccessRelevant = relevant
                self.requireSetState()(next)
            },
            updateNotificationAuthorizationStatus: { status in
                var next = self.requireState()
                next.notificationAuthorizationStatus = status
                self.requireSetState()(next)
            },
            forceFullDiskProbe: force
        )
    }

    func cancelTransientTasks() {
        notificationPermissionPollingTask?.cancel()
        notificationPermissionPollingTask = nil
        permissionRefreshTask?.cancel()
        permissionRefreshTask = nil
    }

    func resetState() {
        cancelTransientTasks()
        var state = requireState()
        state.notificationAuthorizationStatus = .notDetermined
        state.secureStorageReady = false
        state.fullDiskAccessGranted = false
        state.fullDiskAccessRelevant = false
        state.fullDiskAccessRequested = false
        state.lastPermissionStatusRefreshAt = .distantPast
        requireSetState()(state)
    }

    private func openSystemSettings(
        urlCandidates: [String],
        fallbackBundleIDs: [String] = ["com.apple.systemsettings", "com.apple.systempreferences"]
    ) {
        for raw in urlCandidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        openSystemSettingsApplication(bundleIDs: fallbackBundleIDs)
    }

    private func openSystemSettingsApplication(bundleIDs: [String]) {
        for bundleID in bundleIDs {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                continue
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
            return
        }
    }

    private func requireState() -> PermissionStore {
        requireGetState()()
    }

    private func requireGetState() -> PermissionStateGetter {
        guard let getState else {
            preconditionFailure("AppPermissionModel.bind must be called before use")
        }
        return getState
    }

    private func requireSetState() -> PermissionStateSetter {
        guard let setState else {
            preconditionFailure("AppPermissionModel.bind must be called before use")
        }
        return setState
    }

    private func requireRequestPermissionIfNeeded() -> @MainActor () -> Void {
        guard let requestPermissionIfNeeded else {
            preconditionFailure("AppPermissionModel.bind must be called before use")
        }
        return requestPermissionIfNeeded
    }

    private func requireFetchNotificationAuthorizationStatus() -> @MainActor () async -> UNAuthorizationStatus {
        guard let fetchNotificationAuthorizationStatus else {
            preconditionFailure("AppPermissionModel.bind must be called before use")
        }
        return fetchNotificationAuthorizationStatus
    }

    private func requireCheckSecureStorageReady() -> @MainActor () async -> Bool {
        guard let checkSecureStorageReady else {
            preconditionFailure("AppPermissionModel.bind must be called before use")
        }
        return checkSecureStorageReady
    }

    private func requireOnSecureStorageBecameReady() -> @MainActor () -> Void {
        guard let onSecureStorageBecameReady else {
            preconditionFailure("AppPermissionModel.bind must be called before use")
        }
        return onSecureStorageBecameReady
    }

    private func requirePrepareSecureStoreAccess() -> @MainActor () -> Bool {
        guard let prepareSecureStoreAccess else {
            preconditionFailure("AppPermissionModel.bind must be called before use")
        }
        return prepareSecureStoreAccess
    }

    private func requirePresentSecureStorageAccessUI() -> @MainActor () -> Void {
        guard let presentSecureStorageAccessUI else {
            preconditionFailure("AppPermissionModel.bind must be called before use")
        }
        return presentSecureStorageAccessUI
    }
}

extension AppViewModel {
    var hasNotificationPermission: Bool {
        permissionModel.hasNotificationPermission
    }

    var shouldShowPermissionGuide: Bool {
        permissionModel.shouldShowPermissionGuide(
            hasEnabledProviders: config.providers.contains(where: \.enabled),
            hasPersistedOfficialMonitoringState: hasPersistedOfficialMonitoringState
        )
    }

    var canRunLocalDiscoveryFromOnboarding: Bool {
        permissionModel.canRunLocalDiscoveryFromOnboarding
    }

    func requestNotificationPermission() {
        permissionModel.requestNotificationPermission()
    }

    @discardableResult
    func prepareSecureStorageAccess() -> Bool {
        permissionModel.prepareSecureStorageAccess()
    }

    func openNotificationSettings() {
        permissionModel.openNotificationSettings()
    }

    func openKeychainAccessSettings() {
        permissionModel.openKeychainAccessSettings()
    }

    func openFullDiskAccessSettings() {
        permissionModel.openFullDiskAccessSettings()
    }

    func refreshPermissionStatusesIfNeeded(referenceDate: Date = Date()) {
        permissionModel.refreshPermissionStatusesIfNeeded(referenceDate: referenceDate)
    }

    func refreshPermissionStatusesNow() {
        permissionModel.refreshPermissionStatusesNow()
    }

    func refreshPermissionStatuses(force: Bool) {
        permissionModel.refreshPermissionStatuses(force: force)
    }
}
