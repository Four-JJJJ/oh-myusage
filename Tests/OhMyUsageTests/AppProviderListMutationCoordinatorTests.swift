import XCTest
@testable import OhMyUsage

final class AppProviderListMutationCoordinatorTests: XCTestCase {
    func testSetEnabledTogglesProviderStateAndRequestsPersistenceAndRefresh() {
        var provider = ProviderDescriptor.defaultOfficialCodex()
        provider.id = "codex-toggle"
        provider.enabled = false
        var config = AppConfig(providers: [provider])
        let coordinator = AppProviderListMutationCoordinator()

        let enableOutcome = coordinator.setEnabled(
            true,
            providerID: provider.id,
            config: &config
        )
        XCTAssertTrue(config.providers.first(where: { $0.id == provider.id })?.enabled ?? false)
        XCTAssertEqual(
            enableOutcome,
            AppProviderListMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: true,
                shouldRefreshDisplayedProviders: true
            )
        )

        let disableOutcome = coordinator.setEnabled(
            false,
            providerID: provider.id,
            config: &config
        )
        XCTAssertFalse(config.providers.first(where: { $0.id == provider.id })?.enabled ?? true)
        XCTAssertEqual(
            disableOutcome,
            AppProviderListMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: true,
                shouldRefreshDisplayedProviders: true
            )
        )
    }

    func testDisablingThirdPartyProviderClearsStatusBarSelectionAndRequestsBaselineRemoval() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Relay",
            baseURL: "https://relay.example.com"
        )
        relay.id = "relay-a"
        relay.enabled = true
        var config = AppConfig(
            statusBarProviderID: relay.id,
            providers: [relay]
        )
        let coordinator = AppProviderListMutationCoordinator()

        let outcome = coordinator.setEnabled(
            false,
            providerID: relay.id,
            config: &config
        )

        XCTAssertFalse(config.providers[0].enabled)
        XCTAssertNil(config.statusBarProviderID)
        XCTAssertEqual(
            outcome,
            AppProviderListMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: true,
                shouldRefreshDisplayedProviders: true,
                removedThirdPartyBaselineProviderIDs: [relay.id]
            )
        )
    }

    func testEnablingProviderMovesItAfterEnabledPeersInSameFamily() {
        var first = ProviderDescriptor.defaultOfficialCodex()
        first.id = "codex-a"
        first.enabled = true
        var second = ProviderDescriptor.defaultOfficialClaude()
        second.id = "claude-b"
        second.enabled = false
        var third = ProviderDescriptor.defaultOfficialGemini()
        third.id = "gemini-c"
        third.enabled = true
        var config = AppConfig(
            statusBarProviderID: first.id,
            providers: [first, second, third]
        )
        let coordinator = AppProviderListMutationCoordinator()

        _ = coordinator.setEnabled(
            true,
            providerID: second.id,
            config: &config
        )

        XCTAssertEqual(config.providers.map(\.id), ["codex-a", "gemini-c", "claude-b"])
        XCTAssertTrue(config.providers[2].enabled)
    }

    func testEnablingProviderDefaultsMenuBarDisplayOn() {
        var first = ProviderDescriptor.defaultOfficialCodex()
        first.id = "codex-a"
        first.enabled = true
        var second = ProviderDescriptor.defaultOfficialClaude()
        second.id = "claude-b"
        second.enabled = false
        second.showInMenuBar = false
        var config = AppConfig(
            statusBarProviderID: first.id,
            providers: [first, second]
        )
        let coordinator = AppProviderListMutationCoordinator()

        _ = coordinator.setEnabled(
            true,
            providerID: second.id,
            config: &config
        )

        let enabledProvider = config.providers.first(where: { $0.id == second.id })
        XCTAssertTrue(enabledProvider?.enabled ?? false)
        XCTAssertTrue(enabledProvider?.showsInMenuBar ?? false)
        XCTAssertEqual(config.statusBarProviderID, second.id)
    }

    func testEnablingProviderAddsItToMultiMenuBarDisplay() {
        var first = ProviderDescriptor.defaultOfficialCodex()
        first.id = "codex-a"
        first.enabled = true
        var second = ProviderDescriptor.defaultOfficialClaude()
        second.id = "claude-b"
        second.enabled = false
        second.showInMenuBar = false
        var config = AppConfig(
            statusBarProviderID: first.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: [first.id],
            providers: [first, second]
        )
        let coordinator = AppProviderListMutationCoordinator()

        _ = coordinator.setEnabled(
            true,
            providerID: second.id,
            config: &config
        )

        XCTAssertEqual(config.statusBarProviderID, second.id)
        XCTAssertEqual(config.statusBarMultiProviderIDs, [first.id, second.id])
    }

    func testReorderEnabledProvidersOnlyMovesEnabledProvidersWithinFamily() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.id = "codex-a"
        codex.enabled = true
        var claude = ProviderDescriptor.defaultOfficialClaude()
        claude.id = "claude-b"
        claude.enabled = false
        var gemini = ProviderDescriptor.defaultOfficialGemini()
        gemini.id = "gemini-c"
        gemini.enabled = true
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Relay",
            baseURL: "https://relay.example.com"
        )
        relay.id = "relay-d"
        relay.enabled = true

        var config = AppConfig(
            statusBarProviderID: codex.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: [codex.id, gemini.id, relay.id],
            providers: [codex, claude, gemini, relay]
        )
        let coordinator = AppProviderListMutationCoordinator()

        let outcome = coordinator.reorderEnabledProviders(
            family: .official,
            fromOffsets: IndexSet(integer: 0),
            toOffset: 2,
            config: &config
        )

        XCTAssertEqual(config.providers.map(\.id), ["gemini-c", "claude-b", "codex-a", "relay-d"])
        XCTAssertEqual(config.statusBarMultiProviderIDs, ["gemini-c", "codex-a", "relay-d"])
        XCTAssertEqual(
            outcome,
            AppProviderListMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: true
            )
        )
    }

    func testCommitThresholdClampsValueAndRequestsPersist() {
        var provider = ProviderDescriptor.defaultOfficialCodex()
        provider.id = "codex-threshold"
        provider.threshold.lowRemaining = 20
        var config = AppConfig(providers: [provider])
        let coordinator = AppProviderListMutationCoordinator()

        let outcome = coordinator.commitThreshold(
            140,
            providerID: provider.id,
            config: &config
        )

        XCTAssertEqual(config.providers[0].threshold.lowRemaining, 100)
        XCTAssertEqual(
            outcome,
            AppProviderListMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: false,
                shouldRefreshDisplayedProviders: false,
                removedThirdPartyBaselineProviderIDs: []
            )
        )
    }
}
