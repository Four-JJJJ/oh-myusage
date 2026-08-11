import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

struct CodexSnapshotIdentityMetadata: Equatable {
    var accountID: String?
    var teamID: String?
    var accountLabel: String?
    var identityKey: String?
    var slotID: CodexSlotID?
    var isActive: Bool?
}

struct ClaudeSnapshotIdentityMetadata: Equatable {
    var accountID: String?
    var accountLabel: String?
    var configDir: String?
    var slotID: CodexSlotID?
    var isActive: Bool?
}

enum OfficialSnapshotIdentityMetadata {
    static func codex(from snapshot: UsageSnapshot?) -> CodexSnapshotIdentityMetadata {
        guard let snapshot else {
            return CodexSnapshotIdentityMetadata(
                accountID: nil,
                teamID: nil,
                accountLabel: nil,
                identityKey: nil,
                slotID: nil,
                isActive: nil
            )
        }

        let rawMeta = snapshot.rawMeta
        return CodexSnapshotIdentityMetadata(
            accountID: OfficialValueParser.nonPlaceholderString(rawMeta["codex.accountId"]),
            teamID: OfficialValueParser.nonPlaceholderString(rawMeta["codex.teamId"])
                ?? OfficialValueParser.nonPlaceholderString(rawMeta["codex.accountId"]),
            accountLabel: OfficialValueParser.nonPlaceholderString(snapshot.accountLabel)
                ?? OfficialValueParser.nonPlaceholderString(rawMeta["codex.accountLabel"]),
            identityKey: OfficialValueParser.nonPlaceholderString(rawMeta["codex.identityKey"]),
            slotID: OfficialValueParser.nonPlaceholderString(rawMeta["codex.slotID"])
                .flatMap(CodexSlotID.init(rawValue:)),
            isActive: OfficialValueParser.nonPlaceholderString(rawMeta["codex.isActive"])
                .flatMap(Bool.init)
        )
    }

    static func claude(from snapshot: UsageSnapshot?) -> ClaudeSnapshotIdentityMetadata {
        guard let snapshot else {
            return ClaudeSnapshotIdentityMetadata(
                accountID: nil,
                accountLabel: nil,
                configDir: nil,
                slotID: nil,
                isActive: nil
            )
        }

        let rawMeta = snapshot.rawMeta
        return ClaudeSnapshotIdentityMetadata(
            accountID: OfficialValueParser.nonPlaceholderString(rawMeta["claude.accountId"]),
            accountLabel: OfficialValueParser.nonPlaceholderString(snapshot.accountLabel)
                ?? OfficialValueParser.nonPlaceholderString(rawMeta["claude.accountLabel"]),
            configDir: OfficialValueParser.nonPlaceholderString(rawMeta["claude.configDir"]),
            slotID: OfficialValueParser.nonPlaceholderString(rawMeta["claude.slotID"])
                .flatMap(CodexSlotID.init(rawValue:)),
            isActive: OfficialValueParser.nonPlaceholderString(rawMeta["claude.isActive"])
                .flatMap(Bool.init)
        )
    }
}
