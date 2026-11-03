import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageApplication

@MainActor
final class UsageAnalyticsRefreshCoordinatorTests: XCTestCase {
    func testRefreshProbesCCSwitchFingerprintBeforeProbeIntervalAndRefreshesChangedSnapshot() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("usage-analytics-coordinator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let savedAt = try fixedDate("2026-05-16T12:00:00Z")
        let refreshedAt = savedAt.addingTimeInterval(30)
        let filter = UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .last7Days)
        let cachedSnapshot = UsageAnalyticsSnapshot.empty(filter: filter, generatedAt: savedAt)
        let initialFingerprint = usageAnalyticsFingerprint(ccSwitchSeed: 1, localSeed: 1, at: savedAt)
        var fingerprintWithChangedCCSwitch = initialFingerprint
        fingerprintWithChangedCCSwitch.ccSwitch = UsageAnalyticsFileFingerprint(
            roots: ["/tmp/cc-switch-2.db"],
            fileCount: 2,
            totalSize: 256,
            latestModificationTime: refreshedAt
        )
        let changedFingerprint = fingerprintWithChangedCCSwitch
        let cacheStore = UsageAnalyticsSnapshotCacheStore(baseDirectoryURL: root, nowProvider: { savedAt })
        cacheStore.save(snapshot: cachedSnapshot, sourceFingerprint: initialFingerprint)

        let fingerprintCallCount = TestCounter()
        let coordinator = UsageAnalyticsRefreshCoordinator(
            cacheStore: cacheStore,
            nowProvider: { refreshedAt },
            sourceFingerprintLoader: { _ in
                fingerprintCallCount.increment()
                return changedFingerprint
            },
            snapshotLoader: { filter, _ in
                UsageAnalyticsSnapshot.empty(filter: filter, generatedAt: refreshedAt)
            }
        )

        var snapshots: [UsageAnalyticsSnapshot] = []
        var loadingStates: [Bool] = []
        let refreshedSnapshot = expectation(description: "changed cc-switch fingerprint refreshes cached analytics")

        coordinator.refreshUsageAnalyticsIfNeeded(
            filter: filter,
            currentSnapshotFilter: filter,
            claudeAllConfigDirs: [],
            force: false,
            onSnapshotChange: {
                snapshots.append($0)
                if snapshots.count == 2 {
                    refreshedSnapshot.fulfill()
                }
            },
            onLoadingChange: { loadingStates.append($0) }
        )

        await fulfillment(of: [refreshedSnapshot], timeout: 2)

        XCTAssertEqual(snapshots.first, cachedSnapshot)
        XCTAssertEqual(snapshots.last?.generatedAt, refreshedAt)
        XCTAssertEqual(cacheStore.entry(for: filter)?.sourceFingerprint, changedFingerprint)
        XCTAssertEqual(fingerprintCallCount.value, 1)
        XCTAssertEqual(loadingStates, [false, false])
    }

    func testRefreshRestoresFreshCachedSnapshotWithoutLoading() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("usage-analytics-coordinator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = try fixedDate("2026-05-16T12:00:00Z")
        let filter = UsageAnalyticsFilter(mode: .all, selectedModelID: nil, range: .last7Days)
        let cachedSnapshot = UsageAnalyticsSnapshot.empty(filter: filter, generatedAt: now)
        let fingerprint = UsageAnalyticsSourceFingerprint(
            ccSwitch: UsageAnalyticsFileFingerprint(roots: ["/tmp/cc-switch.db"], fileCount: 1, totalSize: 128, latestModificationTime: now),
            codex: UsageAnalyticsFileFingerprint(roots: ["/tmp/codex"], fileCount: 2, totalSize: 256, latestModificationTime: now),
            claude: UsageAnalyticsFileFingerprint(roots: ["/tmp/claude"], fileCount: 3, totalSize: 512, latestModificationTime: now),
            kimi: UsageAnalyticsFileFingerprint(roots: ["/tmp/kimi"], fileCount: 4, totalSize: 1024, latestModificationTime: now)
        )
        let cacheStore = UsageAnalyticsSnapshotCacheStore(baseDirectoryURL: root, nowProvider: { now })
        cacheStore.save(snapshot: cachedSnapshot, sourceFingerprint: fingerprint)
        let snapshotCallCount = TestCounter()
        let coordinator = UsageAnalyticsRefreshCoordinator(
            cacheStore: cacheStore,
            nowProvider: { now },
            sourceFingerprintLoader: { _ in fingerprint },
            snapshotLoader: { filter, _ in
                snapshotCallCount.increment()
                return UsageAnalyticsSnapshot.empty(filter: filter, generatedAt: now)
            }
        )

        var snapshots: [UsageAnalyticsSnapshot] = []
        var loadingStates: [Bool] = []
        let validatedCachedSnapshot = expectation(description: "cached analytics fingerprint is validated")

        coordinator.refreshUsageAnalyticsIfNeeded(
            filter: filter,
            currentSnapshotFilter: UsageAnalyticsFilter(),
            claudeAllConfigDirs: [],
            force: false,
            onSnapshotChange: { snapshots.append($0) },
            onLoadingChange: {
                loadingStates.append($0)
                if loadingStates.count == 2 {
                    validatedCachedSnapshot.fulfill()
                }
            }
        )

        await fulfillment(of: [validatedCachedSnapshot], timeout: 2)

        XCTAssertEqual(snapshots, [cachedSnapshot])
        XCTAssertEqual(snapshotCallCount.value, 0)
        XCTAssertEqual(loadingStates, [false, false])
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "UsageAnalyticsRefreshCoordinatorTests", code: 1)
        }
        return date
    }

    private func usageAnalyticsFingerprint(
        ccSwitchSeed: Int,
        localSeed: Int,
        at date: Date
    ) -> UsageAnalyticsSourceFingerprint {
        UsageAnalyticsSourceFingerprint(
            ccSwitch: UsageAnalyticsFileFingerprint(
                roots: ["/tmp/cc-switch-\(ccSwitchSeed).db"],
                fileCount: ccSwitchSeed,
                totalSize: UInt64(ccSwitchSeed * 128),
                latestModificationTime: date
            ),
            codex: UsageAnalyticsFileFingerprint(
                roots: ["/tmp/codex-\(localSeed)"],
                fileCount: localSeed,
                totalSize: UInt64(localSeed * 256),
                latestModificationTime: date
            ),
            claude: UsageAnalyticsFileFingerprint(
                roots: ["/tmp/claude-\(localSeed)"],
                fileCount: localSeed,
                totalSize: UInt64(localSeed * 512),
                latestModificationTime: date
            ),
            kimi: UsageAnalyticsFileFingerprint(
                roots: ["/tmp/kimi-\(localSeed)"],
                fileCount: localSeed,
                totalSize: UInt64(localSeed * 1024),
                latestModificationTime: date
            )
        )
    }

    private final class TestCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
    }
}
