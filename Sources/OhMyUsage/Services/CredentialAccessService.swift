import Foundation

@MainActor
final class CredentialAccessService {
    private let keychain: KeychainService
    private let credentialBroker: CredentialBroker
    private var lookupInFlight: Set<String> = []
    private var lookupMissingKeys: Set<String> = []

    init(keychain: KeychainService, credentialBroker: CredentialBroker? = nil) {
        self.keychain = keychain
        self.credentialBroker = credentialBroker ?? CredentialBroker(keychain: keychain)
    }

    var debugLookupInFlightCount: Int {
        lookupInFlight.count
    }

    var debugMissingKeyCount: Int {
        lookupMissingKeys.count
    }

    func savedCredentialLength(
        service: String?,
        account: String?,
        secureStorageReady: Bool,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Int? {
        _ = secureStorageReady
        _ = onLookupStateChanged
        guard let service,
              let account,
              !service.isEmpty,
              !account.isEmpty else {
            return nil
        }
        return keychain.cachedCredentialLength(service: service, account: account)
    }

    func credentialExists(
        service: String?,
        account: String?,
        secureStorageReady: Bool,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) -> Bool {
        savedCredentialLength(
            service: service,
            account: account,
            secureStorageReady: secureStorageReady,
            onLookupStateChanged: onLookupStateChanged
        ) != nil
    }

    /// Credential writes go through the shared `CredentialBroker` so settings-page
    /// saves and provider reads observe the same cache in one place.
    func saveCredential(_ value: String, service: String, account: String) -> Bool {
        let ok = credentialBroker.saveToken(value, service: service, account: account)
        if ok {
            markLookupCached(service: service, account: account)
        }
        return ok
    }

    /// Credential deletions go through the shared `CredentialBroker` too, so a
    /// deletion is immediately visible to providers and settings lookups.
    @discardableResult
    func deleteCredential(service: String, account: String) -> Bool {
        let ok = credentialBroker.deleteToken(service: service, account: account)
        if ok {
            markLookupCached(service: service, account: account)
        }
        return ok
    }

    /// Deletes every credential entry the shared store knows about (metadata and
    /// non-interactive enumeration only — other apps' keychain items are never
    /// touched) plus any extra explicit targets. Returns true when every
    /// underlying deletion succeeded.
    ///
    /// Each deletion goes through the broker's `deleteToken`, so the broker's
    /// success/negative caches stay consistent and the vault data is really
    /// removed, not just hidden.
    func deleteAllCredentials(
        extraServiceAccounts: [(service: String, account: String)] = []
    ) -> Bool {
        var identifiers = Set(keychain.storedCredentialIdentifiers())
        for target in extraServiceAccounts {
            identifiers.insert("\(target.service)::\(target.account)")
        }

        var allDeleted = true
        for identifier in identifiers.sorted() {
            // Identifier format is "<service>::<account>"; the normalized service
            // name never contains the separator, so the first split is the service.
            guard let separatorRange = identifier.range(of: "::") else { continue }
            let service = String(identifier[identifier.startIndex..<separatorRange.lowerBound])
            let account = String(identifier[separatorRange.upperBound...])
            if !credentialBroker.deleteToken(service: service, account: account) {
                allDeleted = false
            }
        }

        lookupInFlight.removeAll()
        lookupMissingKeys.removeAll()
        credentialBroker.invalidateCache(service: nil, account: nil)
        return allDeleted
    }

    /// Coarse, non-interactive access state for one credential slot, mapped from
    /// the shared broker into the fixed status copy set (doc 7.5).
    func credentialAccessState(service: String?, account: String?) -> CredentialAccessState {
        guard let service,
              let account,
              !service.isEmpty,
              !account.isEmpty else {
            return .notConfigured
        }
        return credentialBroker.accessState(service: service, account: account)
    }

    func resetAllStoredCredentials() {
        lookupInFlight.removeAll()
        lookupMissingKeys.removeAll()
        credentialBroker.invalidateCache(service: nil, account: nil)
        keychain.resetAllStoredCredentials()
    }

    func invalidateLookupCache() {
        lookupInFlight.removeAll()
        lookupMissingKeys.removeAll()
        credentialBroker.invalidateCache(service: nil, account: nil)
    }

    private func scheduleLookup(
        service: String,
        account: String,
        onLookupStateChanged: @escaping @MainActor () -> Void
    ) {
        let key = cacheKey(service: service, account: account)
        guard !lookupInFlight.contains(key),
              !lookupMissingKeys.contains(key) else {
            return
        }
        lookupInFlight.insert(key)

        let keychain = self.keychain
        Task { @MainActor [weak self, keychain, service, account, key] in
            let token = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let token = keychain.readToken(service: service, account: account)
                    continuation.resume(returning: token)
                }
            }
            guard let self, !Task.isCancelled else { return }
            lookupInFlight.remove(key)
            if let token, !token.isEmpty {
                lookupMissingKeys.remove(key)
                onLookupStateChanged()
            } else {
                lookupMissingKeys.insert(key)
            }
        }
    }

    private func markLookupCached(service: String, account: String) {
        let key = cacheKey(service: service, account: account)
        lookupInFlight.remove(key)
        lookupMissingKeys.remove(key)
    }

    private func cacheKey(service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}
