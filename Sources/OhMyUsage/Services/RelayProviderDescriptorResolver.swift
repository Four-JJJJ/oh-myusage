import Foundation
import OhMyUsageDomain

struct RelayProviderDescriptorResolver {
    private let registry: RelayAdapterRegistry

    init(registry: RelayAdapterRegistry = .shared) {
        self.registry = registry
    }

    func manifest(for provider: ProviderDescriptor) -> RelayAdapterManifest? {
        guard provider.isRelay else { return nil }
        let resolvedBaseURL = provider.relayConfig?.baseURL ?? provider.baseURL ?? ""
        return manifest(for: resolvedBaseURL, preferredID: provider.relayConfig?.adapterID)
    }

    func manifest(for baseURL: String, preferredID: String? = nil) -> RelayAdapterManifest {
        registry.manifest(for: baseURL, preferredID: preferredID)
    }

    func adapterID(for baseURL: String, preferredID: String? = nil) -> String {
        manifest(for: baseURL, preferredID: preferredID).id
    }

    func displayMode(for provider: ProviderDescriptor) -> RelayDisplayMode {
        manifest(for: provider)?.displayMode ?? .balance
    }

    func viewConfig(for provider: ProviderDescriptor) -> OpenProviderConfig? {
        guard let relayConfig = provider.relayConfig else { return nil }
        let manifest = manifest(for: provider) ?? manifest(for: relayConfig.baseURL, preferredID: relayConfig.adapterID)
        return viewConfig(for: relayConfig, manifest: manifest)
    }

    func viewConfig(
        for relayConfig: RelayProviderConfig,
        manifest: RelayAdapterManifest
    ) -> OpenProviderConfig {
        let request = manifest.balanceRequest
        let extract = manifest.extract
        let override = relayConfig.manualOverrides
        return OpenProviderConfig(
            tokenUsageEnabled: relayConfig.tokenChannelEnabled,
            accountBalance: RelayAccountBalanceConfig(
                enabled: relayConfig.balanceChannelEnabled,
                auth: relayConfig.balanceAuth,
                authHeader: override?.authHeader ?? request.authHeader ?? "Authorization",
                authScheme: override?.authScheme ?? request.authScheme ?? "Bearer",
                requestMethod: override?.requestMethod ?? request.method,
                requestBodyJSON: override?.requestBodyJSON ?? request.bodyJSON,
                endpointPath: override?.endpointPath ?? request.path,
                userID: override?.userID ?? request.userID,
                userIDHeader: override?.userIDHeader ?? request.userIDHeader ?? "New-Api-User",
                remainingJSONPath: override?.remainingExpression ?? extract.remaining,
                usedJSONPath: override?.usedExpression ?? extract.used,
                limitJSONPath: override?.limitExpression ?? extract.limit,
                successJSONPath: override?.successExpression ?? extract.success,
                unit: override?.unitExpression ?? extract.unit ?? "quota"
            )
        )
    }

    func defaultRelayConfig(
        id: String,
        baseURL: String?,
        preferredAdapterID: String? = nil,
        auth: AuthConfig = AuthConfig.none,
        legacyOpenConfig: OpenProviderConfig? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> RelayProviderConfig {
        let normalizedBaseURL = ProviderDescriptor.normalizeRelayBaseURL(baseURL ?? "")
        let adapterID = defaultRelayAdapterID(
            id: id,
            baseURL: normalizedBaseURL,
            legacyOpenConfig: legacyOpenConfig,
            preferredAdapterID: preferredAdapterID
        )
        let manifest = manifest(for: normalizedBaseURL, preferredID: adapterID)
        let legacyAccount = legacyOpenConfig?.accountBalance?.auth
        return RelayProviderConfig(
            adapterID: manifest.id,
            baseURL: normalizedBaseURL,
            tokenChannelEnabled: legacyOpenConfig?.tokenUsageEnabled ?? manifest.match.defaultTokenChannelEnabled,
            balanceChannelEnabled: legacyOpenConfig?.accountBalance?.enabled ?? manifest.match.defaultBalanceChannelEnabled,
            balanceAuth: (legacyAccount ?? AuthConfig(kind: .bearer)).withFallback(
                service: auth.keychainService ?? keychainService,
                account: defaultRelayBalanceAccount(
                    id: id,
                    baseURL: normalizedBaseURL,
                    adapterID: manifest.id
                )
            ),
            balanceCredentialMode: .manualPreferred,
            quotaDisplayMode: defaultRelayQuotaDisplayMode(adapterID: manifest.id),
            manualOverrides: manualOverrides(from: legacyOpenConfig)
        )
    }

    func defaultRelayBalanceAccount(
        id: String,
        baseURL: String?,
        adapterID: String
    ) -> String {
        let normalized = ProviderDescriptor.normalizeRelayBaseURL(baseURL ?? "")
        let host = URL(string: normalized)?.host ?? id
        let officialRelayMetadata = OfficialRelayMetadataCatalog.metadata(forAdapterID: adapterID)
        let isOfficialRelayBaseURL = officialRelayMetadata.map {
            ProviderDescriptor.normalizeRelayBaseURL($0.baseURL).lowercased() == normalized.lowercased()
        } ?? false
        if isOfficialRelayBaseURL, let keychainAccount = officialRelayMetadata?.keychainAccount {
            return keychainAccount
        }
        switch adapterID {
        case "ailinyu":
            return "open.ailinyu.de/session-cookie"
        case "dragoncode":
            return "dragoncode.codes/auth_token"
        case "hongmacc":
            return "hongmacc.com/auth_token"
        default:
            return "\(host)/system-access-token"
        }
    }

    private func manualOverrides(from legacyOpenConfig: OpenProviderConfig?) -> RelayManualOverride? {
        guard let legacy = legacyOpenConfig?.accountBalance else { return nil }
        let overrides = RelayManualOverride(
            authHeader: legacy.authHeader,
            authScheme: legacy.authScheme,
            userID: legacy.userID,
            userIDHeader: legacy.userIDHeader,
            requestMethod: legacy.requestMethod,
            requestBodyJSON: legacy.requestBodyJSON,
            endpointPath: legacy.endpointPath,
            remainingExpression: legacy.remainingJSONPath,
            usedExpression: legacy.usedJSONPath,
            limitExpression: legacy.limitJSONPath,
            successExpression: legacy.successJSONPath,
            unitExpression: legacy.unit,
            accountLabelExpression: nil,
            staticHeaders: nil
        )
        return overrides.isEmpty ? nil : overrides
    }

    private func defaultRelayAdapterID(
        id: String,
        baseURL: String,
        legacyOpenConfig: OpenProviderConfig?,
        preferredAdapterID: String? = nil
    ) -> String? {
        if let preferredAdapterID = preferredAdapterID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferredAdapterID.isEmpty {
            return preferredAdapterID
        }
        if id == "open-ailinyu" {
            return "ailinyu"
        }
        if id == "dragoncode" {
            return "dragoncode"
        }
        if id == "hongmacc" {
            return "hongmacc"
        }
        if let metadata = OfficialRelayMetadataCatalog.metadata(forProviderID: id) {
            return metadata.defaultAdapterID
        }
        if let account = legacyOpenConfig?.accountBalance?.auth.keychainAccount?.lowercased() {
            if account.contains("open.ailinyu.de") {
                return "ailinyu"
            }
            if account.contains("dragoncode.codes") {
                return "dragoncode"
            }
            if account.contains("hongmacc.com") {
                return "hongmacc"
            }
            if account.contains("xiaomimimo.com") {
                return "xiaomimimo"
            }
            if account.contains("moonshot.cn") {
                return "moonshot"
            }
        }
        return manifest(for: baseURL).id
    }

    private func defaultRelayQuotaDisplayMode(adapterID: String) -> OfficialQuotaDisplayMode {
        adapterID == "xiaomimimo-token-plan" ? .used : .remaining
    }
}
