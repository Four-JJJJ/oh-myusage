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

    /// How often an auto-importing provider re-reads the browser while a saved
    /// cookie still works. The same cadence the relay session-cookie sites use,
    /// so a login renewed in the browser replaces the saved copy before it
    /// expires instead of only after the server rejects it.
    static let proactiveBrowserCookieReadInterval: TimeInterval = 30 * 60

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

        // A browser import is persisted into the same slot, so the slot alone
        // does not mean the user pasted it. The remembered source keeps a
        // rotated login labelled as the browser it came from.
        let remembered = await rememberedSource(for: official.manualCookieAccount)
        let storedManual: (header: String, source: String)? = {
            guard let account = official.manualCookieAccount,
                  let stored = keychain.readToken(service: service, account: account),
                  let header = strategy.normalizeManualHeader(stored),
                  !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (header, remembered ?? "Manual")
        }()
        let storedManualHeader = storedManual?.header

        // Re-reads the slot rather than reusing `storedManual`, and treats the
        // source remembered at the start of the poll as the slot's label.
        func storedFallbackCookie() -> BrowserCookieHeader? {
            if let account = official.manualCookieAccount,
               let stored = keychain.readToken(service: service, account: account),
               let header = strategy.normalizeManualHeader(stored),
               !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let source = remembered ?? storedManual?.source ?? "Manual"
                return BrowserCookieHeader(header: header, source: source)
            }
            return storedManual.map { BrowserCookieHeader(header: $0.header, source: $0.source) }
        }

        // A pasted cookie is only authoritative while auto-import is off, or
        // while its rotation window is still open. Auto-import re-reads the
        // browser on the shared cadence and falls back to this copy when the
        // browser has nothing newer.
        let canRotateStoredCookie = storedManualHeader != nil && official.webMode == .autoImport
        let rotateStoredCookie = await shouldRotateStoredCookie(
            strategy: strategy,
            descriptorID: descriptorID,
            forceRefresh: forceRefresh,
            enabled: canRotateStoredCookie
        )
        if let storedManual, !rotateStoredCookie {
            return BrowserCookieHeader(header: storedManual.header, source: storedManual.source)
        }

        // A rotation re-reads the browser for real, so it needs the same live
        // lookup a user-initiated import gets. Plain background polls never
        // reach the browser at all.
        let browserAccessIntent: BrowserCredentialAccessIntent = (forceRefresh || rotateStoredCookie)
            ? .interactiveImport
            : .background

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
        // Rotation exists to notice a login the browser renewed, so it must
        // not be served the copy cached from the previous import.
        if !forceRefresh, !rotateStoredCookie,
           let cached = credentialCache.cachedHeader(for: credentialCacheKey) {
            guard let cached else {
                throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
            }
            return cached
        }

        if let webReadBackoff {
            let mayAttempt = await webReadBackoff.shouldAttempt(for: backoffKey, forceRefresh: forceRefresh)
            if !mayAttempt {
                // A recent failed browser read must not turn a working saved
                // cookie into a missing-credential poll.
                if let stored = storedFallbackCookie() {
                    return stored
                }
                throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
            }
        }

        // A first import (nothing stored yet) persists right away: there is no
        // working cookie to lose. A rotation instead hands the detected header
        // out with `pendingPersistHeader` and only reaches the keychain after
        // the request built from it succeeds, so a stale browser login cannot
        // silently destroy a cookie that still works.
        let persistImmediately = storedManualHeader == nil

        if let namedCookie = strategy.namedCookie,
           let detected = browserCookieService.detectNamedCookie(
               name: namedCookie,
               hostContains: strategy.hostContains,
               order: nil,
               accessIntent: browserAccessIntent
           ),
           let normalized = strategy.normalizeDetectedHeader(detected.header) {
            if persistImmediately {
                if let account = official.manualCookieAccount {
                    _ = keychain.saveToken(normalized, service: service, account: account)
                }
                await rememberSource(detected.source, for: official.manualCookieAccount)
            }
            if let webReadBackoff {
                await webReadBackoff.clearFailure(for: backoffKey)
            }
            let header = BrowserCookieHeader(
                header: normalized,
                source: detected.source,
                readBrowserDuringResolution: true,
                pendingPersistHeader: persistImmediately ? nil : normalized
            )
            credentialCache.store(header, for: credentialCacheKey)
            return header
        }

        if let detected = browserCookieService.detectCookieHeader(
               hostContains: strategy.hostContains,
               order: nil,
               accessIntent: browserAccessIntent
           ),
           let normalized = strategy.normalizeDetectedHeader(detected.header) {
            if persistImmediately {
                if let account = official.manualCookieAccount {
                    _ = keychain.saveToken(normalized, service: service, account: account)
                }
                await rememberSource(detected.source, for: official.manualCookieAccount)
            }
            if let webReadBackoff {
                await webReadBackoff.clearFailure(for: backoffKey)
            }
            let header = BrowserCookieHeader(
                header: normalized,
                source: detected.source,
                readBrowserDuringResolution: true,
                pendingPersistHeader: persistImmediately ? nil : normalized
            )
            credentialCache.store(header, for: credentialCacheKey)
            return header
        }

        // The browser had nothing newer. A saved cookie that still works is
        // more useful than failing the poll, so keep serving it.
        if let stored = storedFallbackCookie() {
            return stored
        }

        credentialCache.store(nil, for: credentialCacheKey)
        if let webReadBackoff, let webRetryBackoffInterval {
            await webReadBackoff.markFailure(for: backoffKey, interval: webRetryBackoffInterval)
        }
        throw ProviderError.missingCredential(strategy.autoImportMissingCredential)
    }

    /// Persists a browser-detected cookie once the request built from it has
    /// succeeded. Rotated cookies carry `pendingPersistHeader` precisely so a
    /// stale browser login never replaces a stored cookie the server still
    /// accepts.
    static func persistConfirmedCookie(
        _ cookie: BrowserCookieHeader,
        official: OfficialProviderConfig,
        keychain: any TokenCredentialStoring
    ) async {
        guard let pending = cookie.pendingPersistHeader,
              let account = official.manualCookieAccount else {
            return
        }
        _ = keychain.saveToken(pending, service: TokenCredentialStoreServiceNames.defaultServiceName, account: account)
        await rememberSource(cookie.source, for: account)
    }

    /// Counts the attempt rather than the success, so a logged-out or
    /// unreadable browser is not decrypted again on every poll.
    private static func shouldRotateStoredCookie(
        strategy: OfficialBrowserCookieImportStrategy,
        descriptorID: String,
        forceRefresh: Bool,
        enabled: Bool
    ) async -> Bool {
        guard enabled else {
            return false
        }
        let key = rotationKey(providerKey: strategy.providerKey, descriptorID: descriptorID)
        // A forced refresh reads the browser immediately, and that read counts:
        // the following polls stay inside the window instead of reading again.
        if forceRefresh {
            await RotationTracker.shared.markRead(for: key)
            return true
        }
        guard await RotationTracker.shared.shouldRead(
            for: key,
            minimumInterval: proactiveBrowserCookieReadInterval
        ) else {
            return false
        }
        await RotationTracker.shared.markRead(for: key)
        return true
    }

    /// Keyed by provider and descriptor, not by the cookie account. Pasting a
    /// new cookie must not reset the window, or every poll would re-read the
    /// browser.
    private static func rememberedSource(for account: String?) async -> String? {
        guard let account = account?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty else {
            return nil
        }
        return await RotationTracker.shared.savedSource(for: account)
    }

    private static func rememberSource(_ source: String, for account: String?) async {
        guard let account = account?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty else {
            return
        }
        await RotationTracker.shared.rememberSource(source, for: account)
    }

    private static func rotationKey(providerKey: String, descriptorID: String) -> String {
        let provider = providerKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let identity = descriptorID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "rotate:\(provider):\(identity)"
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

/// Remembers when each provider last re-read its browser cookie, so the
/// rotation cadence survives across fetches without touching the browser on
/// every poll.
private actor RotationTracker {
    static let shared = RotationTracker()

    private var lastReadAt: [String: Date] = [:]
    private var savedSourceByAccount: [String: String] = [:]

    /// The keychain slot is shared by pasted cookies and browser imports, so
    /// the source of the last import is remembered alongside it.
    func savedSource(for account: String) -> String? {
        savedSourceByAccount[account]
    }

    func rememberSource(_ source: String, for account: String) {
        savedSourceByAccount[account] = source
    }

    func shouldRead(for key: String, minimumInterval: TimeInterval, now: Date = Date()) -> Bool {
        guard let lastReadAt = lastReadAt[key] else {
            return true
        }
        return now.timeIntervalSince(lastReadAt) >= max(0, minimumInterval)
    }

    func markRead(for key: String, now: Date = Date()) {
        lastReadAt[key] = now
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
