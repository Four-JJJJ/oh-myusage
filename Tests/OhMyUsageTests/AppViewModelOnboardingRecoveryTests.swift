import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

@MainActor
final class AppViewModelOnboardingRecoveryTests: XCTestCase {
    func testBootstrapReEnablesCodexWhenPersistedSlotStateExists() throws {
        let root = try makeTemporaryDirectory()
        let slotStore = CodexAccountSlotStore(
            fileURL: root.appendingPathComponent("codex_slots.json")
        )
        _ = slotStore.upsertActive(
            snapshot: sampleCodexSnapshot(accountID: "team-slot", email: "slot@example.com"),
            now: Date()
        )

        let viewModel = makeViewModel(root: root, codexSlotStore: slotStore)

        XCTAssertTrue(isOfficialProviderEnabled(type: .codex, in: viewModel))
        XCTAssertFalse(viewModel.shouldShowPermissionGuide)
    }

    func testBootstrapReEnablesCodexWhenPersistedProfileExists() throws {
        let root = try makeTemporaryDirectory()
        let profileStore = CodexAccountProfileStore(
            fileURL: root.appendingPathComponent("codex_profiles.json")
        )
        _ = try profileStore.saveProfile(
            slotID: .a,
            displayName: "Codex A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-profile", email: "profile@example.com"),
            currentFingerprint: nil
        )

        let viewModel = makeViewModel(root: root, codexProfileStore: profileStore)

        XCTAssertTrue(isOfficialProviderEnabled(type: .codex, in: viewModel))
        XCTAssertFalse(viewModel.shouldShowPermissionGuide)
    }

    func testSavingCodexProfileEnablesCodexMenuBarDisplay() throws {
        let root = try makeTemporaryDirectory()
        let viewModel = makeViewModel(root: root)

        _ = viewModel.saveCodexProfile(
            slotID: .a,
            displayName: "Codex A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-profile", email: "profile@example.com")
        )

        XCTAssertTrue(isOfficialProviderEnabled(type: .codex, in: viewModel))
        XCTAssertTrue(
            viewModel.config.providers.contains {
                $0.id == "codex-official" && $0.enabled && $0.showsInMenuBar
            }
        )
    }

    func testPermissionGuideHidesWhenAllPermissionRequirementsAreSatisfied() {
        XCTAssertFalse(
            AppPermissionCoordinator.shouldShowPermissionGuide(
                hasEnabledProviders: false,
                hasPersistedOfficialMonitoringState: false,
                hasNotificationPermission: true,
                secureStorageReady: true,
                fullDiskAccessRelevant: true,
                fullDiskAccessRequested: false,
                fullDiskAccessGranted: true
            )
        )
    }

    func testPermissionGuideShowsWhenRequiredFullDiskAccessIsMissing() {
        XCTAssertTrue(
            AppPermissionCoordinator.shouldShowPermissionGuide(
                hasEnabledProviders: false,
                hasPersistedOfficialMonitoringState: false,
                hasNotificationPermission: true,
                secureStorageReady: true,
                fullDiskAccessRelevant: true,
                fullDiskAccessRequested: false,
                fullDiskAccessGranted: false
            )
        )
    }

    func testPermissionGuideShowsWhenNotificationPermissionIsMissing() {
        XCTAssertTrue(
            AppPermissionCoordinator.shouldShowPermissionGuide(
                hasEnabledProviders: false,
                hasPersistedOfficialMonitoringState: false,
                hasNotificationPermission: false,
                secureStorageReady: true,
                fullDiskAccessRelevant: false,
                fullDiskAccessRequested: false,
                fullDiskAccessGranted: false
            )
        )
    }

    private func makeViewModel(
        root: URL,
        codexSlotStore: CodexAccountSlotStore? = nil,
        codexProfileStore: CodexAccountProfileStore? = nil
    ) -> AppViewModel {
        AppViewModel(
            testingConfig: .default,
            appUpdateService: NoopOnboardingRecoveryAppUpdateService(),
            codexSlotStore: codexSlotStore ?? CodexAccountSlotStore(
                fileURL: root.appendingPathComponent("codex_slots.json")
            ),
            codexProfileStore: codexProfileStore ?? CodexAccountProfileStore(
                fileURL: root.appendingPathComponent("codex_profiles.json")
            ),
            codexDesktopAuthService: CodexDesktopAuthService(
                homeDirectory: { root.path },
                environment: { ["CODEX_HOME": root.path] },
                keychainReader: { nil },
                keychainWriter: { _ in true }
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("app-view-model-onboarding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func isOfficialProviderEnabled(type: ProviderType, in viewModel: AppViewModel) -> Bool {
        viewModel.config.providers.first(where: { $0.type == type && $0.family == .official })?.enabled == true
    }

    private func sampleCodexSnapshot(accountID: String, email: String) -> UsageSnapshot {
        UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: 75,
            used: 25,
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

    private func sampleAuthJSON(accountID: String, email: String) -> String {
        let payload = Data(#"{"email":"\#(email)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return #"""
        {
          "tokens": {
            "access_token": "access-token-\#(accountID)",
            "refresh_token": "refresh-token-\#(accountID)",
            "account_id": "\#(accountID)",
            "id_token": "header.\#(payload).signature"
          }
        }
        """#
    }
}

private actor NoopOnboardingRecoveryAppUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw ProviderError.unavailable("unused")
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw ProviderError.unavailable("unused")
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {
    }
}
