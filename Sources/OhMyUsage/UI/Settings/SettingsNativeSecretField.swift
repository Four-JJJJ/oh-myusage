import AppKit
import SwiftUI

/// 原生 NSSecureTextField 封装：保证点击聚焦、⌘V 粘贴与输入法在所有系统版本下可靠。
/// 用于官方提供者凭据等关键密钥输入位。
struct NativeSecretTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 12)
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeSecretTextField

        init(_ parent: NativeSecretTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

extension SettingsView {
    /// 凭证信息专用：原生安全输入 + 与其他配置控件一致的外观。
    func officialBearerSecureField(
        _ placeholder: String,
        text: Binding<String>
    ) -> some View {
        NativeSecretTextField(placeholder: placeholder, text: text)
            .font(.system(size: 12))
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
