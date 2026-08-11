import OhMyUsageDomain
import Foundation
import UserNotifications

/// Provider runtime state. Physically stored on `AppSessionStore` for Observation.
/// Logical writes must go through `AppProviderRefreshModel` (not direct VM projection assignment).
struct ProviderStateStore {
    var snapshots: [String: UsageSnapshot] = [:]
    var errors: [String: String] = [:]
    var lastUpdatedAt: Date?
    var localUsageHistoryVersion = 0
    var consecutiveFailures: [String: Int] = [:]
    var activeAlerts: Set<String> = []
    var thirdPartyBalanceBaselineTracker = ThirdPartyBalanceBaselineTracker()
}

struct AccountStore {
    var codexSlots: [CodexAccountSlot] = []
    var codexProfiles: [CodexAccountProfile] = []
    var codexSwitchFeedback: [CodexSlotID: CodexSwitchFeedback] = [:]
    var codexOAuthImportState: OAuthImportState?
    var claudeSlots: [ClaudeAccountSlot] = []
    var claudeProfiles: [ClaudeAccountProfile] = []
    var claudeSwitchFeedback: [CodexSlotID: ClaudeSwitchFeedback] = [:]
    var claudeOAuthImportState: OAuthImportState?
}

struct PermissionStore {
    var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    var secureStorageReady = false
    var fullDiskAccessGranted = false
    var fullDiskAccessRelevant = false
    var fullDiskAccessRequested = false
    var lastPermissionStatusRefreshAt = Date.distantPast
}

struct UpdateStore {
    var currentAppVersion = ""
    var availableUpdate: AppUpdateInfo?
    var lastUpdateCheckAt: Date?
    var updateCheckInFlight = false
    var lastCheckedLatestVersion: String?
    var updateCheckErrorMessage: String?
    var updateDownloadInFlight = false
    var updateInstallBufferingInFlight = false
    var updateInstallationInFlight = false
    var updatePreparedVersion: String?
    var updateInstallErrorMessage: String?
    var preparedUpdate: PreparedAppUpdate?
    var preparedUpdateInfo: AppUpdateInfo?
    var updateFlowVersionInFlight: String?
}

struct AppSessionStore {
    var providerState = ProviderStateStore()
    var accountState = AccountStore()
    var permissionState = PermissionStore()
    var updateState = UpdateStore()
    var menuPanelVisible = false
    var settingsWindowVisible = false
    var hasStarted = false
    var credentialLookupVersion = 0
}
