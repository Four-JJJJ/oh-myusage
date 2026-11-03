import Foundation
import OhMyUsageApplication

enum AppOfficialProfileMenuPresenter {
    static func codexSlotViewModels(
        profiles: [CodexAccountProfile],
        slots: [CodexAccountSlot],
        feedbackBySlotID: [CodexSlotID: CodexSwitchFeedback],
        isSwitching: (CodexSlotID) -> Bool,
        titleForSlotID: (CodexSlotID) -> String,
        now: Date = Date()
    ) -> [CodexSlotViewModel] {
        let visibleSlotIDs = Set(profiles.map(\.slotID))
        return AppOfficialProfileStateCoordinator.mergedCodexSlotsForMenu(
            profiles: profiles,
            slots: slots
        )
        .filter { visibleSlotIDs.contains($0.slotID) }
        .sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt > rhs.lastSeenAt }
            return lhs.slotID < rhs.slotID
        }
        .map { slot in
            let profile = matchedCodexProfile(for: slot, profiles: profiles)
            let feedback = feedbackBySlotID[slot.slotID]
            let fallbackTitle = titleForSlotID(slot.slotID)
            let displayName = profile?.displayName ?? slot.displayName
            let displaySnapshot = CodexQuotaDisplayNormalizer.normalize(
                snapshot: slot.lastSnapshot,
                isActive: slot.isActive,
                now: now
            )
            return CodexSlotViewModel(
                slotID: slot.slotID,
                title: menuTitle(
                    fallbackTitle: fallbackTitle,
                    profileDisplayName: profile?.displayName,
                    note: profile?.note
                ),
                snapshot: displaySnapshot,
                isActive: slot.isActive,
                lastSeenAt: slot.lastSeenAt,
                displayName: displayName,
                note: profile?.note,
                isSwitching: isSwitching(slot.slotID),
                canSwitch: profile != nil && !(profile?.isCurrentSystemAccount ?? false),
                isCurrentSystemAccount: profile?.isCurrentSystemAccount ?? false,
                profileDisplayName: profile?.displayName,
                switchMessage: feedback?.message,
                switchMessageIsError: feedback?.isError ?? false
            )
        }
    }

    static func claudeSlotViewModels(
        profiles: [ClaudeAccountProfile],
        slots: [ClaudeAccountSlot],
        feedbackBySlotID: [CodexSlotID: ClaudeSwitchFeedback],
        isSwitching: (CodexSlotID) -> Bool,
        titleForSlotID: (CodexSlotID) -> String,
        now: Date = Date()
    ) -> [ClaudeSlotViewModel] {
        let visibleSlotIDs = AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
            profiles: profiles
        )
        return AppOfficialProfileStateCoordinator.mergedClaudeSlotsForMenu(
            profiles: profiles,
            slots: slots
        )
        .filter { visibleSlotIDs.contains($0.slotID) }
        .sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt > rhs.lastSeenAt }
            return lhs.slotID < rhs.slotID
        }
        .map { slot in
            let profile = matchedClaudeProfile(for: slot, profiles: profiles)
            let feedback = feedbackBySlotID[slot.slotID]
            let fallbackTitle = titleForSlotID(slot.slotID)
            let displayName = profile?.displayName ?? slot.displayName
            let displaySnapshot = CodexQuotaDisplayNormalizer.normalize(
                snapshot: slot.lastSnapshot,
                isActive: slot.isActive,
                now: now
            )
            return ClaudeSlotViewModel(
                slotID: slot.slotID,
                title: menuTitle(
                    fallbackTitle: fallbackTitle,
                    profileDisplayName: profile?.displayName,
                    note: profile?.note
                ),
                snapshot: displaySnapshot,
                isActive: slot.isActive,
                lastSeenAt: slot.lastSeenAt,
                displayName: displayName,
                note: profile?.note,
                source: profile?.source,
                isSwitching: isSwitching(slot.slotID),
                canSwitch: profile != nil && !(profile?.isCurrentSystemAccount ?? false),
                isCurrentSystemAccount: profile?.isCurrentSystemAccount ?? false,
                profileDisplayName: profile?.displayName,
                switchMessage: feedback?.message,
                switchMessageIsError: feedback?.isError ?? false
            )
        }
    }

    private static func matchedCodexProfile(
        for slot: CodexAccountSlot,
        profiles: [CodexAccountProfile]
    ) -> CodexAccountProfile? {
        if let index = CodexAccountProfileStore.matchingIndex(
            for: slot.lastSnapshot,
            in: profiles
        ) {
            return profiles[index]
        }
        return profiles.first(where: { $0.slotID == slot.slotID })
    }

    private static func matchedClaudeProfile(
        for slot: ClaudeAccountSlot,
        profiles: [ClaudeAccountProfile]
    ) -> ClaudeAccountProfile? {
        if let index = ClaudeAccountProfileStore.matchingIndex(
            for: slot.lastSnapshot,
            in: profiles
        ) {
            return profiles[index]
        }
        return profiles.first(where: { $0.slotID == slot.slotID })
    }

    private static func menuTitle(
        fallbackTitle: String,
        profileDisplayName: String?,
        note: String?
    ) -> String {
        let fallback = trimmedValue(fallbackTitle) ?? fallbackTitle
        if let note = OfficialProfileNaming.normalizedNote(note) {
            return "\(modelName(from: fallback)) \(note)"
        }
        return trimmedValue(profileDisplayName) ?? fallback
    }

    private static func modelName(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstToken = trimmed.split(whereSeparator: { $0.isWhitespace }).first else {
            return trimmed
        }
        return String(firstToken)
    }

    private static func trimmedValue(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
