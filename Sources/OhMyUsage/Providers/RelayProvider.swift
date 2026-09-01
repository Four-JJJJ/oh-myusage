import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class RelayProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor
    private let session: URLSession
    private let keychain: any TokenCredentialStoring
    private let browserCredentialService: any BrowserCredentialProviding
    private let registry: RelayAdapterRegistry
    private let browserRecoveryBackoffInterval: TimeInterval = 10 * 60

    // Plan §8.4: the token channel and the balance channel cache their
    // successful results independently (separate caches and key namespaces),
    // so one channel's freshness never extends to the other and a failed
    // channel is always retried while the other one is reused. TTLs follow the
    // relay fetch plan (`ProviderFetchPlanRegistry`, activeTTL 120s for the
    // whole relay family). Keys include the descriptor id, base URL, adapter
    // and an *irreversible fingerprint* of the saved credential next to the
    // keychain service/account, so switching accounts, rotating a credential
    // or re-adding a site can never reuse another account's cached data.
    private static let tokenChannelCache = ProviderValueCache<TokenChannelResult>(
        ttl: ProviderFetchPlanRegistry().plan(for: .relay).activeTTL
    )
    private static let balanceChannelCache = ProviderValueCache<AccountChannelResult>(
        ttl: ProviderFetchPlanRegistry().plan(for: .relay).activeTTL
    )

    private var credentialResolver: RelayCredentialResolver {
        RelayCredentialResolver(
            descriptor: descriptor,
            keychain: keychain,
            browserCredentialService: browserCredentialService
        )
    }
    private var recoveryPolicy: RelayRecoveryPolicy {
        RelayRecoveryPolicy(
            descriptor: descriptor,
            credentialResolver: credentialResolver,
            browserRecoveryBackoffInterval: browserRecoveryBackoffInterval
        )
    }
    private var httpClient: RelayHTTPClient {
        RelayHTTPClient(session: session)
    }
    private var tokenChannelExecutor: RelayTokenChannelExecutor {
        RelayTokenChannelExecutor(
            descriptor: descriptor,
            credentialResolver: credentialResolver,
            recoveryPolicy: recoveryPolicy,
            httpClient: httpClient
        )
    }
    private var balanceChannelExecutor: RelayBalanceChannelExecutor {
        RelayBalanceChannelExecutor(
            descriptor: descriptor,
            credentialResolver: credentialResolver,
            recoveryPolicy: recoveryPolicy,
            httpClient: httpClient,
            registry: registry
        )
    }

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: any TokenCredentialStoring,
        browserCredentialService: any BrowserCredentialProviding = BrowserCredentialService(),
        registry: RelayAdapterRegistry = .shared
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCredentialService = browserCredentialService
        self.registry = registry
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        let normalized = descriptor.normalized()
        guard let relayConfig = normalized.relayConfig else {
            throw ProviderError.unavailable("Missing relay config for \(descriptor.name)")
        }
        guard let baseURL = RelayRequestResolver.relayRootURL(from: relayConfig.baseURL) else {
            throw ProviderError.invalidResponse("invalid relay base URL")
        }
        let manifest = registry.manifest(for: relayConfig.baseURL, preferredID: relayConfig.adapterID)

        var firstError: Error?
        var tokenChannel: TokenChannelResult?
        var balanceChannel: AccountChannelResult?

        if relayConfig.tokenChannelEnabled, manifest.tokenRequest != nil {
            do {
                let cacheKey = Self.tokenChannelCacheKey(
                    descriptorID: normalized.id,
                    baseURL: baseURL,
                    adapterID: manifest.id,
                    auth: normalized.auth,
                    savedCredential: credentialResolver.readSavedCredential(auth: normalized.auth)
                )
                if !forceRefresh, let cached = Self.tokenChannelCache.value(for: cacheKey) {
                    // Plan §8.4: only request a channel when its own cached
                    // data is missing or stale; user-initiated force refresh
                    // always goes live so a re-imported credential is
                    // exercised immediately.
                    tokenChannel = cached
                } else {
                    let result = try await fetchTokenUsageChannel(
                        baseURL: baseURL,
                        relayConfig: relayConfig,
                        tokenRequest: manifest.tokenRequest!,
                        manifest: manifest,
                        forceRefresh: forceRefresh
                    )
                    Self.tokenChannelCache.store(result, for: cacheKey)
                    tokenChannel = result
                }
            } catch {
                firstError = firstError ?? error
            }
        }

        if relayConfig.balanceChannelEnabled {
            do {
                let cacheKey = Self.balanceChannelCacheKey(
                    descriptorID: normalized.id,
                    baseURL: baseURL,
                    adapterID: manifest.id,
                    auth: relayConfig.balanceAuth,
                    savedCredential: credentialResolver.readSavedCredential(auth: relayConfig.balanceAuth)
                )
                if !forceRefresh, let cached = Self.balanceChannelCache.value(for: cacheKey) {
                    balanceChannel = cached
                } else {
                    let result = try await fetchBalanceChannel(
                        baseURL: baseURL,
                        relayConfig: relayConfig,
                        manifest: manifest,
                        forceRefresh: forceRefresh
                    )
                    Self.balanceChannelCache.store(result, for: cacheKey)
                    balanceChannel = result
                }
            } catch {
                firstError = firstError ?? error
            }
        }

        guard tokenChannel != nil || balanceChannel != nil else {
            throw firstError ?? ProviderError.unavailable("No enabled data channel for \(descriptor.name)")
        }

        let remaining = balanceChannel?.remaining ?? tokenChannel?.remaining
        let used = balanceChannel?.used ?? tokenChannel?.used
        let limit = balanceChannel?.limit ?? tokenChannel?.limit
        let unit = balanceChannel?.unit ?? tokenChannel?.unit ?? "quota"

        let status: SnapshotStatus
        if let remaining {
            status = remaining <= descriptor.threshold.lowRemaining ? .warning : .ok
        } else {
            status = .ok
        }

        var noteParts: [String] = []
        var rawMeta: [String: String] = ["relay.adapterID": manifest.id]

        if let balanceChannel {
            noteParts.append(balanceChannel.note)
            for (key, value) in balanceChannel.rawMeta {
                rawMeta["account.\(key)"] = value
            }
        }

        if let tokenChannel {
            noteParts.append(tokenChannel.note)
            for (key, value) in tokenChannel.rawMeta {
                rawMeta["token.\(key)"] = value
            }
        }

        let authSource = rawMeta["account.authSource"] ?? rawMeta["token.authSource"]
        rawMeta["relay.displayMode"] = manifest.displayMode.rawValue
        let resolvedPlanType = balanceChannel?.planType
        let quotaWindows = balanceChannel?.quotaWindows ?? []

        var extras: [String: String] = [
            "relayAdapter": manifest.displayName,
            "relayDisplayMode": manifest.displayMode.rawValue
        ]
        if let resolvedPlanType {
            extras["planType"] = resolvedPlanType
            rawMeta["planType"] = resolvedPlanType
        }
        if let recoveryMeta = balanceChannel?.recoveryMeta ?? tokenChannel?.recoveryMeta {
            for (key, value) in recoveryMeta {
                rawMeta["relay.recovery.\(key)"] = value
            }
            if let source = recoveryMeta["source"] {
                extras["relayRecoverySource"] = source
            }
            if let at = recoveryMeta["at"] {
                extras["relayRecoveryAt"] = at
            }
        }
        if let savedCredentialSource = balanceChannel?.rawMeta["savedCredentialSource"]
            ?? tokenChannel?.rawMeta["savedCredentialSource"] {
            rawMeta["relay.savedCredentialSource"] = savedCredentialSource
            extras["relaySavedCredentialSource"] = savedCredentialSource
        }

        return UsageSnapshot(
            source: normalized.id,
            status: status,
            fetchHealth: .ok,
            valueFreshness: .live,
            remaining: remaining,
            used: used,
            limit: limit,
            unit: unit,
            updatedAt: Date(),
            note: noteParts.isEmpty ? "No detail" : noteParts.joined(separator: " | "),
            quotaWindows: quotaWindows,
            sourceLabel: "Third-Party",
            accountLabel: balanceChannel?.accountLabel,
            authSourceLabel: authSource,
            diagnosticCode: nil,
            extras: extras,
            rawMeta: rawMeta
        )
    }

    private func fetchTokenUsageChannel(
        baseURL: URL,
        relayConfig: RelayProviderConfig,
        tokenRequest: RelayTokenRequestManifest,
        manifest: RelayAdapterManifest,
        forceRefresh: Bool
    ) async throws -> TokenChannelResult {
        try await tokenChannelExecutor.fetch(
            baseURL: baseURL,
            relayConfig: relayConfig,
            tokenRequest: tokenRequest,
            manifest: manifest,
            forceRefresh: forceRefresh,
            browserAccessIntent: browserAccessIntent(for: forceRefresh)
        )
    }

    private func fetchBalanceChannel(
        baseURL: URL,
        relayConfig: RelayProviderConfig,
        manifest: RelayAdapterManifest,
        forceRefresh: Bool
    ) async throws -> AccountChannelResult {
        try await balanceChannelExecutor.fetch(
            baseURL: baseURL,
            relayConfig: relayConfig,
            manifest: manifest,
            forceRefresh: forceRefresh,
            browserAccessIntent: browserAccessIntent(for: forceRefresh)
        )
    }

    private func browserAccessIntent(for forceRefresh: Bool) -> BrowserCredentialAccessIntent {
        forceRefresh ? .interactiveImport : .background
    }

    // MARK: - Channel cache keys

    /// Cache key for the token channel. Namespaced per descriptor, base URL,
    /// adapter, keychain identity and an irreversible credential fingerprint,
    /// so different accounts, rotated credentials or re-added sites can never
    /// share an entry. Only the fingerprint is embedded, never the token value.
    internal static func tokenChannelCacheKey(
        descriptorID: String,
        baseURL: URL,
        adapterID: String,
        auth: AuthConfig,
        savedCredential: String?
    ) -> String {
        "relay|token|\(descriptorID)|\(baseURL.absoluteString)|\(adapterID)|\(keychainIdentityComponent(auth))|\(credentialKeyComponent(savedCredential))"
    }

    /// Cache key for the balance channel; an independent namespace from the
    /// token channel so the two caches can never collide or cross-contaminate.
    internal static func balanceChannelCacheKey(
        descriptorID: String,
        baseURL: URL,
        adapterID: String,
        auth: AuthConfig,
        savedCredential: String?
    ) -> String {
        "relay|balance|\(descriptorID)|\(baseURL.absoluteString)|\(adapterID)|\(keychainIdentityComponent(auth))|\(credentialKeyComponent(savedCredential))"
    }

    private static func keychainIdentityComponent(_ auth: AuthConfig) -> String {
        let service = auth.keychainService?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let account = auth.keychainAccount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(service.isEmpty ? "-" : service)|\(account.isEmpty ? "-" : account)"
    }

    private static func credentialKeyComponent(_ savedCredential: String?) -> String {
        let trimmed = savedCredential?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            // No saved credential (e.g. browser-first setups): the account
            // identity above still separates the cache entries.
            return "nosavedcredential"
        }
        return CredentialFingerprint.sha256Hex(trimmed)
    }

}

struct OpenTokenUsageEnvelope: Decodable {
    struct TokenUsage: Decodable {
        let expiresAt: Int?
        let name: String
        let object: String?
        let totalAvailable: Double
        let totalGranted: Double
        let totalUsed: Double
        let unlimitedQuota: Bool

        enum CodingKeys: String, CodingKey {
            case expiresAt = "expires_at"
            case name
            case object
            case totalAvailable = "total_available"
            case totalGranted = "total_granted"
            case totalUsed = "total_used"
            case unlimitedQuota = "unlimited_quota"
        }
    }

    let code: Bool?
    let message: String?
    let data: TokenUsage
}

struct OpenBillingSubscription: Decodable {
    let object: String
    let hasPaymentMethod: Bool
    let softLimitUSD: Double
    let hardLimitUSD: Double
    let systemHardLimitUSD: Double
    let accessUntil: Int

    enum CodingKeys: String, CodingKey {
        case object
        case hasPaymentMethod = "has_payment_method"
        case softLimitUSD = "soft_limit_usd"
        case hardLimitUSD = "hard_limit_usd"
        case systemHardLimitUSD = "system_hard_limit_usd"
        case accessUntil = "access_until"
    }
}

struct OpenBillingUsage: Decodable {
    let object: String
    let totalUsage: Double

    enum CodingKeys: String, CodingKey {
        case object
        case totalUsage = "total_usage"
    }
}
