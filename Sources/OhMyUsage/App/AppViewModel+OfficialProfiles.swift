import Foundation
import OhMyUsageDomain

@MainActor
extension AppViewModel {
    func codexSlotViewModels() -> [CodexSlotViewModel] {
        officialProfilesModel.codexSlotViewModels()
    }

    func codexSlotViewModelsForSettings() -> [CodexSlotViewModel] {
        officialProfilesModel.codexSlotViewModelsForSettings()
    }

    func codexProfilesForSettings() -> [CodexAccountProfile] {
        officialProfilesModel.codexProfilesForSettings()
    }

    func nextCodexProfileSlotID() -> CodexSlotID {
        officialProfilesModel.nextCodexProfileSlotID()
    }

    func codexSettingsTitle(for slotID: CodexSlotID) -> String {
        officialProfilesModel.codexSettingsTitle(for: slotID)
    }

    func oauthImportState(for providerType: ProviderType) -> OAuthImportState? {
        officialProfilesModel.oauthImportState(for: providerType)
    }

    func claudeOAuthImportEnabled() -> Bool {
        officialProfilesModel.claudeOAuthImportEnabled()
    }

    func setClaudeOAuthImportEnabled(_ enabled: Bool) {
        officialProfilesModel.setClaudeOAuthImportEnabled(enabled)
    }

    func startOAuthImport(providerType: ProviderType, slotID: CodexSlotID) {
        officialProfilesModel.startOAuthImport(providerType: providerType, slotID: slotID)
    }

    func cancelOAuthImport(providerType: ProviderType) {
        officialProfilesModel.cancelOAuthImport(providerType: providerType)
    }

    func saveCodexProfile(slotID: CodexSlotID, displayName: String, note: String?, authJSON: String) -> String {
        officialProfilesModel.saveCodexProfile(
            slotID: slotID,
            displayName: displayName,
            note: note,
            authJSON: authJSON
        )
    }

    func removeCodexProfile(slotID: CodexSlotID) {
        officialProfilesModel.removeCodexProfile(slotID: slotID)
    }

    func claudeSlotViewModels() -> [ClaudeSlotViewModel] {
        officialProfilesModel.claudeSlotViewModels()
    }

    func claudeSlotViewModelsForSettings() -> [ClaudeSlotViewModel] {
        officialProfilesModel.claudeSlotViewModelsForSettings()
    }

    func claudeProfilesForSettings() -> [ClaudeAccountProfile] {
        officialProfilesModel.claudeProfilesForSettings()
    }

    func refreshSettingsProfileState() {
        officialProfilesModel.refreshSettingsProfileState()
    }

    func nextClaudeProfileSlotID() -> CodexSlotID {
        officialProfilesModel.nextClaudeProfileSlotID()
    }

    func claudeSettingsTitle(for slotID: CodexSlotID) -> String {
        officialProfilesModel.claudeSettingsTitle(for: slotID)
    }

    func saveClaudeProfile(
        slotID: CodexSlotID,
        displayName: String,
        note: String?,
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?
    ) -> String {
        officialProfilesModel.saveClaudeProfile(
            slotID: slotID,
            displayName: displayName,
            note: note,
            source: source,
            configDir: configDir,
            credentialsJSON: credentialsJSON
        )
    }

    func removeClaudeProfile(slotID: CodexSlotID) {
        officialProfilesModel.removeClaudeProfile(slotID: slotID)
    }

    func switchCodexProfile(slotID: CodexSlotID) async {
        await officialProfilesModel.switchCodexProfile(slotID: slotID)
    }

    func switchClaudeProfile(slotID: CodexSlotID) async {
        await officialProfilesModel.switchClaudeProfile(slotID: slotID)
    }

    func boundedSnapshot(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        officialProfilesModel.boundedSnapshot(snapshot)
    }

    func markCodexSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
        officialProfilesModel.markCodexSnapshotActive(
            snapshot,
            preferredSlotID: preferredSlotID,
            isActive: isActive
        )
    }

    func syncCodexProfilesCurrentState() {
        officialProfilesModel.syncCodexProfilesCurrentState()
    }

    func refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for descriptor: ProviderDescriptor) async {
        await officialProfilesModel.refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for: descriptor)
    }

    func refreshOfficialProfileCardsAfterManualRefresh(for descriptor: ProviderDescriptor) async {
        await officialProfilesModel.refreshOfficialProfileCardsAfterManualRefresh(for: descriptor)
    }

    func refreshCodexProfileSnapshotSlot(
        _ profile: CodexAccountProfile,
        descriptor: ProviderDescriptor,
        allowSessionWindowStabilization: Bool = true
    ) async -> OfficialProfileRefreshExecutionResult {
        await officialProfilesModel.refreshCodexProfileSnapshotSlot(
            profile,
            descriptor: descriptor,
            allowSessionWindowStabilization: allowSessionWindowStabilization
        )
    }

    var hasPersistedOfficialMonitoringState: Bool {
        officialProfilesModel.hasPersistedOfficialMonitoringState
    }

    func restorePersistedOfficialProvidersIfNeeded() {
        officialProfilesModel.restorePersistedOfficialProvidersIfNeeded()
    }

    func claudeStatusBarDisplaySnapshot() -> UsageSnapshot? {
        officialProfilesModel.claudeStatusBarDisplaySnapshot()
    }

    func claudeOfficialProviderDescriptor() -> ProviderDescriptor? {
        officialProfilesModel.claudeOfficialProviderDescriptor()
    }

    func claudeDisplayableProfiles() -> [ClaudeAccountProfile] {
        officialProfilesModel.claudeDisplayableProfiles()
    }

    func resolvedClaudeStatusBarDisplaySlotID() -> CodexSlotID? {
        officialProfilesModel.resolvedClaudeStatusBarDisplaySlotID()
    }

    func triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: CodexSlotID?) {
        officialProfilesModel.triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: slotID)
    }

    func markClaudeSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
        officialProfilesModel.markClaudeSnapshotActive(
            snapshot,
            preferredSlotID: preferredSlotID,
            isActive: isActive
        )
    }

    func bootstrapClaudeProfileState() {
        officialProfilesModel.bootstrapClaudeProfileState()
    }

    func syncClaudeProfilesCurrentState(triggerPrefetchOnChange: Bool = true) {
        officialProfilesModel.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: triggerPrefetchOnChange)
    }

    func refreshClaudeProfileSnapshotSlot(
        _ profile: ClaudeAccountProfile,
        descriptor: ProviderDescriptor
    ) async -> OfficialProfileRefreshExecutionResult {
        await officialProfilesModel.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
    }
}
