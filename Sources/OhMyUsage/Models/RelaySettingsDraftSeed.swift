import Foundation
import OhMyUsageDomain

struct RelaySettingsDraftSeed: Equatable {
    var providerID: String
    var name: String
    var baseURL: String
    var preferredAdapterID: String
    var balanceCredentialMode: RelayCredentialMode
    var tokenUsageEnabled: Bool
    var accountEnabled: Bool
    var authHeader: String
    var authScheme: String
    var userID: String
    var userIDHeader: String
    var endpointPath: String
    var remainingJSONPath: String
    var usedJSONPath: String
    var limitJSONPath: String
    var successJSONPath: String
    var unit: String
    var quotaDisplayMode: OfficialQuotaDisplayMode
    var showExpirationTimeInMenuBar: Bool

    init(
        provider: ProviderDescriptor,
        preferredAdapterID: String? = nil,
        adapter: RelayProviderDescriptorModelAdapter = .live,
        manifest explicitManifest: RelayAdapterManifest? = nil
    ) {
        let configuredAdapterID = preferredAdapterID ?? provider.relayConfig?.adapterID
        let resolvedBaseURL = provider.baseURL ?? provider.relayConfig?.baseURL ?? ""
        let manifest = explicitManifest
            ?? adapter.manifest(
                for: resolvedBaseURL,
                preferredID: configuredAdapterID
            )
        let selectedAdapterID = configuredAdapterID ?? manifest.id
        let relayViewConfig = provider.relayConfig.map {
            adapter.viewConfig(for: $0, manifest: manifest)
        }
        let account = relayViewConfig?.accountBalance

        self.providerID = provider.id
        self.name = provider.name
        self.baseURL = resolvedBaseURL
        self.preferredAdapterID = selectedAdapterID
        self.balanceCredentialMode = provider.relayConfig?.balanceCredentialMode ?? .manualPreferred
        self.tokenUsageEnabled = relayViewConfig?.tokenUsageEnabled ?? manifest.match.defaultTokenChannelEnabled
        self.accountEnabled = account?.enabled ?? manifest.match.defaultBalanceChannelEnabled
        self.authHeader = account?.authHeader ?? manifest.balanceRequest.authHeader ?? "Authorization"
        self.authScheme = account?.authScheme ?? manifest.balanceRequest.authScheme ?? "Bearer"
        self.userID = account?.userID ?? manifest.balanceRequest.userID ?? ""
        self.userIDHeader = account?.userIDHeader ?? manifest.balanceRequest.userIDHeader ?? "New-Api-User"
        self.endpointPath = account?.endpointPath ?? manifest.balanceRequest.path
        self.remainingJSONPath = account?.remainingJSONPath ?? manifest.extract.remaining
        self.usedJSONPath = account?.usedJSONPath ?? manifest.extract.used ?? ""
        self.limitJSONPath = account?.limitJSONPath ?? manifest.extract.limit ?? ""
        self.successJSONPath = account?.successJSONPath ?? manifest.extract.success ?? ""
        self.unit = account?.unit ?? manifest.extract.unit ?? "quota"
        self.quotaDisplayMode = provider.relayConfig?.quotaDisplayMode ?? .remaining
        self.showExpirationTimeInMenuBar = provider.relayConfig?.showExpirationTimeInMenuBar ?? true
    }

    var draft: RelaySettingsDraft {
        RelaySettingsDraft(
            providerID: providerID,
            name: name,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID,
            balanceCredentialMode: balanceCredentialMode,
            tokenUsageEnabled: tokenUsageEnabled,
            accountEnabled: accountEnabled,
            authHeader: authHeader,
            authScheme: authScheme,
            userID: userID,
            userIDHeader: userIDHeader,
            endpointPath: endpointPath,
            remainingJSONPath: remainingJSONPath,
            usedJSONPath: usedJSONPath,
            limitJSONPath: limitJSONPath,
            successJSONPath: successJSONPath,
            unit: unit,
            quotaDisplayMode: quotaDisplayMode,
            showExpirationTimeInMenuBar: showExpirationTimeInMenuBar
        )
    }
}
