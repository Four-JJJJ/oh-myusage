import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

@MainActor
final class AppViewModelForcedRefreshTests: XCTestCase {
    func testDiscoverLocalProvidersDoesNotEnableProviderWhenForcedRefreshFails() async {
        var gemini = ProviderDescriptor.defaultOfficialGemini()
        gemini.id = "gemini-official-discovery-\(UUID().uuidString)"
        gemini.enabled = false

        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [gemini]),
            appUpdateService: NoopForcedRefreshAppUpdateService(),
            providerFactory: ForcedRefreshProviderFactory(
                snapshot: Self.sampleSnapshot(source: gemini.id)
            )
        )

        let result = await viewModel.discoverLocalProviders()

        XCTAssertEqual(result, viewModel.text(.localDiscoveryNothingFound))
        XCTAssertFalse(viewModel.config.providers.first?.enabled ?? true)
        XCTAssertNil(viewModel.snapshots[gemini.id])
        XCTAssertNil(viewModel.errors[gemini.id])
    }

    func testRelayConnectionReturnsFailureWhenForcedRefreshThrows() async {
        let descriptor = ProviderDescriptor.defaultOpenAilinyu()
        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [descriptor]),
            appUpdateService: NoopForcedRefreshAppUpdateService(),
            providerFactory: ForcedRefreshProviderFactory(
                snapshot: Self.sampleSnapshot(source: descriptor.id)
            )
        )

        let result = await viewModel.testRelayConnection(descriptor: descriptor)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.fetchHealth, .authExpired)
        XCTAssertNil(result.snapshotPreview)
        XCTAssertEqual(viewModel.errors[descriptor.id], ProviderError.unauthorized.localizedDescription)
    }

    private static func sampleSnapshot(source: String) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Test"
        )
    }
}

private struct ForcedRefreshProviderFactory: ProviderFactorying {
    let snapshot: UsageSnapshot

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        ForcedRefreshUsageProvider(descriptor: descriptor, snapshot: snapshot)
    }
}

private struct ForcedRefreshUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot

    func fetch() async throws -> UsageSnapshot {
        snapshot
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        if forceRefresh {
            throw ProviderError.unauthorized
        }
        return snapshot
    }
}

private actor NoopForcedRefreshAppUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw ProviderError.unavailable("unused")
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw ProviderError.unavailable("unused")
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {
    }
}
