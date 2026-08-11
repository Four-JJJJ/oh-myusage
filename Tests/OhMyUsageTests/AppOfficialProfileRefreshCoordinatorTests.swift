import OhMyUsageDomain
import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

@MainActor
final class AppOfficialProfileRefreshCoordinatorTests: XCTestCase {
    func testRefreshCodexProfileSlotPersistsRefreshedAuthAndCommitsInactiveSnapshot() async {
        let coordinator = AppOfficialProfileRefreshCoordinator()
        let runtime = CodexOfficialProfileRefreshRuntime()
        let profile = makeCodexProfile(slotID: .a)
        let descriptor = ProviderDescriptor.defaultOfficialCodex()
        var persistedAuth: (CodexSlotID, String)?
        var didSync = false
        var committed: (UsageSnapshot, CodexSlotID, Bool)?

        let result = await coordinator.refreshCodexProfileSlot(
            profile: profile,
            descriptor: descriptor,
            runtime: runtime,
            allowSessionWindowStabilization: false,
            fetchSnapshot: { _, _ in
                CodexProfileSnapshotResult(
                    snapshot: UsageSnapshot(
                        source: "codex-official",
                        status: .ok,
                        remaining: 80,
                        used: 20,
                        limit: 100,
                        unit: "%",
                        updatedAt: Date(timeIntervalSince1970: 1),
                        note: "ok",
                        sourceLabel: "Profile"
                    ),
                    refreshedAuthJSON: "{\"access_token\":\"updated\"}"
                )
            },
            persistRefreshedAuthJSON: { persistedAuth = ($0, $1) },
            syncProfiles: { didSync = true },
            transformSnapshot: { snapshot, slotID in
                var copy = snapshot
                copy.rawMeta["codex.slotID"] = slotID.rawValue
                return copy
            },
            commitInactiveSnapshot: { committed = ($0, $1, $2) }
        )

        XCTAssertEqual(result, .success)
        XCTAssertEqual(persistedAuth?.0, .a)
        XCTAssertEqual(persistedAuth?.1, "{\"access_token\":\"updated\"}")
        XCTAssertTrue(didSync)
        XCTAssertEqual(committed?.1, .a)
        XCTAssertEqual(committed?.2, false)
        XCTAssertEqual(committed?.0.rawMeta["codex.slotID"], "A")
    }

    func testRefreshClaudeProfileSlotSkipsUnsupportedProfile() async {
        let coordinator = AppOfficialProfileRefreshCoordinator()
        let runtime = ClaudeOfficialProfileRefreshRuntime()
        let profile = makeClaudeProfile(slotID: .a)
        let descriptor = ProviderDescriptor.defaultOfficialClaude()

        let result = await coordinator.refreshClaudeProfileSlot(
            profile: profile,
            descriptor: descriptor,
            runtime: runtime,
            shouldRefreshProfile: { _ in false },
            fetchSnapshot: { _, _ in
                XCTFail("fetch should not run")
                throw ProviderError.unavailable("unused")
            },
            persistRefreshedCredentialsJSON: { _, _ in
                XCTFail("persist should not run")
            },
            syncProfiles: {
                XCTFail("sync should not run")
            },
            transformSnapshot: { snapshot, _ in snapshot },
            commitInactiveSnapshot: { _, _ in
                XCTFail("commit should not run")
            }
        )

        XCTAssertEqual(result, .skipped)
    }

    func testRefreshClaudeProfileSlotPersistsCredentialsAndCommitsSnapshot() async {
        let coordinator = AppOfficialProfileRefreshCoordinator()
        let runtime = ClaudeOfficialProfileRefreshRuntime()
        let profile = makeClaudeProfile(slotID: .b)
        let descriptor = ProviderDescriptor.defaultOfficialClaude()
        var persisted: (CodexSlotID, String)?
        var didSync = false
        var committed: (UsageSnapshot, CodexSlotID)?

        let result = await coordinator.refreshClaudeProfileSlot(
            profile: profile,
            descriptor: descriptor,
            runtime: runtime,
            shouldRefreshProfile: { _ in true },
            fetchSnapshot: { _, _ in
                ClaudeProfileSnapshotResult(
                    snapshot: UsageSnapshot(
                        source: "claude-official",
                        status: .ok,
                        remaining: 75,
                        used: 25,
                        limit: 100,
                        unit: "%",
                        updatedAt: Date(timeIntervalSince1970: 2),
                        note: "ok",
                        sourceLabel: "Profile"
                    ),
                    refreshedCredentialsJSON: "{\"accessToken\":\"updated\"}"
                )
            },
            persistRefreshedCredentialsJSON: { persisted = ($0, $1) },
            syncProfiles: { didSync = true },
            transformSnapshot: { snapshot, slotID in
                var copy = snapshot
                copy.rawMeta["claude.slotID"] = slotID.rawValue
                return copy
            },
            commitInactiveSnapshot: { committed = ($0, $1) }
        )

        XCTAssertEqual(result, .success)
        XCTAssertEqual(persisted?.0, .b)
        XCTAssertEqual(persisted?.1, "{\"accessToken\":\"updated\"}")
        XCTAssertTrue(didSync)
        XCTAssertEqual(committed?.1, .b)
        XCTAssertEqual(committed?.0.rawMeta["claude.slotID"], "B")
    }

    private func makeCodexProfile(slotID: CodexSlotID) -> CodexAccountProfile {
        CodexAccountProfile(
            slotID: slotID,
            displayName: "Codex \(slotID.rawValue)",
            note: nil,
            authJSON: "{}",
            accountId: "team-\(slotID.rawValue.lowercased())",
            accountEmail: "\(slotID.rawValue.lowercased())@example.com",
            accountSubject: "subject-\(slotID.rawValue.lowercased())",
            tenantKey: "tenant",
            identityKey: "tenant|subject-\(slotID.rawValue.lowercased())",
            credentialFingerprint: "fp-\(slotID.rawValue.lowercased())",
            lastImportedAt: Date(timeIntervalSince1970: 1),
            isCurrentSystemAccount: false
        )
    }

    private func makeClaudeProfile(slotID: CodexSlotID) -> ClaudeAccountProfile {
        ClaudeAccountProfile(
            slotID: slotID,
            displayName: "Claude \(slotID.rawValue)",
            note: nil,
            source: .manualCredentials,
            configDir: nil,
            credentialsJSON: "{}",
            accountId: "account-\(slotID.rawValue.lowercased())",
            accountEmail: "\(slotID.rawValue.lowercased())@example.com",
            credentialFingerprint: "fp-\(slotID.rawValue.lowercased())",
            lastImportedAt: Date(timeIntervalSince1970: 1),
            isCurrentSystemAccount: false
        )
    }
}
