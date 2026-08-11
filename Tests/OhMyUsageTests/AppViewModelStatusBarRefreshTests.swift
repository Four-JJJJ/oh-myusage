import OhMyUsageDomain
import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

@MainActor
final class AppViewModelStatusBarRefreshTests: XCTestCase {
    func testRefreshNowPostsStatusBarDisplayConfigNotificationAfterSnapshotUpdate() async {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Refresh Relay",
            baseURL: "https://status-bar-refresh.test"
        )
        relay.id = "status-bar-refresh-relay"
        relay.enabled = true

        let recorder = StatusBarRefreshRecorder()
        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [relay]),
            appUpdateService: NoopStatusBarRefreshAppUpdateService(),
            providerFactory: StatusBarRefreshProviderFactory(
                recorder: recorder,
                snapshotsByProviderID: [
                    relay.id: Self.sampleSnapshot(source: relay.id, remaining: 82, used: 18)
                ]
            )
        )

        let expectation = expectation(
            description: "Refreshing provider data should invalidate the status bar display"
        )
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

        viewModel.refreshNow()

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(viewModel.snapshots[relay.id]?.remaining, 82)
        let refreshEvents = await recorder.snapshot()
        XCTAssertEqual(refreshEvents, ["\(relay.id):true"])
    }

    func testSelectingNewStatusBarProviderImmediatelyRefreshesThatProvider() async throws {
        var first = ProviderDescriptor.makeOpenRelay(
            name: "Alpha Relay",
            baseURL: "https://alpha-status-refresh.invalid"
        )
        first.id = "status-refresh-alpha"
        first.enabled = true

        var second = ProviderDescriptor.makeOpenRelay(
            name: "Beta Relay",
            baseURL: "https://beta-status-refresh.invalid"
        )
        second.id = "status-refresh-beta"
        second.enabled = true

        let recorder = StatusBarRefreshRecorder()
        let viewModel = AppViewModel(
            testingConfig: AppConfig(
                statusBarProviderID: first.id,
                providers: [first, second]
            ),
            appUpdateService: NoopStatusBarRefreshAppUpdateService(),
            providerFactory: StatusBarRefreshProviderFactory(
                recorder: recorder,
                snapshotsByProviderID: [
                    first.id: Self.sampleSnapshot(source: first.id, remaining: 90, used: 10),
                    second.id: Self.sampleSnapshot(source: second.id, remaining: 64, used: 36)
                ]
            )
        )

        viewModel.setStatusBarProvider(providerID: second.id)

        try await waitUntil {
            await recorder.snapshot() == ["\(second.id):false"]
        }

        XCTAssertEqual(viewModel.snapshots[second.id]?.remaining, 64)
        XCTAssertNil(viewModel.snapshots[first.id])
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
        XCTFail("Timed out waiting for status bar refresh")
    }

    private static func sampleSnapshot(
        source: String,
        remaining: Double,
        used: Double
    ) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: remaining,
            used: used,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Test"
        )
    }
}

private struct StatusBarRefreshProviderFactory: ProviderFactorying {
    let recorder: StatusBarRefreshRecorder
    let snapshotsByProviderID: [String: UsageSnapshot]

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        let snapshot = snapshotsByProviderID[descriptor.id]
            ?? UsageSnapshot(
                source: descriptor.id,
                status: .ok,
                remaining: 100,
                used: 0,
                limit: 100,
                unit: "%",
                updatedAt: Date(),
                note: "ok",
                sourceLabel: "Fallback"
            )
        return StatusBarRefreshUsageProvider(
            descriptor: descriptor,
            snapshot: snapshot,
            recorder: recorder
        )
    }
}

private struct StatusBarRefreshUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot
    let recorder: StatusBarRefreshRecorder

    func fetch() async throws -> UsageSnapshot {
        snapshot
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        await recorder.record("\(descriptor.id):\(forceRefresh)")
        return snapshot
    }
}

private actor StatusBarRefreshRecorder {
    private var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private actor NoopStatusBarRefreshAppUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw ProviderError.unavailable("unused")
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw ProviderError.unavailable("unused")
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {
    }
}
