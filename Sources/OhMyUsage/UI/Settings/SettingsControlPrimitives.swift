import SwiftUI

extension View {
    /// 可选无障碍标签：label 非 nil 时才应用 `.accessibilityLabel`，
    /// 纯 a11y 修饰符，不影响视觉布局/渲染。
    @ViewBuilder
    func optionalAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            accessibilityLabel(label)
        } else {
            self
        }
    }

    /// 可选悬停提示：text 非 nil 时才应用 `.help`，避免出现空气泡。
    @ViewBuilder
    func optionalHelp(_ text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
    }
}

struct SettingsSmoothedRoundedRectangle: InsettableShape {
    var cornerRadius: CGFloat
    var smoothing: CGFloat
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat, smoothing: CGFloat = 0.6) {
        self.cornerRadius = cornerRadius
        self.smoothing = smoothing
    }

    private init(cornerRadius: CGFloat, smoothing: CGFloat, insetAmount: CGFloat) {
        self.cornerRadius = cornerRadius
        self.smoothing = smoothing
        self.insetAmount = insetAmount
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, min(min(rect.width, rect.height) / 2, cornerRadius))
        guard radius > 0 else { return Path(rect) }

        let interpolation = max(0, min(1, smoothing))
        let circularK: CGFloat = 0.552_284_75
        let squircleK: CGFloat = 0.34
        let k = circularK - (circularK - squircleK) * interpolation
        let cp = radius * k

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX + radius, y: minY))
        path.addLine(to: CGPoint(x: maxX - radius, y: minY))
        path.addCurve(
            to: CGPoint(x: maxX, y: minY + radius),
            control1: CGPoint(x: maxX - cp, y: minY),
            control2: CGPoint(x: maxX, y: minY + cp)
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        path.addCurve(
            to: CGPoint(x: maxX - radius, y: maxY),
            control1: CGPoint(x: maxX, y: maxY - cp),
            control2: CGPoint(x: maxX - cp, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - radius),
            control1: CGPoint(x: minX + cp, y: maxY),
            control2: CGPoint(x: minX, y: maxY - cp)
        )
        path.addLine(to: CGPoint(x: minX, y: minY + radius))
        path.addCurve(
            to: CGPoint(x: minX + radius, y: minY),
            control1: CGPoint(x: minX, y: minY + cp),
            control2: CGPoint(x: minX + cp, y: minY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        SettingsSmoothedRoundedRectangle(
            cornerRadius: cornerRadius,
            smoothing: smoothing,
            insetAmount: insetAmount + amount
        )
    }
}

struct SettingsPillSegmentOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
}

struct SettingsPillSegmentedControl<ID: Hashable>: View {
    let options: [SettingsPillSegmentOption<ID>]
    let selection: ID
    var backgroundColor: Color
    var selectedFillColor: Color
    var selectedTextColor: Color
    var textColor: Color
    var height: CGFloat = 24
    var segmentWidths: [ID: CGFloat]? = nil
    var onSelect: (ID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option.id == selection

                Button {
                    onSelect(option.id)
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? selectedTextColor : textColor)
                        .frame(width: segmentWidths?[option.id])
                        .frame(maxWidth: segmentWidths == nil ? .infinity : nil)
                        .frame(height: height)
                        .background {
                            if isSelected {
                                SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control)
                                    .fill(selectedFillColor)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(0)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control)
                .fill(backgroundColor)
        )
        .frame(height: height)
    }
}

struct SettingsToggleSwitch: View {
    @Binding var isOn: Bool
    var offTrackColor: Color
    var onTrackColor: Color
    var knobColor: Color
    /// 无障碍标签（双语文案由调用方传入）；nil 时不覆盖默认行为。
    var accessibilityLabel: String? = nil

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? onTrackColor : offTrackColor)

                SettingsSmoothedRoundedRectangle(
                    cornerRadius: SettingsVisualTokens.Radius.control,
                    smoothing: SettingsVisualTokens.Smoothing.continuous
                )
                    .fill(knobColor)
                    .frame(width: 28, height: 16)
                    .padding(4)
            }
            .frame(width: 56, height: 24)
        }
        .buttonStyle(.plain)
        .optionalAccessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

struct SettingsCheckbox: View {
    @Binding var isOn: Bool
    var size: CGFloat = 12
    var cornerRadius: CGFloat = 3
    /// 无障碍标签（双语文案由调用方传入）；nil 时不覆盖默认行为。
    var accessibilityLabel: String? = nil

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .fill(isOn ? Color.white.opacity(0.92) : SettingsVisualTokens.Fill.controlStrong)
                .frame(width: size, height: size)
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: max(6, size * 0.58), weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.86))
                    }
                }
        }
        .buttonStyle(.plain)
        .optionalAccessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
