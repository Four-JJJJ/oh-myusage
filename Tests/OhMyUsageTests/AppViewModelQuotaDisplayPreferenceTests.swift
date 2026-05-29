import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppViewModelQuotaDisplayPreferenceTests: XCTestCase {
    func testUpdateOfficialQuotaDisplayModePostsStatusBarDisplayConfigNotification() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = false
        let viewModel = makeViewModel(providers: [codex])

        assertPostsStatusBarDisplayConfigNotification(
            description: "Changing official usage preference should trigger status bar refresh notification"
        ) {
            viewModel.updateOfficialProviderSettings(
                providerID: codex.id,
                sourceMode: .auto,
                webMode: .autoImport,
                quotaDisplayMode: .used
            )
        }

        XCTAssertEqual(viewModel.config.providers.first?.officialConfig?.quotaDisplayMode, .used)
    }

    func testUpdateThirdPartyQuotaDisplayModePostsStatusBarDisplayConfigNotification() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Quota Relay",
            baseURL: "https://quota-display-relay.test"
        )
        relay.enabled = false
        let viewModel = makeViewModel(providers: [relay])

        assertPostsStatusBarDisplayConfigNotification(
            description: "Changing third-party usage preference should trigger status bar refresh notification"
        ) {
            viewModel.updateThirdPartyQuotaDisplayMode(
                providerID: relay.id,
                quotaDisplayMode: .used
            )
        }

        XCTAssertEqual(viewModel.config.providers.first?.relayConfig?.quotaDisplayMode, .used)
    }

    func testUpdateOfficialRelayQuotaDisplayModePostsStatusBarDisplayConfigNotification() {
        var mimo = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        mimo.enabled = false
        mimo.relayConfig?.quotaDisplayMode = .used
        let viewModel = makeViewModel(providers: [mimo])

        assertPostsStatusBarDisplayConfigNotification(
            description: "Changing official relay usage preference should trigger status bar refresh notification"
        ) {
            viewModel.updateThirdPartyQuotaDisplayMode(
                providerID: mimo.id,
                quotaDisplayMode: .remaining
            )
        }

        XCTAssertEqual(viewModel.config.providers.first?.relayConfig?.quotaDisplayMode, .remaining)
        XCTAssertFalse(viewModel.config.providers.first?.displaysUsedQuota ?? true)
    }

    func testUpdateOfficialTraeValueDisplayModePostsStatusBarDisplayConfigNotification() {
        var trae = ProviderDescriptor.defaultOfficialTrae()
        trae.enabled = false
        let viewModel = makeViewModel(providers: [trae])

        assertPostsStatusBarDisplayConfigNotification(
            description: "Changing Trae value display mode should trigger status bar refresh notification"
        ) {
            viewModel.updateOfficialProviderSettings(
                providerID: trae.id,
                sourceMode: .auto,
                webMode: .disabled,
                quotaDisplayMode: .remaining,
                traeValueDisplayMode: .amount
            )
        }

        XCTAssertEqual(viewModel.config.providers.first?.officialConfig?.traeValueDisplayMode, .amount)
    }

    func testSetShowOfficialAccountEmailPostsStatusBarDisplayConfigNotification() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = false
        let viewModel = makeViewModel(providers: [codex])

        assertPostsStatusBarDisplayConfigNotification(
            description: "Changing show email toggle should trigger status bar refresh notification"
        ) {
            viewModel.setShowOfficialAccountEmailInMenuBar(true)
        }

        XCTAssertTrue(viewModel.showOfficialAccountEmailInMenuBar)
    }

    func testSetShowOfficialPlanTypePostsStatusBarDisplayConfigNotification() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = false
        let viewModel = makeViewModel(providers: [codex])

        assertPostsStatusBarDisplayConfigNotification(
            description: "Changing show plan type toggle should trigger status bar refresh notification"
        ) {
            viewModel.setShowOfficialPlanTypeInMenuBar(false, providerID: codex.id)
        }

        XCTAssertFalse(viewModel.showOfficialPlanTypeInMenuBar(providerID: codex.id))
    }

    func testSetShowExpirationTimePostsStatusBarDisplayConfigNotification() {
        var mimo = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        mimo.enabled = false
        let viewModel = makeViewModel(providers: [mimo])

        assertPostsStatusBarDisplayConfigNotification(
            description: "Changing expiration time toggle should trigger display config notification"
        ) {
            viewModel.setShowExpirationTimeInMenuBar(false, providerID: mimo.id)
        }

        XCTAssertFalse(viewModel.showExpirationTimeInMenuBar(providerID: mimo.id))
        XCTAssertFalse(viewModel.config.providers.first?.relayConfig?.showExpirationTimeInMenuBar ?? true)
    }

    func testUpdateOfficialQuotaDisplayModeDoesNotPostWhenValueUnchanged() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = false
        let viewModel = makeViewModel(providers: [codex])

        assertDoesNotPostStatusBarDisplayConfigNotification(
            description: "Unchanged official usage preference should not trigger status bar refresh notification"
        ) {
            viewModel.updateOfficialProviderSettings(
                providerID: codex.id,
                sourceMode: .auto,
                webMode: .autoImport,
                quotaDisplayMode: .remaining
            )
        }
    }

    func testUpdateThirdPartyQuotaDisplayModeDoesNotPostWhenValueUnchanged() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Quota Relay",
            baseURL: "https://quota-display-relay.test"
        )
        relay.enabled = false
        let viewModel = makeViewModel(providers: [relay])

        assertDoesNotPostStatusBarDisplayConfigNotification(
            description: "Unchanged third-party usage preference should not trigger status bar refresh notification"
        ) {
            viewModel.updateThirdPartyQuotaDisplayMode(
                providerID: relay.id,
                quotaDisplayMode: .remaining
            )
        }
    }

    func testSetShowOfficialAccountEmailDoesNotPostWhenValueUnchanged() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = false
        let viewModel = makeViewModel(providers: [codex])

        assertDoesNotPostStatusBarDisplayConfigNotification(
            description: "Unchanged show email toggle should not trigger status bar refresh notification"
        ) {
            viewModel.setShowOfficialAccountEmailInMenuBar(false)
        }
    }

    func testSetShowOfficialPlanTypeDoesNotPostWhenValueUnchanged() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = false
        let viewModel = makeViewModel(providers: [codex])

        assertDoesNotPostStatusBarDisplayConfigNotification(
            description: "Unchanged show plan type toggle should not trigger status bar refresh notification"
        ) {
            viewModel.setShowOfficialPlanTypeInMenuBar(true, providerID: codex.id)
        }
    }

    func testSetShowExpirationTimeDoesNotPostWhenValueUnchanged() {
        var mimo = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        mimo.enabled = false
        let viewModel = makeViewModel(providers: [mimo])

        assertDoesNotPostStatusBarDisplayConfigNotification(
            description: "Unchanged expiration time toggle should not trigger display config notification"
        ) {
            viewModel.setShowExpirationTimeInMenuBar(true, providerID: mimo.id)
        }
    }

    func testUpdateOfficialTraeValueDisplayModeDoesNotPostWhenValueUnchanged() {
        var trae = ProviderDescriptor.defaultOfficialTrae()
        trae.enabled = false
        let viewModel = makeViewModel(providers: [trae])

        assertDoesNotPostStatusBarDisplayConfigNotification(
            description: "Unchanged Trae value display mode should not trigger status bar refresh notification"
        ) {
            viewModel.updateOfficialProviderSettings(
                providerID: trae.id,
                sourceMode: .auto,
                webMode: .disabled,
                quotaDisplayMode: .remaining,
                traeValueDisplayMode: .percent
            )
        }
    }

    func testUpdateOpenProviderSettingsNamePostsStatusBarDisplayConfigNotification() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Quota Relay",
            baseURL: "https://quota-display-relay.test"
        )
        relay.enabled = false
        let viewModel = makeViewModel(providers: [relay])

        assertPostsStatusBarDisplayConfigNotification(
            description: "Changing custom provider name should trigger status bar refresh notification"
        ) {
            updateRelaySettingsName(
                "Relay Renamed",
                viewModel: viewModel,
                providerID: relay.id
            )
        }

        XCTAssertEqual(viewModel.config.providers.first?.name, "Relay Renamed")
    }

    func testUpdateOpenProviderSettingsNameDoesNotPostWhenUnchanged() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Quota Relay",
            baseURL: "https://quota-display-relay.test"
        )
        relay.enabled = false
        let viewModel = makeViewModel(providers: [relay])

        assertDoesNotPostStatusBarDisplayConfigNotification(
            description: "Unchanged custom provider name should not trigger status bar refresh notification"
        ) {
            updateRelaySettingsName(
                "Quota Relay",
                viewModel: viewModel,
                providerID: relay.id
            )
        }
    }

    private func makeViewModel(providers: [ProviderDescriptor]) -> AppViewModel {
        AppViewModel(
            testingConfig: AppConfig(providers: providers),
            appUpdateService: NoopAppUpdateService()
        )
    }

    private func assertPostsStatusBarDisplayConfigNotification(
        description: String,
        timeout: TimeInterval = 1.0,
        perform: () -> Void
    ) {
        let expectation = expectation(description: description)
        let observer = NotificationCenter.default.addObserver(
            forName: AppViewModel.statusBarDisplayConfigDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        perform()
        wait(for: [expectation], timeout: timeout)
    }

    private func assertDoesNotPostStatusBarDisplayConfigNotification(
        description: String,
        timeout: TimeInterval = 0.2,
        perform: () -> Void
    ) {
        let expectation = expectation(description: description)
        expectation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: AppViewModel.statusBarDisplayConfigDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        perform()
        wait(for: [expectation], timeout: timeout)
    }

    private func updateRelaySettingsName(
        _ name: String,
        viewModel: AppViewModel,
        providerID: String
    ) {
        guard let provider = viewModel.config.providers.first(where: { $0.id == providerID }),
              let relayConfig = provider.relayConfig else {
            XCTFail("Relay provider not found")
            return
        }

        let balanceConfig = provider.relayViewConfig?.accountBalance
        let manualOverrides = relayConfig.manualOverrides
        viewModel.updateOpenProviderSettings(
            providerID: providerID,
            name: name,
            baseURL: provider.baseURL ?? relayConfig.baseURL,
            preferredAdapterID: relayConfig.adapterID,
            balanceCredentialMode: relayConfig.balanceCredentialMode ?? .manualPreferred,
            tokenUsageEnabled: relayConfig.tokenChannelEnabled,
            accountEnabled: relayConfig.balanceChannelEnabled,
            authHeader: balanceConfig?.authHeader ?? manualOverrides?.authHeader ?? "Authorization",
            authScheme: balanceConfig?.authScheme ?? manualOverrides?.authScheme ?? "Bearer",
            userID: balanceConfig?.userID ?? manualOverrides?.userID ?? "",
            userIDHeader: balanceConfig?.userIDHeader ?? manualOverrides?.userIDHeader ?? "New-Api-User",
            endpointPath: balanceConfig?.endpointPath ?? manualOverrides?.endpointPath ?? "/api/user/self",
            remainingJSONPath: balanceConfig?.remainingJSONPath ?? manualOverrides?.remainingExpression ?? "data.quota",
            usedJSONPath: balanceConfig?.usedJSONPath ?? manualOverrides?.usedExpression ?? "",
            limitJSONPath: balanceConfig?.limitJSONPath ?? manualOverrides?.limitExpression ?? "",
            successJSONPath: balanceConfig?.successJSONPath ?? manualOverrides?.successExpression ?? "",
            unit: balanceConfig?.unit ?? manualOverrides?.unitExpression ?? "USD",
            quotaDisplayMode: relayConfig.quotaDisplayMode
        )
    }
}

private actor NoopAppUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw AppUpdateError.invalidMetadata
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw AppUpdateError.missingZipAsset
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {}
}
