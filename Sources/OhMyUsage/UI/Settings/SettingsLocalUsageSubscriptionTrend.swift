import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    func localUsageSubscriptionTrendContent(
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
                SettingsPillSegmentOption(id: LocalUsageTrendScope.allAccounts.id, title: viewModel.text(.usageTrendScopeAll)),
                SettingsPillSegmentOption(id: LocalUsageTrendScope.currentAccount.id, title: viewModel.text(.usageTrendScopeAccount))
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
            ?? viewModel.text(.usageTrendSelectAccount)

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
                    label: viewModel.text(.usageTrendToday),
                    period: summary.today
                )

                Spacer(minLength: 0)

                localUsageSubscriptionSummaryItem(
                    label: viewModel.text(.usageTrendYesterday),
                    period: summary.yesterday
                )

                Spacer(minLength: 0)

                localUsageSubscriptionSummaryItem(
                    label: viewModel.text(.usageTrendLast30Days),
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
            Text(viewModel.text(.usageTrend24Hours))
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
            Text(viewModel.text(.usageTrend7Days))
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
}
