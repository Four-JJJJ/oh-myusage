import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppViewModelConfigurationPersistenceTests: XCTestCase {
    func testStatusBarAppearanceSaveFailureShowsPersistenceFailureState() {
        let repository = StubConfigurationRepository(
            initialConfig: .default,
            saveError: StubConfigurationError.saveFailed
        )
        let viewModel = AppViewModel(
            testingConfig: .default,
            configurationRepository: repository,
            appUpdateService: NoopPersistenceUpdateService(),
            settingsPersistenceStatusClearDelaySeconds: 0.05
        )

        viewModel.setStatusBarAppearanceMode(.dark)

        XCTAssertEqual(viewModel.statusBarAppearanceMode, .dark)
        XCTAssertEqual(viewModel.settingsPersistenceDisplayState.kind, .failed)
        XCTAssertEqual(
            viewModel.settingsPersistenceDisplayState.statusText,
            viewModel.localizedText("保存失败", "Save Failed")
        )
        XCTAssertEqual(
            viewModel.settingsPersistenceErrorMessage,
            StubConfigurationError.saveFailed.localizedDescription
        )
    }

    func testOfficialDraftSaveShowsSavedStateThenAutoClears() async {
        var config = AppConfig.default
        var provider = ProviderDescriptor.defaultOfficialCodex()
        provider.enabled = false
        config.providers = [provider]

        let repository = StubConfigurationRepository(initialConfig: config)
        let viewModel = AppViewModel(
            testingConfig: config,
            configurationRepository: repository,
            appUpdateService: NoopPersistenceUpdateService(),
            settingsPersistenceStatusClearDelaySeconds: 0.05
        )

        viewModel.updateOfficialProviderSettings(
            providerID: provider.id,
            sourceMode: .auto,
            webMode: .autoImport,
            quotaDisplayMode: .used
        )

        // Raw stored status (not deadline-resolved) — persistAndRestart can exceed a short clear delay.
        XCTAssertEqual(viewModel.settingsPersistenceStatus.kind, .saved)
        XCTAssertEqual(
            viewModel.settingsPersistenceStatus.statusText,
            viewModel.localizedText("已保存", "Saved")
        )
        XCTAssertEqual(viewModel.config.providers.first?.officialConfig?.quotaDisplayMode, .used)

        // Starve MainActor briefly so the clear Task cannot run; deadline reconcile must still idle.
        let busyUntil = Date().addingTimeInterval(0.08)
        while Date() < busyUntil {}
        XCTAssertEqual(viewModel.settingsPersistenceDisplayState.kind, .idle)
        XCTAssertNil(viewModel.settingsPersistenceErrorMessageForDisplay)
    }

    func testLanguageSaveShowsSavedStateThenAutoClears() async {
        var config = AppConfig.default
        config.language = .zhHans
        let repository = StubConfigurationRepository(initialConfig: config)
        let viewModel = AppViewModel(
            testingConfig: config,
            configurationRepository: repository,
            appUpdateService: NoopPersistenceUpdateService(),
            settingsPersistenceStatusClearDelaySeconds: 0.05
        )

        viewModel.setLanguage(.en)
        XCTAssertEqual(viewModel.settingsPersistenceStatus.kind, .saved)

        let busyUntil = Date().addingTimeInterval(0.08)
        while Date() < busyUntil {}
        XCTAssertEqual(viewModel.settingsPersistenceDisplayState.kind, .idle)
        XCTAssertNil(viewModel.settingsPersistenceErrorMessageForDisplay)
    }

    func testGlobalRefreshIntervalPersistsAcrossProviders() {
        var config = AppConfig.default
        var codex = ProviderDescriptor.defaultOfficialCodex()
        var relay = ProviderDescriptor.defaultOpenAilinyu()
        codex.pollIntervalSec = 60
        relay.pollIntervalSec = 120
        config.providers = [codex, relay]

        let repository = StubConfigurationRepository(initialConfig: config)
        let viewModel = AppViewModel(
            testingConfig: config,
            configurationRepository: repository,
            appUpdateService: NoopPersistenceUpdateService(),
            settingsPersistenceStatusClearDelaySeconds: 0.05
        )

        viewModel.setGlobalRefreshIntervalSeconds(30)

        XCTAssertEqual(viewModel.globalRefreshIntervalSeconds, 30)
        XCTAssertTrue(viewModel.config.providers.allSatisfy { $0.pollIntervalSec == 30 })
        XCTAssertTrue(repository.storedConfig.providers.allSatisfy { $0.pollIntervalSec == 30 })
        XCTAssertEqual(viewModel.settingsPersistenceDisplayState.kind, .saved)
    }

    func testResourceModePersistsAndUpdatesViewModel() {
        let repository = StubConfigurationRepository(initialConfig: .default)
        let viewModel = AppViewModel(
            testingConfig: .default,
            configurationRepository: repository,
            appUpdateService: NoopPersistenceUpdateService(),
            settingsPersistenceStatusClearDelaySeconds: 0.05
        )

        viewModel.setResourceMode(.background15Minutes)

        XCTAssertEqual(viewModel.resourceMode, .background15Minutes)
        XCTAssertEqual(repository.storedConfig.resourceMode, .background15Minutes)
        XCTAssertEqual(viewModel.settingsPersistenceDisplayState.kind, .saved)
    }

    func testAddRelaySiteDraftPersistsProviderWithUserIDAndBrowserPreferredCredentialMode() throws {
        let config = AppConfig(providers: [])
        let repository = StubConfigurationRepository(initialConfig: config)
        let viewModel = AppViewModel(
            testingConfig: config,
            configurationRepository: repository,
            appUpdateService: NoopPersistenceUpdateService(),
            keychain: KeychainService(storageURL: makeCredentialURL()),
            settingsPersistenceStatusClearDelaySeconds: 0.05
        )

        let beforeCount = viewModel.config.providers.count
        let added = try XCTUnwrap(viewModel.addRelaySiteDraft(
            name: "Team Relay",
            baseURL: "relay.example.com/dashboard?ignored=1",
            preferredAdapterID: "generic-newapi",
            userID: " 1001 "
        ))
        let provider = try XCTUnwrap(viewModel.config.providers.first { $0.id == added.id })

        XCTAssertEqual(viewModel.config.providers.count, beforeCount + 1)
        XCTAssertTrue(repository.storedConfig.providers.contains { $0.id == added.id })
        XCTAssertEqual(provider.name, "Team Relay")
        XCTAssertEqual(provider.baseURL, "https://relay.example.com")
        XCTAssertEqual(provider.relayConfig?.baseURL, "https://relay.example.com")
        XCTAssertEqual(provider.relayConfig?.adapterID, "generic-newapi")
        XCTAssertEqual(provider.relayConfig?.tokenChannelEnabled, false)
        XCTAssertEqual(provider.relayConfig?.balanceChannelEnabled, true)
        XCTAssertEqual(provider.relayConfig?.balanceCredentialMode, .browserPreferred)
        XCTAssertEqual(provider.relayConfig?.quotaDisplayMode, .remaining)
        XCTAssertEqual(provider.relayViewConfig?.accountBalance?.userID, "1001")
    }

    func testAddRelaySiteDraftWithBlankBaseURLDoesNotPersistProvider() {
        let config = AppConfig(providers: [])
        let repository = StubConfigurationRepository(initialConfig: config)
        let viewModel = AppViewModel(
            testingConfig: config,
            configurationRepository: repository,
            appUpdateService: NoopPersistenceUpdateService(),
            keychain: KeychainService(storageURL: makeCredentialURL()),
            settingsPersistenceStatusClearDelaySeconds: 0.05
        )

        let beforeProviderIDs = Set(viewModel.config.providers.map(\.id))
        let storedBefore = repository.storedConfig
        let added = viewModel.addRelaySiteDraft(
            name: "Blank Relay",
            baseURL: "   ",
            preferredAdapterID: "generic-newapi",
            userID: "1001",
            credentialInput: "secret-token"
        )

        XCTAssertNil(added)
        XCTAssertEqual(Set(viewModel.config.providers.map(\.id)), beforeProviderIDs)
        XCTAssertEqual(repository.storedConfig, storedBefore)
    }

    func testAddRelaySiteDraftSavesCredentialToBalanceAuth() throws {
        let config = AppConfig(providers: [])
        let repository = StubConfigurationRepository(initialConfig: config)
        let viewModel = AppViewModel(
            testingConfig: config,
            configurationRepository: repository,
            appUpdateService: NoopPersistenceUpdateService(),
            keychain: KeychainService(storageURL: makeCredentialURL()),
            settingsPersistenceStatusClearDelaySeconds: 0.05
        )

        let provider = try XCTUnwrap(viewModel.addRelaySiteDraft(
            name: "Credential Relay",
            baseURL: "https://credential.example.com",
            preferredAdapterID: "generic-newapi",
            userID: "1001",
            credentialInput: "secret-token"
        ))
        let balanceAuth = try XCTUnwrap(provider.relayConfig?.balanceAuth)

        XCTAssertTrue(viewModel.hasToken(auth: balanceAuth))
        XCTAssertNotNil(viewModel.savedTokenLength(auth: balanceAuth))
        XCTAssertFalse(viewModel.hasToken(for: provider))
        XCTAssertEqual(balanceAuth.keychainAccount, "credential.example.com/system-access-token")
    }

    private func makeCredentialURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private func assertEventually(
        _ message: String,
        timeout: TimeInterval = 1.0,
        pollInterval: TimeInterval = 0.01,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        XCTAssertTrue(condition(), message)
    }
}

private final class StubConfigurationRepository: AppConfigurationRepositorying {
    var lastLoadWasLossy = false

    private(set) var storedConfig: AppConfig
    private let saveError: Error?
    private let resetError: Error?

    init(
        initialConfig: AppConfig,
        saveError: Error? = nil,
        resetError: Error? = nil
    ) {
        self.storedConfig = initialConfig
        self.saveError = saveError
        self.resetError = resetError
    }

    func load() throws -> AppConfig {
        storedConfig
    }

    func save(_ config: AppConfig) throws {
        storedConfig = config
        if let saveError {
            throw saveError
        }
    }

    func saveDuringBootstrap(_ config: AppConfig) throws {
        try save(config)
    }

    func reset() throws {
        if let resetError {
            throw resetError
        }
        storedConfig = .default
    }
}

private enum StubConfigurationError: LocalizedError {
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "stub save failed"
        }
    }
}

private actor NoopPersistenceUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw AppUpdateError.invalidMetadata
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw AppUpdateError.missingZipAsset
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {}
}
