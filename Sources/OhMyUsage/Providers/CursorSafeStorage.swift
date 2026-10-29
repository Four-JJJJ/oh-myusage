import Foundation
import OhMyUsageProviders

/// Cursor IDE 的 token 加密存储（Electron safeStorage）。
///
/// 新版 Cursor 会把 `cursorAuth/accessToken`、`cursorAuth/refreshToken` 用
/// Electron safeStorage 加密后再写进 `state.vscdb`，值形如
/// `cursor-safe-storage:v1:<base64 的 v10 密文>`，密钥来自钥匙串项
/// `Cursor Safe Storage` / `Cursor Key`。把这段密文当 token 发出去只会拿到
/// 401，随后 refresh 也会被 Cursor 以 `{"access_token":"","shouldLogout":true}`
/// 拒绝，所以读取时必须先解密。
struct CursorSafeStorage: Sendable {
    static let encryptedValuePrefix = "cursor-safe-storage:v1:"
    static let keychainService = "Cursor Safe Storage"
    static let keychainAccount = "Cursor Key"

    typealias PasswordReader = @Sendable () throws -> String
    typealias Decryptor = @Sendable (_ encodedPayload: String, _ passphrase: String) -> String?

    var readPassword: PasswordReader
    var decrypt: Decryptor

    static let `default` = CursorSafeStorage(
        readPassword: { try CursorSafeStorage.readKeychainPassword() },
        decrypt: { payload, passphrase in
            ChromiumSafeStorageCrypto.decryptBase64(payload, passphrase: passphrase)
        }
    )

    static func isEncrypted(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(encryptedValuePrefix)
    }

    /// 明文 token 原样返回；加密值解密后返回其中的 token；无法解密返回 nil。
    func resolveToken(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard Self.isEncrypted(trimmed) else { return trimmed }
        guard let passphrase = try? readPassword(), !passphrase.isEmpty else { return nil }
        let payload = String(trimmed.dropFirst(Self.encryptedValuePrefix.count))
        guard let plaintext = decrypt(payload, passphrase) else { return nil }
        return Self.token(from: plaintext)
    }

    /// 解密结果是 token 本身（JWT），或包着 token 的字符串。
    static func token(from plaintext: String) -> String? {
        if let jwt = jwt(in: plaintext) {
            return jwt
        }
        let trimmed = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func jwt(in raw: String) -> String? {
        let pattern = #"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              let jwtRange = Range(match.range, in: raw) else {
            return nil
        }
        return String(raw[jwtRange])
    }

    static func readKeychainPassword() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-a", keychainAccount,
            "-s", keychainService,
            "-w"
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw ProviderError.missingCredential(keychainService)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProviderError.missingCredential(keychainService)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let passphrase = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if passphrase.isEmpty {
            throw ProviderError.missingCredential(keychainService)
        }
        return passphrase
    }
}
