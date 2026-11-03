import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    struct LocalUsageTrendChartStatus {
        var text: String
        var color: Color
    }

    struct LocalUsageTrendAccountOption: Identifiable {
        var id: String
        var label: String
        var selectorLabel: String
        var codexIdentity: CodexTrendIdentityContext?
        var claudeConfigDir: String?
    }

    struct LocalUsageTrendIdentityContext {
        var cacheIdentity: String
        var codexIdentity: CodexTrendIdentityContext?
        var claudeCurrentConfigDir: String?
        var claudeAllConfigDirs: [String]
    }

    func shouldShowOfficialLocalTrendCard(for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .official else { return false }
        switch provider.type {
        case .codex, .claude, .gemini, .kimi, .cursor, .grok:
            return true
        default:
            return false
        }
    }

    func officialUsageSectionHasData(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> Bool {
        let context = localUsageTrendContext(for: provider, snapshot: snapshot)
        let historyState = viewModel.localUsageHistoryState(for: context.query)
        let chartError = historyState.isStaleFallback && historyState.summary != nil
            ? nil
            : historyState.error

        if historyState.isLoading { return true }
        if let chartError, !chartError.isEmpty { return true }

        let strictSummary = historyState.summary
        let summary = localUsageTrendDisplaySummary(
            provider: provider,
            scope: context.scope,
            identityCacheKey: context.identityCacheKey,
            strictSummary: strictSummary
        ) ?? strictSummary

        return summary.map { LocalUsageTrendPresenter.hasData($0) } ?? false
    }

    func refreshOfficialUsageSectionIfNeeded(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) {
        refreshLocalUsageTrendIfNeeded(provider: provider, snapshot: snapshot)
    }

    @ViewBuilder
    func officialLocalTrendSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        showsDivider: Bool = true,
        title: String? = nil,
        showsTitle: Bool = true,
        usesSubscriptionUsageLayout: Bool = false
    ) -> some View {
        let context = localUsageTrendContext(for: provider, snapshot: snapshot)
        let scope = context.scope
        let selectedAccountKey = context.selectedAccountKey
        let identityCacheKey = context.identityCacheKey
        let query = context.query
        let historyState = viewModel.localUsageHistoryState(for: query)
        let strictSummary = historyState.summary
        let summary = localUsageTrendDisplaySummary(
            provider: provider,
            scope: scope,
            identityCacheKey: identityCacheKey,
            strictSummary: strictSummary
        ) ?? strictSummary
        let trendPresentation = LocalUsageTrendPresenter.presentation(
            providerType: provider.type,
            scope: scope,
            historyState: historyState,
            summary: summary,
            localizedText: { viewModel.localizedText($0, $1) },
            formatInteger: formattedSettingsInteger,
            dateText: localUsageTrendDiagnosticTimeText
        )
        let chartStatus = localUsageTrendChartStatus(from: trendPresentation.chartStatus)
        let displaySummary = trendPresentation.displaySummary

        VStack(alignment: .leading, spacing: 0) {
            if usesSubscriptionUsageLayout {
                localUsageSubscriptionTrendContent(
                    provider: provider,
                    scope: scope,
                    selectedAccountKey: selectedAccountKey,
                    accountOptions: context.accountOptions,
                    summary: displaySummary,
                    status: chartStatus
                )
                if let fallbackText = trendPresentation.staleFallbackText {
                    Text(fallbackText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color(hex: 0xD87E3E))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            } else {
                if showsDivider {
                    dividerLine
                }

                VStack(alignment: .leading, spacing: 0) {
                    if showsTitle {
                        Text(title ?? viewModel.localizedText("使用趋势", "Usage Trend"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(settingsBodyColor)
                    }

                    if localUsageTrendSupportsCurrentAccountScope(provider.type) {
                        localUsageTrendControls(
                            provider: provider,
                            scope: scope,
                            selectedAccountKey: selectedAccountKey,
                            accountOptions: context.accountOptions
                        )
                        .padding(.top, showsTitle ? 16 : 0)
                    }

                    localUsageTrendSummaryCapsule(displaySummary)
                        .padding(.top, 16)

                    if let fallbackText = trendPresentation.staleFallbackText {
                        Text(fallbackText)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color(hex: 0xD87E3E))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }

                    if let cacheStatusText = trendPresentation.cacheStatusText {
                        Text(cacheStatusText)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        localUsageHourlyTrendSection(
                            points: displaySummary?.hourly24 ?? [],
                            status: chartStatus,
                            hideVisualization: displaySummary == nil
                        )
                        localUsageWeeklyTrendSection(
                            points: displaySummary?.daily7 ?? [],
                            status: chartStatus,
                            hideVisualization: displaySummary == nil
                        )
                    }
                    .padding(.top, 16)
                }
                .padding(.top, showsDivider ? 24 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            refreshLocalUsageTrendIfNeeded(provider: provider, snapshot: snapshot)
        }
        .onChange(of: scope) { _, _ in
            refreshLocalUsageTrendIfNeeded(
                provider: provider,
                snapshot: snapshot
            )
        }
        .onChange(of: selectedAccountKey) { _, _ in
            refreshLocalUsageTrendIfNeeded(
                provider: provider,
                snapshot: snapshot
            )
        }
        .onChange(of: identityCacheKey) { _, _ in
            refreshLocalUsageTrendIfNeeded(
                provider: provider,
                snapshot: snapshot
            )
        }
    }

    private struct LocalUsageTrendContext {
        var scope: LocalUsageTrendScope
        var accountOptions: [LocalUsageTrendAccountOption]
        var selectedAccountKey: String?
        var identityCacheKey: String
        var query: LocalUsageHistoryQuery
    }

    private func localUsageTrendContext(
        for provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> LocalUsageTrendContext {
        let scope = localUsageTrendScope(for: provider)
        let accountOptions = localUsageTrendAccountOptions(for: provider, snapshot: snapshot)
        let selectedAccountKey = localUsageTrendSelectedAccountKey(
            providerID: provider.id,
            options: accountOptions
        )
        let identityContext = localUsageTrendIdentityContext(
            for: provider,
            snapshot: snapshot,
            selectedAccountKey: selectedAccountKey,
            accountOptions: accountOptions
        )
        let identityCacheKey = localUsageTrendEffectiveIdentityCacheKey(
            scope: scope,
            identityCacheKey: identityContext.cacheIdentity
        )
        let query = LocalUsageHistoryQuery(
            providerType: provider.type,
            providerID: provider.id,
            scope: scope,
            identityKey: identityCacheKey
        )

        return LocalUsageTrendContext(
            scope: scope,
            accountOptions: accountOptions,
            selectedAccountKey: selectedAccountKey,
            identityCacheKey: identityCacheKey,
            query: query
        )
    }

    private func localUsageTrendDiagnosticText(_ summary: LocalUsageSummary) -> String? {
        guard let diagnostics = summary.diagnostics else { return nil }
        let latestText = localUsageTrendDiagnosticTimeText(diagnostics.latestEventAt)
        let modeText = localUsageTrendDiagnosticSourceText(diagnostics.source)
        let recoveredResponses = formattedSettingsInteger(diagnostics.recoveredByConversationResponses)
        let recoveredTokens = formattedSettingsInteger(diagnostics.recoveredByConversationTokens)
        let unattributedResponses = formattedSettingsInteger(diagnostics.unattributedResponses)
        let unattributedTokens = formattedSettingsInteger(diagnostics.unattributedTokens)
        if viewModel.language == .zhHans {
            return "匹配事件 \(formattedSettingsInteger(diagnostics.matchedRows)) 条 · 可归属 \(formattedSettingsInteger(diagnostics.attributableEvents)) 条 · 会话回填 \(recoveredResponses) 条/\(recoveredTokens) Token · 未归属 \(unattributedResponses) 条/\(unattributedTokens) Token · 最近事件 \(latestText) · 口径 \(modeText)"
        }
        return "Matched \(formattedSettingsInteger(diagnostics.matchedRows)) · Attributable \(formattedSettingsInteger(diagnostics.attributableEvents)) · Recovered \(recoveredResponses)/\(recoveredTokens) tokens · Unattributed \(unattributedResponses)/\(unattributedTokens) tokens · Latest \(latestText) · Mode \(modeText)"
    }

    private func localUsageTrendDiagnosticSourceText(_ source: LocalUsageTrendDiagnosticsSource) -> String {
        switch source {
        case .strict:
            return viewModel.localizedText("严格", "strict")
        case .approximate:
            return viewModel.localizedText("近似", "approx")
        case .sessions:
            return viewModel.localizedText("会话", "sessions")
        }
    }

    private func localUsageTrendDiagnosticTimeText(_ date: Date?) -> String {
        LocalUsageTrendFormatter.diagnosticTime(date, language: viewModel.language)
    }

    private func localUsageTrendDataSourceText(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        summary: LocalUsageSummary?
    ) -> String {
        _ = summary
        switch provider.type {
        case .codex:
            if scope == .allAccounts {
                return viewModel.localizedText(
                    "数据来源：本地 ~/.codex/sessions（仅本地 Token，不等价于官方剩余额度）",
                    "Data source: local ~/.codex/sessions (local token usage only, not official remaining quota)."
                )
            }
            return viewModel.localizedText(
                "数据来源：本地 ~/.codex/logs_2.sqlite（当前账号可归属事件；缺失身份会按会话回填，仍无法归属会单独提示，仅本地 Token，不等价于官方剩余额度）",
                "Data source: local ~/.codex/logs_2.sqlite attributable events for current account; missing identity is recovered by conversation when possible, and still-unattributed events are shown separately (local token usage only, not official remaining quota)."
            )
        case .claude:
            if scope == .allAccounts {
                return viewModel.localizedText(
                    "数据来源：本地 ~/.claude/projects + 已绑定 CLAUDE_CONFIG_DIR/projects（仅本地 Token，不等价于官方剩余额度）",
                    "Data source: local ~/.claude/projects + bound CLAUDE_CONFIG_DIR/projects (local token usage only, not official remaining quota)."
                )
            }
            return viewModel.localizedText(
                "数据来源：当前账号 CLAUDE_CONFIG_DIR/projects（目录不可用时回退 ~/.claude/projects，仅本地 Token）",
                "Data source: current account CLAUDE_CONFIG_DIR/projects (fallback to ~/.claude/projects when missing, local token usage only)."
            )
        case .kimi:
            return viewModel.localizedText(
                "数据来源：本地 ~/.kimi/sessions/**/wire.jsonl（仅本地 Token，不等价于官方剩余额度）",
                "Data source: local ~/.kimi/sessions/**/wire.jsonl (local token usage only, not official remaining quota)."
            )
        case .gemini:
            return viewModel.localizedText(
                "数据来源：本地 ~/.gemini/tmp/*/chats/session-*.jsonl（仅本地 Token，不等价于官方剩余额度）",
                "Data source: local ~/.gemini/tmp/*/chats/session-*.jsonl (local token usage only, not official remaining quota)."
            )
        case .cursor:
            return viewModel.localizedText(
                "数据来源：Cursor 仪表盘用量事件，本地 state.vscdb 作回退（仅用量事件，不等价于官方剩余额度）",
                "Data source: Cursor dashboard usage events, with local state.vscdb fallback (usage events only, not official remaining quota)."
            )
        case .grok:
            return viewModel.localizedText(
                "数据来源：本地 ~/.grok/sessions（上下文增量估算，不等价于官方剩余额度）",
                "Data source: local ~/.grok/sessions (estimated from context growth, not official remaining quota)."
            )
        default:
            return viewModel.localizedText(
                "数据来源：本地日志（仅本地 Token）",
                "Data source: local logs (local token usage only)."
            )
        }
    }

    func localUsageTrendSupportsCurrentAccountScope(_ providerType: ProviderType) -> Bool {
        switch providerType {
        case .codex, .claude:
            return true
        default:
            return false
        }
    }

    func localUsageTrendScope(for provider: ProviderDescriptor) -> LocalUsageTrendScope {
        let fallback: LocalUsageTrendScope = localUsageTrendSupportsCurrentAccountScope(provider.type)
            ? .allAccounts
            : .allAccounts
        guard let stored = navigationState.localUsageTrendScopes[provider.id] else {
            return fallback
        }
        if !localUsageTrendSupportsCurrentAccountScope(provider.type) {
            return .allAccounts
        }
        return stored
    }

    func localUsageTrendScopeBinding(for provider: ProviderDescriptor) -> Binding<LocalUsageTrendScope> {
        Binding(
            get: { localUsageTrendScope(for: provider) },
            set: { newValue in
                if localUsageTrendSupportsCurrentAccountScope(provider.type) {
                    navigationState.localUsageTrendScopes[provider.id] = newValue
                } else {
                    navigationState.localUsageTrendScopes[provider.id] = .allAccounts
                }
            }
        )
    }

    func localUsageTrendSelectedAccountKey(
        providerID: String,
        options: [LocalUsageTrendAccountOption]
    ) -> String {
        guard !options.isEmpty else { return "" }
        if let stored = navigationState.localUsageTrendSelectedAccountKeys[providerID],
           options.contains(where: { $0.id == stored }) {
            return stored
        }
        return options[0].id
    }

    func localUsageTrendAccountOptions(
        for provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> [LocalUsageTrendAccountOption] {
        switch provider.type {
        case .codex:
            return localUsageTrendCodexAccountOptions(snapshot: snapshot)
        case .claude:
            return localUsageTrendClaudeAccountOptions(snapshot: snapshot)
        default:
            return []
        }
    }

    private func refreshLocalUsageTrendIfNeeded(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        force: Bool = false
    ) {
        let scope = localUsageTrendScope(for: provider)
        let accountOptions = localUsageTrendAccountOptions(for: provider, snapshot: snapshot)
        let selectedAccountKey = localUsageTrendSelectedAccountKey(
            providerID: provider.id,
            options: accountOptions
        )
        let identityContext = localUsageTrendIdentityContext(
            for: provider,
            snapshot: snapshot,
            selectedAccountKey: selectedAccountKey,
            accountOptions: accountOptions
        )
        let identityCacheKey = localUsageTrendEffectiveIdentityCacheKey(
            scope: scope,
            identityCacheKey: identityContext.cacheIdentity
        )
        let query = LocalUsageHistoryQuery(
            providerType: provider.type,
            providerID: provider.id,
            scope: scope,
            identityKey: identityCacheKey
        )

        viewModel.refreshLocalUsageHistoryIfNeeded(
            query: query,
            codexIdentity: identityContext.codexIdentity,
            claudeCurrentConfigDir: identityContext.claudeCurrentConfigDir,
            claudeAllConfigDirs: identityContext.claudeAllConfigDirs,
            force: force
        )
    }

    private func formattedSettingsInteger(_ value: Int) -> String {
        SharedNumberFormatting.groupedInteger(value)
    }
}
