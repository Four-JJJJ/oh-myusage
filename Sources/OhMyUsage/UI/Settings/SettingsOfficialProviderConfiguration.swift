import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    @ViewBuilder
    func officialConfigurationRows(_ provider: ProviderDescriptor) -> some View {
        let providerConfiguration = providerConfigurationFacade
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

        // doc 10.3：详情配置区固定信息顺序——
        // 5. 授权或重新导入操作 → 6. 套餐字段 → 7. Cookie、API 覆盖规则和调试信息（凭证输入默认折叠）。
        let hasSavedOfficialCredential = providerConfigurationFacade.hasToken(for: provider)
            || providerConfigurationFacade.hasOfficialManualCookie(for: provider)

        settingsConfigurationRows {
            settingsDetailGroupCaption(viewModel.localizedText("授权与导入", "Authorization & Import"))

            if !supportedSourceModes.isEmpty {
                settingsConfigRow(title: viewModel.localizedText("来源", "Source"), nested: true) {
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
                settingsConfigRow(title: viewModel.localizedText("网页", "Web"), nested: true) {
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

            settingsDetailGroupCaption(viewModel.localizedText("套餐与显示", "Plan & Display"))

            settingsConfigToggleRow(
                title: officialStatusBarTitle,
                isOn: Binding(
                    get: { providerConfiguration.isStatusBarProvider(providerID: provider.id) },
                    set: { providerConfiguration.setStatusBarDisplayEnabled($0, providerID: provider.id) }
                )
            )

            settingsConfigToggleRow(
                title: officialShowEmailTitle,
                isOn: Binding(
                    get: { providerConfiguration.showOfficialAccountEmailInMenuBar },
                    set: { providerConfiguration.setShowOfficialAccountEmailInMenuBar($0) }
                )
            )

            settingsConfigToggleRow(
                title: officialShowPlanTypeTitle,
                isOn: Binding(
                    get: { providerConfiguration.showOfficialPlanTypeInMenuBar(providerID: provider.id) },
                    set: { providerConfiguration.setShowOfficialPlanTypeInMenuBar($0, providerID: provider.id) }
                )
            )

            if shouldShowExpirationTimeToggle(for: provider) {
                settingsConfigToggleRow(
                    title: relayExpirationTimeTitle,
                    isOn: relayExpirationTimeBinding(provider, providerConfiguration: providerConfiguration)
                )
            }

            officialUsagePreferenceConfigRow(quotaDisplayBinding)

            if settingsSpec.showsTraeValueDisplayMode {
                settingsConfigRow(title: viewModel.localizedText("显示", "Display"), nested: true) {
                    settingsConfigSegmentedControl(
                        options: [
                            SettingsPillSegmentOption(id: OfficialTraeValueDisplayMode.percent.id, title: viewModel.localizedText("百分比", "Percent")),
                            SettingsPillSegmentOption(id: OfficialTraeValueDisplayMode.amount.id, title: viewModel.localizedText("数字", "Amount"))
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
                valueStyle: officialThresholdValueStyle(
                    provider: provider,
                    traeValueDisplayMode: settingsSpec.showsTraeValueDisplayMode ? traeValueDisplayBinding.wrappedValue : nil
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

            if !settingsSpec.credentialFields.isEmpty {
                settingsDetailGroupCaption(viewModel.localizedText("凭证与调试信息", "Credentials & Debug"))

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

    func officialUsagePreferenceConfigRow(_ quotaDisplayBinding: Binding<OfficialQuotaDisplayMode>) -> some View {
        settingsConfigRow(title: viewModel.localizedText("用量偏好", "Usage Preference")) {
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
            return viewModel.localizedText("自动", "Auto")
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
            return viewModel.localizedText("关闭", "Off")
        case .autoImport:
            return viewModel.localizedText("自动", "Auto")
        case .manual:
            return viewModel.localizedText("手动", "Manual")
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
                : viewModel.localizedText("粘贴 wrk_... (必填)", "Paste wrk_... (Required)")
        case .bearerToken:
            let hasSavedToken = providerConfigurationFacade.hasToken(for: provider)
            return hasSavedToken
                ? maskedSecretDots(length: providerConfigurationFacade.savedTokenLength(for: provider))
                : viewModel.localizedText("粘贴 API Key", "Paste API Key")
        case .traeAuthorization:
            let hasSavedToken = providerConfigurationFacade.hasToken(for: provider)
            return hasSavedToken
                ? maskedSecretDots(length: providerConfigurationFacade.savedTokenLength(for: provider))
                : viewModel.localizedText("粘贴 Cloud-IDE-JWT / JWT", "Paste Cloud-IDE-JWT / JWT")
        case .manualCookie:
            let hasSavedManualCookie = providerConfigurationFacade.hasOfficialManualCookie(for: provider)
            return hasSavedManualCookie
                ? maskedSecretDots(length: providerConfigurationFacade.savedOfficialManualCookieLength(for: provider))
                : viewModel.text(.manualCookieHeader)
        case .opencodeManualCookie:
            let hasSavedManualCookie = providerConfigurationFacade.hasOfficialManualCookie(for: provider)
            return hasSavedManualCookie
                ? maskedSecretDots(length: providerConfigurationFacade.savedOfficialManualCookieLength(for: provider))
                : viewModel.localizedText("auth=... (可选，自动导入可留空)", "auth=... (Optional when auto import is enabled)")
        case .relayBalanceAuth, .relayQuotaAuth:
            let hasSavedToken = providerConfigurationFacade.hasToken(for: provider)
            return hasSavedToken
                ? maskedSecretDots(length: providerConfigurationFacade.savedTokenLength(for: provider))
                : viewModel.localizedText("粘贴凭证", "Paste credential")
        }
    }

    func officialConfigCredentialTitle(for field: CredentialFieldSpec) -> String {
        switch field.kind {
        case .opencodeWorkspaceID:
            return "Workspace"
        case .opencodeManualCookie:
            return "Cookie"
        case .bearerToken, .manualCookie, .traeAuthorization, .relayBalanceAuth, .relayQuotaAuth:
            return viewModel.localizedText("凭证", "Credential")
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
                return viewModel.localizedText(
                    "获取说明：已用 Claude Code 接入 GLM Coding Plan 时，自动模式会直接读取本地配置，也可点右侧「从 Claude Code 导入」一键填入；否则在智谱开放平台（z.ai 或 open.bigmodel.cn）「API Keys」页面创建密钥后粘贴到上方。与「Z.ai (API)」共用同一把密钥，填一次即可。",
                    "How to get key: if you already use GLM Coding Plan via Claude Code, Auto mode reads the local config, or click \"Import from Claude Code\" to fill it in one click; otherwise create a key on the Zhipu platform (z.ai or open.bigmodel.cn) API Keys page and paste it above. The same key is shared with the Z.ai (API) card."
                )
            case .zaiBalance:
                return viewModel.localizedText(
                    "获取说明：点右侧「从 Claude Code 导入」可一键读取本机接入配置里的密钥；或登录智谱开放平台（open.bigmodel.cn 或国际站 z.ai），在「API Keys」页面创建密钥后粘贴到上方。与 Coding Plan 共用同一把密钥，填一次即可。",
                    "How to get key: click \"Import from Claude Code\" to read the key from your local setup in one click; or sign in to the Zhipu platform (open.bigmodel.cn or z.ai), create a key on the API Keys page and paste it above. The same key is shared with the Coding Plan card."
                )
            case .kimi:
                return viewModel.localizedText(
                    "获取说明：登录 kimi.com 的 Kimi for Coding 控制台（kimi.com/code），创建 API Key（即接入 Claude Code 时用的那把）后粘贴到上方，长期有效；本机已登录 Kimi CLI 时自动模式会直接读取登录态，无需填写。与「Kimi (API)」的 Moonshot 开放平台密钥不通用。",
                    "How to get key: sign in to the Kimi for Coding console at kimi.com/code, create an API key (the same one used for Claude Code) and paste it above; it stays valid long-term. If Kimi CLI is signed in on this machine, Auto mode reads it directly. Not interchangeable with the Moonshot platform key used by Kimi (API)."
                )
            case .kimiBalance:
                return viewModel.localizedText(
                    "获取说明：登录 Moonshot 开放平台（platform.moonshot.cn），在「API Key 管理」页面创建密钥，复制后粘贴到上方。",
                    "How to get key: sign in to the Moonshot platform (platform.moonshot.cn), create a key on the API Keys page, then paste it above."
                )
            case .openrouterCredits, .openrouterAPI:
                return viewModel.localizedText(
                    "获取说明：登录 OpenRouter（openrouter.ai），在 Settings → Keys 页面创建密钥，复制后粘贴到上方。",
                    "How to get key: sign in to OpenRouter (openrouter.ai), create a key under Settings → Keys, then paste it above."
                )
            default:
                return nil
            }
        case .traeAuthorization:
            return viewModel.localizedText(
                "获取说明：登录 trae.ai 后打开开发者工具 Network，刷新页面，复制 /trae/api/v1/pay/ide_user_ent_usage 请求头 Authorization（Cloud-IDE-JWT ...）粘贴到上方。",
                "How to get token: sign in to trae.ai, open DevTools Network, refresh, then copy Authorization from /trae/api/v1/pay/ide_user_ent_usage (Cloud-IDE-JWT ...) and paste above."
            )
        case .opencodeWorkspaceID, .opencodeManualCookie, .relayBalanceAuth, .relayQuotaAuth:
            return nil
        case .manualCookie:
            switch provider.type {
            case .qwen, .qwenBalance:
                return viewModel.localizedText(
                    "获取说明：浏览器登录千问AI平台（platform.qianwenai.com）后，手动刷新会自动导入登录 Cookie；也可打开开发者工具 Network，刷新页面，复制任意 platform.qianwenai.com 请求的 Cookie 请求头粘贴到上方。「Qwen」与「Qwen (API)」共用同一份 Cookie，填一次即可。",
                    "How to get cookie: sign in to platform.qianwenai.com in your browser — a manual refresh imports the session cookie automatically; or open DevTools Network, refresh the page, and paste the Cookie header of any platform.qianwenai.com request above. The same cookie is shared between the Qwen and Qwen (API) cards."
                )
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
                            ? viewModel.localizedText("已从本机 Claude Code 配置导入密钥。", "Imported the key from the local Claude Code config.")
                            : viewModel.localizedText("未在 Claude Code 配置或环境变量中找到智谱密钥。", "No Zhipu key found in Claude Code config or environment variables.")
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
                viewModel.localizedText("从 Claude Code 导入", "Import from Claude Code"),
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
        viewModel.language == .zhHans ? "显示邮箱" : "Show Email"
    }

    var officialShowPlanTypeTitle: String {
        viewModel.language == .zhHans ? "套餐信息" : "Plan Info"
    }

    var officialStatusBarTitle: String {
        viewModel.language == .zhHans ? "菜单栏显示" : "Menu Bar"
    }

    var officialDisplayAccountTitle: String {
        viewModel.localizedText("展示账号", "Display Account")
    }

    var officialThresholdTitle: String {
        viewModel.language == .zhHans ? "余额阈值" : "Threshold"
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
