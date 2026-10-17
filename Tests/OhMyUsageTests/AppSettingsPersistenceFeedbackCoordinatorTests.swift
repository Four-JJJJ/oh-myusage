import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppSettingsPersistenceFeedbackCoordinatorTests: XCTestCase {
    func testSavedStatusAutoClearsToIdle() async {
        let clock = ManualFeedbackClock()
        defer { clock.resumeAll() }
        let coordinator = makeCoordinator(clock: clock)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        var errorMessage: String?
        let scheduled = expectSleep(on: clock)
        let cleared = expectation(description: "Saved feedback clears")

        coordinator.setStatus(
            kind: .saved,
            statusText: "Saved",
            tone: .positive,
            update: { next, detail in
                state = next
                errorMessage = detail
                if next.kind == .idle { cleared.fulfill() }
            }
        )

        XCTAssertEqual(state.kind, .saved)

        await fulfillment(of: [scheduled], timeout: 5)
        clock.advance(by: 10)
        await fulfillment(of: [cleared], timeout: 5)
        XCTAssertEqual(state.kind, .idle)
        XCTAssertNil(errorMessage)
    }

    func testDuplicateSavedKeepsOriginalDeadline() async {
        let clock = ManualFeedbackClock()
        defer { clock.resumeAll() }
        let coordinator = makeCoordinator(clock: clock)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        let scheduled = expectSleep(on: clock)
        let cleared = expectation(description: "Duplicate saved feedback keeps its deadline")
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, _ in
            state = next
            if next.kind == .idle { cleared.fulfill() }
        }

        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        await fulfillment(of: [scheduled], timeout: 5)
        clock.advance(by: 4)
        coordinator.setStatus(kind: .saved, statusText: "Saved again", tone: .positive, update: update)
        XCTAssertEqual(state.kind, .saved)

        clock.advance(by: 5)
        coordinator.reconcileIfNeeded(update: update)
        XCTAssertEqual(state.kind, .saved)
        XCTAssertEqual(coordinator.resolvedDisplayState(stored: state).kind, .saved)

        // The original deadline is 10, not 14 after the duplicate save.
        clock.advance(by: 1)
        await fulfillment(of: [cleared], timeout: 5)
        XCTAssertEqual(state.kind, .idle)
    }

    func testDuplicateSavedAfterDeadlineClearsWithoutWaitingForTask() {
        let clock = ManualFeedbackClock()
        let coordinator = makeCoordinator(clock: clock)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, _ in
            state = next
        }

        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        clock.advance(by: 10)
        coordinator.setStatus(kind: .saved, statusText: "Saved again", tone: .positive, update: update)

        XCTAssertEqual(state.kind, .idle)
    }

    func testTaskStartingAfterDeadlineClearsWithoutSleeping() async {
        let clock = ManualFeedbackClock()
        defer { clock.resumeAll() }
        let coordinator = makeCoordinator(clock: clock)
        let cleared = expectation(description: "Delayed auto-clear task catches up")
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)

        coordinator.setStatus(
            kind: .saved,
            statusText: "Saved",
            tone: .positive,
            update: { next, _ in
                state = next
                if next.kind == .idle { cleared.fulfill() }
            }
        )
        clock.advance(by: 10)
        XCTAssertEqual(state.kind, .saved)

        await fulfillment(of: [cleared], timeout: 5)
        XCTAssertEqual(state.kind, .idle)
    }

    func testReconcileAppliesIdleWhenDeadlinePassesWithoutTaskRunning() {
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 0)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        var errorMessage: String? = "stale"
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, detail in
            state = next
            errorMessage = detail
        }

        coordinator.setStatus(
            kind: .saved,
            statusText: "Saved",
            tone: .positive,
            detail: "stale",
            update: update
        )
        // Zero-delay clears synchronously inside setStatus.
        XCTAssertEqual(state.kind, .idle)
        XCTAssertNil(errorMessage)
        XCTAssertEqual(
            coordinator.resolvedDisplayState(
                stored: .init(kind: .saved, statusText: "Saved", tone: .positive)
            ).kind,
            .idle
        )
        XCTAssertNil(
            coordinator.resolvedErrorMessage(stored: "stale", storedKind: .saved)
        )
    }

    func testReconcileClearsStarvedClearTask() {
        let clock = ManualFeedbackClock()
        let coordinator = makeCoordinator(clock: clock)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, _ in
            state = next
        }

        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        XCTAssertEqual(state.kind, .saved)

        // Do not yield to the clear Task; reconciliation must enforce the deadline itself.
        clock.advance(by: 10)

        XCTAssertEqual(state.kind, .saved)
        coordinator.reconcileIfNeeded(update: update)
        XCTAssertEqual(state.kind, .idle)
        XCTAssertEqual(
            coordinator.resolvedDisplayState(
                stored: .init(kind: .saved, statusText: "Saved", tone: .positive)
            ).kind,
            .idle
        )
    }

    func testNewNonIdleStatusCancelsPendingClearTask() {
        let clock = ManualFeedbackClock()
        let coordinator = makeCoordinator(clock: clock)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        var errorMessage: String?
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, detail in
            state = next
            errorMessage = detail
        }

        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        coordinator.setStatus(
            kind: .failed,
            statusText: "Save Failed",
            tone: .negative,
            detail: "boom",
            update: update
        )

        XCTAssertEqual(state.kind, .failed)
        XCTAssertEqual(errorMessage, "boom")
    }

    func testNewNonIdleStatusCancelsPendingClearTaskAfterDelay() async {
        let clock = ManualFeedbackClock()
        defer { clock.resumeAll() }
        let coordinator = makeCoordinator(clock: clock)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        var errorMessage: String?
        let savedScheduled = expectSleep(on: clock)
        let cleared = expectation(description: "Replacement feedback clears at its own deadline")
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, detail in
            state = next
            errorMessage = detail
            if next.kind == .idle { cleared.fulfill() }
        }

        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        await fulfillment(of: [savedScheduled], timeout: 5)
        clock.advance(by: 4)
        let failedScheduled = expectSleep(on: clock)
        coordinator.setStatus(
            kind: .failed,
            statusText: "Save Failed",
            tone: .negative,
            detail: "boom",
            update: update
        )

        XCTAssertEqual(state.kind, .failed)
        XCTAssertEqual(errorMessage, "boom")

        await fulfillment(of: [failedScheduled], timeout: 5)
        // Deliver the cancelled saved timer and verify it cannot clear the newer failure.
        let savedResumed = expectation(description: "Cancelled saved timer resumes")
        clock.onResume = { savedResumed.fulfill() }
        clock.advance(by: 6)
        await fulfillment(of: [savedResumed], timeout: 5)
        clock.onResume = nil
        coordinator.reconcileIfNeeded(update: update)
        XCTAssertEqual(state.kind, .failed)
        XCTAssertEqual(errorMessage, "boom")

        clock.advance(by: 4)
        await fulfillment(of: [cleared], timeout: 5)
        XCTAssertEqual(state.kind, .idle)
        XCTAssertNil(errorMessage)
    }

    func testSavedAfterAutoClearStartsFreshDeadline() async {
        let clock = ManualFeedbackClock()
        defer { clock.resumeAll() }
        let coordinator = makeCoordinator(clock: clock)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        let firstScheduled = expectSleep(on: clock)
        let firstCleared = expectation(description: "First saved feedback clears")
        let secondCleared = expectation(description: "Second saved feedback clears")
        var clearCount = 0
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, _ in
            state = next
            if next.kind == .idle {
                clearCount += 1
                if clearCount == 1 { firstCleared.fulfill() }
                if clearCount == 2 { secondCleared.fulfill() }
            }
        }

        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        await fulfillment(of: [firstScheduled], timeout: 5)
        clock.advance(by: 10)
        await fulfillment(of: [firstCleared], timeout: 5)
        XCTAssertEqual(state.kind, .idle)

        let secondScheduled = expectSleep(on: clock)
        coordinator.setStatus(kind: .saved, statusText: "Saved again", tone: .positive, update: update)
        XCTAssertEqual(state.kind, .saved)
        XCTAssertEqual(
            coordinator.resolvedDisplayState(stored: state).kind,
            .saved
        )

        await fulfillment(of: [secondScheduled], timeout: 5)
        clock.advance(by: 9)
        coordinator.reconcileIfNeeded(update: update)
        XCTAssertEqual(state.kind, .saved)
        clock.advance(by: 1)
        await fulfillment(of: [secondCleared], timeout: 5)
        XCTAssertEqual(state.kind, .idle)
        XCTAssertEqual(clearCount, 2)
    }

    func testResolvedStateStaysSavedBeforeDeadline() {
        let clock = ManualFeedbackClock()
        let coordinator = makeCoordinator(clock: clock)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        coordinator.setStatus(
            kind: .saved,
            statusText: "Saved",
            tone: .positive,
            update: { next, _ in state = next }
        )

        let resolved = coordinator.resolvedDisplayState(stored: state)
        XCTAssertEqual(resolved.kind, .saved)
        XCTAssertEqual(
            coordinator.resolvedErrorMessage(stored: "detail", storedKind: .saved),
            "detail"
        )
    }

    func testResolvedStateAndErrorClearAtDeadlineWithoutTaskRunning() {
        let clock = ManualFeedbackClock()
        let coordinator = makeCoordinator(clock: clock)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        coordinator.setStatus(
            kind: .failed,
            statusText: "Save Failed",
            tone: .negative,
            detail: "boom",
            update: { next, _ in state = next }
        )

        clock.advance(by: 10)

        XCTAssertEqual(state.kind, .failed)
        XCTAssertEqual(coordinator.resolvedDisplayState(stored: state).kind, .idle)
        XCTAssertNil(coordinator.resolvedErrorMessage(stored: "boom", storedKind: .failed))
    }

    func testDefaultClockAutoClearsSavedFeedback() async {
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 0.01)
        let cleared = expectation(description: "Default clock and sleeper clear feedback")
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        coordinator.setStatus(
            kind: .saved,
            statusText: "Saved",
            tone: .positive,
            update: { next, _ in
                state = next
                if next.kind == .idle { cleared.fulfill() }
            }
        )

        await fulfillment(of: [cleared], timeout: 5)
        XCTAssertEqual(state.kind, .idle)
    }

    private func makeCoordinator(clock: ManualFeedbackClock) -> AppSettingsPersistenceFeedbackCoordinator {
        AppSettingsPersistenceFeedbackCoordinator(
            clearDelaySeconds: 10,
            now: { clock.now },
            sleepUntil: { await clock.sleep(until: $0) }
        )
    }

    private func expectSleep(on clock: ManualFeedbackClock) -> XCTestExpectation {
        let scheduled = expectation(description: "Auto-clear task starts waiting")
        scheduled.assertForOverFulfill = true
        clock.onSleep = { scheduled.fulfill() }
        return scheduled
    }
}

@MainActor
private final class ManualFeedbackClock {
    private(set) var now = Date(timeIntervalSince1970: 1_000)
    var onSleep: (() -> Void)?
    var onResume: (() -> Void)?
    private var sleepers: [(deadline: Date, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep(until deadline: Date) async {
        guard deadline > now else { return }
        await withCheckedContinuation { continuation in
            sleepers.append((deadline, continuation))
            onSleep?()
        }
        onResume?()
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        let ready = sleepers.filter { $0.deadline <= now }
        sleepers.removeAll { $0.deadline <= now }
        for sleeper in ready {
            sleeper.continuation.resume()
        }
    }

    func resumeAll() {
        let pending = sleepers
        sleepers.removeAll()
        for sleeper in pending {
            sleeper.continuation.resume()
        }
    }
}
