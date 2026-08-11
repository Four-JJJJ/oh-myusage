import Foundation

@MainActor
final class AppSettingsPersistenceFeedbackCoordinator {
    typealias DisplayState = SettingsPersistenceDisplayState
    typealias DisplayKind = SettingsPersistenceDisplayState.Kind
    typealias DisplayTone = UpdateDisplayTone
    typealias StateUpdater = @MainActor (_ state: DisplayState, _ errorMessage: String?) -> Void

    private static let idleState = DisplayState(
        kind: .idle,
        statusText: nil,
        tone: .neutral
    )

    private let clearDelaySeconds: TimeInterval
    private var clearTask: Task<Void, Never>?
    private var presentedKind: DisplayKind = .idle
    /// Bumped whenever a new auto-clear schedule replaces a prior one so stale Tasks cannot apply idle.
    private var clearGeneration = 0
    /// Wall-clock deadline for auto-clear. Used so UI/tests still resolve to idle when the
    /// clear Task is delayed by MainActor load (e.g. persistAndRestart → polling/prefetch).
    private var clearDeadline: Date?
    /// Remains true after a deadline-based clear until the next non-idle presentation, so
    /// stale stored `.saved` values still resolve as idle.
    private var clearExpired = false

    init(clearDelaySeconds: TimeInterval) {
        self.clearDelaySeconds = max(0, clearDelaySeconds)
    }

    @discardableResult
    func apply(
        _ outcome: AppConfigurationPersistenceOutcome,
        update: @escaping StateUpdater
    ) -> Bool {
        if let feedback = outcome.feedback {
            setStatus(
                kind: feedback.kind,
                statusText: feedback.statusText,
                tone: feedback.tone,
                detail: feedback.detail,
                update: update
            )
        }
        return outcome.success
    }

    func setStatus(
        kind: DisplayKind,
        statusText: String?,
        tone: DisplayTone,
        detail: String? = nil,
        update: @escaping StateUpdater
    ) {
        update(
            DisplayState(
                kind: kind,
                statusText: statusText,
                tone: tone
            ),
            detail
        )

        if kind == .idle {
            cancelClearTask()
            clearDeadline = nil
            clearExpired = false
            presentedKind = .idle
            return
        }

        // Keep the original auto-clear deadline when the same non-idle kind is re-applied
        // (e.g. persistAndRestart follow-up work re-saving). Resetting the timer on every
        // duplicate write can otherwise prevent idle forever under MainActor load.
        if kind == presentedKind, clearDeadline != nil || clearExpired {
            if isDeadlineDue {
                applyIdle(update: update)
            }
            return
        }

        presentedKind = kind
        clearExpired = false
        clearDeadline = Date().addingTimeInterval(clearDelaySeconds)
        cancelClearTask()

        if isDeadlineDue {
            applyIdle(update: update)
            return
        }

        let deadline = clearDeadline
        let generation = clearGeneration
        clearTask = Task { [weak self] in
            if let deadline {
                let remaining = deadline.timeIntervalSinceNow
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.clearGeneration == generation else { return }
                self.applyIdleIfDeadlinePassed(update: update)
            }
        }
    }

    /// Eagerly applies idle when the wall-clock deadline has passed, even if the clear Task
    /// has not yet been scheduled to run on a busy MainActor.
    func reconcileIfNeeded(update: @escaping StateUpdater) {
        applyIdleIfDeadlinePassed(update: update)
    }

    func resolvedDisplayState(stored: DisplayState) -> DisplayState {
        guard shouldPresentAsIdle(storedKind: stored.kind) else {
            return stored
        }
        return Self.idleState
    }

    func resolvedErrorMessage(stored: String?, storedKind: DisplayKind) -> String? {
        guard shouldPresentAsIdle(storedKind: storedKind) else {
            return stored
        }
        return nil
    }

    private var isDeadlineDue: Bool {
        clearExpired || clearDeadline.map { Date() >= $0 } == true
    }

    private func shouldPresentAsIdle(storedKind: DisplayKind) -> Bool {
        storedKind != .idle && isDeadlineDue
    }

    private func applyIdleIfDeadlinePassed(update: StateUpdater) {
        guard presentedKind != .idle, isDeadlineDue else { return }
        applyIdle(update: update)
    }

    private func applyIdle(update: StateUpdater) {
        cancelClearTask()
        clearDeadline = nil
        clearExpired = true
        presentedKind = .idle
        update(Self.idleState, nil)
    }

    private func cancelClearTask() {
        clearTask?.cancel()
        clearTask = nil
        clearGeneration &+= 1
    }
}
