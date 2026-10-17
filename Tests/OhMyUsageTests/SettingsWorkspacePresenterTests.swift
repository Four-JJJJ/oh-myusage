import XCTest
@testable import OhMyUsage

final class SettingsWorkspacePresenterTests: XCTestCase {
    func testHeaderPresentationUsesOverviewCopy() {
        let presentation = SettingsWorkspacePresenter.headerPresentation(
            selectedTab: .overview,
            localizedText: Self.english,
            generalTabTitle: "General"
        )

        XCTAssertEqual(presentation.title, "Settings Overview")
        XCTAssertEqual(
            presentation.subtitle,
            "A scannable workspace for monitoring, permissions, and service configuration."
        )
        XCTAssertEqual(presentation.refreshButtonTitle, "Refresh All")
    }

    func testHeaderPresentationUsesCustomEndpointCopy() {
        let presentation = SettingsWorkspacePresenter.headerPresentation(
            selectedTab: .customProviders,
            localizedText: Self.english,
            generalTabTitle: "General"
        )

        XCTAssertEqual(presentation.title, "Custom Endpoints")
        XCTAssertEqual(
            presentation.subtitle,
            "Configure Relay, New API, and third-party balance endpoints."
        )
    }

    func testOfficialServicesUseUnifiedListCopy() {
        let header = SettingsWorkspacePresenter.headerPresentation(
            selectedTab: .officialProviders,
            localizedText: Self.english,
            generalTabTitle: "General"
        )
        XCTAssertEqual(header.title, "Official Services")
        XCTAssertEqual(
            header.subtitle,
            "Manage official accounts, credentials, and usage in one list, with API services labeled by name."
        )

        let sidebar = SettingsWorkspacePresenter.sidebarPresentation(
            localizedText: { zhHans, _ in zhHans },
            generalTabTitle: "通用"
        )
        let officialItems = sidebar.sections.flatMap(\.items).filter { $0.tab == .officialProviders }
        XCTAssertEqual(officialItems.map(\.title), ["官方服务"])
    }

    func testSidebarPresentationBuildsExpectedSectionsAndLabels() {
        let presentation = SettingsWorkspacePresenter.sidebarPresentation(
            localizedText: Self.english,
            generalTabTitle: "General"
        )

        XCTAssertEqual(presentation.appTitle, "oh-myusage")
        XCTAssertEqual(presentation.appSubtitle, "Monitoring workspace")
        XCTAssertEqual(presentation.sections.map(\.id), ["main"])
        XCTAssertEqual(
            presentation.sections[0].items.map(\.title),
            ["Usage", "General", "Menubar", "Official", "Relay", "Buy me a coffee"]
        )
        XCTAssertEqual(
            presentation.sections[0].items.map(\.tab),
            [.usageAnalytics, .general, .menuBar, .officialProviders, .customProviders, .donate]
        )
        XCTAssertEqual(
            presentation.sections[0].items.map(\.icon),
            [
                "settings_sidebar_usage_icon",
                "settings_sidebar_general_icon",
                "settings_sidebar_menubar_icon",
                "settings_sidebar_official_icon",
                "settings_sidebar_relay_icon",
                "settings_sidebar_donate_icon"
            ]
        )
        XCTAssertEqual(
            presentation.sections[0].items.first?.iconName(isSelected: true),
            "settings_sidebar_usage_icon_selected"
        )
        XCTAssertEqual(
            presentation.sections[0].items.last?.iconName(isSelected: true),
            "settings_sidebar_donate_icon_selected"
        )
    }

    private static func english(_ zhHans: String, _ english: String) -> String {
        english
    }
}
