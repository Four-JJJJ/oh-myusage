import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class AppOfficialProfileSyncCoordinatorTests: XCTestCase {
    func testSyncCodexProfilesCapturesCurrentAuthAndReturnsVisibleSlotIDs() throws {
        let root = try makeTemporaryDirectory()
        let profileStore = CodexAccountProfileStore(
            fileURL: root.appendingPathComponent("codex_profiles.json")
        )
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        XCTAssertTrue(
            vault.saveOAuthJSON(
                provider: .codex,
                rawJSON: Self.sampleCodexAuthJSON(accountID: "acc-a", email: "a@example.com")
            )
        )
        var externalKeychainReads = 0
        let authService = CodexDesktopAuthService(
            homeDirectory: { root.path },
            environment: { [:] },
            keychainReader: {
                externalKeychainReads += 1
                return Self.sampleCodexAuthJSON(accountID: "acc-a", email: "a@example.com")
            },
            keychainWriter: { _ in true },
            oauthVault: vault
        )

        let result = AppOfficialProfileSyncCoordinator().syncCodexProfiles(
            profileStore: profileStore,
            desktopAuthService: authService
        )

        XCTAssertEqual(result.profiles.count, 1)
        XCTAssertEqual(result.visibleSlotIDs, [.a])
        XCTAssertEqual(result.profiles.first?.accountEmail, "a@example.com")
        // Ordinary sync reads the app vault, never the external `Codex Auth` keychain.
        XCTAssertEqual(externalKeychainReads, 0)
    }

    func testBootstrapClaudeProfilesIfNeededReturnsCurrentProfilesWhenAlreadyCompacted() {
        let currentProfiles = [
            ClaudeAccountProfile(
                slotID: .a,
                displayName: "Claude A",
                note: nil,
                source: .manualCredentials,
                configDir: nil,
                credentialsJSON: Self.sampleClaudeCredentialsJSON(
                    email: "a@example.com",
                    accessToken: "access-a",
                    scopes: ["user:profile"]
                ),
                accountId: "acc-a",
                accountEmail: "a@example.com",
                credentialFingerprint: "fp-a",
                lastImportedAt: Date(timeIntervalSince1970: 1_700_000_000),
                isCurrentSystemAccount: true
            )
        ]

        let result = AppOfficialProfileSyncCoordinator().bootstrapClaudeProfilesIfNeeded(
            currentProfiles: currentProfiles,
            didRunAutoCaptureCompaction: true,
            profileStore: ClaudeAccountProfileStore(),
            desktopAuthService: ClaudeDesktopAuthService()
        )

        XCTAssertEqual(result.profiles, currentProfiles)
        XCTAssertTrue(result.removedSlotIDs.isEmpty)
        XCTAssertTrue(result.didRunAutoCaptureCompaction)
    }

    func testSyncClaudeProfilesReturnsNormalizedDisplaySelectionAndVisibleSlotIDs() throws {
        let root = try makeTemporaryDirectory()
        let profileStore = ClaudeAccountProfileStore(
            fileURL: root.appendingPathComponent("claude_profiles.json")
        )
        let currentProfiles = [
            ClaudeAccountProfile(
                slotID: .a,
                displayName: "Claude A",
                note: nil,
                source: .manualCredentials,
                configDir: nil,
                credentialsJSON: Self.sampleClaudeCredentialsJSON(
                    email: "proxy@example.com",
                    accessToken: "access-proxy",
                    scopes: ["user:inference"]
                ),
                accountId: "acc-a",
                accountEmail: "proxy@example.com",
                credentialFingerprint: ClaudeAccountProfileStore.credentialFingerprint(for: "access-proxy"),
                lastImportedAt: Date(timeIntervalSince1970: 1_700_000_000),
                isCurrentSystemAccount: true
            )
        ]
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        XCTAssertTrue(
            vault.saveOAuthJSON(
                provider: .claude,
                rawJSON: Self.sampleClaudeCredentialsJSON(
                    email: "visible@example.com",
                    accessToken: "access-visible",
                    scopes: ["user:profile"]
                )
            )
        )
        var externalKeychainReads = 0
        let authService = ClaudeDesktopAuthService(
            homeDirectory: { root.path },
            environment: { [:] },
            keychainReader: {
                externalKeychainReads += 1
                return Self.sampleClaudeCredentialsJSON(
                    email: "visible@example.com",
                    accessToken: "access-visible",
                    scopes: ["user:profile"]
                )
            },
            keychainWriter: { _ in true },
            oauthVault: vault
        )

        let result = AppOfficialProfileSyncCoordinator().syncClaudeProfiles(
            currentProfiles: currentProfiles,
            slots: [],
            configuredDisplaySlotID: .a,
            profileStore: profileStore,
            desktopAuthService: authService
        )

        XCTAssertEqual(result.visibleSlotIDs, [.a])
        XCTAssertEqual(result.syncEvaluation.normalizedConfiguredDisplaySlotID, .a)
        XCTAssertEqual(result.syncEvaluation.resolvedDisplaySlotID, .a)
        XCTAssertTrue(result.syncEvaluation.didProfileIdentityChange)
        // Ordinary sync reads the app vault, never the external `Claude Code-credentials` keychain.
        XCTAssertEqual(externalKeychainReads, 0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("app-official-profile-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sampleCodexAuthJSON(accountID: String, email: String) -> String {
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

    private static func sampleClaudeCredentialsJSON(
        email: String,
        accessToken: String,
        scopes: [String]
    ) -> String {
        let root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "refreshToken": "refresh-\(accessToken)",
                "subscriptionType": "pro",
                "scopes": scopes
            ],
            "accountId": "acc-\(accessToken)",
            "email": email
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
