import AppKit
import SwiftUI

enum SettingsThresholdValueStyle {
    case percent
    case number

    var suffix: String? {
        switch self {
        case .percent:
            return "%"
        case .number:
            return nil
        }
    }

    func displayText(for value: Double) -> String {
        switch self {
        case .percent:
            return "\(Int(round(value)))"
        case .number:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        }
    }

    func parse(_ text: String) -> Double? {
        var normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: " ", with: "")

        switch self {
        case .percent:
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        case .number:
            normalized = normalized.replacingOccurrences(of: ",", with: "")
        }
        return Double(normalized)
    }
}

struct SettingsCompactThresholdSlider: NSViewRepresentable {
    @Binding var value: Double
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> SliderView {
        let slider = SliderView()
        configure(slider)
        return slider
    }

    func updateNSView(_ nsView: SliderView, context: Context) {
        configure(nsView)
    }

    private func configure(_ slider: SliderView) {
        slider.value = min(max(value, 0), 100)
        slider.onValueChanged = { newValue in
            value = newValue
        }
        slider.onEditingChanged = onEditingChanged
    }

    final class SliderView: NSView {
        var value: Double = 0 {
            didSet { needsDisplay = true }
        }
        var onValueChanged: (Double) -> Void = { _ in }
        var onEditingChanged: (Bool) -> Void = { _ in }

        private var isEditing = false

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let width = max(bounds.width, 1)
            let clampedValue = min(max(value, 0), 100)
            let fillWidth = width * CGFloat(clampedValue / 100)
            let trackHeight: CGFloat = 4
            let trackY = (bounds.height - trackHeight) / 2
            let trackRect = NSRect(x: 0, y: trackY, width: width, height: trackHeight)

            NSColor(calibratedWhite: 1, alpha: 0.15).setFill()
            NSBezierPath(
                roundedRect: trackRect,
                xRadius: trackHeight / 2,
                yRadius: trackHeight / 2
            ).fill()

            let fillRect = NSRect(x: 0, y: trackY, width: max(0, fillWidth), height: trackHeight)
            NSColor(calibratedWhite: 1, alpha: 0.80).setFill()
            NSBezierPath(
                roundedRect: fillRect,
                xRadius: trackHeight / 2,
                yRadius: trackHeight / 2
            ).fill()

            let thumbSize = NSSize(width: 32, height: 20)
            let thumbX = min(max(fillWidth - thumbSize.width / 2, 0), max(width - thumbSize.width, 0))
            let thumbRect = NSRect(
                x: thumbX,
                y: (bounds.height - thumbSize.height) / 2,
                width: thumbSize.width,
                height: thumbSize.height
            )
            NSColor(
                calibratedRed: 208 / 255,
                green: 208 / 255,
                blue: 208 / 255,
                alpha: 1
            ).setFill()
            NSBezierPath(
                roundedRect: thumbRect,
                xRadius: thumbSize.height / 2,
                yRadius: thumbSize.height / 2
            ).fill()
        }

        override func mouseDown(with event: NSEvent) {
            beginEditingIfNeeded()
            updateValue(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            updateValue(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            updateValue(with: event)
            endEditingIfNeeded()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                endEditingIfNeeded()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        private func updateValue(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let nextValue = min(max(Double(point.x / max(bounds.width, 1)) * 100, 0), 100)
            value = nextValue
            onValueChanged(nextValue)
        }

        private func beginEditingIfNeeded() {
            guard !isEditing else { return }
            isEditing = true
            onEditingChanged(true)
        }

        private func endEditingIfNeeded() {
            guard isEditing else { return }
            isEditing = false
            onEditingChanged(false)
        }
    }
}

struct SettingsThresholdControlRowSlider: NSViewRepresentable {
    @Binding var value: Double
    var onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onEditingChanged: onEditingChanged)
    }

    func makeNSView(context: Context) -> SliderView {
        let slider = SliderView(
            value: min(max(value, 0), 100),
            minValue: 0,
            maxValue: 100,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.controlSize = .small
        slider.trackFillColor = NSColor(calibratedWhite: 1, alpha: 0.80)
        slider.onEditingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.onEditingChanged(editing)
        }
        return slider
    }

    func updateNSView(_ nsView: SliderView, context: Context) {
        context.coordinator.value = $value
        context.coordinator.onEditingChanged = onEditingChanged
        let clampedValue = min(max(value, 0), 100)
        if abs(nsView.doubleValue - clampedValue) > 0.0001 {
            nsView.doubleValue = clampedValue
        }
        nsView.onEditingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.onEditingChanged(editing)
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var onEditingChanged: (Bool) -> Void

        init(value: Binding<Double>, onEditingChanged: @escaping (Bool) -> Void) {
            self.value = value
            self.onEditingChanged = onEditingChanged
        }

        @MainActor @objc func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = min(max(sender.doubleValue, 0), 100)
        }
    }

    final class SliderView: NSSlider {
        var onEditingChanged: (Bool) -> Void = { _ in }

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            onEditingChanged(true)
            defer { onEditingChanged(false) }
            super.mouseDown(with: event)
        }
    }
}

struct SettingsThresholdValueField: View {
    @Binding var value: Double
    var style: SettingsThresholdValueStyle
    var displayTextOverride: String? = nil
    var step: Double = 1
    var range: ClosedRange<Double> = 0...100
    var onValueCommit: ((Double) -> Void)? = nil
    var onEditingChanged: (Bool) -> Void

    @FocusState private var isFocused: Bool
    @State private var draftText = ""

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 1) {
                TextField("", text: $draftText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsVisualTokens.Text.primary)
                    .lineLimit(1)
                    .frame(width: textFieldWidth, alignment: .leading)
                    .focused($isFocused)
                    .onSubmit {
                        applyDraft()
                        isFocused = false
                    }

                if let suffix = style.suffix {
                    Text(suffix)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsVisualTokens.Text.primary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                Button {
                    adjust(by: step)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)

                Button {
                    adjust(by: -step)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(width: 80, height: 28, alignment: .leading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control)
                .fill(SettingsVisualTokens.Fill.control)
        )
        .onAppear(perform: syncDraftText)
        .onChange(of: value) { _, _ in
            if !isFocused {
                syncDraftText()
            }
        }
        .onChange(of: displayTextOverride) { _, _ in
            if !isFocused {
                syncDraftText()
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                onEditingChanged(true)
                draftText = style.displayText(for: value)
            } else {
                applyDraft()
            }
        }
        .onDisappear {
            applyDraft()
        }
    }

    private func syncDraftText() {
        draftText = displayTextOverride ?? style.displayText(for: value)
    }

    private func adjust(by delta: Double) {
        let base = style.parse(draftText) ?? value
        let nextValue = clamped(base + delta)
        onEditingChanged(true)
        commitValue(nextValue)
    }

    private func applyDraft() {
        guard let parsedValue = style.parse(draftText) else {
            syncDraftText()
            onEditingChanged(false)
            return
        }
        let nextValue = clamped(parsedValue)
        commitValue(nextValue)
    }

    private func commitValue(_ nextValue: Double) {
        value = nextValue
        draftText = style.displayText(for: nextValue)
        onValueCommit?(nextValue)
        onEditingChanged(false)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private var textFieldWidth: CGFloat? {
        guard style.suffix != nil else { return nil }
        let measuredText = draftText.isEmpty ? "0" : draftText
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let width = (measuredText as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(width) + 4, 12), 44)
    }
}

extension SettingsView {
    func settingsConfigThresholdRow(
        title: String,
        value: Binding<Double>,
        valueStyle: SettingsThresholdValueStyle = .percent,
        displayTextOverride: String? = nil,
        onValueCommit: ((Double) -> Void)? = nil,
        onEditingChanged: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .lineLimit(1)
                .frame(width: thirdPartyConfigLabelWidth, alignment: .trailing)

            Spacer()
                .frame(width: thirdPartyConfigLabelSpacing)

            SettingsCompactThresholdSlider(
                value: value,
                onEditingChanged: onEditingChanged
            )
            .frame(width: thirdPartyConfigSliderWidth, height: 20)

            Spacer(minLength: 16)

            SettingsThresholdValueField(
                value: value,
                style: valueStyle,
                displayTextOverride: displayTextOverride,
                onValueCommit: onValueCommit,
                onEditingChanged: onEditingChanged
            )
        }
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
    }
}
