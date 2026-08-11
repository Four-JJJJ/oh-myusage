import Foundation
import OhMyUsageDomain

@MainActor
extension AppOfficialProfilesModel {
    // MARK: - Settings / slot projections

    func codexSlotViewModels() -> [CodexSlotViewModel] {
        codexSlotViewModels(refreshFromStore: true, triggerPrefetch: true)
    }

    func codexSlotViewModelsForSettings() -> [CodexSlotViewModel] {
        codexSlotViewModels(refreshFromStore: false, triggerPrefetch: false)
    }

    func codexProfilesForSettings() -> [CodexAccountProfile] {
        let host = requireHost()
        return host.codexProfiles.sorted { $0.slotID < $1.slotID }
    }

    func nextCodexProfileSlotID() -> CodexSlotID {
        requireHost().codexProfileStore.nextAvailableSlotID()
    }

    func codexSettingsTitle(for slotID: CodexSlotID) -> String {
        "Codex \(slotID.rawValue)"
    }

    func oauthImportState(for providerType: ProviderType) -> OAuthImportState? {
        let host = requireHost()
        switch providerType {
        case .codex:
            return host.codexOAuthImportState
        case .claude:
            return host.claudeOAuthImportState
        default:
            return nil
        }
    }

    func claudeOAuthImportEnabled() -> Bool {
        true
    }

    func setClaudeOAuthImportEnabled(_ enabled: Bool) {
        _ = enabled
    }

    func claudeSlotViewModels() -> [ClaudeSlotViewModel] {
        claudeSlotViewModels(refreshFromStore: true, triggerPrefetch: true)
    }

    func claudeSlotViewModelsForSettings() -> [ClaudeSlotViewModel] {
        claudeSlotViewModels(refreshFromStore: false, triggerPrefetch: false)
    }

    func claudeProfilesForSettings() -> [ClaudeAccountProfile] {
        claudeDisplayableProfiles()
    }

    func refreshSettingsProfileState() {
        syncCodexProfilesCurrentState()
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
    }

    func nextClaudeProfileSlotID() -> CodexSlotID {
        requireHost().claudeProfileStore.nextAvailableSlotID()
    }

    func claudeSettingsTitle(for slotID: CodexSlotID) -> String {
        "Claude \(slotID.rawValue)"
    }

    // MARK: - Snapshot helpers

    func boundedSnapshot(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        var copy = snapshot
        copy.note = RuntimeBoundedState.boundedSnapshotNote(copy.note)
        return copy
    }

    func markCodexSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
        let host = requireHost()
        return AppOfficialProfileStateCoordinator.markCodexSnapshotActive(
            snapshot,
            preferredSlotID: preferredSlotID,
            isActive: isActive,
            profiles: host.codexProfiles
        )
    }

    func markClaudeSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
        let host = requireHost()
        return AppOfficialProfileStateCoordinator.markClaudeSnapshotActive(
            snapshot,
            preferredSlotID: preferredSlotID,
            isActive: isActive,
            profiles: host.claudeProfiles
        )
    }

    // MARK: - Lifecycle / refresh

    func refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for descriptor: ProviderDescriptor) async {
        let host = requireHost()
        await lifecycleCoordinator.refreshInactiveProfilesInBackgroundIfNeeded(
            descriptor: descriptor,
            codexSlots: host.codexSlots,
            claudeSlots: host.claudeSlots,
            codexRuntime: host.codexOfficialProfileRefreshRuntime,
            claudeRuntime: host.claudeOfficialProfileRefreshRuntime,
            syncCodexProfiles: {
                self.syncCodexProfilesCurrentState()
                return host.codexProfiles
            },
            syncClaudeProfiles: {
                self.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
                return host.claudeProfiles
            },
            refreshCodexProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshCodexProfileSnapshotSlot(profile, descriptor: descriptor)
            },
            refreshClaudeProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        )
    }

    func refreshOfficialProfileCardsAfterManualRefresh(for descriptor: ProviderDescriptor) async {
        let host = requireHost()
        await lifecycleCoordinator.refreshProfilesAfterManualRefresh(
            descriptor: descriptor,
            codexSlots: host.codexSlots,
            claudeSlots: host.claudeSlots,
            codexRuntime: host.codexOfficialProfileRefreshRuntime,
            claudeRuntime: host.claudeOfficialProfileRefreshRuntime,
            syncCodexProfiles: {
                self.syncCodexProfilesCurrentState()
                return host.codexProfiles
            },
            syncClaudeProfiles: {
                self.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
                return self.claudeDisplayableProfiles()
            },
            refreshCodexProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshCodexProfileSnapshotSlot(
                    profile,
                    descriptor: descriptor,
                    allowSessionWindowStabilization: false
                )
            },
            refreshClaudeProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        )
    }

    func refreshCodexProfileSnapshotSlot(
        _ profile: CodexAccountProfile,
        descriptor: ProviderDescriptor,
        allowSessionWindowStabilization: Bool = true
    ) async -> OfficialProfileRefreshExecutionResult {
        let host = requireHost()
        return await refreshCoordinator.refreshCodexProfileSlot(
            profile: profile,
            descriptor: descriptor,
            runtime: host.codexOfficialProfileRefreshRuntime,
            allowSessionWindowStabilization: allowSessionWindowStabilization,
            fetchSnapshot: { profile, descriptor in
                try await host.codexProfileSnapshotService.fetchSnapshot(
                    profile: profile,
                    descriptor: descriptor
                )
            },
            persistRefreshedAuthJSON: { slotID, refreshedAuthJSON in
                _ = host.codexProfileStore.updateStoredAuthJSON(
                    slotID: slotID,
                    authJSON: refreshedAuthJSON
                )
            },
            syncProfiles: {
                self.syncCodexProfilesCurrentState()
            },
            transformSnapshot: { snapshot, slotID in
                self.boundedSnapshot(
                    self.markCodexSnapshotActive(
                        snapshot,
                        preferredSlotID: slotID,
                        isActive: false
                    )
                )
            },
            commitInactiveSnapshot: { snapshot, slotID, allowSessionWindowStabilization in
                host.codexSlots = host.codexSlotStore.upsertInactive(
                    snapshot: snapshot,
                    preferredSlotID: slotID,
                    allowSessionWindowStabilization: allowSessionWindowStabilization
                )
            }
        )
    }

    func refreshClaudeProfileSnapshotSlot(
        _ profile: ClaudeAccountProfile,
        descriptor: ProviderDescriptor
    ) async -> OfficialProfileRefreshExecutionResult {
        let host = requireHost()
        return await refreshCoordinator.refreshClaudeProfileSlot(
            profile: profile,
            descriptor: descriptor,
            runtime: host.claudeOfficialProfileRefreshRuntime,
            shouldRefreshProfile: { AppOfficialProfileStateCoordinator.canDisplayClaudeMonitoringProfile($0) },
            fetchSnapshot: { profile, descriptor in
                try await host.claudeProfileSnapshotService.fetchSnapshot(
                    profile: profile,
                    descriptor: descriptor
                )
            },
            persistRefreshedCredentialsJSON: { slotID, refreshedCredentialsJSON in
                _ = host.claudeProfileStore.updateStoredCredentials(
                    slotID: slotID,
                    credentialsJSON: refreshedCredentialsJSON
                )
            },
            syncProfiles: {
                self.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
            },
            transformSnapshot: { snapshot, slotID in
                self.boundedSnapshot(
                    self.markClaudeSnapshotActive(
                        snapshot,
                        preferredSlotID: slotID,
                        isActive: false
                    )
                )
            },
            commitInactiveSnapshot: { snapshot, slotID in
                host.claudeSlots = host.claudeSlotStore.upsertInactive(
                    snapshot: snapshot,
                    preferredSlotID: slotID
                )
                if self.resolvedClaudeStatusBarDisplaySlotID() == slotID {
                    host.notifyStatusBarDisplayConfigChanged()
                }
            }
        )
    }

    // MARK: - Display / persistence

    var hasPersistedOfficialMonitoringState: Bool {
        let host = requireHost()
        return AppOfficialProfileStateCoordinator.hasPersistedOfficialMonitoringState(
            codexProfiles: host.codexProfiles,
            codexSlots: host.codexSlots,
            claudeProfiles: host.claudeProfiles,
            claudeSlots: host.claudeSlots
        )
    }

    func restorePersistedOfficialProvidersIfNeeded() {
        let host = requireHost()
        if AppOfficialProfileStateCoordinator.restorePersistedOfficialProvidersIfNeeded(
            config: &host.config,
            codexProfiles: host.codexProfiles,
            codexSlots: host.codexSlots,
            claudeProfiles: host.claudeProfiles,
            claudeSlots: host.claudeSlots
        ) {
            host.normalizeStatusBarSelections()
        }
    }

    func claudeStatusBarDisplaySnapshot() -> UsageSnapshot? {
        let host = requireHost()
        let descriptor = claudeOfficialProviderDescriptor()
        return displayCoordinator.claudeStatusBarDisplaySnapshot(
            resolvedSlotID: resolvedClaudeStatusBarDisplaySlotID(),
            slotViewModels: claudeSlotViewModels(refreshFromStore: true, triggerPrefetch: false),
            providerSnapshot: descriptor.flatMap { host.snapshots[$0.id] }
        )
    }

    func claudeOfficialProviderDescriptor() -> ProviderDescriptor? {
        let host = requireHost()
        return host.config.providers.first(where: { $0.type == .claude && $0.family == .official })
    }

    func claudeDisplayableProfiles() -> [ClaudeAccountProfile] {
        let host = requireHost()
        return AppOfficialProfileStateCoordinator.displayableClaudeProfiles(host.claudeProfiles)
    }

    func resolvedClaudeStatusBarDisplaySlotID() -> CodexSlotID? {
        let host = requireHost()
        return AppOfficialProfileStateCoordinator.resolveClaudeStatusBarDisplaySlotID(
            configuredSlotID: host.config.claudeStatusBarDisplaySlotID,
            profiles: host.claudeProfiles,
            slots: host.claudeSlots
        )
    }

    func triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: CodexSlotID?) {
        let host = requireHost()
        let action = displayCoordinator.claudeStatusBarDisplayPrefetchAction(
            slotID: slotID,
            descriptor: claudeOfficialProviderDescriptor(),
            profiles: host.claudeProfiles
        )
        switch action {
        case .none:
            return
        case .notifyOnly:
            host.notifyStatusBarDisplayConfigChanged()
            return
        case .refresh(let slotID):
            guard let descriptor = claudeOfficialProviderDescriptor(),
                  let profile = host.claudeProfiles.first(where: { $0.slotID == slotID }) else {
                return
            }
            Task { [weak self] in
                guard let self else { return }
                _ = await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
                self.requireHost().notifyStatusBarDisplayConfigChanged()
            }
        }
    }

    // MARK: - Private slot builders

    private func codexSlotViewModels(
        refreshFromStore: Bool,
        triggerPrefetch: Bool
    ) -> [CodexSlotViewModel] {
        let host = requireHost()
        if refreshFromStore {
            let latestCodexSlots = host.codexSlotStore.visibleSlots()
            if latestCodexSlots != host.codexSlots {
                host.codexSlots = latestCodexSlots
            }
        }
        if triggerPrefetch {
            lifecycleCoordinator.scheduleCodexPrefetchIfNeeded(
                descriptor: host.config.providers.first(where: { $0.type == .codex && $0.family == .official }),
                profiles: host.codexProfiles,
                slots: host.codexSlots,
                runtime: host.codexOfficialProfileRefreshRuntime
            ) { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshCodexProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        }
        return AppOfficialProfileMenuPresenter.codexSlotViewModels(
            profiles: host.codexProfiles,
            slots: host.codexSlots,
            feedbackBySlotID: host.codexSwitchFeedback,
            isSwitching: { self.codexSwitchCoordinator.isRunning(slotID: $0) },
            titleForSlotID: { self.codexMenuTitle(for: $0) }
        )
    }

    private func claudeSlotViewModels(
        refreshFromStore: Bool,
        triggerPrefetch: Bool
    ) -> [ClaudeSlotViewModel] {
        let host = requireHost()
        if refreshFromStore {
            let latestClaudeSlots = host.claudeSlotStore.visibleSlots()
            if latestClaudeSlots != host.claudeSlots {
                host.claudeSlots = latestClaudeSlots
            }
        }
        if triggerPrefetch {
            lifecycleCoordinator.scheduleClaudePrefetchIfNeeded(
                descriptor: claudeOfficialProviderDescriptor(),
                profiles: claudeDisplayableProfiles(),
                slots: host.claudeSlots,
                runtime: host.claudeOfficialProfileRefreshRuntime
            ) { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        }
        return AppOfficialProfileMenuPresenter.claudeSlotViewModels(
            profiles: host.claudeProfiles,
            slots: host.claudeSlots,
            feedbackBySlotID: host.claudeSwitchFeedback,
            isSwitching: { self.claudeSwitchCoordinator.isRunning(slotID: $0) },
            titleForSlotID: { self.claudeMenuTitle(for: $0) }
        )
    }

    private func codexMenuTitle(for slotID: CodexSlotID) -> String {
        "Codex \(slotID.rawValue)"
    }

    private func claudeMenuTitle(for slotID: CodexSlotID) -> String {
        "Claude \(slotID.rawValue)"
    }
}
