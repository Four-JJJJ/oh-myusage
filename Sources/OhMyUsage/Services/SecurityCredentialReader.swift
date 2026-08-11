import Foundation
import LocalAuthentication
import Security
import OhMyUsageProviders

enum SecurityCredentialReader {
    private struct CredentialCacheKey: Hashable {
        let service: String
        let account: String?
        let interactive: Bool
    }

    private enum CachedCredentialValue {
        case value(String)
        case missing
    }

    private struct CachedCredential {
        let value: CachedCredentialValue
        let expiresAt: Date
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var credentialCache: [CredentialCacheKey: CachedCredential] = [:]
    private static let successCacheTTL: TimeInterval = 120
    private static let failureBackoffInterval: TimeInterval = 8

    static func readGenericPassword(
        service: String,
        account: String? = nil,
        bypassCache: Bool = false,
        interactive: Bool = false
    ) -> String? {
        let normalizedService = normalize(service)
        let normalizedAccount = normalizeOptional(account)
        let cacheKey = CredentialCacheKey(
            service: normalizedService,
            account: normalizedAccount,
            interactive: interactive
        )
        let now = Date()

        if !bypassCache, let cached = cachedCredential(for: cacheKey, now: now) {
            switch cached {
            case .value(let value):
                return value
            case .missing:
                return nil
            }
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: normalizedService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: authenticationContext(interactive: interactive),
        ]
        if let normalizedAccount {
            query[kSecAttrAccount as String] = normalizedAccount
        } else if let account {
            query[kSecAttrAccount as String] = account
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            cache(.value(text), for: cacheKey, now: now)
            return text
        }
        cache(.missing, for: cacheKey, now: now)
        return nil
    }

    @discardableResult
    static func saveGenericPassword(service: String, account: String? = nil, text: String) -> Bool {
        let normalizedService = normalize(service)
        let normalizedAccount = normalizeOptional(account) ?? normalizedService
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: normalizedService,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let data = Data(text.utf8)
        let addAttributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: normalizedService,
            kSecAttrAccount as String: normalizedAccount,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(addAttributes as CFDictionary, nil)
        if status == errSecSuccess {
            let now = Date()
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: normalizedAccount, interactive: false), now: now)
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: normalizedAccount, interactive: true), now: now)
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: nil, interactive: false), now: now)
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: nil, interactive: true), now: now)
            return true
        }

        let args = [
            "add-generic-password",
            "-U",
            "-s", normalizedService,
            "-a", normalizedAccount,
            "-w", text
        ]
        guard let output = ShellCommand.run(executable: "/usr/bin/security", arguments: args, timeout: 5) else {
            return false
        }
        if output.status == 0 {
            let now = Date()
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: normalizedAccount, interactive: false), now: now)
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: normalizedAccount, interactive: true), now: now)
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: nil, interactive: false), now: now)
            cache(.value(text), for: CredentialCacheKey(service: normalizedService, account: nil, interactive: true), now: now)
            return true
        }
        return false
    }

    private static func cachedCredential(for key: CredentialCacheKey, now: Date) -> CachedCredentialValue? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        purgeExpiredEntriesLocked(now: now)
        guard let entry = credentialCache[key] else {
            return nil
        }
        return entry.value
    }

    private static func cache(_ value: CachedCredentialValue, for key: CredentialCacheKey, now: Date) {
        let ttl: TimeInterval
        switch value {
        case .value:
            ttl = successCacheTTL
        case .missing:
            ttl = failureBackoffInterval
        }

        cacheLock.lock()
        credentialCache[key] = CachedCredential(
            value: value,
            expiresAt: now.addingTimeInterval(max(0, ttl))
        )
        purgeExpiredEntriesLocked(now: now)
        cacheLock.unlock()
    }

    private static func purgeExpiredEntriesLocked(now: Date) {
        credentialCache = credentialCache.filter { _, value in
            value.expiresAt > now
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func authenticationContext(interactive: Bool) -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = !interactive
        return context
    }
}
