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
                        Text(title ?? viewModel.text(.usageTrendTitle))
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

    private func localUsageTrendDiagnosticTimeText(_ date: Date?) -> String {
        LocalUsageTrendFormatter.diagnosticTime(date, language: viewModel.language)
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
