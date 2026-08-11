import OhMyUsageDomain
import AppKit
import OhMyUsageApplication
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AppViewModel {
    let keychain: KeychainService
    let configurationRepository: any AppConfigurationRepositorying
    @ObservationIgnored let credentialAccessService: CredentialAccessService
    let thirdPartyBalanceBaselineStore = ThirdPartyBalanceBaselineStore()
    let codexSlotStore: CodexAccountSlotStore
    let codexProfileStore: CodexAccountProfileStore
    let codexProfileSnapshotService: CodexProfileSnapshotService
    let codexDesktopAuthService: CodexDesktopAuthService
    let codexDesktopAppService: CodexDesktopAppService
    let oauthImportOrchestrator = OAuthImportOrchestrator()
    let claudeSlotStore = ClaudeAccountSlotStore()
    let claudeProfileStore = ClaudeAccountProfileStore()
    let claudeProfileSnapshotService = ClaudeProfileSnapshotService()
    let claudeDesktopAuthService = ClaudeDesktopAuthService()
    let launchAtLoginService = LaunchAtLoginService()
    let notifications: NotificationService
    @ObservationIgnored private let localSessionSignalMonitor = LocalSessionCompletionSignalMonitor()
    let providerFactory: any ProviderFactorying
    @ObservationIgnored private let localSessionRefreshCoordinator: LocalSessionRefreshCoordinator
    @ObservationIgnored private let localUsageHistoryRepository: LocalUsageHistoryRepository
    @ObservationIgnored private let detectsInstalledAppVersionForUpdates: Bool
    @ObservationIgnored let usageAnalyticsModel: AppUsageAnalyticsModel
    @ObservationIgnored let providerRefreshModel: AppProviderRefreshModel
    @ObservationIgnored let officialProfilesModel = AppOfficialProfilesModel()
    @ObservationIgnored let configurationModel: AppConfigurationModel
    @ObservationIgnored let resetCoordinator = AppResetCoordinator()
    @ObservationIgnored private let localProviderDiscoveryCoordinator = LocalProviderDiscoveryCoordinator()
    @ObservationIgnored private let localUsageHistoryRefreshCoordinator = LocalUsageHistoryRefreshCoordinator()
    @ObservationIgnored let codexOfficialProfileRefreshRuntime = CodexOfficialProfileRefreshRuntime()
    @ObservationIgnored let claudeOfficialProfileRefreshRuntime = ClaudeOfficialProfileRefreshRuntime()
    @ObservationIgnored let permissionModel: AppPermissionModel
    @ObservationIgnored let updateModel: AppUpdateModel
    private var sessionStore = AppSessionStore()

    var officialProviderSettingsCoordinator: AppOfficialProviderSettingsCoordinator {
        configurationModel.officialProviderSettingsCoordinator
    }
    var providerListMutationCoordinator: AppProviderListMutationCoordinator {
        configurationModel.providerListMutationCoordinator
    }
    var providerCredentialCoordinator: AppProviderCredentialCoordinator {
        configurationModel.providerCredentialCoordinator
    }
    var credentialLookupCoordinator: AppCredentialLookupCoordinator {
        configurationModel.credentialLookupCoordinator
    }
    var relayProviderSettingsCoordinator: AppRelayProviderSettingsCoordinator {
        configurationModel.relayProviderSettingsCoordinator
    }
    var relayDescriptorPreviewBuilder: RelayDescriptorPreviewBuilder {
        configurationModel.relayDescriptorPreviewBuilder
    }
    var statusBarPreferencesCoordinator: AppStatusBarPreferencesCoordinator {
        configurationModel.statusBarPreferencesCoordinator
    }
    var configurationMutationCoordinator: AppConfigurationMutationCoordinator {
        configurationModel.configurationMutationCoordinator
    }
    var settingsPersistenceFeedbackCoordinator: AppSettingsPersistenceFeedbackCoordinator {
        configurationModel.settingsPersistenceFeedbackCoordinator
    }

    var officialAccountImportCoordinator: AppOfficialAccountImportCoordinator {
        officialProfilesModel.accountImportCoordinator
    }
    var officialAccountSwitchCoordinator: AppOfficialAccountSwitchCoordinator {
        officialProfilesModel.accountSwitchCoordinator
    }
    var officialProfileLifecycleCoordinator: AppOfficialProfileLifecycleCoordinator {
        officialProfilesModel.lifecycleCoordinator
    }
    var officialProfileRefreshCoordinator: AppOfficialProfileRefreshCoordinator {
        officialProfilesModel.refreshCoordinator
    }
    var officialProfileDisplayCoordinator: AppOfficialProfileDisplayCoordinator {
        officialProfilesModel.displayCoordinator
    }
    var officialProfileSyncCoordinator: AppOfficialProfileSyncCoordinator {
        officialProfilesModel.syncCoordinator
    }
    var codexFeedbackCoordinator: AppTransientFeedbackCoordinator<CodexSlotID, CodexSwitchFeedback> {
        officialProfilesModel.codexFeedbackCoordinator
    }
    var claudeFeedbackCoordinator: AppTransientFeedbackCoordinator<CodexSlotID, ClaudeSwitchFeedback> {
        officialProfilesModel.claudeFeedbackCoordinator
    }
    var codexSwitchCoordinator: AccountSwitchTransactionCoordinator<CodexSlotID> {
        officialProfilesModel.codexSwitchCoordinator
    }
    var claudeSwitchCoordinator: AccountSwitchTransactionCoordinator<CodexSlotID> {
        officialProfilesModel.claudeSwitchCoordinator
    }


    var settingsPersistenceStatus = SettingsPersistenceDisplayState(
        kind: .idle,
        statusText: nil,
        tone: .neutral
    )
    var settingsPersistenceErrorMessage: String?

    var config: AppConfig
    // Provider-state projections below are read-only; writes go through `providerRefreshModel`.
    var snapshots: [String: UsageSnapshot] {
        sessionStore.providerState.snapshots
    }
    var codexSlots: [CodexAccountSlot] {
        get { sessionStore.accountState.codexSlots }
        set { sessionStore.accountState.codexSlots = newValue }
    }
    var codexProfiles: [CodexAccountProfile] {
        get { sessionStore.accountState.codexProfiles }
        set { sessionStore.accountState.codexProfiles = newValue }
    }
    var codexSwitchFeedback: [CodexSlotID: CodexSwitchFeedback] {
        get { sessionStore.accountState.codexSwitchFeedback }
        set { sessionStore.accountState.codexSwitchFeedback = newValue }
    }
    var codexOAuthImportState: OAuthImportState? {
        get { sessionStore.accountState.codexOAuthImportState }
        set { sessionStore.accountState.codexOAuthImportState = newValue }
    }
    var claudeSlots: [ClaudeAccountSlot] {
        get { sessionStore.accountState.claudeSlots }
        set { sessionStore.accountState.claudeSlots = newValue }
    }
    var claudeProfiles: [ClaudeAccountProfile] {
        get { sessionStore.accountState.claudeProfiles }
        set { sessionStore.accountState.claudeProfiles = newValue }
    }
    var claudeSwitchFeedback: [CodexSlotID: ClaudeSwitchFeedback] {
        get { sessionStore.accountState.claudeSwitchFeedback }
        set { sessionStore.accountState.claudeSwitchFeedback = newValue }
    }
    var claudeOAuthImportState: OAuthImportState? {
        get { sessionStore.accountState.claudeOAuthImportState }
        set { sessionStore.accountState.claudeOAuthImportState = newValue }
    }
    var errors: [String: String] {
        sessionStore.providerState.errors
    }
    var lastUpdatedAt: Date? {
        sessionStore.providerState.lastUpdatedAt
    }
    var notificationAuthorizationStatus: UNAuthorizationStatus {
        get { sessionStore.permissionState.notificationAuthorizationStatus }
        set { sessionStore.permissionState.notificationAuthorizationStatus = newValue }
    }
    var secureStorageReady: Bool {
        get { sessionStore.permissionState.secureStorageReady }
        set { sessionStore.permissionState.secureStorageReady = newValue }
    }
    var fullDiskAccessGranted: Bool {
        get { sessionStore.permissionState.fullDiskAccessGranted }
        set { sessionStore.permissionState.fullDiskAccessGranted = newValue }
    }
    var fullDiskAccessRelevant: Bool {
        get { sessionStore.permissionState.fullDiskAccessRelevant }
        set { sessionStore.permissionState.fullDiskAccessRelevant = newValue }
    }
    var fullDiskAccessRequested: Bool {
        get { sessionStore.permissionState.fullDiskAccessRequested }
        set { sessionStore.permissionState.fullDiskAccessRequested = newValue }
    }
    private(set) var currentAppVersion: String {
        get { sessionStore.updateState.currentAppVersion }
        set { sessionStore.updateState.currentAppVersion = newValue }
    }
    private(set) var availableUpdate: AppUpdateInfo? {
        get { sessionStore.updateState.availableUpdate }
        set { sessionStore.updateState.availableUpdate = newValue }
    }
    private(set) var lastUpdateCheckAt: Date? {
        get { sessionStore.updateState.lastUpdateCheckAt }
        set { sessionStore.updateState.lastUpdateCheckAt = newValue }
    }
    private(set) var updateCheckInFlight: Bool {
        get { sessionStore.updateState.updateCheckInFlight }
        set { sessionStore.updateState.updateCheckInFlight = newValue }
    }
    private(set) var lastCheckedLatestVersion: String? {
        get { sessionStore.updateState.lastCheckedLatestVersion }
        set { sessionStore.updateState.lastCheckedLatestVersion = newValue }
    }
    private(set) var updateCheckErrorMessage: String? {
        get { sessionStore.updateState.updateCheckErrorMessage }
        set { sessionStore.updateState.updateCheckErrorMessage = newValue }
    }
    private(set) var updateDownloadInFlight: Bool {
        get { sessionStore.updateState.updateDownloadInFlight }
        set { sessionStore.updateState.updateDownloadInFlight = newValue }
    }
    private(set) var updateInstallBufferingInFlight: Bool {
        get { sessionStore.updateState.updateInstallBufferingInFlight }
        set { sessionStore.updateState.updateInstallBufferingInFlight = newValue }
    }
    private(set) var updateInstallationInFlight: Bool {
        get { sessionStore.updateState.updateInstallationInFlight }
        set { sessionStore.updateState.updateInstallationInFlight = newValue }
    }
    private(set) var updatePreparedVersion: String? {
        get { sessionStore.updateState.updatePreparedVersion }
        set { sessionStore.updateState.updatePreparedVersion = newValue }
    }
    private(set) var updateInstallErrorMessage: String? {
        get { sessionStore.updateState.updateInstallErrorMessage }
        set { sessionStore.updateState.updateInstallErrorMessage = newValue }
    }
    var localUsageHistoryVersion: Int {
        sessionStore.providerState.localUsageHistoryVersion
    }
    var usageAnalyticsFilter = UsageAnalyticsFilter()
    private(set) var usageAnalyticsSnapshot = UsageAnalyticsSnapshot.empty(filter: UsageAnalyticsFilter())
    private(set) var usageAnalyticsLoading = false
    private(set) var menuPanelVisible: Bool {
        get { sessionStore.menuPanelVisible }
        set { sessionStore.menuPanelVisible = newValue }
    }
    private(set) var settingsWindowVisible: Bool {
        get { sessionStore.settingsWindowVisible }
        set { sessionStore.settingsWindowVisible = newValue }
    }
    var updateStateStorage: UpdateStore {
        get { sessionStore.updateState }
        set { sessionStore.updateState = newValue }
    }
    var permissionStateStorage: PermissionStore {
        get { sessionStore.permissionState }
        set { sessionStore.permissionState = newValue }
    }
    var providerStateStorage: ProviderStateStore {
        sessionStore.providerState
    }

    /// Physical Observation write used only by `AppProviderRefreshModel` setState binding.
    func applyProviderStateStorage(_ state: ProviderStateStore) {
        sessionStore.providerState = state
    }

    var codexOAuthImportTask: Task<Void, Never>?
    var claudeOAuthImportTask: Task<Void, Never>?
    var didRunClaudeAutoCaptureCompaction = false
    var credentialLookupVersion: Int {
        get { sessionStore.credentialLookupVersion }
        set { sessionStore.credentialLookupVersion = newValue }
    }
    var consecutiveFailures: [String: Int] {
        sessionStore.providerState.consecutiveFailures
    }
    var activeAlerts: Set<String> {
        sessionStore.providerState.activeAlerts
    }
    var thirdPartyBalanceBaselineTracker: ThirdPartyBalanceBaselineTracker {
        sessionStore.providerState.thirdPartyBalanceBaselineTracker
    }
    var hasStarted: Bool {
        get { sessionStore.hasStarted }
        set { sessionStore.hasStarted = newValue }
    }
    var lastPermissionStatusRefreshAt: Date {
        get { sessionStore.permissionState.lastPermissionStatusRefreshAt }
        set { sessionStore.permissionState.lastPermissionStatusRefreshAt = newValue }
    }
    convenience init(
        configurationRepository: any AppConfigurationRepositorying = AppConfigurationRepository(),
        appUpdateService: any AppUpdateServicing = AppUpdateService(),
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore(),
        codexSlotStore: CodexAccountSlotStore = CodexAccountSlotStore(),
        codexProfileStore: CodexAccountProfileStore = CodexAccountProfileStore(),
        codexDesktopAuthService: CodexDesktopAuthService = CodexDesktopAuthService(),
        codexDesktopAppService: CodexDesktopAppService = CodexDesktopAppService(),
        codexProfileSnapshotService: CodexProfileSnapshotService = CodexProfileSnapshotService(),
        notificationService: NotificationService = NotificationService(),
        providerFactory: (any ProviderFactorying)? = nil,
        keychain: KeychainService = KeychainService(),
        localUsageHistoryRepository: LocalUsageHistoryRepository = LocalUsageHistoryRepository(),
        usageAnalyticsRefreshCoordinator: UsageAnalyticsRefreshCoordinator = UsageAnalyticsRefreshCoordinator(),
        updateInstallBufferDelaySeconds: TimeInterval = 2,
        updateCheckStatusClearDelaySeconds: TimeInterval = 10,
        settingsPersistenceStatusClearDelaySeconds: TimeInterval = 4
    ) {
        let dependencyGraph = AppCompositionFactory.makeDependencyGraph(
            configurationRepository: configurationRepository,
            appUpdateService: appUpdateService,
            postUpdateReleaseNotesStore: postUpdateReleaseNotesStore,
            codexSlotStore: codexSlotStore,
            codexProfileStore: codexProfileStore,
            codexDesktopAuthService: codexDesktopAuthService,
            codexDesktopAppService: codexDesktopAppService,
            codexProfileSnapshotService: codexProfileSnapshotService,
            notificationService: notificationService,
            providerFactory: providerFactory,
            keychain: keychain,
            localUsageHistoryRepository: localUsageHistoryRepository,
            usageAnalyticsRefreshCoordinator: usageAnalyticsRefreshCoordinator,
            updateInstallBufferDelaySeconds: updateInstallBufferDelaySeconds,
            updateCheckStatusClearDelaySeconds: updateCheckStatusClearDelaySeconds,
            settingsPersistenceStatusClearDelaySeconds: settingsPersistenceStatusClearDelaySeconds
        )
        let configBootstrap = AppCompositionFactory.loadProductionConfig(
            from: dependencyGraph.configurationRepository
        )
        self.init(
            dependencyGraph: dependencyGraph,
            config: configBootstrap.config,
            currentAppVersion: AppVersionResolver.detectCurrentAppVersion(),
            shouldPersistConfigDuringBootstrap: configBootstrap.shouldPersistDuringBootstrap,
            performsProductionBootstrapSideEffects: true
        )
    }

#if DEBUG
    convenience init(
        testingConfig: AppConfig = .default,
        testingCurrentAppVersion: String = "0.0.0",
        configurationRepository: any AppConfigurationRepositorying = AppViewModel.makeTestingConfigurationRepository(),
        appUpdateService: any AppUpdateServicing,
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore(),
        codexSlotStore: CodexAccountSlotStore = CodexAccountSlotStore(),
        codexProfileStore: CodexAccountProfileStore = CodexAccountProfileStore(),
        codexDesktopAuthService: CodexDesktopAuthService = CodexDesktopAuthService(),
        codexDesktopAppService: CodexDesktopAppService = CodexDesktopAppService(),
        codexProfileSnapshotService: CodexProfileSnapshotService = CodexProfileSnapshotService(),
        notificationService: NotificationService = NotificationService(),
        providerFactory: (any ProviderFactorying)? = nil,
        keychain: KeychainService = KeychainService(),
        localUsageHistoryRepository: LocalUsageHistoryRepository = LocalUsageHistoryRepository(),
        usageAnalyticsRefreshCoordinator: UsageAnalyticsRefreshCoordinator = UsageAnalyticsRefreshCoordinator(),
        updateInstallBufferDelaySeconds: TimeInterval = 2,
        updateCheckStatusClearDelaySeconds: TimeInterval = 10,
        settingsPersistenceStatusClearDelaySeconds: TimeInterval = 4
    ) {
        let dependencyGraph = AppCompositionFactory.makeDependencyGraph(
            configurationRepository: configurationRepository,
            appUpdateService: appUpdateService,
            postUpdateReleaseNotesStore: postUpdateReleaseNotesStore,
            codexSlotStore: codexSlotStore,
            codexProfileStore: codexProfileStore,
            codexDesktopAuthService: codexDesktopAuthService,
            codexDesktopAppService: codexDesktopAppService,
            codexProfileSnapshotService: codexProfileSnapshotService,
            notificationService: notificationService,
            providerFactory: providerFactory,
            keychain: keychain,
            localUsageHistoryRepository: localUsageHistoryRepository,
            usageAnalyticsRefreshCoordinator: usageAnalyticsRefreshCoordinator,
            updateInstallBufferDelaySeconds: updateInstallBufferDelaySeconds,
            updateCheckStatusClearDelaySeconds: updateCheckStatusClearDelaySeconds,
            settingsPersistenceStatusClearDelaySeconds: settingsPersistenceStatusClearDelaySeconds
        )
        self.init(
            dependencyGraph: dependencyGraph,
            config: testingConfig.migratedWithSiteDefaults(),
            currentAppVersion: testingCurrentAppVersion,
            shouldPersistConfigDuringBootstrap: false,
            performsProductionBootstrapSideEffects: false
        )
    }

    private static func makeTestingConfigurationRepository() -> AppConfigurationRepository {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return AppConfigurationRepository(store: ConfigStore(baseDirectoryURL: root))
    }
#endif

    private init(
        dependencyGraph: AppDependencyGraph,
        config: AppConfig,
        currentAppVersion: String,
        shouldPersistConfigDuringBootstrap: Bool,
        performsProductionBootstrapSideEffects: Bool
    ) {
        self.keychain = dependencyGraph.keychain
        self.configurationRepository = dependencyGraph.configurationRepository
        self.credentialAccessService = dependencyGraph.credentialAccessService
        self.codexSlotStore = dependencyGraph.codexSlotStore
        self.codexProfileStore = dependencyGraph.codexProfileStore
        self.codexDesktopAuthService = dependencyGraph.codexDesktopAuthService
        self.codexDesktopAppService = dependencyGraph.codexDesktopAppService
        self.codexProfileSnapshotService = dependencyGraph.codexProfileSnapshotService
        self.notifications = dependencyGraph.notifications
        self.providerRefreshModel = dependencyGraph.providerRefreshModel
        self.permissionModel = dependencyGraph.permissionModel
        self.updateModel = dependencyGraph.updateModel
        self.configurationModel = dependencyGraph.configurationModel
        self.config = config
        self.providerFactory = dependencyGraph.providerFactory
        self.localUsageHistoryRepository = dependencyGraph.localUsageHistoryRepository
        self.usageAnalyticsModel = dependencyGraph.usageAnalyticsModel
        self.localSessionRefreshCoordinator = LocalSessionRefreshCoordinator(
            signalSource: localSessionSignalMonitor
        )
        self.detectsInstalledAppVersionForUpdates = performsProductionBootstrapSideEffects
        self.currentAppVersion = currentAppVersion
        self.codexSlots = dependencyGraph.codexSlotStore.visibleSlots()
        self.claudeSlots = claudeSlotStore.visibleSlots()
        self.codexProfiles = []
        self.claudeProfiles = []
        bindConfigurationModel()
        bindProviderRefreshModel()
        if performsProductionBootstrapSideEffects {
            providerRefreshModel.mutateProviderState { state in
                state.thirdPartyBalanceBaselineTracker.restore(
                    entries: self.thirdPartyBalanceBaselineStore.load()
                )
            }
        }
        let preNormalizedConfig = self.config
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        if shouldPersistConfigDuringBootstrap && self.config != preNormalizedConfig {
            _ = configurationRepository.saveDuringBootstrapResult(self.config)
        }
        if performsProductionBootstrapSideEffects {
            launchAtLoginService.migrateLegacyLaunchAgentsIfNeeded()
            let launchAtLoginEnabled = launchAtLoginService.isEnabled()
            if self.config.launchAtLoginEnabled != launchAtLoginEnabled {
                self.config.launchAtLoginEnabled = launchAtLoginEnabled
                if shouldPersistConfigDuringBootstrap {
                    _ = configurationRepository.saveDuringBootstrapResult(self.config)
                }
            }
        }
        bindOfficialProfilesModel()
        syncCodexProfilesCurrentState()
        bootstrapClaudeProfileState()
        restorePersistedOfficialProvidersIfNeeded()
        bindPermissionModel()
        bindUpdateModel()
        bindUsageAnalyticsModel()
        if performsProductionBootstrapSideEffects {
            refreshPermissionStatuses(force: true)
        }
    }

    private func bindConfigurationModel() {
        configurationModel.bind(host: self)
    }

    private func bindProviderRefreshModel() {
        providerRefreshModel.bind(
            host: self,
            localSessionRefreshCoordinator: localSessionRefreshCoordinator,
            getState: { [weak self] in
                self?.providerStateStorage ?? ProviderStateStore()
            },
            setState: { [weak self] state in
                self?.applyProviderStateStorage(state)
            }
        )
        providerRefreshModel.installRefreshScheduler()
    }

    private func bindOfficialProfilesModel() {
        officialProfilesModel.bind(host: self)
    }

    private func bindPermissionModel() {
        permissionModel.bind(
            getState: { [weak self] in
                self?.permissionStateStorage ?? PermissionStore()
            },
            setState: { [weak self] state in
                self?.permissionStateStorage = state
            },
            requestPermissionIfNeeded: { [weak self] in
                self?.notifications.requestPermissionIfNeeded()
            },
            fetchNotificationAuthorizationStatus: { [weak self] in
                await self?.notifications.authorizationStatus() ?? .notDetermined
            },
            checkSecureStorageReady: { [weak self] in
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        continuation.resume(returning: self?.keychain.isSecureStoreReady() ?? false)
                    }
                }
            },
            onSecureStorageBecameReady: { [weak self] in
                self?.invalidateCredentialLookupCache()
            },
            prepareSecureStoreAccess: { [weak self] in
                self?.keychain.prepareSecureStoreAccess() ?? false
            },
            presentSecureStorageAccessUI: { [weak self] in
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)
                SettingsWindowController.shared.show(viewModel: self)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
            }
        )
    }

    private func bindUpdateModel() {
        updateModel.bind(
            getState: { [weak self] in
                self?.updateStateStorage ?? UpdateStore()
            },
            setState: { [weak self] state in
                self?.updateStateStorage = state
            },
            effectiveInstalledVersion: { [weak self] in
                guard let self else { return "" }
                if self.detectsInstalledAppVersionForUpdates {
                    return AppVersionResolver.detectNewestInstalledAppVersion(
                        fallbackVersion: self.currentAppVersion
                    )
                }
                return self.currentAppVersion
            },
            localizedText: { [weak self] zhHans, en in
                self?.localizedText(zhHans, en) ?? zhHans
            }
        )
    }

    private func bindUsageAnalyticsModel() {
        usageAnalyticsModel.bind(
            getFilter: { [weak self] in
                self?.usageAnalyticsFilter ?? UsageAnalyticsFilter()
            },
            getSnapshot: { [weak self] in
                self?.usageAnalyticsSnapshot
                    ?? UsageAnalyticsSnapshot.empty(filter: UsageAnalyticsFilter())
            },
            setSnapshot: { [weak self] snapshot in
                self?.usageAnalyticsSnapshot = snapshot
            },
            setLoading: { [weak self] isLoading in
                self?.usageAnalyticsLoading = isLoading
            },
            claudeAllConfigDirs: { [weak self] in
                self?.usageAnalyticsClaudeAllConfigDirs() ?? []
            }
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshPermissionStatuses(force: true)
        restartPolling()
        refreshDisplayedStatusBarProviders()
    }

    func setMenuPanelVisible(_ visible: Bool) {
        guard menuPanelVisible != visible else { return }
        menuPanelVisible = visible
    }

    func setSettingsWindowVisible(_ visible: Bool) {
        guard settingsWindowVisible != visible else { return }
        settingsWindowVisible = visible
    }

    func openRepositoryPage() {
        NSWorkspace.shared.open(AppUpdateService.repositoryURL)
    }

    func openCurrentVersionReleaseNotes() {
        ReleaseNotesWindowController.shared.show(
            releaseNotes: PendingPostUpdateReleaseNotes(
                version: currentAppVersion,
                releaseURL: AppUpdateService.releasePageURL(forVersion: currentAppVersion),
                notesURL: nil,
                createdAt: Date()
            )
        )
    }

    var language: AppLanguage {
        config.language
    }

    var resourceMode: ResourceMode {
        config.resourceMode
    }

    var launchAtLoginEnabled: Bool {
        config.launchAtLoginEnabled
    }

    var globalRefreshIntervalSeconds: Int {
        let intervals = Set(config.providers.map(\.pollIntervalSec))
        if intervals.count == 1, let value = intervals.first {
            return value
        }

        for candidate in [15, 30, 60, 300] {
            if intervals.contains(candidate) {
                return candidate
            }
        }
        return 60
    }

    func thirdPartyBarPercent(for providerID: String) -> Double? {
        thirdPartyBalanceBaselineTracker.percent(for: providerID)
    }

    func text(_ key: L10nKey) -> String {
        Localizer.text(key, language: config.language)
    }

    func localizedText(_ zhHans: String, _ en: String) -> String {
        config.language == .zhHans ? zhHans : en
    }

    func menuViewState(now: Date) -> MenuViewState {
        MenuDashboardStateBuilder.build(
            config: config,
            snapshots: snapshots,
            errors: errors,
            lastUpdatedAt: lastUpdatedAt,
            updateState: menuUpdateDisplayState,
            now: now,
            shouldShowPermissionGuide: shouldShowPermissionGuide,
            codexSlots: codexSlotViewModels(),
            claudeSlots: claudeSlotViewModels(),
            localization: menuViewLocalization
        )
    }

    func applyMenuClock(to state: inout MenuViewState, now: Date) {
        MenuDashboardStateBuilder.applyClock(to: &state, now: now)
    }

    private var menuViewLocalization: MenuViewLocalization {
        MenuViewLocalization(
            updatedAgoLabel: text(.updatedAgo),
            quota: MenuQuotaLocalization(
                quotaFiveHour: "5h",
                quotaWeekly: localizedText("周", "Weekly"),
                allModels: localizedText("全部模型", "All models"),
                sonnetOnly: localizedText("Sonnet 专用", "Sonnet only"),
                claudeDesign: localizedText("Claude Design", "Claude Design"),
                session: localizedText("会话", "Session"),
                monthly: localizedText("月度", "Monthly"),
                currentPlan: localizedText("当前套餐", "Current Plan"),
                totalUsage: localizedText("总用量", "Total Usage"),
                autocomplete: localizedText("自动补全", "Autocomplete"),
                dollarBalance: localizedText("美元余额", "Dollar Balance")
            ),
            usedLabel: text(.used),
            balanceLabel: text(.balanceLabel),
            tightText: text(.statusTight),
            sufficientText: text(.statusSufficient),
            exhaustedText: text(.statusExhausted),
            disconnectedText: text(.statusDisconnected),
            codexSwitchAction: text(.codexSwitchAction),
            claudeSwitchAction: localizedText("切换", "Switch")
        )
    }

    func runtimeMemoryDiagnostics() -> RuntimeMemoryDiagnostics {
        RuntimeMemoryDiagnostics(
            residentSizeBytes: RuntimeMemoryProbe.residentSizeBytes(),
            snapshotCount: snapshots.count,
            codexProfileCount: codexProfiles.count,
            codexSlotCount: codexSlots.count,
            claudeProfileCount: claudeProfiles.count,
            claudeSlotCount: claudeSlots.count,
            codexPrefetchAttemptedIdentityCount: codexOfficialProfileRefreshRuntime.attemptedIdentityCount,
            codexPrefetchInFlightCount: codexOfficialProfileRefreshRuntime.inFlightCount,
            claudePrefetchAttemptedIdentityCount: claudeOfficialProfileRefreshRuntime.attemptedIdentityCount,
            claudePrefetchInFlightCount: claudeOfficialProfileRefreshRuntime.inFlightCount,
            pollTaskCount: providerRefreshModel.pollTaskCount,
            enabledProviderCount: config.providers.filter(\.enabled).count,
            providerErrorCount: errors.count,
            consecutiveFailureTotal: consecutiveFailures.values.reduce(0, +)
        )
    }

    var settingsPersistenceDisplayState: SettingsPersistenceDisplayState {
        reconcileSettingsPersistenceFeedbackIfNeeded()
        return settingsPersistenceFeedbackCoordinator.resolvedDisplayState(
            stored: settingsPersistenceStatus
        )
    }

    var settingsPersistenceErrorMessageForDisplay: String? {
        reconcileSettingsPersistenceFeedbackIfNeeded()
        return settingsPersistenceFeedbackCoordinator.resolvedErrorMessage(
            stored: settingsPersistenceErrorMessage,
            storedKind: settingsPersistenceStatus.kind
        )
    }

    private func reconcileSettingsPersistenceFeedbackIfNeeded() {
        settingsPersistenceFeedbackCoordinator.reconcileIfNeeded { [weak self] state, errorMessage in
            self?.settingsPersistenceStatus = state
            self?.settingsPersistenceErrorMessage = errorMessage
        }
    }

    func aggregateStatusTitle(_ status: AggregateStatus) -> String {
        switch status {
        case .normal:
            return text(.statusNormal)
        case .alert:
            return text(.statusAlert)
        case .disconnected:
            return text(.statusDisconnected)
        }
    }

    func localUsageHistoryState(for query: LocalUsageHistoryQuery) -> LocalUsageHistoryState {
        guard LocalUsageHistoryRefreshCoordinator.supports(query.providerType) else {
            return LocalUsageHistoryState(
                summary: nil,
                error: nil,
                isLoading: false,
                lastRefreshedAt: nil,
                sourceFingerprint: nil,
                lastFingerprintCheckedAt: nil,
                isStaleFallback: false
            )
        }
        _ = localUsageHistoryVersion
        return localUsageHistoryRepository.snapshot(for: query)
    }

    func refreshLocalUsageHistoryIfNeeded(
        query: LocalUsageHistoryQuery,
        codexIdentity: CodexTrendIdentityContext? = nil,
        claudeCurrentConfigDir: String? = nil,
        claudeAllConfigDirs: [String] = [],
        force: Bool = false
    ) {
        localUsageHistoryRefreshCoordinator.refreshLocalUsageHistoryIfNeeded(
            query: query,
            repository: localUsageHistoryRepository,
            codexIdentity: codexIdentity,
            claudeCurrentConfigDir: claudeCurrentConfigDir,
            claudeAllConfigDirs: claudeAllConfigDirs,
            force: force
        ) { [weak self] in
            self?.providerRefreshModel.mutateProviderState { state in
                state.localUsageHistoryVersion += 1
            }
        }
    }

    private func usageAnalyticsClaudeAllConfigDirs() -> [String] {
        Array(Set(claudeProfiles.compactMap { profile in
            profile.configDir?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }

    func discoverLocalProviders() async -> String {
        let candidates = config.providers.filter { $0.family == .official }
        return await localProviderDiscoveryCoordinator.discoverLocalProviders(
            candidates: candidates,
            makeProvider: { self.providerFactory.makeProvider(for: $0) },
            handleFetchedSnapshot: { descriptor, fetched in
                if descriptor.type == .codex {
                    let snapshot = self.markCodexSnapshotActive(fetched)
                    self.codexSlots = self.codexSlotStore.upsertActive(snapshot: snapshot)
                    self.providerRefreshModel.mutateProviderState { state in
                        state.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                    }
                } else if descriptor.type == .claude {
                    let snapshot = self.markClaudeSnapshotActive(fetched)
                    self.claudeSlots = self.claudeSlotStore.upsertActive(snapshot: snapshot)
                    self.providerRefreshModel.mutateProviderState { state in
                        state.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                    }
                } else {
                    self.providerRefreshModel.mutateProviderState { state in
                        state.snapshots[descriptor.id] = self.boundedSnapshot(fetched)
                    }
                }
            },
            clearProviderError: { providerID in
                self.providerRefreshModel.mutateProviderState { state in
                    state.errors.removeValue(forKey: providerID)
                }
            },
            clearProviderFailures: { providerID in
                self.providerRefreshModel.mutateProviderState { state in
                    state.consecutiveFailures[providerID] = 0
                }
            },
            markLastUpdatedAt: { date in
                self.providerRefreshModel.mutateProviderState { state in
                    state.lastUpdatedAt = date
                }
            },
            setProviderEnabled: { providerID in
                if let index = self.config.providers.firstIndex(where: { $0.id == providerID }) {
                    self.config.providers[index].enabled = true
                }
            },
            normalizeStatusBarSelections: { self.normalizeStatusBarSelections() },
            persistConfiguration: { self.persistConfiguration(showFeedback: false) },
            restartPolling: { self.restartPolling() },
            notifyStatusBarDisplayConfigChanged: { self.notifyStatusBarDisplayConfigChanged() },
            displayNameForDiscovery: { self.displayNameForDiscovery($0) },
            nothingFoundText: text(.localDiscoveryNothingFound),
            language: config.language
        )
    }

    var aggregateStatus: AggregateStatus {
        let enabled = config.providers.filter(\.enabled)
        if enabled.isEmpty {
            return .disconnected
        }

        let allErrored = enabled.allSatisfy { errors[$0.id] != nil }
        if allErrored {
            return .disconnected
        }

        if !activeAlerts.isEmpty || snapshots.values.contains(where: { $0.status == .warning || $0.status == .error }) {
            return .alert
        }

        return .normal
    }

}

extension ResourceMode {
    var refreshSchedulerConfig: ProviderRefreshSchedulerConfig {
        switch self {
        case .background3Minutes:
            return ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: intervalSeconds,
                localSessionSignalActiveSleepSeconds: 10,
                localSessionSignalIdleSleepSeconds: 30,
                inFlightProviderSleepSeconds: 5
            )
        case .background5Minutes:
            return ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: intervalSeconds,
                localSessionSignalActiveSleepSeconds: RuntimeDiagnosticsLimits.localSessionSignalActiveSleepSeconds,
                localSessionSignalIdleSleepSeconds: RuntimeDiagnosticsLimits.localSessionSignalIdleSleepSeconds,
                inFlightProviderSleepSeconds: 5
            )
        case .background10Minutes:
            return ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: intervalSeconds,
                localSessionSignalActiveSleepSeconds: 20,
                localSessionSignalIdleSleepSeconds: 90,
                inFlightProviderSleepSeconds: 10
            )
        case .background15Minutes:
            return ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: intervalSeconds,
                localSessionSignalActiveSleepSeconds: 30,
                localSessionSignalIdleSleepSeconds: 120,
                inFlightProviderSleepSeconds: 15
            )
        }
    }
}

private enum LocalUsageHistoryError: LocalizedError {
    case unsupportedProvider(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Unsupported local trend provider: \(provider)"
        }
    }
}

enum AggregateStatus {
    case normal
    case alert
    case disconnected

    var iconName: String {
        switch self {
        case .normal:
            return "checkmark.circle.fill"
        case .alert:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            return "xmark.octagon.fill"
        }
    }
}
