import XCTest
@testable import OhMyUsage

final class AppRelayProviderSettingsCoordinatorTests: XCTestCase {
    func testUpdateOpenProviderSettingsNameChangeRequestsPersistAndNotify() {
        let coordinator = AppRelayProviderSettingsCoordinator()
        var provider = ProviderDescriptor.makeOpenRelay(
            name: "Relay Existing",
            baseURL: "https://relay-settings.example.com"
        )
        provider.id = "relay-settings-mutation"
        var providers = [provider]
        let draft = RelaySettingsDraft(provider: provider)
        var updatedDraft = draft
        updatedDraft.name = "Relay Renamed"

        let outcome = coordinator.updateOpenProviderSettings(
            draft: updatedDraft,
            providers: &providers
        )

        XCTAssertEqual(providers[0].name, "Relay Renamed")
        XCTAssertEqual(
            outcome,
            AppProviderSettingsMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: true
            )
        )
    }

    func testUpdateThirdPartyQuotaDisplayModeOnlyNotifiesWhenDisplayModeChanges() {
        let coordinator = AppRelayProviderSettingsCoordinator()
        var provider = ProviderDescriptor.makeOpenRelay(
            name: "Relay Existing",
            baseURL: "https://relay-settings.example.com"
        )
        provider.id = "relay-quota-mode"
        var providers = [provider]

        let changedOutcome = coordinator.updateThirdPartyQuotaDisplayMode(
            providerID: provider.id,
            quotaDisplayMode: .used,
            providers: &providers
        )
        let unchangedOutcome = coordinator.updateThirdPartyQuotaDisplayMode(
            providerID: provider.id,
            quotaDisplayMode: .used,
            providers: &providers
        )

        XCTAssertEqual(providers[0].relayConfig?.quotaDisplayMode, .used)
        XCTAssertEqual(
            changedOutcome,
            AppProviderSettingsMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: true
            )
        )
        XCTAssertEqual(
            unchangedOutcome,
            AppProviderSettingsMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: false
            )
        )
    }

    func testUpdateQuotaDisplayModeSupportsOfficialRelayProviders() {
        let coordinator = AppRelayProviderSettingsCoordinator()
        var provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        provider.relayConfig?.quotaDisplayMode = .used
        var providers = [provider]

        let outcome = coordinator.updateThirdPartyQuotaDisplayMode(
            providerID: provider.id,
            quotaDisplayMode: .remaining,
            providers: &providers
        )

        XCTAssertEqual(providers[0].relayConfig?.quotaDisplayMode, .remaining)
        XCTAssertFalse(providers[0].displaysUsedQuota)
        XCTAssertEqual(
            outcome,
            AppProviderSettingsMutationOutcome(
                shouldPersistAndRestart: true,
                shouldNotifyDisplayConfigChange: true
            )
        )
    }
}
