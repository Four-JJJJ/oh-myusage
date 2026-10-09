import Foundation
import OhMyUsageDomain

enum RelaySettingsDraftBuilder {
    static func build(seed: RelaySettingsDraftSeed, inputs: RelayProviderEditorDraft, name: String, baseURL: String) -> RelaySettingsDraft {
        return RelaySettingsDraft(
            providerID: seed.providerID,
            name: name,
            baseURL: baseURL,
            preferredAdapterID: seed.preferredAdapterID,
            balanceCredentialMode: inputs.relayCredentialModeInputs[seed.providerID] ?? seed.balanceCredentialMode,
            tokenUsageEnabled: inputs.tokenUsageEnabledInputs[seed.providerID] ?? seed.tokenUsageEnabled,
            accountEnabled: inputs.accountEnabledInputs[seed.providerID] ?? seed.accountEnabled,
            authHeader: inputs.authHeaderInputs[seed.providerID] ?? seed.authHeader,
            authScheme: inputs.authSchemeInputs[seed.providerID] ?? seed.authScheme,
            userID: inputs.userIDInputs[seed.providerID] ?? seed.userID,
            userIDHeader: inputs.userHeaderInputs[seed.providerID] ?? seed.userIDHeader,
            endpointPath: inputs.endpointPathInputs[seed.providerID] ?? seed.endpointPath,
            remainingJSONPath: inputs.remainingPathInputs[seed.providerID] ?? seed.remainingJSONPath,
            usedJSONPath: inputs.usedPathInputs[seed.providerID] ?? seed.usedJSONPath,
            limitJSONPath: inputs.limitPathInputs[seed.providerID] ?? seed.limitJSONPath,
            successJSONPath: inputs.successPathInputs[seed.providerID] ?? seed.successJSONPath,
            unit: inputs.unitInputs[seed.providerID] ?? seed.unit,
            quotaDisplayMode: inputs.thirdPartyQuotaDisplayModeInputs[seed.providerID] ?? seed.quotaDisplayMode,
            showExpirationTimeInMenuBar: inputs.relayShowExpirationTimeInputs[seed.providerID]
                ?? seed.showExpirationTimeInMenuBar
        )
    }
}
