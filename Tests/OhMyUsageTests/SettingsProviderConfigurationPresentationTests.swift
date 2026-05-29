import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class SettingsProviderConfigurationPresentationTests: XCTestCase {
    func testOfficialRelayProvidersUseRelayConfigurationSectionAndExposeCredentialModeDefaults() {
        let providers = [
            ProviderDescriptor.defaultOfficialMoonshot(),
            ProviderDescriptor.defaultOfficialMiniMax(),
            ProviderDescriptor.defaultOfficialDeepSeek(),
            ProviderDescriptor.defaultOfficialXiaomiMIMO()
        ]

        for provider in providers {
            XCTAssertEqual(
                SettingsProviderConfigurationSectionPresenter.sectionKind(for: provider),
                .relay,
                "\(provider.id) should render the relay configuration controls in Official subscriptions"
            )
            XCTAssertEqual(provider.relayConfig?.balanceCredentialMode, .manualPreferred)
            XCTAssertEqual(RelaySettingsDraftSeed(provider: provider).balanceCredentialMode, .manualPreferred)
        }
    }

    func testNonRelayOfficialProvidersUseOfficialConfigurationSection() {
        let providers = [
            ProviderDescriptor.defaultOfficialKimi(),
            ProviderDescriptor.defaultOfficialCodex(),
            ProviderDescriptor.defaultOfficialClaude()
        ]

        for provider in providers {
            XCTAssertEqual(
                SettingsProviderConfigurationSectionPresenter.sectionKind(for: provider),
                .official,
                "\(provider.id) should keep the standard official configuration controls"
            )
        }
    }

    func testRelayDraftPersistsCredentialModeForOfficialRelayProvider() {
        let provider = ProviderDescriptor.defaultOfficialMiniMax()
        var draft = RelaySettingsDraftSeed(provider: provider).draft
        draft.balanceCredentialMode = .browserPreferred

        let preview = RelayDescriptorPreviewBuilder().build(
            draft: draft,
            providers: [provider]
        )

        XCTAssertEqual(preview?.family, .official)
        XCTAssertEqual(preview?.type, .relay)
        XCTAssertEqual(preview?.relayConfig?.adapterID, "minimax")
        XCTAssertEqual(preview?.relayConfig?.balanceCredentialMode, .browserPreferred)
    }
}
