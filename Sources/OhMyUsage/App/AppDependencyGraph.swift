import Foundation

/// Assembled App runtime dependencies owned by the executable composition boundary.
/// Built by `AppCompositionFactory`; consumed by `AppViewModel` instead of inline service-tree wiring.
@MainActor
struct AppDependencyGraph {
    let keychain: KeychainService
    let configurationRepository: any AppConfigurationRepositorying
    let credentialAccessService: CredentialAccessService
    let codexSlotStore: CodexAccountSlotStore
    let codexProfileStore: CodexAccountProfileStore
    let codexDesktopAuthService: CodexDesktopAuthService
    let codexDesktopAppService: CodexDesktopAppService
    let codexProfileSnapshotService: CodexProfileSnapshotService
    let notifications: NotificationService
    let providerFactory: any ProviderFactorying
    let providerRefreshModel: AppProviderRefreshModel
    let permissionModel: AppPermissionModel
    let updateModel: AppUpdateModel
    let configurationModel: AppConfigurationModel
    let localUsageHistoryRepository: LocalUsageHistoryRepository
    let usageAnalyticsModel: AppUsageAnalyticsModel
}
