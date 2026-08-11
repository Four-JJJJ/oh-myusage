import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppSettingsPersistenceFeedbackCoordinatorTests: XCTestCase {
    func testSavedStatusAutoClearsToIdle() async {
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 0.05)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        var errorMessage: String?

        coordinator.setStatus(
            kind: .saved,
            statusText: "Saved",
            tone: .positive,
            update: { next, detail in
                state = next
                errorMessage = detail
            }
        )

        XCTAssertEqual(state.kind, .saved)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if state.kind == .idle && errorMessage == nil {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("expected auto-clear to idle, still \(state.kind)")
    }

    func testDuplicateSavedKeepsOriginalDeadline() async {
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 0.15)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, _ in
            state = next
        }

        let startedAt = Date()
        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        try? await Task.sleep(nanoseconds: 60_000_000)
        coordinator.setStatus(kind: .saved, statusText: "Saved again", tone: .positive, update: update)
        XCTAssertEqual(state.kind, .saved)

        let deadline = startedAt.addingTimeInterval(1.0)
        while Date() < deadline {
            if state.kind == .idle {
                XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.45)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("duplicate saved reset deadline; still \(state.kind)")
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

    func testReconcileClearsStarvedClearTask() async {
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 0.05)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, _ in
            state = next
        }

        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        XCTAssertEqual(state.kind, .saved)

        let busyUntil = Date().addingTimeInterval(0.08)
        while Date() < busyUntil {
            // Busy-wait on MainActor so the clear Task cannot run.
        }

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
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 0.2)
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
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 1.0)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        var errorMessage: String?
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, detail in
            state = next
            errorMessage = detail
        }

        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.setStatus(
            kind: .failed,
            statusText: "Save Failed",
            tone: .negative,
            detail: "boom",
            update: update
        )

        XCTAssertEqual(state.kind, .failed)
        XCTAssertEqual(errorMessage, "boom")

        // Failed feedback also auto-clears after the same delay.
        let cleared = Date().addingTimeInterval(1.5)
        while Date() < cleared {
            if state.kind == .idle && errorMessage == nil {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("expected failed status to auto-clear, still \(state.kind)")
    }

    func testSavedAfterAutoClearStartsFreshDeadline() async {
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 0.05)
        var state = SettingsPersistenceDisplayState(kind: .idle, statusText: nil, tone: .neutral)
        let update: AppSettingsPersistenceFeedbackCoordinator.StateUpdater = { next, _ in
            state = next
        }

        coordinator.setStatus(kind: .saved, statusText: "Saved", tone: .positive, update: update)
        let firstClearDeadline = Date().addingTimeInterval(1)
        while Date() < firstClearDeadline {
            if state.kind == .idle {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(state.kind, .idle)

        coordinator.setStatus(kind: .saved, statusText: "Saved again", tone: .positive, update: update)
        XCTAssertEqual(state.kind, .saved)
        XCTAssertEqual(
            coordinator.resolvedDisplayState(stored: state).kind,
            .saved
        )

        let secondClearDeadline = Date().addingTimeInterval(1)
        while Date() < secondClearDeadline {
            if state.kind == .idle {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("expected second saved status to auto-clear, still \(state.kind)")
    }

    func testResolvedStateStaysSavedBeforeDeadline() {
        let coordinator = AppSettingsPersistenceFeedbackCoordinator(clearDelaySeconds: 5)
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
}
