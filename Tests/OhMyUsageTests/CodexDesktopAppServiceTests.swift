import AppKit
import XCTest
@testable import OhMyUsage

@MainActor
final class CodexDesktopAppServiceTests: XCTestCase {
    func testIsRunningReturnsTrueWhenMatchingAppExists() {
        let service = makeService(isRunning: .constant(true))
        XCTAssertTrue(service.isRunning())
    }

    func testIsRunningReturnsFalseWhenNoMatchingAppExists() {
        let service = makeService(isRunning: .constant(false))
        XCTAssertFalse(service.isRunning())
    }

    func testRestartIfRunningUsesGracefulTerminationBeforeForceQuit() async {
        let state = RunningState(true)
        var gracefulCalls = 0
        var forceCalls = 0
        var openCalls = 0

        let service = makeService(
            isRunning: state,
            gracefulTerminator: { _ in
                gracefulCalls += 1
                state.setRunning(false)
                return true
            },
            forceTerminator: { _ in
                forceCalls += 1
                return true
            },
            openApplication: { _, _ in
                openCalls += 1
                return NSRunningApplication.current
            }
        )

        let result = await service.restartIfRunning()

        XCTAssertEqual(result, .relaunched)
        XCTAssertEqual(gracefulCalls, 1)
        XCTAssertEqual(forceCalls, 0)
        XCTAssertEqual(openCalls, 1)
    }

    func testRestartIfRunningFallsBackToForceQuitAfterGracefulTimeout() async {
        let state = RunningState(true)
        var gracefulCalls = 0
        var forceCalls = 0

        let service = makeService(
            isRunning: state,
            gracefulTerminator: { _ in
                gracefulCalls += 1
                return true
            },
            forceTerminator: { _ in
                forceCalls += 1
                state.setRunning(false)
                return true
            },
            openApplication: { _, _ in NSRunningApplication.current }
        )

        let result = await service.restartIfRunning()

        XCTAssertEqual(result, .relaunched)
        XCTAssertEqual(gracefulCalls, 1)
        XCTAssertEqual(forceCalls, 1)
    }

    func testRestartIfRunningReturnsShutdownTimedOutWhenForceQuitCannotStopApp() async {
        let state = RunningState(true)
        var openCalls = 0

        let service = makeService(
            isRunning: state,
            gracefulTerminator: { _ in true },
            forceTerminator: { _ in true },
            openApplication: { _, _ in
                openCalls += 1
                return NSRunningApplication.current
            }
        )

        let result = await service.restartIfRunning()

        XCTAssertEqual(result, .shutdownTimedOut)
        XCTAssertEqual(openCalls, 0)
    }

    func testRestartIfRunningReturnsNotRunningWhenAppIsClosed() async {
        let service = makeService(isRunning: .constant(false))
        let result = await service.restartIfRunning()
        XCTAssertEqual(result, .notRunning)
    }

    func testRestartIfRunningReturnsRelaunchFailedAfterThreeLaunchAttempts() async {
        let state = RunningState(true)
        var openCalls = 0

        let service = makeService(
            isRunning: state,
            gracefulTerminator: { _ in
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    state.setRunning(false)
                }
                return true
            },
            forceTerminator: { _ in true },
            openApplication: { _, _ in
                openCalls += 1
                throw LaunchFailure()
            }
        )

        let result = await service.restartIfRunning()

        XCTAssertEqual(result, .relaunchFailed)
        XCTAssertEqual(openCalls, 3)
    }

    private func makeService(
        isRunning: RunningState,
        gracefulTerminator: @escaping (NSRunningApplication) -> Bool = { _ in true },
        forceTerminator: @escaping (NSRunningApplication) -> Bool = { _ in true },
        openApplication: @escaping (URL, NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication = { _, _ in
            NSRunningApplication.current
        }
    ) -> CodexDesktopAppService {
        CodexDesktopAppService(
            runningAppsProvider: {
                isRunning.currentValue ? [NSRunningApplication.current] : []
            },
            bundleURLResolver: {
                URL(fileURLWithPath: "/Applications/Codex.app")
            },
            appMatcher: { _ in true },
            gracefulTerminator: gracefulTerminator,
            forceTerminator: forceTerminator,
            openApplication: openApplication,
            gracefulShutdownTimeout: 0.08,
            forcedShutdownTimeout: 0.08,
            shutdownPollInterval: 0.01,
            relaunchStabilizationDelay: 0.01,
            relaunchRetryDelay: 0.01,
            relaunchAttempts: 3
        )
    }
}

private final class RunningState {
    private let lock = NSLock()
    private var running: Bool

    init(_ running: Bool) {
        self.running = running
    }

    static func constant(_ running: Bool) -> RunningState {
        RunningState(running)
    }

    var currentValue: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func setRunning(_ value: Bool) {
        lock.lock()
        running = value
        lock.unlock()
    }
}

private struct LaunchFailure: Error {
}
