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
    let codexProfileSnapshotService = CodexProfileSnapshotService()
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
    @ObservationIgnored private let usageAnalyticsRefreshCoordinator: UsageAnalyticsRefreshCoordinator
    @ObservationIgnored var refreshScheduler: ProviderRefreshScheduler?
    @ObservationIgnored let providerRefreshCoordinator: AppProviderRefreshCoordinator
    @ObservationIgnored let officialAccountImportCoordinator = AppOfficialAccountImportCoordinator()
    @ObservationIgnored let officialAccountSwitchCoordinator = AppOfficialAccountSwitchCoordinator()
    @ObservationIgnored let officialProfileLifecycleCoordinator = AppOfficialProfileLifecycleCoordinator()
    @ObservationIgnored let officialProfileRefreshCoordinator = AppOfficialProfileRefreshCoordinator()
    @ObservationIgnored let officialProfileDisplayCoordinator = AppOfficialProfileDisplayCoordinator()
    @ObservationIgnored let officialProfileSyncCoordinator = AppOfficialProfileSyncCoordinator()
    @ObservationIgnored let codexFeedbackCoordinator = AppTransientFeedbackCoordinator<CodexSlotID, CodexSwitchFeedback>()
    @ObservationIgnored let claudeFeedbackCoordinator = AppTransientFeedbackCoordinator<CodexSlotID, ClaudeSwitchFeedback>()
    @ObservationIgnored let officialProviderSettingsCoordinator = AppOfficialProviderSettingsCoordinator()
    @ObservationIgnored let providerListMutationCoordinator = AppProviderListMutationCoordinator()
    @ObservationIgnored let providerCredentialCoordinator = AppProviderCredentialCoordinator()
    @ObservationIgnored let credentialLookupCoordinator = AppCredentialLookupCoordinator()
    @ObservationIgnored let permissionCoordinator = AppPermissionCoordinator()
    @ObservationIgnored let resetCoordinator = AppResetCoordinator()
    @ObservationIgnored let relayProviderSettingsCoordinator = AppRelayProviderSettingsCoordinator()
    @ObservationIgnored let relayDescriptorPreviewBuilder = RelayDescriptorPreviewBuilder()
    @ObservationIgnored let statusBarPreferencesCoordinator = AppStatusBarPreferencesCoordinator()
    @ObservationIgnored let configurationMutationCoordinator = AppConfigurationMutationCoordinator()
    @ObservationIgnored let settingsPersistenceFeedbackCoordinator: AppSettingsPersistenceFeedbackCoordinator
    @ObservationIgnored private let localProviderDiscoveryCoordinator = LocalProviderDiscoveryCoordinator()
    @ObservationIgnored private let localUsageHistoryRefreshCoordinator = LocalUsageHistoryRefreshCoordinator()
    @ObservationIgnored let codexOfficialProfileRefreshRuntime = CodexOfficialProfileRefreshRuntime()
    @ObservationIgnored let claudeOfficialProfileRefreshRuntime = ClaudeOfficialProfileRefreshRuntime()
    @ObservationIgnored let updateCoordinator: AppUpdateCoordinator
    @ObservationIgnored let codexSwitchCoordinator = AccountSwitchTransactionCoordinator<CodexSlotID>()
    @ObservationIgnored let claudeSwitchCoordinator = AccountSwitchTransactionCoordinator<CodexSlotID>()
    private var sessionStore = AppSessionStore()

    var settingsPersistenceStatus = SettingsPersistenceDisplayState(
        kind: .idle,
        statusText: nil,
        tone: .neutral
    )
    var settingsPersistenceErrorMessage: String?

    var config: AppConfig
    var snapshots: [String: UsageSnapshot] {
        get { sessionStore.providerState.snapshots }
        set { sessionStore.providerState.snapshots = newValue }
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
        get { sessionStore.providerState.errors }
        set { sessionStore.providerState.errors = newValue }
    }
    var lastUpdatedAt: Date? {
        get { sessionStore.providerState.lastUpdatedAt }
        set { sessionStore.providerState.lastUpdatedAt = newValue }
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
    private(set) var localUsageHistoryVersion: Int {
        get { sessionStore.providerState.localUsageHistoryVersion }
        set { sessionStore.providerState.localUsageHistoryVersion = newValue }
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

    var codexOAuthImportTask: Task<Void, Never>?
    var claudeOAuthImportTask: Task<Void, Never>?
    var didRunClaudeAutoCaptureCompaction = false
    var notificationPermissionPollingTask: Task<Void, Never>?
    @ObservationIgnored var permissionRefreshTask: Task<Void, Never>?
    var credentialLookupVersion: Int {
        get { sessionStore.credentialLookupVersion }
        set { sessionStore.credentialLookupVersion = newValue }
    }
    var consecutiveFailures: [String: Int] {
        get { sessionStore.providerState.consecutiveFailures }
        set { sessionStore.providerState.consecutiveFailures = newValue }
    }
    var activeAlerts: Set<String> {
        get { sessionStore.providerState.activeAlerts }
        set { sessionStore.providerState.activeAlerts = newValue }
    }
    var thirdPartyBalanceBaselineTracker: ThirdPartyBalanceBaselineTracker {
        get { sessionStore.providerState.thirdPartyBalanceBaselineTracker }
        set { sessionStore.providerState.thirdPartyBalanceBaselineTracker = newValue }
    }
    var hasStarted: Bool {
        get { sessionStore.hasStarted }
        set { sessionStore.hasStarted = newValue }
    }
    var lastPermissionStatusRefreshAt: Date {
        get { sessionStore.permissionState.lastPermissionStatusRefreshAt }
        set { sessionStore.permissionState.lastPermissionStatusRefreshAt = newValue }
    }
    private var preparedUpdate: PreparedAppUpdate? {
        get { sessionStore.updateState.preparedUpdate }
        set { sessionStore.updateState.preparedUpdate = newValue }
    }
    private var preparedUpdateInfo: AppUpdateInfo? {
        get { sessionStore.updateState.preparedUpdateInfo }
        set { sessionStore.updateState.preparedUpdateInfo = newValue }
    }
    private var updateFlowVersionInFlight: String? {
        get { sessionStore.updateState.updateFlowVersionInFlight }
        set { sessionStore.updateState.updateFlowVersionInFlight = newValue }
    }

    init(
        configurationRepository: any AppConfigurationRepositorying = AppConfigurationRepository(),
        appUpdateService: any AppUpdateServicing = AppUpdateService(),
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore(),
        codexSlotStore: CodexAccountSlotStore = CodexAccountSlotStore(),
        codexProfileStore: CodexAccountProfileStore = CodexAccountProfileStore(),
        codexDesktopAuthService: CodexDesktopAuthService = CodexDesktopAuthService(),
        codexDesktopAppService: CodexDesktopAppService = CodexDesktopAppService(),
        notificationService: NotificationService = NotificationService(),
        providerFactory: (any ProviderFactorying)? = nil,
        keychain: KeychainService = KeychainService(),
        localUsageHistoryRepository: LocalUsageHistoryRepository = LocalUsageHistoryRepository(),
        usageAnalyticsRefreshCoordinator: UsageAnalyticsRefreshCoordinator = UsageAnalyticsRefreshCoordinator(),
        updateInstallBufferDelaySeconds: TimeInterval = 2,
        updateCheckStatusClearDelaySeconds: TimeInterval = 10,
        settingsPersistenceStatusClearDelaySeconds: TimeInterval = 4
    ) {
        self.keychain = keychain
        self.configurationRepository = configurationRepository
        self.credentialAccessService = CredentialAccessService(keychain: keychain)
        self.codexSlotStore = codexSlotStore
        self.codexProfileStore = codexProfileStore
        self.codexDesktopAuthService = codexDesktopAuthService
        self.codexDesktopAppService = codexDesktopAppService
        self.notifications = notificationService
        let resolvedProviderFactory = providerFactory ?? ProviderFactory(keychain: keychain)
        self.providerRefreshCoordinator = AppProviderRefreshCoordinator(
            providerFactory: resolvedProviderFactory,
            notifications: notificationService
        )
        self.updateCoordinator = AppUpdateCoordinator(
            appUpdateService: appUpdateService,
            postUpdateReleaseNotesStore: postUpdateReleaseNotesStore,
            updateInstallBufferDelaySeconds: updateInstallBufferDelaySeconds,
            updateCheckStatusClearDelaySeconds: updateCheckStatusClearDelaySeconds
        )
        self.settingsPersistenceFeedbackCoordinator = AppSettingsPersistenceFeedbackCoordinator(
            clearDelaySeconds: settingsPersistenceStatusClearDelaySeconds
        )
        let shouldPersistConfigDuringBootstrap: Bool
        var loadedConfig: AppConfig
        do {
            loadedConfig = try configurationRepository.load()
            shouldPersistConfigDuringBootstrap = !configurationRepository.lastLoadWasLossy
        } catch {
            loadedConfig = .default
            shouldPersistConfigDuringBootstrap = false
        }
        self.config = loadedConfig
        self.providerFactory = resolvedProviderFactory
        self.localUsageHistoryRepository = localUsageHistoryRepository
        self.usageAnalyticsRefreshCoordinator = usageAnalyticsRefreshCoordinator
        self.localSessionRefreshCoordinator = LocalSessionRefreshCoordinator(
            signalSource: localSessionSignalMonitor
        )
        self.refreshScheduler = makeRefreshScheduler()
        self.currentAppVersion = AppVersionResolver.detectCurrentAppVersion()
        self.codexSlots = codexSlotStore.visibleSlots()
        self.claudeSlots = claudeSlotStore.visibleSlots()
        self.codexProfiles = []
        self.claudeProfiles = []
        thirdPartyBalanceBaselineTracker.restore(entries: thirdPartyBalanceBaselineStore.load())
        let preNormalizedConfig = self.config
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        if shouldPersistConfigDuringBootstrap && self.config != preNormalizedConfig {
            _ = configurationRepository.saveDuringBootstrapResult(self.config)
        }
        launchAtLoginService.migrateLegacyLaunchAgentsIfNeeded()
        let launchAtLoginEnabled = launchAtLoginService.isEnabled()
        if self.config.launchAtLoginEnabled != launchAtLoginEnabled {
            self.config.launchAtLoginEnabled = launchAtLoginEnabled
            if shouldPersistConfigDuringBootstrap {
                _ = configurationRepository.saveDuringBootstrapResult(self.config)
            }
        }
        syncCodexProfilesCurrentState()
        bootstrapClaudeProfileState()
        restorePersistedOfficialProvidersIfNeeded()
        refreshPermissionStatuses(force: true)
    }

#if DEBUG
    init(
        testingConfig: AppConfig = .default,
        testingCurrentAppVersion: String = "0.0.0",
        configurationRepository: any AppConfigurationRepositorying = AppViewModel.makeTestingConfigurationRepository(),
        appUpdateService: any AppUpdateServicing,
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore(),
        codexSlotStore: CodexAccountSlotStore = CodexAccountSlotStore(),
        codexProfileStore: CodexAccountProfileStore = CodexAccountProfileStore(),
        codexDesktopAuthService: CodexDesktopAuthService = CodexDesktopAuthService(),
        codexDesktopAppService: CodexDesktopAppService = CodexDesktopAppService(),
        notificationService: NotificationService = NotificationService(),
        providerFactory: (any ProviderFactorying)? = nil,
        keychain: KeychainService = KeychainService(),
        localUsageHistoryRepository: LocalUsageHistoryRepository = LocalUsageHistoryRepository(),
        usageAnalyticsRefreshCoordinator: UsageAnalyticsRefreshCoordinator = UsageAnalyticsRefreshCoordinator(),
        updateInstallBufferDelaySeconds: TimeInterval = 2,
        updateCheckStatusClearDelaySeconds: TimeInterval = 10,
        settingsPersistenceStatusClearDelaySeconds: TimeInterval = 4
    ) {
        self.keychain = keychain
        self.configurationRepository = configurationRepository
        self.credentialAccessService = CredentialAccessService(keychain: keychain)
        self.codexSlotStore = codexSlotStore
        self.codexProfileStore = codexProfileStore
        self.codexDesktopAuthService = codexDesktopAuthService
        self.codexDesktopAppService = codexDesktopAppService
        self.notifications = notificationService
        let resolvedProviderFactory = providerFactory ?? ProviderFactory(keychain: keychain)
        self.providerRefreshCoordinator = AppProviderRefreshCoordinator(
            providerFactory: resolvedProviderFactory,
            notifications: notificationService
        )
        self.updateCoordinator = AppUpdateCoordinator(
            appUpdateService: appUpdateService,
            postUpdateReleaseNotesStore: postUpdateReleaseNotesStore,
            updateInstallBufferDelaySeconds: updateInstallBufferDelaySeconds,
            updateCheckStatusClearDelaySeconds: updateCheckStatusClearDelaySeconds
        )
        self.settingsPersistenceFeedbackCoordinator = AppSettingsPersistenceFeedbackCoordinator(
            clearDelaySeconds: settingsPersistenceStatusClearDelaySeconds
        )
        self.config = testingConfig.migratedWithSiteDefaults()
        self.providerFactory = resolvedProviderFactory
        self.localUsageHistoryRepository = localUsageHistoryRepository
        self.usageAnalyticsRefreshCoordinator = usageAnalyticsRefreshCoordinator
        self.localSessionRefreshCoordinator = LocalSessionRefreshCoordinator(
            signalSource: localSessionSignalMonitor
        )
        self.refreshScheduler = makeRefreshScheduler()
        self.currentAppVersion = testingCurrentAppVersion
        self.codexSlots = codexSlotStore.visibleSlots()
        self.claudeSlots = claudeSlotStore.visibleSlots()
        self.codexProfiles = []
        self.claudeProfiles = []
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        syncCodexProfilesCurrentState()
        bootstrapClaudeProfileState()
        restorePersistedOfficialProvidersIfNeeded()
    }

    private static func makeTestingConfigurationRepository() -> AppConfigurationRepository {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return AppConfigurationRepository(store: ConfigStore(baseDirectoryURL: root))
    }
#endif

    private func makeRefreshScheduler() -> ProviderRefreshScheduler {
        ProviderRefreshScheduler(
            descriptorProvider: { [weak self] providerID in
                guard let descriptor = self?.descriptor(for: providerID) else {
                    return nil
                }
                return self?.providerRefreshCoordinator.refreshScheduleDescriptor(for: descriptor)
            },
            providersProvider: { [weak self] in
                self?.providerRefreshCoordinator.refreshScheduleDescriptors(from: self?.config.providers ?? []) ?? []
            },
            activeProviderIDsProvider: { [weak self] in
                Set(self?.statusBarProvidersForDisplay().map(\.id) ?? [])
            },
            failureCountProvider: { [weak self] providerID in
                self?.consecutiveFailures[providerID, default: 0] ?? 0
            },
            refreshAction: { [weak self] providerID, forceRefresh in
                guard let descriptor = self?.descriptor(for: providerID) else { return }
                await self?.refreshProvider(descriptor, forceRefresh: forceRefresh)
            },
            localSessionRefreshCoordinator: localSessionRefreshCoordinator,
            config: config.resourceMode.refreshSchedulerConfig
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshPermissionStatuses(force: true)
        restartPolling()
        refreshDisplayedStatusBarProviders()
    }

    func restartPolling() {
        refreshScheduler?.restart(
            providers: providerRefreshCoordinator.refreshScheduleDescriptors(from: config.providers)
        )
    }

    func refreshNow() {
        refreshScheduler?.refreshNow(
            providers: providerRefreshCoordinator.refreshScheduleDescriptors(from: config.providers)
        )
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

    var hasNotificationPermission: Bool {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    var shouldShowPermissionGuide: Bool {
        let hasEnabledProviders = config.providers.contains(where: \.enabled)
        return AppPermissionCoordinator.shouldShowPermissionGuide(
            hasEnabledProviders: hasEnabledProviders,
            hasPersistedOfficialMonitoringState: hasPersistedOfficialMonitoringState,
            hasNotificationPermission: hasNotificationPermission,
            secureStorageReady: secureStorageReady,
            fullDiskAccessRelevant: fullDiskAccessRelevant,
            fullDiskAccessRequested: fullDiskAccessRequested,
            fullDiskAccessGranted: fullDiskAccessGranted
        )
    }

    var canRunLocalDiscoveryFromOnboarding: Bool {
        guard secureStorageReady else { return false }
        if fullDiskAccessRelevant || fullDiskAccessRequested {
            return fullDiskAccessGranted
        }
        return true
    }

    func setLanguage(_ language: AppLanguage) {
        guard let outcome = configurationMutationCoordinator.setLanguage(
            language,
            config: &config,
            repository: configurationRepository,
            showFeedback: true,
            successText: localizedText("已保存", "Saved"),
            failureText: localizedText("保存失败", "Save Failed")
        ) else { return }
        applyConfigurationPersistenceOutcome(outcome)
    }

    func setResourceMode(_ resourceMode: ResourceMode) {
        guard let outcome = configurationMutationCoordinator.setResourceMode(
            resourceMode,
            config: &config,
            repository: configurationRepository,
            showFeedback: true,
            successText: localizedText("已保存", "Saved"),
            failureText: localizedText("保存失败", "Save Failed")
        ) else { return }
        if applyConfigurationPersistenceOutcome(outcome) {
            refreshScheduler = makeRefreshScheduler()
            restartPolling()
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard let outcome = configurationMutationCoordinator.setLaunchAtLoginEnabled(
            enabled,
            config: &config,
            setLaunchAtLogin: { try launchAtLoginService.setEnabled($0) },
            repository: configurationRepository,
            showFeedback: true,
            successText: localizedText("已保存", "Saved"),
            failureText: localizedText("保存失败", "Save Failed")
        ) else { return }
        if let persistence = outcome.persistence {
            _ = applyConfigurationPersistenceOutcome(persistence)
        }
        if let errorMessage = outcome.errorMessage {
            errors["launch-at-login"] = errorMessage
        }
    }

    func setGlobalRefreshIntervalSeconds(_ seconds: Int) {
        let supported = [15, 30, 60, 300]
        let normalized = supported.contains(seconds) ? seconds : 60
        guard config.providers.contains(where: { $0.pollIntervalSec != normalized }) else { return }

        for index in config.providers.indices {
            config.providers[index].pollIntervalSec = normalized
        }

        if persistConfiguration(showFeedback: true) {
            restartPolling()
        }
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
            pollTaskCount: refreshScheduler?.pollTaskCount ?? 0,
            enabledProviderCount: config.providers.filter(\.enabled).count,
            providerErrorCount: errors.count,
            consecutiveFailureTotal: consecutiveFailures.values.reduce(0, +)
        )
    }

    var settingsPersistenceDisplayState: SettingsPersistenceDisplayState {
        settingsPersistenceStatus
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
            self?.localUsageHistoryVersion += 1
        }
    }

    func refreshUsageAnalytics() {
        refreshUsageAnalyticsIfNeeded(force: true)
    }

    func refreshUsageAnalyticsIfNeeded(force: Bool = false) {
        usageAnalyticsRefreshCoordinator.refreshUsageAnalyticsIfNeeded(
            filter: usageAnalyticsFilter,
            currentSnapshotFilter: usageAnalyticsSnapshot.filter,
            claudeAllConfigDirs: usageAnalyticsClaudeAllConfigDirs(),
            force: force,
            onSnapshotChange: { [weak self] snapshot in
                self?.usageAnalyticsSnapshot = snapshot
            },
            onLoadingChange: { [weak self] isLoading in
                self?.usageAnalyticsLoading = isLoading
            }
        )
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
                    self.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                } else if descriptor.type == .claude {
                    let snapshot = self.markClaudeSnapshotActive(fetched)
                    self.claudeSlots = self.claudeSlotStore.upsertActive(snapshot: snapshot)
                    self.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                } else {
                    self.snapshots[descriptor.id] = self.boundedSnapshot(fetched)
                }
            },
            clearProviderError: { self.errors.removeValue(forKey: $0) },
            clearProviderFailures: { self.consecutiveFailures[$0] = 0 },
            markLastUpdatedAt: { self.lastUpdatedAt = $0 },
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

    func refreshProvider(_ descriptor: ProviderDescriptor, forceRefresh: Bool = false) async {
        await providerRefreshCoordinator.refreshProvider(
            descriptor: descriptor,
            forceRefresh: forceRefresh,
            getState: { self.sessionStore.providerState },
            setState: { self.sessionStore.providerState = $0 },
            beforeRefresh: { descriptor in
                if descriptor.type == .codex, descriptor.family == .official {
                    self.syncCodexProfilesCurrentState()
                }
                if descriptor.type == .claude, descriptor.family == .official {
                    self.syncClaudeProfilesCurrentState()
                }
            },
            transformFetchedSnapshot: { descriptor, fetched in
                if descriptor.type == .codex, descriptor.family == .official {
                    let snapshot = self.markCodexSnapshotActive(fetched)
                    self.codexSlots = self.codexSlotStore.upsertActive(snapshot: snapshot)
                    return snapshot
                }
                if descriptor.type == .claude, descriptor.family == .official {
                    let snapshot = self.markClaudeSnapshotActive(fetched)
                    self.claudeSlots = self.claudeSlotStore.upsertActive(snapshot: snapshot)
                    return snapshot
                }
                return fetched
            },
            postOfficialRefresh: { descriptor, forceRefresh in
                guard descriptor.family == .official else { return }
                if forceRefresh {
                    await self.refreshOfficialProfileCardsAfterManualRefresh(for: descriptor)
                } else {
                    await self.refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for: descriptor)
                }
            },
            persistBaselineEntries: { entries in
                self.thirdPartyBalanceBaselineStore.save(entries)
            },
            afterRefresh: {
                self.pruneThirdPartyBalanceBaselines()
            },
            notifyStatusBarDisplayConfigChanged: {
                self.notifyStatusBarDisplayConfigChanged()
            },
            text: { key in
                self.text(key)
            },
            localizedText: { zhHans, en in
                self.localizedText(zhHans, en)
            },
            language: {
                self.config.language
            },
            boundedSnapshot: { snapshot in
                self.boundedSnapshot(snapshot)
            }
        )
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
