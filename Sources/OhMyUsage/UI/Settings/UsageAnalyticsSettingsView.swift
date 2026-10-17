import SwiftUI

struct UsageAnalyticsSettingsView: View {
    @Bindable var viewModel: AppViewModel
    var theme: SettingsTheme
#if DEBUG
    var rendersLocalizationFixture = false
    var localizationFixtureSnapshot: UsageAnalyticsSnapshot? = nil
#endif

    @State private var hoveredBucketID: String?
    @State private var selectedStatisticsBreakdown: UsageStatisticsBreakdown = .provider

    private var copy: UsageAnalyticsCopy { UsageAnalyticsCopy(language: viewModel.language) }

    private var snapshot: UsageAnalyticsSnapshot {
#if DEBUG
        if let localizationFixtureSnapshot { return localizationFixtureSnapshot }
#endif
        return viewModel.usageAnalyticsSnapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            topControls

            scrollableModules
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.usageAnalyticsLanguage, viewModel.language)
        .onAppear {
#if DEBUG
            guard !rendersLocalizationFixture else { return }
#endif
            viewModel.usageAnalyticsFilter.mode = .all
            viewModel.usageAnalyticsFilter.selectedModelID = nil
            viewModel.refreshUsageAnalyticsIfNeeded(force: false)
        }
        .onChange(of: viewModel.usageAnalyticsFilter.range) { _, _ in
            viewModel.refreshUsageAnalyticsIfNeeded(force: false)
        }
    }

    @ViewBuilder
    private var scrollableModules: some View {
#if DEBUG
        if rendersLocalizationFixture {
            analyticsModules
        } else {
            ScrollView { analyticsModules }.scrollIndicators(.never)
        }
#else
        ScrollView { analyticsModules }.scrollIndicators(.never)
#endif
    }

    private var analyticsModules: some View {
        VStack(alignment: .leading, spacing: 24) {
            overviewModule
            trendModule
            statisticsModule
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var topControls: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsPillSegmentedControl(
                options: timeRangeOptions.map {
                    SettingsPillSegmentOption(id: $0, title: copy.timeRangeTitle($0))
                },
                selection: viewModel.usageAnalyticsFilter.range,
                backgroundColor: Color.white.opacity(0.15),
                selectedFillColor: Color.white.opacity(0.80),
                selectedTextColor: Color.black.opacity(0.88),
                textColor: Color.white.opacity(0.80),
                height: 24,
                segmentWidths: [
                    .all: 48,
                    .last24Hours: 80,
                    .last7Days: 58,
                    .last30Days: 66
                ]
            ) { range in
                viewModel.usageAnalyticsFilter.range = range
            }
            .frame(width: 252, height: 24)

            Button {
                viewModel.refreshUsageAnalytics()
            } label: {
                Image(systemName: viewModel.usageAnalyticsLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(usageText80)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(copy.text(.refresh))
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewModule: some View {
        module(title: copy.text(.overview), subtitle: sourceSubtitle) {
            UsageOverviewMetricsGrid(totals: snapshot.totals)
        }
    }

    private var sourceSubtitle: String {
        copy.diagnostic(snapshot.diagnostics.first ?? "")
    }

    private var trendModule: some View {
        module(title: copy.text(.trend), subtitle: "") {
            VStack(alignment: .leading, spacing: 16) {
                UsageTrendChartView(
                    buckets: snapshot.trendBuckets,
                    hoveredBucketID: $hoveredBucketID,
                    selectedBucketID: focusedTrendBucket?.id
                )
                .frame(height: 128)

                Rectangle()
                    .fill(theme.subtlePanelStrokeColor)
                    .frame(height: 1)

                if let bucket = focusedTrendBucket {
                    UsageHoverDetailView(bucket: bucket)
                }
            }
        }
    }

    private var statisticsModule: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.text(.statistics))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(usageText80)
                .frame(height: 12, alignment: .leading)

            SettingsPillSegmentedControl(
                options: UsageStatisticsBreakdown.allCases.map {
                    SettingsPillSegmentOption(id: $0, title: $0 == .provider ? copy.text(.provider) : copy.text(.model))
                },
                selection: selectedStatisticsBreakdown,
                backgroundColor: Color.white.opacity(0.15),
                selectedFillColor: Color.white.opacity(0.80),
                selectedTextColor: Color.black.opacity(0.88),
                textColor: Color.white.opacity(0.80),
                height: 24,
                segmentWidths: [
                    .provider: viewModel.language == .en ? 74 : 58,
                    .model: viewModel.language == .en ? 56 : 48
                ]
            ) { selection in
                selectedStatisticsBreakdown = selection
            }
            .frame(width: viewModel.language == .en ? 130 : 106, height: 24)

            UsagePieAndTableView(
                pieItems: statisticsPieItems,
                rows: statisticsRows,
                theme: theme
            )
        }
    }

    private var statisticsPieItems: [UsagePieItem] {
        switch selectedStatisticsBreakdown {
        case .provider:
            return snapshot.providerStats.map {
                UsagePieItem(id: $0.id, title: $0.providerName, share: $0.share)
            }
        case .model:
            return snapshot.modelStats.map {
                UsagePieItem(id: $0.id, title: $0.modelID, share: $0.share)
            }
        }
    }

    private var statisticsRows: [UsageStatsTableRow] {
        switch selectedStatisticsBreakdown {
        case .provider:
            return snapshot.providerStats.map {
                UsageStatsTableRow(
                    id: $0.id,
                    title: $0.providerName,
                    totals: $0.totals
                )
            }
        case .model:
            return snapshot.modelStats.map {
                UsageStatsTableRow(
                    id: $0.id,
                    title: $0.modelID,
                    totals: $0.totals
                )
            }
        }
    }

    private func module<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(usageText80)
                .frame(height: 12, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(usageText40)
                        .lineLimit(2)
                }
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                SettingsSmoothedRoundedRectangle(cornerRadius: theme.sectionCornerRadius)
                    .fill(Color.clear)
            )
            .overlay(
                SettingsSmoothedRoundedRectangle(cornerRadius: theme.sectionCornerRadius)
                    .stroke(theme.subtlePanelStrokeColor, lineWidth: 1)
            )
        }
    }

    private var hoveredBucket: UsageTrendBucket? {
        guard let hoveredBucketID else { return nil }
        return snapshot.trendBuckets.first { $0.id == hoveredBucketID }
    }

    private var focusedTrendBucket: UsageTrendBucket? {
        hoveredBucket
            ?? snapshot.trendBuckets.last(where: { $0.totals.totalTokens > 0 })
            ?? snapshot.trendBuckets.last
    }
}

private enum UsageStatisticsBreakdown: String, CaseIterable, Hashable {
    case provider
    case model


}

private let timeRangeOptions: [UsageAnalyticsRange] = [
    .all,
    .last24Hours,
    .last7Days,
    .last30Days
]

private let usageText80 = Color.white.opacity(0.80)
private let usageText55 = Color.white.opacity(0.55)
private let usageText40 = Color.white.opacity(0.40)
private let usageText30 = Color.white.opacity(0.30)

private struct UsageOverviewMetricsGrid: View {
    @Environment(\.usageAnalyticsLanguage) private var language
    private var copy: UsageAnalyticsCopy { UsageAnalyticsCopy(language: language) }
    var totals: UsageMetricTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                UsageMetricTile(title: copy.text(.requests), value: tokenText(totals.requestCount))
                UsageMetricTile(title: copy.text(.tokens), value: tokenText(totals.totalTokens))
                UsageMetricTile(title: copy.text(.input), value: tokenText(totals.inputTokens))
                UsageMetricTile(title: copy.text(.output), value: tokenText(totals.outputTokens))
            }

            HStack(spacing: 24) {
                UsageMetricTile(title: copy.text(.cacheRead), value: tokenText(totals.cacheReadTokens))
                UsageMetricTile(title: copy.text(.cacheWrite), value: tokenText(totals.cacheWriteTokens))
                UsageMetricTile(title: copy.text(.cacheRate), value: percentText(totals.cacheRate))
                UsageMetricTile(title: copy.text(.successRate), value: percentText(totals.successRate))
            }
        }
    }
}

private struct UsageMetricTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(usageText40)
                .lineLimit(1)
            Text(value)
                .font(AppFonts.numeric(size: 14, fallbackWeight: .semibold))
                .foregroundStyle(usageText80)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageTrendChartView: View {
    @Environment(\.usageAnalyticsLanguage) private var language
    private var copy: UsageAnalyticsCopy { UsageAnalyticsCopy(language: language) }
    var buckets: [UsageTrendBucket]
    @Binding var hoveredBucketID: String?
    var selectedBucketID: String?

    var body: some View {
        GeometryReader { proxy in
            let maxTokens = max(1, buckets.map { $0.totals.totalTokens }.max() ?? 1)
            let activeBucketID = hoveredBucketID ?? selectedBucketID
            HStack(alignment: .bottom, spacing: 6) {
                if buckets.isEmpty {
                    Text(copy.text(.emptyTrend))
                        .font(.system(size: 12))
                        .foregroundStyle(usageText55)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ForEach(buckets) { bucket in
                        let ratio = CGFloat(bucket.totals.totalTokens) / CGFloat(maxTokens)
                        let isActive = bucket.id == activeBucketID
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isActive ? usageText80 : usageText40)
                                    .frame(width: 16, height: max(4, ratio * (proxy.size.height - 18)))
                            }
                            .frame(maxWidth: .infinity)

                            Text(copy.trendTickLabel(bucket.startAt, endAt: bucket.endAt))
                                .font(usageTrendLabelFont(isActive: isActive))
                                .foregroundStyle(isActive ? usageText80 : usageText40)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(height: 10)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard !buckets.isEmpty, proxy.size.width > 0 else { return }
                    let widthPerBucket = proxy.size.width / CGFloat(buckets.count)
                    let index = min(max(0, Int(location.x / max(1, widthPerBucket))), buckets.count - 1)
                    hoveredBucketID = buckets[index].id
                case .ended:
                    hoveredBucketID = nil
                }
            }
        }
    }
}

private struct UsageHoverDetailView: View {
    @Environment(\.usageAnalyticsLanguage) private var language
    private var copy: UsageAnalyticsCopy { UsageAnalyticsCopy(language: language) }
    var bucket: UsageTrendBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shortDate(bucket.startAt))
                .font(usagePingFangFont(size: 10, weight: .semibold))
                .foregroundStyle(usageText80)

            HStack(spacing: 24) {
                detail(copy.text(.tokens), tokenText(bucket.totals.totalTokens))
                detail(copy.text(.input), tokenText(bucket.totals.inputTokens))
                detail(copy.text(.output), tokenText(bucket.totals.outputTokens))
                detail(copy.text(.cacheRead), tokenText(bucket.totals.cacheReadTokens))
                detail(copy.text(.cacheWrite), tokenText(bucket.totals.cacheWriteTokens))
                detail(copy.text(.cacheRate), percentText(bucket.totals.cacheRate))
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(usagePingFangFont(size: 10, weight: .regular))
                .foregroundStyle(usageText40)
            Text(value)
                .font(AppFonts.numeric(size: 14, fallbackWeight: .bold))
                .foregroundStyle(usageText80)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsagePieItem: Identifiable {
    var id: String
    var title: String
    var share: Double
}

private struct UsageStatsTableRow: Identifiable {
    var id: String
    var title: String
    var totals: UsageMetricTotals
}

private struct UsagePieAndTableView: View {
    var pieItems: [UsagePieItem]
    var rows: [UsageStatsTableRow]
    var theme: SettingsTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 40) {
                Spacer(minLength: 0)

                UsagePieChartView(items: pieItems, theme: theme)
                    .frame(width: 160, height: 160)

                legend
                    .frame(width: 260, alignment: .leading)

                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(theme.subtlePanelStrokeColor)
                .frame(height: 1)

            UsageStatsTableView(rows: rows, theme: theme)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                .stroke(theme.subtlePanelStrokeColor, lineWidth: 1)
        )
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(pieItems.prefix(6).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(pieColor(index, theme: theme))
                        .frame(width: 6, height: 6)
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(usageText55)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(percentText(item.share))
                        .font(AppFonts.numeric(size: 12, fallbackWeight: .semibold))
                        .foregroundStyle(usageText55)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct UsagePieChartView: View {
    var items: [UsagePieItem]
    var theme: SettingsTheme

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ringFrame = max(28, side - 6)
            let innerRatio = 0.62
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                if items.isEmpty {
                    Circle()
                        .stroke(
                            theme.subtlePanelStrokeColor.opacity(0.60),
                            style: StrokeStyle(lineWidth: max(16, side * 0.24), lineCap: .butt)
                        )
                        .frame(width: ringFrame, height: ringFrame)
                        .position(center)
                } else {
                    let segments = ringSegments
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        UsageDonutSegmentShape(
                            start: Angle(degrees: segment.startDegrees),
                            end: Angle(degrees: segment.endDegrees),
                            innerRatio: innerRatio
                        )
                        .fill(pieColor(index, theme: theme))
                        .frame(width: ringFrame, height: ringFrame)
                        .position(center)
                    }

                    Circle()
                        .fill(theme.sectionFillColor)
                        .frame(
                            width: ringFrame * innerRatio + 2,
                            height: ringFrame * innerRatio + 2
                        )
                        .position(center)
                }
            }
        }
    }

    private var ringSegments: [UsageRingSegment] {
        let visibleItems = items.filter { $0.share > 0 }
        guard !visibleItems.isEmpty else { return [] }

        let gap = visibleItems.count == 1 ? 0 : 1.5
        let totalGap = min(Double(visibleItems.count) * gap, 24)
        let availableDegrees = max(0, 360 - totalGap)
        let totalShare = max(visibleItems.reduce(0) { $0 + max(0, $1.share) }, 0.0001)
        let rawSegments = visibleItems.map { item in
            (item: item, degrees: max(0, item.share / totalShare) * availableDegrees)
        }
        let minimumDegrees = visibleItems.count == 1 ? 0 : 4.0
        let fixedDegrees = rawSegments.reduce(0) { partial, raw in
            partial + (raw.degrees > 0 && raw.degrees < minimumDegrees ? minimumDegrees : 0)
        }
        let flexibleRawDegrees = rawSegments.reduce(0) { partial, raw in
            partial + (raw.degrees >= minimumDegrees ? raw.degrees : 0)
        }
        let flexibleDegrees = max(0, availableDegrees - fixedDegrees)

        var cursor = -90.0
        return rawSegments.map { raw in
            let degrees: Double
            if raw.degrees > 0 && raw.degrees < minimumDegrees {
                degrees = minimumDegrees
            } else if flexibleRawDegrees > 0 {
                degrees = raw.degrees / flexibleRawDegrees * flexibleDegrees
            } else {
                degrees = raw.degrees
            }
            let startDegrees = cursor + gap / 2
            let endDegrees = startDegrees + degrees
            cursor += degrees + gap
            return UsageRingSegment(
                id: raw.item.id,
                startDegrees: startDegrees,
                endDegrees: endDegrees
            )
        }
    }
}

private struct UsageRingSegment: Identifiable {
    var id: String
    var startDegrees: Double
    var endDegrees: Double
}

private struct UsageDonutSegmentShape: Shape {
    var start: Angle
    var end: Angle
    var innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        let startRadians = start.radians
        let endRadians = end.radians

        var path = Path()
        path.move(to: point(center: center, radius: outerRadius, radians: startRadians))
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        path.addLine(to: point(center: center, radius: innerRadius, radians: endRadians))
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: end,
            endAngle: start,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: CGFloat, radians: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

private struct UsageStatsTableView: View {
    @Environment(\.usageAnalyticsLanguage) private var language
    private var copy: UsageAnalyticsCopy { UsageAnalyticsCopy(language: language) }
    var rows: [UsageStatsTableRow]
    var theme: SettingsTheme
    private var rateColumnWidth: CGFloat { language == .en ? 68 : 48 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                tableRow(row)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(theme.subtlePanelStrokeColor)
                        .frame(height: 1)
                }
            }
            if rows.isEmpty {
                Text(copy.text(.emptyData))
                    .font(.system(size: 12))
                    .foregroundStyle(usageText55)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            }
        }
    }

    private func tableRow(_ row: UsageStatsTableRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(usagePingFangFont(size: 12, weight: .semibold))
                .foregroundStyle(usageText80)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 24) {
                compactMetric(title: copy.text(.tokens), tokenText(row.totals.totalTokens))
                compactMetric(title: copy.text(.input), tokenText(row.totals.inputTokens))
                compactMetric(title: copy.text(.output), tokenText(row.totals.outputTokens))
                compactMetric(title: copy.text(.cacheRead), tokenText(row.totals.cacheReadTokens))
                compactMetric(title: copy.text(.cacheWrite), tokenText(row.totals.cacheWriteTokens))
                compactMetric(title: copy.text(.cacheRate), percentTextFixed(row.totals.cacheRate), fixedWidth: rateColumnWidth)
                compactMetric(title: copy.text(.successRate), percentTextFixed(row.totals.successRate), fixedWidth: rateColumnWidth)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(
        title: String,
        _ value: String,
        fixedWidth: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(usagePingFangFont(size: 10, weight: .regular))
                .foregroundStyle(usageText40)
                .lineLimit(1)
            Text(value)
                .font(AppFonts.numeric(size: 12, fallbackWeight: .bold))
                .foregroundStyle(usageText80)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(width: fixedWidth, alignment: .leading)
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil, alignment: .leading)
    }
}

private func tokenText(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func percentText(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: value)) ?? "0%"
}

private func percentTextFixed(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: value)) ?? "0.0%"
}

private func shortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d  HH:mm"
    return formatter.string(from: date)
}

private func usageTrendLabelFont(isActive: Bool) -> Font {
    usagePingFangFont(size: 10, weight: isActive ? .semibold : .regular)
}

private func usagePingFangFont(size: CGFloat, weight: Font.Weight) -> Font {
    switch weight {
    case .semibold, .bold, .heavy, .black:
        return .custom("PingFangSC-Semibold", size: size)
    default:
        return .custom("PingFangSC-Regular", size: size)
    }
}

private func pieColor(_ index: Int, theme: SettingsTheme) -> Color {
    let colors = [0.82, 0.56, 0.40, 0.30, 0.18, 0.08].map {
        Color.white.opacity($0)
    }
    return colors[index % colors.count]
}

private struct UsageAnalyticsLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .zhHans
}

private extension EnvironmentValues {
    var usageAnalyticsLanguage: AppLanguage {
        get { self[UsageAnalyticsLanguageKey.self] }
        set { self[UsageAnalyticsLanguageKey.self] = newValue }
    }
}

struct UsageAnalyticsCopy {
    enum Key: CaseIterable {
        case refresh
        case overview
        case trend
        case statistics
        case provider
        case model
        case all
        case last24Hours
        case last7Days
        case last30Days
        case requests
        case tokens
        case input
        case output
        case cacheRead
        case cacheWrite
        case cacheRate
        case successRate
        case emptyTrend
        case emptyData
    }

    var language: AppLanguage

    func text(_ key: Key) -> String {
        let pair: (String, String)
        switch key {
        case .refresh: pair = ("刷新使用统计", "Refresh usage statistics")
        case .overview: pair = ("总览", "Overview")
        case .trend: pair = ("使用趋势", "Usage trend")
        case .statistics: pair = ("统计", "Statistics")
        case .provider: pair = ("供应商", "Provider")
        case .model: pair = ("模型", "Model")
        case .all: pair = ("全部", "All")
        case .last24Hours: pair = ("近24小时", "Last 24h")
        case .last7Days: pair = ("近7天", "Last 7d")
        case .last30Days: pair = ("近30天", "Last 30d")
        case .requests: pair = ("总请求", "Requests")
        case .tokens: pair = ("总Token", "Tokens")
        case .input: pair = ("输入", "Input")
        case .output: pair = ("输出", "Output")
        case .cacheRead: pair = ("缓存命中", "Cache read")
        case .cacheWrite: pair = ("缓存写入", "Cache write")
        case .cacheRate: pair = ("缓存率", "Cache rate")
        case .successRate: pair = ("成功率", "Success rate")
        case .emptyTrend: pair = ("暂无趋势数据", "No trend data yet")
        case .emptyData: pair = ("暂无匹配的使用数据", "No matching usage data")
        }
        return language == .zhHans ? pair.0 : pair.1
    }

    func timeRangeTitle(_ range: UsageAnalyticsRange) -> String {
        switch range {
        case .all: return text(.all)
        case .last24Hours: return text(.last24Hours)
        case .last7Days: return text(.last7Days)
        case .last30Days: return text(.last30Days)
        }
    }

    func diagnostic(_ value: String) -> String {
        guard language == .en else { return value }
        switch value {
        case "统计来源：官方应用本地用量日志 / Cursor dashboard（可用时）":
            return "Sources: local app usage logs / Cursor dashboard (when available)"
        case "统计来源：官方应用本地用量 / Cursor dashboard（可用时）+ cc-switch 请求日志":
            return "Sources: local app usage / Cursor dashboard (when available) + cc-switch request logs"
        default: return value
        }
    }

    func trendTickLabel(_ date: Date, endAt: Date) -> String {
        let duration = endAt.timeIntervalSince(date)
        if duration > 40 * 24 * 60 * 60 {
            let components = Calendar.current.dateComponents([.year, .month], from: date)
            let year = components.year ?? 0
            let month = components.month ?? 1
            let quarter = ((month - 1) / 3) + 1
            return "\(year) Q\(quarter)"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        if duration <= 90 * 60 {
            formatter.dateFormat = "H"
        } else if duration <= 36 * 60 * 60 {
            formatter.dateFormat = "d"
        } else if duration <= 8 * 24 * 60 * 60 {
            formatter.dateFormat = "M/d"
        } else {
            formatter.dateFormat = language == .zhHans ? "M月" : "MMM"
        }
        return formatter.string(from: date)
    }

}
