import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    func relayPresetProvider(for presetID: String) -> ProviderDescriptor? {
        viewModel.config.providers.first { provider in
            provider.family == .thirdParty && provider.relayConfig?.adapterID == presetID
        }
    }

    func setRelayPresetEnabled(_ enabled: Bool, preset: RelayTemplatePreset) {
        if let provider = relayPresetProvider(for: preset.id) {
            viewModel.setEnabled(enabled, providerID: provider.id)
            navigationState.selectedGroup = .thirdParty
            navigationState.selectedProviderID = provider.id
            return
        }

        guard enabled else { return }

        // Phase 2：preset 开关不再直接创建 provider，改为打开统一的草稿面板并预填 preset 模板
        cancelActiveRelayTitleEdit()
        newRelaySiteDraft.reset(using: preset.id)
        newRelaySiteDraft.selectedPresetID = preset.id
        applyRelayPreset(preset)
        navigationState.selectedGroup = .thirdParty
        navigationState.selectedProviderID = nil
        showingRelayNewSiteDraft = true
    }

    var newAPICustomSection: some View {
        let selectedPreset = relayBuiltInPresets.first(where: { $0.id == newRelaySiteDraft.selectedPresetID })
        let selectedManifest = selectedPreset?.manifest ?? relaySiteTemplates.first?.manifest
        let selectedRequiredInputs = selectedManifest.map {
            relayRequiredInputs(
                for: $0,
                tokenChannelEnabled: $0.tokenRequest != nil && $0.match.defaultTokenChannelEnabled,
                accountChannelEnabled: $0.match.defaultBalanceChannelEnabled,
                showsManualUserID: relayTemplateNeedsManualUserID($0)
            )
        } ?? [.displayName, .baseURL]
        let showNameField = true
        let showBaseURLField = selectedRequiredInputs.contains(.baseURL)

        return VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.text(.relayTemplate))
                .font(settingsLabelFont)
                .foregroundStyle(settingsHintColor)

            Text(relaySiteTemplates.first?.displayName ?? "NewAPI")
                .font(settingsBodyFont)
                .foregroundStyle(settingsBodyColor)

            HStack(spacing: 8) {
                if showNameField {
                    relayProminentTextField(viewModel.text(.providerName), text: $newRelaySiteDraft.providerName)
                }
                if showBaseURLField {
                    relayProminentTextField(viewModel.text(.baseURL), text: $newRelaySiteDraft.baseURL)
                }
                settingsActionButton(viewModel.localizedText("继续", "Continue"), prominent: true) {
                    // Phase 2：对话框不再直接创建 provider，改为带着已填的名称/地址
                    // 打开统一的草稿面板补录凭证后再保存
                    dialogState.isNewAPISiteDialogPresented = false
                    cancelActiveRelayTitleEdit()
                    navigationState.selectedGroup = .thirdParty
                    navigationState.selectedProviderID = nil
                    showingRelayNewSiteDraft = true
                }
            }

            if !showBaseURLField, let selectedManifest, let suggestedBaseURL = suggestedBaseURL(for: selectedManifest) {
                Text("Base URL: \(suggestedBaseURL)")
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
            }

            if let preset = selectedPreset ?? relaySiteTemplates.first(where: { $0.id == newRelaySiteDraft.templateID }) {
                Text(relayRequiredInputSummary(
                    manifest: preset.manifest,
                    tokenChannelEnabled: preset.manifest.tokenRequest != nil && preset.manifest.match.defaultTokenChannelEnabled,
                    accountChannelEnabled: preset.manifest.match.defaultBalanceChannelEnabled,
                    showsManualUserID: relayTemplateNeedsManualUserID(preset.manifest)
                ))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)

                Text(relayFixedTemplateSummary(for: preset.manifest))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
            }

            Text(viewModel.text(.relayTemplatePresetHint))
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)
        }
    }

    var newAPISiteDialog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.language == .zhHans ? "添加 NewAPI 站点" : "Add NewAPI Site")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(settingsBodyColor)

            newAPICustomSection

            HStack {
                Spacer(minLength: 0)
                settingsCapsuleButton(viewModel.text(.permissionCancel)) {
                    dialogState.isNewAPISiteDialogPresented = false
                }
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
        .background(
            DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                .fill(panelBackground)
        )
        .overlay(
            DialogSmoothRoundedRectangle(cornerRadius: 16, smoothing: 0.6)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 45, x: 0, y: 17)
        .shadow(color: Color.black.opacity(0.20), radius: 1, x: 0, y: 0)
    }

    func relayPresetSidebarRow(_ preset: RelayTemplatePreset) -> some View {
        let provider = relayPresetProvider(for: preset.id)
        let isEnabled = provider?.enabled ?? false
        let isSelected = provider.map { navigationState.selectedProviderID == $0.id } ?? false

        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { setRelayPresetEnabled($0, preset: preset) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            if let provider {
                providerIcon(for: provider, size: 12)
            } else if let image = themedBundledImage(named: relayPresetIconName(for: preset)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else if let image = themedBundledImage(named: "menu_relay_icon") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(settingsBodyColor)
            }

            Text(preset.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? settingsSelectedRowFillColor : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? settingsSelectedRowStrokeColor : settingsRowStrokeColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let provider {
                navigationState.selectedProviderID = provider.id
            }
        }
    }

    func relayPresetIconName(for preset: RelayTemplatePreset) -> String {
        let presetID = preset.id.lowercased()
        if presetID.contains("moonshot") || presetID.contains("moonsho") {
            return "menu_kimi_icon"
        }
        if presetID.contains("deepseek") {
            return firstExistingRelayIconName([
                "menu_deepseek_icon",
                "menu_deep_seek_icon"
            ]) ?? "menu_relay_icon"
        }
        if presetID.contains("xiaomimimo") || presetID.contains("mimo") {
            return firstExistingRelayIconName([
                "menu_mimo_icon",
                "menu_xiaomimimo_icon",
                "menu_xiaomi_mimo_icon"
            ]) ?? "menu_relay_icon"
        }
        if presetID.contains("minimax") || presetID.contains("minimaxi") {
            return firstExistingRelayIconName([
                "menu_minimax_icon",
                "menu_minimaxi_icon"
            ]) ?? "menu_relay_icon"
        }
        return "menu_relay_icon"
    }

    var unaddedRelayBuiltInPresets: [RelayTemplatePreset] {
        let configuredPresetIDs = Set(
            viewModel.config.providers
                .filter { $0.family == .thirdParty }
                .compactMap { $0.relayConfig?.adapterID }
        )
        return relayBuiltInPresets.filter { !configuredPresetIDs.contains($0.id) }
    }

    var relayTemplatePresets: [RelayTemplatePreset] {
        RelayAdapterRegistry.shared
            .builtInManifests()
            .map { manifest in
                RelayTemplatePreset(
                    manifest: manifest,
                    suggestedBaseURL: suggestedBaseURL(for: manifest)
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.id == "generic-newapi", rhs.id == "generic-newapi") {
                case (true, false):
                    return false
                case (false, true):
                    return true
                default:
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }
    }

    var relaySiteTemplates: [RelayTemplatePreset] {
        relayTemplatePresets.filter { $0.id == "generic-newapi" }
    }

    var relayBuiltInPresets: [RelayTemplatePreset] {
        []
    }

    func relayTemplateNeedsManualUserID(_ manifest: RelayAdapterManifest) -> Bool {
        if manifest.id == "minimax" {
            // GroupId remains available for Cookie compatibility, but the
            // preferred Coding Plan API-key flow does not require it.
            return true
        }
        let setupRequiresUserID = manifest.setup?.requiredInputs.contains(.userID) ?? false
        return setupRequiresUserID || (
            manifest.balanceRequest.userID == nil &&
            !(manifest.balanceRequest.userIDHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        )
    }

    func suggestedBaseURL(for manifest: RelayAdapterManifest) -> String? {
        if let recommendedBaseURL = manifest.setup?.recommendedBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommendedBaseURL.isEmpty {
            return recommendedBaseURL
        }
        guard let hostPattern = manifest.match.hostPatterns.first(where: { $0 != "*" }) else {
            return nil
        }
        let normalizedHost: String
        if hostPattern.hasPrefix("*.") {
            normalizedHost = String(hostPattern.dropFirst(2))
        } else {
            normalizedHost = hostPattern
        }
        return normalizedHost.isEmpty ? nil : "https://\(normalizedHost)"
    }

    func applyNewRelayTemplate(_ templateID: String) {
        newRelaySiteDraft.templateID = templateID
        newRelaySiteDraft.testState = .unverified
        guard let preset = relaySiteTemplates.first(where: { $0.id == templateID }) else { return }
        if let suggestedBaseURL = preset.suggestedBaseURL {
            newRelaySiteDraft.baseURL = suggestedBaseURL
        } else {
            newRelaySiteDraft.baseURL = ""
        }
        if newRelaySiteDraft.selectedPresetID == nil {
            newRelaySiteDraft.providerName = ""
        }
    }

    func applyRelayPreset(_ preset: RelayTemplatePreset) {
        newRelaySiteDraft.testState = .unverified
        if let suggestedBaseURL = preset.suggestedBaseURL {
            newRelaySiteDraft.baseURL = suggestedBaseURL
        } else {
            newRelaySiteDraft.baseURL = "https://"
        }
        newRelaySiteDraft.providerName = preset.displayName
    }

    func selectedNewRelaySiteManifest() -> RelayAdapterManifest {
        if let selectedPresetID = newRelaySiteDraft.selectedPresetID,
           let selectedPreset = relayTemplatePresets.first(where: { $0.id == selectedPresetID }) {
            return selectedPreset.manifest
        }
        if let selectedTemplate = relaySiteTemplates.first(where: { $0.id == newRelaySiteDraft.templateID }) {
            return selectedTemplate.manifest
        }
        return RelayAdapterRegistry.genericManifest
    }

    func saveNewRelaySiteDraft() {
        if editingNewRelaySiteName {
            commitNewRelaySiteNameEdit()
        }

        let selectedManifest = selectedNewRelaySiteManifest()
        let resolvedBaseURL = resolvedRelayBaseURLInput(
            typedBaseURL: newRelaySiteDraft.baseURL,
            manifest: selectedManifest
        )
        guard !ProviderDescriptor.normalizeRelayBaseURL(resolvedBaseURL).isEmpty else {
            return
        }

        let typedName = newRelaySiteDraft.providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? relayDefaultNewSiteTitle
            : newRelaySiteDraft.providerName
        guard let added = viewModel.addRelaySiteDraft(
            name: resolvedRelayNameInput(
                typedName: typedName,
                manifest: selectedManifest
            ),
            baseURL: resolvedBaseURL,
            preferredAdapterID: newRelaySiteDraft.selectedPresetID ?? newRelaySiteDraft.templateID,
            userID: newRelaySiteDraft.userID,
            credentialInput: newRelaySiteDraft.credentialInput,
            balanceCredentialMode: .browserPreferred
        ) else {
            return
        }

        navigationState.selectedGroup = .thirdParty
        navigationState.selectedProviderID = added.id
        showingRelayNewSiteDraft = false

        // 保存后若仍缺凭证（余额凭证未填，或额度 token 通道开启但未保存），
        // 让编辑页自动聚焦对应凭证输入框补录
        let needsBalanceCredential = added.relayViewConfig?.accountBalance
            .map { !viewModel.hasToken(auth: $0.auth) } ?? false
        let needsQuotaCredential = (added.relayConfig?.tokenChannelEnabled ?? false)
            && !viewModel.hasToken(for: added)
        if needsBalanceCredential || needsQuotaCredential {
            pendingRelayCredentialFocusProviderID = added.id
        }

        let templateID = newRelaySiteDraft.templateID
        newRelaySiteDraft.reset(using: templateID)
        applyNewRelayTemplate(templateID)
        cancelActiveRelayTitleEdit()
    }

    func resolvedRelayNameInput(
        typedName: String,
        manifest: RelayAdapterManifest?
    ) -> String {
        let trimmed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return manifest?.displayName ?? typedName
    }

    func resolvedRelayBaseURLInput(
        typedBaseURL: String,
        manifest: RelayAdapterManifest?
    ) -> String {
        let trimmed = typedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return suggestedBaseURL(for: manifest ?? RelayAdapterRegistry.genericManifest) ?? typedBaseURL
    }

    enum RelaySetupHintField {
        case quotaAuth
        case balanceAuth
        case userID
    }

    func relaySetupHint(
        for manifest: RelayAdapterManifest,
        field: RelaySetupHintField
    ) -> String? {
        let localized: RelaySetupManifest.LocalizedText?
        switch field {
        case .quotaAuth:
            localized = manifest.setup?.quotaAuthHint
        case .balanceAuth:
            localized = manifest.setup?.balanceAuthHint
        case .userID:
            localized = manifest.setup?.userIDHint
        }

        switch viewModel.language {
        case .zhHans:
            return localized?.zhHans ?? localized?.en
        case .en:
            return localized?.en ?? localized?.zhHans
        }
    }

    func relayDiagnosticHint(for manifest: RelayAdapterManifest) -> String? {
        switch viewModel.language {
        case .zhHans:
            return manifest.setup?.diagnosticHints?.zhHans ?? manifest.setup?.diagnosticHints?.en
        case .en:
            return manifest.setup?.diagnosticHints?.en ?? manifest.setup?.diagnosticHints?.zhHans
        }
    }

    func relayRequiredInputs(
        for manifest: RelayAdapterManifest,
        tokenChannelEnabled: Bool,
        accountChannelEnabled: Bool,
        showsManualUserID: Bool
    ) -> [RelayRequiredInputKind] {
        if let setupInputs = manifest.setup?.requiredInputs, !setupInputs.isEmpty {
            var resolved: [RelayRequiredInputKind] = []
            for item in setupInputs {
                switch item {
                case .quotaAuth where tokenChannelEnabled:
                    resolved.append(item)
                case .balanceAuth where accountChannelEnabled:
                    resolved.append(item)
                case .userID where showsManualUserID:
                    resolved.append(item)
                case .quotaAuth, .balanceAuth, .userID:
                    continue
                default:
                    resolved.append(item)
                }
            }
            if showsManualUserID,
               manifest.id != "minimax",
               !resolved.contains(.userID),
               relayTemplateNeedsManualUserID(manifest) {
                resolved.append(.userID)
            }
            return resolved
        }

        var inferred: [RelayRequiredInputKind] = [.displayName, .baseURL]
        if tokenChannelEnabled {
            inferred.append(.quotaAuth)
        }
        if accountChannelEnabled {
            inferred.append(.balanceAuth)
        }
        if showsManualUserID {
            inferred.append(.userID)
        }
        return inferred
    }

    func requiresDisplayNameInput(
        for manifest: RelayAdapterManifest,
        currentName: String
    ) -> Bool {
        let requiredInputs = manifest.setup?.requiredInputs ?? []
        if requiredInputs.isEmpty {
            return true
        }
        if requiredInputs.contains(.displayName) {
            return true
        }
        return currentName.trimmingCharacters(in: .whitespacesAndNewlines) != manifest.displayName
    }

    func requiresBaseURLInput(
        for manifest: RelayAdapterManifest,
        currentBaseURL: String
    ) -> Bool {
        let requiredInputs = manifest.setup?.requiredInputs ?? []
        if requiredInputs.isEmpty {
            return true
        }
        if requiredInputs.contains(.baseURL) {
            return true
        }
        guard let suggestedBaseURL = suggestedBaseURL(for: manifest) else {
            return true
        }
        return ProviderDescriptor.normalizeRelayBaseURL(currentBaseURL) != ProviderDescriptor.normalizeRelayBaseURL(suggestedBaseURL)
    }

    func relayRequiredInputSummary(
        manifest: RelayAdapterManifest,
        tokenChannelEnabled: Bool,
        accountChannelEnabled: Bool,
        showsManualUserID: Bool
    ) -> String {
        let tokenTemplateKind = relayCredentialTemplate(authHeader: "Authorization", authScheme: "Bearer").kind
        let balanceTemplateKind = relayCredentialTemplate(
            authHeader: manifest.balanceRequest.authHeader,
            authScheme: manifest.balanceRequest.authScheme
        ).kind
        let items = relayRequiredInputs(
            for: manifest,
            tokenChannelEnabled: tokenChannelEnabled,
            accountChannelEnabled: accountChannelEnabled,
            showsManualUserID: showsManualUserID
        ).filter { $0 != .displayName }.map { item in
            switch item {
            case .displayName:
                return viewModel.language == .zhHans ? "名称" : "Name"
            case .baseURL:
                return "Base URL"
            case .quotaAuth:
                return relayCredentialFieldName(isAccount: false, templateKind: tokenTemplateKind)
            case .balanceAuth:
                return relayCredentialFieldName(isAccount: true, templateKind: balanceTemplateKind)
            case .userID:
                return viewModel.language == .zhHans ? "用户 ID" : "User ID"
            }
        }

        let joined = items.joined(separator: viewModel.language == .zhHans ? "、" : ", ")
        if viewModel.language == .zhHans {
            if joined.isEmpty {
                return "当前模板 `\(manifest.displayName)` 的接口配置已固定，名称可自定义。"
            }
            return "当前模板 `\(manifest.displayName)` 的核心必填项：\(joined)。名称可自定义。"
        } else {
            if joined.isEmpty {
                return "Template `\(manifest.displayName)` already fixes the endpoint details; the display name is optional and customizable."
            }
            return "Template `\(manifest.displayName)` only needs these core fields: \(joined). Display name is optional and customizable."
        }
    }

    func relayFixedTemplateSummary(for manifest: RelayAdapterManifest) -> String {
        let language = viewModel.language
        var parts: [String] = []

        if let suggestedBaseURL = suggestedBaseURL(for: manifest) {
            parts.append(language == .zhHans ? "固定地址 = \(suggestedBaseURL)" : "base URL = \(suggestedBaseURL)")
        }

        parts.append("\(manifest.balanceRequest.method) \(manifest.balanceRequest.path)")
        parts.append(language == .zhHans
            ? "剩余 = \(manifest.extract.remaining)"
            : "remaining = \(manifest.extract.remaining)")

        if let used = manifest.extract.used, !used.isEmpty {
            parts.append(language == .zhHans ? "已用 = \(used)" : "used = \(used)")
        }
        if let limit = manifest.extract.limit, !limit.isEmpty {
            parts.append(language == .zhHans ? "上限 = \(limit)" : "limit = \(limit)")
        }
        if let unit = manifest.extract.unit, !unit.isEmpty {
            parts.append(language == .zhHans ? "单位 = \(unit)" : "unit = \(unit)")
        }

        let joined = parts.joined(separator: language == .zhHans ? "；" : "; ")
        if language == .zhHans {
            return "以下内容由模板固定：\(joined)。如需改接口或字段映射，再展开高级设置。"
        } else {
            return "These values are fixed by the template: \(joined). Open Advanced settings only if the site differs."
        }
    }
}
