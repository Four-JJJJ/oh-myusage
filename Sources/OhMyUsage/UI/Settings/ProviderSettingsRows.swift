import SwiftUI

struct SettingsProviderHeaderView: View {
    var title: String
    var titleColor: Color
    var dividerColor: Color
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(titleColor)

                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .allowsHitTesting(false)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                isEnabled.toggle()
            }

            Rectangle()
                .fill(dividerColor)
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
        }
    }
}

struct SettingsToggleRowView: View {
    var title: String
    var labelFont: Font
    var bodyColor: Color
    var labelWidth: CGFloat = 60
    var spacing: CGFloat = 12
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: spacing) {
            Text(title)
                .font(labelFont)
                .foregroundStyle(bodyColor)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

            SettingsToggleSwitch(
                isOn: $isOn,
                offTrackColor: Color.white.opacity(0.15),
                onTrackColor: Color(hex: 0x69BD64),
                knobColor: Color.white.opacity(0.88),
                accessibilityLabel: title
            )

            Spacer(minLength: 0)
        }
        .frame(height: 24)
    }
}

struct SettingsThresholdControlRowView: View {
    var title: String
    var labelFont: Font
    var bodyColor: Color
    var sliderTintColor: Color
    var labelWidth: CGFloat
    var spacing: CGFloat
    var sliderValue: Binding<Double>
    var stepperValue: Binding<Double>
    var displayText: String
    var onEditingChanged: (Bool) -> Void

    var body: some View {
        HStack(spacing: spacing) {
            Text(title)
                .font(labelFont)
                .foregroundStyle(bodyColor)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

            SettingsThresholdControlRowSlider(
                value: sliderValue,
                onEditingChanged: onEditingChanged
            )
            .frame(width: 320, height: 20)
            .tint(sliderTintColor)

            Spacer(minLength: 0)

            Text(displayText)
                .font(AppFonts.numeric(size: 12, fallbackWeight: .semibold))
                .foregroundStyle(bodyColor)
                .padding(.horizontal, 16)
                .frame(width: 86, height: 44)
                .background(
                    SettingsSmoothedRoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.12))
                )
        }
        .frame(minHeight: 44)
    }
}

struct ClaudeStatusBarDisplayRowView: View {
    struct Option: Identifiable, Equatable {
        var id: String
        var title: String
    }

    var labelTitle: String
    var autoTitle: String
    var currentMenubarTitle: String?
    var options: [Option]
    var labelFont: Font
    var bodyColor: Color
    var hintColor: Color
    var labelWidth: CGFloat = 60
    var selection: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(labelTitle)
                    .font(labelFont)
                    .foregroundStyle(bodyColor)
                    .lineLimit(1)
                    .frame(width: labelWidth, alignment: .leading)

                Picker("", selection: selection) {
                    Text(autoTitle).tag("auto")
                    ForEach(options) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer(minLength: 0)
            }

            if let currentMenubarTitle, !currentMenubarTitle.isEmpty {
                Text(currentMenubarTitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(hintColor)
            }
        }
    }
}
