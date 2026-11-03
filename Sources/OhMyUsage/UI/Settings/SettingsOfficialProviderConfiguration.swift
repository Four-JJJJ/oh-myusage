import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    @ViewBuilder
    func officialConfigurationRows(_ provider: ProviderDescriptor) -> some View {
        let settingsSpec = ProviderSettingsSpec.resolve(for: provider)
        let supportedSourceModes = settingsSpec.supportedSourceModes
        let visibleWebModes = officialConfigVisibleWebModes(settingsSpec.supportedWebModes)
        let quotaDisplayBinding: Binding<OfficialQuotaDisplayMode> = Binding(
            get: {
                officialEditorDraft.officialQuotaDisplayModeInputs[provider.id]
                    ?? (provider.officialConfig?.quotaDisplayMode
                        ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).quotaDisplayMode)
            },
            set: { officialEditorDraft.officialQuotaDisplayModeInputs[provider.id] = $0 }
        )
        let traeValueDisplayBinding: Binding<OfficialTraeValueDisplayMode> = Binding(
            get: {
                officialEditorDraft.officialTraeValueDisplayModeInputs[provider.id]
                    ?? (provider.officialConfig?.traeValueDisplayMode
                        ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).traeValueDisplayMode
                        ?? .percent)
            },
            set: { officialEditorDraft.officialTraeValueDisplayModeInputs[provider.id] = $0 }
        )
        let sourceBinding: Binding<OfficialSourceMode> = Binding(
            get: {
                let current = officialEditorDraft.officialSourceModeInputs[provider.id] ?? (provider.officialConfig?.sourceMode ?? .auto)
                return supportedSourceModes.contains(current) ? current : (supportedSourceModes.first ?? .auto)
            },
            set: { officialEditorDraft.officialSourceModeInputs[provider.id] = $0 }
        )
        let webBinding: Binding<OfficialWebMode> = Binding(
            get: {
                let current = officialEditorDraft.officialWebModeInputs[provider.id] ?? (provider.officialConfig?.webMode ?? .disabled)
                return settingsSpec.supportedWebModes.contains(current) ? current : (settingsSpec.supportedWebModes.first ?? .disabled)
            },
            set: { officialEditorDraft.officialWebModeInputs[provider.id] = $0 }
        )

        let hasSavedOfficialCredential = providerConfigurationFacade.hasToken(for: provider)
            || providerConfigurationFacade.hasOfficialManualCookie(for: provider)

        settingsConfigurationRows {
            settingsDetailGroupCaption(viewModel.text(.relayAuthorizationAndImport))

            if !supportedSourceModes.isEmpty {
                settingsConfigRow(title: viewModel.text(.officialConfigSource), nested: true) {
                    settingsConfigSegmentedControl(
                        options: supportedSourceModes.map {
                            SettingsPillSegmentOption(id: $0.id, title: officialConfigSourceModeLabel($0))
                        },
                        selection: sourceBinding.wrappedValue.id,
                        width: officialConfigSourceSegmentWidth(supportedSourceModes)
                    ) { selectedID in
                        if let selected = supportedSourceModes.first(where: { $0.id == selectedID }) {
                            sourceBinding.wrappedValue = selected
                        }
                    }
                }
            }

            if visibleWebModes.count > 1 {
                let webSelection = officialConfigResolvedWebSelection(webBinding.wrappedValue, visibleModes: visibleWebModes)
                settingsConfigRow(title: viewModel.text(.officialConfigWeb), nested: true) {
                    settingsConfigSegmentedControl(
                        options: visibleWebModes.map {
                            SettingsPillSegmentOption(id: $0.id, title: officialConfigWebModeLabel($0))
                        },
                        selection: webSelection.id,
                        width: officialConfigWebSegmentWidth(visibleWebModes)
                    ) { selectedID in
                        if let selected = visibleWebModes.first(where: { $0.id == selectedID }) {
                            webBinding.wrappedValue = selected
                        }
                    }
                }
            }

            if !settingsSpec.credentialFields.isEmpty {
                // 凭证输入默认折叠，只有点击「重新导入凭证 / 手动配置凭证」时展开。
                SettingsCredentialDisclosureBlock(
                    headerTitle: SettingsCredentialDisclosurePresenter.headerTitle(
                        hasSavedCredential: hasSavedOfficialCredential,
                        language: viewModel.language
                    )
                ) {
                    ForEach(settingsSpec.credentialFields) { credentialField in
                        VStack(alignment: .leading, spacing: 5) {
                            settingsConfigRow(title: officialConfigCredentialTitle(for: credentialField), nested: true) {
                                officialConfigCredentialField(
                                    credentialField,
                                    provider: provider,
                                    sourceMode: sourceBinding.wrappedValue,
                                    webMode: webBinding.wrappedValue,
                                    quotaDisplayMode: quotaDisplayBinding.wrappedValue,
                                    traeValueDisplayMode: settingsSpec.showsTraeValueDisplayMode ? traeValueDisplayBinding.wrappedValue : nil
                                )
                            }

                            if let credentialHint = officialCredentialHint(for: credentialField, provider: provider) {
                                thirdPartyHintText(credentialHint)
                            }
                        }
                    }
                }
            }
            officialDisplayConfigurationRows(
                provider,
                quotaDisplayBinding: quotaDisplayBinding,
                traeValueDisplayBinding: traeValueDisplayBinding
            )
        }
        .onChange(of: sourceBinding.wrappedValue) { _, newValue in
            persistOfficialConfigSettings(
                provider: provider,
                sourceMode: newValue,
                webMode: webBinding.wrappedValue,
                quotaDisplayMode: quotaDisplayBinding.wrappedValue,
                traeValueDisplayMode: settingsSpec.showsTraeValueDisplayMode ? traeValueDisplayBinding.wrappedValue : nil
            )
        }
        .onChange(of: webBinding.wrappedValue) { _, newValue in
            persistOfficialConfigSettings(
                provider: provider,
                sourceMode: sourceBinding.wrappedValue,
                webMode: newValue,
                quotaDisplayMode: quotaDisplayBinding.wrappedValue,
                traeValueDisplayMode: settingsSpec.showsTraeValueDisplayMode ? traeValueDisplayBinding.wrappedValue : nil
            )
        }
        .onChange(of: quotaDisplayBinding.wrappedValue) { _, newValue in
            persistOfficialConfigSettings(
                provider: provider,
                sourceMode: sourceBinding.wrappedValue,
                webMode: webBinding.wrappedValue,
                quotaDisplayMode: newValue,
                traeValueDisplayMode: settingsSpec.showsTraeValueDisplayMode ? traeValueDisplayBinding.wrappedValue : nil
            )
        }
        .onChange(of: traeValueDisplayBinding.wrappedValue) { _, newValue in
            guard settingsSpec.showsTraeValueDisplayMode else { return }
            persistOfficialConfigSettings(
                provider: provider,
                sourceMode: sourceBinding.wrappedValue,
                webMode: webBinding.wrappedValue,
                quotaDisplayMode: quotaDisplayBinding.wrappedValue,
                traeValueDisplayMode: newValue
            )
        }
    }

    @ViewBuilder
    func officialDisplayConfigurationRows(
        _ provider: ProviderDescriptor,
        quotaDisplayBinding: Binding<OfficialQuotaDisplayMode>,
        traeValueDisplayBinding: Binding<OfficialTraeValueDisplayMode>? = nil
    ) -> some View {
        let providerConfiguration = providerConfigurationFacade
        let category = OfficialSettingsCategory.resolve(for: provider) ?? .subscription

        settingsDetailGroupCaption(viewModel.text(.officialDisplayAndAlerts))

        settingsConfigToggleRow(
            title: viewModel.text(.officialMenubar),
            isOn: Binding(
                get: { providerConfiguration.isStatusBarProvider(providerID: provider.id) },
                set: { providerConfiguration.setStatusBarDisplayEnabled($0, providerID: provider.id) }
            )
        )

        if category == .subscription {
            settingsConfigToggleRow(
                title: viewModel.text(.officialShowAccount),
                isOn: Binding(
                    get: { providerConfiguration.showOfficialAccountEmailInMenuBar },
                    set: { providerConfiguration.setShowOfficialAccountEmailInMenuBar($0) }
                )
            )

            settingsConfigToggleRow(
                title: viewModel.text(.officialShowPlan),
                isOn: Binding(
                    get: { providerConfiguration.showOfficialPlanTypeInMenuBar(providerID: provider.id) },
                    set: { providerConfiguration.setShowOfficialPlanTypeInMenuBar($0, providerID: provider.id) }
                )
            )
        }

        if shouldShowExpirationTimeToggle(for: provider) {
            settingsConfigToggleRow(
                title: viewModel.text(.officialResetTime),
                isOn: relayExpirationTimeBinding(provider, providerConfiguration: providerConfiguration)
            )
        }

        officialUsagePreferenceConfigRow(quotaDisplayBinding)

        if let traeValueDisplayBinding, provider.type == .trae {
            settingsConfigRow(title: viewModel.text(.officialDisplay), nested: true) {
                settingsConfigSegmentedControl(
                    options: [
                        SettingsPillSegmentOption(id: OfficialTraeValueDisplayMode.percent.id, title: viewModel.text(.officialDisplayPercent)),
                        SettingsPillSegmentOption(id: OfficialTraeValueDisplayMode.amount.id, title: viewModel.text(.officialDisplayAmount))
                    ],
                    selection: traeValueDisplayBinding.wrappedValue.id,
                    width: 112
                ) { selectedID in
                    if let selected = [OfficialTraeValueDisplayMode.percent, .amount].first(where: { $0.id == selectedID }) {
                        traeValueDisplayBinding.wrappedValue = selected
                    }
                }
            }
        }

        settingsConfigThresholdRow(
            title: officialThresholdTitle,
            value: Binding(
                get: { thresholdValue(for: provider) },
                set: { setOfficialThresholdValue($0, providerID: provider.id) }
            ),
            valueStyle: provider.isRelay || [.zaiBalance, .kimiBalance, .qwenBalance].contains(provider.type) ? .number : officialThresholdValueStyle(
                provider: provider,
                traeValueDisplayMode: traeValueDisplayBinding?.wrappedValue
            ),
            onValueCommit: { newValue in
                providerConfiguration.commitProviderThreshold(newValue, providerID: provider.id)
            },
            onEditingChanged: { editing in
                if !editing {
                    commitOfficialThresholdDraft(provider)
                }
            }
        )
        .onChange(of: provider.threshold.lowRemaining) { _, newValue in
            if focusedThresholdProviderID != provider.id {
                officialEditorDraft.thresholdDraftValues[provider.id] = newValue
                officialEditorDraft.officialThresholdInputs[provider.id] = formattedOfficialThresholdValue(newValue)
            }
        }
        .onChange(of: focusedThresholdProviderID) { oldValue, newValue in
            if oldValue == provider.id, newValue != provider.id {
                applyOfficialThresholdInput(provider)
            }
        }
    }

    func officialUsagePreferenceConfigRow(_ quotaDisplayBinding: Binding<OfficialQuotaDisplayMode>) -> some View {
        settingsConfigRow(title: viewModel.text(.relayUsagePreference)) {
            settingsConfigSegmentedControl(
                options: [
                    SettingsPillSegmentOption(id: OfficialQuotaDisplayMode.remaining.id, title: viewModel.text(.quotaDisplayRemaining)),
                    SettingsPillSegmentOption(id: OfficialQuotaDisplayMode.used.id, title: viewModel.text(.quotaDisplayUsed))
                ],
                selection: quotaDisplayBinding.wrappedValue.id,
                width: 136
            ) { selectedID in
                if let selected = [OfficialQuotaDisplayMode.remaining, .used].first(where: { $0.id == selectedID }) {
                    quotaDisplayBinding.wrappedValue = selected
                }
            }
        }
    }

    func officialConfigVisibleWebModes(_ modes: [OfficialWebMode]) -> [OfficialWebMode] {
        let visibleModes = modes.filter { $0 != .disabled }
        return visibleModes.isEmpty ? modes : visibleModes
    }

    func officialConfigResolvedWebSelection(
        _ current: OfficialWebMode,
        visibleModes: [OfficialWebMode]
    ) -> OfficialWebMode {
        if visibleModes.contains(current) {
            return current
        }
        return visibleModes.first ?? current
    }

    func officialConfigSourceSegmentWidth(_ modes: [OfficialSourceMode]) -> CGFloat {
        switch modes.count {
        case 4:
            return 215
        case 2:
            return 112
        default:
            return CGFloat(max(modes.count, 1)) * 56
        }
    }

    func officialConfigWebSegmentWidth(_ modes: [OfficialWebMode]) -> CGFloat {
        switch modes.count {
        case 2:
            return 112
        default:
            return CGFloat(max(modes.count, 1)) * 56
        }
    }

    func officialConfigSourceModeLabel(_ mode: OfficialSourceMode) -> String {
        switch mode {
        case .auto:
            return viewModel.text(.kimiAuthAuto)
        case .api:
            return "API"
        case .cli:
            return "CLI"
        case .web:
            return "Web"
        }
    }

    func officialConfigWebModeLabel(_ mode: OfficialWebMode) -> String {
        switch mode {
        case .disabled:
            return viewModel.text(.toggleOff)
        case .autoImport:
            return viewModel.text(.kimiAuthAuto)
        case .manual:
            return viewModel.text(.webManual)
        }
    }

    func officialConfigCredentialPlaceholder(
        for field: CredentialFieldSpec,
        provider: ProviderDescriptor
    ) -> String {
        switch field.kind {
        case .opencodeWorkspaceID:
            let hasSavedToken = providerConfigurationFacade.hasToken(for: provider)
            return hasSavedToken
                ? maskedSecretDots(length: providerConfigurationFacade.savedTokenLength(for: provider))
                : viewModel.text(.officialWorkspaceIDPlaceholder)
        case .bearerToken:
            let hasSavedToken = providerConfigurationFacade.hasToken(for: provider)
            return hasSavedToken
                ? maskedSecretDots(length: providerConfigurationFacade.savedTokenLength(for: provider))
                : viewModel.text(.officialAPIKeyPlaceholder)
        case .traeAuthorization:
            let hasSavedToken = providerConfigurationFacade.hasToken(for: provider)
            return hasSavedToken
                ? maskedSecretDots(length: providerConfigurationFacade.savedTokenLength(for: provider))
                : viewModel.text(.officialTraeJWTPlaceholder)
        case .manualCookie:
            let hasSavedManualCookie = providerConfigurationFacade.hasOfficialManualCookie(for: provider)
            return hasSavedManualCookie
                ? maskedSecretDots(length: providerConfigurationFacade.savedOfficialManualCookieLength(for: provider))
                : viewModel.text(.manualCookieHeader)
        case .opencodeManualCookie:
            let hasSavedManualCookie = providerConfigurationFacade.hasOfficialManualCookie(for: provider)
            return hasSavedManualCookie
                ? maskedSecretDots(length: providerConfigurationFacade.savedOfficialManualCookieLength(for: provider))
                : viewModel.text(.officialAuthCookiePlaceholder)
        case .relayBalanceAuth, .relayQuotaAuth:
            let hasSavedToken = providerConfigurationFacade.hasToken(for: provider)
            return hasSavedToken
                ? maskedSecretDots(length: providerConfigurationFacade.savedTokenLength(for: provider))
                : viewModel.text(.officialCredentialPlaceholder)
        }
    }

    func officialConfigCredentialTitle(for field: CredentialFieldSpec) -> String {
        switch field.kind {
        case .opencodeWorkspaceID:
            return "Workspace"
        case .opencodeManualCookie:
            return "Cookie"
        case .bearerToken, .manualCookie, .traeAuthorization, .relayBalanceAuth, .relayQuotaAuth:
            return viewModel.text(.relayCredential)
        }
    }

    func officialCredentialHint(
        for field: CredentialFieldSpec,
        provider: ProviderDescriptor
    ) -> String? {
        switch field.kind {
        case .bearerToken:
            switch provider.type {
            case .zai:
                return viewModel.text(.officialZhipuCodingPlanKeyHint)
            case .zaiBalance:
                return viewModel.text(.officialZhipuAPIKeyHint)
            case .kimi:
                return viewModel.text(.officialKimiCodingKeyHint)
            case .kimiBalance:
                return viewModel.text(.officialMoonshotKeyHint)
            case .openrouterCredits, .openrouterAPI:
                return viewModel.text(.officialOpenRouterKeyHint)
            default:
                return nil
            }
        case .traeAuthorization:
            return viewModel.text(.officialTraeTokenHint)
        case .opencodeWorkspaceID, .opencodeManualCookie, .relayBalanceAuth, .relayQuotaAuth:
            return nil
        case .manualCookie:
            switch provider.type {
            case .qwen, .qwenBalance:
                return viewModel.text(.officialQwenCookieHint)
            default:
                return nil
            }
        }
    }

    @ViewBuilder
    func officialConfigCredentialField(
        _ field: CredentialFieldSpec,
        provider: ProviderDescriptor,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        traeValueDisplayMode: OfficialTraeValueDisplayMode?
    ) -> some View {
        let inputBinding = Binding(
            get: { officialConfigCredentialInput(for: field, providerID: provider.id) },
            set: { officialConfigSetCredentialInput($0, for: field, providerID: provider.id) }
        )
        let submit = {
            saveOfficialConfigCredential(
                for: field,
                provider: provider,
                sourceMode: sourceMode,
                webMode: webMode,
                quotaDisplayMode: quotaDisplayMode,
                traeValueDisplayMode: traeValueDisplayMode
            )
        }

        switch field.kind {
        case .opencodeWorkspaceID:
            settingsConfigTextField(
                officialConfigCredentialPlaceholder(for: field, provider: provider),
                text: inputBinding
            )
            .onSubmit(submit)
        case .bearerToken, .manualCookie, .opencodeManualCookie, .traeAuthorization, .relayBalanceAuth, .relayQuotaAuth:
            // 自动获取槽位由 CredentialFieldSpec.autoImport 能力声明驱动（执行 handler 不变）
            let autoImportSlot = officialAutoImportSlot(
                for: field,
                provider: provider,
                sourceMode: sourceMode,
                webMode: webMode,
                quotaDisplayMode: quotaDisplayMode
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    settingsConfigSecureField(
                        officialConfigCredentialPlaceholder(for: field, provider: provider),
                        text: inputBinding,
                        width: autoImportSlot != nil ? max(280, thirdPartyConfigControlWidth - 120) : nil
                    )
                    .onSubmit(submit)

                    if let autoImportSlot {
                        settingsSmallOutlineButton(autoImportSlot.label, width: 112, action: autoImportSlot.action)
                    }
                }

                if field.autoImport != nil,
                   let importSucceeded = officialEditorDraft.officialCredentialImportResults[provider.id] {
                    Text(
                        importSucceeded
                            ? viewModel.text(.officialClaudeCodeImportSucceeded)
                            : viewModel.text(.officialClaudeCodeImportNotFound)
                    )
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(importSucceeded ? Color(hex: 0x69BD64) : Color(hex: 0xEB654F))
                    .lineLimit(1)
                }
            }
        }
    }

    /// 字段级自动获取槽位：把 CredentialFieldSpec.autoImport 能力声明解析为按钮。
    /// 浏览器 / OAuth / 本地 CLI 导入由账号管理区或 sourceMode 自动行为承载，不在字段上渲染。
    func officialAutoImportSlot(
        for field: CredentialFieldSpec,
        provider: ProviderDescriptor,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode
    ) -> (label: String, action: () -> Void)? {
        guard let capability = field.autoImport else { return nil }
        switch capability {
        case .claudeCodeConfig:
            return (
                viewModel.text(.officialImportFromClaudeCode),
                {
                    importZaiCredentialFromClaudeCode(
                        provider: provider,
                        sourceMode: sourceMode,
                        webMode: webMode,
                        quotaDisplayMode: quotaDisplayMode
                    )
                }
            )
        case .browser, .oauth, .localCLI:
            return nil
        }
    }

    func officialConfigCredentialInput(
        for field: CredentialFieldSpec,
        providerID: String
    ) -> String {
        switch field.kind {
        case .opencodeWorkspaceID:
            return officialEditorDraft.officialWorkspaceInputs[providerID, default: ""]
        case .bearerToken, .manualCookie, .opencodeManualCookie, .traeAuthorization, .relayBalanceAuth, .relayQuotaAuth:
            return officialEditorDraft.officialCookieInputs[providerID, default: ""]
        }
    }

    func officialConfigSetCredentialInput(
        _ value: String,
        for field: CredentialFieldSpec,
        providerID: String
    ) {
        switch field.kind {
        case .opencodeWorkspaceID:
            officialEditorDraft.officialWorkspaceInputs[providerID] = value
        case .bearerToken, .manualCookie, .opencodeManualCookie, .traeAuthorization, .relayBalanceAuth, .relayQuotaAuth:
            officialEditorDraft.officialCookieInputs[providerID] = value
        }
    }

    func saveOfficialConfigCredential(
        for field: CredentialFieldSpec,
        provider: ProviderDescriptor,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        traeValueDisplayMode: OfficialTraeValueDisplayMode?
    ) {
        let raw = officialConfigCredentialInput(for: field, providerID: provider.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            switch field.storageTarget {
            case .providerToken:
                _ = providerConfigurationFacade.saveCredential(raw, field: .providerToken(provider))
            case .officialManualCookie:
                _ = providerConfigurationFacade.saveCredential(raw, field: .officialManualCookie(providerID: provider.id))
            case .auth(let auth):
                _ = providerConfigurationFacade.saveCredential(raw, field: .authToken(auth))
            }
        }
        officialConfigSetCredentialInput("", for: field, providerID: provider.id)
        persistOfficialConfigSettings(
            provider: provider,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode
        )
    }

    /// Z.ai / 智谱余额：一键导入本机 Claude Code 接入配置（或环境变量）里的智谱密钥，
    /// 免去只订阅 Coding Plan 的用户再跑开放平台控制台手动创建。
    func importZaiCredentialFromClaudeCode(
        provider: ProviderDescriptor,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode
    ) {
        guard let key = ZaiProvider.discoverLocalAPIKey() else {
            officialEditorDraft.officialCredentialImportResults[provider.id] = false
            return
        }
        _ = providerConfigurationFacade.saveCredential(key, field: .providerToken(provider))
        officialEditorDraft.officialCredentialImportResults[provider.id] = true
        persistOfficialConfigSettings(
            provider: provider,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: nil
        )
    }

    func persistOfficialConfigSettings(
        provider: ProviderDescriptor,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        traeValueDisplayMode: OfficialTraeValueDisplayMode?
    ) {
        providerConfigurationFacade.updateOfficialProviderSettings(
            providerID: provider.id,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode
        )
    }

    func officialThresholdValueStyle(
        provider: ProviderDescriptor,
        traeValueDisplayMode: OfficialTraeValueDisplayMode?
    ) -> SettingsThresholdValueStyle {
        if provider.type == .trae, traeValueDisplayMode == .amount {
            return .number
        }
        return .percent
    }

    func thirdPartyConfigRow<Content: View>(
        title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: thirdPartyConfigLabelSpacing) {
            Text(title)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)
                .frame(width: thirdPartyConfigLabelWidth, alignment: .trailing)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }

    func thirdPartyHintText(_ text: String) -> some View {
        Text(text)
            .font(settingsHintFont)
            .foregroundStyle(Color.white.opacity(0.40))
            .lineSpacing(1)
            .frame(width: thirdPartyConfigControlWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, thirdPartyConfigLabelWidth + thirdPartyConfigLabelSpacing)
    }

    func officialSegmentControl<Option: Identifiable & Equatable>(
        selection: Binding<Option>,
        options: [Option],
        label: @escaping (Option) -> String
    ) -> some View where Option.ID == String {
        SettingsPillSegmentedControl(
            options: options.map { option in
                SettingsPillSegmentOption(id: option.id, title: label(option))
            },
            selection: selection.wrappedValue.id,
            backgroundColor: Color.white.opacity(0.15),
            selectedFillColor: Color.white.opacity(0.82),
            selectedTextColor: Color.black.opacity(0.88),
            textColor: Color.white.opacity(0.78)
        ) { newValue in
            if let option = options.first(where: { $0.id == newValue }) {
                selection.wrappedValue = option
            }
        }
        .frame(width: 214, height: 24)
    }

    var officialShowEmailTitle: String {
        viewModel.text(.officialShowEmail)
    }

    var officialShowPlanTypeTitle: String {
        viewModel.text(.officialPlanInfo)
    }

    var officialStatusBarTitle: String {
        viewModel.text(.officialMenuBarDisplay)
    }

    var officialDisplayAccountTitle: String {
        viewModel.text(.officialDisplayAccount)
    }

    var officialThresholdTitle: String {
        viewModel.text(.officialBalanceThreshold)
    }

    func maskedSecretDots(length: Int?) -> String {
        let dotCount = max(length ?? 8, 1)
        return String(repeating: "•", count: dotCount)
    }

    func formattedOfficialThresholdValue(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    func thresholdValue(for provider: ProviderDescriptor) -> Double {
        officialEditorDraft.thresholdDraftValues[provider.id] ?? provider.threshold.lowRemaining
    }

    func setOfficialThresholdValue(_ value: Double, providerID: String, persist: Bool = false) {
        let clamped = min(max(value, 0), 100)
        officialEditorDraft.thresholdDraftValues[providerID] = clamped
        if focusedThresholdProviderID != providerID {
            officialEditorDraft.officialThresholdInputs[providerID] = formattedOfficialThresholdValue(clamped)
        }
        if persist {
            providerConfigurationFacade.commitProviderThreshold(clamped, providerID: providerID)
        }
    }

    func commitOfficialThresholdDraft(_ provider: ProviderDescriptor) {
        let value = officialEditorDraft.thresholdDraftValues[provider.id] ?? provider.threshold.lowRemaining
        providerConfigurationFacade.commitProviderThreshold(value, providerID: provider.id)
        officialEditorDraft.thresholdDraftValues[provider.id] = value
    }

    func applyOfficialThresholdInput(_ provider: ProviderDescriptor) {
        let key = provider.id
        let rawInput = officialEditorDraft.officialThresholdInputs[key, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else {
            officialEditorDraft.officialThresholdInputs[key] = formattedOfficialThresholdValue(provider.threshold.lowRemaining)
            return
        }

        let normalizedInput = rawInput.replacingOccurrences(of: ",", with: ".")
        guard let parsedValue = Double(normalizedInput) else {
            officialEditorDraft.officialThresholdInputs[key] = formattedOfficialThresholdValue(provider.threshold.lowRemaining)
            return
        }

        let clamped = min(max(parsedValue, 0), 100)
        officialEditorDraft.thresholdDraftValues[key] = clamped
        providerConfigurationFacade.commitProviderThreshold(clamped, providerID: key)
        officialEditorDraft.officialThresholdInputs[key] = formattedOfficialThresholdValue(clamped)
    }
}
