import Foundation
import XCTest
@testable import OhMyUsage

final class OfficialOAuthVaultStoreTests: XCTestCase {
    func testVaultAccountConstantsUseCanonicalNames() {
        XCTAssertEqual(OfficialOAuthVaultAccounts.codexOAuthJSON, "official/codex/oauth-json")
        XCTAssertEqual(OfficialOAuthVaultAccounts.claudeOAuthJSON, "official/claude/oauth-json")
        XCTAssertEqual(
            OfficialOAuthVaultAccounts.account(for: .codex),
            "official/codex/oauth-json"
        )
        XCTAssertEqual(
            OfficialOAuthVaultAccounts.account(for: .claude),
            "official/claude/oauth-json"
        )
    }

    func testSaveOAuthJSONVerifiesAndWritesCodexVaultAccount() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let store = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)
        let rawJSON = Self.sampleCodexAuthJSON(accountID: "acc-a")

        XCTAssertTrue(store.saveOAuthJSON(provider: .codex, rawJSON: rawJSON))
        XCTAssertEqual(store.readOAuthJSON(provider: .codex), rawJSON)
        XCTAssertTrue(store.isMigrationComplete(provider: .codex))
        XCTAssertFalse(store.isMigrationComplete(provider: .claude))
        XCTAssertEqual(keychain.readToken(service: "oh-myusage", account: "official/codex/oauth-json"), rawJSON)
    }

    func testSaveOAuthJSONRejectsInvalidPayloadWithoutWriting() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let store = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)

        XCTAssertFalse(store.saveOAuthJSON(provider: .codex, rawJSON: "not-json"))
        XCTAssertFalse(store.saveOAuthJSON(provider: .codex, rawJSON: #"{"tokens":{}}"#))
        XCTAssertFalse(store.saveOAuthJSON(provider: .claude, rawJSON: #"{"claudeAiOauth":{"accessToken":""}}"#))
        XCTAssertNil(store.readOAuthJSON(provider: .codex))
        XCTAssertNil(store.readOAuthJSON(provider: .claude))
        XCTAssertFalse(store.isMigrationComplete(provider: .codex))
        XCTAssertFalse(store.isMigrationComplete(provider: .claude))
    }

    func testSaveOAuthJSONFailsWhenVaultWriteFails() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let store = OfficialOAuthVaultStore(
            keychain: FailingTokenCredentialStore(),
            defaults: defaults
        )

        XCTAssertFalse(store.saveOAuthJSON(provider: .codex, rawJSON: Self.sampleCodexAuthJSON(accountID: "acc-a")))
        XCTAssertFalse(store.isMigrationComplete(provider: .codex))
    }

    func testMigrateFromExternalKeychainWritesVaultOnce() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let rawJSON = Self.sampleCodexAuthJSON(accountID: "acc-migrate")
        let externalReads = SendableCounter()
        let store = OfficialOAuthVaultStore(
            keychain: keychain,
            defaults: defaults,
            externalKeychainReader: { _ in
                externalReads.increment()
                return rawJSON
            }
        )

        XCTAssertTrue(store.migrateFromExternalKeychainIfNeeded(provider: .codex))
        XCTAssertEqual(store.readOAuthJSON(provider: .codex), rawJSON)
        XCTAssertTrue(store.isMigrationComplete(provider: .codex))
        XCTAssertEqual(externalReads.value, 1)

        // Once the vault holds verified OAuth JSON the external keychain is not read again.
        XCTAssertTrue(store.migrateFromExternalKeychainIfNeeded(provider: .codex))
        XCTAssertEqual(externalReads.value, 1)
    }

    func testMigrateRetriesWhenVaultEntryDisappears() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let rawJSON = Self.sampleClaudeCredentialsJSON()
        let externalReads = SendableCounter()
        let store = OfficialOAuthVaultStore(
            keychain: keychain,
            defaults: defaults,
            externalKeychainReader: { _ in
                externalReads.increment()
                return rawJSON
            }
        )

        XCTAssertTrue(store.migrateFromExternalKeychainIfNeeded(provider: .claude))
        XCTAssertEqual(externalReads.value, 1)

        // The local vault account can be cleared (e.g. full credential reset);
        // recovery migration must not be blocked by the stale completion marker.
        keychain.deleteToken(service: "oh-myusage", account: "official/claude/oauth-json")
        XCTAssertNil(store.readOAuthJSON(provider: .claude))

        XCTAssertTrue(store.migrateFromExternalKeychainIfNeeded(provider: .claude))
        XCTAssertEqual(externalReads.value, 2)
        XCTAssertEqual(store.readOAuthJSON(provider: .claude), rawJSON)
    }

    func testMigrateFailsWhenExternalKeychainHasNoUsableCredential() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let store = OfficialOAuthVaultStore(
            keychain: makeTestKeychain(),
            defaults: defaults,
            externalKeychainReader: { _ in nil }
        )

        XCTAssertFalse(store.migrateFromExternalKeychainIfNeeded(provider: .codex))
        XCTAssertNil(store.readOAuthJSON(provider: .codex))
        XCTAssertFalse(store.isMigrationComplete(provider: .codex))
    }

    // MARK: - Per-profile slot accounts (P0-2 multi-account storage)

    func testProfileAccountConstantsUseCanonicalNames() {
        XCTAssertEqual(
            OfficialOAuthVaultAccounts.profileAccount(for: .codex, slotID: .a),
            "official/codex/profile/A/oauth-json"
        )
        XCTAssertEqual(
            OfficialOAuthVaultAccounts.profileAccount(for: .claude, slotID: CodexSlotID(rawValue: "B")),
            "official/claude/profile/B/oauth-json"
        )
    }

    func testProfileSlotAccountsRoundTripPerSlotWithoutTouchingProviderEntry() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let store = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)
        let slotA = Self.sampleCodexAuthJSON(accountID: "acc-slot-a")
        let slotB = Self.sampleCodexAuthJSON(accountID: "acc-slot-b")

        XCTAssertTrue(store.saveProfileOAuthJSON(provider: .codex, slotID: .a, rawJSON: slotA))
        XCTAssertTrue(store.saveProfileOAuthJSON(provider: .codex, slotID: .b, rawJSON: slotB))
        XCTAssertEqual(store.readProfileOAuthJSON(provider: .codex, slotID: .a), slotA)
        XCTAssertEqual(store.readProfileOAuthJSON(provider: .codex, slotID: .b), slotB)
        XCTAssertNil(store.readProfileOAuthJSON(provider: .codex, slotID: CodexSlotID(rawValue: "C")))

        // Slot writes never touch the provider-wide "current" entry.
        XCTAssertNil(store.readOAuthJSON(provider: .codex))
        XCTAssertNil(
            keychain.readToken(
                service: "oh-myusage",
                account: OfficialOAuthVaultAccounts.codexOAuthJSON
            )
        )
    }

    func testSaveProfileOAuthJSONRejectsInvalidPayloadWithoutWriting() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let store = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)

        XCTAssertFalse(store.saveProfileOAuthJSON(provider: .codex, slotID: .a, rawJSON: "not-json"))
        XCTAssertFalse(store.saveProfileOAuthJSON(provider: .claude, slotID: .a, rawJSON: #"{"claudeAiOauth":{}}"#))
        XCTAssertNil(store.readProfileOAuthJSON(provider: .codex, slotID: .a))
        XCTAssertNil(store.readProfileOAuthJSON(provider: .claude, slotID: .a))
    }

    func testDeleteProfileOAuthJSONRemovesOnlyThatSlot() {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let store = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)
        let slotA = Self.sampleClaudeCredentialsJSON()
        let slotB = Self.sampleClaudeCredentialsJSON()

        XCTAssertTrue(store.saveProfileOAuthJSON(provider: .claude, slotID: .a, rawJSON: slotA))
        XCTAssertTrue(store.saveProfileOAuthJSON(provider: .claude, slotID: .b, rawJSON: slotB))

        XCTAssertTrue(store.deleteProfileOAuthJSON(provider: .claude, slotID: .a))
        XCTAssertNil(store.readProfileOAuthJSON(provider: .claude, slotID: .a))
        XCTAssertEqual(store.readProfileOAuthJSON(provider: .claude, slotID: .b), slotB)
    }

    // MARK: - Fixtures (fake values only)

    private final class SendableCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
    }

    private static func sampleCodexAuthJSON(accountID: String) -> String {
        let payload = Data(#"{"email":"user\#(accountID)@example.com"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return #"""
        {
          "tokens": {
            "access_token": "vault-codex-access-\#(accountID)",
            "refresh_token": "vault-codex-refresh-\#(accountID)",
            "account_id": "\#(accountID)",
            "id_token": "header.\#(payload).signature"
          }
        }
        """#
    }

    private static func sampleClaudeCredentialsJSON() -> String {
        #"""
        {
          "claudeAiOauth": {
            "accessToken": "vault-claude-access",
            "refreshToken": "vault-claude-refresh",
            "subscriptionType": "pro",
            "scopes": ["user:profile"]
          }
        }
        """#
    }
}
