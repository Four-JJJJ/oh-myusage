import AppKit
import SwiftUI

extension SettingsView {
    struct SettingsCompactRecordMetric: Identifiable {
        var id: String
        var title: String
        var valueText: String
        var resetText: String?
    }

    struct SettingsCompactRecordAction: Identifiable {
        var id: String
        var title: String
        var destructive: Bool = false
        var action: () -> Void
    }

    func settingsCompactSection<Actions: View, Content: View>(
        title: String,
        spacing: CGFloat = 12,
        headerWidth: CGFloat = 566,
        headerHeight: CGFloat = 22,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)

                Spacer(minLength: 0)

                actions()
            }
            .frame(width: headerWidth, height: headerHeight, alignment: .center)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func settingsConfigurationSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, height: 12, alignment: .leading)

            settingsOutlineCard(
                padding: 0,
                cornerRadius: SettingsVisualTokens.Radius.control,
                strokeOpacity: 0.15,
                content: content
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func settingsConfigurationRows<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            content()
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func settingsConfigRow<Content: View>(
        title: String,
        nested: Bool = false,
        rowHeight: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let labelWidth = nested ? settingsNestedConfigLabelWidth : thirdPartyConfigLabelWidth
        let leadingOffset = nested ? thirdPartyConfigLabelWidth - labelWidth : 0

        return HStack(alignment: .center, spacing: thirdPartyConfigLabelSpacing) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .trailing)

            content()
        }
        .padding(.leading, leadingOffset)
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
    }

    func settingsConfigToggleRow(
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        settingsConfigRow(title: title) {
            SettingsToggleSwitch(
                isOn: isOn,
                offTrackColor: SettingsVisualTokens.Fill.control,
                onTrackColor: SettingsVisualTokens.Text.tertiary,
                knobColor: SettingsVisualTokens.Fill.knob
            )
        }
    }

    func settingsConfigSegmentedControl<ID: Hashable>(
        options: [SettingsPillSegmentOption<ID>],
        selection: ID,
        width: CGFloat,
        segmentWidths: [ID: CGFloat]? = nil,
        onSelect: @escaping (ID) -> Void
    ) -> some View {
        SettingsPillSegmentedControl(
            options: options,
            selection: selection,
            backgroundColor: SettingsVisualTokens.Fill.control,
            selectedFillColor: SettingsVisualTokens.Fill.selectedControl,
            selectedTextColor: SettingsVisualTokens.Fill.selectedText,
            textColor: SettingsVisualTokens.Text.primary,
            segmentWidths: segmentWidths,
            onSelect: onSelect
        )
        .frame(width: width, height: 24)
    }

    func settingsConfigSecureField(
        _ placeholder: String,
        text: Binding<String>,
        width: CGFloat? = nil
    ) -> some View {
        SecureField("", text: text, prompt: Text(placeholder)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(SettingsVisualTokens.Text.tertiary))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(SettingsVisualTokens.Text.primary)
            .padding(.horizontal, 8)
            .frame(width: width ?? thirdPartyConfigControlWidth, height: 24)
            .background(
                SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control)
                    .fill(SettingsVisualTokens.Fill.control)
            )
    }

    func settingsConfigTextField(
        _ placeholder: String,
        text: Binding<String>
    ) -> some View {
        TextField("", text: text, prompt: Text(placeholder)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(SettingsVisualTokens.Text.tertiary))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(SettingsVisualTokens.Text.primary)
            .padding(.horizontal, 8)
            .frame(width: thirdPartyConfigControlWidth, height: 24)
            .background(
                SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control)
                    .fill(SettingsVisualTokens.Fill.control)
            )
    }

    func settingsOutlineCard<Content: View>(
        padding: CGFloat = 24,
        cornerRadius: CGFloat = 12,
        strokeOpacity: Double = 0.12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(padding)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.clear)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(strokeOpacity), lineWidth: SettingsVisualTokens.Stroke.hairline)
        )
    }

    func settingsSmallOutlineButton(
        _ title: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minWidth: width)
                .frame(height: 22)
                .background(Color.clear)
                .overlay(
                    SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.compact)
                        .stroke(SettingsVisualTokens.Text.primary, lineWidth: SettingsVisualTokens.Stroke.hairline)
                )
        }
        .buttonStyle(.plain)
    }

    func settingsCompactRecordRow(
        title: String,
        currentText: String? = nil,
        statusText: String,
        statusColor: Color,
        errorText: String? = nil,
        metrics: [SettingsCompactRecordMetric],
        actions: [SettingsCompactRecordAction]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsVisualTokens.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let currentText, !currentText.isEmpty {
                    Text(currentText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(SettingsVisualTokens.Status.positive)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(statusText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .frame(height: 12)

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(SettingsVisualTokens.Status.destructive)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 12) {
                settingsCompactRecordMetricsLine(metrics)

                Spacer(minLength: 0)

                ForEach(actions) { action in
                    settingsCompactRecordTextActionButton(
                        action.title,
                        destructive: action.destructive,
                        action: action.action
                    )
                }
            }
            .frame(height: 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func settingsCompactRecordMetricsLine(
        _ metrics: [SettingsCompactRecordMetric],
        firstColumnWidth: CGFloat? = nil,
        columnSpacing: CGFloat = 24
    ) -> some View {
        HStack(spacing: columnSpacing) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                settingsCompactRecordMetricView(metric)
                    .frame(width: index == 0 ? firstColumnWidth : nil, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    func settingsCompactRecordMetricView(_ metric: SettingsCompactRecordMetric) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(metric.title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(SettingsVisualTokens.Text.secondary)
                    .lineLimit(1)

                Text(metric.valueText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SettingsVisualTokens.Text.primary)
                    .lineLimit(1)
            }

            if let resetText = metric.resetText, !resetText.isEmpty {
                HStack(spacing: 2) {
                    if let image = bundledImage(named: "menu_reset_clock_icon") {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                            .frame(width: 10, height: 10)
                    }

                    Text(resetText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    func settingsCompactRecordTextActionButton(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(destructive ? SettingsVisualTokens.Status.destructive : SettingsVisualTokens.Text.secondary)
                .lineLimit(1)
                .frame(height: 10, alignment: .center)
        }
        .buttonStyle(.plain)
    }

    func settingsCapsuleButton(
        _ title: String,
        destructive: Bool = false,
        disabled: Bool = false,
        dismissInputFocus: Bool = false,
        textOpacity: Double = 0.80,
        borderOpacity: Double = 0.55,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if dismissInputFocus {
                dismissEditingFocus()
            }
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    destructive
                        ? SettingsVisualTokens.Status.destructiveAccent.opacity(disabled ? 0.38 : textOpacity)
                        : Color.white.opacity(disabled ? 0.38 : textOpacity)
                )
                .padding(.horizontal, 16)
                .frame(height: 24)
                .background(Color.clear)
                .overlay(
                    SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.card)
                        .stroke(
                            destructive
                                ? SettingsVisualTokens.Status.destructiveAccent.opacity(disabled ? 0.24 : borderOpacity)
                                : Color.white.opacity(disabled ? 0.24 : borderOpacity),
                            lineWidth: SettingsVisualTokens.Stroke.hairline
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    func dismissEditingFocus() {
        focusedThresholdProviderID = nil
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            window.makeFirstResponder(nil)
        }
    }

    func settingsInputPrompt(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(settingsInputPlaceholderColor)
    }

    func relayProminentTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: SettingsVisualTokens.Stroke.hairline)
            )
    }

    func relayProminentSecureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: SettingsVisualTokens.Stroke.hairline)
            )
    }

    func relayCompactTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.80))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: SettingsVisualTokens.Stroke.hairline)
            )
    }

}
