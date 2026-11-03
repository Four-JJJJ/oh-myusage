import Foundation
import OhMyUsagePresentation


enum MenuPermissionGuidePresenter {
    typealias LocalDiscoveryState = MenuPermissionGuideLocalDiscoveryState

    static func build(
        language: AppLanguage,
        hasNotificationPermission: Bool,
        secureStorageReady: Bool,
        fullDiskAccessRelevant: Bool,
        fullDiskAccessRequested: Bool,
        fullDiskAccessGranted: Bool,
        canRunLocalDiscovery: Bool,
        localDiscoveryState: LocalDiscoveryState
    ) -> MenuPermissionGuidePresentation {
        MenuPermissionGuidePresentation.build(
            strings: strings(language: language),
            hasNotificationPermission: hasNotificationPermission,
            secureStorageReady: secureStorageReady,
            fullDiskAccessRelevant: fullDiskAccessRelevant,
            fullDiskAccessRequested: fullDiskAccessRequested,
            fullDiskAccessGranted: fullDiskAccessGranted,
            canRunLocalDiscovery: canRunLocalDiscovery,
            localDiscoveryState: localDiscoveryState
        )
    }

    private static func strings(language: AppLanguage) -> MenuPermissionGuideStrings {
        MenuPermissionGuideStrings(
            title: Localizer.text(.permissionsTitle, language: language),
            privacyPromise: Localizer.text(.permissionsPrivacyPromise, language: language),
            notifications: .init(
                title: Localizer.text(.permissionNotificationsTitle, language: language),
                hint: Localizer.text(.permissionNotificationsHint, language: language),
                actionTitle: Localizer.text(.permissionNotificationsAction, language: language)
            ),
            keychain: .init(
                title: Localizer.text(.permissionKeychainTitle, language: language),
                hint: Localizer.text(.permissionKeychainHint, language: language),
                actionTitle: Localizer.text(.permissionKeychainAction, language: language)
            ),
            fullDisk: .init(
                title: Localizer.text(.permissionFullDiskTitle, language: language),
                hint: Localizer.text(.permissionFullDiskHint, language: language),
                actionTitle: Localizer.text(.permissionFullDiskAction, language: language)
            ),
            localDiscovery: .init(
                title: Localizer.text(.localDiscoveryTitle, language: language),
                hint: Localizer.text(.localDiscoveryHint, language: language),
                actionTitle: Localizer.text(.localDiscoveryAction, language: language)
            ),
            grantedStatusText: grantedStatusText(language: language),
            pendingStatusText: pendingStatusText(language: language),
            waitingStatusText: waitingStatusText(language: language),
            localDiscoveryReadyStatusText: language == .zhHans ? "可开始" : "Ready",
            localDiscoveryDoneStatusText: language == .zhHans ? "已完成" : "Done"
        )
    }

    private static func grantedStatusText(language: AppLanguage) -> String {
        language == .zhHans ? "已授权" : "Allowed"
    }

    private static func pendingStatusText(language: AppLanguage) -> String {
        language == .zhHans ? "待授权" : "Pending"
    }

    private static func waitingStatusText(language: AppLanguage) -> String {
        language == .zhHans ? "待确认" : "Waiting"
    }
}
