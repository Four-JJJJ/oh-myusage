import SwiftUI

struct LocalUsageTrendHourlyBarsView: View {
    struct Appearance {
        var barWidth: CGFloat
        var maxBarHeight: CGFloat
        var minBarHeight: CGFloat
        var chartHeight: CGFloat
        var showsEmbeddedLabels: Bool
        var usesCapsule: Bool
        var filledBarColor: Color
        var emptyBarColor: Color
        var activeBarColor: Color
        var axisLabelColor: Color
        var tooltipBackground: Color
        var tooltipStroke: Color
        var tooltipTitleColor: Color
        var tooltipLabelColor: Color
        var tooltipValueColor: Color
    }

    var points: [LocalUsageTrendPoint]
    var language: AppLanguage
    var localizedText: (String, String) -> String
    var appearance: Appearance

    @State private var hoveredPointID: String?
    @State private var chartWidth: CGFloat = 0

    private let tooltipSize = CGSize(width: 148, height: 118)

    var body: some View {
        GeometryReader { proxy in
            let metric = displayMetric(points: points)
            let values = points.map { trendValue($0, metric: metric) }
            let maxValue = max(values.max() ?? 0, 1)
            let count = max(points.count, 1)
            let totalBarsWidth = CGFloat(count) * appearance.barWidth
            let spacing = count > 1 ? max(0, (proxy.size.width - totalBarsWidth) / CGFloat(count - 1)) : 0

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(points) { point in
                    let pointValue = trendValue(point, metric: metric)
                    let ratio = maxValue > 0 ? CGFloat(pointValue / maxValue) : 0
                    let barHeight = pointValue > 0
                        ? max(appearance.minBarHeight, appearance.maxBarHeight * ratio)
                        : appearance.minBarHeight
                    let isHovered = point.id == hoveredPointID

                    barColumn(
                        point: point,
                        barHeight: barHeight,
                        hasValue: pointValue > 0,
                        isHovered: isHovered
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
            .animation(.easeOut(duration: 0.12), value: hoveredPointID)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredPointID = pointID(at: location, containerWidth: proxy.size.width)
                case .ended:
                    hoveredPointID = nil
                }
            }
            .onAppear {
                chartWidth = proxy.size.width
            }
            .onChange(of: proxy.size.width) { _, width in
                chartWidth = width
            }
        }
        .frame(height: appearance.chartHeight)
        .overlay(alignment: .topLeading) {
            if let hoveredIndex = points.firstIndex(where: { $0.id == hoveredPointID }) {
                tooltipView(for: points[hoveredIndex])
                    .offset(tooltipOffset(index: hoveredIndex, containerWidth: chartWidth))
                    .allowsHitTesting(false)
            }
        }
        .zIndex(hoveredPointID == nil ? 0 : 10)
    }

    @ViewBuilder
    private func barColumn(
        point: LocalUsageTrendPoint,
        barHeight: CGFloat,
        hasValue: Bool,
        isHovered: Bool
    ) -> some View {
        let fill = barFill(isHovered: isHovered, hasValue: hasValue)

        VStack(alignment: .center, spacing: appearance.showsEmbeddedLabels ? 4 : 0) {
            ZStack(alignment: .bottom) {
                barShape(fill: fill)
                    .frame(width: appearance.barWidth, height: barHeight)
            }
            .frame(
                width: appearance.barWidth,
                height: appearance.maxBarHeight,
                alignment: .bottom
            )

            if appearance.showsEmbeddedLabels {
                Text(hourLabel(point.startAt))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(isHovered ? appearance.tooltipTitleColor : appearance.axisLabelColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 24, height: 10, alignment: .center)
            }
        }
        .frame(
            width: appearance.barWidth,
            height: appearance.chartHeight,
            alignment: .bottom
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LocalUsageTrendPresenter.hourRangeTitle(startAt: point.startAt))
        .accessibilityValue(accessibilityValue(for: point))
    }

    @ViewBuilder
    private func barShape(fill: Color) -> some View {
        if appearance.usesCapsule {
            Capsule()
                .fill(fill)
        } else {
            SettingsSmoothedRoundedRectangle(cornerRadius: 4, smoothing: 0.6)
                .fill(fill)
        }
    }

    private func barFill(isHovered: Bool, hasValue: Bool) -> Color {
        if isHovered {
            return appearance.activeBarColor
        }
        return hasValue ? appearance.filledBarColor : appearance.emptyBarColor
    }

    private func tooltipView(for point: LocalUsageTrendPoint) -> some View {
        let tooltip = LocalUsageTrendPresenter.pointTooltip(
            for: point,
            language: language,
            localizedText: localizedText
        )

        return VStack(alignment: .leading, spacing: 6) {
            Text(tooltip.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(appearance.tooltipTitleColor)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(tooltip.rows) { row in
                    HStack(spacing: 8) {
                        Text(row.label)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(appearance.tooltipLabelColor)
                        Spacer(minLength: 8)
                        Text(row.value)
                            .font(AppFonts.numeric(size: 11, fallbackWeight: .semibold))
                            .foregroundStyle(appearance.tooltipValueColor)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: tooltipSize.width, alignment: .leading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8, smoothing: 0.6)
                .fill(appearance.tooltipBackground)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8, smoothing: 0.6)
                .stroke(appearance.tooltipStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 10, y: 4)
    }

    private func tooltipOffset(index: Int, containerWidth: CGFloat) -> CGSize {
        let count = max(points.count, 1)
        let width = max(containerWidth, 1)
        let totalBarsWidth = CGFloat(count) * appearance.barWidth
        let spacing = count > 1 ? max(0, (width - totalBarsWidth) / CGFloat(count - 1)) : 0
        let barCenterX = CGFloat(index) * (appearance.barWidth + spacing) + appearance.barWidth / 2
        let x = min(max(4, barCenterX - tooltipSize.width / 2), max(4, width - tooltipSize.width - 4))
        let y = -tooltipSize.height + 12
        return CGSize(width: x, height: y)
    }

    private func pointID(at location: CGPoint, containerWidth: CGFloat) -> String? {
        guard !points.isEmpty, containerWidth > 0 else { return nil }
        let columnWidth = containerWidth / CGFloat(points.count)
        let index = min(max(0, Int(location.x / max(columnWidth, 1))), points.count - 1)
        return points[index].id
    }

    private func displayMetric(points: [LocalUsageTrendPoint]) -> LocalTrendDisplayMetric {
        if points.contains(where: { $0.totalTokens > 0 }) {
            return .tokens
        }
        return .responses
    }

    private func trendValue(_ point: LocalUsageTrendPoint, metric: LocalTrendDisplayMetric) -> Double {
        switch metric {
        case .tokens:
            return Double(max(0, point.totalTokens))
        case .responses:
            return Double(max(0, point.responses))
        }
    }

    private func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH"
        return formatter.string(from: date)
    }

    private func accessibilityValue(for point: LocalUsageTrendPoint) -> String {
        LocalUsageTrendPresenter.pointTooltip(
            for: point,
            language: language,
            localizedText: localizedText
        )
        .rows
        .map { "\($0.label) \($0.value)" }
        .joined(separator: ", ")
    }
}

extension LocalUsageTrendHourlyBarsView.Appearance {
    static func subscription() -> Self {
        Self(
            barWidth: 12,
            maxBarHeight: 50,
            minBarHeight: 4,
            chartHeight: 64,
            showsEmbeddedLabels: true,
            usesCapsule: false,
            filledBarColor: Color.white.opacity(0.55),
            emptyBarColor: Color.white.opacity(0.55),
            activeBarColor: Color.white.opacity(0.92),
            axisLabelColor: Color.white.opacity(0.40),
            tooltipBackground: Color(hex: 0x2A2A2A).opacity(0.96),
            tooltipStroke: Color.white.opacity(0.14),
            tooltipTitleColor: Color.white.opacity(0.88),
            tooltipLabelColor: Color.white.opacity(0.45),
            tooltipValueColor: Color.white.opacity(0.88)
        )
    }

    static func settings(
        filledBarColor: Color,
        emptyBarColor: Color,
        axisLabelColor: Color,
        usesLightAppearance: Bool
    ) -> Self {
        Self(
            barWidth: 12,
            maxBarHeight: 50,
            minBarHeight: 6,
            chartHeight: 50,
            showsEmbeddedLabels: false,
            usesCapsule: true,
            filledBarColor: filledBarColor,
            emptyBarColor: emptyBarColor,
            activeBarColor: usesLightAppearance ? Color(hex: 0x168DFF) : Color.white.opacity(0.92),
            axisLabelColor: axisLabelColor,
            tooltipBackground: usesLightAppearance
                ? Color.white.opacity(0.96)
                : Color(hex: 0x2A2A2A).opacity(0.96),
            tooltipStroke: usesLightAppearance
                ? Color.black.opacity(0.10)
                : Color.white.opacity(0.14),
            tooltipTitleColor: usesLightAppearance
                ? Color.black.opacity(0.82)
                : Color.white.opacity(0.88),
            tooltipLabelColor: usesLightAppearance
                ? Color.black.opacity(0.48)
                : Color.white.opacity(0.45),
            tooltipValueColor: usesLightAppearance
                ? Color.black.opacity(0.82)
                : Color.white.opacity(0.88)
        )
    }
}
