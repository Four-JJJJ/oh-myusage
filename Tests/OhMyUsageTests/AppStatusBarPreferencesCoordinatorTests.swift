import XCTest
@testable import OhMyUsage

final class AppStatusBarPreferencesCoordinatorTests: XCTestCase {
    func testSetStatusBarMultiUsageEnabledSeedsSelectedProviderAndRequestsRefresh() {
        var config = AppConfig(
            statusBarProviderID: "alpha",
            statusBarMultiUsageEnabled: false,
            providers: [
                makeProvider(id: "alpha"),
                makeProvider(id: "beta")
            ]
        )
        let coordinator = AppStatusBarPreferencesCoordinator()

        let outcome = coordinator.setStatusBarMultiUsageEnabled(
            true,
            config: &config,
            visibleClaudeMonitoringSlotIDs: []
        )

        XCTAssertTrue(config.statusBarMultiUsageEnabled)
        XCTAssertEqual(config.statusBarMultiProviderIDs, ["alpha"])
        XCTAssertEqual(
            outcome,
            StatusBarPreferencesMutationOutcome(
                shouldPersist: true,
                shouldNotifyDisplayConfigChange: true,
                shouldRefreshDisplayedProviders: true
            )
        )
    }

    func testSetStatusBarProviderUpdatesSelectionAndRequestsRefresh() {
        var config = AppConfig(
            statusBarProviderID: "alpha",
            providers: [
                makeProvider(id: "alpha"),
                makeProvider(id: "beta")
            ]
        )
        let coordinator = AppStatusBarPreferencesCoordinator()

        let outcome = coordinator.setStatusBarProvider(
            providerID: "beta",
            config: &config,
            visibleClaudeMonitoringSlotIDs: []
        )

        XCTAssertEqual(config.statusBarProviderID, "beta")
        XCTAssertEqual(
            outcome,
            StatusBarPreferencesMutationOutcome(
                shouldPersist: true,
                shouldNotifyDisplayConfigChange: true,
                shouldRefreshDisplayedProviders: true
            )
        )
    }

    func testSetStatusBarDisplayDisabledHidesSelectedSingleProvider() {
        var config = AppConfig(
            statusBarProviderID: "alpha",
            providers: [
                makeProvider(id: "alpha")
            ]
        )
        let coordinator = AppStatusBarPreferencesCoordinator()

        let outcome = coordinator.setStatusBarDisplayEnabled(
            false,
            providerID: "alpha",
            config: &config,
            visibleClaudeMonitoringSlotIDs: []
        )

        XCTAssertFalse(config.providers[0].showsInMenuBar)
        XCTAssertNil(config.statusBarProviderID)
        XCTAssertEqual(
            outcome,
            StatusBarPreferencesMutationOutcome(
                shouldPersist: true,
                shouldNotifyDisplayConfigChange: true,
                shouldRefreshDisplayedProviders: true
            )
        )
    }

    func testSetStatusBarDisplayDisabledFallsBackToNextVisibleProvider() {
        var config = AppConfig(
            statusBarProviderID: "alpha",
            providers: [
                makeProvider(id: "alpha"),
                makeProvider(id: "beta")
            ]
        )
        let coordinator = AppStatusBarPreferencesCoordinator()

        _ = coordinator.setStatusBarDisplayEnabled(
            false,
            providerID: "alpha",
            config: &config,
            visibleClaudeMonitoringSlotIDs: []
        )

        XCTAssertEqual(config.statusBarProviderID, "beta")
        XCTAssertFalse(config.providers.first(where: { $0.id == "alpha" })?.showsInMenuBar ?? true)
    }

    func testSetShowOfficialPlanTypeInMenuBarMutatesOfficialConfigAndNotifies() {
        var provider = ProviderDescriptor.defaultOfficialCodex()
        provider.enabled = false
        var config = AppConfig(providers: [provider])
        let coordinator = AppStatusBarPreferencesCoordinator()

        let outcome = coordinator.setShowOfficialPlanTypeInMenuBar(
            false,
            providerID: provider.id,
            config: &config
        )

        XCTAssertFalse(config.providers[0].officialConfig?.showPlanTypeInMenuBar ?? true)
        XCTAssertEqual(
            outcome,
            StatusBarPreferencesMutationOutcome(
                shouldPersist: true,
                shouldNotifyDisplayConfigChange: true,
                shouldRefreshDisplayedProviders: false
            )
        )
    }

    func testSetShowExpirationTimeInMenuBarMutatesOfficialRelayConfigAndNotifies() {
        var provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        provider.enabled = false
        var config = AppConfig(providers: [provider])
        let coordinator = AppStatusBarPreferencesCoordinator()

        let outcome = coordinator.setShowExpirationTimeInMenuBar(
            false,
            providerID: provider.id,
            config: &config
        )

        XCTAssertFalse(config.providers[0].relayConfig?.showExpirationTimeInMenuBar ?? true)
        XCTAssertEqual(
            outcome,
            StatusBarPreferencesMutationOutcome(
                shouldPersist: true,
                shouldNotifyDisplayConfigChange: true,
                shouldRefreshDisplayedProviders: false
            )
        )
    }

    private func makeProvider(id: String) -> ProviderDescriptor {
        var provider = ProviderDescriptor.makeOpenRelay(
            name: id.capitalized,
            baseURL: "https://\(id).example.com"
        )
        provider.id = id
        provider.enabled = true
        return provider
    }
}
