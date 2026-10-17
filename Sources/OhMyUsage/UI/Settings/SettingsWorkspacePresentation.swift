import Foundation

struct SettingsHeaderPresentation: Equatable {
    var title: String
    var subtitle: String
    var refreshButtonTitle: String
    var refreshHelpText: String
}

struct SettingsSidebarItemPresentation: Identifiable, Equatable {
    var tab: SettingsTab
    var icon: String
    var selectedIcon: String
    var title: String

    var id: String { tab.rawValue }

    init(tab: SettingsTab, icon: String, selectedIcon: String? = nil, title: String) {
        self.tab = tab
        self.icon = icon
        self.selectedIcon = selectedIcon ?? icon
        self.title = title
    }

    func iconName(isSelected: Bool) -> String {
        isSelected ? selectedIcon : icon
    }
}

struct SettingsSidebarSectionPresentation: Identifiable, Equatable {
    var id: String
    var title: String
    var items: [SettingsSidebarItemPresentation]
}

struct SettingsWorkspaceSidebarPresentation: Equatable {
    var appTitle: String
    var appSubtitle: String
    var currentVersionTitle: String
    var checkUpdatesTitle: String
    var updateButtonTitle: String
    var lastRefreshTitle: String
    var githubTitle: String
    var sections: [SettingsSidebarSectionPresentation]
}

enum SettingsWorkspacePresenter {
    static func headerPresentation(
        selectedTab: SettingsTab,
        localizedText: (String, String) -> String,
        generalTabTitle: String
    ) -> SettingsHeaderPresentation {
        let title: String
        let subtitle: String

        switch selectedTab {
        case .overview:
            title = localizedText("设置概览", "Settings Overview")
            subtitle = localizedText(
                "把监控、权限和服务配置收拢成一个可快速扫描的工作台。",
                "A scannable workspace for monitoring, permissions, and service configuration."
            )
        case .general:
            title = generalTabTitle
            subtitle = localizedText(
                "管理应用语言、启动行为和基础偏好。",
                "Manage app language, launch behavior, and basic preferences."
            )
        case .menuBar:
            title = localizedText("菜单栏", "Menubar")
            subtitle = localizedText(
                "调整菜单栏里显示哪些模型、如何显示以及跟随哪种外观。",
                "Adjust which models appear in the menubar, how they render, and which appearance mode they use."
            )
        case .usageAnalytics:
            title = localizedText("使用统计", "Usage Analytics")
            subtitle = localizedText(
                "汇总本地服务、模型和供应商的请求与 Token 使用趋势。",
                "Summarize local request and token usage by service, model, and provider."
            )
        case .permissions:
            title = localizedText("权限", "Permissions")
            subtitle = localizedText(
                "检查授权状态，确保通知、钥匙串和本地读取能力可用。",
                "Review authorization status for notifications, keychain, and local file access."
            )
        case .localData:
            title = localizedText("本地数据", "Local Data")
            subtitle = localizedText(
                "发现本地 CLI 账号配置，或在需要时清理本地应用数据。",
                "Discover local CLI account config or clear local app data when needed."
            )
        case .officialProviders:
            title = localizedText("官方服务", "Official Services")
            subtitle = localizedText(
                "统一管理官方服务的账号、凭证与用量，API 服务在名称后标注。",
                "Manage official accounts, credentials, and usage in one list, with API services labeled by name."
            )
        case .customProviders:
            title = localizedText("自定义接口", "Custom Endpoints")
            subtitle = localizedText(
                "配置 Relay、New API 和第三方余额接口。",
                "Configure Relay, New API, and third-party balance endpoints."
            )
        case .donate:
            title = localizedText("请我喝咖啡", "Buy me a coffee")
            subtitle = localizedText(
                "如果 oh-myusage 帮到了你，可以请我喝杯咖啡，或者随手赞赏支持一下继续维护。",
                "If oh-myusage has helped you, you can buy me a coffee or support continued maintenance."
            )
        }

        return SettingsHeaderPresentation(
            title: title,
            subtitle: subtitle,
            refreshButtonTitle: localizedText("刷新全部", "Refresh All"),
            refreshHelpText: localizedText("立即刷新所有已启用服务", "Refresh all enabled services now")
        )
    }

    static func sidebarPresentation(
        localizedText: (String, String) -> String,
        generalTabTitle: String
    ) -> SettingsWorkspaceSidebarPresentation {
        SettingsWorkspaceSidebarPresentation(
            appTitle: "oh-myusage",
            appSubtitle: localizedText("监控与设置工作台", "Monitoring workspace"),
            currentVersionTitle: localizedText("版本", "Version"),
            checkUpdatesTitle: localizedText("检查更新", "Check Updates"),
            updateButtonTitle: localizedText("更新版本", "Update App"),
            lastRefreshTitle: localizedText("最近刷新", "Last refresh"),
            githubTitle: "GitHub",
            sections: [
                SettingsSidebarSectionPresentation(
                    id: "main",
                    title: "",
                    items: [
                        SettingsSidebarItemPresentation(
                            tab: .usageAnalytics,
                            icon: "settings_sidebar_usage_icon",
                            selectedIcon: "settings_sidebar_usage_icon_selected",
                            title: localizedText("使用统计", "Usage")
                        ),
                        SettingsSidebarItemPresentation(
                            tab: .general,
                            icon: "settings_sidebar_general_icon",
                            title: generalTabTitle
                        ),
                        SettingsSidebarItemPresentation(
                            tab: .menuBar,
                            icon: "settings_sidebar_menubar_icon",
                            title: localizedText("菜单栏", "Menubar")
                        ),
                        SettingsSidebarItemPresentation(
                            tab: .officialProviders,
                            icon: "settings_sidebar_official_icon",
                            title: localizedText("官方服务", "Official")
                        ),
                        SettingsSidebarItemPresentation(
                            tab: .customProviders,
                            icon: "settings_sidebar_relay_icon",
                            title: localizedText("中转代理", "Relay")
                        ),
                        SettingsSidebarItemPresentation(
                            tab: .donate,
                            icon: "settings_sidebar_donate_icon",
                            selectedIcon: "settings_sidebar_donate_icon_selected",
                            title: localizedText("请我喝咖啡", "Buy me a coffee")
                        )
                    ]
                )
            ]
        )
    }
}
