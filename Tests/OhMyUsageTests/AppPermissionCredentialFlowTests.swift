import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

@MainActor
final class AppPermissionCredentialFlowTests: XCTestCase {
    // MARK: - Vault access state resolution

    func testResolvedVaultAccessStateTransitions() {
        // Vault not ready: stays not configured, or latches a denied prepare.
        XCTAssertEqual(
            AppPermissionModel.resolvedVaultAccessState(ready: false, previous: .notConfigured),
            .notConfigured
        )
        XCTAssertEqual(
            AppPermissionModel.resolvedVaultAccessState(ready: false, previous: .ready),
            .notConfigured
        )
        XCTAssertEqual(
            AppPermissionModel.resolvedVaultAccessState(ready: false, previous: .systemAccessRequired),
            .systemAccessRequired
        )

        // Vault ready: plain readiness wins over notConfigured, and a previously
        // denied prepare is cleared once the vault reports ready again.
        XCTAssertEqual(
            AppPermissionModel.resolvedVaultAccessState(ready: true, previous: .notConfigured),
            .ready
        )
        XCTAssertEqual(
            AppPermissionModel.resolvedVaultAccessState(ready: true, previous: .systemAccessRequired),
            .ready
        )

        // OAuth/browser failure states survive readiness refreshes.
        XCTAssertEqual(
            AppPermissionModel.resolvedVaultAccessState(ready: true, previous: .expired),
            .expired
        )
        XCTAssertEqual(
            AppPermissionModel.resolvedVaultAccessState(ready: true, previous: .blocked),
            .blocked
        )
    }

    // MARK: - Fixed status copy set (doc 7.5)

    func testFixedCredentialStatusCopySetIsPinned() {
        let zhExpectations: [AppCredentialAccessDisplayState: String] = [
            .notConfigured: "未配置",
            .ready: "已准备，可后台读取",
            .reloginRequired: "需要重新登录",
            .systemAccessRequired: "系统拒绝访问",
            .browserSessionExpired: "浏览器会话已过期",
            .credentialRefreshFailed: "凭证刷新失败"
        ]
        XCTAssertEqual(zhExpectations.count, 6)
        for (state, expected) in zhExpectations {
            XCTAssertEqual(
                Localizer.text(state.localizationKey, language: .zhHans),
                expected
            )
            XCTAssertFalse(
                Localizer.text(state.localizationKey, language: .en).isEmpty
            )
        }
    }

    func testResolveMapsBrokerStatesIntoDisplayStates() {
        XCTAssertEqual(
            AppCredentialAccessDisplayState.resolve(
                vaultState: .notConfigured,
                secureStorageReady: false,
                hasProviderAuthFailure: false
            ),
            .notConfigured
        )
        XCTAssertEqual(
            AppCredentialAccessDisplayState.resolve(
                vaultState: .systemAccessRequired,
                secureStorageReady: false,
                hasProviderAuthFailure: false
            ),
            .systemAccessRequired
        )
        XCTAssertEqual(
            AppCredentialAccessDisplayState.resolve(
                vaultState: .expired,
                secureStorageReady: true,
                hasProviderAuthFailure: false
            ),
            .browserSessionExpired
        )
        XCTAssertEqual(
            AppCredentialAccessDisplayState.resolve(
                vaultState: .blocked,
                secureStorageReady: true,
                hasProviderAuthFailure: false
            ),
            .credentialRefreshFailed
        )
    }

    func testResolveDerivesReloginRequiredFromProviderAuthFailure() {
        XCTAssertEqual(
            AppCredentialAccessDisplayState.resolve(
                vaultState: .ready,
                secureStorageReady: true,
                hasProviderAuthFailure: true
            ),
            .reloginRequired
        )
        XCTAssertEqual(
            AppCredentialAccessDisplayState.resolve(
                vaultState: .ready,
                secureStorageReady: true,
                hasProviderAuthFailure: false
            ),
            .ready
        )
        // Defensive: a ready vault state without a ready flag is treated as unconfigured.
        XCTAssertEqual(
            AppCredentialAccessDisplayState.resolve(
                vaultState: .ready,
                secureStorageReady: false,
                hasProviderAuthFailure: false
            ),
            .notConfigured
        )
    }

    // MARK: - Interactive prepare updates state exactly once

    func testPrepareSuccessMarksReadyAndNotifiesOnce() async {
        let recorder = PrepareFlowRecorder(prepareSucceeded: true)
        let model = makeBoundModel(recorder: recorder)

        let ok = model.prepareSecureStorageAccess()

        XCTAssertTrue(ok)
        XCTAssertEqual(recorder.prepareCallCount, 1)
        XCTAssertEqual(recorder.presentedUICount, 1)
        XCTAssertGreaterThanOrEqual(recorder.becameReadyCount, 1)
        XCTAssertEqual(recorder.state.credentialAccessState, .ready)
        await waitForBackgroundRefreshToSettle()
        // The follow-up refresh keeps the state stable once ready.
        XCTAssertEqual(recorder.state.credentialAccessState, .ready)
        XCTAssertEqual(recorder.state.secureStorageReady, true)
    }
    func testPrepareFailureLatchesSystemAccessRequiredWithoutBecomingReady() async {
        let recorder = PrepareFlowRecorder(prepareSucceeded: false)
        let model = makeBoundModel(recorder: recorder)

        let ok = model.prepareSecureStorageAccess()

        XCTAssertFalse(ok)
        XCTAssertEqual(recorder.prepareCallCount, 1)
        XCTAssertEqual(recorder.becameReadyCount, 0)
        XCTAssertEqual(recorder.state.credentialAccessState, .systemAccessRequired)
        await waitForBackgroundRefreshToSettle()
        // A background (non-interactive) refresh must not clear the latch nor
        // trigger the interactive preparation or UI again.
        XCTAssertEqual(recorder.state.credentialAccessState, .systemAccessRequired)
        XCTAssertEqual(recorder.prepareCallCount, 1)
        XCTAssertEqual(recorder.presentedUICount, 1)
        XCTAssertEqual(recorder.becameReadyCount, 0)
    }

    func testRefreshTransitionToReadyFiresBecameReadyOnce() async {
        let recorder = PrepareFlowRecorder(prepareSucceeded: false)
        let model = makeBoundModel(recorder: recorder)

        recorder.secureStoreReady = true
        model.refreshPermissionStatusesNow()
        await waitForBackgroundRefreshToSettle()

        XCTAssertEqual(recorder.state.secureStorageReady, true)
        XCTAssertEqual(recorder.state.credentialAccessState, .ready)
        XCTAssertEqual(recorder.becameReadyCount, 1)
        XCTAssertEqual(recorder.prepareCallCount, 0)
    }

    // MARK: - Provider vault-credential requirements (doc 7.5 rule)

    func testProviderRequiresVaultCredentialsCoversKeychainBackedSlotsOnly() {
        let localFileOnly = makeDescriptor(auth: AuthConfig(kind: .localCodex))
        XCTAssertFalse(AppConfigurationModel.providerRequiresVaultCredentials(localFileOnly))

        let bearer = makeDescriptor(auth: AuthConfig(
            kind: .bearer,
            keychainService: KeychainService.defaultServiceName,
            keychainAccount: "relay.example.com/sk-token"
        ))
        XCTAssertTrue(AppConfigurationModel.providerRequiresVaultCredentials(bearer))

        let manualCookie = makeDescriptor(
            auth: .none,
            officialConfig: OfficialProviderConfig(manualCookieAccount: "manual-cookie-account")
        )
        XCTAssertTrue(AppConfigurationModel.providerRequiresVaultCredentials(manualCookie))

        let relayBalance = makeDescriptor(
            auth: .none,
            relayConfig: RelayProviderConfig(
                baseURL: "https://relay.example.com",
                balanceAuth: AuthConfig(
                    kind: .bearer,
                    keychainService: KeychainService.defaultServiceName,
                    keychainAccount: "relay.example.com/user-id"
                )
            )
        )
        XCTAssertTrue(AppConfigurationModel.providerRequiresVaultCredentials(relayBalance))
    }

    func testCredentialTargetsCollectDistinctVaultSlots() {
        let providers = [
            makeDescriptor(
                id: "p1",
                auth: AuthConfig(
                    kind: .bearer,
                    keychainService: KeychainService.defaultServiceName,
                    keychainAccount: "shared-account"
                ),
                officialConfig: OfficialProviderConfig(manualCookieAccount: "cookie-account")
            ),
            makeDescriptor(
                id: "p2",
                auth: AuthConfig(
                    kind: .bearer,
                    keychainService: KeychainService.defaultServiceName,
                    keychainAccount: "shared-account"
                )
            ),
            makeDescriptor(id: "p3", auth: AuthConfig(kind: .localCodex))
        ]

        let targets = AppConfigurationModel.credentialTargets(in: providers)

        XCTAssertEqual(targets.count, 2)
        XCTAssertTrue(targets.contains { $0.service == KeychainService.defaultServiceName && $0.account == "shared-account" })
        XCTAssertTrue(targets.contains { $0.service == KeychainService.defaultServiceName && $0.account == "cookie-account" })
    }

    // MARK: - Helpers

    private func makeBoundModel(recorder: PrepareFlowRecorder) -> AppPermissionModel {
        let model = AppPermissionModel()
        model.bind(
            getState: { recorder.state },
            setState: { recorder.state = $0 },
            requestPermissionIfNeeded: {},
            fetchNotificationAuthorizationStatus: { .notDetermined },
            checkSecureStorageReady: { recorder.secureStoreReady },
            onSecureStorageBecameReady: { recorder.recordBecameReady() },
            prepareSecureStoreAccess: { recorder.recordPrepare() },
            presentSecureStorageAccessUI: { recorder.recordPresentedUI() }
        )
        return model
    }

    /// Lets the detached permission-refresh task finish so its state writes are
    /// observable without reaching into private tasks.
    private func waitForBackgroundRefreshToSettle() async {
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            if Task.isCancelled { break }
        }
    }

    private func makeDescriptor(
        id: String = "provider",
        auth: AuthConfig,
        officialConfig: OfficialProviderConfig? = nil,
        relayConfig: RelayProviderConfig? = nil
    ) -> ProviderDescriptor {
        ProviderDescriptor(
            id: id,
            name: id,
            type: .relay,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 3, notifyOnAuthError: true),
            auth: auth,
            officialConfig: officialConfig,
            relayConfig: relayConfig
        )
    }
}

/// Lock-protected recorder for the permission model bind seams. Only call
/// counts and permission state are retained — never credential values.
/// Deliberately not MainActor-isolated: the bind closures are nonisolated.
private final class PrepareFlowRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let prepareSucceeded: Bool
    private var secureStoreReadyValue = false
    private var stateValue = PermissionStore()
    private var prepareCallCountValue = 0
    private var presentedUICountValue = 0
    private var becameReadyCountValue = 0

    init(prepareSucceeded: Bool) {
        self.prepareSucceeded = prepareSucceeded
    }

    var state: PermissionStore {
        get { lock.withLock { stateValue } }
        set { lock.withLock { stateValue = newValue } }
    }

    var secureStoreReady: Bool {
        get { lock.withLock { secureStoreReadyValue } }
        set { lock.withLock { secureStoreReadyValue = newValue } }
    }

    var prepareCallCount: Int {
        lock.withLock { prepareCallCountValue }
    }

    var presentedUICount: Int {
        lock.withLock { presentedUICountValue }
    }

    var becameReadyCount: Int {
        lock.withLock { becameReadyCountValue }
    }

    /// Mirrors KeychainService: a successful interactive prepare marks the store
    /// prepared for subsequent metadata-only readiness checks.
    func recordPrepare() -> Bool {
        lock.withLock {
            prepareCallCountValue += 1
            if prepareSucceeded {
                secureStoreReadyValue = true
            }
            return prepareSucceeded
        }
    }

    func recordPresentedUI() {
        lock.withLock { presentedUICountValue += 1 }
    }

    func recordBecameReady() {
        lock.withLock { becameReadyCountValue += 1 }
    }
}
