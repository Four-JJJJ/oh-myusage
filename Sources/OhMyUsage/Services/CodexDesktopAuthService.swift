import Foundation
import OhMyUsageProviders

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

    // MARK: - Shared OAuth refresh pipeline (P2-4)

    /// Lightweight Codex configuration for the shared desktop refresh
    /// pipeline: `auth.openai.com` token endpoint (form-encoded refresh
    /// request) → `tokens` field merge (with root-level fallback for flat
    /// auth JSON) → `last_refresh` stamp → canonical parse verification.
    static let oauthRefreshConfiguration = OAuthRefreshPipeline.Configuration(
        label: "Codex",
        vaultProvider: .codex,
        makeRefreshRequest: { refreshToken in
            var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = OfficialProviderAuthRuntime.urlEncodedFormData([
                "grant_type": "refresh_token",
                "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
                "refresh_token": refreshToken,
            ])
            return request
        },
        invalidRefreshedJSONMessage: "invalid refreshed auth json",
        writingOptions: [.prettyPrinted, .sortedKeys],
        mergeRefreshedFields: { refresh, now, json in
            let tokens = (json["tokens"] as? [String: Any]) ?? json
            let resolvedRefreshToken = OfficialValueParser.string(refresh.json["refresh_token"])
                ?? OfficialValueParser.string(tokens["refresh_token"] ?? tokens["refreshToken"])
            let resolvedIDToken = OfficialValueParser.string(refresh.json["id_token"])
                ?? OfficialValueParser.string(tokens["id_token"] ?? tokens["idToken"])
            let resolvedAccountID = OfficialValueParser.string(refresh.json["account_id"] ?? refresh.json["accountId"])
                ?? OfficialValueParser.string(tokens["account_id"] ?? tokens["accountId"])

            var updatedTokens = tokens
            updatedTokens["access_token"] = refresh.accessToken
            updatedTokens["refresh_token"] = resolvedRefreshToken
            updatedTokens["id_token"] = resolvedIDToken
            updatedTokens["account_id"] = resolvedAccountID
            if json["tokens"] != nil {
                json["tokens"] = updatedTokens
            } else {
                json = updatedTokens
            }
            json["last_refresh"] = ISO8601DateFormatter().string(from: now)
        },
        verifyRefreshedJSON: { rawJSON in
            _ = try CodexAccountProfileStore.parseAuthJSON(rawJSON)
        }
    )

    /// Refreshes the OAuth credential behind `rawAuthJSON` through the shared
    /// desktop refresh pipeline (token refresh → `tokens` field merge →
    /// auth.json merge write-back for every existing auth file → vault
    /// write-back).
    ///
    /// Semantics match the previous per-service flow: returns nil when the
    /// credential carries no refresh token; throws when the refresh request
    /// itself fails. Write-back failures are logged (via `log`) but never
    /// fail an otherwise successful refresh — the returned JSON always holds
    /// the freshly accepted tokens.
    func refreshAuthJSON(
        session: URLSession = .shared,
        rawAuthJSON: String,
        fileIO: OAuthRefreshPipeline.FileIO = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = OAuthRefreshPipeline.standardLog
    ) async throws -> String? {
        let payload = try CodexAccountProfileStore.parseAuthJSON(rawAuthJSON)
        let pipeline = OAuthRefreshPipeline(
            configuration: Self.oauthRefreshConfiguration,
            log: log
        )
        let result = try await pipeline.refreshCredential(
            session: session,
            rawJSON: rawAuthJSON,
            refreshToken: payload.refreshToken,
            filePaths: resolvedAuthPaths().filter { fileManager.fileExists(atPath: $0) },
            vault: oauthVault,
            fileIO: fileIO,
            now: now
        )
        return result?.refreshedRawJSON
    }
}
