import Foundation
import OhMyUsageDomain

struct RelayDescriptorPreviewBuilder {
    func build(draft: RelaySettingsDraft, providers: [ProviderDescriptor]) -> ProviderDescriptor? {
        guard let idx = providers.firstIndex(where: { $0.id == draft.providerID }),
              providers[idx].isRelay else {
            return nil
        }

        var provider = providers[idx]
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            provider.name = trimmedName
        }

        let normalizedBaseURL = ProviderDescriptor.normalizeRelayBaseURL(
            draft.baseURL.isEmpty ? (provider.baseURL ?? "") : draft.baseURL
        )
        provider.baseURL = normalizedBaseURL

        let normalizedProvider = provider.normalized()
        let matchedManifest = RelayAdapterRegistry.shared.manifest(
            for: normalizedBaseURL,
            preferredID: trimmedOrNil(draft.preferredAdapterID)
        )
        var relayConfig = normalizedProvider.relayConfig ?? ProviderDescriptor.makeOpenRelay(
            name: provider.name,
            baseURL: normalizedBaseURL,
            preferredAdapterID: trimmedOrNil(draft.preferredAdapterID)
        ).relayConfig!
        relayConfig.baseURL = normalizedBaseURL
        relayConfig.adapterID = matchedManifest.id
        relayConfig.tokenChannelEnabled = draft.tokenUsageEnabled
        relayConfig.balanceChannelEnabled = draft.accountEnabled
        relayConfig.balanceCredentialMode = draft.balanceCredentialMode
        relayConfig.quotaDisplayMode = draft.quotaDisplayMode
        relayConfig.showExpirationTimeInMenuBar = draft.showExpirationTimeInMenuBar

        let templateRequest = matchedManifest.balanceRequest
        let templateExtract = matchedManifest.extract
        let resolvedAuthHeader = templateRequest.authHeader ?? "Authorization"
        let resolvedAuthScheme = templateRequest.authScheme ?? "Bearer"
        let resolvedUserID = trimmedOrNil(draft.userID) ?? templateRequest.userID
        let resolvedUserIDHeader = templateRequest.userIDHeader ?? "New-Api-User"
        let resolvedRequestMethod = templateRequest.method
        let resolvedRequestBody = templateRequest.bodyJSON
        let resolvedEndpointPath = templateRequest.path
        let resolvedRemaining = templateExtract.remaining
        let resolvedUsed = templateExtract.used
        let resolvedLimit = templateExtract.limit
        let resolvedSuccess = templateExtract.success
        let resolvedUnit = templateExtract.unit ?? "USD"

        relayConfig.manualOverrides = RelayManualOverride(
            authHeader: resolvedAuthHeader,
            authScheme: resolvedAuthScheme,
            userID: resolvedUserID,
            userIDHeader: resolvedUserIDHeader,
            requestMethod: resolvedRequestMethod,
            requestBodyJSON: resolvedRequestBody,
            endpointPath: resolvedEndpointPath,
            remainingExpression: resolvedRemaining,
            usedExpression: resolvedUsed,
            limitExpression: resolvedLimit,
            successExpression: resolvedSuccess,
            unitExpression: resolvedUnit,
            accountLabelExpression: relayConfig.manualOverrides?.accountLabelExpression,
            staticHeaders: templateRequest.headers
        )
        provider.relayConfig = relayConfig
        provider.openConfig = nil
        return provider.normalized()
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
