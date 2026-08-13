import OhMyUsageApplication
import Foundation

@MainActor
final class AppOfficialProfileLifecycleCoordinator {
    func refreshInactiveProfilesInBackgroundIfNeeded(
        descriptor: ProviderDescriptor,
        codexSlots: [CodexAccountSlot],
        claudeSlots: [ClaudeAccountSlot],
        codexRuntime: CodexOfficialProfileRefreshRuntime,
        claudeRuntime: ClaudeOfficialProfileRefreshRuntime,
        syncCodexProfiles: () -> [CodexAccountProfile],
        syncClaudeProfiles: () -> [ClaudeAccountProfile],
        refreshCodexProfile: @escaping @MainActor (
            CodexAccountProfile,
            ProviderDescriptor
        ) async -> OfficialProfileRefreshExecutionResult,
        refreshClaudeProfile: @escaping @MainActor (
            ClaudeAccountProfile,
            ProviderDescriptor
        ) async -> OfficialProfileRefreshExecutionResult
    ) async {
        guard descriptor.family == .official else { return }
        switch descriptor.type {
        case .codex:
            await refreshCodexInactiveProfilesInBackgroundIfNeeded(
                descriptor: descriptor,
                slots: codexSlots,
                runtime: codexRuntime,
                syncProfiles: syncCodexProfiles
            ) { profile in
                await refreshCodexProfile(profile, descriptor)
            }
        case .claude:
            await refreshClaudeInactiveProfilesInBackgroundIfNeeded(
                descriptor: descriptor,
                slots: claudeSlots,
                runtime: claudeRuntime,
                syncProfiles: syncClaudeProfiles
            ) { profile in
                await refreshClaudeProfile(profile, descriptor)
            }
        case .relay, .open, .dragon, .gemini, .copilot, .microsoftCopilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf, .kimi, .grok, .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo:
            break
        }
    }

    func refreshProfilesAfterManualRefresh(
        descriptor: ProviderDescriptor,
        codexSlots: [CodexAccountSlot],
        claudeSlots: [ClaudeAccountSlot],
        codexRuntime: CodexOfficialProfileRefreshRuntime,
        claudeRuntime: ClaudeOfficialProfileRefreshRuntime,
        syncCodexProfiles: () -> [CodexAccountProfile],
        syncClaudeProfiles: () -> [ClaudeAccountProfile],
        refreshCodexProfile: @escaping @MainActor (
            CodexAccountProfile,
            ProviderDescriptor
        ) async -> OfficialProfileRefreshExecutionResult,
        refreshClaudeProfile: @escaping @MainActor (
            ClaudeAccountProfile,
            ProviderDescriptor
        ) async -> OfficialProfileRefreshExecutionResult
    ) async {
        guard descriptor.family == .official else { return }
        switch descriptor.type {
        case .codex:
            await refreshCodexProfilesAfterManualRefresh(
                descriptor: descriptor,
                slots: codexSlots,
                runtime: codexRuntime,
                syncProfiles: syncCodexProfiles
            ) { profile in
                await refreshCodexProfile(profile, descriptor)
            }
        case .claude:
            await refreshClaudeProfilesAfterManualRefresh(
                descriptor: descriptor,
                slots: claudeSlots,
                runtime: claudeRuntime,
                syncProfiles: syncClaudeProfiles
            ) { profile in
                await refreshClaudeProfile(profile, descriptor)
            }
        case .relay, .open, .dragon, .gemini, .copilot, .microsoftCopilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf, .kimi, .grok, .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo:
            break
        }
    }

    func refreshCodexInactiveProfilesInBackgroundIfNeeded(
        descriptor: ProviderDescriptor,
        slots: [CodexAccountSlot],
        runtime: CodexOfficialProfileRefreshRuntime,
        syncProfiles: () -> [CodexAccountProfile],
        refreshProfile: @escaping @MainActor (CodexAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        guard descriptor.family == .official, descriptor.type == .codex else { return }
        let profiles = syncProfiles()
        await runtime.refreshInactiveProfileCardInBackgroundIfNeeded(
            descriptor: descriptor,
            profiles: profiles,
            slots: slots,
            refreshProfile: refreshProfile
        )
    }

    func refreshClaudeInactiveProfilesInBackgroundIfNeeded(
        descriptor: ProviderDescriptor,
        slots: [ClaudeAccountSlot],
        runtime: ClaudeOfficialProfileRefreshRuntime,
        syncProfiles: () -> [ClaudeAccountProfile],
        refreshProfile: @escaping @MainActor (ClaudeAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        guard descriptor.family == .official, descriptor.type == .claude else { return }
        let profiles = syncProfiles()
        await runtime.refreshInactiveProfileCardInBackgroundIfNeeded(
            descriptor: descriptor,
            profiles: profiles,
            slots: slots,
            refreshProfile: refreshProfile
        )
    }

    func refreshCodexProfilesAfterManualRefresh(
        descriptor: ProviderDescriptor,
        slots: [CodexAccountSlot],
        runtime: CodexOfficialProfileRefreshRuntime,
        syncProfiles: () -> [CodexAccountProfile],
        refreshProfile: @escaping @MainActor (CodexAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        guard descriptor.family == .official, descriptor.type == .codex else { return }
        let profiles = syncProfiles()
        await runtime.refreshProfilesAfterManualRefresh(
            profiles: profiles,
            slots: slots,
            refreshProfile: refreshProfile
        )
    }

    func refreshClaudeProfilesAfterManualRefresh(
        descriptor: ProviderDescriptor,
        slots: [ClaudeAccountSlot],
        runtime: ClaudeOfficialProfileRefreshRuntime,
        syncProfiles: () -> [ClaudeAccountProfile],
        refreshProfile: @escaping @MainActor (ClaudeAccountProfile) async -> OfficialProfileRefreshExecutionResult
    ) async {
        guard descriptor.family == .official, descriptor.type == .claude else { return }
        let profiles = syncProfiles()
        await runtime.refreshProfilesAfterManualRefresh(
            profiles: profiles,
            slots: slots,
            refreshProfile: refreshProfile
        )
    }

    func scheduleCodexPrefetchIfNeeded(
        descriptor: ProviderDescriptor?,
        profiles: [CodexAccountProfile],
        slots: [CodexAccountSlot],
        runtime: CodexOfficialProfileRefreshRuntime,
        refreshProfile: @escaping @MainActor (
            CodexAccountProfile,
            ProviderDescriptor
        ) async -> OfficialProfileRefreshExecutionResult
    ) {
        runtime.schedulePrefetchIfNeeded(
            descriptor: descriptor,
            profiles: profiles,
            slots: slots,
            refreshProfile: refreshProfile
        )
    }

    func scheduleClaudePrefetchIfNeeded(
        descriptor: ProviderDescriptor?,
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        runtime: ClaudeOfficialProfileRefreshRuntime,
        refreshProfile: @escaping @MainActor (
            ClaudeAccountProfile,
            ProviderDescriptor
        ) async -> OfficialProfileRefreshExecutionResult
    ) {
        runtime.schedulePrefetchIfNeeded(
            descriptor: descriptor,
            profiles: profiles,
            slots: slots,
            refreshProfile: refreshProfile
        )
    }
}
