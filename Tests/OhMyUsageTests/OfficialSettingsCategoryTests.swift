import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class OfficialSettingsCategoryTests: XCTestCase {
    func testCodingPlansStaySubscriptionsEvenWhenFetchedThroughAPI() {
        for provider in [
            OfficialProviderDefaultCatalog.codex(),
            OfficialProviderDefaultCatalog.claude(),
            OfficialProviderDefaultCatalog.zai(),
            OfficialProviderDefaultCatalog.kimi(),
            OfficialProviderDefaultCatalog.qwen()
        ] {
            XCTAssertEqual(OfficialSettingsCategory.resolve(for: provider), .subscription, provider.id)
        }
    }

    func testMeteredBalancesAndBothOpenRouterViewsAreAPI() {
        for provider in [
            OfficialProviderDefaultCatalog.zaiBalance(),
            OfficialProviderDefaultCatalog.kimiBalance(),
            OfficialProviderDefaultCatalog.qwenBalance(),
            OfficialProviderDefaultCatalog.openRouterCredits(),
            OfficialProviderDefaultCatalog.openRouterAPI(),
            OfficialRelayProviderDefaultCatalog.moonshot(),
            OfficialRelayProviderDefaultCatalog.miniMax(),
            OfficialRelayProviderDefaultCatalog.deepSeek()
        ] {
            XCTAssertEqual(OfficialSettingsCategory.resolve(for: provider), .api, provider.id)
        }
    }

    func testMimoClassificationFollowsPlanVersusBalanceAdapter() {
        var provider = OfficialRelayProviderDefaultCatalog.xiaomiMIMO()
        XCTAssertEqual(OfficialSettingsCategory.resolve(for: provider), .subscription)
        provider.relayConfig?.adapterID = "xiaomimimo"
        XCTAssertEqual(OfficialSettingsCategory.resolve(for: provider), .api)
    }

    func testLegacyOfficialRelayIsIncludedButCustomEndpointIsNot() {
        var legacy = OfficialRelayProviderDefaultCatalog.deepSeek()
        legacy.family = .thirdParty
        XCTAssertEqual(OfficialSettingsCategory.resolve(for: legacy), .api)
        XCTAssertNil(OfficialSettingsCategory.resolve(for: .makeOpenRelay(name: "Custom", baseURL: "https://example.test")))
    }

    func testGroupsPartitionEveryDefaultWithoutChangingEnabledOrder() {
        let defaults = ProviderDefaultCatalog.allDefaultProviders
        let grouped = OfficialSettingsCategory.allCases.flatMap { $0.providers(in: defaults) }
        XCTAssertEqual(grouped.count, defaults.count)
        XCTAssertEqual(Set(grouped.map(\.id)), Set(defaults.map(\.id)))

        var kimi = OfficialProviderDefaultCatalog.kimiBalance()
        kimi.enabled = true
        var zai = OfficialProviderDefaultCatalog.zaiBalance()
        zai.enabled = true
        let disabled = OfficialRelayProviderDefaultCatalog.deepSeek()
        let mixed = [disabled, kimi, OfficialProviderDefaultCatalog.codex(), zai]
        XCTAssertEqual(OfficialSettingsCategory.api.providers(in: mixed).map(\.id), [kimi.id, zai.id, disabled.id])
    }

    func testMissingAPIValuesAreNotPresentedAsZeroOrInventedTotals() {
        XCTAssertEqual(OfficialAPIUsagePresenter.amount(nil, unit: "CNY"), "—")
        XCTAssertEqual(OfficialAPIUsagePresenter.amount(.nan, unit: "USD"), "—")
        XCTAssertEqual(OfficialAPIUsagePresenter.amount(0, unit: "CNY"), "0 CNY")
        XCTAssertTrue(OfficialAPIUsagePresenter.amount(12.5, unit: " USD ").hasSuffix(" USD"))
    }

    func testAPIProvidersUseOneParenthesizedSuffix() {
        let examples: [(ProviderDescriptor, String)] = [
            (OfficialProviderDefaultCatalog.zaiBalance(), "Z.ai (API)"),
            (OfficialProviderDefaultCatalog.kimiBalance(), "Kimi (API)"),
            (OfficialProviderDefaultCatalog.qwenBalance(), "Qwen (API)"),
            (OfficialProviderDefaultCatalog.openRouterCredits(), "OpenRouter Credits (API)"),
            (OfficialProviderDefaultCatalog.openRouterAPI(), "OpenRouter (API)"),
            (OfficialRelayProviderDefaultCatalog.moonshot(), "Moonshot (API)"),
            (OfficialRelayProviderDefaultCatalog.miniMax(), "MiniMax (API)"),
            (OfficialRelayProviderDefaultCatalog.deepSeek(), "DeepSeek (API)")
        ]
        for (provider, expectedName) in examples {
            XCTAssertEqual(SettingsProviderSidebarPresenter.displayName(for: provider), expectedName, provider.id)
        }
    }

    func testSubscriptionsAndCustomEndpointsKeepTheirNames() {
        for provider in [
            OfficialProviderDefaultCatalog.codex(),
            OfficialProviderDefaultCatalog.kimi(),
            OfficialRelayProviderDefaultCatalog.xiaomiMIMO(),
            .makeOpenRelay(name: "Custom API", baseURL: "https://example.test")
        ] {
            XCTAssertEqual(
                SettingsProviderSidebarPresenter.displayName(for: provider),
                ProviderDefinitionRegistry.definition(for: provider).displayName,
                provider.id
            )
        }
    }

    func testCategoryReorderMapsBackToGlobalOrderInBothDirections() {
        var providers = [
            OfficialProviderDefaultCatalog.codex(),
            OfficialProviderDefaultCatalog.zaiBalance(),
            OfficialProviderDefaultCatalog.claude(),
            OfficialProviderDefaultCatalog.kimiBalance()
        ]
        for index in providers.indices { providers[index].enabled = true }
        let apiIDs = OfficialSettingsCategory.api.providers(in: providers).map(\.id)
        let subscriptionIDs = OfficialSettingsCategory.subscription.providers(in: providers).map(\.id)
        for sourceID in apiIDs {
            var config = AppConfig(providers: providers)
            let allIDs = providers.map(\.id)
            let destination = SettingsProviderReorderPresenter.destination(
                providerID: sourceID,
                previewIDs: apiIDs.reversed(),
                allEnabledIDs: allIDs
            )
            XCTAssertNotNil(destination)
            _ = AppProviderListMutationCoordinator().reorderEnabledProviders(
                family: .official,
                fromOffsets: IndexSet(integer: allIDs.firstIndex(of: sourceID)!),
                toOffset: destination!,
                config: &config
            )
            XCTAssertEqual(OfficialSettingsCategory.api.providers(in: config.providers).map(\.id), apiIDs.reversed())
            XCTAssertEqual(OfficialSettingsCategory.subscription.providers(in: config.providers).map(\.id), subscriptionIDs)
        }
        XCTAssertNil(SettingsProviderReorderPresenter.destination(providerID: "removed", previewIDs: ["removed"], allEnabledIDs: providers.map(\.id)))
    }

    func testUnifiedListSupportsDraggingAcrossSubscriptionAndAPIProviders() {
        var providers = [
            OfficialProviderDefaultCatalog.codex(),
            OfficialProviderDefaultCatalog.zaiBalance(),
            OfficialProviderDefaultCatalog.claude(),
            OfficialProviderDefaultCatalog.kimiBalance()
        ]
        for index in providers.indices { providers[index].enabled = true }
        let allIDs = providers.map(\.id)
        let previewIDs = Array(allIDs.reversed())
        for sourceID in [allIDs[0], allIDs[3]] {
            var config = AppConfig(providers: providers)
            let destination = SettingsProviderReorderPresenter.destination(
                providerID: sourceID,
                previewIDs: previewIDs,
                allEnabledIDs: allIDs
            )
            XCTAssertNotNil(destination)
            _ = AppProviderListMutationCoordinator().reorderEnabledProviders(
                family: .official,
                fromOffsets: IndexSet(integer: allIDs.firstIndex(of: sourceID)!),
                toOffset: destination!,
                config: &config
            )
            var expectedIDs = allIDs.filter { $0 != sourceID }
            expectedIDs.insert(sourceID, at: destination!)
            XCTAssertEqual(config.providers.map(\.id), expectedIDs)
        }
    }
}
