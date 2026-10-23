import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    func openClaudeProfileEditor(slotID: CodexSlotID, existingProfile: ClaudeAccountProfile?) {
        let key = slotID.rawValue
        dialogState.claudeProfileEditorSource = existingProfile?.source ?? .configDir
        dialogState.claudeProfileEditorConfigDir = profileDraftState.claudeProfileConfigDirInputs[key] ?? existingProfile?.configDir ?? ""
        dialogState.claudeProfileEditorJSON = profileDraftState.claudeProfileJSONInputs[key] ?? existingProfile?.credentialsJSON ?? ""
        dialogState.claudeProfileEditorNote = OfficialProfileNaming.limitedNote(
            profileDraftState.claudeProfileNoteInputs[key] ?? existingProfile?.note
        )
        dialogState.claudeProfileEditor = ClaudeProfileEditorState(
            slotID: slotID,
            title: OfficialProfileNaming.claudeModelName,
            isNewSlot: existingProfile == nil
        )
    }

    func saveClaudeProfileEditor() {
        guard let editor = dialogState.claudeProfileEditor else { return }
        let key = editor.slotID.rawValue
        let note = OfficialProfileNaming.limitedNote(dialogState.claudeProfileEditorNote)
        dialogState.claudeProfileEditorNote = note
        profileDraftState.claudeProfileConfigDirInputs[key] = dialogState.claudeProfileEditorConfigDir
        profileDraftState.claudeProfileJSONInputs[key] = dialogState.claudeProfileEditorJSON
        profileDraftState.claudeProfileNoteInputs[key] = note
        profileDraftState.claudeProfileResult[key] = viewModel.saveClaudeProfile(
            slotID: editor.slotID,
            displayName: OfficialProfileNaming.displayName(
                modelName: OfficialProfileNaming.claudeModelName,
                slotID: editor.slotID,
                note: note
            ),
            note: note,
            source: dialogState.claudeProfileEditorSource,
            configDir: dialogState.claudeProfileEditorConfigDir,
            credentialsJSON: dialogState.claudeProfileEditorJSON
        )
        dialogState.clearClaudeProfileEditor()
    }

    private var profileDialogBodyColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.82) : Color.white.opacity(0.80)
    }

    private var profileDialogHintColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.46) : Color.white.opacity(0.40)
    }

    private var profileDialogStrokeColor: Color {
        settingsUsesLightAppearance ? Color.black.opacity(0.14) : Color.white.opacity(0.15)
    }

    func profileNoteBinding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { OfficialProfileNaming.limitedNote(source.wrappedValue) },
            set: { source.wrappedValue = OfficialProfileNaming.limitedNote($0) }
        )
    }

    func profileDialogContainer<Content: View>(
        width: CGFloat = 560,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(24)
            .frame(width: width, alignment: .leading)
            .background(
                DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                    .fill(panelBackground)
            )
            .overlay(
                DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                    .stroke(profileDialogStrokeColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.50), radius: 45, x: 0, y: 17)
            .shadow(color: Color.black.opacity(0.20), radius: 1, x: 0, y: 0)
    }

    func profileDialogHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(profileDialogBodyColor)

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(profileDialogHintColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func profileDialogNoteRow(note: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 0) {
                Text(viewModel.localizedText("备注名称", "Note"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(profileDialogBodyColor)
                    .frame(width: 64, alignment: .leading)

                profileDialogNoteField(note: note)
            }

            Text(viewModel.localizedText("备注会显示在菜单栏模型卡片上，建议使用简短易辨识的名称", "The note appears on the menu bar model card. Keep it short and recognizable."))
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(profileDialogHintColor)
                .lineLimit(1)
                .padding(.leading, 64)
        }
    }

    func profileDialogNoteField(note: Binding<String>) -> some View {
        ZStack(alignment: .trailing) {
            TextField(
                "",
                text: profileNoteBinding(note),
                prompt: settingsInputPrompt(viewModel.localizedText("例如公司账号/工作/个人", "e.g. Work / Personal"))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(profileDialogBodyColor)
            .padding(.leading, 14)
            .padding(.trailing, 52)

            Text("\(OfficialProfileNaming.limitedNote(note.wrappedValue).count)/\(OfficialProfileNaming.noteLimit)")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(profileDialogHintColor)
                .padding(.trailing, 12)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(settingsInputFillColor)
        )
    }

    func profileDialogTextField(placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: settingsInputPrompt(placeholder))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(profileDialogBodyColor)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(settingsInputFillColor)
            )
    }

    func profileDialogJSONEditor(text: Binding<String>, height: CGFloat = 266) -> some View {
        TextEditor(text: text)
            .scrollContentBackground(.hidden)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(profileDialogBodyColor)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(settingsInputFillColor)
            )
    }

    func profileDialogButton(
        _ title: String,
        dismissInputFocus: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if dismissInputFocus {
                dismissEditingFocus()
            }
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(profileDialogBodyColor)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 24)
                .frame(height: 24)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            settingsUsesLightAppearance
                                ? Color.black.opacity(0.45)
                                : Color.white.opacity(0.75),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    func profileDialogButtonRow(
        cancel: @escaping () -> Void,
        save: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            profileDialogButton(viewModel.text(.permissionCancel), action: cancel)
                .keyboardShortcut(.cancelAction)
            if let save {
                profileDialogButton(viewModel.text(.save), dismissInputFocus: true, action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    var claudeProfileEditorDialog: some View {
        profileDialogContainer {
            VStack(alignment: .leading, spacing: 24) {
                profileDialogHeader(
                    title: claudeProfileEditorTitle,
                    subtitle: viewModel.localizedText(
                        "支持两种导入方式：绑定一个 CLAUDE_CONFIG_DIR 目录，或粘贴完整 .credentials.json。如果手动粘贴缺少 email，建议同时绑定目录读取 claude.json。切换时会同步写回系统默认 Claude 登录。",
                        "Bind a CLAUDE_CONFIG_DIR directory or paste the full .credentials.json. If manual JSON has no email, also bind the directory so claude.json can be used. Switching also writes to the system Claude credentials."
                    )
                )

                profileDialogNoteRow(note: $dialogState.claudeProfileEditorNote)

                VStack(alignment: .leading, spacing: 12) {
                    officialSegmentControl(
                        selection: $dialogState.claudeProfileEditorSource,
                        options: ClaudeProfileSource.allCases,
                        label: claudeProfileSourceLabel
                    )

                    HStack(alignment: .center, spacing: 0) {
                        Text(viewModel.localizedText("目录", "Directory"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(profileDialogBodyColor)
                            .frame(width: 64, alignment: .leading)

                        profileDialogTextField(
                            placeholder: "~/.claude-profile",
                            text: $dialogState.claudeProfileEditorConfigDir
                        )
                    }

                    if dialogState.claudeProfileEditorSource == .manualCredentials {
                        profileDialogJSONEditor(text: $dialogState.claudeProfileEditorJSON, height: 220)
                    }
                }

                profileDialogButtonRow(
                    cancel: { dialogState.clearClaudeProfileEditor() },
                    save: { saveClaudeProfileEditor() }
                )
            }
        }
    }

    var claudeProfileEditorTitle: String {
        guard let editor = dialogState.claudeProfileEditor else { return "" }
        if viewModel.language == .zhHans {
            return editor.isNewSlot ? "添加 \(editor.title) 凭证" : "编辑 \(editor.title) 凭证"
        }
        return editor.isNewSlot ? "Add \(editor.title) credentials" : "Edit \(editor.title) credentials"
    }

    var oauthImportProgressDialog: some View {
        profileDialogContainer {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(oauthImportDialogTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(profileDialogBodyColor)

                    if let state = activeOAuthImportDialogState {
                        Text(oauthImportStateText(state))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(oauthImportStateColor(state))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = state.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(profileDialogHintColor)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                profileDialogButtonRow(
                    cancel: {
                        guard let state = activeOAuthImportDialogState else { return }
                        viewModel.cancelOAuthImport(providerType: oauthProviderType(for: state.provider))
                    }
                )
            }
        }
    }

    private var oauthImportDialogTitle: String {
        guard let state = activeOAuthImportDialogState else { return "" }
        switch state.provider {
        case .codex:
            return viewModel.localizedText("Codex OAuth 添加", "Add Codex via OAuth")
        case .claude:
            return viewModel.localizedText("Claude OAuth 添加", "Add Claude via OAuth")
        }
    }

    private func oauthProviderType(for provider: OAuthImportProvider) -> ProviderType {
        switch provider {
        case .codex:
            return .codex
        case .claude:
            return .claude
        }
    }

    func oauthImportStateText(_ state: OAuthImportState) -> String {
        switch state.phase {
        case .launching:
            return viewModel.localizedText("正在启动官方 CLI 登录流程…", "Launching official CLI login…")
        case .waitingForBrowser:
            return viewModel.localizedText("请在浏览器完成授权，完成后将自动导入本地账号", "Complete authorization in your browser. The local account will be imported automatically.")
        case .waitingForDevice:
            return viewModel.localizedText("浏览器回调失败，已自动回退到 Device Code 登录。", "Browser callback failed. Automatically switched to Device Code login.")
        case .verifying:
            return viewModel.localizedText("正在读取并校验本地凭据…", "Reading and validating local credentials…")
        case .succeeded:
            return viewModel.localizedText("OAuth 导入成功。", "OAuth import succeeded.")
        case .failed:
            return viewModel.localizedText("OAuth 导入失败。", "OAuth import failed.")
        case .cancelled:
            return viewModel.localizedText("OAuth 导入已取消。", "OAuth import cancelled.")
        }
    }

    func oauthImportStateColor(_ state: OAuthImportState) -> Color {
        switch state.phase {
        case .failed:
            return Color(hex: 0xD05757)
        case .succeeded:
            return Color(hex: 0x69BD64)
        default:
            return settingsBodyColor
        }
    }

    func openCodexProfileEditor(slotID: CodexSlotID, existingProfile: CodexAccountProfile?) {
        let key = slotID.rawValue
        dialogState.codexProfileEditorJSON = profileDraftState.codexProfileJSONInputs[key] ?? existingProfile?.authJSON ?? ""
        dialogState.codexProfileEditorNote = OfficialProfileNaming.limitedNote(
            profileDraftState.codexProfileNoteInputs[key] ?? existingProfile?.note
        )
        dialogState.codexProfileEditor = CodexProfileEditorState(
            slotID: slotID,
            title: OfficialProfileNaming.codexModelName,
            isNewSlot: existingProfile == nil
        )
    }

    func saveCodexProfileEditor() {
        guard let editor = dialogState.codexProfileEditor else { return }
        let key = editor.slotID.rawValue
        let note = OfficialProfileNaming.limitedNote(dialogState.codexProfileEditorNote)
        dialogState.codexProfileEditorNote = note
        profileDraftState.codexProfileJSONInputs[key] = dialogState.codexProfileEditorJSON
        profileDraftState.codexProfileNoteInputs[key] = note
        profileDraftState.codexProfileResult[key] = viewModel.saveCodexProfile(
            slotID: editor.slotID,
            displayName: OfficialProfileNaming.displayName(
                modelName: OfficialProfileNaming.codexModelName,
                slotID: editor.slotID,
                note: note
            ),
            note: note,
            authJSON: dialogState.codexProfileEditorJSON
        )
        dialogState.clearCodexProfileEditor()
    }

    var codexProfileEditorDialog: some View {
        profileDialogContainer {
            VStack(alignment: .leading, spacing: 24) {
                profileDialogHeader(
                    title: codexProfileEditorTitle,
                    subtitle: viewModel.text(.codexAuthJSONHowTo)
                )

                profileDialogNoteRow(note: $dialogState.codexProfileEditorNote)

                profileDialogJSONEditor(text: $dialogState.codexProfileEditorJSON)

                profileDialogButtonRow(
                    cancel: { dialogState.clearCodexProfileEditor() },
                    save: { saveCodexProfileEditor() }
                )
            }
        }
    }

    var codexProfileEditorTitle: String {
        guard let editor = dialogState.codexProfileEditor else { return "" }
        if viewModel.language == .zhHans {
            return editor.isNewSlot ? "添加 \(editor.title) auth.json" : "编辑 \(editor.title) auth.json"
        }
        return editor.isNewSlot ? "Add \(editor.title) auth.json" : "Edit \(editor.title) auth.json"
    }

    func profileEmailWithNote(email: String?, note: String?, fallback: String) -> String {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmail = (trimmedEmail?.isEmpty == false ? trimmedEmail! : fallback)
        guard let trimmedNote, !trimmedNote.isEmpty else {
            return resolvedEmail
        }
        return "\(resolvedEmail) \(trimmedNote)"
    }

    func claudeProfileSubtitle(profile: ClaudeAccountProfile, fallback: String) -> String {
        let trimmedNote = profile.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let email = profile.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            guard let trimmedNote, !trimmedNote.isEmpty else {
                return email
            }
            return "\(email) \(trimmedNote)"
        }
        if let trimmedNote, !trimmedNote.isEmpty {
            return trimmedNote
        }
        if let fingerprint = claudeShortFingerprint(profile.credentialFingerprint) {
            return viewModel.localizedText("指纹 \(fingerprint)", "Fingerprint \(fingerprint)")
        }
        return fallback
    }

    func claudeProfileIdentitySubtitle(profile: ClaudeAccountProfile, fallback: String) -> String {
        if let email = profile.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return email
        }
        if let note = profile.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return note
        }
        if let fingerprint = claudeShortFingerprint(profile.credentialFingerprint) {
            return viewModel.localizedText("指纹 \(fingerprint)", "Fingerprint \(fingerprint)")
        }
        return fallback
    }

    private func claudeShortFingerprint(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(8)).lowercased()
    }
}
