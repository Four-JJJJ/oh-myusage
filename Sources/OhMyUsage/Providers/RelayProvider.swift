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
                tokenChannel = try await fetchTokenUsageChannel(
                    baseURL: baseURL,
                    relayConfig: relayConfig,
                    tokenRequest: manifest.tokenRequest!,
                    manifest: manifest,
                    forceRefresh: forceRefresh
                )
            } catch {
                firstError = firstError ?? error
            }
        }

        if relayConfig.balanceChannelEnabled {
            do {
                balanceChannel = try await fetchBalanceChannel(
                    baseURL: baseURL,
                    relayConfig: relayConfig,
                    manifest: manifest,
                    forceRefresh: forceRefresh
                )
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
