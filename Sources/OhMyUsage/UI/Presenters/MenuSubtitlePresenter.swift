import OhMyUsageApplication
import Foundation
import OhMyUsageDomain

enum MenuSubtitlePresenter {
    static func officialAccountSubtitle(
        providerType: ProviderType,
        snapshot: UsageSnapshot?,
        showAccountEmail: Bool,
        note: String? = nil,
        codexTeamAliases: [String: String] = [:]
    ) -> String? {
        let accountValue: String? = {
            guard showAccountEmail,
                  let value = OfficialValueParser.nonPlaceholderString(snapshot?.accountLabel) else {
                return nil
            }
            return value
        }()
        let accountText = joinedSubtitleParts([accountValue, note])

        guard providerType == .codex else {
            return accountText
        }

        guard let teamAlias = codexTeamAlias(for: snapshot, aliases: codexTeamAliases) else {
            return accountText
        }
        return joinedSubtitleParts([accountText, teamAlias])
    }

    static func relaySecondaryText(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        language: AppLanguage
    ) -> String? {
        let relayMetadata = RelaySnapshotDisplayMetadata(
            snapshot: snapshot,
            fallbackAdapterID: provider.relayConfig?.adapterID
        )
        guard relayMetadata.resolvedAdapterID == "generic-newapi",
              let requestCount = relayMetadata.requestCount else {
            return nil
        }

        switch language {
        case .zhHans:
            return "请求次数 \(requestCount)"
        case .en:
            return "Requests \(requestCount)"
        }
    }

    static func relayQuotaSubtitle(
        snapshot: UsageSnapshot?,
        language: AppLanguage,
        showExpirationTime: Bool = true
    ) -> String? {
        guard showExpirationTime else {
            return nil
        }
        let relayMetadata = RelaySnapshotDisplayMetadata(snapshot: snapshot)
        guard let raw = relayMetadata.tokenPlanCurrentPeriodEnd else {
            return nil
        }
        switch language {
        case .zhHans:
            return "有效期至 \(raw) (UTC)"
        case .en:
            return "Valid until \(raw) (UTC)"
        }
    }

    static func codexTeamAliasMap(from snapshots: [UsageSnapshot]) -> [String: String] {
        var teamIDsByEmail: [String: Set<String>] = [:]
        for snapshot in snapshots {
            guard let key = codexTeamAliasKey(from: snapshot) else { continue }
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            teamIDsByEmail[parts[0], default: []].insert(parts[1])
        }

        var aliases: [String: String] = [:]
        for (email, teamIDs) in teamIDsByEmail {
            let sortedTeamIDs = teamIDs.sorted()
            guard sortedTeamIDs.count > 1 else { continue }
            for (index, teamID) in sortedTeamIDs.enumerated() {
                aliases["\(email)|\(teamID)"] = "Team \(codexTeamAliasToken(index: index))"
            }
        }
        return aliases
    }

    private static func joinedSubtitleParts(_ parts: [String?]) -> String? {
        let values = parts.compactMap { raw -> String? in
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " · ")
    }

    private static func codexTeamAlias(for snapshot: UsageSnapshot?, aliases: [String: String]) -> String? {
        guard let key = codexTeamAliasKey(from: snapshot) else { return nil }
        return aliases[key]
    }

    private static func codexTeamAliasKey(from snapshot: UsageSnapshot?) -> String? {
        let metadata = OfficialSnapshotIdentityMetadata.codex(from: snapshot)
        guard let email = CodexIdentity.normalizedEmail(metadata.accountLabel) else {
            return nil
        }
        guard let teamID = CodexIdentity.normalizedAccountID(metadata.teamID) else {
            return nil
        }
        return "\(email)|\(teamID)"
    }

    private static func codexTeamAliasToken(index: Int) -> String {
        var value = index
        var token = ""
        repeat {
            let remainder = value % 26
            let scalar = UnicodeScalar(65 + remainder)!
            token = String(Character(scalar)) + token
            value = value / 26 - 1
        } while value >= 0
        return token
    }
}
