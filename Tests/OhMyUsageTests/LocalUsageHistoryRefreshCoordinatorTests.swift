import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class LocalUsageHistoryRefreshCoordinatorTests: XCTestCase {
    func testGeminiQueryLoadsLocalHistory() {
        let coordinator = LocalUsageHistoryRefreshCoordinator()
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("local-history-\(UUID().uuidString)", isDirectory: true)
        )
        var invoked = false

        coordinator.refreshLocalUsageHistoryIfNeeded(
            query: LocalUsageHistoryQuery(
                providerType: .gemini,
                providerID: "gemini-official",
                scope: .allAccounts,
                identityKey: "all"
            ),
            repository: repository,
            performRefresh: { _, _, _, _, _, _ in
                invoked = true
            },
            onStateChange: {}
        )

        XCTAssertTrue(invoked)
    }

    func testRelayQueryIsIgnored() {
        let coordinator = LocalUsageHistoryRefreshCoordinator()
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("local-history-\(UUID().uuidString)", isDirectory: true)
        )
        var invoked = false

        coordinator.refreshLocalUsageHistoryIfNeeded(
            query: LocalUsageHistoryQuery(
                providerType: .relay,
                providerID: "deepseek-official",
                scope: .allAccounts,
                identityKey: "all"
            ),
            repository: repository,
            performRefresh: { _, _, _, _, _, _ in
                invoked = true
            },
            onStateChange: {}
        )

        XCTAssertFalse(invoked)
    }
}
