import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class ProviderDefinitionRegistryTests: XCTestCase {
    func testOfficialCodexDefinitionAggregatesPresentationCapabilitiesAndSettings() {
        let definition = ProviderDefinitionRegistry.definition(for: ProviderDescriptor.defaultOfficialCodex())

        XCTAssertEqual(definition.id, "codex-official")
        XCTAssertEqual(definition.type, .codex)
        XCTAssertEqual(definition.family, .official)
        XCTAssertEqual(definition.displayName, "Codex")
        XCTAssertEqual(definition.iconName, "menu_codex_icon")
        XCTAssertEqual(definition.fallbackSystemIcon, "terminal.fill")
        XCTAssertTrue(definition.supportsAccountSwitch)
        XCTAssertTrue(definition.supportsHistory)
        XCTAssertTrue(definition.capabilities.usesPercentageMenuCard)
        XCTAssertEqual(definition.settingsSpec.supportedSourceModes, [.auto, .api, .cli, .web])
        XCTAssertEqual(definition.preferredMetricCount, 2)
    }

    func testClaudeDefinitionUsesFourMetricsAndManualCookieSettings() {
        let definition = ProviderDefinitionRegistry.definition(for: ProviderDescriptor.defaultOfficialClaude())

        XCTAssertEqual(definition.displayName, "Claude")
        XCTAssertEqual(definition.preferredMetricCount, 4)
        XCTAssertEqual(definition.settingsSpec.credentialFields.map(\.kind), [.manualCookie])
        XCTAssertTrue(definition.capabilities.supportsQuotaWindows)
    }

    func testRelayDefinitionUsesResolvedProviderPresentationAndCapabilities() {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Relay X",
            baseURL: "https://relay.example.com"
        )
        let definition = ProviderDefinitionRegistry.definition(for: provider)

        XCTAssertEqual(definition.displayName, "Relay X")
        XCTAssertEqual(definition.iconName, "menu_relay_icon")
        XCTAssertEqual(definition.fallbackSystemIcon, "link")
        XCTAssertTrue(definition.capabilities.supportsBalance)
        XCTAssertFalse(definition.capabilities.usesPercentageMenuCard)
        XCTAssertTrue(definition.settingsSpec.credentialFields.isEmpty)
    }

    func testCredentialFieldsStayStableForRepresentativeProviderKinds() {
        let cases: [(provider: ProviderDescriptor, fields: [CredentialFieldKind])] = [
            (.defaultOfficialClaude(), [.manualCookie]),
            (.defaultOfficialTrae(), [.traeAuthorization]),
            (.defaultOfficialOpenRouterAPI(), [.bearerToken]),
            (.defaultOfficialOpenRouterCredits(), [.bearerToken]),
            (.defaultOfficialKimi(), [.bearerToken]),
            (.defaultOfficialOpenCodeGo(), [.opencodeWorkspaceID, .opencodeManualCookie]),
            (.makeOpenRelay(name: "Relay X", baseURL: "https://relay.example.com"), [])
        ]

        for item in cases {
            let definition = ProviderDefinitionRegistry.definition(for: item.provider)

            XCTAssertEqual(
                definition.settingsSpec.credentialFields.map(\.kind),
                item.fields,
                item.provider.id
            )
        }
    }

    func testDefinitionsPreserveProviderOrder() {
        let providers = [
            ProviderDescriptor.defaultOfficialCodex(),
            ProviderDescriptor.defaultOfficialClaude(),
            ProviderDescriptor.makeOpenRelay(name: "Relay X", baseURL: "https://relay.example.com")
        ]

        XCTAssertEqual(
            ProviderDefinitionRegistry.definitions(for: providers).map(\.id),
            providers.map(\.id)
        )
    }

    func testDefaultDefinitionsPreserveDefaultProviderOrder() {
        XCTAssertEqual(
            ProviderDefinitionRegistry.defaultDefinitions.map(\.id),
            AppConfig.default.providers.map(\.id)
        )
    }

    func testDefinitionRegistryReadsSingleCentralMetadataSnapshot() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Services/ProviderDefinitionRegistry.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("ProviderMetadataCatalog.metadata(for: provider)"),
            "ProviderDefinitionRegistry should use ProviderMetadataCatalog as the single metadata read model"
        )
        XCTAssertFalse(
            source.contains("ProviderPresentationRegistry.presentation"),
            "ProviderDefinitionRegistry should not re-query presentation through the legacy facade"
        )
        XCTAssertFalse(
            source.contains("ProviderSettingsSpec.resolve"),
            "ProviderDefinitionRegistry should not re-query settings spec outside the central metadata snapshot"
        )
        XCTAssertFalse(
            source.contains("ProviderCapabilities.capabilities"),
            "ProviderDefinitionRegistry should not re-query capabilities outside the central metadata snapshot"
        )
        XCTAssertFalse(
            source.contains("QuotaMetricDisplayFactory.preferredMetricCount"),
            "ProviderDefinitionRegistry should not re-query preferred metrics outside the central metadata snapshot"
        )
    }

    func testProviderTypeMetadataCatalogCoversEveryProviderType() {
        XCTAssertEqual(
            ProviderTypeMetadataCatalog.missingProviderTypes.map(\.rawValue),
            [],
            "Every ProviderType should be explicitly registered in ProviderTypeMetadataCatalog"
        )
    }

    func testDefinitionRegistryFacadeQueriesStayAlignedWithCentralMetadata() {
        for provider in AppConfig.default.providers {
            let metadata = ProviderDefinitionRegistry.metadata(for: provider)

            XCTAssertEqual(ProviderDefinitionRegistry.presentation(for: provider), metadata.presentation, provider.id)
            XCTAssertEqual(ProviderDefinitionRegistry.capabilities(for: provider), metadata.capabilities, provider.id)
            XCTAssertEqual(ProviderDefinitionRegistry.settingsSpec(for: provider), metadata.settingsSpec, provider.id)
            XCTAssertEqual(ProviderDefinitionRegistry.preferredMetricCount(for: provider), metadata.preferredMetricCount, provider.id)
        }
    }

    func testProviderPresentationRegistryDelegatesToDefinitionRegistryReadModel() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Services/ProviderPresentationRegistry.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("ProviderDefinitionRegistry.presentation(for: provider)"),
            "ProviderPresentationRegistry should delegate provider presentation reads to ProviderDefinitionRegistry"
        )
        XCTAssertTrue(
            source.contains("ProviderDefinitionRegistry.preferredMetricCount(for: provider)"),
            "QuotaMetricDisplayFactory should delegate preferred metric reads to ProviderDefinitionRegistry"
        )
        XCTAssertFalse(
            source.contains("ProviderMetadataCatalog.presentation(for: provider)"),
            "ProviderPresentationRegistry should not maintain a parallel presentation read path"
        )
        XCTAssertFalse(
            source.contains("ProviderMetadataCatalog.preferredMetricCount(for: provider)"),
            "QuotaMetricDisplayFactory should not maintain a parallel metric read path"
        )
    }

    func testProviderSettingsSpecResolveDelegatesToDefinitionRegistryReadModel() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderSettingsSpec.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("ProviderDefinitionRegistry.settingsSpec(for: provider)"),
            "ProviderSettingsSpec.resolve should delegate settings reads to ProviderDefinitionRegistry"
        )
        XCTAssertFalse(
            source.contains("ProviderMetadataCatalog.settingsSpec(for: provider)"),
            "ProviderSettingsSpec.resolve should not maintain a parallel settings read path"
        )
    }

    func testDefaultProvidersAreCoveredByCentralMetadataCatalog() {
        for provider in AppConfig.default.providers {
            let metadata = ProviderMetadataCatalog.metadata(for: provider)
            let definition = ProviderDefinitionRegistry.definition(for: provider)

            XCTAssertFalse(metadata.presentation.displayName.isEmpty, provider.id)
            XCTAssertFalse(metadata.presentation.iconName.isEmpty, provider.id)
            XCTAssertFalse(metadata.presentation.fallbackSystemIcon.isEmpty, provider.id)
            XCTAssertEqual(ProviderDefinitionRegistry.metadata(for: provider), metadata, provider.id)
            XCTAssertEqual(definition.presentation, metadata.presentation, provider.id)
            XCTAssertEqual(definition.displayName, metadata.presentation.displayName, provider.id)
            XCTAssertEqual(definition.iconName, metadata.presentation.iconName, provider.id)
            XCTAssertEqual(definition.fallbackSystemIcon, metadata.presentation.fallbackSystemIcon, provider.id)
            XCTAssertEqual(definition.capabilities, metadata.capabilities, provider.id)
            XCTAssertEqual(definition.settingsSpec, metadata.settingsSpec, provider.id)
            XCTAssertEqual(definition.preferredMetricCount, metadata.preferredMetricCount, provider.id)
        }
    }

    func testOfficialRelayMetadataUsesStableProviderMapping() {
        let cases: [(provider: ProviderDescriptor, name: String, icon: String, id: String)] = [
            (.defaultOfficialMoonshot(), "Moonshot", "menu_kimi_icon", "moonshot-official"),
            (.defaultOfficialMiniMax(), "MiniMax", "menu_minimax_icon", "minimax-official"),
            (.defaultOfficialDeepSeek(), "DeepSeek", "menu_deepseek_icon", "deepseek-official"),
            (.defaultOfficialXiaomiMIMO(), "Xiaomi MIMO", "menu_mimo_icon", "xiaomi-mimo-official")
        ]

        for item in cases {
            let metadata = ProviderMetadataCatalog.metadata(for: item.provider)

            XCTAssertEqual(item.provider.officialRelayDefaultProviderID, item.id)
            XCTAssertEqual(metadata.presentation.displayName, item.name)
            XCTAssertEqual(metadata.presentation.iconName, item.icon)
            XCTAssertEqual(ProviderDescriptor.officialRelayDefaultProviderID(adapterID: item.provider.officialRelayAdapterID ?? ""), item.id)
        }
    }

    func testOfficialRelayPresentationIconsStayStable() {
        let cases: [(provider: ProviderDescriptor, icon: String)] = [
            (.defaultOfficialMoonshot(), "menu_kimi_icon"),
            (.defaultOfficialMiniMax(), "menu_minimax_icon"),
            (.defaultOfficialDeepSeek(), "menu_deepseek_icon"),
            (.defaultOfficialXiaomiMIMO(), "menu_mimo_icon")
        ]

        for item in cases {
            XCTAssertEqual(
                ProviderDefinitionRegistry.presentation(for: item.provider).iconName,
                item.icon,
                item.provider.id
            )
        }
    }

    func testUnofficialRelayPresentationIconOverridesStayStable() {
        let cases: [(provider: ProviderDescriptor, icon: String)] = [
            (
                .makeOpenRelay(
                    name: "Relay X",
                    baseURL: "https://proxy.example.com",
                    preferredAdapterID: "moonshot"
                ),
                "menu_kimi_icon"
            ),
            (
                .makeOpenRelay(
                    name: "Kimi Relay",
                    baseURL: "https://proxy.example.com",
                    preferredAdapterID: "generic"
                ),
                "menu_kimi_icon"
            ),
            (
                .makeOpenRelay(
                    name: "Relay X",
                    baseURL: "https://deepseek.proxy.example.com",
                    preferredAdapterID: "generic"
                ),
                "menu_deepseek_icon"
            ),
            (
                .makeOpenRelay(
                    name: "Relay X",
                    baseURL: "https://proxy.example.com",
                    preferredAdapterID: "xiaomimimo-token-plan"
                ),
                "menu_mimo_icon"
            ),
            (
                .makeOpenRelay(
                    name: "MIMO Relay",
                    baseURL: "https://proxy.example.com",
                    preferredAdapterID: "generic"
                ),
                "menu_mimo_icon"
            ),
            (
                .makeOpenRelay(
                    name: "Relay X",
                    baseURL: "https://proxy.example.com",
                    preferredAdapterID: "minimax"
                ),
                "menu_minimax_icon"
            ),
            (
                .makeOpenRelay(
                    name: "Relay X",
                    baseURL: "https://minimaxi.proxy.example.com",
                    preferredAdapterID: "generic"
                ),
                "menu_minimax_icon"
            )
        ]

        for item in cases {
            XCTAssertFalse(item.provider.isOfficialRelayProvider, item.provider.name)
            XCTAssertEqual(
                ProviderDefinitionRegistry.presentation(for: item.provider).iconName,
                item.icon,
                item.provider.name
            )
        }
    }

    func testOfficialRelayDefaultsAreDerivedFromMetadataCatalog() throws {
        let providers = [
            ProviderDescriptor.defaultOfficialMoonshot(),
            ProviderDescriptor.defaultOfficialMiniMax(),
            ProviderDescriptor.defaultOfficialDeepSeek(),
            ProviderDescriptor.defaultOfficialXiaomiMIMO()
        ]

        for provider in providers {
            let metadata = try XCTUnwrap(OfficialRelayMetadataCatalog.metadata(forProviderID: provider.id))

            XCTAssertEqual(provider.name, metadata.displayName, provider.id)
            XCTAssertEqual(provider.baseURL, metadata.baseURL, provider.id)
            XCTAssertEqual(provider.relayConfig?.baseURL, metadata.baseURL, provider.id)
            XCTAssertEqual(provider.relayConfig?.adapterID, metadata.defaultAdapterID, provider.id)
            XCTAssertEqual(provider.auth.keychainAccount, metadata.keychainAccount, provider.id)
            XCTAssertEqual(provider.relayConfig?.balanceAuth.keychainAccount, metadata.keychainAccount, provider.id)
            XCTAssertEqual(
                ProviderDescriptor.defaultRelayBalanceAccount(
                    id: provider.id,
                    baseURL: metadata.baseURL,
                    adapterID: metadata.defaultAdapterID
                ),
                metadata.keychainAccount,
                provider.id
            )
        }
    }
}
