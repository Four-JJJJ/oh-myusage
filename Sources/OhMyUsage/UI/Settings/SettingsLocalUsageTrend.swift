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

    private func localUsageSubscriptionTrendContent(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        selectedAccountKey: String?,
        accountOptions: [LocalUsageTrendAccountOption],
        summary: LocalUsageSummary?,
        status: LocalUsageTrendChartStatus?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            localUsageSubscriptionTrendControls(
                provider: provider,
                scope: scope,
                selectedAccountKey: selectedAccountKey,
                accountOptions: accountOptions
            )

            localUsageSubscriptionSummaryCard(summary)
                .padding(.top, 16)

            localUsageSubscriptionHourlyTrendSection(
                points: summary?.hourly24 ?? [],
                status: status,
                hideVisualization: summary == nil
            )
            .padding(.top, 16)

            localUsageSubscriptionWeeklyTrendSection(
                points: summary?.daily7 ?? [],
                status: status,
                hideVisualization: summary == nil
            )
            .padding(.top, 24)
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(width: 566, height: 364, alignment: .topLeading)
    }

    private func localUsageSubscriptionTrendControls(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        selectedAccountKey: String?,
        accountOptions: [LocalUsageTrendAccountOption]
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            localUsageSubscriptionScopeSegmentControl(provider: provider, scope: scope)
                .frame(width: 116, height: 28)

            Spacer(minLength: 0)

            if scope == .currentAccount,
               localUsageTrendSupportsCurrentAccountScope(provider.type),
               !accountOptions.isEmpty {
                localUsageSubscriptionAccountSelector(
                    providerID: provider.id,
                    selectedAccountKey: selectedAccountKey,
                    options: accountOptions
                )
                .frame(width: 180, height: 28)
            }
        }
        .frame(width: 534, height: 28, alignment: .leading)
    }

    private func localUsageSubscriptionScopeSegmentControl(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope
    ) -> some View {
        SettingsPillSegmentedControl(
            options: [
                SettingsPillSegmentOption(id: LocalUsageTrendScope.allAccounts.id, title: viewModel.localizedText("全量", "All")),
                SettingsPillSegmentOption(id: LocalUsageTrendScope.currentAccount.id, title: viewModel.localizedText("账号", "Account"))
            ],
            selection: scope.id,
            backgroundColor: Color.white.opacity(0.15),
            selectedFillColor: Color.white.opacity(0.80),
            selectedTextColor: Color.black.opacity(0.88),
            textColor: Color.white.opacity(0.80),
            height: 28
        ) { newValue in
            if let nextScope = LocalUsageTrendScope.allCases.first(where: { $0.id == newValue }) {
                localUsageTrendScopeBinding(for: provider).wrappedValue = nextScope
            }
        }
    }

    private func localUsageSubscriptionAccountSelector(
        providerID: String,
        selectedAccountKey: String?,
        options: [LocalUsageTrendAccountOption]
    ) -> some View {
        let resolved = options.first(where: { $0.id == selectedAccountKey }) ?? options.first
        let isExpanded = navigationState.localUsageTrendExpandedAccountSelectorProviderID == providerID
        let selectorText = localUsageTrendTrimmed(resolved?.selectorLabel)
            ?? viewModel.localizedText("请选择账号", "Select account")

        return Button {
            navigationState.localUsageTrendExpandedAccountSelectorProviderID = isExpanded ? nil : providerID
        } label: {
            HStack(spacing: 8) {
                Text(selectorText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.40))
                    .frame(width: 12, height: 12, alignment: .center)
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(width: 180, height: 28, alignment: .leading)
            .background(
                SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.15))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: localUsageTrendAccountSelectorExpandedBinding(providerID: providerID),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            localUsageTrendAccountSelectorPopover(
                providerID: providerID,
                selectedAccountKey: selectedAccountKey,
                options: options
            )
        }
    }

    @ViewBuilder
    private func localUsageSubscriptionSummaryCard(_ summary: LocalUsageSummary?) -> some View {
        HStack(alignment: .center, spacing: 0) {
            if let summary {
                localUsageSubscriptionSummaryItem(
                    label: viewModel.localizedText("今日", "Today"),
                    period: summary.today
                )

                Spacer(minLength: 0)

                localUsageSubscriptionSummaryItem(
                    label: viewModel.localizedText("昨日", "Yesterday"),
                    period: summary.yesterday
                )

                Spacer(minLength: 0)

                localUsageSubscriptionSummaryItem(
                    label: viewModel.localizedText("近30日", "Last 30d"),
                    period: summary.last30Days
                )
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 534, height: 64, alignment: .center)
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func localUsageSubscriptionSummaryItem(
        label: String,
        period: LocalUsagePeriodSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.40))
                .lineLimit(1)
                .frame(height: 10, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                Text(localUsageSubscriptionTokenText(period.totalTokens))
                    .font(AppFonts.numeric(size: 14, fallbackWeight: .bold))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)

                SettingsSmoothedRoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.40))
                    .frame(width: 1, height: 8)

                Text(localUsageSubscriptionCallText(period.responses))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
            }
            .frame(height: 14, alignment: .leading)
        }
        .frame(height: 32, alignment: .leading)
    }

    private func localUsageSubscriptionHourlyTrendSection(
        points: [LocalUsageTrendPoint],
        status: LocalUsageTrendChartStatus?,
        hideVisualization: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.localizedText("24小时趋势", "24h Trend"))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.80))
                .frame(width: 534, height: 12, alignment: .leading)

            if hideVisualization, let status {
                localUsageTrendStatusPlaceholder(
                    text: status.text,
                    color: status.color,
                    height: 64
                )
                .padding(.top, 12)
            } else {
                LocalUsageTrendHourlyBarsView(
                    points: points,
                    language: viewModel.language,
                    localizedText: { viewModel.localizedText($0, $1) },
                    appearance: .subscription()
                )
                .frame(width: 534, height: 64)
                .padding(.top, 12)
            }
        }
        .frame(width: 534, height: 88, alignment: .topLeading)
    }

    private func localUsageSubscriptionWeeklyTrendSection(
        points: [LocalUsageTrendPoint],
        status: LocalUsageTrendChartStatus?,
        hideVisualization: Bool
    ) -> some View {
        let displayPoints = hideVisualization ? [] : localUsageWeeklyDisplayPoints(points)

        return VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.localizedText("7天趋势", "7d Trend"))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.80))
                .frame(width: 534, height: 12, alignment: .leading)

            if hideVisualization, let status {
                localUsageTrendStatusPlaceholder(
                    text: status.text,
                    color: status.color,
                    height: 64
                )
                .padding(.top, 12)
            } else {
                localUsageSubscriptionWeeklyChart(points: displayPoints)
                    .padding(.top, 12)

                HStack(spacing: 0) {
                    ForEach(displayPoints) { point in
                        Text(localUsageWeeklyLabel(point.startAt))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.40))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 534, height: 10)
                .padding(.top, 4)
            }
        }
        .frame(width: 534, height: 88, alignment: .topLeading)
    }

    private func localUsageSubscriptionWeeklyChart(points: [LocalUsageTrendPoint]) -> some View {
        GeometryReader { proxy in
            let metric = localUsageTrendDisplayMetric(points: points)
            let values = points.map { localUsageTrendValue($0, metric: metric) }
            let maxValue = max(values.max() ?? 0, 1)
            let count = max(points.count, 1)
            let stepX = proxy.size.width / CGFloat(count)

            Path { path in
                for (index, point) in points.enumerated() {
                    let x = stepX * (CGFloat(index) + 0.5)
                    let y = localUsageTrendY(
                        value: localUsageTrendValue(point, metric: metric),
                        maxValue: maxValue,
                        height: proxy.size.height
                    )
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                Color.white.opacity(0.55),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 534, height: 50)
    }

    private func localUsageSubscriptionTokenText(_ value: Int) -> String {
        "\(localUsageSubscriptionCompactTokenNumber(value)) tok"
    }

    private func localUsageSubscriptionCallText(_ value: Int) -> String {
        let safeValue = max(0, value)
        if safeValue >= 10_000 {
            return "\(localUsageSubscriptionCompactDecimal(Double(safeValue) / 10_000)) w calls"
        }
        return "\(safeValue) calls"
    }

    private func localUsageSubscriptionCompactTokenNumber(_ value: Int) -> String {
        let safeValue = max(0, value)
        if safeValue >= 1_000_000_000 {
            return "\(localUsageSubscriptionCompactDecimal(Double(safeValue) / 1_000_000_000))B"
        }
        if safeValue >= 10_000 {
            return "\(localUsageSubscriptionCompactDecimal(Double(safeValue) / 10_000))w"
        }
        return "\(safeValue)"
    }

    private func localUsageSubscriptionCompactDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.000_1 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    @ViewBuilder
    private func localUsageTrendControls(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        selectedAccountKey: String?,
        accountOptions: [LocalUsageTrendAccountOption]
    ) -> some View {
        let showsAccountSelector = scope == .currentAccount && !accountOptions.isEmpty

        if showsAccountSelector {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    localUsageTrendScopeSegmentControl(provider: provider)
                        .frame(width: localUsageTrendScopeControlWidth, height: 24)

                    Spacer(minLength: 12)

                    localUsageTrendAccountSelector(
                        providerID: provider.id,
                        selectedAccountKey: selectedAccountKey,
                        options: accountOptions
                    )
                    .frame(width: 205, height: 24, alignment: .trailing)
                    .frame(height: 24)
                }

                VStack(alignment: .leading, spacing: 10) {
                    localUsageTrendScopeSegmentControl(provider: provider)
                        .frame(width: localUsageTrendScopeControlWidth, height: 24)

                    localUsageTrendAccountSelector(
                        providerID: provider.id,
                        selectedAccountKey: selectedAccountKey,
                        options: accountOptions
                    )
                    .frame(width: 205, alignment: .leading)
                    .frame(height: 24)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                localUsageTrendScopeSegmentControl(provider: provider)
                    .frame(width: localUsageTrendScopeControlWidth, height: 24)
                Spacer(minLength: 0)
            }
        }
    }

    private var localUsageTrendScopeControlWidth: CGFloat {
        viewModel.language == .zhHans ? 140 : 170
    }

    private func localUsageTrendScopeSegmentControl(provider: ProviderDescriptor) -> some View {
        Picker("", selection: Binding(
            get: { localUsageTrendScope(for: provider).id },
            set: { newValue in
                if let scope = LocalUsageTrendScope.allCases.first(where: { $0.id == newValue }) {
                    localUsageTrendScopeBinding(for: provider).wrappedValue = scope
                }
            }
        )) {
            Text(viewModel.localizedText("全量", "All")).tag(LocalUsageTrendScope.allAccounts.id)
            Text(viewModel.localizedText("按账号", "By Account")).tag(LocalUsageTrendScope.currentAccount.id)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(height: 24)
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

    @ViewBuilder
    private func localUsageHourlyTrendSection(
        points: [LocalUsageTrendPoint],
        status: LocalUsageTrendChartStatus?,
        hideVisualization: Bool
    ) -> some View {
        let displayPoints = hideVisualization ? [] : points

        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.localizedText("24小时趋势", "24h Trend"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            if hideVisualization, let status {
                localUsageTrendStatusPlaceholder(
                    text: status.text,
                    color: status.color,
                    height: 50
                )
                .padding(.top, 12)
            } else {
                LocalUsageTrendHourlyBarsView(
                    points: displayPoints,
                    language: viewModel.language,
                    localizedText: { viewModel.localizedText($0, $1) },
                    appearance: .settings(
                        filledBarColor: settingsTrendPrimaryColor,
                        emptyBarColor: settingsTrendMutedColor,
                        axisLabelColor: settingsHintColor,
                        usesLightAppearance: settingsUsesLightAppearance
                    )
                )
                .padding(.top, 12)
            }

            localUsageHourlyAxisLabels(points: displayPoints)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func localUsageHourlyAxisLabels(points: [LocalUsageTrendPoint]) -> some View {
        if !points.isEmpty {
            GeometryReader { proxy in
                let count = max(points.count, 1)
                let barWidth: CGFloat = 12
                let step = count > 1 ? (proxy.size.width - barWidth) / CGFloat(count - 1) : 0

                ZStack(alignment: .topLeading) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        let rawX = CGFloat(index) * step + barWidth / 2
                        let clampedX = min(max(12, rawX), max(12, proxy.size.width - 12))
                        Text(localUsageHourlyLabel(point.startAt))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: 24, alignment: .center)
                            .position(
                                x: clampedX,
                                y: 7
                            )
                    }
                }
            }
            .frame(height: 14)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(settingsHintColor)
        } else {
            Color.clear
                .frame(height: 14)
        }
    }

    @ViewBuilder
    private func localUsageWeeklyTrendSection(
        points: [LocalUsageTrendPoint],
        status: LocalUsageTrendChartStatus?,
        hideVisualization: Bool
    ) -> some View {
        let displayPoints = hideVisualization ? [] : localUsageWeeklyDisplayPoints(points)
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.localizedText("7天趋势", "7d Trend"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            if hideVisualization, let status {
                localUsageTrendStatusPlaceholder(
                    text: status.text,
                    color: status.color,
                    height: 50
                )
                .padding(.top, 12)
            } else {
                localUsageWeeklyTrendChart(points: displayPoints)
                    .padding(.top, 12)
            }

            HStack(spacing: 0) {
                ForEach(displayPoints) { point in
                    Text(localUsageWeeklyLabel(point.startAt))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
            .padding(.top, 8)
        }
    }

    private func localUsageTrendStatusPlaceholder(
        text: String,
        color: Color,
        height: CGFloat
    ) -> some View {
        ZStack {
            Color.clear
            Text(text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func localUsageTrendChartStatus(
        from presentation: LocalUsageTrendStatusPresentation?
    ) -> LocalUsageTrendChartStatus? {
        guard let presentation else { return nil }
        let color: Color
        switch presentation.tone {
        case .muted:
            color = settingsMutedHintColor
        case .error:
            color = Color(hex: 0xD05757)
        }
        return LocalUsageTrendChartStatus(text: presentation.text, color: color)
    }

    private func localUsageWeeklyTrendChart(points: [LocalUsageTrendPoint]) -> some View {
        GeometryReader { proxy in
            let metric = localUsageTrendDisplayMetric(points: points)
            let values = points.map { localUsageTrendValue($0, metric: metric) }
            let maxValue = max(values.max() ?? 0, 1)
            let count = max(points.count, 1)
            let stepX = proxy.size.width / CGFloat(count)

            ZStack {
                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = stepX * (CGFloat(index) + 0.5)
                        let y = localUsageTrendY(
                            value: localUsageTrendValue(point, metric: metric),
                            maxValue: maxValue,
                            height: proxy.size.height
                        )
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    settingsTrendPrimaryColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(height: 50)
    }

    private func localUsageTrendDisplayMetric(points: [LocalUsageTrendPoint]) -> LocalTrendDisplayMetric {
        if points.contains(where: { $0.totalTokens > 0 }) {
            return .tokens
        }
        return .responses
    }

    private func localUsageTrendValue(_ point: LocalUsageTrendPoint, metric: LocalTrendDisplayMetric) -> Double {
        switch metric {
        case .tokens:
            return Double(max(0, point.totalTokens))
        case .responses:
            return Double(max(0, point.responses))
        }
    }

    private func localUsageTrendY(value: Double, maxValue: Double, height: CGFloat) -> CGFloat {
        let drawableHeight = max(8, height - 6)
        let ratio = maxValue > 0 ? CGFloat(value / maxValue) : 0
        return height - max(3, drawableHeight * ratio + 3)
    }

    private func localUsageWeeklyLabel(_ date: Date) -> String {
        LocalUsageTrendFormatter.weeklyLabel(date, language: viewModel.language)
    }

    private func localUsageHourlyLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func localUsageTrendSummaryCapsule(_ summary: LocalUsageSummary?) -> some View {
        HStack(alignment: .center, spacing: 0) {
            if let summary {
                HStack(spacing: 16) {
                    localUsageTrendSummaryItem(
                        label: viewModel.localizedText("今日", "Today"),
                        period: summary.today
                    )
                    localUsageTrendSummaryItem(
                        label: viewModel.localizedText("昨日", "Yesterday"),
                        period: summary.yesterday
                    )
                }

                Spacer(minLength: 0)

                localUsageTrendSummaryItem(
                    label: viewModel.localizedText("近30日", "Last 30d"),
                    period: summary.last30Days
                )
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(settingsRowStrokeColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func localUsageTrendSummaryItem(label: String, period: LocalUsagePeriodSummary) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(settingsHintColor)

            Text(LocalTrendValueFormatter.metricValueText(value: period.totalTokens, metric: .tokens, language: viewModel.language))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            localUsageTrendSummaryDivider

            Text(localUsageTrendResponseText(period.responses))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settingsBodyColor)
        }
        .lineLimit(1)
    }

    private var localUsageTrendSummaryDivider: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(settingsRowStrokeColor)
            .frame(width: 1, height: 8)
    }

    private func localUsageTrendSummaryValueText(_ period: LocalUsagePeriodSummary) -> String {
        let tokens = LocalTrendValueFormatter.metricValueText(value: period.totalTokens, metric: .tokens, language: viewModel.language)
        let responses = localUsageTrendResponseText(period.responses)
        return "\(tokens) | \(responses)"
    }

    private func localUsageTrendResponseText(_ value: Int) -> String {
        LocalTrendValueFormatter.responseCountText(value, language: viewModel.language)
    }

    private func localUsageWeeklyDisplayPoints(_ points: [LocalUsageTrendPoint]) -> [LocalUsageTrendPoint] {
        guard points.count == 7 else { return points }
        return points.sorted { lhs, rhs in
            localUsageWeekdayOrder(lhs.startAt) < localUsageWeekdayOrder(rhs.startAt)
        }
    }

    private func localUsageWeekdayOrder(_ date: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        switch calendar.component(.weekday, from: date) {
        case 2: return 0
        case 3: return 1
        case 4: return 2
        case 5: return 3
        case 6: return 4
        case 7: return 5
        default: return 6
        }
    }

    @ViewBuilder
    private func localUsageTrendAccountSelector(
        providerID: String,
        selectedAccountKey: String?,
        options: [LocalUsageTrendAccountOption]
    ) -> some View {
        let resolved = options.first(where: { $0.id == selectedAccountKey }) ?? options.first
        let isExpanded = navigationState.localUsageTrendExpandedAccountSelectorProviderID == providerID
        let selectorText = localUsageTrendTrimmed(resolved?.selectorLabel)
            ?? viewModel.localizedText("请选择账号", "Select account")

        Button {
            navigationState.localUsageTrendExpandedAccountSelectorProviderID = isExpanded ? nil : providerID
        } label: {
            HStack(spacing: 8) {
                Text(selectorText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(settingsBodyColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settingsHintColor)
                    .frame(width: 14, height: 14, alignment: .center)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(settingsControlFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(settingsControlStrokeColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: localUsageTrendAccountSelectorExpandedBinding(providerID: providerID),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            localUsageTrendAccountSelectorPopover(
                providerID: providerID,
                selectedAccountKey: selectedAccountKey,
                options: options
            )
        }
    }

    private func localUsageTrendAccountSelectorExpandedBinding(providerID: String) -> Binding<Bool> {
        Binding(
            get: { navigationState.localUsageTrendExpandedAccountSelectorProviderID == providerID },
            set: { isPresented in
                if isPresented {
                    navigationState.localUsageTrendExpandedAccountSelectorProviderID = providerID
                } else if navigationState.localUsageTrendExpandedAccountSelectorProviderID == providerID {
                    navigationState.localUsageTrendExpandedAccountSelectorProviderID = nil
                }
            }
        )
    }

    private func localUsageTrendAccountSelectorPopover(
        providerID: String,
        selectedAccountKey: String?,
        options: [LocalUsageTrendAccountOption]
    ) -> some View {
        let selectedID = selectedAccountKey ?? options.first?.id
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(options) { option in
                Button {
                    navigationState.localUsageTrendSelectedAccountKeys[providerID] = option.id
                    navigationState.localUsageTrendExpandedAccountSelectorProviderID = nil
                } label: {
                    HStack(spacing: 8) {
                        Text(option.label)
                            .font(.system(size: 12, weight: option.id == selectedID ? .semibold : .regular))
                            .foregroundStyle(option.id == selectedID ? settingsTitleColor : settingsBodyColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        if option.id == selectedID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(settingsAccentBlue)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(option.id == selectedID ? settingsPopoverSelectedFillColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(settingsPopoverFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(settingsControlStrokeColor, lineWidth: 1)
        )
    }

    func localUsageTrendSummaryText(_ summary: LocalUsageSummary) -> String {
        let today = "\(viewModel.localizedText("今日", "Today")) \(localUsageTrendSummaryValueText(summary.today))"
        let yesterday = "\(viewModel.localizedText("昨日", "Yesterday")) \(localUsageTrendSummaryValueText(summary.yesterday))"
        let last30 = "\(viewModel.localizedText("近30日", "Last 30d")) \(localUsageTrendSummaryValueText(summary.last30Days))"
        return "\(today) · \(yesterday) · \(last30)"
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

    private func localUsageTrendSupportsCurrentAccountScope(_ providerType: ProviderType) -> Bool {
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

    private func localUsageTrendScopeBinding(for provider: ProviderDescriptor) -> Binding<LocalUsageTrendScope> {
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
