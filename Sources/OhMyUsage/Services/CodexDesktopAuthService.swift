import Foundation

enum CodexDesktopAuthError: LocalizedError {
    case invalidProfile
    case noWritableAuthPath
    case fileWriteFailed(String)
    case keychainWriteFailed
    case vaultWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidProfile:
            return "Invalid Codex auth profile"
        case .noWritableAuthPath:
            return "Unable to locate a writable Codex auth.json path"
        case .fileWriteFailed(let path):
            return "Failed to write Codex auth.json at \(path)"
        case .keychainWriteFailed:
            return "Failed to update Codex Auth keychain entry"
        case .vaultWriteFailed:
            return "Failed to store the Codex OAuth credential in the app vault"
        }
    }
}

final class CodexDesktopAuthService {
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
            SecurityCredentialReader.readGenericPassword(service: "Codex Auth")
        },
        keychainWriter: @escaping (String) -> Bool = { value in
            SecurityCredentialReader.saveGenericPassword(service: "Codex Auth", text: value)
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

    func resolvedAuthPaths() -> [String] {
        CodexAuthPathResolver.resolveAuthPaths(
            homeDirectory: homeDirectory(),
            environment: environment()
        )
    }

    /// Non-interactive sources only (app vault → local auth.json files). Safe for
    /// ordinary polling / sync; the external `Codex Auth` Keychain item is never
    /// read here (Phase 1 §7.6).
    func currentAuthJSON() -> String? {
        if let vaultJSON = oauthVault.readOAuthJSON(provider: .codex) {
            return vaultJSON
        }
        for path in resolvedAuthPaths() where fileManager.fileExists(atPath: path) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    /// Explicit auth-recovery read (user-initiated import / recovery only):
    /// app vault → local auth.json files → external `Codex Auth` Keychain.
    func currentAuthJSONForAuthRecovery() -> String? {
        currentAuthJSON() ?? keychainReader()
    }

    /// Reads the local auth.json files only (no vault, no external keychain).
    /// This is the live system truth owned by the Codex desktop app, used by the
    /// switch-verification flow to capture refreshes the desktop app performed
    /// while the verification fetch was running.
    func currentSystemFileAuthJSON() -> String? {
        for path in resolvedAuthPaths() where fileManager.fileExists(atPath: path) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    /// Parse-verifies and writes the given normalized OAuth JSON into the app
    /// vault. Used to keep the vault in sync with system-side auth.json refreshes.
    @discardableResult
    func saveVaultOAuthJSON(_ rawJSON: String) -> Bool {
        oauthVault.saveOAuthJSON(provider: .codex, rawJSON: rawJSON)
    }

    /// Explicit auth-recovery migration of the external `Codex Auth` Keychain
    /// credential into the app vault. Never called from ordinary polling.
    @discardableResult
    func migrateVaultFromExternalKeychain() -> Bool {
        oauthVault.migrateFromExternalKeychainIfNeeded(provider: .codex)
    }

    /// 认证恢复快路径（Phase 1 §7.6）：仅由用户主动导入/恢复流程调用。
    /// vault 已有可解析的 OAuth JSON 时不迁移——避免把已被上游吊销的旧授权
    /// 反复“复活”成死循环；vault 缺失时尝试把外部 `Codex Auth` Keychain 条目
    /// 静默迁入 vault。成功返回迁移后的 vault JSON；无法迁移返回 nil，调用方
    /// 继续走交互式导入流程。
    func migrateExternalKeychainCredentialForRecoveryIfNeeded() -> String? {
        if let existing = oauthVault.readOAuthJSON(provider: .codex),
           (try? CodexAccountProfileStore.parseAuthJSON(existing)) != nil {
            return nil
        }
        guard oauthVault.migrateFromExternalKeychainIfNeeded(provider: .codex),
              let migrated = oauthVault.readOAuthJSON(provider: .codex) else {
            return nil
        }
        return migrated
    }

    func currentCredentialFingerprint() -> String? {
        guard let raw = currentAuthJSON(),
              let payload = try? CodexAccountProfileStore.parseAuthJSON(raw) else {
            return nil
        }
        return payload.credentialFingerprint
    }

    func applyProfile(_ profile: CodexAccountProfile) throws {
        guard !profile.authJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (try? CodexAccountProfileStore.parseAuthJSON(profile.authJSON)) != nil else {
            throw CodexDesktopAuthError.invalidProfile
        }

        let existingPaths = resolvedAuthPaths().filter { fileManager.fileExists(atPath: $0) }
        let targets = existingPaths.isEmpty ? Array(resolvedAuthPaths().prefix(1)) : existingPaths
        guard !targets.isEmpty else {
            throw CodexDesktopAuthError.noWritableAuthPath
        }

        for path in targets {
            let url = URL(fileURLWithPath: path)
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = profile.authJSON.data(using: .utf8) else {
                    throw CodexDesktopAuthError.invalidProfile
                }
                try data.write(to: url, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                throw CodexDesktopAuthError.fileWriteFailed(path)
            }
        }

        guard keychainWriter(profile.authJSON) else {
            throw CodexDesktopAuthError.keychainWriteFailed
        }
        guard oauthVault.saveOAuthJSON(provider: .codex, rawJSON: profile.authJSON) else {
            throw CodexDesktopAuthError.vaultWriteFailed
        }
    }
}
