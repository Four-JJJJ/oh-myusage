import Foundation
import OhMyUsageDomain

/// Owns OfficialProfiles session boundary: coordinators + switch/import/sync orchestration.
/// Account / provider projections remain on AppViewModel/sessionStore so Observation keeps working.
@MainActor
final class AppOfficialProfilesModel {
    let accountImportCoordinator = AppOfficialAccountImportCoordinator()
    let accountSwitchCoordinator = AppOfficialAccountSwitchCoordinator()
    let lifecycleCoordinator = AppOfficialProfileLifecycleCoordinator()
    let refreshCoordinator = AppOfficialProfileRefreshCoordinator()
    let displayCoordinator = AppOfficialProfileDisplayCoordinator()
    let syncCoordinator = AppOfficialProfileSyncCoordinator()
    let codexFeedbackCoordinator = AppTransientFeedbackCoordinator<CodexSlotID, CodexSwitchFeedback>()
    let claudeFeedbackCoordinator = AppTransientFeedbackCoordinator<CodexSlotID, ClaudeSwitchFeedback>()
    let codexSwitchCoordinator = AccountSwitchTransactionCoordinator<CodexSlotID>()
    let claudeSwitchCoordinator = AccountSwitchTransactionCoordinator<CodexSlotID>()

    private weak var host: AppViewModel?

    /// Bind the host ViewModel after it is fully initialized (before sync/bootstrap).
    func bind(host: AppViewModel) {
        self.host = host
    }

    // MARK: - Import

    func startOAuthImport(providerType: ProviderType, slotID: CodexSlotID) {
        let host = requireHost()
        switch providerType {
        case .codex:
            if let task = accountImportCoordinator.startCodexImport(
                slotID: slotID,
                currentTask: host.codexOAuthImportTask,
                currentState: { host.codexOAuthImportState },
                importAccount: { [oauthImportOrchestrator = host.oauthImportOrchestrator] provider, slotID, stateHandler in
                    await oauthImportOrchestrator.importAccount(
                        provider: provider,
                        slotID: slotID,
                        stateHandler: stateHandler
                    )
                },
                matchingProfile: { rawCredentialJSON in
                    host.codexProfileStore.matchingProfile(authJSON: rawCredentialJSON)
                },
                saveImportedProfile: { imported, originalSlotID, existing in
                    let resolvedSlotID = existing?.slotID ?? originalSlotID
                    let resolvedDisplayName = existing?.displayName ?? "Codex \(resolvedSlotID.rawValue)"
                    let detail = self.saveCodexProfile(
                        slotID: resolvedSlotID,
                        displayName: resolvedDisplayName,
                        note: existing?.note,
                        authJSON: imported.rawCredentialJSON
                    )
                    return OAuthImportSaveOutcome(slotID: resolvedSlotID, detail: detail)
                },
                setState: { host.codexOAuthImportState = $0 },
                clearTask: { host.codexOAuthImportTask = nil }
            ) {
                host.codexOAuthImportTask = task
            }
        case .claude:
            if let task = accountImportCoordinator.startClaudeImport(
                slotID: slotID,
                currentTask: host.claudeOAuthImportTask,
                currentState: { host.claudeOAuthImportState },
                importAccount: { [oauthImportOrchestrator = host.oauthImportOrchestrator] provider, slotID, stateHandler in
                    await oauthImportOrchestrator.importAccount(
                        provider: provider,
                        slotID: slotID,
                        stateHandler: stateHandler
                    )
                },
                matchingProfile: { rawCredentialJSON in
                    host.claudeProfileStore.matchingProfile(credentialsJSON: rawCredentialJSON)
                },
                saveImportedProfile: { imported, originalSlotID, existing in
                    let resolvedSlotID = existing?.slotID ?? originalSlotID
                    let resolvedDisplayName = existing?.displayName ?? "Claude \(resolvedSlotID.rawValue)"
                    let detail = self.saveClaudeProfile(
                        slotID: resolvedSlotID,
                        displayName: resolvedDisplayName,
                        note: existing?.note,
                        source: .manualCredentials,
                        configDir: existing?.configDir,
                        credentialsJSON: imported.rawCredentialJSON
                    )
                    return OAuthImportSaveOutcome(slotID: resolvedSlotID, detail: detail)
                },
                setState: { host.claudeOAuthImportState = $0 },
                clearTask: { host.claudeOAuthImportTask = nil }
            ) {
                host.claudeOAuthImportTask = task
            }
        default:
            return
        }
    }

    func cancelOAuthImport(providerType: ProviderType) {
        let host = requireHost()
        switch providerType {
        case .codex:
            Task { await host.oauthImportOrchestrator.cancelImport(provider: .codex) }
        case .claude:
            Task { await host.oauthImportOrchestrator.cancelImport(provider: .claude) }
        default:
            break
        }
    }

    func saveCodexProfile(slotID: CodexSlotID, displayName: String, note: String?, authJSON: String) -> String {
        let host = requireHost()
        do {
            _ = try host.codexProfileStore.saveProfile(
                slotID: slotID,
                displayName: displayName,
                note: note,
                authJSON: authJSON,
                currentFingerprint: host.codexDesktopAuthService.currentCredentialFingerprint()
            )
            syncCodexProfilesCurrentState()
            activateOfficialProviderAfterProfileSave(type: .codex)
            return host.text(.codexProfileImported)
        } catch {
            return "\(host.text(.codexProfileImportFailed)): \(error.localizedDescription)"
        }
    }

    func removeCodexProfile(slotID: CodexSlotID) {
        let host = requireHost()
        syncCodexProfilesCurrentState()
        host.codexProfiles = host.codexProfileStore.removeProfile(slotID: slotID)
        host.codexSlots = host.codexSlotStore.remove(slotID: slotID)
        host.codexOfficialProfileRefreshRuntime.remove(slotID: slotID)
        setCodexSwitchFeedback(nil, for: slotID)
    }

    func saveClaudeProfile(
        slotID: CodexSlotID,
        displayName: String,
        note: String?,
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?
    ) -> String {
        let host = requireHost()
        do {
            if try host.claudeProfileStore.updateProfileMetadataIfCredentialInputsUnchanged(
                slotID: slotID,
                displayName: displayName,
                note: note,
                source: source,
                configDir: configDir,
                credentialsJSON: credentialsJSON
            ) != nil {
                syncClaudeProfilesCurrentState()
                return host.localizedText("Claude 账号备注已更新", "Claude profile note updated")
            }

            _ = try host.claudeProfileStore.saveProfile(
                slotID: slotID,
                displayName: displayName,
                note: note,
                source: source,
                configDir: configDir,
                credentialsJSON: credentialsJSON,
                currentFingerprint: host.claudeDesktopAuthService.currentCredentialFingerprint()
            )
            syncClaudeProfilesCurrentState()
            return host.localizedText("Claude 账号档案已导入", "Claude profile imported")
        } catch {
            return "\(host.localizedText("导入失败", "Import failed")): \(error.localizedDescription)"
        }
    }

    func removeClaudeProfile(slotID: CodexSlotID) {
        let host = requireHost()
        let previousConfiguredDisplaySlotID = host.config.claudeStatusBarDisplaySlotID
        let previousResolvedDisplaySlotID = resolvedClaudeStatusBarDisplaySlotID()
        syncClaudeProfilesCurrentState()
        host.claudeProfiles = host.claudeProfileStore.removeProfile(slotID: slotID)
        host.claudeSlots = host.claudeSlotStore.remove(slotID: slotID)
        host.claudeOfficialProfileRefreshRuntime.remove(slotID: slotID)
        setClaudeSwitchFeedback(nil, for: slotID)
        host.normalizeStatusBarSelections()
        if host.config.claudeStatusBarDisplaySlotID != previousConfiguredDisplaySlotID {
            _ = host.persistConfiguration(showFeedback: false)
        }
        let resolvedDisplaySlotID = resolvedClaudeStatusBarDisplaySlotID()
        if resolvedDisplaySlotID != previousResolvedDisplaySlotID {
            triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: resolvedDisplaySlotID)
            host.notifyStatusBarDisplayConfigChanged()
        }
    }

    // MARK: - Switch

    func switchCodexProfile(slotID: CodexSlotID) async {
        let host = requireHost()
        syncCodexProfilesCurrentState()
        await accountSwitchCoordinator.switchCodexProfile(
            slotID: slotID,
            transactionCoordinator: codexSwitchCoordinator,
            prepare: {
                guard let profile = host.codexProfiles.first(where: { $0.slotID == slotID }) else {
                    throw AccountSwitchTransactionUserMessageError(message: host.text(.codexProfileMissing))
                }
                return profile
            },
            apply: { profile in
                let refreshedProfile = try await self.refreshCodexProfileAuthBeforeDesktopApply(profile)
                try host.codexDesktopAuthService.applyProfile(refreshedProfile)
            },
            restart: { _ in
                await host.codexDesktopAppService.restartIfRunning()
            },
            verify: { _ in
                self.syncCodexProfilesCurrentState()
                guard let descriptor = host.config.providers.first(where: { $0.type == .codex && $0.family == .official }) else {
                    return .none
                }
                let provider = host.providerFactory.makeProvider(for: descriptor)
                let fetched = try await provider.fetch(forceRefresh: true)
                if let currentAuthJSON = host.codexDesktopAuthService.currentAuthJSON() {
                    _ = host.codexProfileStore.updateStoredAuthJSON(
                        slotID: slotID,
                        authJSON: currentAuthJSON
                    )
                    self.syncCodexProfilesCurrentState()
                }
                let snapshot = self.markCodexSnapshotActive(fetched, preferredSlotID: slotID)
                return OfficialAccountSwitchVerificationResult(
                    descriptor: descriptor,
                    snapshot: snapshot
                )
            },
            commitVerifiedState: { descriptor, snapshot in
                host.codexSlots = host.codexSlotStore.upsertActive(snapshot: snapshot)
                host.providerRefreshModel.mutateProviderState { state in
                    state.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                    state.errors.removeValue(forKey: descriptor.id)
                    state.consecutiveFailures[descriptor.id] = 0
                    state.lastUpdatedAt = Date()
                }
                host.notifyStatusBarDisplayConfigChanged()
            },
            successMessage: { restartResult in
                self.codexSwitchMessage(
                    for: restartResult,
                    successKey: .codexSwitchSuccess
                )
            },
            setFeedback: { feedback, slotID in
                self.setCodexSwitchFeedback(feedback, for: slotID)
            },
            recordVerifyError: { descriptor, message in
                host.providerRefreshModel.mutateProviderState { state in
                    state.errors[descriptor.id] = message
                }
            },
            notify: { message in
                host.notifications.notify(
                    title: "Codex",
                    body: message,
                    identifier: "codex-switch-\(slotID.rawValue.lowercased())"
                )
            },
            applyFailureMessage: { error in
                "\(host.text(.codexSwitchFailed)): \(error.localizedDescription)"
            },
            verifyFailureMessage: { error in
                "\(host.text(.codexSwitchNeedsVerification)): \(error.localizedDescription)"
            }
        )
    }

    func switchClaudeProfile(slotID: CodexSlotID) async {
        let host = requireHost()
        syncClaudeProfilesCurrentState()
        await accountSwitchCoordinator.switchClaudeProfile(
            slotID: slotID,
            transactionCoordinator: claudeSwitchCoordinator,
            prepare: {
                guard let profile = host.claudeProfiles.first(where: { $0.slotID == slotID }) else {
                    throw AccountSwitchTransactionUserMessageError(
                        message: host.localizedText(
                            "该槽位还没有导入可切换的 Claude 账号",
                            "No imported Claude profile is available for this slot"
                        )
                    )
                }
                return profile
            },
            apply: { profile in
                let credentialsJSON = try host.claudeProfileStore.resolvedCredentialsJSON(for: profile)
                try host.claudeDesktopAuthService.applyCredentialsJSON(credentialsJSON)
            },
            restart: { _ in () },
            verify: { _ in
                self.syncClaudeProfilesCurrentState()
                guard let descriptor = host.config.providers.first(where: { $0.type == .claude && $0.family == .official }) else {
                    return .none
                }
                let provider = host.providerFactory.makeProvider(for: descriptor)
                let fetched = try await provider.fetch(forceRefresh: true)
                let snapshot = self.markClaudeSnapshotActive(fetched, preferredSlotID: slotID)
                return OfficialAccountSwitchVerificationResult(
                    descriptor: descriptor,
                    snapshot: snapshot
                )
            },
            commitVerifiedState: { descriptor, snapshot in
                host.claudeSlots = host.claudeSlotStore.upsertActive(snapshot: snapshot)
                host.providerRefreshModel.mutateProviderState { state in
                    state.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                    state.errors.removeValue(forKey: descriptor.id)
                    state.consecutiveFailures[descriptor.id] = 0
                    state.lastUpdatedAt = Date()
                }
                host.notifyStatusBarDisplayConfigChanged()
            },
            verifiedSuccessMessage: host.localizedText("已切换 Claude 账号", "Claude account switched"),
            localSuccessMessage: host.localizedText("已写入本机 Claude 登录", "Local Claude credentials updated"),
            setFeedback: { feedback, slotID in
                self.setClaudeSwitchFeedback(feedback, for: slotID)
            },
            recordVerifyError: { descriptor, message in
                host.providerRefreshModel.mutateProviderState { state in
                    state.errors[descriptor.id] = message
                }
            },
            notify: { message in
                host.notifications.notify(
                    title: "Claude",
                    body: message,
                    identifier: "claude-switch-\(slotID.rawValue.lowercased())"
                )
            },
            applyFailureMessage: { error in
                "\(host.localizedText("切换失败", "Switch failed")): \(error.localizedDescription)"
            },
            verifyFailureMessage: { error in
                "\(host.localizedText("已切换到该账号，但需要重新验证", "Switched to this account, but re-verification is required")): \(error.localizedDescription)"
            }
        )
    }

    // MARK: - Sync / Bootstrap

    func syncCodexProfilesCurrentState() {
        let host = requireHost()
        let result = syncCoordinator.syncCodexProfiles(
            profileStore: host.codexProfileStore,
            desktopAuthService: host.codexDesktopAuthService
        )
        if result.profiles != host.codexProfiles {
            host.codexProfiles = result.profiles
        }
        host.codexOfficialProfileRefreshRuntime.pruneRetryState(keeping: result.visibleSlotIDs)
    }

    func bootstrapClaudeProfileState() {
        let host = requireHost()
        let bootstrapResult = syncCoordinator.bootstrapClaudeProfilesIfNeeded(
            currentProfiles: host.claudeProfiles,
            didRunAutoCaptureCompaction: host.didRunClaudeAutoCaptureCompaction,
            profileStore: host.claudeProfileStore,
            desktopAuthService: host.claudeDesktopAuthService
        )
        host.didRunClaudeAutoCaptureCompaction = bootstrapResult.didRunAutoCaptureCompaction
        if bootstrapResult.profiles != host.claudeProfiles {
            host.claudeProfiles = bootstrapResult.profiles
        }
        if !bootstrapResult.removedSlotIDs.isEmpty {
            removeClaudeSlotState(slotIDs: bootstrapResult.removedSlotIDs)
        }
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: true)
    }

    func syncClaudeProfilesCurrentState(triggerPrefetchOnChange: Bool = true) {
        let host = requireHost()
        let previousConfiguredDisplaySlotID = host.config.claudeStatusBarDisplaySlotID
        let previousResolvedDisplaySlotID = resolvedClaudeStatusBarDisplaySlotID()
        let syncResult = syncCoordinator.syncClaudeProfiles(
            currentProfiles: host.claudeProfiles,
            slots: host.claudeSlots,
            configuredDisplaySlotID: host.config.claudeStatusBarDisplaySlotID,
            profileStore: host.claudeProfileStore,
            desktopAuthService: host.claudeDesktopAuthService
        )
        if syncResult.profiles != host.claudeProfiles {
            host.claudeProfiles = syncResult.profiles
        }

        host.claudeOfficialProfileRefreshRuntime.pruneVisibleSlots(keeping: syncResult.visibleSlotIDs)
        host.config.claudeStatusBarDisplaySlotID = syncResult.syncEvaluation.normalizedConfiguredDisplaySlotID

        if host.config.claudeStatusBarDisplaySlotID != previousConfiguredDisplaySlotID {
            _ = host.persistConfiguration(showFeedback: false)
        }

        if triggerPrefetchOnChange,
           syncResult.syncEvaluation.didProfileIdentityChange {
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
        let resolvedDisplaySlotID = syncResult.syncEvaluation.resolvedDisplaySlotID
        if resolvedDisplaySlotID != previousResolvedDisplaySlotID {
            triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: resolvedDisplaySlotID)
            host.notifyStatusBarDisplayConfigChanged()
        }
    }

    // MARK: - Feedback / Reset helpers

    func cancelTransientFeedback() {
        codexFeedbackCoordinator.cancelAll()
        claudeFeedbackCoordinator.cancelAll()
    }

    func resetSwitchCoordinators() {
        codexSwitchCoordinator.reset()
        claudeSwitchCoordinator.reset()
    }

    func setCodexSwitchFeedback(_ feedback: CodexSwitchFeedback?, for slotID: CodexSlotID) {
        let host = requireHost()
        codexFeedbackCoordinator.set(
            feedback,
            for: slotID,
            currentValue: { host.codexSwitchFeedback[$0] },
            setValue: { slotID, feedback in
                if let feedback {
                    host.codexSwitchFeedback[slotID] = feedback
                } else {
                    host.codexSwitchFeedback.removeValue(forKey: slotID)
                }
            }
        )
    }

    func setClaudeSwitchFeedback(_ feedback: ClaudeSwitchFeedback?, for slotID: CodexSlotID) {
        let host = requireHost()
        claudeFeedbackCoordinator.set(
            feedback,
            for: slotID,
            currentValue: { host.claudeSwitchFeedback[$0] },
            setValue: { slotID, feedback in
                if let feedback {
                    host.claudeSwitchFeedback[slotID] = feedback
                } else {
                    host.claudeSwitchFeedback.removeValue(forKey: slotID)
                }
            }
        )
    }

    // MARK: - Private

    private func refreshCodexProfileAuthBeforeDesktopApply(
        _ profile: CodexAccountProfile
    ) async throws -> CodexAccountProfile {
        let host = requireHost()
        guard let descriptor = host.config.providers.first(where: { $0.type == .codex && $0.family == .official }) else {
            return profile
        }

        do {
            let result = try await host.codexProfileSnapshotService.fetchSnapshot(
                profile: profile,
                descriptor: descriptor
            )
            guard let refreshedAuthJSON = result.refreshedAuthJSON,
                  !refreshedAuthJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let updated = host.codexProfileStore.updateStoredAuthJSON(
                    slotID: profile.slotID,
                    authJSON: refreshedAuthJSON
                  ) else {
                return profile
            }
            syncCodexProfilesCurrentState()
            return updated
        } catch {
            return profile
        }
    }

    private func activateOfficialProviderAfterProfileSave(type: ProviderType) {
        let host = requireHost()
        let before = host.config
        if let index = host.config.providers.firstIndex(where: { $0.type == type && $0.family == .official }),
           !host.config.providers[index].enabled {
            host.config.providers[index].enabled = true
        }
        host.normalizeStatusBarSelections()
        if host.config != before {
            _ = host.persistConfiguration(showFeedback: true)
            host.restartPolling()
            host.refreshDisplayedStatusBarProviders()
        }
        host.notifyStatusBarDisplayConfigChanged()
    }

    private func codexSwitchMessage(
        for restartResult: CodexDesktopAppRestartResult,
        successKey: L10nKey
    ) -> String {
        let host = requireHost()
        if restartResult.requiresManualRelaunch {
            return host.text(.codexSwitchDesktopRestartIncomplete)
        }
        return host.text(successKey)
    }

    private func removeClaudeSlotState(slotIDs: [CodexSlotID]) {
        let host = requireHost()
        guard !slotIDs.isEmpty else { return }
        let uniqueSlotIDs = Array(Set(slotIDs)).sorted()
        for slotID in uniqueSlotIDs {
            host.claudeSlots = host.claudeSlotStore.remove(slotID: slotID)
            host.claudeOfficialProfileRefreshRuntime.remove(slotID: slotID)
            host.claudeSwitchFeedback.removeValue(forKey: slotID)
        }
    }

    func requireHost() -> AppViewModel {
        guard let host else {
            preconditionFailure("AppOfficialProfilesModel.bind must be called before use")
        }
        return host
    }
}
