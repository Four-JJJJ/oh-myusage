import SwiftUI

extension SettingsView {
    @ViewBuilder
    func localUsageHourlyTrendSection(
        points: [LocalUsageTrendPoint],
        status: LocalUsageTrendChartStatus?,
        hideVisualization: Bool
    ) -> some View {
        let displayPoints = hideVisualization ? [] : points

        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.text(.usageTrend24Hours))
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
    func localUsageWeeklyTrendSection(
        points: [LocalUsageTrendPoint],
        status: LocalUsageTrendChartStatus?,
        hideVisualization: Bool
    ) -> some View {
        let displayPoints = hideVisualization ? [] : localUsageWeeklyDisplayPoints(points)
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.text(.usageTrend7Days))
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

    func localUsageTrendStatusPlaceholder(
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

    func localUsageTrendChartStatus(
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

    func localUsageTrendDisplayMetric(points: [LocalUsageTrendPoint]) -> LocalTrendDisplayMetric {
        if points.contains(where: { $0.totalTokens > 0 }) {
            return .tokens
        }
        return .responses
    }

    func localUsageTrendValue(_ point: LocalUsageTrendPoint, metric: LocalTrendDisplayMetric) -> Double {
        switch metric {
        case .tokens:
            return Double(max(0, point.totalTokens))
        case .responses:
            return Double(max(0, point.responses))
        }
    }

    func localUsageTrendY(value: Double, maxValue: Double, height: CGFloat) -> CGFloat {
        let drawableHeight = max(8, height - 6)
        let ratio = maxValue > 0 ? CGFloat(value / maxValue) : 0
        return height - max(3, drawableHeight * ratio + 3)
    }

    func localUsageWeeklyLabel(_ date: Date) -> String {
        LocalUsageTrendFormatter.weeklyLabel(date, language: viewModel.language)
    }

    private func localUsageHourlyLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH"
        return formatter.string(from: date)
    }

    @ViewBuilder
    func localUsageTrendSummaryCapsule(_ summary: LocalUsageSummary?) -> some View {
        HStack(alignment: .center, spacing: 0) {
            if let summary {
                HStack(spacing: 16) {
                    localUsageTrendSummaryItem(
                        label: viewModel.text(.usageTrendToday),
                        period: summary.today
                    )
                    localUsageTrendSummaryItem(
                        label: viewModel.text(.usageTrendYesterday),
                        period: summary.yesterday
                    )
                }

                Spacer(minLength: 0)

                localUsageTrendSummaryItem(
                    label: viewModel.text(.usageTrendLast30Days),
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

    func localUsageWeeklyDisplayPoints(_ points: [LocalUsageTrendPoint]) -> [LocalUsageTrendPoint] {
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

    func localUsageTrendSummaryText(_ summary: LocalUsageSummary) -> String {
        let today = "\(viewModel.text(.usageTrendToday)) \(localUsageTrendSummaryValueText(summary.today))"
        let yesterday = "\(viewModel.text(.usageTrendYesterday)) \(localUsageTrendSummaryValueText(summary.yesterday))"
        let last30 = "\(viewModel.text(.usageTrendLast30Days)) \(localUsageTrendSummaryValueText(summary.last30Days))"
        return "\(today) · \(yesterday) · \(last30)"
    }
}
