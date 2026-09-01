import Foundation
import XCTest
@testable import OhMyUsage

final class CodexDesktopAuthServiceTests: XCTestCase {
    func testApplyProfileWritesAuthFileAndKeychain() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let authPath = directory.appendingPathComponent("auth.json").path
        var savedKeychain: String?

        let service = CodexDesktopAuthService(
            homeDirectory: { directory.path },
            environment: { ["CODEX_HOME": directory.path] },
            keychainReader: { nil },
            keychainWriter: { value in
                savedKeychain = value
                return true
            }
        )
        let profile = try CodexAccountProfileStore.makeProfile(
            slotID: .a,
            displayName: "Account A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-a", email: "a@example.com")
        )

        try service.applyProfile(profile)

        let written = try String(contentsOfFile: authPath, encoding: .utf8)
        XCTAssertEqual(written.trimmingCharacters(in: .whitespacesAndNewlines), profile.authJSON)
        XCTAssertEqual(savedKeychain, profile.authJSON)
    }

    func testApplyProfileWritesNormalizedOAuthJSONIntoVault() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let vault = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)
        let service = CodexDesktopAuthService(
            homeDirectory: { directory.path },
            environment: { ["CODEX_HOME": directory.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true },
            oauthVault: vault
        )
        let profile = try CodexAccountProfileStore.makeProfile(
            slotID: .a,
            displayName: "Account A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-vault", email: "vault@example.com")
        )

        try service.applyProfile(profile)

        XCTAssertEqual(vault.readOAuthJSON(provider: .codex), profile.authJSON.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertTrue(vault.isMigrationComplete(provider: .codex))
    }

    func testApplyProfileThrowsWhenVaultWriteFails() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: FailingTokenCredentialStore(), defaults: defaults)
        let service = CodexDesktopAuthService(
            homeDirectory: { directory.path },
            environment: { ["CODEX_HOME": directory.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true },
            oauthVault: vault
        )
        let profile = try CodexAccountProfileStore.makeProfile(
            slotID: .a,
            displayName: "Account A",
            note: nil,
            authJSON: sampleAuthJSON(accountID: "acc-fail", email: "fail@example.com")
        )

        XCTAssertThrowsError(try service.applyProfile(profile)) { error in
            guard case CodexDesktopAuthError.vaultWriteFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testCurrentAuthJSONPrefersVaultOverLocalFilesAndSkipsExternalKeychain() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)", isDirectory: true)
        let authDirectory = directory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)
        try sampleAuthJSON(accountID: "acc-file", email: "file@example.com")
            .write(to: authDirectory.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        XCTAssertTrue(
            vault.saveOAuthJSON(provider: .codex, rawJSON: sampleAuthJSON(accountID: "acc-vault", email: "vault@example.com"))
        )
        var externalKeychainReads = 0
        let service = CodexDesktopAuthService(
            homeDirectory: { directory.path },
            environment: { ["CODEX_HOME": authDirectory.path] },
            keychainReader: {
                externalKeychainReads += 1
                return self.sampleAuthJSON(accountID: "acc-external", email: "external@example.com")
            },
            keychainWriter: { _ in true },
            oauthVault: vault
        )

        // App vault wins over the local file...
        XCTAssertEqual(
            service.currentAuthJSON(),
            vault.readOAuthJSON(provider: .codex)
        )
        // ...and the external `Codex Auth` keychain item is never read by polling paths.
        XCTAssertEqual(externalKeychainReads, 0)
    }

    func testCurrentAuthJSONReturnsNilWhenVaultAndFilesAreMissing() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)", isDirectory: true)
        var externalKeychainReads = 0
        let service = CodexDesktopAuthService(
            homeDirectory: { directory.path },
            environment: { [:] },
            keychainReader: {
                externalKeychainReads += 1
                return self.sampleAuthJSON(accountID: "acc-external", email: "external@example.com")
            },
            keychainWriter: { _ in true }
        )

        XCTAssertNil(service.currentAuthJSON())
        XCTAssertEqual(externalKeychainReads, 0)
    }

    func testCurrentAuthJSONForAuthRecoveryFallsBackToExternalKeychain() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-auth-tests-\(UUID().uuidString)", isDirectory: true)
        let externalJSON = sampleAuthJSON(accountID: "acc-external", email: "external@example.com")
        let service = CodexDesktopAuthService(
            homeDirectory: { directory.path },
            environment: { [:] },
            keychainReader: { externalJSON },
            keychainWriter: { _ in true }
        )

        XCTAssertNil(service.currentAuthJSON())
        XCTAssertEqual(service.currentAuthJSONForAuthRecovery(), externalJSON)
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
