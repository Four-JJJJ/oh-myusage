import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppViewModelUpdateFlowTests: XCTestCase {
    func testDownloadSuccessTransitionsToBufferingThenAttemptsInstall() async {
        let service = StubAppUpdateService()
        let releaseNotesStore = StubPostUpdateReleaseNotesStore()
        await service.enqueueFetch(.success(makeUpdate(version: "2.2.3")))
        await service.enqueuePrepare(.success(makePrepared(version: "2.2.3")))
        await service.enqueueInstall(.failure(StubUpdateError.installFailed))

        let viewModel = AppViewModel(
            testingCurrentAppVersion: "1.0.0",
            appUpdateService: service,
            postUpdateReleaseNotesStore: releaseNotesStore,
            updateInstallBufferDelaySeconds: 0.12
        )

        viewModel.checkForAppUpdate(force: true)
        await assertEventually("should detect update availability") {
            viewModel.availableUpdate?.latestVersion == "2.2.3"
        }

        viewModel.openLatestReleaseDownload()
        await assertEventually("should enter install buffering after preparation") {
            if case .installBuffering = viewModel.settingsUpdateDisplayState.kind {
                return viewModel.updateInstallBufferingInFlight
            }
            return false
        }

        await assertEventually("should attempt install after buffering delay") {
            await service.installCallCount() == 1
        }
        XCTAssertEqual(releaseNotesStore.scheduledVersions, ["2.2.3"])
        await assertEventually("failed install should expose retry state") {
            if case .failed = viewModel.menuUpdateDisplayState.kind {
                return viewModel.updateInstallErrorMessage != nil
            }
            return false
        }
    }

    func testBufferingCancelsWhenVersionChangesDuringDelay() async {
        let service = StubAppUpdateService()
        await service.enqueueFetch(.success(makeUpdate(version: "2.2.3")))
        await service.enqueueFetch(.success(makeUpdate(version: "3.0.0")))
        await service.enqueuePrepare(.success(makePrepared(version: "2.2.3")))

        let viewModel = AppViewModel(
            testingCurrentAppVersion: "1.0.0",
            appUpdateService: service,
            updateInstallBufferDelaySeconds: 0.20
        )

        viewModel.checkForAppUpdate(force: true)
        await assertEventually("should load first available update") {
            viewModel.availableUpdate?.latestVersion == "2.2.3"
        }

        viewModel.openLatestReleaseDownload()
        await assertEventually("should enter buffering for first update") {
            viewModel.updateInstallBufferingInFlight
        }

        viewModel.checkForAppUpdate(force: true)
        await assertEventually("should switch to newer update and clear prepared state") {
            viewModel.availableUpdate?.latestVersion == "3.0.0"
                && !viewModel.updateInstallBufferingInFlight
                && viewModel.updatePreparedVersion == nil
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        let installCalls = await service.installCallCount()
        XCTAssertEqual(installCalls, 0)
    }

    func testRetryAfterFailureReentersUpdateFlow() async {
        let service = StubAppUpdateService()
        await service.enqueueFetch(.success(makeUpdate(version: "2.2.3")))
        await service.enqueuePrepare(.failure(StubUpdateError.prepareFailed))
        await service.enqueuePrepare(.success(makePrepared(version: "2.2.3")))
        await service.enqueueInstall(.failure(StubUpdateError.installFailed))

        let viewModel = AppViewModel(
            testingCurrentAppVersion: "1.0.0",
            appUpdateService: service,
            updateInstallBufferDelaySeconds: 0.10
        )

        viewModel.checkForAppUpdate(force: true)
        await assertEventually("should load update before starting install flow") {
            viewModel.availableUpdate?.latestVersion == "2.2.3"
        }

        viewModel.openLatestReleaseDownload()
        await assertEventually("first preparation failure should expose failed state") {
            if case .failed = viewModel.settingsUpdateDisplayState.kind {
                return viewModel.updateInstallErrorMessage != nil
            }
            return false
        }

        viewModel.openLatestReleaseDownload()
        await assertEventually("retry should run preparation again") {
            await service.prepareCallCount() == 2
        }
        await assertEventually("retry flow should continue to install attempt") {
            await service.installCallCount() == 1
        }
    }

    func testMenuActionDoesNotFallbackToUpdateCheckWithoutAvailableUpdate() async {
        let service = StubAppUpdateService()
        let viewModel = AppViewModel(
            testingCurrentAppVersion: "1.0.0",
            appUpdateService: service,
            updateInstallBufferDelaySeconds: 0.10
        )

        viewModel.performMenuUpdateAction()
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertFalse(viewModel.updateCheckInFlight)
        let fetchCalls = await service.fetchCallCount()
        XCTAssertEqual(fetchCalls, 0)
    }

    func testUpdateActionTitleReflectsDownloadAndInstallStates() {
        let coordinator = AppUpdateCoordinator(
            appUpdateService: StubAppUpdateService(),
            postUpdateReleaseNotesStore: StubPostUpdateReleaseNotesStore(),
            updateInstallBufferDelaySeconds: 2,
            updateCheckStatusClearDelaySeconds: 10
        )
        let localizedText: (String, String) -> String = { zhHans, _ in zhHans }

        var state = UpdateStore()
        state.availableUpdate = makeUpdate(version: "2.2.3")
        XCTAssertEqual(
            coordinator.updateActionTitle(for: state, localizedText: localizedText),
            "更新版本"
        )

        state.updateDownloadInFlight = true
        XCTAssertEqual(
            coordinator.updateActionTitle(for: state, localizedText: localizedText),
            "正在下载..."
        )

        state.updateDownloadInFlight = false
        state.updateInstallBufferingInFlight = true
        XCTAssertEqual(
            coordinator.updateActionTitle(for: state, localizedText: localizedText),
            "即将安装重启..."
        )
    }

    func testCheckForUpdateShowsUpToDateWhenNoNewVersion() async {
        let service = StubAppUpdateService()
        await service.enqueueFetch(.success(makeUpdate(version: "1.0.0")))

        let viewModel = AppViewModel(
            testingCurrentAppVersion: "1.0.0",
            appUpdateService: service,
            updateInstallBufferDelaySeconds: 0.10,
            updateCheckStatusClearDelaySeconds: 0.08
        )

        viewModel.checkForAppUpdate(force: true)
        await assertEventually("no new release should show up-to-date status") {
            if case .upToDate = viewModel.settingsUpdateDisplayState.kind {
                return viewModel.settingsUpdateDisplayState.statusText == viewModel.localizedText("已经是最新版本", "Up to Date")
            }
            return false
        }
        await assertEventually("up-to-date status should auto-clear") {
            if case .idle = viewModel.settingsUpdateDisplayState.kind {
                return true
            }
            return false
        }
    }

    func testCheckForUpdateFailureShowsCheckFailedStatus() async {
        let service = StubAppUpdateService()
        await service.enqueueFetch(.failure(StubUpdateError.fetchFailed))

        let viewModel = AppViewModel(
            testingCurrentAppVersion: "1.0.0",
            appUpdateService: service,
            updateInstallBufferDelaySeconds: 0.10,
            updateCheckStatusClearDelaySeconds: 0.08
        )

        viewModel.checkForAppUpdate(force: true)
        await assertEventually("failed release check should show check-failed status") {
            if case .checkFailed = viewModel.settingsUpdateDisplayState.kind {
                return viewModel.settingsUpdateDisplayState.statusText == viewModel.localizedText("检查失败", "Check Failed")
            }
            return false
        }
        await assertEventually("check-failed status should auto-clear") {
            if case .idle = viewModel.settingsUpdateDisplayState.kind {
                return true
            }
            return false
        }
    }

    private func makeUpdate(version: String) -> AppUpdateInfo {
        AppUpdateInfo(
            latestVersion: version,
            releaseURL: URL(string: "https://example.com/releases/\(version)")!,
            notesURL: nil,
            publishedAt: nil,
            zipAsset: AppUpdateAsset(url: URL(string: "https://example.com/downloads/\(version).zip")!, sha256: nil, size: nil),
            dmgAsset: nil
        )
    }

    private func makePrepared(version: String) -> PreparedAppUpdate {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("app-view-model-update-tests-\(UUID().uuidString)", isDirectory: true)
        let appURL = root.appendingPathComponent("OhMyUsage.app", isDirectory: true)
        return PreparedAppUpdate(version: version, appBundleURL: appURL, workingDirectoryURL: root)
    }

    private func assertEventually(
        _ message: String,
        timeout: TimeInterval = 1.5,
        pollInterval: TimeInterval = 0.01,
        condition: @escaping @MainActor () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        let finalResult = await condition()
        XCTAssertTrue(finalResult, message)
    }
}

private final class StubPostUpdateReleaseNotesStore: PostUpdateReleaseNotesStoring {
    private let lock = NSLock()
    private var storedScheduledVersions: [String] = []

    var scheduledVersions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedScheduledVersions
    }

    func schedulePresentation(for update: AppUpdateInfo) {
        lock.lock()
        storedScheduledVersions.append(update.latestVersion)
        lock.unlock()
    }

    func consumePresentationIfNeeded(currentVersion: String) -> PendingPostUpdateReleaseNotes? {
        nil
    }

    func reset() {}
}

private actor StubAppUpdateService: AppUpdateServicing {
    private var fetchResults: [Result<AppUpdateInfo, Error>] = []
    private var prepareResults: [Result<PreparedAppUpdate, Error>] = []
    private var installResults: [Result<Void, Error>] = []
    private var fetchCalls = 0
    private var prepareCalls = 0
    private var installCalls = 0

    func enqueueFetch(_ result: Result<AppUpdateInfo, Error>) {
        fetchResults.append(result)
    }

    func enqueuePrepare(_ result: Result<PreparedAppUpdate, Error>) {
        prepareResults.append(result)
    }

    func enqueueInstall(_ result: Result<Void, Error>) {
        installResults.append(result)
    }

    func fetchCallCount() -> Int {
        fetchCalls
    }

    func prepareCallCount() -> Int {
        prepareCalls
    }

    func installCallCount() -> Int {
        installCalls
    }

    func fetchLatestRelease() async throws -> AppUpdateInfo {
        fetchCalls += 1
        guard !fetchResults.isEmpty else {
            throw StubUpdateError.unconfiguredFetch
        }
        return try fetchResults.removeFirst().get()
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        prepareCalls += 1
        guard !prepareResults.isEmpty else {
            throw StubUpdateError.unconfiguredPrepare
        }
        return try prepareResults.removeFirst().get()
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {
        installCalls += 1
        guard !installResults.isEmpty else { return }
        try installResults.removeFirst().get()
    }
}

private enum StubUpdateError: LocalizedError {
    case fetchFailed
    case unconfiguredFetch
    case unconfiguredPrepare
    case prepareFailed
    case installFailed

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Fetch failed"
        case .unconfiguredFetch:
            return "Fetch result was not configured"
        case .unconfiguredPrepare:
            return "Prepare result was not configured"
        case .prepareFailed:
            return "Prepare failed"
        case .installFailed:
            return "Install failed"
        }
    }
}
