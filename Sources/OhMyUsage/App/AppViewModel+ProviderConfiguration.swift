import Foundation
import OhMyUsageApplication
import OhMyUsageDomain

@MainActor
extension AppViewModel {
    func setLanguage(_ language: AppLanguage) { configurationModel.setLanguage(language) }
    func setResourceMode(_ resourceMode: ResourceMode) { configurationModel.setResourceMode(resourceMode) }
    func setLaunchAtLoginEnabled(_ enabled: Bool) { configurationModel.setLaunchAtLoginEnabled(enabled) }
    func setGlobalRefreshIntervalSeconds(_ seconds: Int) { configurationModel.setGlobalRefreshIntervalSeconds(seconds) }
    func setEnabled(_ enabled: Bool, providerID: String) { configurationModel.setEnabled(enabled, providerID: providerID) }
    func reorderEnabledProviders(family: ProviderFamily, fromOffsets: IndexSet, toOffset: Int) {
        configurationModel.reorderEnabledProviders(family: family, fromOffsets: fromOffsets, toOffset: toOffset)
    }
    func setLowThreshold(_ value: Double, providerID: String) {
        configurationModel.commitProviderThreshold(value, providerID: providerID)
    }
    func commitProviderThreshold(_ value: Double, providerID: String) {
        configurationModel.commitProviderThreshold(value, providerID: providerID)
    }
    func hasToken(for descriptor: ProviderDescriptor) -> Bool { configurationModel.hasToken(for: descriptor) }
    func savedTokenLength(for descriptor: ProviderDescriptor) -> Int? { configurationModel.savedTokenLength(for: descriptor) }
    func hasToken(auth: AuthConfig) -> Bool { configurationModel.hasToken(auth: auth) }
    func savedTokenLength(auth: AuthConfig) -> Int? { configurationModel.savedTokenLength(auth: auth) }
    func saveToken(_ token: String, for descriptor: ProviderDescriptor) -> Bool { configurationModel.saveToken(token, for: descriptor) }
    @discardableResult
    func saveTokenAndRestart(_ token: String, for descriptor: ProviderDescriptor) -> Bool { configurationModel.saveTokenAndRestart(token, for: descriptor) }
    func saveToken(_ token: String, auth: AuthConfig) -> Bool { configurationModel.saveToken(token, auth: auth) }
    @discardableResult
    func saveTokenAndRestart(_ token: String, auth: AuthConfig) -> Bool { configurationModel.saveTokenAndRestart(token, auth: auth) }
    func hasOfficialManualCookie(for provider: ProviderDescriptor) -> Bool { configurationModel.hasOfficialManualCookie(for: provider) }
    func savedOfficialManualCookieLength(for provider: ProviderDescriptor) -> Int? { configurationModel.savedOfficialManualCookieLength(for: provider) }
    func saveOfficialManualCookie(_ value: String, providerID: String) -> Bool { configurationModel.saveOfficialManualCookie(value, providerID: providerID) }
    @discardableResult
    func saveOfficialManualCookieAndRestart(_ value: String, providerID: String) -> Bool { configurationModel.saveOfficialManualCookieAndRestart(value, providerID: providerID) }
    func invalidateCredentialLookupCache() { configurationModel.invalidateCredentialLookupCache() }
    @discardableResult
    func addRelaySiteDraft(
        name: String, baseURL: String, preferredAdapterID: String? = nil, userID: String,
        credentialInput: String? = nil, balanceCredentialMode: RelayCredentialMode = .browserPreferred
    ) -> ProviderDescriptor? {
        configurationModel.addRelaySiteDraft(
            name: name, baseURL: baseURL, preferredAdapterID: preferredAdapterID, userID: userID,
            credentialInput: credentialInput, balanceCredentialMode: balanceCredentialMode
        )
    }
    func removeProvider(providerID: String) { configurationModel.removeProvider(providerID: providerID) }
    func updateOpenProviderSettings(
        providerID: String, name: String, baseURL: String, preferredAdapterID: String? = nil,
        balanceCredentialMode: RelayCredentialMode = .manualPreferred, tokenUsageEnabled: Bool,
        accountEnabled: Bool, authHeader: String, authScheme: String, userID: String,
        userIDHeader: String, endpointPath: String, remainingJSONPath: String, usedJSONPath: String,
        limitJSONPath: String, successJSONPath: String, unit: String,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil
    ) {
        configurationModel.updateOpenProviderSettings(
            providerID: providerID, name: name, baseURL: baseURL, preferredAdapterID: preferredAdapterID,
            balanceCredentialMode: balanceCredentialMode, tokenUsageEnabled: tokenUsageEnabled,
            accountEnabled: accountEnabled, authHeader: authHeader, authScheme: authScheme,
            userID: userID, userIDHeader: userIDHeader, endpointPath: endpointPath,
            remainingJSONPath: remainingJSONPath, usedJSONPath: usedJSONPath,
            limitJSONPath: limitJSONPath, successJSONPath: successJSONPath, unit: unit,
            quotaDisplayMode: quotaDisplayMode
        )
    }
    func saveRelayDraft(_ draft: RelaySettingsDraft) { configurationModel.saveRelayDraft(draft) }
    func relayDescriptorForPreview(
        providerID: String, name: String, baseURL: String, preferredAdapterID: String? = nil,
        balanceCredentialMode: RelayCredentialMode = .manualPreferred, tokenUsageEnabled: Bool,
        accountEnabled: Bool, authHeader: String, authScheme: String, userID: String,
        userIDHeader: String, endpointPath: String, remainingJSONPath: String, usedJSONPath: String,
        limitJSONPath: String, successJSONPath: String, unit: String,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil
    ) -> ProviderDescriptor? {
        configurationModel.relayDescriptorForPreview(
            providerID: providerID, name: name, baseURL: baseURL, preferredAdapterID: preferredAdapterID,
            balanceCredentialMode: balanceCredentialMode, tokenUsageEnabled: tokenUsageEnabled,
            accountEnabled: accountEnabled, authHeader: authHeader, authScheme: authScheme,
            userID: userID, userIDHeader: userIDHeader, endpointPath: endpointPath,
            remainingJSONPath: remainingJSONPath, usedJSONPath: usedJSONPath,
            limitJSONPath: limitJSONPath, successJSONPath: successJSONPath, unit: unit,
            quotaDisplayMode: quotaDisplayMode
        )
    }
    func relayDescriptorForPreview(draft: RelaySettingsDraft) -> ProviderDescriptor? { configurationModel.relayDescriptorForPreview(draft: draft) }
    func testRelayDraft(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult { await configurationModel.testRelayDraft(draft) }
    func testNewRelaySiteDraft(
        name: String, baseURL: String, preferredAdapterID: String? = nil, userID: String, credentialInput: String? = nil
    ) async -> RelayDiagnosticResult {
        await configurationModel.testNewRelaySiteDraft(
            name: name, baseURL: baseURL, preferredAdapterID: preferredAdapterID, userID: userID, credentialInput: credentialInput
        )
    }
    func importRelayDraftFromBrowser(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult { await configurationModel.importRelayDraftFromBrowser(draft) }
    func updateThirdPartyQuotaDisplayMode(providerID: String, quotaDisplayMode: OfficialQuotaDisplayMode) {
        configurationModel.updateThirdPartyQuotaDisplayMode(providerID: providerID, quotaDisplayMode: quotaDisplayMode)
    }
    func relayAdapterName(for provider: ProviderDescriptor) -> String? { configurationModel.relayAdapterName(for: provider) }
    func relayAuthSource(for providerID: String) -> String? { configurationModel.relayAuthSource(for: providerID) }
    func relayFetchHealth(for providerID: String) -> FetchHealth? { configurationModel.relayFetchHealth(for: providerID) }
    func relayValueFreshness(for providerID: String) -> ValueFreshness? { configurationModel.relayValueFreshness(for: providerID) }
    func testRelayConnection(providerID: String) async -> RelayDiagnosticResult { await configurationModel.testRelayConnection(providerID: providerID) }
    func testRelayConnection(descriptor: ProviderDescriptor) async -> RelayDiagnosticResult { await configurationModel.testRelayConnection(descriptor: descriptor) }
    func updateOfficialProviderSettings(
        providerID: String, sourceMode: OfficialSourceMode, webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) {
        configurationModel.updateOfficialProviderSettings(
            providerID: providerID, sourceMode: sourceMode, webMode: webMode,
            quotaDisplayMode: quotaDisplayMode, traeValueDisplayMode: traeValueDisplayMode
        )
    }
    func saveOfficialDraft(_ draft: OfficialSettingsDraft) { configurationModel.saveOfficialDraft(draft) }
    @discardableResult
    func saveOfficialCredentialAndSettings(
        providerID: String, credentialInput: String?, manualCookieInput: String?,
        sourceMode: OfficialSourceMode, webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) -> Bool {
        configurationModel.saveOfficialCredentialAndSettings(
            providerID: providerID, credentialInput: credentialInput, manualCookieInput: manualCookieInput,
            sourceMode: sourceMode, webMode: webMode, quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode
        )
    }
    @discardableResult
    func persistConfiguration(showFeedback: Bool = false, successText: String? = nil) -> Bool {
        configurationModel.persistConfiguration(showFeedback: showFeedback, successText: successText)
    }
    @discardableResult
    func resetConfiguration(showFeedback: Bool = false) -> Bool { configurationModel.resetConfiguration(showFeedback: showFeedback) }
    @discardableResult
    func applyConfigurationPersistenceOutcome(_ outcome: AppConfigurationPersistenceOutcome) -> Bool {
        configurationModel.applyConfigurationPersistenceOutcome(outcome)
    }
    func pruneThirdPartyBalanceBaselines() { configurationModel.pruneThirdPartyBalanceBaselines() }
    func displayNameForDiscovery(_ descriptor: ProviderDescriptor) -> String { configurationModel.displayNameForDiscovery(descriptor) }
    func descriptor(for id: String) -> ProviderDescriptor? { configurationModel.descriptor(for: id) }
}
