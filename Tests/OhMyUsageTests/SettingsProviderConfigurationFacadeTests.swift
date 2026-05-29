import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

@MainActor
final class SettingsProviderConfigurationFacadeTests: XCTestCase {
    func testFacadeForwardsStatusBarAndOfficialSettingsMutations() {
        var statusBarProviderQueries: [String] = []
        var statusBarMutations: [(String, Bool)] = []
        var showEmailMutations: [Bool] = []
        var planTypeQueries: [String] = []
        var planTypeMutations: [(String, Bool)] = []
        var expirationQueries: [String] = []
        var expirationMutations: [(String, Bool)] = []
        var officialSettings: [(String, OfficialSourceMode, OfficialWebMode, OfficialQuotaDisplayMode?, OfficialTraeValueDisplayMode?)] = []
        var thresholds: [(String, Double)] = []

        let facade = SettingsProviderConfigurationFacade(
            language: .zhHans,
            showOfficialAccountEmailInMenuBar: { false },
            isStatusBarProvider: {
                statusBarProviderQueries.append($0)
                return $0 == "codex"
            },
            setStatusBarDisplayEnabled: { enabled, providerID in
                statusBarMutations.append((providerID, enabled))
            },
            setShowOfficialAccountEmailInMenuBar: {
                showEmailMutations.append($0)
            },
            showOfficialPlanTypeInMenuBar: {
                planTypeQueries.append($0)
                return false
            },
            setShowOfficialPlanTypeInMenuBar: { enabled, providerID in
                planTypeMutations.append((providerID, enabled))
            },
            showExpirationTimeInMenuBar: {
                expirationQueries.append($0)
                return true
            },
            setShowExpirationTimeInMenuBar: { enabled, providerID in
                expirationMutations.append((providerID, enabled))
            },
            updateOfficialProviderSettings: { providerID, sourceMode, webMode, quotaDisplayMode, traeValueDisplayMode in
                officialSettings.append((providerID, sourceMode, webMode, quotaDisplayMode, traeValueDisplayMode))
            },
            commitProviderThreshold: { value, providerID in
                thresholds.append((providerID, value))
            }
        )

        XCTAssertTrue(facade.isStatusBarProvider(providerID: "codex"))
        facade.setStatusBarDisplayEnabled(false, providerID: "codex")
        XCTAssertFalse(facade.showOfficialAccountEmailInMenuBar)
        facade.setShowOfficialAccountEmailInMenuBar(true)
        XCTAssertFalse(facade.showOfficialPlanTypeInMenuBar(providerID: "trae"))
        facade.setShowOfficialPlanTypeInMenuBar(true, providerID: "trae")
        XCTAssertTrue(facade.showExpirationTimeInMenuBar(providerID: "trae"))
        facade.setShowExpirationTimeInMenuBar(false, providerID: "trae")
        facade.updateOfficialProviderSettings(
            providerID: "trae",
            sourceMode: .auto,
            webMode: .disabled,
            quotaDisplayMode: .used,
            traeValueDisplayMode: .amount
        )
        facade.commitProviderThreshold(42, providerID: "trae")

        XCTAssertEqual(statusBarProviderQueries, ["codex"])
        XCTAssertEqual(statusBarMutations.map(\.0), ["codex"])
        XCTAssertEqual(statusBarMutations.map(\.1), [false])
        XCTAssertEqual(showEmailMutations, [true])
        XCTAssertEqual(planTypeQueries, ["trae"])
        XCTAssertEqual(planTypeMutations.map(\.0), ["trae"])
        XCTAssertEqual(planTypeMutations.map(\.1), [true])
        XCTAssertEqual(expirationQueries, ["trae"])
        XCTAssertEqual(expirationMutations.map(\.0), ["trae"])
        XCTAssertEqual(expirationMutations.map(\.1), [false])
        XCTAssertEqual(officialSettings.count, 1)
        XCTAssertEqual(officialSettings.first?.0, "trae")
        XCTAssertEqual(officialSettings.first?.1, .auto)
        XCTAssertEqual(officialSettings.first?.2, .disabled)
        XCTAssertEqual(officialSettings.first?.3, .used)
        XCTAssertEqual(officialSettings.first?.4, .amount)
        XCTAssertEqual(thresholds.map(\.0), ["trae"])
        XCTAssertEqual(thresholds.map(\.1), [42])
    }

    func testFacadeForwardsRelayDraftActions() async {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Demo Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )
        let draft = RelaySettingsDraft(provider: provider)
        var savedDrafts: [RelaySettingsDraft] = []
        var testedDrafts: [RelaySettingsDraft] = []
        var importedDrafts: [RelaySettingsDraft] = []
        var quotaDisplayMutations: [(String, OfficialQuotaDisplayMode)] = []
        var removedProviderIDs: [String] = []

        let facade = SettingsProviderConfigurationFacade(
            language: .en,
            saveRelayDraft: {
                savedDrafts.append($0)
            },
            testRelayDraft: {
                testedDrafts.append($0)
                return RelayDiagnosticResult(
                    success: true,
                    fetchHealth: .ok,
                    resolvedAdapterID: $0.preferredAdapterID,
                    resolvedAuthSource: nil,
                    message: "ok",
                    snapshotPreview: nil
                )
            },
            importRelayDraftFromBrowser: {
                importedDrafts.append($0)
                return RelayDiagnosticResult(
                    success: false,
                    fetchHealth: .authExpired,
                    resolvedAdapterID: $0.preferredAdapterID,
                    resolvedAuthSource: nil,
                    message: "missing",
                    snapshotPreview: nil
                )
            },
            updateThirdPartyQuotaDisplayMode: { providerID, mode in
                quotaDisplayMutations.append((providerID, mode))
            },
            removeProvider: {
                removedProviderIDs.append($0)
            }
        )

        facade.saveRelayDraft(draft)
        let testResult = await facade.testRelayDraft(draft)
        let importResult = await facade.importRelayDraftFromBrowser(draft)
        facade.updateThirdPartyQuotaDisplayMode(providerID: provider.id, quotaDisplayMode: OfficialQuotaDisplayMode.used)
        facade.removeProvider(providerID: provider.id)

        XCTAssertEqual(savedDrafts.map(\.providerID), [provider.id])
        XCTAssertEqual(testedDrafts.map(\.providerID), [provider.id])
        XCTAssertTrue(testResult.success)
        XCTAssertEqual(importedDrafts.map(\.providerID), [provider.id])
        XCTAssertFalse(importResult.success)
        XCTAssertEqual(quotaDisplayMutations.map(\.0), [provider.id])
        XCTAssertEqual(quotaDisplayMutations.map(\.1), [.used])
        XCTAssertEqual(removedProviderIDs, [provider.id])
    }
}
