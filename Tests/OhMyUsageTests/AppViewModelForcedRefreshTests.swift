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

    func testMenuOpenRefreshesOnlyStaleVisibleProviders() async throws {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.id = "codex-menu-open-\(UUID().uuidString)"
        codex.enabled = true

        let recorder = MenuOpenFetchRecorder()
        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [codex]),
            appUpdateService: NoopForcedRefreshAppUpdateService(),
            providerFactory: MenuOpenProviderFactory(snapshot: Self.sampleSnapshot(source: codex.id), recorder: recorder)
        )

        // Doc §9.4: opening the menu refreshes visible providers, but only
        // those whose snapshot is already stale (TTL-aware, not forced).
        viewModel.providerRefreshModel.mutateProviderState { state in
            state.snapshots[codex.id] = Self.sampleSnapshot(source: codex.id, updatedAt: Date())
        }

        viewModel.setMenuPanelVisible(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        let freshOpenCalls = await recorder.snapshot()
        XCTAssertTrue(
            freshOpenCalls.isEmpty,
            "A fresh visible snapshot must not be refetched when the menu opens"
        )

        // Stale snapshot: the next menu open refreshes the visible provider.
        viewModel.setMenuPanelVisible(false)
        viewModel.providerRefreshModel.mutateProviderState { state in
            state.snapshots[codex.id] = Self.sampleSnapshot(
                source: codex.id,
                updatedAt: Date().addingTimeInterval(-1_000)
            )
        }
        viewModel.setMenuPanelVisible(true)

        try await waitUntil {
            await recorder.snapshot() == [false]
        }
        XCTAssertEqual(
            viewModel.snapshots[codex.id]?.remaining,
            80,
            "Menu-open refresh must write back the fetched snapshot"
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        predicate: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for menu-open refresh state")
    }

    private static func sampleSnapshot(source: String, updatedAt: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: updatedAt,
            note: "ok",
            sourceLabel: "Test"
        )
    }
}

private actor MenuOpenFetchRecorder {
    private var calls: [Bool] = []

    func record(_ forceRefresh: Bool) {
        calls.append(forceRefresh)
    }

    func snapshot() -> [Bool] {
        calls
    }
}

private struct MenuOpenProviderFactory: ProviderFactorying {
    let snapshot: UsageSnapshot
    let recorder: MenuOpenFetchRecorder

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        MenuOpenCountingUsageProvider(
            descriptor: descriptor,
            snapshot: snapshot,
            recorder: recorder
        )
    }
}

private struct MenuOpenCountingUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot
    let recorder: MenuOpenFetchRecorder

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        await recorder.record(forceRefresh)
        return snapshot
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
