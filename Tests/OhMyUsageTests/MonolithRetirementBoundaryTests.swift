import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class MonolithRetirementBoundaryTests: XCTestCase {
    func testCoordinatorsAndPresentersDoNotDependOnAppViewModelNestedDisplayTypes() throws {
        let files = [
            "Sources/OhMyUsage/App/AppConfigurationMutationCoordinator.swift",
            "Sources/OhMyUsage/App/AppSettingsPersistenceFeedbackCoordinator.swift",
            "Sources/OhMyUsage/UI/Presenters/MenuDashboardPresenter.swift"
        ]

        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for file in files {
            let fileURL = rootURL.appendingPathComponent(file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(
                source.contains("AppViewModel."),
                "\(file) should use top-level display models instead of AppViewModel nested types"
            )
        }

        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)
        for nestedDefinition in [
            "enum UpdateDisplayTone",
            "struct SettingsUpdateDisplayState",
            "struct MenuUpdateDisplayState",
            "struct SettingsPersistenceDisplayState"
        ] {
            XCTAssertFalse(
                appViewModel.contains(nestedDefinition),
                "AppViewModel.swift should not re-own \(nestedDefinition)"
            )
        }
    }

    func testProviderMetadataCatalogLivesWithProviderModels() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let modelCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderMetadataCatalog.swift")
        let serviceCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Services/ProviderMetadataCatalog.swift")
        let presentationModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderPresentationModels.swift")
        let catalogSource = try String(contentsOf: modelCatalogURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: modelCatalogURL.path),
            "ProviderMetadataCatalog should stay beside provider model policy instead of living in Services"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: serviceCatalogURL.path),
            "ProviderMetadataCatalog is pure provider metadata and should not create a Models -> Services dependency"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: presentationModelsURL.path),
            "ProviderPresentation and ProviderCapabilities should be model values, not service facade types"
        )
        XCTAssertFalse(
            catalogSource.contains("Bundle.module"),
            "ProviderMetadataCatalog should not reach into package resources while it lives with model policy"
        )
    }

    func testProviderMetadataCatalogStaysAsFacadeOverFocusedMetadataCatalogs() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let modelCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderMetadataCatalog.swift")
        let relayCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/OfficialRelayMetadataCatalog.swift")
        let typeCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderTypeMetadataCatalog.swift")
        let presentationCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderPresentationMetadataCatalog.swift")
        let settingsCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderSettingsMetadataCatalog.swift")
        let capabilityCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderCapabilityMetadataCatalog.swift")
        let relayIconCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/RelayIconMetadataCatalog.swift")
        let officialRelayMetadataURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+OfficialRelayMetadata.swift")
        let catalogSource = try String(contentsOf: modelCatalogURL, encoding: .utf8)
        let settingsCatalogSource = try String(contentsOf: settingsCatalogURL, encoding: .utf8)
        let capabilityCatalogSource = try String(contentsOf: capabilityCatalogURL, encoding: .utf8)
        let relayIconCatalogSource = try String(contentsOf: relayIconCatalogURL, encoding: .utf8)
        let officialRelayMetadataSource = try String(contentsOf: officialRelayMetadataURL, encoding: .utf8)
        let catalogLineCount = catalogSource.split(separator: "\n", omittingEmptySubsequences: false).count

        XCTAssertLessThanOrEqual(
            catalogLineCount,
            180,
            "ProviderMetadataCatalog should stay as a small facade after splitting type and relay metadata"
        )
        XCTAssertFalse(
            catalogSource.contains("officialRelayMetadata"),
            "ProviderMetadataCatalog should not directly own the official relay metadata array"
        )
        XCTAssertFalse(
            catalogSource.contains("providerTypeMetadata"),
            "ProviderMetadataCatalog should not directly own provider type metadata"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: relayCatalogURL.path),
            "Official relay metadata should live in OfficialRelayMetadataCatalog"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: typeCatalogURL.path),
            "Provider type metadata should live in ProviderTypeMetadataCatalog"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: presentationCatalogURL.path),
            "Provider presentation metadata should live in ProviderPresentationMetadataCatalog"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: settingsCatalogURL.path),
            "Provider settings metadata should live in ProviderSettingsMetadataCatalog"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: capabilityCatalogURL.path),
            "Provider capabilities metadata should live in ProviderCapabilityMetadataCatalog"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: relayIconCatalogURL.path),
            "Relay icon override metadata should live in RelayIconMetadataCatalog"
        )
        XCTAssertFalse(
            catalogSource.contains("private static func credentialFields"),
            "ProviderMetadataCatalog should not own credential field derivation"
        )
        XCTAssertFalse(
            catalogSource.contains("private static func relayIconOverrideName"),
            "ProviderMetadataCatalog should not own relay icon override matching"
        )
        XCTAssertFalse(
            catalogSource.contains("private static func displayName"),
            "ProviderMetadataCatalog should not own provider presentation display names"
        )
        XCTAssertFalse(
            catalogSource.contains("private static func iconName"),
            "ProviderMetadataCatalog should not own provider presentation icons"
        )
        XCTAssertFalse(
            catalogSource.contains("private static func fallbackIcon"),
            "ProviderMetadataCatalog should not own provider presentation fallback icons"
        )
        XCTAssertFalse(
            officialRelayMetadataSource.contains("ProviderMetadataCatalog.officialRelay"),
            "ProviderDescriptor+OfficialRelayMetadata should query OfficialRelayMetadataCatalog directly"
        )
        XCTAssertFalse(
            catalogSource.contains("ProviderCapabilities("),
            "ProviderMetadataCatalog should delegate capability construction"
        )
        XCTAssertFalse(
            catalogSource.contains("ProviderSettingsSpec("),
            "ProviderMetadataCatalog should delegate settings spec construction"
        )
        XCTAssertTrue(settingsCatalogSource.contains("static func settingsSpec(for provider: ProviderDescriptor)"))
        XCTAssertTrue(settingsCatalogSource.contains("static func supportedOfficialSourceModes(for provider: ProviderDescriptor)"))
        XCTAssertTrue(settingsCatalogSource.contains("static func supportedOfficialWebModes(for provider: ProviderDescriptor)"))
        XCTAssertTrue(settingsCatalogSource.contains("static func supportsOfficialBearerCredentialInput(for provider: ProviderDescriptor)"))
        XCTAssertTrue(settingsCatalogSource.contains("credentialFields(for provider: ProviderDescriptor)"))
        XCTAssertTrue(capabilityCatalogSource.contains("static func capabilities(for provider: ProviderDescriptor)"))
        XCTAssertTrue(relayIconCatalogSource.contains("static func iconOverrideName(for provider: ProviderDescriptor)"))
        XCTAssertTrue(
            relayIconCatalogSource.contains("OfficialRelayMetadataCatalog.metadata"),
            "RelayIconMetadataCatalog should prefer OfficialRelayMetadataCatalog for known relay icons"
        )
        XCTAssertFalse(
            relayIconCatalogSource.contains("menu_kimi_icon"),
            "RelayIconMetadataCatalog should not hardcode official relay icon names"
        )
        XCTAssertFalse(
            relayIconCatalogSource.contains("contains(\"moonshot\")"),
            "RelayIconMetadataCatalog should not keep parallel moonshot/kimi string heuristics"
        )
        XCTAssertFalse(
            relayIconCatalogSource.contains("contains(\"deepseek\")"),
            "RelayIconMetadataCatalog should not keep parallel deepseek string heuristics"
        )
        XCTAssertFalse(
            relayIconCatalogSource.contains("contains(\"minimax\")"),
            "RelayIconMetadataCatalog should not keep parallel minimax string heuristics"
        )
        XCTAssertFalse(
            relayIconCatalogSource.contains("contains(\"mimo\")"),
            "RelayIconMetadataCatalog should not keep parallel mimo string heuristics"
        )
    }

    func testProviderModelsDoesNotOwnAppConfigDefinition() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for appConfigResponsibility in [
            "struct AppConfig",
            "migratedWithSiteDefaults",
            "migrateOfficialRelayProvidersToStableIDs"
        ] {
            XCTAssertFalse(
                providerModels.contains(appConfigResponsibility),
                "ProviderModels.swift should keep provider descriptors separate from app-level configuration models"
            )
        }

        let appConfigURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/AppConfigModels.swift")
        let appConfigModels = try String(contentsOf: appConfigURL, encoding: .utf8)
        XCTAssertTrue(appConfigModels.contains("struct AppConfig"))

        let appConfigMigrationURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/AppConfig+SiteDefaultsMigration.swift")
        let appConfigMigration = try String(contentsOf: appConfigMigrationURL, encoding: .utf8)
        XCTAssertTrue(appConfigMigration.contains("migratedWithSiteDefaults"))
    }

    func testProviderModelsDoesNotOwnAuthConfigCredentialHelpers() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        XCTAssertFalse(providerModels.contains("extension AuthConfig"))

        let authHelpersURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/AuthConfig+CredentialHelpers.swift")
        let authHelpers = try String(contentsOf: authHelpersURL, encoding: .utf8)
        XCTAssertTrue(authHelpers.contains("func withFallback"))
        XCTAssertTrue(authHelpers.contains("func normalizedCredentialServiceName"))
    }

    func testProviderConfigurationDomainMigrationKeepsRuntimeAndPolicyRedLinesInExecutable() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let domainURL = rootURL.appendingPathComponent("Sources/OhMyUsageDomain")
        let executableModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models")
        let executableServicesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Services")

        let domainValueFiles = [
            "AuthModels.swift",
            "OfficialProviderConfigModels.swift",
            "RelayModels.swift",
            "OpenRelayProviderConfigModels.swift"
        ]
        for fileName in domainValueFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: domainURL.appendingPathComponent(fileName).path),
                "Stage 1 pure provider configuration value objects should live in OhMyUsageDomain/\(fileName)"
            )
        }

        let executableModelRedLines = [
            "AuthConfig+CredentialHelpers.swift",
            "ProviderModels.swift",
            "ProviderDescriptor+CatalogFacades.swift",
            "ProviderDefaultCatalog.swift",
            "OfficialProviderDefaultCatalog.swift",
            "OfficialRelayProviderDefaultCatalog.swift",
            "RelayProviderDefaultCatalog.swift",
            "ProviderDescriptor+Normalization.swift",
            "ProviderDescriptor+LegacyRelayMigration.swift",
            "ProviderDescriptor+RelayViewConfig.swift",
            "ProviderDescriptor+OfficialRelayMetadata.swift",
            "SettingsDraftModels.swift",
            "AppConfigModels.swift"
        ]
        for fileName in executableModelRedLines {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: executableModelsURL.appendingPathComponent(fileName).path),
                "\(fileName) should remain in the executable target boundary"
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: domainURL.appendingPathComponent(fileName).path),
                "\(fileName) should not move into OhMyUsageDomain during Stage 1"
            )
        }

        let executableServiceRedLines = [
            "ProviderFactory.swift",
            "ProviderFactoryRegistry.swift",
            "ProviderDefinitionRegistry.swift"
        ]
        for fileName in executableServiceRedLines {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: executableServicesURL.appendingPathComponent(fileName).path),
                "\(fileName) should remain in the executable services boundary"
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: domainURL.appendingPathComponent(fileName).path),
                "\(fileName) should not move into OhMyUsageDomain during Stage 1"
            )
        }

        let authHelpersURL = executableModelsURL.appendingPathComponent("AuthConfig+CredentialHelpers.swift")
        let authHelpers = try String(contentsOf: authHelpersURL, encoding: .utf8)
        XCTAssertTrue(authHelpers.contains("normalizedCredentialServiceName"))
        XCTAssertTrue(authHelpers.contains("withFallback"))
    }

    func testProviderModelsDoesNotOwnDefaultProviderConstructors() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for defaultConstructor in [
            "defaultOfficialCodex",
            "defaultOfficialRelaySite",
            "defaultOpenAilinyu",
            "defaultHongmacc"
        ] {
            XCTAssertFalse(
                providerModels.contains(defaultConstructor),
                "ProviderModels.swift should keep default provider constructors in ProviderDescriptor+CatalogFacades.swift"
            )
        }

        let facadesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+CatalogFacades.swift")
        let facades = try String(contentsOf: facadesURL, encoding: .utf8)
        XCTAssertTrue(facades.contains("defaultOfficialCodex"))
        XCTAssertTrue(facades.contains("defaultOpenAilinyu"))
    }

    func testProviderDescriptorDefaultsStayAsFacadesOverDefaultCatalogs() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let facadesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+CatalogFacades.swift")
        let providerCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDefaultCatalog.swift")
        let officialCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/OfficialProviderDefaultCatalog.swift")
        let officialRelayCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/OfficialRelayProviderDefaultCatalog.swift")
        let relayCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/RelayProviderDefaultCatalog.swift")
        let appConfigURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/AppConfigModels.swift")

        for catalogURL in [providerCatalogURL, officialCatalogURL, officialRelayCatalogURL, relayCatalogURL] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: catalogURL.path),
                "\(catalogURL.lastPathComponent) should own focused provider default construction or policy"
            )
        }

        let facades = try String(contentsOf: facadesURL, encoding: .utf8)
        let providerCatalog = try String(contentsOf: providerCatalogURL, encoding: .utf8)
        let officialCatalog = try String(contentsOf: officialCatalogURL, encoding: .utf8)
        let officialRelayCatalog = try String(contentsOf: officialRelayCatalogURL, encoding: .utf8)
        let relayCatalog = try String(contentsOf: relayCatalogURL, encoding: .utf8)
        let appConfigModels = try String(contentsOf: appConfigURL, encoding: .utf8)

        XCTAssertFalse(facades.contains("ProviderDescriptor("))
        XCTAssertFalse(facades.contains("OfficialRelayMetadataCatalog.metadata"))
        XCTAssertFalse(facades.contains("switch type"))
        XCTAssertFalse(facades.contains("RelayProviderDescriptorModelAdapter.live"))
        XCTAssertFalse(facades.contains("URLComponents("))
        XCTAssertTrue(facades.contains("defaultOfficialConfig"))
        XCTAssertTrue(facades.contains("defaultRelayConfig"))
        XCTAssertTrue(facades.contains("normalizeRelayBaseURL"))

        XCTAssertTrue(providerCatalog.contains("enum ProviderDefaultCatalog"))
        XCTAssertTrue(providerCatalog.contains("allDefaultProviders"))
        XCTAssertTrue(providerCatalog.contains("OfficialProviderDefaultCatalog.codex()"))
        XCTAssertTrue(
            providerCatalog.contains("OfficialRelayProviderDefaultCatalog.allDefaultProviders"),
            "ProviderDefaultCatalog should expand official relays from OfficialRelayProviderDefaultCatalog.allDefaultProviders"
        )
        XCTAssertFalse(
            providerCatalog.contains("OfficialRelayProviderDefaultCatalog.moonshot()"),
            "ProviderDefaultCatalog should not hand-enumerate official relay defaults"
        )
        XCTAssertFalse(providerCatalog.contains("OfficialRelayProviderDefaultCatalog.miniMax()"))
        XCTAssertFalse(providerCatalog.contains("OfficialRelayProviderDefaultCatalog.deepSeek()"))
        XCTAssertFalse(providerCatalog.contains("OfficialRelayProviderDefaultCatalog.xiaomiMIMO()"))
        XCTAssertTrue(officialCatalog.contains("enum OfficialProviderDefaultCatalog"))
        XCTAssertTrue(officialCatalog.contains("static func config(for type: ProviderType)"))
        XCTAssertTrue(officialCatalog.contains("switch type"))
        XCTAssertTrue(officialRelayCatalog.contains("enum OfficialRelayProviderDefaultCatalog"))
        XCTAssertTrue(officialRelayCatalog.contains("OfficialRelayMetadataCatalog.metadata(forProviderID:"))
        XCTAssertTrue(
            officialRelayCatalog.contains("static var allDefaultProviders"),
            "OfficialRelayProviderDefaultCatalog should expose allDefaultProviders driven by metadata order"
        )
        XCTAssertTrue(
            officialRelayCatalog.contains("OfficialRelayMetadataCatalog.defaultProviderOrder"),
            "Official relay default list should be driven by OfficialRelayMetadataCatalog.defaultProviderOrder"
        )
        XCTAssertTrue(officialRelayCatalog.contains("static func moonshot()"))
        XCTAssertTrue(officialRelayCatalog.contains("static func miniMax()"))
        XCTAssertTrue(officialRelayCatalog.contains("static func deepSeek()"))
        XCTAssertTrue(officialRelayCatalog.contains("static func xiaomiMIMO()"))
        XCTAssertTrue(relayCatalog.contains("enum RelayProviderDefaultCatalog"))
        XCTAssertTrue(relayCatalog.contains("RelayProviderDescriptorModelAdapter.live"))
        XCTAssertTrue(relayCatalog.contains("URLComponents("))
        XCTAssertTrue(appConfigModels.contains("ProviderDefaultCatalog.allDefaultProviders"))
    }

    func testDefaultProviderCatalogPreservesDefaultOrderAndCredentialAccounts() throws {
        let providers = AppConfig.default.providers
        let officialRelayOrder = OfficialRelayMetadataCatalog.defaultProviderOrder

        XCTAssertEqual(
            OfficialRelayProviderDefaultCatalog.allDefaultProviders.map(\.id),
            officialRelayOrder,
            "Official relay defaults should follow OfficialRelayMetadataCatalog.defaultProviderOrder"
        )

        XCTAssertEqual(
            providers.map(\.id),
            [
                "codex-official",
                "claude-official",
                "gemini-official",
                "copilot-official",
                "microsoft-copilot-official",
                "zai-official",
                "amp-official",
                "cursor-official",
                "jetbrains-official",
                "kiro-official",
                "windsurf-official",
                "grok-official",
                "kimi-official"
            ]
                + officialRelayOrder
                + [
                    "trae-official",
                    "openrouter-credits-official",
                    "openrouter-api-official",
                    "ollama-cloud-official",
                    "opencode-go-official"
                ]
        )

        let kimiIndex = try XCTUnwrap(providers.firstIndex(where: { $0.id == "kimi-official" }))
        let traeIndex = try XCTUnwrap(providers.firstIndex(where: { $0.id == "trae-official" }))
        XCTAssertEqual(
            providers[(kimiIndex + 1)..<traeIndex].map(\.id),
            officialRelayOrder,
            "Official relays remain inserted between kimi and trae in metadata order"
        )

        let providersByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        XCTAssertEqual(providersByID["trae-official"]?.auth.keychainAccount, "official/trae/cloud-ide-jwt")
        XCTAssertEqual(providersByID["openrouter-credits-official"]?.auth.keychainAccount, "official/openrouter/credits-api-key")
        XCTAssertEqual(providersByID["openrouter-api-official"]?.auth.keychainAccount, "official/openrouter/api-key")
        XCTAssertEqual(providersByID["opencode-go-official"]?.auth.keychainAccount, "official/opencode-go/workspace-id")

        for providerID in officialRelayOrder {
            let provider = providersByID[providerID]
            let metadata = OfficialRelayMetadataCatalog.metadata(forProviderID: providerID)
            XCTAssertEqual(provider?.name, metadata?.displayName)
            XCTAssertEqual(provider?.baseURL, metadata?.baseURL)
            XCTAssertEqual(provider?.auth.keychainAccount, metadata?.keychainAccount)
            XCTAssertEqual(provider?.relayConfig?.adapterID, metadata?.defaultAdapterID)
        }
    }

    func testCursorProviderUsesSharedOfficialAuthRuntime() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cursorProviderURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Providers/CursorProvider.swift")
        let cursorProvider = try String(contentsOf: cursorProviderURL, encoding: .utf8)

        XCTAssertTrue(
            cursorProvider.contains("OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh"),
            "CursorProvider should reuse the shared official auth refresh/retry runtime instead of owning another hand-rolled loop"
        )
        XCTAssertFalse(
            cursorProvider.contains("catch let error as ProviderError"),
            "CursorProvider should not keep a bespoke unauthorized refresh retry loop after adopting OfficialProviderAuthRuntime"
        )
    }

    func testProviderModelsDoesNotOwnProviderDefaultConfigurationHelpers() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for defaultHelper in [
            "static func defaultOfficialBaseURL",
            "static func defaultOfficialConfig",
            "static func defaultKimiConfig"
        ] {
            XCTAssertFalse(
                providerModels.contains(defaultHelper),
                "ProviderModels.swift should keep provider default configuration helpers in ProviderDescriptor+CatalogFacades.swift"
            )
        }

        let facadesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+CatalogFacades.swift")
        let facades = try String(contentsOf: facadesURL, encoding: .utf8)
        XCTAssertTrue(facades.contains("defaultOfficialConfig"))
        XCTAssertTrue(facades.contains("defaultKimiConfig"))
    }

    func testProviderModelsDoesNotOwnOfficialRelayMetadataPolicy() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for relayMetadataResponsibility in [
            "var officialRelayAdapterID",
            "var isOfficialRelayProvider",
            "static var officialRelayDefaultProviderIDs",
            "static func officialRelayDefaultBaseURL"
        ] {
            XCTAssertFalse(
                providerModels.contains(relayMetadataResponsibility),
                "ProviderModels.swift should keep official relay metadata policy in ProviderDescriptor+OfficialRelayMetadata.swift"
            )
        }

        let metadataURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+OfficialRelayMetadata.swift")
        let metadata = try String(contentsOf: metadataURL, encoding: .utf8)
        XCTAssertTrue(metadata.contains("isOfficialRelayProvider"))
        XCTAssertTrue(metadata.contains("OfficialRelayMetadataCatalog.defaultProviderOrder"))
        XCTAssertFalse(metadata.contains("ProviderMetadataCatalog.officialRelay"))
    }

    func testProviderModelsDoesNotOwnRelayDefaultAndOverrideMigrationHelpers() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for relayHelperDefinition in [
            "static func makeOpenRelay",
            "static func defaultRelayConfig",
            "static func defaultRelayBalanceAccount",
            "static func normalizeRelayBaseURL",
            "func looksLikeGenericDefaultOverride",
            "func migrateGenericNewAPIDefaultOverride",
            "func looksLikeTemplateDefaultOverride"
        ] {
            XCTAssertFalse(
                providerModels.contains(relayHelperDefinition),
                "ProviderModels.swift should keep relay defaults and override migration helpers in focused ProviderDescriptor extensions"
            )
        }

        let facadesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+CatalogFacades.swift")
        let facades = try String(contentsOf: facadesURL, encoding: .utf8)
        XCTAssertTrue(facades.contains("static func defaultRelayConfig"))
        XCTAssertTrue(facades.contains("static func normalizeRelayBaseURL"))

        let relayOverrideURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+RelayOverrideMigration.swift")
        let relayOverride = try String(contentsOf: relayOverrideURL, encoding: .utf8)
        XCTAssertTrue(relayOverride.contains("migrateGenericNewAPIDefaultOverride"))
        XCTAssertTrue(relayOverride.contains("looksLikeTemplateDefaultOverride"))
    }

    func testProviderModelsDoesNotOwnLegacyRelayMigrationPolicy() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for legacyRelayMigrationDefinition in [
            "var legacyRelayImportIdentity",
            "var isLegacyRelayExample"
        ] {
            XCTAssertFalse(
                providerModels.contains(legacyRelayMigrationDefinition),
                "ProviderModels.swift should keep legacy relay migration policy in ProviderDescriptor+LegacyRelayMigration.swift"
            )
        }

        let migrationURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+LegacyRelayMigration.swift")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)
        XCTAssertTrue(migration.contains("legacyRelayImportIdentity"))
        XCTAssertTrue(migration.contains("isLegacyRelayExample"))
    }

    func testProviderModelsDoesNotOwnRelayViewOrDisplayPreferenceDerivations() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for derivedProperty in [
            "var relayManifest",
            "var relayDisplayMode",
            "var relayViewConfig",
            "var displaysUsedQuota",
            "var traeDisplaysAmount",
            "var supportedOfficialSourceModes",
            "var supportsOfficialManualCookieInput"
        ] {
            XCTAssertFalse(
                providerModels.contains(derivedProperty),
                "ProviderModels.swift should keep relay view and display preference derivations in focused ProviderDescriptor extensions"
            )
        }

        let relayViewURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+RelayViewConfig.swift")
        let relayView = try String(contentsOf: relayViewURL, encoding: .utf8)
        XCTAssertTrue(relayView.contains("relayViewConfig"))
        XCTAssertTrue(relayView.contains("relayManifest"))

        let displayPreferencesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+DisplayPreferences.swift")
        let displayPreferences = try String(contentsOf: displayPreferencesURL, encoding: .utf8)
        XCTAssertTrue(displayPreferences.contains("displaysUsedQuota"))
        XCTAssertTrue(displayPreferences.contains("supportsOfficialManualCookieInput"))
    }

    func testProviderModelsDoesNotOwnNormalizationPolicy() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        XCTAssertFalse(
            providerModels.contains("func normalized()"),
            "ProviderModels.swift should keep normalization policy in ProviderDescriptor+Normalization.swift"
        )

        let normalizationURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+Normalization.swift")
        let normalizerURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptorNormalizer.swift")
        let normalization = try String(contentsOf: normalizationURL, encoding: .utf8)
        let normalizer = try String(contentsOf: normalizerURL, encoding: .utf8)
        XCTAssertTrue(normalization.contains("func normalized()"))
        XCTAssertTrue(normalization.contains("ProviderDescriptorNormalizer.normalized(self)"))
        for strategyMethod in [
            "normalizedOfficialProvider",
            "normalizedRelayProvider",
            "normalizedKimiProvider",
            "normalizedRelayConfig"
        ] {
            XCTAssertFalse(
                normalization.contains(strategyMethod),
                "ProviderDescriptor+Normalization.swift should stay as a facade and not own \(strategyMethod)"
            )
            XCTAssertTrue(
                normalizer.contains(strategyMethod),
                "ProviderDescriptorNormalizer.swift should own \(strategyMethod)"
            )
        }
    }

    func testAppConfigSiteDefaultsMigrationStaysAsFacadeOverFocusedMigrator() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let migrationURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/AppConfig+SiteDefaultsMigration.swift")
        let migratorURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/AppConfigSiteDefaultsMigrator.swift")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)
        let migrator = try String(contentsOf: migratorURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: migratorURL.path),
            "AppConfig site defaults migration strategy should live in AppConfigSiteDefaultsMigrator.swift"
        )
        XCTAssertTrue(migration.contains("func migratedWithSiteDefaults() -> AppConfig"))
        XCTAssertTrue(migration.contains("AppConfigSiteDefaultsMigrator.migrated(self)"))
        for strategyMethod in [
            "migrateOfficialRelayProvidersToStableIDs",
            "mergedOfficialRelayProvider",
            "migratedSiteDefaults"
        ] {
            XCTAssertFalse(
                migration.contains(strategyMethod),
                "AppConfig+SiteDefaultsMigration.swift should stay as a facade and not own \(strategyMethod)"
            )
            XCTAssertTrue(
                migrator.contains(strategyMethod),
                "AppConfigSiteDefaultsMigrator.swift should own \(strategyMethod)"
            )
        }
    }

    func testSettingsDraftModelsDelegateRelaySeedDerivation() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let settingsDraftModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/SettingsDraftModels.swift")
        let settingsDraftModels = try String(contentsOf: settingsDraftModelsURL, encoding: .utf8)

        XCTAssertTrue(settingsDraftModels.contains("RelaySettingsDraftSeed"))
        XCTAssertFalse(
            settingsDraftModels.contains("relayViewConfig"),
            "SettingsDraftModels.swift should use RelaySettingsDraftSeed instead of deriving relay view config directly"
        )
    }

    func testModelRelayDescriptorDerivationsUseResolverInsteadOfSharedRegistry() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            "Sources/OhMyUsage/Models/RelaySettingsDraftSeed.swift",
            "Sources/OhMyUsage/Models/ProviderDescriptor+OfficialRelayMetadata.swift",
            "Sources/OhMyUsage/Models/ProviderDescriptor+LegacyRelayMigration.swift"
        ]

        for file in files {
            let fileURL = rootURL.appendingPathComponent(file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(
                source.contains("RelayAdapterRegistry.shared"),
                "\(file) should resolve relay descriptors through RelayProviderDescriptorResolver instead of the shared registry"
            )
        }
    }

    func testAppViewModelDelegatesDependencyCompositionToExecutableFactory() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let compositionFactoryURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppCompositionFactory.swift")
        let dependencyGraphURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppDependencyGraph.swift")
        let compositionRootURL = rootURL.appendingPathComponent("Sources/OhMyUsageBootstrap/OhMyUsageCompositionRoot.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)
        let compositionFactory = try String(contentsOf: compositionFactoryURL, encoding: .utf8)
        let dependencyGraph = try String(contentsOf: dependencyGraphURL, encoding: .utf8)
        let compositionRoot = try String(contentsOf: compositionRootURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: compositionFactoryURL.path),
            "Executable App dependency assembly should live in AppCompositionFactory.swift"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: dependencyGraphURL.path),
            "Executable App dependency graph should live in AppDependencyGraph.swift"
        )
        XCTAssertTrue(compositionFactory.contains("enum AppCompositionFactory"))
        XCTAssertTrue(compositionFactory.contains("static func makeDependencyGraph("))
        XCTAssertTrue(compositionFactory.contains("static func loadProductionConfig("))
        XCTAssertTrue(compositionFactory.contains("ProviderFactory(keychain:"))
        XCTAssertTrue(compositionFactory.contains("AppProviderRefreshModel("))
        XCTAssertTrue(compositionFactory.contains("AppUpdateModel("))
        XCTAssertTrue(compositionFactory.contains("AppConfigurationModel("))
        XCTAssertTrue(compositionFactory.contains("AppUsageAnalyticsModel("))
        XCTAssertTrue(dependencyGraph.contains("struct AppDependencyGraph"))
        XCTAssertTrue(dependencyGraph.contains("let providerRefreshModel: AppProviderRefreshModel"))
        XCTAssertTrue(dependencyGraph.contains("let updateModel: AppUpdateModel"))
        XCTAssertTrue(appViewModel.contains("AppCompositionFactory.makeDependencyGraph("))
        XCTAssertTrue(appViewModel.contains("AppCompositionFactory.loadProductionConfig("))
        XCTAssertTrue(appViewModel.contains("private init(\n        dependencyGraph: AppDependencyGraph,"))
        XCTAssertGreaterThanOrEqual(
            appViewModel.components(separatedBy: "AppCompositionFactory.makeDependencyGraph(").count - 1,
            2,
            "Production and DEBUG AppViewModel init should both build through AppCompositionFactory"
        )
        for inlineAssembly in [
            "CredentialAccessService(keychain:",
            "ProviderFactory(keychain:",
            "AppProviderRefreshModel(",
            "AppUpdateModel(",
            "AppConfigurationModel(",
            "AppUsageAnalyticsModel(coordinator:"
        ] {
            XCTAssertFalse(
                appViewModel.contains(inlineAssembly),
                "AppViewModel.swift should not inline dependency assembly \(inlineAssembly)"
            )
        }
        XCTAssertTrue(
            compositionRoot.contains("AppCompositionFactory"),
            "Bootstrap composition docs should point executable App wiring at AppCompositionFactory"
        )
        XCTAssertFalse(
            compositionRoot.contains("makeAppViewModel"),
            "OhMyUsageCompositionRoot must not claim executable host construction"
        )
    }

    func testAppViewModelDelegatesUsageAnalyticsRefresh() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let usageAnalyticsModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppUsageAnalyticsModel.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: usageAnalyticsModelURL.path),
            "Usage analytics session boundary should live in AppUsageAnalyticsModel.swift"
        )
        XCTAssertTrue(appViewModel.contains("AppUsageAnalyticsModel"))
        XCTAssertTrue(appViewModel.contains("UsageAnalyticsRefreshCoordinator"))
        XCTAssertFalse(
            appViewModel.contains("usageAnalyticsRefreshCoordinator.refreshUsageAnalyticsIfNeeded"),
            "AppViewModel.swift should forward usage analytics refresh through AppUsageAnalyticsModel"
        )
        for directDependency in [
            "UsageAnalyticsRepository",
            "UsageAnalyticsSnapshotCacheStore",
            "usageAnalyticsRefreshTask",
            "usageAnalyticsRefreshGeneration"
        ] {
            XCTAssertFalse(
                appViewModel.contains(directDependency),
                "AppViewModel.swift should delegate usage analytics refresh internals instead of owning \(directDependency)"
            )
        }
    }

    func testAppViewModelStatusBarDisplayResponsibilitiesStayInFocusedExtension() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let statusBarDisplayURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel+StatusBarDisplay.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: statusBarDisplayURL.path),
            "Status bar display preferences should live in AppViewModel+StatusBarDisplay.swift"
        )

        if FileManager.default.fileExists(atPath: statusBarDisplayURL.path) {
            let statusBarDisplay = try String(contentsOf: statusBarDisplayURL, encoding: .utf8)
            for focusedResponsibility in [
                "statusBarDisplayConfigDidChangeNotification",
                "func setStatusBarProvider",
                "func setStatusBarDisplayEnabled",
                "func applyStatusBarPreferencesMutation",
                "func notifyStatusBarDisplayConfigChanged"
            ] {
                XCTAssertTrue(
                    statusBarDisplay.contains(focusedResponsibility),
                    "AppViewModel+StatusBarDisplay.swift should own \(focusedResponsibility)"
                )
            }
        }

        for appViewModelResponsibility in [
            "statusBarDisplayConfigDidChangeNotification",
            "func setStatusBarProvider",
            "func setStatusBarDisplayEnabled",
            "func applyStatusBarPreferencesMutation",
            "func notifyStatusBarDisplayConfigChanged"
        ] {
            XCTAssertFalse(
                appViewModel.contains(appViewModelResponsibility),
                "AppViewModel.swift should delegate status bar display responsibilities instead of owning \(appViewModelResponsibility)"
            )
        }
    }

    func testAppViewModelOfficialProfileResponsibilitiesStayInFocusedExtension() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let officialProfilesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel+OfficialProfiles.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: officialProfilesURL.path),
            "Official profile menu, OAuth import, save/remove, and switching responsibilities should live in AppViewModel+OfficialProfiles.swift"
        )

        if FileManager.default.fileExists(atPath: officialProfilesURL.path) {
            let officialProfiles = try String(contentsOf: officialProfilesURL, encoding: .utf8)
            for focusedResponsibility in [
                "func codexSlotViewModels()",
                "func claudeSlotViewModels()",
                "func oauthImportState(for providerType: ProviderType)",
                "func startOAuthImport(providerType: ProviderType, slotID: CodexSlotID)",
                "func cancelOAuthImport(providerType: ProviderType)",
                "func saveCodexProfile(slotID: CodexSlotID, displayName: String, note: String?, authJSON: String)",
                "func removeCodexProfile(slotID: CodexSlotID)",
                "func saveClaudeProfile(",
                "func removeClaudeProfile(slotID: CodexSlotID)",
                "func switchCodexProfile(slotID: CodexSlotID) async",
                "func switchClaudeProfile(slotID: CodexSlotID) async"
            ] {
                XCTAssertTrue(
                    officialProfiles.contains(focusedResponsibility),
                    "AppViewModel+OfficialProfiles.swift should own \(focusedResponsibility)"
                )
                XCTAssertFalse(
                    appViewModel.contains(focusedResponsibility),
                    "AppViewModel.swift should delegate official profile responsibilities instead of owning \(focusedResponsibility)"
                )
            }
        }
    }

    func testUsageAnalyticsValueTypesLiveInApplicationTarget() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let applicationTypesURL = rootURL.appendingPathComponent("Sources/OhMyUsageApplication/UsageAnalyticsTypes.swift")
        let executableTypesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Services/UsageAnalyticsTypes.swift")
        let executableTypes = try String(contentsOf: executableTypesURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: applicationTypesURL.path),
            "Usage analytics pure value types should move into the application target"
        )

        if FileManager.default.fileExists(atPath: applicationTypesURL.path) {
            let applicationTypes = try String(contentsOf: applicationTypesURL, encoding: .utf8)
            for valueTypeDefinition in [
                "struct UsageMetricTotals",
                "enum UsageAnalyticsFilterMode",
                "enum UsageAnalyticsRange",
                "struct UsageAnalyticsFilter",
                "enum UsageAnalyticsRecordSource",
                "struct UsageAnalyticsRecord",
                "struct UsageAnalyticsSnapshot"
            ] {
                XCTAssertTrue(
                    applicationTypes.contains(valueTypeDefinition),
                    "OhMyUsageApplication should own \(valueTypeDefinition)"
                )
            }
        }

        for executableDefinition in [
            "struct UsageMetricTotals",
            "enum UsageAnalyticsFilterMode",
            "enum UsageAnalyticsRange",
            "struct UsageAnalyticsFilter",
            "enum UsageAnalyticsRecordSource",
            "struct UsageAnalyticsRecord",
            "struct UsageAnalyticsSnapshot"
        ] {
            XCTAssertFalse(
                executableTypes.contains(executableDefinition),
                "Executable Services should import usage analytics value types instead of owning \(executableDefinition)"
            )
        }
    }

    func testAppViewModelDoesNotOwnPermissionAndResetImplementations() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)

        for implementationSignature in [
            "func openSystemSettings(",
            "func resetLocalAppData()",
            "func refreshPermissionStatuses("
        ] {
            XCTAssertFalse(
                appViewModel.contains(implementationSignature),
                "AppViewModel.swift should move \(implementationSignature) into focused AppViewModel extensions"
            )
        }
    }

    func testAppViewModelProviderConfigurationResponsibilitiesStayInFocusedExtension() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let providerConfigurationURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel+ProviderConfiguration.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)
        let appViewModelLineCount = appViewModel.split(separator: "\n", omittingEmptySubsequences: false).count

        XCTAssertLessThanOrEqual(
            appViewModelLineCount,
            1200,
            "AppViewModel.swift should stay below the provider configuration split budget"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: providerConfigurationURL.path),
            "Provider, credential, relay, and official settings responsibilities should live in AppViewModel+ProviderConfiguration.swift"
        )

        guard FileManager.default.fileExists(atPath: providerConfigurationURL.path) else {
            return
        }

        let providerConfiguration = try String(contentsOf: providerConfigurationURL, encoding: .utf8)
        for focusedResponsibility in [
            "func setLanguage(",
            "func setResourceMode(",
            "func setLaunchAtLoginEnabled(",
            "func setGlobalRefreshIntervalSeconds(",
            "func persistConfiguration(",
            "func resetConfiguration(",
            "func applyConfigurationPersistenceOutcome(",
            "func pruneThirdPartyBalanceBaselines()",
            "func setEnabled(",
            "func reorderEnabledProviders(",
            "func setLowThreshold(",
            "func commitProviderThreshold(",
            "func hasToken(for descriptor:",
            "func savedTokenLength(for descriptor:",
            "func saveToken(_ token: String, for descriptor:",
            "func saveTokenAndRestart(_ token: String, for descriptor:",
            "func saveToken(_ token: String, auth:",
            "func saveTokenAndRestart(_ token: String, auth:",
            "func hasOfficialManualCookie(",
            "func savedOfficialManualCookieLength(",
            "func saveOfficialManualCookie(",
            "func saveOfficialManualCookieAndRestart(",
            "func invalidateCredentialLookupCache()",
            "func addRelaySiteDraft(",
            "func addOpenRelay(",
            "func removeProvider(providerID:",
            "func updateOpenProviderSettings(",
            "func saveRelayDraft(",
            "func relayDescriptorForPreview(",
            "func testRelayDraft(",
            "func importRelayDraftFromBrowser(",
            "func updateThirdPartyQuotaDisplayMode(",
            "func relayAdapterName(",
            "func relayAuthSource(",
            "func relayFetchHealth(",
            "func relayValueFreshness(",
            "func testRelayConnection(providerID:",
            "func testRelayConnection(descriptor:",
            "func updateOfficialProviderSettings(",
            "func saveOfficialDraft(",
            "func saveOfficialCredentialAndSettings("
        ] {
            XCTAssertTrue(
                providerConfiguration.contains(focusedResponsibility),
                "AppViewModel+ProviderConfiguration.swift should own \(focusedResponsibility)"
            )
            XCTAssertFalse(
                appViewModel.contains(focusedResponsibility),
                "AppViewModel.swift should not re-own provider configuration responsibility \(focusedResponsibility)"
            )
        }
    }
}
