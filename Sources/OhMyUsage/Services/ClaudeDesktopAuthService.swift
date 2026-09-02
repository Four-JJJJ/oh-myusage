import Foundation

enum ClaudeDesktopAuthError: LocalizedError {
    case invalidCredentials
    case noWritableCredentialPath
    case fileWriteFailed(String)
    case keychainWriteFailed
    case vaultWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Claude credentials JSON"
        case .noWritableCredentialPath:
            return "Unable to locate a writable Claude credentials path"
        case .fileWriteFailed(let path):
            return "Failed to write Claude credentials at \(path)"
        case .keychainWriteFailed:
            return "Failed to update Claude Code keychain credentials"
        case .vaultWriteFailed:
            return "Failed to store the Claude OAuth credential in the app vault"
        }
    }
}

final class ClaudeDesktopAuthService {
    private let fileManager: FileManager
    private let homeDirectory: () -> String
    private let environment: () -> [String: String]
    private let keychainReader: () -> String?
    private let keychainWriter: (String) -> Bool
    private let oauthVault: OfficialOAuthVaultStore

    init(
        fileManager: FileManager = .default,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        keychainReader: @escaping () -> String? = {
            SecurityCredentialReader.readGenericPassword(service: "Claude Code-credentials")
        },
        keychainWriter: @escaping (String) -> Bool = { value in
            SecurityCredentialReader.saveGenericPassword(service: "Claude Code-credentials", text: value)
        },
        oauthVault: OfficialOAuthVaultStore? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.keychainReader = keychainReader
        self.keychainWriter = keychainWriter
        self.oauthVault = oauthVault ?? OfficialOAuthVaultStore(
            keychain: CredentialBroker(keychain: KeychainService())
        )
    }

    func resolvedConfigDirectories() -> [String] {
        let home = homeDirectory()
        let envConfigDir = ClaudeAccountProfileStore.normalizedConfigDirectory(environment()["CLAUDE_CONFIG_DIR"])
        let defaultDir = ClaudeAccountProfileStore.normalizedConfigDirectory("\(home)/.claude")
        let candidates = [envConfigDir, defaultDir].compactMap { $0 }
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    func resolvedCredentialPaths() -> [String] {
        resolvedConfigDirectories().map { ClaudeAccountProfileStore.credentialsFilePath(configDirectory: $0) }
    }

    func currentSystemConfigDirectory() -> String? {
        resolvedConfigDirectories().first
    }

    /// Non-interactive sources only (app vault → local .credentials.json files).
    /// Safe for ordinary polling / sync; the external `Claude Code-credentials`
    /// Keychain item is never read here (Phase 1 §7.6).
    func currentCredentialsJSON() -> String? {
        if let vaultJSON = oauthVault.readOAuthJSON(provider: .claude) {
            return vaultJSON
        }
        for path in resolvedCredentialPaths() where fileManager.fileExists(atPath: path) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    /// Explicit auth-recovery read (user-initiated import / recovery only):
    /// app vault → local .credentials.json files → external `Claude Code-credentials` Keychain.
    func currentCredentialsJSONForAuthRecovery() -> String? {
        currentCredentialsJSON() ?? keychainReader()
    }

    /// Explicit auth-recovery migration of the external `Claude Code-credentials`
    /// Keychain credential into the app vault. Never called from ordinary polling.
    @discardableResult
    func migrateVaultFromExternalKeychain() -> Bool {
        oauthVault.migrateFromExternalKeychainIfNeeded(provider: .claude)
    }

    /// 认证恢复快路径（Phase 1 §7.6）：仅由用户主动导入/恢复流程调用。
    /// vault 已有可解析的 OAuth JSON 时不迁移——避免把已被上游吊销的旧授权
    /// 反复“复活”成死循环；vault 缺失时尝试把外部 `Claude Code-credentials`
    /// Keychain 条目静默迁入 vault。成功返回迁移后的 vault JSON；无法迁移返回
    /// nil，调用方继续走交互式导入流程。
    func migrateExternalKeychainCredentialForRecoveryIfNeeded() -> String? {
        if let existing = oauthVault.readOAuthJSON(provider: .claude),
           (try? ClaudeAccountProfileStore.parseCredentialsJSON(existing)) != nil {
            return nil
        }
        guard oauthVault.migrateFromExternalKeychainIfNeeded(provider: .claude),
              let migrated = oauthVault.readOAuthJSON(provider: .claude) else {
            return nil
        }
        return migrated
    }

    func currentCredentialFingerprint() -> String? {
        guard let raw = currentCredentialsJSON(),
              let payload = try? ClaudeAccountProfileStore.parseCredentialsJSON(raw) else {
            return nil
        }
        return payload.credentialFingerprint
    }

    func applyCredentialsJSON(_ credentialsJSON: String) throws {
        let trimmed = credentialsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              (try? ClaudeAccountProfileStore.parseCredentialsJSON(trimmed)) != nil else {
            throw ClaudeDesktopAuthError.invalidCredentials
        }

        let existingPaths = resolvedCredentialPaths().filter { fileManager.fileExists(atPath: $0) }
        let targets = existingPaths.isEmpty ? Array(resolvedCredentialPaths().prefix(1)) : existingPaths
        guard !targets.isEmpty else {
            throw ClaudeDesktopAuthError.noWritableCredentialPath
        }

        for path in targets {
            let url = URL(fileURLWithPath: path)
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = trimmed.data(using: .utf8) else {
                    throw ClaudeDesktopAuthError.invalidCredentials
                }
                try data.write(to: url, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                throw ClaudeDesktopAuthError.fileWriteFailed(path)
            }
        }

        guard keychainWriter(trimmed) else {
            throw ClaudeDesktopAuthError.keychainWriteFailed
        }
        guard oauthVault.saveOAuthJSON(provider: .claude, rawJSON: trimmed) else {
            throw ClaudeDesktopAuthError.vaultWriteFailed
        }
    }
}
