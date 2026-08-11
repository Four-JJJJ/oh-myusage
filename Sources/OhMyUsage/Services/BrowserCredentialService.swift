import Foundation
import OhMyUsageProviders

final class BrowserCredentialService {
    private struct ExpiringCacheEntry<T> {
        let value: T
        let expiresAt: Date
    }

    private let storageReader: BrowserStorageCredentialReader
    private let kimiCookieService: KimiBrowserCookieService
    private let cookieService: BrowserCookieService
    private let bearerCandidatesOverride: ((String) -> [BrowserDetectedCredential])?
    private let cookieHeaderOverride: ((String) -> BrowserDetectedCredential?)?
    private let namedCookieOverride: ((String, String) -> BrowserDetectedCredential?)?
    private let cacheTTL: TimeInterval
    private let now: () -> Date
    private let fullCachePurgeInterval: TimeInterval = 60
    private let lock = NSLock()
    private var bearerCache: [String: ExpiringCacheEntry<[BrowserDetectedCredential]>] = [:]
    private var cookieHeaderCache: [String: ExpiringCacheEntry<BrowserDetectedCredential?>] = [:]
    private var namedCookieCache: [String: ExpiringCacheEntry<BrowserDetectedCredential?>] = [:]
    private var nextFullCachePurgeAt: Date?

    init(
        bearerService: KimiBrowserCookieService? = nil,
        storageReader: BrowserStorageCredentialReader = BrowserStorageCredentialReader(),
        kimiCookieService: KimiBrowserCookieService? = nil,
        cookieService: BrowserCookieService = BrowserCookieService(),
        bearerCandidatesOverride: ((String) -> [BrowserDetectedCredential])? = nil,
        cookieHeaderOverride: ((String) -> BrowserDetectedCredential?)? = nil,
        namedCookieOverride: ((String, String) -> BrowserDetectedCredential?)? = nil,
        cacheTTL: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.storageReader = storageReader
        self.kimiCookieService = kimiCookieService ?? bearerService ?? KimiBrowserCookieService()
        self.cookieService = cookieService
        self.bearerCandidatesOverride = bearerCandidatesOverride
        self.cookieHeaderOverride = cookieHeaderOverride
        self.namedCookieOverride = namedCookieOverride
        self.cacheTTL = max(0, cacheTTL)
        self.now = now
    }

    func detectBearerTokenCandidates(
        host: String,
        accessIntent: BrowserCredentialAccessIntent = .interactiveImport
    ) -> [BrowserDetectedCredential] {
        let normalizedHost = normalizedHost(host)
        guard !normalizedHost.isEmpty else { return [] }

        let now = now()
        // Interactive lookups always hit disk so a login the user just completed
        // is picked up immediately; only background polls reuse the cached result.
        if !accessIntent.allowsLiveLookup {
            if let cached = cachedBearerCandidates(for: normalizedHost, now: now) {
                return cached
            }
            return []
        }

        let resolved: [BrowserDetectedCredential]
        if let bearerCandidatesOverride {
            resolved = bearerCandidatesOverride(normalizedHost)
        } else {
            let firstPass = storageReader.bearerTokenCandidates(
                host: normalizedHost,
                refreshPaths: false
            )
            resolved = firstPass.isEmpty
                ? storageReader.bearerTokenCandidates(host: normalizedHost, refreshPaths: true)
                : firstPass
        }
        cacheBearerCandidates(resolved, for: normalizedHost, now: now)
        return resolved
    }

    func detectCookieHeader(
        host: String,
        accessIntent: BrowserCredentialAccessIntent = .interactiveImport
    ) -> BrowserDetectedCredential? {
        let normalizedHost = normalizedHost(host)
        guard !normalizedHost.isEmpty else { return nil }

        let now = now()
        if !accessIntent.allowsLiveLookup {
            if let cached = cachedCookieHeader(for: normalizedHost, now: now) {
                return cached
            }
            return nil
        }

        let resolved: BrowserDetectedCredential?
        if let cookieHeaderOverride {
            var candidate: BrowserDetectedCredential?
            for candidateHost in hostCandidates(for: normalizedHost) {
                if let detected = cookieHeaderOverride(candidateHost) {
                    candidate = detected
                    break
                }
            }
            resolved = candidate
        } else {
            let firstPass = detectLiveBrowserCookieHeader(
                normalizedHost: normalizedHost,
                accessIntent: accessIntent,
                refreshPaths: false
            )
            let browserCookie = firstPass ?? detectLiveBrowserCookieHeader(
                normalizedHost: normalizedHost,
                accessIntent: accessIntent,
                refreshPaths: true
            )
            if let browserCookie {
                resolved = browserCookie
            } else {
                let kimiFirstPass = detectLiveKimiCookieHeader(
                    normalizedHost: normalizedHost,
                    refreshPaths: false
                )
                resolved = kimiFirstPass ?? detectLiveKimiCookieHeader(
                    normalizedHost: normalizedHost,
                    refreshPaths: true
                )
            }
        }

        cacheCookieHeader(resolved, for: normalizedHost, now: now)
        return resolved
    }

    func detectNamedCookie(
        name: String,
        host: String,
        accessIntent: BrowserCredentialAccessIntent = .interactiveImport
    ) -> BrowserDetectedCredential? {
        let normalizedHost = normalizedHost(host)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty, !normalizedName.isEmpty else { return nil }

        let cacheKey = "\(normalizedName.lowercased())|\(normalizedHost)"
        let now = now()
        if !accessIntent.allowsLiveLookup {
            if let cached = cachedNamedCookie(for: cacheKey, now: now) {
                return cached
            }
            return nil
        }

        let resolved: BrowserDetectedCredential?
        if let namedCookieOverride {
            var candidate: BrowserDetectedCredential?
            for candidateHost in hostCandidates(for: normalizedHost) {
                if let detected = namedCookieOverride(normalizedName, candidateHost) {
                    candidate = detected
                    break
                }
            }
            resolved = candidate
        } else {
            let firstPass = detectLiveNamedCookie(
                name: normalizedName,
                normalizedHost: normalizedHost,
                accessIntent: accessIntent,
                refreshPaths: false
            )
            resolved = firstPass ?? detectLiveNamedCookie(
                name: normalizedName,
                normalizedHost: normalizedHost,
                accessIntent: accessIntent,
                refreshPaths: true
            )
        }

        cacheNamedCookie(resolved, for: cacheKey, now: now)
        return resolved
    }

    private func detectLiveBrowserCookieHeader(
        normalizedHost: String,
        accessIntent: BrowserCredentialAccessIntent,
        refreshPaths: Bool
    ) -> BrowserDetectedCredential? {
        for candidateHost in hostCandidates(for: normalizedHost) {
            if let detected = cookieService.detectCookieHeader(
                hostContains: candidateHost,
                order: nil,
                accessIntent: accessIntent,
                refreshPaths: refreshPaths
            ) {
                return BrowserDetectedCredential(value: detected.header, source: detected.source)
            }
        }
        return nil
    }

    private func detectLiveKimiCookieHeader(
        normalizedHost: String,
        refreshPaths: Bool
    ) -> BrowserDetectedCredential? {
        for candidateHost in hostCandidates(for: normalizedHost) {
            if let detected = kimiCookieService.detectCookieHeader(
                host: candidateHost,
                refreshPaths: refreshPaths
            ) {
                return BrowserDetectedCredential(value: detected.token, source: detected.source)
            }
        }
        return nil
    }

    private func detectLiveNamedCookie(
        name: String,
        normalizedHost: String,
        accessIntent: BrowserCredentialAccessIntent,
        refreshPaths: Bool
    ) -> BrowserDetectedCredential? {
        for candidateHost in hostCandidates(for: normalizedHost) {
            if let detected = cookieService.detectNamedCookie(
                name: name,
                hostContains: candidateHost,
                order: nil,
                accessIntent: accessIntent,
                refreshPaths: refreshPaths
            ) {
                return BrowserDetectedCredential(value: detected.header, source: detected.source)
            }
        }
        return nil
    }

    private func hostCandidates(for host: String) -> [String] {
        let normalized = normalizedHost(host)
        guard !normalized.isEmpty else { return [] }

        var candidates: [String] = [normalized]
        let labels = normalized.split(separator: ".").map(String.init)
        if labels.count > 2 {
            for index in 1..<(labels.count - 1) {
                let suffix = labels[index...].joined(separator: ".")
                if suffix.isEmpty { continue }
                if candidates.contains(suffix) { continue }
                candidates.append(suffix)
            }
        }
        return candidates
    }

    private func normalizedHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func cachedBearerCandidates(for host: String, now: Date) -> [BrowserDetectedCredential]? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredCacheLockedIfNeeded(now: now)
        guard let entry = bearerCache[host] else {
            return nil
        }
        guard entry.expiresAt > now else {
            bearerCache.removeValue(forKey: host)
            return nil
        }
        return entry.value
    }

    private func cacheBearerCandidates(_ candidates: [BrowserDetectedCredential], for host: String, now: Date) {
        lock.lock()
        defer { lock.unlock() }
        guard cacheTTL > 0 else {
            bearerCache.removeValue(forKey: host)
            purgeExpiredCacheLockedIfNeeded(now: now)
            return
        }
        bearerCache[host] = ExpiringCacheEntry(
            value: candidates,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )
        purgeExpiredCacheLockedIfNeeded(now: now)
    }

    private func cachedCookieHeader(for host: String, now: Date) -> BrowserDetectedCredential?? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredCacheLockedIfNeeded(now: now)
        guard let entry = cookieHeaderCache[host] else {
            return nil
        }
        guard entry.expiresAt > now else {
            cookieHeaderCache.removeValue(forKey: host)
            return nil
        }
        return entry.value
    }

    private func cacheCookieHeader(_ credential: BrowserDetectedCredential?, for host: String, now: Date) {
        lock.lock()
        defer { lock.unlock() }
        guard cacheTTL > 0 else {
            cookieHeaderCache.removeValue(forKey: host)
            purgeExpiredCacheLockedIfNeeded(now: now)
            return
        }
        cookieHeaderCache[host] = ExpiringCacheEntry(
            value: credential,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )
        purgeExpiredCacheLockedIfNeeded(now: now)
    }

    private func cachedNamedCookie(for key: String, now: Date) -> BrowserDetectedCredential?? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredCacheLockedIfNeeded(now: now)
        guard let entry = namedCookieCache[key] else {
            return nil
        }
        guard entry.expiresAt > now else {
            namedCookieCache.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    private func cacheNamedCookie(_ credential: BrowserDetectedCredential?, for key: String, now: Date) {
        lock.lock()
        defer { lock.unlock() }
        guard cacheTTL > 0 else {
            namedCookieCache.removeValue(forKey: key)
            purgeExpiredCacheLockedIfNeeded(now: now)
            return
        }
        namedCookieCache[key] = ExpiringCacheEntry(
            value: credential,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )
        purgeExpiredCacheLockedIfNeeded(now: now)
    }

    private func purgeExpiredCacheLockedIfNeeded(now: Date) {
        if let nextFullCachePurgeAt, now < nextFullCachePurgeAt {
            return
        }
        purgeExpiredCacheLocked(now: now)
        nextFullCachePurgeAt = now.addingTimeInterval(fullCachePurgeInterval)
    }

    private func purgeExpiredCacheLocked(now: Date) {
        bearerCache = bearerCache.filter { _, entry in
            entry.expiresAt > now
        }
        cookieHeaderCache = cookieHeaderCache.filter { _, entry in
            entry.expiresAt > now
        }
        namedCookieCache = namedCookieCache.filter { _, entry in
            entry.expiresAt > now
        }
    }
}
