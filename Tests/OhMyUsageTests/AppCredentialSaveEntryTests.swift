import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

/// 单一保存入口 saveCredential 的端到端行为：keychain 目标槽位 + restart 条件。
@MainActor
final class AppCredentialSaveEntryTests: XCTestCase {
    func testSaveCredentialProviderTokenWritesDescriptorAuthSlot() throws {
        let provider = ProviderDescriptor.defaultOfficialZai()
        let config = AppConfig(providers: [provider])
        let viewModel = makeViewModel(config: config)

        let saved = viewModel.saveCredential("zai-key", field: .providerToken(provider))

        XCTAssertTrue(saved)
        XCTAssertTrue(viewModel.hasToken(for: provider))
        XCTAssertEqual(viewModel.savedTokenLength(for: provider), "zai-key".count)
    }

    func testSaveCredentialAuthTokenWritesAuthSlotOnly() throws {
        let viewModel = makeViewModel(config: AppConfig(providers: []))
        let auth = AuthConfig(
            kind: .bearer,
            keychainService: KeychainService.defaultServiceName,
            keychainAccount: "relay.example.com/system-access-token"
        )

        let saved = viewModel.saveCredential("relay-token", field: .authToken(auth))

        XCTAssertTrue(saved)
        XCTAssertTrue(viewModel.hasToken(auth: auth))
        XCTAssertEqual(viewModel.savedTokenLength(auth: auth), "relay-token".count)
    }

    func testSaveCredentialOfficialManualCookieWritesManualCookieAccount() throws {
        let provider = ProviderDescriptor.defaultOfficialOllamaCloud()
        let config = AppConfig(providers: [provider])
        let viewModel = makeViewModel(config: config)

        let saved = viewModel.saveCredential("session=abc", field: .officialManualCookie(providerID: provider.id))

        XCTAssertTrue(saved)
        XCTAssertTrue(viewModel.hasOfficialManualCookie(for: provider))
        XCTAssertEqual(viewModel.savedOfficialManualCookieLength(for: provider), "session=abc".count)
    }

    func testSaveCredentialBlankValueDoesNotPersist() throws {
        let provider = ProviderDescriptor.defaultOfficialZai()
        let config = AppConfig(providers: [provider])
        let viewModel = makeViewModel(config: config)

        let saved = viewModel.saveCredential("   ", field: .providerToken(provider))

        XCTAssertFalse(saved)
        XCTAssertFalse(viewModel.hasToken(for: provider))
    }

    func testSaveCredentialInvalidatesProviderSnapshotsAndPersistedCache() throws {
        let provider = ProviderDescriptor.defaultOfficialZai()
        let config = AppConfig(providers: [provider])
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageCredentialSnapshotTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("provider_snapshots.json")
        let cache = PersistedSnapshotCache(fileURL: cacheURL)
        let viewModel = makeViewModel(config: config, persistedSnapshotCache: cache)
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 10,
            used: 90,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "old account",
            sourceLabel: "Test"
        )
        viewModel.providerRefreshModel.mutateProviderState { state in
            state.snapshots[provider.id] = snapshot
            state.errors[provider.id] = "old error"
            state.consecutiveFailures[provider.id] = 2
        }
        cache.save(providerID: provider.id, snapshot: snapshot)

        XCTAssertTrue(viewModel.saveCredential("new-zai-key", field: .providerToken(provider)))

        XCTAssertNil(viewModel.snapshots[provider.id])
        XCTAssertNil(viewModel.errors[provider.id])
        XCTAssertTrue(cache.loadAll().isEmpty)
    }

    func testProviderTokenAffectsEveryProviderSharingCredentialSlot() {
        let provider = ProviderDescriptor.defaultOfficialZai()
        var sharedProvider = ProviderDescriptor.defaultOfficialZai()
        sharedProvider.id = "shared-zai"
        var unrelatedProvider = ProviderDescriptor.defaultOfficialOpenRouterCredits()
        unrelatedProvider.id = "unrelated"

        let affectedProviderIDs = AppCredentialField.providerToken(provider).affectedProviderIDs(
            in: [provider, sharedProvider, unrelatedProvider]
        )

        XCTAssertEqual(affectedProviderIDs, [provider.id, sharedProvider.id])
    }

    // MARK: - restart 条件

    func testShouldRestartPollingOnlyWhenPersistedAndPolicyRequests() {
        XCTAssertTrue(AppConfigurationModel.shouldRestartPolling(didPersist: true, policy: .restartPolling))
        XCTAssertFalse(AppConfigurationModel.shouldRestartPolling(didPersist: true, policy: .none))
        XCTAssertFalse(AppConfigurationModel.shouldRestartPolling(didPersist: false, policy: .restartPolling))
        XCTAssertFalse(AppConfigurationModel.shouldRestartPolling(didPersist: false, policy: .none))
    }

    func testSaveCredentialFailedWriteDoesNotRestartOrPersist() throws {
        let provider = ProviderDescriptor.defaultOfficialZai()
        var descriptor = provider
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: nil, keychainAccount: nil)
        let config = AppConfig(providers: [descriptor])
        let viewModel = makeViewModel(config: config)

        let saved = viewModel.saveCredential("zai-key", field: .providerToken(descriptor), restartPolicy: .restartPolling)

        XCTAssertFalse(saved)
        XCTAssertFalse(viewModel.hasToken(for: descriptor))
    }

    // MARK: - helpers

    private func makeViewModel(
        config: AppConfig,
        persistedSnapshotCache: PersistedSnapshotCache? = nil
    ) -> AppViewModel {
        AppViewModel(
            testingConfig: config,
            configurationRepository: StubCredentialSaveConfigurationRepository(initialConfig: config),
            appUpdateService: NoopCredentialSaveUpdateService(),
            keychain: KeychainService(storageURL: makeCredentialURL()),
            settingsPersistenceStatusClearDelaySeconds: 0.05,
            persistedSnapshotCache: persistedSnapshotCache
        )
    }

    private func makeCredentialURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("credentials.json")
    }
}

private final class StubCredentialSaveConfigurationRepository: AppConfigurationRepositorying {
    var lastLoadWasLossy = false
    private(set) var storedConfig: AppConfig

    init(initialConfig: AppConfig) {
        self.storedConfig = initialConfig
    }

    func load() throws -> AppConfig { storedConfig }
    func save(_ config: AppConfig) throws { storedConfig = config }
    func saveDuringBootstrap(_ config: AppConfig) throws { storedConfig = config }
    func reset() throws { storedConfig = .default }
}

private actor NoopCredentialSaveUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw AppUpdateError.invalidMetadata
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw AppUpdateError.missingZipAsset
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {
        throw AppUpdateError.extractedAppNotFound
    }
}
