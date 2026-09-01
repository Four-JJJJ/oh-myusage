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
