import SwiftUI

struct PercentageModelCard: View {
    private let primaryMetricLeadingWidth: CGFloat = 172
    private let primaryMetricTrailingWidth: CGFloat = 104
    let title: String
    let planType: String?
    let iconName: String
    let iconFallback: String
    let subtitle: String?
    let status: CardStatus
    let metrics: [PercentageMetricDisplay]
    let errorText: String?
    let backgroundColor: Color
    let isDisconnected: Bool
    var highlightColor: Color? = nil
    var leadingAccentColor: Color? = nil
    var actionLabel: String? = nil
    var actionDisabled: Bool = false
    var action: (() -> Void)? = nil
    var infoText: String? = nil
    var infoTextColor: Color = Color.white.opacity(0.5)

    var body: some View {
        // 百分比型模型卡（Codex/Claude/Gemini 等）的整体样式。
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                ModelIconBadge(
                    iconName: iconName,
                    fallback: iconFallback
                )

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        ModelTitleWithPlanType(
                            title: title,
                            planType: planType,
                            textColor: SettingsVisualTokens.Text.primary
                        )
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(SettingsVisualTokens.Text.secondary)
                                .lineSpacing(0)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    HStack(spacing: 12) {
                        if let actionLabel, let action {
                            HoverActionButton(title: actionLabel, disabled: actionDisabled, action: action)
                        }

                        Text(status.text)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(status.color)
                            .lineSpacing(0)
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(height: 24)

            ModelCardDivider()

            if metrics.count > 2 {
                VStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 16) {
                            ForEach(metricsForRow(row), id: \.id) { metric in
                                PercentageMetricView(metric: metric)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            } else if metrics.count == 2 {
                HStack(spacing: 24) {
                    PercentageMetricView(metric: metrics[0])
                        .frame(width: primaryMetricLeadingWidth, alignment: .leading)

                    PercentageMetricView(metric: metrics[1])
                        .frame(width: primaryMetricTrailingWidth, alignment: .leading)
                }
            } else {
                HStack(spacing: 16) {
                    ForEach(metrics) { metric in
                        PercentageMetricView(metric: metric)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let errorText, !errorText.isEmpty {
                ModelCardDivider()

                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsVisualTokens.Status.error)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let infoText, !infoText.isEmpty {
                Text(infoText)
                    .font(.system(size: 10))
                    .foregroundStyle(infoTextColor)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SettingsVisualTokens.Menu.cardPadding)
        .background(
            SettingsSmoothedRoundedRectangle(
                cornerRadius: SettingsVisualTokens.Radius.card,
                smoothing: SettingsVisualTokens.Smoothing.continuous
            )
                // 卡片背景色由外部传入，统一在这里渲染。
                .fill(backgroundColor)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(
                cornerRadius: SettingsVisualTokens.Radius.card,
                smoothing: SettingsVisualTokens.Smoothing.continuous
            )
                // 卡片描边：断连或高亮时显示。
                .stroke(borderColor, lineWidth: hasBorder ? 1 : 0)
        )
        .overlay {
            if let leadingAccentColor {
                // 左侧状态条：距离卡片左边框 4px，上下固定间距 12px，高度自适应。
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(leadingAccentColor)
                        .frame(
                            width: 2,
                            height: max(0, proxy.size.height - 24)
                        )
                        .padding(.leading, 4)
                        .padding(.vertical, 12)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var borderColor: Color {
        if let highlightColor {
            return highlightColor
        }
        return SettingsVisualTokens.Status.error
    }

    private var hasBorder: Bool {
        highlightColor != nil || isDisconnected
    }

    private func metricsForRow(_ row: Int) -> [PercentageMetricDisplay] {
        let start = row * 2
        guard start < metrics.count else { return [] }
        let end = min(start + 2, metrics.count)
        return Array(metrics[start..<end])
    }
}

private struct PercentageMetricView: View {
    let metric: PercentageMetricDisplay

    var body: some View {
        // 百分比卡里的单个指标块（标题、倒计时、进度条）。
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(metric.title)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsVisualTokens.Text.secondary)
                    .lineSpacing(0)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    // 重置计时左侧时钟图标（Figma: icon/system/clock，10x10）。
                    BundledIconView(
                        name: "menu_reset_clock_icon",
                        fallback: "clock",
                        size: 10
                    )

                    // 重置计时文本（Figma: 10px、white 40%、单行）。
                    Text(metric.resetText)
                        .font(.system(size: 10, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                        .lineSpacing(0)
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                }
                .frame(alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .frame(height: 10)
            }
            .frame(height: 10)

            HStack(spacing: 2) {
                Text(metric.valueText)
                    .font(AppFonts.numeric(size: 16, fallbackWeight: .bold))
                    .foregroundStyle(SettingsVisualTokens.Text.primary)
                    .lineSpacing(0)
                    .frame(width: metric.valueColumnWidth, alignment: .leading)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                            .fill(SettingsVisualTokens.Text.muted)
                        if let percent = metric.percent, percent > 0 {
                            RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                                .fill(metric.barColor)
                                .frame(width: max(1, geo.size.width * percent / 100))
                                .clipShape(RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous))
                        }
                        if metric.isBlockedByDepletedQuota {
                            QuotaBlockedStripePattern()
                                .fill(SettingsVisualTokens.Status.blockedStripe)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous))
                }
                .frame(height: SettingsVisualTokens.Menu.progressTrackHeight)
            }

            if let detailText = metric.detailText, !detailText.isEmpty {
                Text(detailText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                    .lineSpacing(0)
                    .lineLimit(1)
            }
        }
    }
}

struct AmountModelCard: View {
    let title: String
    let planType: String?
    let iconName: String
    let iconFallback: String
    let status: CardStatus
    let amountText: String
    let secondaryText: String?
    let errorText: String?
    let backgroundColor: Color
    let isDisconnected: Bool
    var highlightColor: Color? = nil
    let balanceLabel: String

    var body: some View {
        // 余额型模型卡（第三方 relay 等）的整体样式。
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                ModelIconBadge(
                    iconName: iconName,
                    fallback: iconFallback
                )

                HStack(alignment: .center, spacing: 12) {
                    ModelTitleWithPlanType(
                        title: title,
                        planType: planType,
                        textColor: SettingsVisualTokens.Text.primary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    Text(status.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(status.color)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: false, vertical: false)
            }
            .frame(height: 24)

            ModelCardDivider()

            VStack(alignment: .leading, spacing: 4) {
                Text(balanceLabel)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(SettingsVisualTokens.Text.secondary)
                    .lineSpacing(0)
                    .lineLimit(1)
                HStack(spacing: 2) {
                    BundledIconView(
                        name: "menu_balance_icon",
                        fallback: "dollarsign.circle.fill",
                        size: 16,
                        iconOpacity: 0.9
                    )
                    Text(amountText)
                        .font(AppFonts.numeric(size: 16, fallbackWeight: .semibold))
                }
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .lineSpacing(0)
                .frame(height: 16)

                if let secondaryText, !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(.system(size: 10))
                        .foregroundStyle(SettingsVisualTokens.Text.secondary)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
            }

            if let errorText, !errorText.isEmpty {
                ModelCardDivider()

                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsVisualTokens.Status.error)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SettingsVisualTokens.Menu.cardPadding)
        .background(
            SettingsSmoothedRoundedRectangle(
                cornerRadius: SettingsVisualTokens.Radius.card,
                smoothing: SettingsVisualTokens.Smoothing.continuous
            )
                .fill(backgroundColor)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(
                cornerRadius: SettingsVisualTokens.Radius.card,
                smoothing: SettingsVisualTokens.Smoothing.continuous
            )
                .stroke(borderColor, lineWidth: hasBorder ? 1 : 0)
        )
    }

    private var borderColor: Color {
        if let highlightColor {
            return highlightColor
        }
        return SettingsVisualTokens.Status.error
    }

    private var hasBorder: Bool {
        highlightColor != nil || isDisconnected
    }
}
