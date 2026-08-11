import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

struct OfficialBrowserCookieImportStrategy {
    let providerKey: String
    let hostContains: String
    let namedCookie: String?
    let autoImportMissingCredential: String
    let manualCredentialFallback: String
    let normalizeManualHeader: (String) -> String?
    let normalizeDetectedHeader: (String) -> String?
}

enum OfficialProviderWebOverlayRuntime {
    private static let credentialCache = OfficialWebOverlayCredentialCache(ttl: 60)

    static func resolveCookieHeader(
        official: OfficialProviderConfig,
        descriptorID: String,
        keychain: any TokenCredentialStoring,
        browserCookieService: any BrowserCookieDetecting,
        webReadBackoff: WebOverlayRetryBackoff? = nil,
        webRetryBackoffInterval: TimeInterval? = nil,
        forceRefresh: Bool,
        strategy: OfficialBrowserCookieImportStrategy
    ) async throws -> BrowserCookieHeader {
        let service = TokenCredentialStoreServiceNames.defaultServiceName
        let browserAccessIntent: BrowserCredentialAccessIntent = forceRefresh ? .interactiveImport : .background

        if let account = official.manualCookieAccount,
           let stored = keychain.readToken(service: service, account: account),
           let header = strategy.normalizeManualHeader(stored),
           !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return BrowserCookieHeader(header: header, source: "Manual")
        }

        guard official.webMode != .manual else {
            throw ProviderError.missingCredential(official.manualCookieAccount ?? strategy.manualCredentialFallback)
        }

        guard official.webMode == .autoImport else {
            throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
        }

        let backoffKey = backoffKey(
            providerKey: strategy.providerKey,
            descriptorID: descriptorID,
            manualCookieAccount: official.manualCookieAccount
        )
        let credentialCacheKey = credentialCacheKey(
            providerKey: strategy.providerKey,
            descriptorID: descriptorID,
            manualCookieAccount: official.manualCookieAccount,
            hostContains: strategy.hostContains,
            namedCookie: strategy.namedCookie
        )
        if !forceRefresh,
           let cached = credentialCache.cachedHeader(for: credentialCacheKey) {
            guard let cached else {
                throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
            }
            return cached
        }

        if let webReadBackoff {
            guard await webReadBackoff.shouldAttempt(for: backoffKey, forceRefresh: forceRefresh) else {
                throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
            }
        }

        if let namedCookie = strategy.namedCookie,
           let detected = browserCookieService.detectNamedCookie(
               name: namedCookie,
               hostContains: strategy.hostContains,
               order: nil,
               accessIntent: browserAccessIntent
           ),
           let normalized = strategy.normalizeDetectedHeader(detected.header) {
            if let account = official.manualCookieAccount {
                _ = keychain.saveToken(normalized, service: service, account: account)
            }
            if let webReadBackoff {
                await webReadBackoff.clearFailure(for: backoffKey)
            }
            let header = BrowserCookieHeader(header: normalized, source: detected.source)
            credentialCache.store(header, for: credentialCacheKey)
            return header
        }

        if let detected = browserCookieService.detectCookieHeader(
            hostContains: strategy.hostContains,
            order: nil,
            accessIntent: browserAccessIntent
        ),
           let normalized = strategy.normalizeDetectedHeader(detected.header) {
            if let account = official.manualCookieAccount {
                _ = keychain.saveToken(normalized, service: service, account: account)
            }
            if let webReadBackoff {
                await webReadBackoff.clearFailure(for: backoffKey)
            }
            let header = BrowserCookieHeader(header: normalized, source: detected.source)
            credentialCache.store(header, for: credentialCacheKey)
            return header
        }

        credentialCache.store(nil, for: credentialCacheKey)
        if let webReadBackoff, let webRetryBackoffInterval {
            await webReadBackoff.markFailure(for: backoffKey, interval: webRetryBackoffInterval)
        }
        throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
    }

    static func hasStoredManualCookie(
        official: OfficialProviderConfig,
        keychain: any TokenCredentialStoring,
        normalizeManualHeader: (String) -> String?
    ) -> Bool {
        guard let account = official.manualCookieAccount,
              let stored = keychain.readToken(service: TokenCredentialStoreServiceNames.defaultServiceName, account: account),
              let header = normalizeManualHeader(stored),
              !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    static func merge(primary: UsageSnapshot, overlay: UsageSnapshot, sourceLabel: String) -> UsageSnapshot {
        var merged = primary
        merged.sourceLabel = sourceLabel
        merged.accountLabel = primary.accountLabel ?? overlay.accountLabel

        var existing = Set(merged.quotaWindows.map(\.id))
        for window in overlay.quotaWindows where !existing.contains(window.id) {
            merged.quotaWindows.append(window)
            existing.insert(window.id)
        }

        for (key, value) in overlay.extras where merged.extras[key] == nil {
            merged.extras[key] = value
        }
        if merged.note.isEmpty {
            merged.note = overlay.note
        }
        return merged
    }

    private static func backoffKey(
        providerKey: String,
        descriptorID: String,
        manualCookieAccount: String?
    ) -> String {
        let account = manualCookieAccount?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (account?.isEmpty == false ? account! : descriptorID)
        return "\(providerKey):\(normalized)"
    }

    private static func credentialCacheKey(
        providerKey: String,
        descriptorID: String,
        manualCookieAccount: String?,
        hostContains: String,
        namedCookie: String?
    ) -> String {
        let provider = providerKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let account = manualCookieAccount?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let identity = account?.isEmpty == false
            ? account!
            : descriptorID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = hostContains.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cookie = namedCookie?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "*"
        return "\(provider)|\(identity)|\(host)|\(cookie)"
    }
}

private final class OfficialWebOverlayCredentialCache: @unchecked Sendable {
    private struct Entry {
        let header: BrowserCookieHeader?
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private let now: () -> Date
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    init(ttl: TimeInterval, now: @escaping () -> Date = Date.init) {
        self.ttl = max(0, ttl)
        self.now = now
    }

    func cachedHeader(for key: String) -> BrowserCookieHeader?? {
        let currentDate = now()
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredLocked(now: currentDate)
        guard let entry = entries[key] else {
            return nil
        }
        return entry.header
    }

    func store(_ header: BrowserCookieHeader?, for key: String) {
        let currentDate = now()
        lock.lock()
        entries[key] = Entry(
            header: header,
            expiresAt: currentDate.addingTimeInterval(ttl)
        )
        purgeExpiredLocked(now: currentDate)
        lock.unlock()
    }

    private func purgeExpiredLocked(now: Date) {
        entries = entries.filter { _, entry in
            entry.expiresAt > now
        }
    }
}
