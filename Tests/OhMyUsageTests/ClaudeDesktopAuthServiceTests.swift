import Foundation
import XCTest
@testable import OhMyUsage

final class ClaudeDesktopAuthServiceTests: XCTestCase {
    func testApplyCredentialsWritesCredentialFileAndKeychain() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent("profiles/main", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        var savedKeychain: String?

        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: { nil },
            keychainWriter: { value in
                savedKeychain = value
                return true
            }
        )
        let credentialsJSON = sampleCredentialsJSON(accessToken: "access-a", refreshToken: "refresh-a")

        try service.applyCredentialsJSON(credentialsJSON)

        let credentialPath = configDir.appendingPathComponent(".credentials.json").path
        let written = try String(contentsOfFile: credentialPath, encoding: .utf8)
        XCTAssertEqual(written.trimmingCharacters(in: .whitespacesAndNewlines), credentialsJSON)
        XCTAssertEqual(savedKeychain, credentialsJSON)

        let attributes = try FileManager.default.attributesOfItem(atPath: credentialPath)
        let posix = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(posix, 0o600)
    }

    func testApplyCredentialsWritesNormalizedOAuthJSONIntoVault() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true },
            oauthVault: vault
        )
        let credentialsJSON = sampleCredentialsJSON(accessToken: "vault-access", refreshToken: "vault-refresh")

        try service.applyCredentialsJSON(credentialsJSON)

        XCTAssertEqual(
            vault.readOAuthJSON(provider: .claude),
            credentialsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertTrue(vault.isMigrationComplete(provider: .claude))
    }

    func testApplyCredentialsThrowsWhenVaultWriteFails() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: FailingTokenCredentialStore(), defaults: defaults)
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true },
            oauthVault: vault
        )

        XCTAssertThrowsError(
            try service.applyCredentialsJSON(
                sampleCredentialsJSON(accessToken: "access-vault-fail", refreshToken: "refresh-vault-fail")
            )
        ) { error in
            guard case ClaudeDesktopAuthError.vaultWriteFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testCurrentCredentialsPrefersVaultOverLocalFilesAndSkipsExternalKeychain() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let fileJSON = sampleCredentialsJSON(accessToken: "file-access", refreshToken: "file-refresh")
        try fileJSON.write(
            to: configDir.appendingPathComponent(".credentials.json"),
            atomically: true,
            encoding: .utf8
        )
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        let vaultJSON = sampleCredentialsJSON(accessToken: "vault-access", refreshToken: "vault-refresh")
        XCTAssertTrue(vault.saveOAuthJSON(provider: .claude, rawJSON: vaultJSON))
        var externalKeychainReads = 0
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: {
                externalKeychainReads += 1
                return self.sampleCredentialsJSON(accessToken: "external-access", refreshToken: "external-refresh")
            },
            keychainWriter: { _ in true },
            oauthVault: vault
        )

        // App vault wins over the local file...
        XCTAssertEqual(service.currentCredentialsJSON(), vaultJSON.trimmingCharacters(in: .whitespacesAndNewlines))
        // ...and the external `Claude Code-credentials` keychain item is never read by polling paths.
        XCTAssertEqual(externalKeychainReads, 0)
    }

    func testCurrentCredentialsDoesNotReadExternalKeychainWhenVaultAndFilesMissing() {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        var externalKeychainReads = 0
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { [:] },
            keychainReader: {
                externalKeychainReads += 1
                return self.sampleCredentialsJSON(accessToken: "external-access", refreshToken: "external-refresh")
            },
            keychainWriter: { _ in true }
        )

        XCTAssertNil(service.currentCredentialsJSON())
        XCTAssertEqual(externalKeychainReads, 0)
    }

    func testCurrentCredentialsForAuthRecoveryFallsBackToExternalKeychain() {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        let externalJSON = sampleCredentialsJSON(accessToken: "keychain-access", refreshToken: "keychain-refresh")
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { [:] },
            keychainReader: { externalJSON },
            keychainWriter: { _ in true }
        )

        XCTAssertNil(service.currentCredentialsJSON())
        XCTAssertEqual(service.currentCredentialsJSONForAuthRecovery(), externalJSON)
    }

    func testApplyCredentialsRejectsInvalidJSON() {
        let service = ClaudeDesktopAuthService(
            homeDirectory: { NSHomeDirectory() },
            environment: { [:] },
            keychainReader: { nil },
            keychainWriter: { _ in true }
        )

        XCTAssertThrowsError(try service.applyCredentialsJSON(#"{"accessToken":""}"#)) { error in
            guard case ClaudeDesktopAuthError.invalidCredentials = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testApplyCredentialsFailsWhenKeychainWriteFails() {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-auth-home-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent(".claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: { nil },
            keychainWriter: { _ in false }
        )

        XCTAssertThrowsError(
            try service.applyCredentialsJSON(
                sampleCredentialsJSON(accessToken: "access-fail", refreshToken: "refresh-fail")
            )
        ) { error in
            guard case ClaudeDesktopAuthError.keychainWriteFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    private func sampleCredentialsJSON(accessToken: String, refreshToken: String) -> String {
        let root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "refreshToken": refreshToken,
                "expiresAt": 4_102_444_800_000 as Double,
                "subscriptionType": "pro",
                "scopes": ["user:profile"]
            ],
            "accountId": "acc-1",
            "email": "claude@example.com"
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
