import Foundation

/// Executable composition boundary for App runtime dependency wiring.
///
/// Layered `OhMyUsageBootstrap` / `OhMyUsageCompositionRoot` stay limited to pure Usage
/// feature composition and must not import this executable or construct `AppViewModel`.
/// Production and DEBUG `AppViewModel` initialization both build through this factory.
@MainActor
enum AppCompositionFactory {
    struct ProductionConfigBootstrap {
        let config: AppConfig
        let shouldPersistDuringBootstrap: Bool
    }

    static func makeDependencyGraph(
        configurationRepository: any AppConfigurationRepositorying = AppConfigurationRepository(),
        appUpdateService: any AppUpdateServicing = AppUpdateService(),
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore(),
        codexSlotStore: CodexAccountSlotStore = CodexAccountSlotStore(),
        codexProfileStore: CodexAccountProfileStore = CodexAccountProfileStore(),
        codexDesktopAuthService: CodexDesktopAuthService? = nil,
        claudeDesktopAuthService: ClaudeDesktopAuthService? = nil,
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
    ) -> AppDependencyGraph {
        let credentialBroker = CredentialBroker(keychain: keychain)
        // Phase 1 §7.6: the Codex / Claude OAuth JSON vault accounts are read and
        // written through the shared broker-backed vault store.
        let oauthVaultStore = OfficialOAuthVaultStore(keychain: credentialBroker)
        let resolvedCodexDesktopAuthService = codexDesktopAuthService ?? CodexDesktopAuthService(oauthVault: oauthVaultStore)
        let resolvedClaudeDesktopAuthService = claudeDesktopAuthService ?? ClaudeDesktopAuthService(oauthVault: oauthVaultStore)
        let resolvedProviderFactory = providerFactory ?? ProviderFactory(keychain: keychain, credentialBroker: credentialBroker)
        return AppDependencyGraph(
            keychain: keychain,
            credentialBroker: credentialBroker,
            oauthVaultStore: oauthVaultStore,
            configurationRepository: configurationRepository,
            credentialAccessService: CredentialAccessService(
                keychain: keychain,
                credentialBroker: credentialBroker
            ),
            codexSlotStore: codexSlotStore,
            codexProfileStore: codexProfileStore,
            codexDesktopAuthService: resolvedCodexDesktopAuthService,
            claudeDesktopAuthService: resolvedClaudeDesktopAuthService,
            codexDesktopAppService: codexDesktopAppService,
            codexProfileSnapshotService: codexProfileSnapshotService,
            notifications: notificationService,
            providerFactory: resolvedProviderFactory,
            providerRefreshModel: AppProviderRefreshModel(
                providerFactory: resolvedProviderFactory,
                notifications: notificationService
            ),
            permissionModel: AppPermissionModel(),
            updateModel: AppUpdateModel(
                appUpdateService: appUpdateService,
                postUpdateReleaseNotesStore: postUpdateReleaseNotesStore,
                updateInstallBufferDelaySeconds: updateInstallBufferDelaySeconds,
                updateCheckStatusClearDelaySeconds: updateCheckStatusClearDelaySeconds
            ),
            configurationModel: AppConfigurationModel(
                settingsPersistenceStatusClearDelaySeconds: settingsPersistenceStatusClearDelaySeconds
            ),
            localUsageHistoryRepository: localUsageHistoryRepository,
            usageAnalyticsModel: AppUsageAnalyticsModel(coordinator: usageAnalyticsRefreshCoordinator)
        )
    }

    static func loadProductionConfig(
        from configurationRepository: any AppConfigurationRepositorying
    ) -> ProductionConfigBootstrap {
        do {
            let loadedConfig = try configurationRepository.load()
            return ProductionConfigBootstrap(
                config: loadedConfig,
                shouldPersistDuringBootstrap: !configurationRepository.lastLoadWasLossy
            )
        } catch {
            return ProductionConfigBootstrap(
                config: .default,
                shouldPersistDuringBootstrap: false
            )
        }
    }
}
