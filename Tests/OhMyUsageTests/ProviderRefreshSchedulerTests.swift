import Foundation
import XCTest
import OhMyUsageApplication

@MainActor
final class ProviderRefreshSchedulerTests: XCTestCase {
    func testRestartSchedulesOnlyEnabledProvidersAndStopCancels() {
        let enabled = makeProvider(id: "enabled", enabled: true)
        let disabled = makeProvider(id: "disabled", enabled: false)
        let scheduler = makeScheduler(providers: [enabled, disabled])

        scheduler.restart(providers: [enabled, disabled])

        XCTAssertEqual(scheduler.scheduledProviderIDs, ["enabled"])
        XCTAssertEqual(scheduler.pollTaskCount, 1)

        scheduler.stop()

        XCTAssertTrue(scheduler.scheduledProviderIDs.isEmpty)
        XCTAssertEqual(scheduler.pollTaskCount, 0)
    }

    func testRestartWithMultipleEnabledProvidersUsesSinglePollLoopTask() {
        let first = makeProvider(id: "first", enabled: true)
        let second = makeProvider(id: "second", enabled: true)
        let disabled = makeProvider(id: "disabled", enabled: false)
        let scheduler = makeScheduler(providers: [first, second, disabled])

        scheduler.restart(providers: [first, second, disabled])

        XCTAssertEqual(scheduler.scheduledProviderIDs, ["first", "second"])
        XCTAssertEqual(scheduler.pollTaskCount, 1)

        scheduler.stop()
    }

    func testRepeatedRestartKeepsSingleScheduledTaskAndCancelsPriorTask() async throws {
        let provider = makeProvider(id: "poll", enabled: true)
        let recorder = RefreshRecorder()
        let sleepGate = BlockingSleepGate()
        let scheduler = makeScheduler(
            providers: [provider],
            refreshRecorder: recorder,
            startupJitterProvider: { 1 },
            sleepAction: { seconds in
                try await sleepGate.sleep(seconds)
            }
        )

        scheduler.restart(providers: [provider])
        try await waitUntil {
            await sleepGate.snapshot().count == 1
        }

        scheduler.restart(providers: [provider])

        XCTAssertEqual(scheduler.scheduledProviderIDs, ["poll"])
        XCTAssertEqual(scheduler.pollTaskCount, 1)

        try await waitUntil {
            await sleepGate.snapshot().count == 2
        }
        await sleepGate.releaseAll()

        try await waitUntil {
            let events = await recorder.snapshot()
            let sleeps = await sleepGate.snapshot()
            return events.count == 1 && sleeps.count >= 3
        }
        let restartEvents = await recorder.snapshot()
        XCTAssertEqual(restartEvents, ["poll:false"])

        scheduler.stop()
        await sleepGate.releaseAll()
    }

    func testRestartWithDisabledProviderRemovesScheduleAndCancelsPriorTask() async throws {
        let enabled = makeProvider(id: "toggle", enabled: true)
        let disabled = makeProvider(id: "toggle", enabled: false)
        let recorder = RefreshRecorder()
        let sleepGate = BlockingSleepGate()
        let scheduler = makeScheduler(
            providers: [enabled],
            refreshRecorder: recorder,
            startupJitterProvider: { 1 },
            sleepAction: { seconds in
                try await sleepGate.sleep(seconds)
            }
        )

        scheduler.restart(providers: [enabled])
        try await waitUntil {
            await sleepGate.snapshot().count == 1
        }

        scheduler.restart(providers: [disabled])

        XCTAssertTrue(scheduler.scheduledProviderIDs.isEmpty)
        XCTAssertEqual(scheduler.pollTaskCount, 0)

        await sleepGate.releaseAll()
        try await Task.sleep(nanoseconds: 50_000_000)

        let events = await recorder.snapshot()
        XCTAssertEqual(events, [])
    }

    func testRefreshNowSkipsDisabledProvidersAndRefreshesEnabledProviders() async throws {
        let first = makeProvider(id: "first", enabled: true)
        let second = makeProvider(id: "second", enabled: true)
        let disabled = makeProvider(id: "disabled", enabled: false)
        let recorder = RefreshRecorder()
        let scheduler = makeScheduler(
            providers: [first, second, disabled],
            refreshRecorder: recorder
        )

        scheduler.refreshNow(providers: [first, disabled, second])

        try await waitUntil {
            await recorder.snapshot().count == 2
        }
        let events = await recorder.snapshot()
        XCTAssertEqual(Set(events), ["first:true", "second:true"])
    }

    func testRefreshNowDoesNotBlockOtherProvidersWhenOneRefreshIsStillRunning() async throws {
        let first = makeProvider(id: "first", enabled: true)
        let second = makeProvider(id: "second", enabled: true)
        let refreshGate = BlockingRefreshGate()
        let scheduler = makeScheduler(
            providers: [first, second],
            refreshAction: { providerID, forceRefresh in
                await refreshGate.refresh(providerID: providerID, forceRefresh: forceRefresh)
            }
        )

        scheduler.refreshNow(providers: [first, second])

        try await waitUntil {
            let events = await refreshGate.snapshot()
            return Set(events) == ["first:true", "second:true"]
        }

        await refreshGate.releaseAll()
    }

    func testPollLoopUsesFailureBackoff() async throws {
        let provider = makeProvider(id: "poll", enabled: true, pollIntervalSec: 60)
        var events: [String] = []
        let sleepRecorder = SleepRecorder()
        let scheduler = makeScheduler(
            providers: [provider],
            failureCounts: ["poll": 1],
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                events.append("\(providerID):\(forceRefresh)")
            },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])

        try await waitUntil {
            let sleeps = await sleepRecorder.snapshot()
            return events == ["poll:false"] && self.timeIntervals(sleeps, approximatelyEqualTo: [120])
        }
        scheduler.stop()
    }

    func testBackgroundProviderUsesConfiguredBackgroundInterval() async throws {
        let foreground = makeProvider(id: "foreground", enabled: true, pollIntervalSec: 300)
        // Doc §9.3: the background interval combines the scheduler's background
        // floor with the provider's own cadence (never polls faster than either).
        let background = makeProvider(id: "background", enabled: true, pollIntervalSec: 60)
        var events: [String] = []
        let sleepGate = BlockingSleepGate()
        let scheduler = makeScheduler(
            providers: [foreground, background],
            activeProviderIDs: ["foreground"],
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                events.append("\(providerID):\(forceRefresh)")
            },
            sleepAction: { seconds in
                try await sleepGate.sleep(seconds)
            }
        )

        scheduler.restart(providers: [foreground, background])

        try await waitUntil {
            let sleeps = await sleepGate.snapshot()
            return Set(events) == ["foreground:false", "background:false"]
                && events.count == 2
                && self.timeIntervals(sleeps, approximatelyEqualTo: [180])
        }

        await sleepGate.releaseAll()

        try await waitUntil {
            let sleeps = await sleepGate.snapshot()
            return events.filter { $0 == "background:false" }.count >= 2
                && events.contains("foreground:false")
                && self.timeIntervals(sleeps, approximatelyEqualTo: [180, 120])
        }

        scheduler.stop()
        await sleepGate.releaseAll()
    }

    func testPollLoopDoesNotBlockOtherDueProvidersWhenOneRefreshIsStillRunning() async throws {
        let first = makeProvider(id: "first", enabled: true, pollIntervalSec: 60)
        let second = makeProvider(id: "second", enabled: true, pollIntervalSec: 60)
        let refreshGate = BlockingRefreshGate()
        let scheduler = makeScheduler(
            providers: [first, second],
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                await refreshGate.refresh(providerID: providerID, forceRefresh: forceRefresh)
            }
        )

        scheduler.restart(providers: [first, second])

        try await waitUntil {
            await refreshGate.snapshot() == ["first:false", "second:false"]
        }

        scheduler.stop()
        await refreshGate.releaseAll()
    }

    func testActiveProviderUsesConfiguredActivePollFloor() async throws {
        let provider = makeProvider(id: "poll", enabled: true, pollIntervalSec: 60)
        var events: [String] = []
        let sleepRecorder = SleepRecorder()
        let scheduler = makeScheduler(
            providers: [provider],
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                events.append("\(providerID):\(forceRefresh)")
            },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])

        try await waitUntil {
            let sleeps = await sleepRecorder.snapshot()
            return events == ["poll:false"]
                && self.timeIntervals(sleeps, approximatelyEqualTo: [180])
        }
        scheduler.stop()
    }

    func testActiveProviderIntervalCombinesUserCadenceAndPlanActiveTTL() async throws {
        // Doc §9.3: the active interval combines the user cadence with the
        // fetch plan's activeTTL; the plan TTL wins when it is longer.
        var provider = makeProvider(id: "plan-active", enabled: true, pollIntervalSec: 60)
        provider.activeTTLSeconds = 300
        var events: [String] = []
        let sleepRecorder = SleepRecorder()
        let scheduler = makeScheduler(
            providers: [provider],
            activeProviderIDs: ["plan-active"],
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                events.append("\(providerID):\(forceRefresh)")
            },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])

        try await waitUntil {
            let sleeps = await sleepRecorder.snapshot()
            return events == ["plan-active:false"]
                && self.timeIntervals(sleeps, approximatelyEqualTo: [300])
        }
        scheduler.stop()
    }

    func testBackgroundProviderIntervalRespectsPlanBackgroundTTLFloor() async throws {
        // Doc §9.3: backgroundTTL is the minimum spacing between background
        // scheduler refreshes, on top of the scheduler's own background floor.
        var provider = makeProvider(id: "plan-bg", enabled: true, pollIntervalSec: 60)
        provider.backgroundTTLSeconds = 1_800
        var events: [String] = []
        let sleepRecorder = SleepRecorder()
        let scheduler = makeScheduler(
            providers: [provider],
            activeProviderIDs: ["other-visible-provider"],
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                events.append("\(providerID):\(forceRefresh)")
            },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])

        try await waitUntil {
            let sleeps = await sleepRecorder.snapshot()
            return events == ["plan-bg:false"]
                && self.timeIntervals(sleeps, approximatelyEqualTo: [1_800])
        }
        scheduler.stop()
    }

    func testPollLoopDefersDueProvidersBeyondConcurrencyCapWithoutDroppingThem() async throws {
        let providers = [
            makeProvider(id: "first", enabled: true, pollIntervalSec: 60),
            makeProvider(id: "second", enabled: true, pollIntervalSec: 60),
            makeProvider(id: "third", enabled: true, pollIntervalSec: 60)
        ]
        let refreshGate = BlockingRefreshGate()
        let sleepGate = BlockingSleepGate()
        let scheduler = makeScheduler(
            providers: providers,
            config: ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: 180,
                activeProviderPollIntervalSeconds: 0,
                maxConcurrentRefreshes: 1,
                localSessionSignalActiveSleepSeconds: 15,
                localSessionSignalIdleSleepSeconds: 60,
                inFlightProviderSleepSeconds: 3
            ),
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                await refreshGate.refresh(providerID: providerID, forceRefresh: forceRefresh)
            },
            sleepAction: { seconds in
                try await sleepGate.sleep(seconds)
            }
        )

        scheduler.restart(providers: providers)

        // Cap 1: only the first due provider starts, the others are deferred.
        try await waitUntil {
            let sleeps = await sleepGate.snapshot()
            return await refreshGate.snapshot() == ["first:false"] && sleeps.contains(3)
        }
        let sleeps = await sleepGate.snapshot()
        XCTAssertTrue(
            sleeps.contains(3),
            "Deferred due items must idle-sleep instead of hot-spinning"
        )

        // Deferred items are not dropped: they start as slots free up.
        await refreshGate.releaseAll()
        try await waitUntil {
            await sleepGate.releaseAll()
            return await refreshGate.snapshot() == ["first:false", "second:false"]
        }
        await refreshGate.releaseAll()
        try await waitUntil {
            await sleepGate.releaseAll()
            return await refreshGate.snapshot() == ["first:false", "second:false", "third:false"]
        }

        scheduler.stop()
        await refreshGate.releaseAll()
        await sleepGate.releaseAll()
    }

    func testPollLoopKeepsConcurrentRefreshesWithinConfiguredCap() async throws {
        let providers = (1...4).map { makeProvider(id: "provider\($0)", enabled: true, pollIntervalSec: 60) }
        let refreshGate = ConcurrencyTrackingRefreshGate()
        let sleepGate = BlockingSleepGate()
        let scheduler = makeScheduler(
            providers: providers,
            config: ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: 180,
                activeProviderPollIntervalSeconds: 0,
                maxConcurrentRefreshes: 2,
                localSessionSignalActiveSleepSeconds: 15,
                localSessionSignalIdleSleepSeconds: 60,
                inFlightProviderSleepSeconds: 3
            ),
            startupJitterProvider: { 0 },
            refreshAction: { providerID, _ in
                await refreshGate.refresh(providerID: providerID)
            },
            sleepAction: { seconds in
                try await sleepGate.sleep(seconds)
            }
        )

        scheduler.restart(providers: providers)

        try await waitUntil {
            await refreshGate.snapshot().entered == ["provider1", "provider2"]
        }
        let firstPeak = await refreshGate.snapshot().peak
        XCTAssertEqual(firstPeak, 2)

        await refreshGate.releaseAll()
        try await waitUntil {
            await sleepGate.releaseAll()
            return await refreshGate.snapshot().entered.count == 4
        }
        let finalPeak = await refreshGate.snapshot().peak
        XCTAssertEqual(finalPeak, 2, "Concurrent refreshes must never exceed maxConcurrentRefreshes")

        scheduler.stop()
        await refreshGate.releaseAll()
        await sleepGate.releaseAll()
    }

    func testOfflineSchedulerSkipsBackgroundRefreshesButManualRefreshStillFires() async throws {
        let provider = makeProvider(id: "poll", enabled: true, pollIntervalSec: 60)
        let onlineFlag = NetworkOnlineFlag(online: false)
        let recorder = RefreshRecorder()
        let sleepGate = BlockingSleepGate()
        let scheduler = makeScheduler(
            providers: [provider],
            isNetworkOnlineProvider: { onlineFlag.isOnline },
            refreshRecorder: recorder,
            startupJitterProvider: { 0 },
            sleepAction: { seconds in
                try await sleepGate.sleep(seconds)
            }
        )

        scheduler.restart(providers: [provider])

        // Offline: the due background refresh is skipped (idle-sleep, retry later).
        try await waitUntil {
            await sleepGate.snapshot().contains(5)
        }
        let backgroundEvents = await recorder.snapshot()
        XCTAssertTrue(backgroundEvents.isEmpty, "Offline background refreshes must be skipped")

        // Manual refreshes are not gated by the offline seam.
        scheduler.refreshNow(providers: [provider])
        try await waitUntil {
            await recorder.snapshot() == ["poll:true"]
        }

        // Back online: the still-due item is refreshed by the poll loop.
        onlineFlag.isOnline = true
        await sleepGate.releaseAll()
        try await waitUntil {
            await recorder.snapshot().contains("poll:false")
        }

        scheduler.stop()
        await sleepGate.releaseAll()
    }

    func testRateLimitedFailureBacksOffLongerThanOrdinaryFailure() async throws {
        let provider = makeProvider(id: "poll", enabled: true, pollIntervalSec: 60)
        var events: [String] = []
        let sleepRecorder = SleepRecorder()
        let scheduler = makeScheduler(
            providers: [provider],
            failureCounts: ["poll": 1],
            rateLimitedProviderIDs: ["poll"],
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                events.append("\(providerID):\(forceRefresh)")
            },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])

        // Ordinary failure backoff is 120s (see testPollLoopUsesFailureBackoff);
        // a 429 doubles it (doc §9.6).
        try await waitUntil {
            let sleeps = await sleepRecorder.snapshot()
            return events == ["poll:false"] && self.timeIntervals(sleeps, approximatelyEqualTo: [240])
        }
        scheduler.stop()
    }

    func testRateLimitedWithoutFailureCountDoublesBaseInterval() async throws {
        let provider = makeProvider(id: "poll", enabled: true, pollIntervalSec: 60)
        var events: [String] = []
        let sleepRecorder = SleepRecorder()
        let scheduler = makeScheduler(
            providers: [provider],
            rateLimitedProviderIDs: ["poll"],
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                events.append("\(providerID):\(forceRefresh)")
            },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])

        // The cached-snapshot 429 path keeps the failure counter at 0, so the
        // base interval itself is doubled (180s active floor x 2).
        try await waitUntil {
            let sleeps = await sleepRecorder.snapshot()
            return events == ["poll:false"] && self.timeIntervals(sleeps, approximatelyEqualTo: [360])
        }
        scheduler.stop()
    }

    func testLongRunningInFlightRefreshUsesConfiguredSleepInsteadOfOneSecondPolling() async throws {
        let provider = makeProvider(id: "slow", enabled: true, pollIntervalSec: 2)
        let refreshGate = BlockingRefreshGate()
        let sleepGate = BlockingSleepGate()
        let scheduler = makeScheduler(
            providers: [provider],
            config: ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: 180,
                activeProviderPollIntervalSeconds: 0,
                localSessionSignalActiveSleepSeconds: 15,
                localSessionSignalIdleSleepSeconds: 60,
                inFlightProviderSleepSeconds: 7
            ),
            startupJitterProvider: { 0 },
            refreshAction: { providerID, forceRefresh in
                await refreshGate.refresh(providerID: providerID, forceRefresh: forceRefresh)
            },
            sleepAction: { seconds in
                try await sleepGate.sleep(seconds)
            }
        )

        scheduler.restart(providers: [provider])

        try await waitUntil {
            let events = await refreshGate.snapshot()
            let sleeps = await sleepGate.snapshot()
            return events == ["slow:false"]
                && self.timeIntervals(sleeps, approximatelyEqualTo: [2])
        }
        await sleepGate.releaseAll()

        try await waitUntil {
            let sleeps = await sleepGate.snapshot()
            return self.timeIntervals(sleeps, approximatelyEqualTo: [2, 7])
        }

        scheduler.stop()
        await sleepGate.releaseAll()
        await refreshGate.releaseAll()
    }

    func testLocalSessionSignalTriggersRefresh() async throws {
        let provider = makeProvider(
            id: "codex-official",
            enabled: true,
            pollIntervalSec: 60,
            localSessionWatchKind: .codex
        )
        let recorder = RefreshRecorder()
        let sleepRecorder = SleepRecorder()
        let signalSource = FakeLocalSessionSignalSource(codexCompletionAt: Date(timeIntervalSince1970: 100))
        let coordinator = LocalSessionRefreshCoordinator(
            signalSource: signalSource,
            minimumEventRefreshGap: 1
        )
        let scheduler = makeScheduler(
            providers: [provider],
            activeProviderIDs: ["codex-official"],
            refreshRecorder: recorder,
            localSessionRefreshCoordinator: coordinator,
            startupJitterProvider: { 999 },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])

        try await waitUntil {
            await recorder.snapshot() == ["codex-official:false"]
        }
        scheduler.stop()
    }

    func testLocalSessionSignalSkipsInactiveProviderUntilActive() async throws {
        let provider = makeProvider(
            id: "codex-official",
            enabled: true,
            pollIntervalSec: 60,
            localSessionWatchKind: .codex
        )
        let activeProviderIDsBox = ActiveProviderIDsBox()
        let recorder = RefreshRecorder()
        let sleepRecorder = SleepRecorder()
        let signalSource = FakeLocalSessionSignalSource(codexCompletionAt: Date(timeIntervalSince1970: 100))
        let coordinator = LocalSessionRefreshCoordinator(
            signalSource: signalSource,
            minimumEventRefreshGap: 1
        )
        let scheduler = makeScheduler(
            providers: [provider],
            activeProviderIDsProvider: {
                activeProviderIDsBox.ids
            },
            refreshRecorder: recorder,
            localSessionRefreshCoordinator: coordinator,
            startupJitterProvider: { 999 },
            sleepAction: { seconds in
                await sleepRecorder.record(seconds)
                throw CancellationError()
            }
        )

        scheduler.restart(providers: [provider])
        try await Task.sleep(nanoseconds: 100_000_000)

        let inactiveRefreshEvents = await recorder.snapshot()
        XCTAssertEqual(inactiveRefreshEvents, [])

        activeProviderIDsBox.ids = ["codex-official"]
        scheduler.restart(providers: [provider])

        try await waitUntil {
            await recorder.snapshot() == ["codex-official:false"]
        }
        scheduler.stop()
    }

    private func makeScheduler(
        providers: [ProviderRefreshScheduleDescriptor],
        activeProviderIDs: Set<String> = [],
        activeProviderIDsProvider customActiveProviderIDsProvider: ProviderRefreshScheduler.ActiveProviderIDsProvider? = nil,
        failureCounts: [String: Int] = [:],
        rateLimitedProviderIDs: Set<String> = [],
        isNetworkOnlineProvider: ProviderRefreshScheduler.IsNetworkOnlineProvider? = nil,
        refreshRecorder: RefreshRecorder = RefreshRecorder(),
        localSessionRefreshCoordinator: LocalSessionRefreshCoordinator = LocalSessionRefreshCoordinator(
            signalSource: FakeLocalSessionSignalSource()
        ),
        config: ProviderRefreshSchedulerConfig = ProviderRefreshSchedulerConfig(
            backgroundProviderPollIntervalSeconds: 180,
            localSessionSignalActiveSleepSeconds: 15,
            localSessionSignalIdleSleepSeconds: 60
        ),
        startupJitterProvider: @escaping @Sendable () -> TimeInterval = { 999 },
        refreshAction customRefreshAction: ProviderRefreshScheduler.RefreshAction? = nil,
        sleepAction: @escaping ProviderRefreshScheduler.SleepAction = { _ in throw CancellationError() }
    ) -> ProviderRefreshScheduler {
        let currentProviders = providers
        return ProviderRefreshScheduler(
            descriptorProvider: { providerID in
                currentProviders.first { $0.id == providerID }
            },
            providersProvider: {
                currentProviders
            },
            activeProviderIDsProvider: customActiveProviderIDsProvider ?? {
                activeProviderIDs
            },
            failureCountProvider: { providerID in
                failureCounts[providerID, default: 0]
            },
            isRateLimitedProvider: { providerID in
                rateLimitedProviderIDs.contains(providerID)
            },
            isNetworkOnline: isNetworkOnlineProvider ?? { true },
            refreshAction: customRefreshAction ?? { providerID, forceRefresh in
                await refreshRecorder.record(providerID: providerID, forceRefresh: forceRefresh)
            },
            localSessionRefreshCoordinator: localSessionRefreshCoordinator,
            config: config,
            startupJitterProvider: startupJitterProvider,
            sleepAction: sleepAction
        )
    }

    private func makeProvider(
        id: String,
        enabled: Bool,
        pollIntervalSec: Int = 60,
        activeTTLSeconds: TimeInterval? = nil,
        backgroundTTLSeconds: TimeInterval? = nil,
        localSessionWatchKind: LocalSessionWatchKind? = nil
    ) -> ProviderRefreshScheduleDescriptor {
        ProviderRefreshScheduleDescriptor(
            id: id,
            isEnabled: enabled,
            pollIntervalSec: pollIntervalSec,
            activeTTLSeconds: activeTTLSeconds,
            backgroundTTLSeconds: backgroundTTLSeconds,
            localSessionWatchKind: localSessionWatchKind
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
        XCTFail("Timed out waiting for scheduler state")
    }

    private func timeIntervals(
        _ values: [TimeInterval],
        approximatelyEqualTo expected: [TimeInterval],
        accuracy: TimeInterval = 0.5
    ) -> Bool {
        guard values.count == expected.count else { return false }
        return zip(values, expected).allSatisfy { abs($0 - $1) <= accuracy }
    }
}

private actor RefreshRecorder {
    private var events: [String] = []

    func record(providerID: String, forceRefresh: Bool) {
        events.append("\(providerID):\(forceRefresh)")
    }

    func snapshot() -> [String] {
        events
    }
}

@MainActor
private final class ActiveProviderIDsBox {
    var ids = Set<String>()
}

private actor SleepRecorder {
    private var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        values.append(value)
    }

    func snapshot() -> [TimeInterval] {
        values
    }
}

private actor BlockingSleepGate {
    private var values: [TimeInterval] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(_ value: TimeInterval) async throws {
        values.append(value)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func releaseAll() {
        let continuations = continuations
        self.continuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func snapshot() -> [TimeInterval] {
        values
    }
}

private actor BlockingRefreshGate {
    private var events: [String] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func refresh(providerID: String, forceRefresh: Bool) async {
        events.append("\(providerID):\(forceRefresh)")
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func releaseAll() {
        let continuations = continuations
        self.continuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func snapshot() -> [String] {
        events
    }
}

private actor ConcurrencyTrackingRefreshGate {
    struct Snapshot: Equatable {
        let entered: [String]
        let peak: Int
    }

    private var entered: [String] = []
    private var runningCount = 0
    private var peakCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func refresh(providerID: String) async {
        entered.append(providerID)
        runningCount += 1
        peakCount = max(peakCount, runningCount)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        runningCount -= 1
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }

    func snapshot() -> Snapshot {
        Snapshot(entered: entered, peak: peakCount)
    }
}

private final class NetworkOnlineFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isOnlineValue: Bool

    init(online: Bool) {
        isOnlineValue = online
    }

    var isOnline: Bool {
        get { lock.withLock { isOnlineValue } }
        set { lock.withLock { isOnlineValue = newValue } }
    }
}

private final class FakeLocalSessionSignalSource: LocalSessionCompletionSignalSource {
    var codexCompletionAt: Date?
    var claudeCompletionAt: Date?

    init(codexCompletionAt: Date? = nil, claudeCompletionAt: Date? = nil) {
        self.codexCompletionAt = codexCompletionAt
        self.claudeCompletionAt = claudeCompletionAt
    }

    func latestCodexCompletionAt() -> Date? {
        codexCompletionAt
    }

    func latestClaudeCompletionAt() -> Date? {
        claudeCompletionAt
    }
}
