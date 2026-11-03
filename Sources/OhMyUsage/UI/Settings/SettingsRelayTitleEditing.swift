import SwiftUI

extension SettingsView {
    func beginNewRelaySiteNameEdit() {
        relayTitleEditOriginalValue = newRelaySiteDraft.providerName
        if newRelaySiteDraft.providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newRelaySiteDraft.providerName = relayDefaultNewSiteTitle
        }
        editingRelayProviderID = nil
        editingNewRelaySiteName = true
        DispatchQueue.main.async {
            focusedRelayTitleEditorID = "relay-new-site-title"
        }
    }

    func commitNewRelaySiteNameEdit() {
        let trimmed = newRelaySiteDraft.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        newRelaySiteDraft.providerName = trimmed.isEmpty ? relayDefaultNewSiteTitle : trimmed
        editingNewRelaySiteName = false
        focusedRelayTitleEditorID = nil
    }

    func cancelNewRelaySiteNameEdit() {
        newRelaySiteDraft.providerName = relayTitleEditOriginalValue
        editingNewRelaySiteName = false
        focusedRelayTitleEditorID = nil
    }

    func beginRelayProviderNameEdit(_ provider: ProviderDescriptor) {
        let currentName = relayEditorDraft.providerNameInputs[provider.id] ?? provider.name
        relayTitleEditOriginalValue = currentName
        relayEditorDraft.providerNameInputs[provider.id] = currentName
        editingNewRelaySiteName = false
        editingRelayProviderID = provider.id
        DispatchQueue.main.async {
            focusedRelayTitleEditorID = "relay-title-\(provider.id)"
        }
    }

    func commitRelayProviderNameEdit(_ provider: ProviderDescriptor) {
        let input = relayEditorDraft.providerNameInputs[provider.id] ?? provider.name
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelRelayProviderNameEdit(provider)
            return
        }
        relayEditorDraft.providerNameInputs[provider.id] = trimmed
        viewModel.saveRelayDraft(currentRelaySettingsDraft(for: provider))
        editingRelayProviderID = nil
        focusedRelayTitleEditorID = nil
    }

    func cancelRelayProviderNameEdit(_ provider: ProviderDescriptor) {
        relayEditorDraft.providerNameInputs[provider.id] = relayTitleEditOriginalValue
        editingRelayProviderID = nil
        focusedRelayTitleEditorID = nil
    }

    func cancelActiveRelayTitleEdit() {
        if editingNewRelaySiteName {
            newRelaySiteDraft.providerName = relayTitleEditOriginalValue
        }
        if let editingRelayProviderID {
            relayEditorDraft.providerNameInputs[editingRelayProviderID] = relayTitleEditOriginalValue
        }
        editingNewRelaySiteName = false
        editingRelayProviderID = nil
        focusedRelayTitleEditorID = nil
    }

    func relayTitleEditField(
        text: Binding<String>,
        focusID: String,
        placeholder: String,
        onSubmit: @escaping () -> Void,
        onCommitButton: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .trailing) {
            TextField("", text: text, prompt: settingsInputPrompt(placeholder))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsTitleColor)
                .lineLimit(1)
                .padding(.leading, 8)
                .padding(.trailing, 34)
                .focused($focusedRelayTitleEditorID, equals: focusID)
                .onSubmit(onSubmit)

            Button(action: onCommitButton) {
                relayTitleIconImage(named: "relay_title_commit_icon", fallback: "checkmark")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel(viewModel.localizedText("保存名称", "Save name"))
            .help(viewModel.localizedText("保存名称", "Save name"))
        }
        .frame(width: 240, height: 24, alignment: .leading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control)
                .fill(settingsUsesLightAppearance ? Color.white.opacity(0.10) : SettingsVisualTokens.Fill.control)
        )
    }

    func relayTitleIconButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            relayTitleIconImage(named: "relay_title_edit_icon", fallback: systemName)
        }
        .buttonStyle(.plain)
        .frame(width: 14, height: 14)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    @ViewBuilder
    func relayTitleIconImage(named name: String, fallback: String) -> some View {
        if let image = bundledImage(named: name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        } else {
            Image(systemName: fallback)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(settingsTitleColor)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
    }

    func relayHeaderTitleLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(settingsTitleColor)
            .lineLimit(1)
            .frame(height: 14, alignment: .center)
    }
}
