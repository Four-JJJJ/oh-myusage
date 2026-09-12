import Foundation
import OhMyUsageProviders

struct GrokBotDesktopCredentialStore: Sendable {
    typealias PasswordReader = @Sendable () throws -> String
    typealias FileReader = @Sendable (String) throws -> Data
    typealias Decryptor = @Sendable (String, String) -> String?

    var secretsFilePath: String
    var readPassword: PasswordReader
    var readFile: FileReader
    var decrypt: Decryptor

    static func defaultSecretsFilePath(homeDirectory: String = NSHomeDirectory()) -> String {
        homeDirectory + "/Library/Application Support/Grok Bot/sand-secrets.json"
    }

    static func `default`(homeDirectory: String = NSHomeDirectory()) -> GrokBotDesktopCredentialStore {
        GrokBotDesktopCredentialStore(
            secretsFilePath: defaultSecretsFilePath(homeDirectory: homeDirectory),
            readPassword: { try readKeychainPassphrase() },
            readFile: { path in try Data(contentsOf: URL(fileURLWithPath: path)) },
            decrypt: { encoded, passphrase in
                ChromiumSafeStorageCrypto.decryptBase64(encoded, passphrase: passphrase)
            }
        )
    }

    func load() throws -> CursorSessionCredentials {
        let data: Data
        do {
            data = try readFile(secretsFilePath)
        } catch {
            throw ProviderError.missingCredential(secretsFilePath)
        }

        let account = try Self.parseActiveAccount(from: data)
        let passphrase = try readPassword()

        guard let encryptedAccess = OfficialValueParser.string(account["cursor-access-token"]) else {
            throw ProviderError.missingCredential("Grok Bot cursor-access-token")
        }
        guard let decryptedAccess = decrypt(encryptedAccess, passphrase),
              let accessToken = Self.extractJWT(from: decryptedAccess) else {
            throw ProviderError.missingCredential("Grok Bot Safe Storage")
        }

        var refreshToken: String?
        if let encryptedRefresh = OfficialValueParser.string(account["cursor-refresh-token"]),
           let decryptedRefresh = decrypt(encryptedRefresh, passphrase) {
            refreshToken = Self.extractRefreshToken(from: decryptedRefresh)
        }

        var email: String?
        if let encryptedProfile = OfficialValueParser.string(account["cursor-account-profile"]),
           let decryptedProfile = decrypt(encryptedProfile, passphrase),
           let profileData = decryptedProfile.data(using: .utf8),
           let profile = try? JSONSerialization.jsonObject(with: profileData) as? [String: Any] {
            email = OfficialValueParser.string(profile["email"])
        }

        return CursorSessionCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            email: email,
            membershipType: nil,
            source: .grokBotApp,
            databasePath: nil
        )
    }

    internal static func parseActiveAccount(from data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Grok Bot sand-secrets decode failed")
        }

        let accountsObject: [String: Any]
        if let encoded = root["cursor-accounts"] as? String,
           let encodedData = encoded.data(using: .utf8),
           let parsed = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any] {
            accountsObject = parsed
        } else if let parsed = root["cursor-accounts"] as? [String: Any] {
            accountsObject = parsed
        } else {
            throw ProviderError.missingCredential("Grok Bot cursor-accounts")
        }

        let accounts = accountsObject["accounts"] as? [String: Any] ?? [:]
        let activeKey = OfficialValueParser.string(accountsObject["active"])
        if let activeKey, let account = accounts[activeKey] as? [String: Any] {
            return account
        }
        if let first = accounts.values.compactMap({ $0 as? [String: Any] }).first {
            return first
        }
        throw ProviderError.missingCredential("Grok Bot active account")
    }

    internal static func extractJWT(from raw: String) -> String? {
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

    internal static func extractRefreshToken(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let token = trimmed.unicodeScalars.prefix { allowed.contains($0) }
        let value = String(String.UnicodeScalarView(token))
        return value.isEmpty ? nil : value
    }

    private static func readKeychainPassphrase() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-a", "Grok Bot Key",
            "-s", "Grok Bot Safe Storage",
            "-w"
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw ProviderError.missingCredential("Grok Bot Safe Storage")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProviderError.missingCredential("Grok Bot Safe Storage")
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let passphrase = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if passphrase.isEmpty {
            throw ProviderError.missingCredential("Grok Bot Safe Storage")
        }
        return passphrase
    }
}
