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
        let background = makeProvider(id: "background", enabled: true, pollIntervalSec: 300)
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

    func testLongRunningInFlightRefreshUsesConfiguredSleepInsteadOfOneSecondPolling() async throws {
        let provider = makeProvider(id: "slow", enabled: true, pollIntervalSec: 2)
        let refreshGate = BlockingRefreshGate()
        let sleepGate = BlockingSleepGate()
        let scheduler = makeScheduler(
            providers: [provider],
            config: ProviderRefreshSchedulerConfig(
                backgroundProviderPollIntervalSeconds: 180,
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
        localSessionWatchKind: LocalSessionWatchKind? = nil
    ) -> ProviderRefreshScheduleDescriptor {
        ProviderRefreshScheduleDescriptor(
            id: id,
            isEnabled: enabled,
            pollIntervalSec: pollIntervalSec,
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
