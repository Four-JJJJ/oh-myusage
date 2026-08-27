import SwiftUI

extension SettingsView {
    /// 通用凭证字段行：标题 + 安全输入框 + （可选）自动获取槽位 + 保存按钮 + 提示行。
    /// 保存流程统一为 trim → 空值丢弃 → onSaveValue(trimmed) → 清空输入，
    /// 与各旧表单内联手写保存逻辑逐位一致。
    @ViewBuilder
    func credentialFieldRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        saveLabel: String,
        hintLines: [String] = [],
        autoImport: (label: String, action: () -> Void)? = nil,
        onSaveValue: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            thirdPartyConfigRow(title: title) {
                HStack(spacing: 8) {
                    relayProminentSecureField(placeholder, text: text)
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                    if let autoImport {
                        settingsCapsuleButton(autoImport.label, dismissInputFocus: true, action: autoImport.action)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                    }

                    settingsCapsuleButton(saveLabel, dismissInputFocus: true) {
                        let value = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        onSaveValue(value)
                        text.wrappedValue = ""
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(hintLines, id: \.self) { line in
                thirdPartyHintText(line)
            }
        }
    }

    /// 由 CredentialFieldSpec 驱动的凭证字段行。copy 未提供时退化为传入的兜底文案。
    @ViewBuilder
    func credentialFieldRow(
        spec: CredentialFieldSpec,
        text: Binding<String>,
        saveLabel: String,
        fallbackTitle: String,
        fallbackPlaceholder: String,
        fallbackHintLines: [String] = [],
        autoImport: (label: String, action: () -> Void)? = nil,
        onSaveValue: @escaping (String) -> Void
    ) -> some View {
        credentialFieldRow(
            title: spec.copy?.title ?? fallbackTitle,
            placeholder: spec.copy?.placeholder ?? fallbackPlaceholder,
            text: text,
            saveLabel: saveLabel,
            hintLines: spec.copy?.hintLines ?? fallbackHintLines,
            autoImport: autoImport,
            onSaveValue: onSaveValue
        )
    }
}
