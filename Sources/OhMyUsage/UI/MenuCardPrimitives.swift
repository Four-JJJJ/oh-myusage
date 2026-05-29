import AppKit
import SwiftUI

struct ModelCardDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(SettingsVisualTokens.Fill.control)
            .frame(height: SettingsVisualTokens.Menu.dividerHeight)
    }
}

struct ModelIconBadge: View {
    let iconName: String
    let fallback: String

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(SettingsVisualTokens.Fill.control)
            .frame(width: 24, height: 24)
            .overlay {
                BundledIconView(
                    name: iconName,
                    fallback: fallback,
                    size: 12,
                    iconOpacity: 0.8
                )
            }
    }
}

struct ModelTitleWithPlanType: View {
    let title: String
    let planType: String?
    let textColor: Color

    private var planTypeGradient: LinearGradient {
        LinearGradient(
            colors: [
                SettingsVisualTokens.Text.primary,
                Color(red: 1.0, green: 0.819, blue: 0.225, opacity: 0.80)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .lineSpacing(0)
                .lineLimit(1)

            if let planType, !planType.isEmpty {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(SettingsVisualTokens.Text.tertiary)
                    .frame(width: 1, height: 8)

                Text(planType)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(planTypeGradient)
                    .lineSpacing(0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }
}

struct HoverActionButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        // 卡片右上角小按钮（hover 态边框和底色）。
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(disabled ? SettingsVisualTokens.Text.disabled : SettingsVisualTokens.Text.primary)
                .padding(.horizontal, 4)
                .frame(width: 28, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.compact, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.compact, style: .continuous)
                        .stroke(borderColor, lineWidth: SettingsVisualTokens.Stroke.thin)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var backgroundColor: Color {
        if disabled {
            return Color.white.opacity(0.02)
        }
        return isHovered ? Color.white.opacity(0.12) : Color.clear
    }

    private var borderColor: Color {
        if disabled {
            return SettingsVisualTokens.Fill.selectedRow
        }
        return isHovered ? Color.white.opacity(0.92) : SettingsVisualTokens.Text.primary
    }
}

struct BundledIconView: View {
    let name: String
    let fallback: String
    let size: CGFloat
    var tint: Color? = nil
    var iconOpacity: Double = 1

    var body: some View {
        // 图标渲染入口：优先资源图，找不到则回退 SF Symbols。
        Group {
            if let image = bundledImage(named: name) {
                if let tint {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(tint)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Image(systemName: fallback)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint ?? SettingsVisualTokens.Text.primary)
            }
        }
        .frame(width: size, height: size)
        .opacity(iconOpacity)
    }

    private func bundledImage(named name: String) -> NSImage? {
        if let pngURL = Bundle.module.url(forResource: name, withExtension: "png"),
           let pngImage = NSImage(contentsOf: pngURL) {
            return pngImage
        }
        if let svgURL = Bundle.module.url(forResource: name, withExtension: "svg"),
           let svgImage = NSImage(contentsOf: svgURL) {
            return svgImage
        }
        return nil
    }
}

struct CardStatus {
    let text: String
    let color: Color
}

struct PercentageMetricDisplay: Identifiable {
    let id: String
    let title: String
    let valueText: String
    let resetText: String
    let detailText: String?
    let percent: Double?
    let barColor: Color
    let isBlockedByDepletedQuota: Bool

    var valueColumnWidth: CGFloat {
        valueText.contains("%") || valueText == "-"
            ? MetricValueLayoutFormatter.percentageMetricValueColumnWidth
            : MetricValueLayoutFormatter.metricValueColumnWidth
    }
}
