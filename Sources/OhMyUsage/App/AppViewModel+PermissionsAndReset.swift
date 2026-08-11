import Foundation

@MainActor
extension AppViewModel {
    func resetLocalAppData() {
        resetCoordinator.resetLocalAppData(
            using: AppResetCoordinator.ResetHooks(
                stopPollingAndTransientTasks: {
                    self.permissionModel.cancelTransientTasks()
                    self.providerRefreshModel.stopPolling()
                    self.officialProfilesModel.cancelTransientFeedback()
                    self.codexOAuthImportTask?.cancel()
                    self.codexOAuthImportTask = nil
                    self.claudeOAuthImportTask?.cancel()
                    self.claudeOAuthImportTask = nil
                },
                cancelOAuthImports: {
                    Task { await self.oauthImportOrchestrator.cancelImport(provider: .codex) }
                    Task { await self.oauthImportOrchestrator.cancelImport(provider: .claude) }
                },
                resetRuntimeComponents: {
                    self.officialProfilesModel.resetSwitchCoordinators()
                    self.codexOfficialProfileRefreshRuntime.reset()
                    self.codexSwitchFeedback.removeAll()
                    self.codexOAuthImportState = nil
                    self.claudeOfficialProfileRefreshRuntime.reset()
                    self.didRunClaudeAutoCaptureCompaction = false
                    self.claudeSwitchFeedback.removeAll()
                    self.claudeOAuthImportState = nil
                },
                clearInMemoryState: {
                    self.providerRefreshModel.mutateProviderState { state in
                        state.snapshots.removeAll()
                        state.errors.removeAll()
                        state.consecutiveFailures.removeAll()
                        state.activeAlerts.removeAll()
                        state.thirdPartyBalanceBaselineTracker.removeAll()
                        state.lastUpdatedAt = nil
                    }
                    self.thirdPartyBalanceBaselineStore.reset()
                },
                resetPersistentState: {
                    self.launchAtLoginService.reset()
                    self.credentialAccessService.resetAllStoredCredentials()
                    self.codexProfileStore.reset()
                    self.codexSlotStore.reset()
                    self.claudeProfileStore.reset()
                    self.claudeSlotStore.reset()
                    _ = self.resetConfiguration(showFeedback: true)
                },
                restoreDefaultState: {
                    self.config = .default
                    self.codexSlots = []
                    self.codexProfiles = []
                    self.claudeSlots = []
                    self.claudeProfiles = []
                    self.syncCodexProfilesCurrentState()
                    self.bootstrapClaudeProfileState()
                    self.permissionModel.resetState()
                    self.hasStarted = false
                },
                rebootstrap: {
                    self.start()
                    self.refreshPermissionStatuses(force: true)
                }
            )
        )
    }
}
