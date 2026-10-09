import Foundation
import OhMyUsageDomain

extension SettingsView {
    func localUsageTrendCodexAccountOptions(snapshot: UsageSnapshot?) -> [LocalUsageTrendAccountOption] {
        var options: [LocalUsageTrendAccountOption] = []
        var seenIdentityKeys: Set<String> = []

        for profile in viewModel.codexProfilesForSettings() {
            let identity = CodexTrendIdentityContext(
                accountID: profile.accountId,
                email: profile.accountEmail,
                identityKey: profile.identityKey
            )
            guard identity.accountID != nil || identity.email != nil || identity.identityKey != nil else {
                continue
            }
            let identityKey = identity.cacheIdentity
            guard !seenIdentityKeys.contains(identityKey) else { continue }
            seenIdentityKeys.insert(identityKey)

            let title = localUsageTrendCodexAccountLabel(profile: profile, identity: identity)
            options.append(
                LocalUsageTrendAccountOption(
                    id: "codex:\(identityKey)",
                    label: title,
                    selectorLabel: localUsageTrendCodexSelectorLabel(profile: profile, identity: identity),
                    codexIdentity: identity,
                    claudeConfigDir: nil
                )
            )
        }

        if let snapshotIdentity = codexLocalTrendIdentityContext(from: snapshot) {
            let snapshotKey = snapshotIdentity.cacheIdentity
            if !seenIdentityKeys.contains(snapshotKey) {
                let label = localUsageTrendCurrentSnapshotLabel(snapshot: snapshot)
                options.insert(
                    LocalUsageTrendAccountOption(
                        id: "codex:current:\(snapshotKey)",
                        label: label,
                        selectorLabel: localUsageTrendCurrentSnapshotSelectorLabel(snapshot: snapshot),
                        codexIdentity: snapshotIdentity,
                        claudeConfigDir: nil
                    ),
                    at: 0
                )
            }
        }

        return options
    }

    func localUsageTrendClaudeAccountOptions(snapshot: UsageSnapshot?) -> [LocalUsageTrendAccountOption] {
        var options: [LocalUsageTrendAccountOption] = []
        var seenIDs: Set<String> = []

        for profile in viewModel.claudeProfilesForSettings() {
            let configDir = localUsageTrendTrimmed(profile.configDir)
            let key = "claude:\(configDir ?? "default")"
            guard !seenIDs.contains(key) else { continue }
            seenIDs.insert(key)
            options.append(
                LocalUsageTrendAccountOption(
                    id: key,
                    label: localUsageTrendClaudeAccountLabel(profile: profile, configDir: configDir),
                    selectorLabel: localUsageTrendClaudeSelectorLabel(profile: profile, configDir: configDir),
                    codexIdentity: nil,
                    claudeConfigDir: configDir
                )
            )
        }

        let snapshotConfigDir = OfficialSnapshotIdentityMetadata.claude(from: snapshot).configDir
            .flatMap(localUsageTrendTrimmed(_:))
        if let snapshotConfigDir {
            let snapshotKey = "claude:\(snapshotConfigDir)"
            if !seenIDs.contains(snapshotKey) {
                options.insert(
                    LocalUsageTrendAccountOption(
                        id: snapshotKey,
                        label: viewModel.localizedText("当前目录", "Current Directory"),
                        selectorLabel: localUsageTrendTrimmed(snapshot?.accountLabel)
                            ?? viewModel.localizedText("当前目录", "Current Directory"),
                        codexIdentity: nil,
                        claudeConfigDir: snapshotConfigDir
                    ),
                    at: 0
                )
            }
        } else if options.isEmpty {
            options.append(
                LocalUsageTrendAccountOption(
                    id: "claude:default",
                    label: viewModel.localizedText(
                        "默认目录 (~/.claude/projects)",
                        "Default Directory (~/.claude/projects)"
                    ),
                    selectorLabel: viewModel.localizedText("默认目录", "Default"),
                    codexIdentity: nil,
                    claudeConfigDir: nil
                )
            )
        }

        return options
    }

    func localUsageTrendCodexAccountLabel(
        profile: CodexAccountProfile,
        identity: CodexTrendIdentityContext
    ) -> String {
        let displayName = localUsageTrendTrimmed(profile.displayName) ?? "Codex \(profile.slotID.rawValue)"
        if let email = localUsageTrendTrimmed(profile.accountEmail) {
            return "\(displayName) · \(email)"
        }
        if let accountID = localUsageTrendShortID(identity.accountID) {
            return "\(displayName) · \(accountID)"
        }
        return displayName
    }

    func localUsageTrendCodexSelectorLabel(
        profile: CodexAccountProfile,
        identity: CodexTrendIdentityContext
    ) -> String {
        if let email = localUsageTrendTrimmed(profile.accountEmail) {
            return email
        }
        if let accountID = localUsageTrendShortID(identity.accountID) {
            return accountID
        }
        return localUsageTrendTrimmed(profile.displayName) ?? "Codex \(profile.slotID.rawValue)"
    }

    func localUsageTrendClaudeAccountLabel(profile: ClaudeAccountProfile, configDir: String?) -> String {
        let displayName = localUsageTrendTrimmed(profile.displayName) ?? "Claude \(profile.slotID.rawValue)"
        if let email = localUsageTrendTrimmed(profile.accountEmail) {
            return "\(displayName) · \(email)"
        }
        if configDir == nil {
            return "\(displayName) · \(viewModel.localizedText("默认目录", "Default"))"
        }
        return displayName
    }

    func localUsageTrendClaudeSelectorLabel(profile: ClaudeAccountProfile, configDir: String?) -> String {
        if let email = localUsageTrendTrimmed(profile.accountEmail) {
            return email
        }
        if configDir == nil {
            return viewModel.localizedText("默认目录", "Default")
        }
        return localUsageTrendTrimmed(profile.displayName) ?? "Claude \(profile.slotID.rawValue)"
    }

    func localUsageTrendCurrentSnapshotLabel(snapshot: UsageSnapshot?) -> String {
        let base = viewModel.localizedText("当前账号", "Current Account")
        if let label = localUsageTrendTrimmed(snapshot?.accountLabel) {
            return "\(base) · \(label)"
        }
        return base
    }

    func localUsageTrendCurrentSnapshotSelectorLabel(snapshot: UsageSnapshot?) -> String {
        localUsageTrendTrimmed(snapshot?.accountLabel)
            ?? viewModel.localizedText("当前账号", "Current Account")
    }

    func localUsageTrendShortID(_ value: String?) -> String? {
        guard let value = localUsageTrendTrimmed(value) else { return nil }
        guard value.count > 14 else { return value }
        let prefix = value.prefix(6)
        let suffix = value.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    func localUsageTrendIdentityContext(
        for provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        selectedAccountKey: String,
        accountOptions: [LocalUsageTrendAccountOption]
    ) -> LocalUsageTrendIdentityContext {
        switch provider.type {
        case .codex:
            let identity = accountOptions.first(where: { $0.id == selectedAccountKey })?.codexIdentity
                ?? codexLocalTrendIdentityContext(from: snapshot)
            return LocalUsageTrendIdentityContext(
                cacheIdentity: identity?.cacheIdentity ?? "unknown",
                codexIdentity: identity,
                claudeCurrentConfigDir: nil,
                claudeAllConfigDirs: []
            )
        case .claude:
            let selectedConfigDir = accountOptions.first(where: { $0.id == selectedAccountKey })?.claudeConfigDir
            let currentConfigDir = localUsageTrendTrimmed(selectedConfigDir)
                ?? OfficialSnapshotIdentityMetadata.claude(from: snapshot).configDir
                    .flatMap(localUsageTrendTrimmed(_:))
            let allConfigDirs = Array(
                Set(
                    accountOptions.compactMap { localUsageTrendTrimmed($0.claudeConfigDir) }
                )
            )
            .sorted()
            let currentKey = currentConfigDir ?? "default"
            let allKey = allConfigDirs.joined(separator: ",")
            return LocalUsageTrendIdentityContext(
                cacheIdentity: "current=\(currentKey)|all=\(allKey)",
                codexIdentity: nil,
                claudeCurrentConfigDir: currentConfigDir,
                claudeAllConfigDirs: allConfigDirs
            )
        default:
            return LocalUsageTrendIdentityContext(
                cacheIdentity: "global",
                codexIdentity: nil,
                claudeCurrentConfigDir: nil,
                claudeAllConfigDirs: []
            )
        }
    }

    func localUsageTrendEffectiveIdentityCacheKey(
        scope: LocalUsageTrendScope,
        identityCacheKey: String
    ) -> String {
        if scope == .allAccounts {
            return "all"
        }
        return identityCacheKey
    }

    func localUsageTrendDisplaySummary(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        identityCacheKey: String,
        strictSummary: LocalUsageSummary?
    ) -> LocalUsageSummary? {
        _ = provider
        _ = scope
        _ = identityCacheKey
        return strictSummary
    }

    func localUsageTrendTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func codexLocalTrendIdentityContext(from snapshot: UsageSnapshot?) -> CodexTrendIdentityContext? {
        guard let snapshot else { return nil }
        let metadata = OfficialSnapshotIdentityMetadata.codex(from: snapshot)
        let accountID = localUsageTrendTrimmed(metadata.accountID)
            ?? localUsageTrendTrimmed(metadata.teamID)
        let email = localUsageTrendTrimmed(metadata.accountLabel)
        let identityKey = localUsageTrendTrimmed(metadata.identityKey)

        let context = CodexTrendIdentityContext(
            accountID: accountID,
            email: email,
            identityKey: identityKey
        )
        if context.accountID == nil, context.email == nil, context.identityKey == nil {
            return nil
        }
        return context
    }

}
