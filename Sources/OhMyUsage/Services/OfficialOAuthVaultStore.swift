import Foundation
import OhMyUsageProviders

/// Vault account identifiers that hold the normalized OAuth JSON for the official
/// Codex / Claude integrations. The accounts live inside the app's own credential
/// vault (service `oh-myusage`) and are read/written through the shared
/// ``CredentialBroker`` via the `TokenCredentialStoring` port.
enum OfficialOAuthVaultAccounts {
    static let codexOAuthJSON = "official/codex/oauth-json"
    static let claudeOAuthJSON = "official/claude/oauth-json"

    static func account(for provider: OAuthImportProvider) -> String {
        switch provider {
        case .codex:
            return codexOAuthJSON
        case .claude:
            return claudeOAuthJSON
        }
    }

    /// Per-slot vault account for profile-scoped OAuth JSON (multi-account
    /// profile token storage). The profile file keeps metadata only; the token
    /// for slot `slotID` lives under this account. The provider-wide account
    /// above continues to hold the *current* system credential and is kept in
    /// sync by the desktop auth services, so both layouts coexist.
    static func profileAccount(for provider: OAuthImportProvider, slotID: CodexSlotID) -> String {
        "official/\(provider == .codex ? "codex" : "claude")/profile/\(slotID.rawValue)/oauth-json"
    }
}

/// Vault persistence for the normalized OAuth JSON of the official Codex / Claude
/// integrations (Phase 1 §7.6).
///
/// Fixed read priority: app vault → local credential files → external Keychain
/// (`Codex Auth` / `Claude Code-credentials`). The external Keychain tier is only
/// readable through ``readExternalKeychainJSON`` / ``migrateFromExternalKeychainIfNeeded``
/// on explicit user import or auth-recovery paths; ordinary polling never touches it.
///
/// Writes parse-verify the payload first, and the one-way migration completion
/// marker is only recorded after verification AND the vault write both succeeded.
/// External Keychain items owned by other apps are never deleted by this store.
final class OfficialOAuthVaultStore: @unchecked Sendable {
    static let codexExternalKeychainService = "Codex Auth"
    static let claudeExternalKeychainService = "Claude Code-credentials"

    private let keychain: any TokenCredentialStoring
    private let defaults: UserDefaults
    private let externalKeychainReader: @Sendable (OAuthImportProvider) -> String?

    init(
        keychain: any TokenCredentialStoring,
        defaults: UserDefaults = .standard,
        externalKeychainReader: @escaping @Sendable (OAuthImportProvider) -> String? = { provider in
            OfficialOAuthVaultStore.readExternalKeychainJSON(provider: provider)
        }
    ) {
        self.keychain = keychain
        self.defaults = defaults
        self.externalKeychainReader = externalKeychainReader
    }

    // MARK: - Reads

    /// Non-interactive read of the normalized OAuth JSON from the app vault.
    /// Returns nil when the account is absent or empty.
    func readOAuthJSON(provider: OAuthImportProvider) -> String? {
        let raw = keychain.readToken(
            service: TokenCredentialStoreServiceNames.defaultServiceName,
            account: OfficialOAuthVaultAccounts.account(for: provider)
        )
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Reads the external `Codex Auth` / `Claude Code-credentials` Keychain item.
    /// Only for explicit user import or auth recovery; never called by polling.
    func readExternalKeychainJSON(provider: OAuthImportProvider) -> String? {
        let raw = externalKeychainReader(provider)
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Per-profile slot reads / writes (multi-account profiles)

    /// Non-interactive read of the profile-scoped OAuth JSON for one slot.
    /// Returns nil when the slot account is absent or empty.
    func readProfileOAuthJSON(provider: OAuthImportProvider, slotID: CodexSlotID) -> String? {
        let raw = keychain.readToken(
            service: TokenCredentialStoreServiceNames.defaultServiceName,
            account: OfficialOAuthVaultAccounts.profileAccount(for: provider, slotID: slotID)
        )
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Parse-verifies `rawJSON` and stores it as the profile-scoped OAuth JSON
    /// for one slot. Returns false when verification or the vault write fails.
    @discardableResult
    func saveProfileOAuthJSON(
        provider: OAuthImportProvider,
        slotID: CodexSlotID,
        rawJSON: String
    ) -> Bool {
        guard let verified = verifiedOAuthJSON(provider: provider, rawJSON: rawJSON) else {
            return false
        }
        return keychain.saveToken(
            verified,
            service: TokenCredentialStoreServiceNames.defaultServiceName,
            account: OfficialOAuthVaultAccounts.profileAccount(for: provider, slotID: slotID)
        )
    }

    /// Deletes the profile-scoped OAuth JSON for one slot. Only for explicit
    /// cleanup paths; ordinary profile removal keeps the token (lossless).
    @discardableResult
    func deleteProfileOAuthJSON(provider: OAuthImportProvider, slotID: CodexSlotID) -> Bool {
        keychain.deleteToken(
            service: TokenCredentialStoreServiceNames.defaultServiceName,
            account: OfficialOAuthVaultAccounts.profileAccount(for: provider, slotID: slotID)
        )
    }

    // MARK: - Writes (verify first)

    /// Parse-verifies `rawJSON` and stores it as the normalized OAuth JSON in the
    /// app vault. The migration completion marker is only recorded after
    /// verification and the vault write both succeeded. Returns false when
    /// verification or the vault write fails.
    @discardableResult
    func saveOAuthJSON(provider: OAuthImportProvider, rawJSON: String) -> Bool {
        guard let verified = verifiedOAuthJSON(provider: provider, rawJSON: rawJSON) else {
            return false
        }
        guard keychain.saveToken(
            verified,
            service: TokenCredentialStoreServiceNames.defaultServiceName,
            account: OfficialOAuthVaultAccounts.account(for: provider)
        ) else {
            return false
        }
        defaults.set(true, forKey: migrationCompleteKey(for: provider))
        return true
    }

    /// Explicit auth-recovery migration: reads the external Keychain item (allowed
    /// only on this explicit path), verifies it, and writes the app vault. Skips
    /// the external read when the vault already holds verified OAuth JSON. The
    /// completion marker is only updated after verification and write succeed.
    @discardableResult
    func migrateFromExternalKeychainIfNeeded(provider: OAuthImportProvider) -> Bool {
        if isMigrationComplete(provider: provider),
           let existing = readOAuthJSON(provider: provider),
           isValidOAuthJSON(provider: provider, rawJSON: existing) {
            return true
        }

        guard let external = readExternalKeychainJSON(provider: provider) else {
            return false
        }
        return saveOAuthJSON(provider: provider, rawJSON: external)
    }

    /// Whether a previous migration write plus parse verification has completed.
    func isMigrationComplete(provider: OAuthImportProvider) -> Bool {
        defaults.bool(forKey: migrationCompleteKey(for: provider))
    }

    // MARK: - Verification

    private func verifiedOAuthJSON(provider: OAuthImportProvider, rawJSON: String) -> String? {
        let trimmed = rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValidOAuthJSON(provider: provider, rawJSON: trimmed) else {
            return nil
        }
        return trimmed
    }

    private func isValidOAuthJSON(provider: OAuthImportProvider, rawJSON: String) -> Bool {
        switch provider {
        case .codex:
            return (try? CodexAccountProfileStore.parseAuthJSON(rawJSON)) != nil
        case .claude:
            return (try? ClaudeAccountProfileStore.parseCredentialsJSON(rawJSON)) != nil
        }
    }

    private func migrationCompleteKey(for provider: OAuthImportProvider) -> String {
        let providerKey = provider == .codex ? "Codex" : "Claude"
        return "OhMyUsage.OAuthVault.\(providerKey).OAuthJSONMigrationComplete"
    }

    private static func readExternalKeychainJSON(provider: OAuthImportProvider) -> String? {
        switch provider {
        case .codex:
            return SecurityCredentialReader.readGenericPassword(service: codexExternalKeychainService)
        case .claude:
            return SecurityCredentialReader.readGenericPassword(service: claudeExternalKeychainService)
        }
    }
}
