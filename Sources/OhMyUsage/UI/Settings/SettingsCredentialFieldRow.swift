import SwiftUI

/// doc 10.3：凭证输入默认折叠的容器。标题即触发器——点击「重新导入凭证 / 手动配置凭证」
/// 才展开内容；展开状态为视图本地状态，切换 Provider 后回到默认折叠。
struct SettingsCredentialDisclosureBlock<Content: View>: View {
    let headerTitle: String
    @State private var isExpanded = false
    private var externalExpansion: Binding<Bool>?
    @ViewBuilder var content: () -> Content

    init(headerTitle: String, @ViewBuilder content: @escaping () -> Content) {
        self.headerTitle = headerTitle
        self.content = content
    }

    /// 展开状态托管到外部（如 relayEditorDraft 草稿字典）时使用，
    /// 供“保存新站点后自动聚焦凭证框”等跨视图联动展开。
    init(headerTitle: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.headerTitle = headerTitle
        self.externalExpansion = isExpanded
        self.content = content
    }

    private var expansion: Binding<Bool> {
        externalExpansion ?? Binding(
            get: { isExpanded },
            set: { isExpanded = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expansion.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(headerTitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SettingsVisualTokens.Text.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: expansion.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsVisualTokens.Text.primary)
                }
                .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(headerTitle)

            if expansion.wrappedValue {
                content()
            }
        }
    }
}

extension SettingsView {
    /// 通用凭证字段行：标题 + 安全输入框 + （可选）自动获取槽位 + 保存按钮 + 提示行。
    /// 保存流程统一为 trim → 空值丢弃 → onSaveValue(trimmed) → 清空输入，
    /// 与各旧表单内联手写保存逻辑逐位一致。focus 用于「保存新站点后自动聚焦凭证框」，
    /// 仅折叠区内需要跨视图联动聚焦的表单传入。
    @ViewBuilder
    func credentialFieldRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        saveLabel: String,
        hintLines: [String] = [],
        autoImport: (label: String, action: () -> Void)? = nil,
        focus: (binding: FocusState<String?>.Binding, value: String)? = nil,
        onSaveValue: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            thirdPartyConfigRow(title: title) {
                HStack(spacing: 8) {
                    Group {
                        if let focus {
                            relayProminentSecureField(placeholder, text: text)
                                .focused(focus.binding, equals: focus.value)
                        } else {
                            relayProminentSecureField(placeholder, text: text)
                        }
                    }
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
        focus: (binding: FocusState<String?>.Binding, value: String)? = nil,
        onSaveValue: @escaping (String) -> Void
    ) -> some View {
        credentialFieldRow(
            title: spec.copy?.title ?? fallbackTitle,
            placeholder: spec.copy?.placeholder ?? fallbackPlaceholder,
            text: text,
            saveLabel: saveLabel,
            hintLines: spec.copy?.hintLines ?? fallbackHintLines,
            autoImport: autoImport,
            focus: focus,
            onSaveValue: onSaveValue
        )
    }
}
