import OhMyUsageDomain
import AppKit
import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppViewModelCodexSwitchTests: XCTestCase {
    func testSwitchCodexProfileKeepsAutoApplyWhenDesktopRelaunches() async throws {
        let fixture = try makeFixture(restartResult: .relaunched)
        let viewModel = fixture.viewModel

        _ = viewModel.saveCodexProfile(
            slotID: .b,
            displayName: "Codex B",
            note: "工作",
            authJSON: Self.sampleAuthJSON(accountID: "acc-b", email: "b@example.com")
        )

        await viewModel.switchCodexProfile(slotID: .b)

        XCTAssertEqual(fixture.restartCounter.value, 1)
        XCTAssertEqual(viewModel.codexSwitchFeedback[.b]?.message, viewModel.text(.codexSwitchSuccess))
        XCTAssertEqual(viewModel.codexSlots.first?.slotID, .b)
        XCTAssertTrue(viewModel.codexSlots.first?.isActive == true)
        XCTAssertEqual(viewModel.snapshots["codex-official"]?.rawMeta["codex.slotID"], "B")
    }

    func testSwitchCodexProfileMarksDesktopRestartIncompleteWhenShutdownTimesOut() async throws {
        try await assertSwitchPersistsAndWarnsForManualRelaunch(restartResult: .shutdownTimedOut)
    }

    func testSwitchCodexProfileMarksDesktopRestartIncompleteWhenRelaunchFails() async throws {
        try await assertSwitchPersistsAndWarnsForManualRelaunch(restartResult: .relaunchFailed)
    }

    func testSwitchCodexProfileStoresRefreshedSystemAuthAfterVerifiedFetch() async throws {
        let refreshedAuthJSON = Self.sampleAuthJSON(
            accountID: "acc-b",
            email: "b@example.com",
            accessToken: "access-token-refreshed",
            refreshToken: "refresh-token-refreshed"
        )
        let fixture = try makeFixture(
            restartResult: .relaunched,
            providerFactory: { root in
                MutatingStubProviderFactory(
                    snapshot: Self.makeSnapshot(accountID: "acc-b", email: "b@example.com"),
                    onFetch: {
                        try refreshedAuthJSON.write(
                            to: root.appendingPathComponent("auth.json"),
                            atomically: true,
                            encoding: .utf8
                        )
                    }
                )
            }
        )
        let viewModel = fixture.viewModel
        let originalAuthJSON = Self.sampleAuthJSON(
            accountID: "acc-b",
            email: "b@example.com",
            accessToken: "access-token-original",
            refreshToken: "refresh-token-original"
        )

        _ = viewModel.saveCodexProfile(
            slotID: .b,
            displayName: "Codex B",
            note: nil,
            authJSON: originalAuthJSON
        )

        await viewModel.switchCodexProfile(slotID: .b)

        let stored = try XCTUnwrap(fixture.profileStore.profile(slotID: .b))
        XCTAssertTrue(stored.authJSON.contains("access-token-refreshed"))
        XCTAssertTrue(stored.authJSON.contains("refresh-token-refreshed"))
    }

    func testSwitchCodexProfileRefreshesTargetAuthBeforeApplyingToDesktop() async throws {
        var usageRequestCount = 0
        CodexSwitchMockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url == "https://chatgpt.com/backend-api/wham/usage" {
                usageRequestCount += 1
                if usageRequestCount == 1 {
                    return (
                        HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                        Data()
                    )
                }
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token-refreshed")
                let body: [String: Any] = [
                    "plan_type": "team",
                    "rate_limit": [
                        "primary_window": ["used_percent": 1, "reset_at": 1_760_000_000],
                        "secondary_window": ["used_percent": 0, "reset_at": 1_760_500_000]
                    ]
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: body)
                )
            }
            if url == "https://auth.openai.com/oauth/token" {
                let body: [String: Any] = [
                    "access_token": "access-token-refreshed",
                    "refresh_token": "refresh-token-refreshed",
                    "id_token": Self.makeIDToken(email: "b@example.com")
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: body)
                )
            }
            throw URLError(.badURL)
        }
        defer { CodexSwitchMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexSwitchMockURLProtocol.self]
        let keychainWrites = LockedStringLog()
        let fixture = try makeFixture(
            restartResult: .relaunched,
            codexProfileSnapshotService: CodexProfileSnapshotService(
                session: URLSession(configuration: configuration)
            ),
            keychainWrites: keychainWrites
        )
        let viewModel = fixture.viewModel

        _ = viewModel.saveCodexProfile(
            slotID: .b,
            displayName: "Codex B",
            note: nil,
            authJSON: Self.sampleAuthJSON(
                accountID: "acc-b",
                email: "b@example.com",
                accessToken: "access-token-stale",
                refreshToken: "refresh-token-stale"
            )
        )

        await viewModel.switchCodexProfile(slotID: .b)

        let writes = keychainWrites.values
        XCTAssertEqual(usageRequestCount, 2)
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(writes[0].contains("access-token-refreshed"))
        XCTAssertFalse(writes[0].contains("access-token-stale"))
        let stored = try XCTUnwrap(fixture.profileStore.profile(slotID: .b))
        XCTAssertTrue(stored.authJSON.contains("refresh-token-refreshed"))
    }

    func testSwitchCodexProfileStillAppliesDesktopAuthWhenPreflightRefreshFails() async throws {
        CodexSwitchMockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url == "https://chatgpt.com/backend-api/wham/usage"
                || url == "https://auth.openai.com/oauth/token" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
            throw URLError(.badURL)
        }
        defer { CodexSwitchMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexSwitchMockURLProtocol.self]
        let keychainWrites = LockedStringLog()
        let fixture = try makeFixture(
            restartResult: .relaunched,
            codexProfileSnapshotService: CodexProfileSnapshotService(
                session: URLSession(configuration: configuration)
            ),
            keychainWrites: keychainWrites
        )
        let viewModel = fixture.viewModel

        _ = viewModel.saveCodexProfile(
            slotID: .b,
            displayName: "Codex B",
            note: nil,
            authJSON: Self.sampleAuthJSON(
                accountID: "acc-b",
                email: "b@example.com",
                accessToken: "access-token-original",
                refreshToken: "refresh-token-original"
            )
        )

        await viewModel.switchCodexProfile(slotID: .b)

        XCTAssertEqual(fixture.restartCounter.value, 1)
        let writes = keychainWrites.values
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(writes.first?.contains("access-token-original") == true)
        XCTAssertEqual(viewModel.codexSwitchFeedback[.b]?.message, viewModel.text(.codexSwitchSuccess))
    }

    private func assertSwitchPersistsAndWarnsForManualRelaunch(
        restartResult: CodexDesktopAppRestartResult
    ) async throws {
        let fixture = try makeFixture(restartResult: restartResult)
        let viewModel = fixture.viewModel

        _ = viewModel.saveCodexProfile(
            slotID: .a,
            displayName: "Codex A",
            note: nil,
            authJSON: Self.sampleAuthJSON(accountID: "acc-a", email: "a@example.com")
        )

        await viewModel.switchCodexProfile(slotID: .a)

        XCTAssertEqual(fixture.restartCounter.value, 1)
        XCTAssertEqual(
            viewModel.codexSwitchFeedback[.a]?.message,
            viewModel.text(.codexSwitchDesktopRestartIncomplete)
        )
        XCTAssertEqual(viewModel.codexSlots.first?.slotID, .a)
        XCTAssertTrue(viewModel.codexSlots.first?.isActive == true)
        XCTAssertEqual(viewModel.snapshots["codex-official"]?.rawMeta["codex.slotID"], "A")
    }

    private func makeFixture(
        restartResult: CodexDesktopAppRestartResult,
        providerFactory: ((URL) -> ProviderFactorying)? = nil,
        codexProfileSnapshotService: CodexProfileSnapshotService? = nil,
        keychainWrites: LockedStringLog? = nil
    ) throws -> (
        viewModel: AppViewModel,
        restartCounter: LockedCounter,
        root: URL,
        profileStore: CodexAccountProfileStore
    ) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("app-view-model-codex-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let profileStore = CodexAccountProfileStore(
            fileURL: root.appendingPathComponent("codex_profiles.json")
        )
        let slotStore = CodexAccountSlotStore(
            fileURL: root.appendingPathComponent("codex_slots.json")
        )
        let authService = CodexDesktopAuthService(
            homeDirectory: { root.path },
            environment: { ["CODEX_HOME": root.path] },
            keychainReader: { nil },
            keychainWriter: {
                keychainWrites?.append($0)
                return true
            }
        )
        let restartCounter = LockedCounter()
        let runningState = LockedRunningState(true)
        let appService = makeAppService(
            result: restartResult,
            runningState: runningState,
            restartCounter: restartCounter
        )
        let resolvedProfileSnapshotService = codexProfileSnapshotService ?? Self.makePassthroughProfileSnapshotService()
        let resolvedProviderFactory = providerFactory?(root) ?? StubProviderFactory(
            snapshot: Self.makeSnapshot(accountID: "team-a", email: "test@example.com")
        )

        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true

        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [codex]),
            appUpdateService: NoopCodexSwitchAppUpdateService(),
            codexSlotStore: slotStore,
            codexProfileStore: profileStore,
            codexDesktopAuthService: authService,
            codexDesktopAppService: appService,
            codexProfileSnapshotService: resolvedProfileSnapshotService,
            providerFactory: resolvedProviderFactory
        )
        return (viewModel, restartCounter, root, profileStore)
    }

    private static func makePassthroughProfileSnapshotService() -> CodexProfileSnapshotService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexSwitchPassthroughURLProtocol.self]
        return CodexProfileSnapshotService(session: URLSession(configuration: configuration))
    }

    private func makeAppService(
        result: CodexDesktopAppRestartResult,
        runningState: LockedRunningState,
        restartCounter: LockedCounter
    ) -> CodexDesktopAppService {
        CodexDesktopAppService(
            runningAppsProvider: {
                runningState.currentValue ? [NSRunningApplication.current] : []
            },
            bundleURLResolver: {
                URL(fileURLWithPath: "/Applications/Codex.app")
            },
            appMatcher: { _ in true },
            gracefulTerminator: { _ in
                restartCounter.increment()
                switch result {
                case .relaunched, .relaunchFailed:
                    Task {
                        try? await Task.sleep(nanoseconds: 15_000_000)
                        runningState.setRunning(false)
                    }
                case .shutdownTimedOut, .notRunning:
                    break
                }
                return true
            },
            forceTerminator: { _ in
                if result == .relaunched {
                    Task {
                        try? await Task.sleep(nanoseconds: 10_000_000)
                        runningState.setRunning(false)
                    }
                }
                return true
            },
            openApplication: { _, _ in
                if result == .relaunchFailed {
                    throw CodexSwitchLaunchFailure()
                }
                return NSRunningApplication.current
            },
            gracefulShutdownTimeout: 0.05,
            forcedShutdownTimeout: 0.05,
            shutdownPollInterval: 0.01,
            relaunchStabilizationDelay: 0.01,
            relaunchRetryDelay: 0.01,
            relaunchAttempts: 3
        )
    }

    private static func makeSnapshot(accountID: String, email: String) -> UsageSnapshot {
        UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: 70,
            used: 30,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Official",
            accountLabel: email,
            rawMeta: [
                "codex.accountId": accountID,
                "codex.teamId": accountID,
                "codex.accountKey": "tenant::\(email)",
                "codex.identityKey": "tenant::\(email)",
                "codex.accountLabel": email
            ]
        )
    }

    private static func sampleAuthJSON(
        accountID: String,
        email: String,
        accessToken: String? = nil,
        refreshToken: String? = nil
    ) -> String {
        let idToken = makeIDToken(email: email)
        let resolvedAccessToken = accessToken ?? "access-token-\(accountID)"
        let resolvedRefreshToken = refreshToken ?? "refresh-token-\(accountID)"
        return #"""
        {
          "tokens": {
            "access_token": "\#(resolvedAccessToken)",
            "refresh_token": "\#(resolvedRefreshToken)",
            "account_id": "\#(accountID)",
            "id_token": "\#(idToken)"
          }
        }
        """#
    }

    private static func makeIDToken(email: String) -> String {
        let payload = Data(#"{"email":"\#(email)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }
}

private struct StubProviderFactory: ProviderFactorying {
    let snapshot: UsageSnapshot

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        StubUsageProvider(descriptor: descriptor, snapshot: snapshot)
    }
}

private struct StubUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot

    func fetch() async throws -> UsageSnapshot {
        snapshot
    }
}

private struct MutatingStubProviderFactory: ProviderFactorying {
    let snapshot: UsageSnapshot
    let onFetch: @Sendable () throws -> Void

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        MutatingStubUsageProvider(
            descriptor: descriptor,
            snapshot: snapshot,
            onFetch: onFetch
        )
    }
}

private struct MutatingStubUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot
    let onFetch: @Sendable () throws -> Void

    func fetch() async throws -> UsageSnapshot {
        try onFetch()
        return snapshot
    }
}

private actor NoopCodexSwitchAppUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw ProviderError.unavailable("unused")
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw ProviderError.unavailable("unused")
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {
    }
}

private final class LockedRunningState {
    private let lock = NSLock()
    private var isRunning: Bool

    init(_ isRunning: Bool) {
        self.isRunning = isRunning
    }

    var currentValue: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    func setRunning(_ value: Bool) {
        lock.lock()
        isRunning = value
        lock.unlock()
    }
}

private final class LockedCounter {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class LockedStringLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private struct CodexSwitchLaunchFailure: Error {
}

private final class CodexSwitchMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = CodexSwitchMockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class CodexSwitchPassthroughURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body: [String: Any] = [
            "plan_type": "team",
            "rate_limit": [
                "primary_window": ["used_percent": 1, "reset_at": 1_760_000_000],
                "secondary_window": ["used_percent": 0, "reset_at": 1_760_500_000]
            ]
        ]
        do {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
