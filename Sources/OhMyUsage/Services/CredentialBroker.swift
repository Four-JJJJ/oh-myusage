import Foundation

/// Coarse-grained authorization state for the app's own secure credential store.
/// Mirrors the fixed copy set used by the permission UI:
/// notConfigured(未配置) / ready(已准备，可后台读取) / systemAccessRequired(系统拒绝访问).
/// `expired` and `blocked` are reserved for OAuth refresh and browser session failures.
enum CredentialAccessState: Equatable, Sendable {
    case notConfigured
    case ready
    case systemAccessRequired
    case expired
    case blocked
}

/// Outcome of the single interactive secure-store preparation entry point.
struct CredentialPreparationResult: Equatable, Sendable {
    let succeeded: Bool
    let state: CredentialAccessState
}

/// Shared, synchronous credential access broker.
///
/// Single choke point in front of `KeychainService`:
/// - `prepareSecureStoreAccess()` is the only interactive entry point.
/// - `readToken` is always a non-interactive background read (per-key in-flight merge).
/// - Successful credentials are short-TTL cached in memory; missing credentials get a
///   short negative cache so repeated misses do not hammer the keychain.
/// - `saveToken` / `deleteToken` update the caches immediately.
/// - Never logs credential values or any reversible content.
///
/// Deliberately a `final class` with `NSLock` (not an actor): the provider ports
/// (`TokenCredentialStoring` / `CredentialStoring`) are synchronous protocols.
final class CredentialBroker: @unchecked Sendable {
    private struct CacheEntry {
        let token: String
        let expiresAt: Date
    }

    /// Broadcast completion for any number of waiters joining one in-flight call.
    private final class InFlight<T> {
        private let condition = NSCondition()
        private var done = false
        private var stored: T?

        init(_ placeholder: T) {
            stored = placeholder
        }

        func wait() -> T {
            condition.lock()
            while !done {
                condition.wait()
            }
            defer { condition.unlock() }
            // `complete` always stores a value before flipping `done`.
            return stored!
        }

        func complete(_ value: T) {
            condition.lock()
            stored = value
            done = true
            condition.broadcast()
            condition.unlock()
        }
    }

    private let lock = NSLock()
    private let keychain: KeychainService
    private let successCacheTTL: TimeInterval
    private let negativeCacheTTL: TimeInterval
    private let now: @Sendable () -> Date
    private var successCache: [String: CacheEntry] = [:]
    private var negativeCache: [String: Date] = [:]
    private var inFlightReads: [String: InFlight<String?>] = [:]
    private var prepareInFlight: InFlight<CredentialPreparationResult>?
    private var preparedState: CredentialAccessState = .notConfigured

    init(
        keychain: KeychainService,
        successCacheTTL: TimeInterval = 120,
        negativeCacheTTL: TimeInterval = 8,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keychain = keychain
        self.successCacheTTL = max(0, successCacheTTL)
        self.negativeCacheTTL = max(0, negativeCacheTTL)
        self.now = now
    }

    // MARK: - Interactive preparation (single entry point)

    /// Interactive secure-store preparation. Concurrent callers join the in-flight
    /// preparation so the underlying interactive keychain access runs at most once.
    func prepareSecureStoreAccess() -> CredentialPreparationResult {
        lock.lock()
        if let inFlight = prepareInFlight {
            lock.unlock()
            return inFlight.wait()
        }
        let inFlight = InFlight(CredentialPreparationResult(succeeded: false, state: .notConfigured))
        prepareInFlight = inFlight
        lock.unlock()

        let succeeded = keychain.prepareSecureStoreAccess()

        let result: CredentialPreparationResult
        lock.lock()
        if succeeded {
            // Preparation may have migrated previously-missing credentials into the
            // vault, so stale negative entries must not keep hiding them.
            negativeCache.removeAll()
            preparedState = .ready
            result = CredentialPreparationResult(succeeded: true, state: .ready)
        } else {
            preparedState = .systemAccessRequired
            result = CredentialPreparationResult(succeeded: false, state: .systemAccessRequired)
        }
        prepareInFlight = nil
        lock.unlock()
        inFlight.complete(result)
        return result
    }

    // MARK: - Background reads (always non-interactive)

    /// Non-interactive credential read with in-flight merge and TTL caches.
    func readToken(service: String, account: String) -> String? {
        let normalizedService = normalizedServiceName(service)
        let normalizedAccount = normalizedAccountName(account)
        let key = cacheKey(service: normalizedService, account: normalizedAccount)
        let timestamp = now()

        lock.lock()
        if let entry = successCache[key], entry.expiresAt > timestamp {
            lock.unlock()
            return entry.token
        }
        if let expiresAt = negativeCache[key], expiresAt > timestamp {
            lock.unlock()
            return nil
        }
        if let inFlight = inFlightReads[key] {
            lock.unlock()
            return inFlight.wait()
        }
        let inFlight = InFlight(String?.none)
        inFlightReads[key] = inFlight
        lock.unlock()

        let token = keychain.readToken(service: normalizedService, account: normalizedAccount)

        lock.lock()
        inFlightReads[key] = nil
        let timestampAfterRead = now()
        if let token, !token.isEmpty {
            successCache[key] = CacheEntry(
                token: token,
                expiresAt: timestampAfterRead.addingTimeInterval(successCacheTTL)
            )
            negativeCache[key] = nil
        } else {
            successCache[key] = nil
            negativeCache[key] = timestampAfterRead.addingTimeInterval(negativeCacheTTL)
        }
        pruneExpiredEntriesLocked(now: timestampAfterRead)
        lock.unlock()

        inFlight.complete(token)
        return token
    }

    // MARK: - Writes (cache updated immediately)

    @discardableResult
    func saveToken(_ token: String, service: String, account: String) -> Bool {
        let normalizedService = normalizedServiceName(service)
        let normalizedAccount = normalizedAccountName(account)
        let key = cacheKey(service: normalizedService, account: normalizedAccount)
        let ok = keychain.saveToken(token, service: normalizedService, account: normalizedAccount)

        lock.lock()
        if ok {
            successCache[key] = CacheEntry(
                token: token,
                expiresAt: now().addingTimeInterval(successCacheTTL)
            )
            negativeCache[key] = nil
        }
        lock.unlock()
        return ok
    }

    @discardableResult
    func deleteToken(service: String, account: String) -> Bool {
        let normalizedService = normalizedServiceName(service)
        let normalizedAccount = normalizedAccountName(account)
        let key = cacheKey(service: normalizedService, account: normalizedAccount)
        let ok = keychain.deleteToken(service: normalizedService, account: normalizedAccount)

        lock.lock()
        successCache[key] = nil
        if ok {
            negativeCache[key] = now().addingTimeInterval(negativeCacheTTL)
        }
        lock.unlock()
        return ok
    }

    // MARK: - Access state

    func accessState(service: String, account: String) -> CredentialAccessState {
        // 与读写路径一致先做规范化，旧 service 名才能命中同一份缓存。
        let key = cacheKey(
            service: normalizedServiceName(service),
            account: normalizedAccountName(account)
        )
        let timestamp = now()

        lock.lock()
        defer { lock.unlock() }
        if let entry = successCache[key], entry.expiresAt > timestamp {
            return .ready
        }
        if let expiresAt = negativeCache[key], expiresAt > timestamp {
            return .notConfigured
        }
        return preparedState == .ready ? .ready : preparedState
    }

    // MARK: - Cache invalidation

    /// Clears cached lookup state. `nil` service clears every service; `nil` account
    /// clears every account of the given (normalized) service.
    func invalidateCache(service: String?, account: String?) {
        lock.lock()
        defer { lock.unlock() }
        switch (service, account) {
        case (nil, nil):
            successCache.removeAll()
            negativeCache.removeAll()
        case (.some(let service), .some(let account)):
            let key = cacheKey(service: service, account: account)
            successCache[key] = nil
            negativeCache[key] = nil
        case (.some(let service), nil):
            let prefix = "\(normalizedServiceName(service))::"
            successCache = successCache.filter { !$0.key.hasPrefix(prefix) }
            negativeCache = negativeCache.filter { !$0.key.hasPrefix(prefix) }
        case (nil, .some(let account)):
            let suffix = "::\(normalizedAccountName(account))"
            successCache = successCache.filter { !$0.key.hasSuffix(suffix) }
            negativeCache = negativeCache.filter { !$0.key.hasSuffix(suffix) }
        }
    }

    // MARK: - Normalization (mirrors KeychainService)

    private func cacheKey(service: String, account: String) -> String {
        "\(service)::\(account)"
    }

    private func normalizedServiceName(_ service: String) -> String {
        let trimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || KeychainService.isLegacyServiceName(trimmed) {
            return KeychainService.defaultServiceName
        }
        return trimmed
    }

    private func normalizedAccountName(_ account: String) -> String {
        account.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pruneExpiredEntriesLocked(now timestamp: Date) {
        successCache = successCache.filter { $0.value.expiresAt > timestamp }
        negativeCache = negativeCache.filter { $0.value > timestamp }
    }
}
