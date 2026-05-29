import Foundation
import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    func currentRelaySettingsDraft(for provider: ProviderDescriptor) -> RelaySettingsDraft {
        let providerAdapterID = provider.relayConfig?.adapterID
            ?? provider.relayManifest?.id
            ?? "generic-newapi"
        let selectedTemplateID = relayEditorDraft.selectedRelayTemplateInputs[provider.id] ?? providerAdapterID
        let selectedTemplate = relaySiteTemplates.first(where: { $0.id == selectedTemplateID })?.manifest
            ?? provider.relayManifest
            ?? RelayAdapterRegistry.shared.manifest(for: provider.baseURL ?? "", preferredID: selectedTemplateID)
        let seed = RelaySettingsDraftSeed(provider: provider, preferredAdapterID: selectedTemplateID, manifest: selectedTemplate)
        return RelaySettingsDraft(
            providerID: provider.id,
            name: resolvedRelayNameInput(
                typedName: relayEditorDraft.providerNameInputs[provider.id] ?? seed.name,
                manifest: selectedTemplate
            ),
            baseURL: resolvedRelayBaseURLInput(
                typedBaseURL: relayEditorDraft.baseURLInputs[provider.id] ?? seed.baseURL,
                manifest: selectedTemplate
            ),
            preferredAdapterID: seed.preferredAdapterID,
            balanceCredentialMode: relayEditorDraft.relayCredentialModeInputs[provider.id] ?? seed.balanceCredentialMode,
            tokenUsageEnabled: relayEditorDraft.tokenUsageEnabledInputs[provider.id] ?? seed.tokenUsageEnabled,
            accountEnabled: relayEditorDraft.accountEnabledInputs[provider.id] ?? seed.accountEnabled,
            authHeader: relayEditorDraft.authHeaderInputs[provider.id] ?? seed.authHeader,
            authScheme: relayEditorDraft.authSchemeInputs[provider.id] ?? seed.authScheme,
            userID: relayEditorDraft.userIDInputs[provider.id] ?? seed.userID,
            userIDHeader: relayEditorDraft.userHeaderInputs[provider.id] ?? seed.userIDHeader,
            endpointPath: relayEditorDraft.endpointPathInputs[provider.id] ?? seed.endpointPath,
            remainingJSONPath: relayEditorDraft.remainingPathInputs[provider.id] ?? seed.remainingJSONPath,
            usedJSONPath: relayEditorDraft.usedPathInputs[provider.id] ?? seed.usedJSONPath,
            limitJSONPath: relayEditorDraft.limitPathInputs[provider.id] ?? seed.limitJSONPath,
            successJSONPath: relayEditorDraft.successPathInputs[provider.id] ?? seed.successJSONPath,
            unit: relayEditorDraft.unitInputs[provider.id] ?? seed.unit,
            quotaDisplayMode: relayEditorDraft.thirdPartyQuotaDisplayModeInputs[provider.id] ?? seed.quotaDisplayMode,
            showExpirationTimeInMenuBar: relayEditorDraft.relayShowExpirationTimeInputs[provider.id]
                ?? seed.showExpirationTimeInMenuBar
        )
    }

    enum RelayCredentialTemplateKind {
        case cookie
        case bearer
        case custom(header: String, scheme: String)
    }

    struct RelayCredentialTemplate {
        let kind: RelayCredentialTemplateKind
        let placeholder: String
        let hint: String
    }

    @ViewBuilder
    func relayCondensedConfigSection(_ provider: ProviderDescriptor) -> some View {
        let providerConfiguration = providerConfigurationFacade
        let relayViewConfig = provider.relayViewConfig
        let accountAuth = relayViewConfig?.accountBalance?.auth
        let providerAdapterID = provider.relayConfig?.adapterID
            ?? provider.relayManifest?.id
            ?? "generic-newapi"
        let selectedTemplateID = relayEditorDraft.selectedRelayTemplateInputs[provider.id] ?? providerAdapterID
        let selectedTemplate = relaySiteTemplates.first(where: { $0.id == selectedTemplateID })?.manifest
            ?? provider.relayManifest
            ?? RelayAdapterRegistry.shared.manifest(for: provider.baseURL ?? "", preferredID: selectedTemplateID)
        let seed = RelaySettingsDraftSeed(provider: provider, preferredAdapterID: selectedTemplateID, manifest: selectedTemplate)
        let accountChannelEnabled = relayEditorDraft.accountEnabledInputs[provider.id]
            ?? seed.accountEnabled
        let showBalanceCredential = accountChannelEnabled
        let defaultUserID = seed.userID
        let showUserIDField = showBalanceCredential && relayTemplateNeedsManualUserID(selectedTemplate)
        let currentBaseURL = relayEditorDraft.baseURLInputs[provider.id] ?? seed.baseURL
        let balanceAuthHeader = relayEditorDraft.authHeaderInputs[provider.id]
            ?? seed.authHeader
        let balanceAuthScheme = relayEditorDraft.authSchemeInputs[provider.id]
            ?? seed.authScheme
        let balanceCredentialTemplate = relayCredentialTemplate(authHeader: balanceAuthHeader, authScheme: balanceAuthScheme)
        let quotaCredentialTemplate = relayCredentialTemplate(authHeader: "Authorization", authScheme: "Bearer")
        let credentialHintLines = showBalanceCredential
            ? relayCredentialHintLines(
                for: provider,
                template: balanceCredentialTemplate,
                setupHint: relaySetupHint(for: selectedTemplate, field: .balanceAuth)
            )
            : relayCredentialHintLines(
                for: provider,
                template: quotaCredentialTemplate,
                setupHint: relaySetupHint(for: selectedTemplate, field: .quotaAuth)
            )
        let credentialModeBinding = Binding<RelayCredentialMode>(
            get: {
                relayEditorDraft.relayCredentialModeInputs[provider.id]
                    ?? seed.balanceCredentialMode
            },
            set: { relayEditorDraft.relayCredentialModeInputs[provider.id] = $0 }
        )
        let quotaDisplayBinding: Binding<OfficialQuotaDisplayMode> = Binding(
            get: {
                relayEditorDraft.thirdPartyQuotaDisplayModeInputs[provider.id]
                    ?? seed.quotaDisplayMode
            },
            set: { newValue in
                relayEditorDraft.thirdPartyQuotaDisplayModeInputs[provider.id] = newValue
                providerConfiguration.updateThirdPartyQuotaDisplayMode(
                    providerID: provider.id,
                    quotaDisplayMode: newValue
                )
            }
        )
        let persistRelaySettings: () -> Void = {
            providerConfiguration.saveRelayDraft(currentRelaySettingsDraft(for: provider))
        }

        let saveBalanceCredential: () -> Void = {
            guard let accountAuth else { return }
            let token = relayEditorDraft.systemTokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return }
            _ = providerConfiguration.saveTokenAndRestart(token, auth: accountAuth)
            relayEditorDraft.systemTokenInputs[provider.id] = ""
        }

        let saveQuotaCredential: () -> Void = {
            let token = relayEditorDraft.tokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return }
            _ = providerConfiguration.saveTokenAndRestart(token, for: provider)
            relayEditorDraft.tokenInputs[provider.id] = ""
        }
        let saveCurrentCredentialIfNeeded: () -> Void = {
            if showBalanceCredential {
                saveBalanceCredential()
            } else {
                saveQuotaCredential()
            }
        }

        let relayTestStatus = relayEditorDraft.relayTestResult[provider.id]
        let supportsBrowserImport = relayTemplateSupportsBrowserImport(selectedTemplate)
        let credentialFieldWidth = max(220, thirdPartyConfigControlWidth - 58)

        settingsConfigurationRows {
            settingsConfigToggleRow(
                title: officialStatusBarTitle,
                isOn: Binding(
                    get: { providerConfiguration.isStatusBarProvider(providerID: provider.id) },
                    set: { providerConfiguration.setStatusBarDisplayEnabled($0, providerID: provider.id) }
                )
            )

            if shouldShowExpirationTimeToggle(for: provider) {
                settingsConfigToggleRow(
                    title: relayExpirationTimeTitle,
                    isOn: relayExpirationTimeBinding(provider, providerConfiguration: providerConfiguration)
                )
            }

            relayCompactConfigRow(title: viewModel.localizedText("用量偏好", "Usage Preference")) {
                relayPillControl(
                    selection: quotaDisplayBinding.wrappedValue.id,
                    options: [
                        (OfficialQuotaDisplayMode.remaining.id, viewModel.text(.quotaDisplayRemaining)),
                        (OfficialQuotaDisplayMode.used.id, viewModel.text(.quotaDisplayUsed))
                    ],
                    width: 136
                ) { selection in
                    if let match = [OfficialQuotaDisplayMode.remaining, .used].first(where: { $0.id == selection }) {
                        quotaDisplayBinding.wrappedValue = match
                    }
                }
            }

            relayCompactConfigRow(title: viewModel.localizedText("站点地址", "Site Address")) {
                settingsConfigTextField(
                    viewModel.localizedText("填写站点访问地址", "Enter site URL"),
                    text: Binding(
                        get: { relayEditorDraft.baseURLInputs[provider.id] ?? currentBaseURL },
                        set: { relayEditorDraft.baseURLInputs[provider.id] = $0 }
                    )
                )
                .onSubmit(persistRelaySettings)
            }

            VStack(alignment: .leading, spacing: 5) {
                relayCompactConfigRow(title: viewModel.localizedText("凭证模式", "Credential Mode")) {
                    relayPillControl(
                        selection: credentialModeBinding.wrappedValue.id,
                        options: relayCredentialModeConfigOptions,
                        width: 252,
                        segmentWidths: relayCredentialModeConfigSegmentWidths
                    ) { selection in
                        if let match = RelayCredentialMode.allCases.first(where: { $0.id == selection }) {
                            credentialModeBinding.wrappedValue = match
                            persistRelaySettings()
                        }
                    }
                }

                thirdPartyHintText(
                    viewModel.localizedText(
                        "浏览器优先会在手动凭证失效时自动读取浏览器登录态；仅浏览器模式只使用浏览器登录态，不使用手动保存的 Cookie 或 Token。",
                        "Browser preferred automatically falls back to browser login when manual credentials fail; Browser only never uses manually saved cookies or tokens."
                    )
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                relayCompactConfigRow(title: viewModel.localizedText("凭证", "Credential")) {
                    HStack(spacing: 8) {
                        Group {
                            if showBalanceCredential {
                                let hasSavedBalanceToken = accountAuth.map { providerConfiguration.hasToken(auth: $0) } ?? false
                                let savedBalanceTokenLength = accountAuth.flatMap { providerConfiguration.savedTokenLength(auth: $0) }
                                settingsConfigSecureField(
                                    hasSavedBalanceToken ? maskedSecretDots(length: savedBalanceTokenLength) : balanceCredentialTemplate.placeholder,
                                    text: Binding(
                                        get: { relayEditorDraft.systemTokenInputs[provider.id, default: ""] },
                                        set: { relayEditorDraft.systemTokenInputs[provider.id] = $0 }
                                    ),
                                    width: credentialFieldWidth
                                )
                                .onSubmit(saveBalanceCredential)
                            } else {
                                let hasSavedToken = providerConfiguration.hasToken(for: provider)
                                let savedTokenLength = providerConfiguration.savedTokenLength(for: provider)
                                settingsConfigSecureField(
                                    hasSavedToken ? maskedSecretDots(length: savedTokenLength) : quotaCredentialTemplate.placeholder,
                                    text: Binding(
                                        get: { relayEditorDraft.tokenInputs[provider.id, default: ""] },
                                        set: { relayEditorDraft.tokenInputs[provider.id] = $0 }
                                    ),
                                    width: credentialFieldWidth
                                )
                                .onSubmit(saveQuotaCredential)
                            }
                        }

                        settingsSmallOutlineButton(viewModel.localizedText("保存", "Save"), width: 46) {
                            saveCurrentCredentialIfNeeded()
                        }
                    }
                }

                ForEach(credentialHintLines, id: \.self) { line in
                    thirdPartyHintText(line)
                }
            }

            if showUserIDField {
                relayCompactConfigRow(title: "User ID") {
                    settingsConfigTextField(
                        viewModel.text(.userID),
                        text: Binding(
                            get: { relayEditorDraft.userIDInputs[provider.id] ?? defaultUserID },
                            set: { relayEditorDraft.userIDInputs[provider.id] = $0 }
                        )
                    )
                    .onSubmit(persistRelaySettings)
                }
            }

            settingsConfigThresholdRow(
                title: officialThresholdTitle,
                value: Binding(
                    get: { thresholdValue(for: provider) },
                    set: { setOfficialThresholdValue($0, providerID: provider.id) }
                ),
                valueStyle: .number,
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

            HStack(spacing: 12) {
                settingsSmallOutlineButton(viewModel.localizedText("测试链接", "Test Connection"), width: 60) {
                    saveCurrentCredentialIfNeeded()
                    let resultGeneration = relayTestResultGeneration
                    let providerID = provider.id
                    Task {
                        let draft = currentRelaySettingsDraft(for: provider)
                        let result = await providerConfiguration.testRelayDraft(draft)
                        guard resultGeneration == relayTestResultGeneration,
                              navigationState.selectedProviderID == providerID else { return }
                        relayEditorDraft.relayTestResult[providerID] = result
                    }
                }

                if supportsBrowserImport {
                    settingsSmallOutlineButton(viewModel.localizedText("从浏览器导入", "Import from Browser"), width: 82) {
                        let resultGeneration = relayTestResultGeneration
                        let providerID = provider.id
                        Task {
                            let draft = currentRelaySettingsDraft(for: provider)
                            let result = await providerConfiguration.importRelayDraftFromBrowser(draft)
                            guard resultGeneration == relayTestResultGeneration,
                                  navigationState.selectedProviderID == providerID else { return }
                            relayEditorDraft.relayTestResult[providerID] = result
                        }
                    }
                }

                if let relayTestStatus {
                    Text(relayCondensedTestStatusText(relayTestStatus))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(relayTestStatus.success ? Color(hex: 0x69BD64) : Color(hex: 0xEB654F))
                }
            }
            .padding(.leading, thirdPartyConfigLabelWidth + thirdPartyConfigLabelSpacing - 3)
        }
    }

    @ViewBuilder
    var relayNewSiteDraftConfigPanel: some View {
        settingsConfigurationSection(title: viewModel.localizedText("配置", "Configuration")) {
            settingsConfigurationRows {
                relayCompactConfigRow(title: viewModel.localizedText("用量偏好", "Usage Preference")) {
                    relayPillControl(
                        selection: OfficialQuotaDisplayMode.remaining.id,
                        options: [
                            (OfficialQuotaDisplayMode.remaining.id, viewModel.text(.quotaDisplayRemaining)),
                            (OfficialQuotaDisplayMode.used.id, viewModel.text(.quotaDisplayUsed))
                        ],
                        width: 136
                    ) { _ in }
                    .allowsHitTesting(false)
                }

                relayCompactConfigRow(title: viewModel.localizedText("站点地址", "Site Address")) {
                    settingsConfigTextField(
                        viewModel.localizedText("填写站点访问地址", "Enter site URL"),
                        text: Binding(
                            get: { newRelaySiteDraft.baseURL },
                            set: {
                                newRelaySiteDraft.baseURL = $0
                                newRelaySiteDraft.testStatusVisible = false
                            }
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    relayCompactConfigRow(title: viewModel.localizedText("凭证模式", "Credential Mode")) {
                        relayPillControl(
                            selection: RelayCredentialMode.browserPreferred.id,
                            options: relayCredentialModeConfigOptions,
                            width: 252,
                            segmentWidths: relayCredentialModeConfigSegmentWidths
                        ) { _ in }
                        .allowsHitTesting(false)
                    }

                    thirdPartyHintText(
                        viewModel.localizedText(
                            "浏览器优先会在手动凭证失效时自动读取浏览器登录态；仅浏览器模式只使用浏览器登录态，不使用手动保存的 Cookie 或 Token。",
                            "Browser preferred automatically falls back to browser login when manual credentials fail; Browser only never uses manually saved cookies or tokens."
                        )
                    )
                }

                relayCompactConfigRow(title: viewModel.localizedText("凭证", "Credential")) {
                    settingsConfigSecureField(
                        viewModel.localizedText("Authorization Bearer或者cookies", "Authorization Bearer or cookies"),
                        text: Binding(
                            get: { newRelaySiteDraft.credentialInput },
                            set: {
                                newRelaySiteDraft.credentialInput = $0
                                newRelaySiteDraft.testStatusVisible = false
                            }
                        )
                    )
                }

                relayCompactConfigRow(title: "User ID") {
                    settingsConfigTextField(
                        viewModel.localizedText("个人设置中的User ID", "User ID from personal settings"),
                        text: Binding(
                            get: { newRelaySiteDraft.userID },
                            set: {
                                newRelaySiteDraft.userID = $0
                                newRelaySiteDraft.testStatusVisible = false
                            }
                        )
                    )
                }

                thirdPartyThresholdRowPlaceholder(valueText: "2,000")

                HStack(spacing: 12) {
                    settingsSmallOutlineButton(viewModel.localizedText("测试链接", "Test Connection"), width: 60) {
                        newRelaySiteDraft.testStatusVisible = true
                    }

                    settingsSmallOutlineButton(viewModel.localizedText("保存站点", "Save Site"), width: 60) {
                        saveNewRelaySiteDraft()
                    }

                    if newRelaySiteDraft.testStatusVisible {
                        Text(viewModel.localizedText("链接成功接口正常", "Connection succeeded and endpoint is healthy"))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color(hex: 0x69BD64))
                    }
                }
                .padding(.leading, thirdPartyConfigLabelWidth + thirdPartyConfigLabelSpacing - 3)
            }
        }
    }

    func thirdPartyThresholdRowPlaceholder(valueText: String) -> some View {
        settingsConfigThresholdStaticRow(
            title: viewModel.localizedText("余额阈值", "Threshold"),
            value: 20,
            displayText: valueText
        )
    }

    func openRelayConfigSection(_ provider: ProviderDescriptor) -> some View {
        let providerConfiguration = providerConfigurationFacade
        let relayViewConfig = provider.relayViewConfig
        let accountAuth = relayViewConfig?.accountBalance?.auth
        let providerAdapterID = provider.relayConfig?.adapterID
            ?? provider.relayManifest?.id
            ?? "generic-newapi"
        let selectedTemplateID = relayEditorDraft.selectedRelayTemplateInputs[provider.id] ?? providerAdapterID
        let selectedTemplate = relaySiteTemplates.first(where: { $0.id == selectedTemplateID })?.manifest
            ?? provider.relayManifest
            ?? RelayAdapterRegistry.shared.manifest(for: provider.baseURL ?? "", preferredID: selectedTemplateID)
        let seed = RelaySettingsDraftSeed(provider: provider, preferredAdapterID: selectedTemplateID, manifest: selectedTemplate)
        let currentPreset = providerAdapterID == "generic-newapi"
            ? nil
            : relayBuiltInPresets.first(where: { $0.id == providerAdapterID })?.manifest
        let tokenChannelEnabled = relayEditorDraft.tokenUsageEnabledInputs[provider.id]
            ?? seed.tokenUsageEnabled
        let accountChannelEnabled = relayEditorDraft.accountEnabledInputs[provider.id]
            ?? seed.accountEnabled
        let showTokenCredential = tokenChannelEnabled
        let showBalanceCredential = accountChannelEnabled
        let defaultUserID = seed.userID
        let showUserIDField = showBalanceCredential && relayTemplateNeedsManualUserID(selectedTemplate)
        let currentBaseURL = relayEditorDraft.baseURLInputs[provider.id] ?? seed.baseURL
        let usesGenericTemplate = (relayEditorDraft.selectedRelayTemplateInputs[provider.id] ?? providerAdapterID) == "generic-newapi"
        let showNameField = true
        let showBaseURLField = usesGenericTemplate || requiresBaseURLInput(for: selectedTemplate, currentBaseURL: currentBaseURL)
        let tokenSaveButtonTitle = viewModel.language == .zhHans ? "保存" : "Save"
        let quotaCredentialTemplate = relayCredentialTemplate(authHeader: "Authorization", authScheme: "Bearer")
        let balanceAuthHeader = relayEditorDraft.authHeaderInputs[provider.id]
            ?? seed.authHeader
        let balanceAuthScheme = relayEditorDraft.authSchemeInputs[provider.id]
            ?? seed.authScheme
        let balanceCredentialTemplate = relayCredentialTemplate(authHeader: balanceAuthHeader, authScheme: balanceAuthScheme)
        let quotaFieldTitle = relayCredentialFieldName(isAccount: false, templateKind: quotaCredentialTemplate.kind)
        let balanceFieldTitle = relayCredentialFieldName(isAccount: true, templateKind: balanceCredentialTemplate.kind)
        let quotaPlaceholder = quotaCredentialTemplate.placeholder
        let balancePlaceholder: String = {
            if selectedTemplate.id == "generic-newapi", viewModel.language == .zhHans {
                return "粘帖Access Token"
            }
            return balanceCredentialTemplate.placeholder
        }()
        let quotaHintLines = relayCredentialHintLines(
            for: provider,
            template: quotaCredentialTemplate,
            setupHint: relaySetupHint(for: selectedTemplate, field: .quotaAuth)
        )
        let balanceHintLines: [String] = {
            if selectedTemplate.id == "generic-newapi", viewModel.language == .zhHans {
                return ["这里填写Access Token通过个人设置-安全设置-系统访问令牌, 生成令牌"]
            }
            return relayCredentialHintLines(
                for: provider,
                template: balanceCredentialTemplate,
                setupHint: relaySetupHint(for: selectedTemplate, field: .balanceAuth)
            )
        }()
        let credentialModeBinding = Binding<RelayCredentialMode>(
            get: {
                relayEditorDraft.relayCredentialModeInputs[provider.id]
                    ?? seed.balanceCredentialMode
            },
            set: { relayEditorDraft.relayCredentialModeInputs[provider.id] = $0 }
        )
        let contentLeading = thirdPartyConfigLabelWidth + thirdPartyConfigLabelSpacing
        let currentRelayDraft: () -> RelaySettingsDraft = {
            RelaySettingsDraft(
                providerID: provider.id,
                name: resolvedRelayNameInput(
                    typedName: relayEditorDraft.providerNameInputs[provider.id] ?? seed.name,
                    manifest: selectedTemplate
                ),
                baseURL: resolvedRelayBaseURLInput(
                    typedBaseURL: relayEditorDraft.baseURLInputs[provider.id] ?? seed.baseURL,
                    manifest: selectedTemplate
                ),
                preferredAdapterID: seed.preferredAdapterID,
                balanceCredentialMode: relayEditorDraft.relayCredentialModeInputs[provider.id] ?? seed.balanceCredentialMode,
                tokenUsageEnabled: relayEditorDraft.tokenUsageEnabledInputs[provider.id] ?? tokenChannelEnabled,
                accountEnabled: relayEditorDraft.accountEnabledInputs[provider.id] ?? accountChannelEnabled,
                authHeader: relayEditorDraft.authHeaderInputs[provider.id] ?? seed.authHeader,
                authScheme: relayEditorDraft.authSchemeInputs[provider.id] ?? seed.authScheme,
                userID: relayEditorDraft.userIDInputs[provider.id] ?? defaultUserID,
                userIDHeader: relayEditorDraft.userHeaderInputs[provider.id] ?? seed.userIDHeader,
                endpointPath: relayEditorDraft.endpointPathInputs[provider.id] ?? seed.endpointPath,
                remainingJSONPath: relayEditorDraft.remainingPathInputs[provider.id] ?? seed.remainingJSONPath,
                usedJSONPath: relayEditorDraft.usedPathInputs[provider.id] ?? seed.usedJSONPath,
                limitJSONPath: relayEditorDraft.limitPathInputs[provider.id] ?? seed.limitJSONPath,
                successJSONPath: relayEditorDraft.successPathInputs[provider.id] ?? seed.successJSONPath,
                unit: relayEditorDraft.unitInputs[provider.id] ?? seed.unit,
                quotaDisplayMode: relayEditorDraft.thirdPartyQuotaDisplayModeInputs[provider.id] ?? seed.quotaDisplayMode,
                showExpirationTimeInMenuBar: relayEditorDraft.relayShowExpirationTimeInputs[provider.id]
                    ?? seed.showExpirationTimeInMenuBar
            )
        }
        let persistRelaySettings: () -> Void = {
            let draft = currentRelayDraft()
            providerConfiguration.saveRelayDraft(draft)
        }
        let supportsBrowserImport = relayTemplateSupportsBrowserImport(selectedTemplate)

        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                if let currentPreset, relayEditorDraft.selectedRelayTemplateInputs[provider.id] == nil, !usesGenericTemplate {
                    thirdPartyConfigRow(title: viewModel.text(.relayTemplate)) {
                        Text(currentPreset.displayName)
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsBodyColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    thirdPartyConfigRow(title: viewModel.text(.relayTemplate)) {
                        Picker("", selection: Binding(
                            get: { relayEditorDraft.selectedRelayTemplateInputs[provider.id] ?? "generic-newapi" },
                            set: { relayEditorDraft.selectedRelayTemplateInputs[provider.id] = $0 }
                        )) {
                            ForEach(relaySiteTemplates) { preset in
                                Text(preset.displayName).tag(preset.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                if !showBaseURLField, let suggestedBaseURL = suggestedBaseURL(for: selectedTemplate) {
                    thirdPartyHintText("Base URL: \(suggestedBaseURL)")
                }
            }

            if showBaseURLField {
                thirdPartyConfigRow(title: "Base URL") {
                    HStack(spacing: 8) {
                        relayProminentTextField(viewModel.text(.baseURL), text: Binding(
                            get: { relayEditorDraft.baseURLInputs[provider.id] ?? (provider.baseURL ?? "") },
                            set: { relayEditorDraft.baseURLInputs[provider.id] = $0 }
                        ))
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                        settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                            persistRelaySettings()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if showNameField {
                thirdPartyConfigRow(title: viewModel.text(.providerName)) {
                    HStack(spacing: 8) {
                        relayProminentTextField(viewModel.text(.providerName), text: Binding(
                            get: { relayEditorDraft.providerNameInputs[provider.id] ?? provider.name },
                            set: { relayEditorDraft.providerNameInputs[provider.id] = $0 }
                        ))
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                        settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                            persistRelaySettings()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if showUserIDField {
                VStack(alignment: .leading, spacing: 8) {
                    thirdPartyConfigRow(title: viewModel.text(.userID)) {
                        HStack(spacing: 8) {
                            relayProminentTextField(viewModel.text(.userID), text: Binding(
                                get: { relayEditorDraft.userIDInputs[provider.id] ?? defaultUserID },
                                set: { relayEditorDraft.userIDInputs[provider.id] = $0 }
                            ))
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                                persistRelaySettings()
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let userIDHint = relaySetupHint(for: selectedTemplate, field: .userID) {
                        thirdPartyHintText(userIDHint)
                    }
                }
            }

            if showBalanceCredential {
                let hasSavedBalanceToken = accountAuth.map { providerConfiguration.hasToken(auth: $0) } ?? false
                let savedBalanceTokenLength = accountAuth.flatMap { providerConfiguration.savedTokenLength(auth: $0) }

                VStack(alignment: .leading, spacing: 8) {
                    thirdPartyConfigRow(title: balanceFieldTitle) {
                        HStack(spacing: 8) {
                            relayProminentSecureField(hasSavedBalanceToken ? maskedSecretDots(length: savedBalanceTokenLength) : balancePlaceholder, text: Binding(
                                get: { relayEditorDraft.systemTokenInputs[provider.id, default: ""] },
                                set: { relayEditorDraft.systemTokenInputs[provider.id] = $0 }
                            ))
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                                guard let accountAuth else { return }
                                let token = relayEditorDraft.systemTokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !token.isEmpty else { return }
                                _ = providerConfiguration.saveTokenAndRestart(token, auth: accountAuth)
                                relayEditorDraft.systemTokenInputs[provider.id] = ""
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(balanceHintLines, id: \.self) { line in
                        thirdPartyHintText(line)
                    }
                }
            }

            if showTokenCredential {
                let hasSavedToken = providerConfiguration.hasToken(for: provider)
                let savedTokenLength = providerConfiguration.savedTokenLength(for: provider)

                VStack(alignment: .leading, spacing: 8) {
                    thirdPartyConfigRow(title: quotaFieldTitle) {
                        HStack(spacing: 8) {
                            relayProminentSecureField(hasSavedToken ? maskedSecretDots(length: savedTokenLength) : quotaPlaceholder, text: Binding(
                                get: { relayEditorDraft.tokenInputs[provider.id, default: ""] },
                                set: { relayEditorDraft.tokenInputs[provider.id] = $0 }
                            ))
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                                let token = relayEditorDraft.tokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !token.isEmpty else { return }
                                _ = providerConfiguration.saveTokenAndRestart(token, for: provider)
                                relayEditorDraft.tokenInputs[provider.id] = ""
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(quotaHintLines, id: \.self) { line in
                        thirdPartyHintText(line)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                thirdPartyConfigRow(title: viewModel.text(.credentialMode)) {
                    officialSegmentControl(
                        selection: credentialModeBinding,
                        options: RelayCredentialMode.allCases,
                        label: relayCredentialModeLabel
                    )
                }

                thirdPartyHintText(viewModel.text(.credentialModeHint))
            }

            HStack(spacing: 8) {
                settingsCapsuleButton(viewModel.text(.saveConfig), dismissInputFocus: true) {
                    persistRelaySettings()
                }

                settingsCapsuleButton(viewModel.text(.testConnection)) {
                    let resultGeneration = relayTestResultGeneration
                    let providerID = provider.id
                    Task {
                        let result = await providerConfiguration.testRelayDraft(currentRelayDraft())
                        guard resultGeneration == relayTestResultGeneration,
                              navigationState.selectedProviderID == providerID else { return }
                        relayEditorDraft.relayTestResult[providerID] = result
                    }
                }

                if supportsBrowserImport {
                    settingsCapsuleButton(viewModel.localizedText("从浏览器导入", "Import from Browser")) {
                        let resultGeneration = relayTestResultGeneration
                        let providerID = provider.id
                        Task {
                            let result = await providerConfiguration.importRelayDraftFromBrowser(currentRelayDraft())
                            guard resultGeneration == relayTestResultGeneration,
                                  navigationState.selectedProviderID == providerID else { return }
                            relayEditorDraft.relayTestResult[providerID] = result
                        }
                    }
                }

                if provider.family == .thirdParty && provider.id != "open-ailinyu" {
                    settingsCapsuleButton(viewModel.text(.removeProvider), destructive: true) {
                        providerConfiguration.removeProvider(providerID: provider.id)
                    }
                }
            }
            .padding(.leading, contentLeading)

            if let relayTestResult = relayEditorDraft.relayTestResult[provider.id] {
                relayDiagnosticSection(provider, relayTestResult)
                    .padding(.leading, contentLeading)
            }

            dividerLine

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.language == .zhHans ? "连接状态" : "Connection status")
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)

                relayRuntimeStatusSection(provider, selectedTemplate: selectedTemplate)
            }

            dividerLine

            let advancedExpandedBinding = Binding(
                get: { relayEditorDraft.relayAdvancedExpanded[provider.id] ?? false },
                set: { relayEditorDraft.relayAdvancedExpanded[provider.id] = $0 }
            )

            Button {
                advancedExpandedBinding.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(viewModel.text(.advancedSettings))
                        .font(settingsLabelFont)
                        .foregroundStyle(settingsBodyColor)
                    Spacer(minLength: 0)
                    Image(systemName: advancedExpandedBinding.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if advancedExpandedBinding.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    Text(relayRequiredInputSummary(
                        manifest: selectedTemplate,
                        tokenChannelEnabled: showTokenCredential,
                        accountChannelEnabled: showBalanceCredential,
                        showsManualUserID: showUserIDField
                    ))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)

                    Text(relayFixedTemplateSummary(for: selectedTemplate))
                        .font(settingsHintFont)
                        .foregroundStyle(settingsHintColor)

                    if let diagnosticHint = relayDiagnosticHint(for: selectedTemplate) {
                        Text(diagnosticHint)
                            .font(settingsHintFont)
                            .foregroundStyle(settingsHintColor)
                    }

                    let tokenChannelBinding = Binding(
                        get: { relayEditorDraft.tokenUsageEnabledInputs[provider.id] ?? tokenChannelEnabled },
                        set: { relayEditorDraft.tokenUsageEnabledInputs[provider.id] = $0 }
                    )
                    HStack(spacing: 10) {
                        Text(viewModel.text(.enableTokenChannel))
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsBodyColor)
                            .frame(width: thirdPartyConfigLabelWidth, alignment: .leading)
                        SettingsToggleSwitch(
                            isOn: tokenChannelBinding,
                            offTrackColor: Color.white.opacity(0.15),
                            onTrackColor: Color.white.opacity(0.40),
                            knobColor: Color.white.opacity(0.88)
                        )
                        .allowsHitTesting(false)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tokenChannelBinding.wrappedValue.toggle()
                    }

                    let accountChannelBinding = Binding(
                        get: { relayEditorDraft.accountEnabledInputs[provider.id] ?? accountChannelEnabled },
                        set: { relayEditorDraft.accountEnabledInputs[provider.id] = $0 }
                    )
                    HStack(spacing: 10) {
                        Text(viewModel.text(.enableAccountChannel))
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsBodyColor)
                            .frame(width: thirdPartyConfigLabelWidth, alignment: .leading)
                        SettingsToggleSwitch(
                            isOn: accountChannelBinding,
                            offTrackColor: Color.white.opacity(0.15),
                            onTrackColor: Color.white.opacity(0.40),
                            knobColor: Color.white.opacity(0.88)
                        )
                        .allowsHitTesting(false)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        accountChannelBinding.wrappedValue.toggle()
                    }

                    HStack(spacing: 8) {
                        relayCompactTextField(viewModel.text(.authHeader), text: Binding(
                            get: {
                                relayEditorDraft.authHeaderInputs[provider.id]
                                    ?? seed.authHeader
                            },
                            set: { relayEditorDraft.authHeaderInputs[provider.id] = $0 }
                        ))

                        relayCompactTextField(viewModel.text(.authScheme), text: Binding(
                            get: {
                                relayEditorDraft.authSchemeInputs[provider.id]
                                    ?? seed.authScheme
                            },
                            set: { relayEditorDraft.authSchemeInputs[provider.id] = $0 }
                        ))
                    }

                    HStack(spacing: 8) {
                        relayCompactTextField(viewModel.text(.userIDHeader), text: Binding(
                            get: {
                                relayEditorDraft.userHeaderInputs[provider.id]
                                    ?? seed.userIDHeader
                            },
                            set: { relayEditorDraft.userHeaderInputs[provider.id] = $0 }
                        ))

                        relayCompactTextField(viewModel.text(.endpointPath), text: Binding(
                            get: {
                                relayEditorDraft.endpointPathInputs[provider.id]
                                    ?? seed.endpointPath
                            },
                            set: { relayEditorDraft.endpointPathInputs[provider.id] = $0 }
                        ))
                    }

                    HStack(spacing: 8) {
                        relayCompactTextField(viewModel.text(.unit), text: Binding(
                            get: {
                                relayEditorDraft.unitInputs[provider.id]
                                    ?? seed.unit
                            },
                            set: { relayEditorDraft.unitInputs[provider.id] = $0 }
                        ))

                        relayCompactTextField(viewModel.text(.remainingPath), text: Binding(
                            get: {
                                relayEditorDraft.remainingPathInputs[provider.id]
                                    ?? seed.remainingJSONPath
                            },
                            set: { relayEditorDraft.remainingPathInputs[provider.id] = $0 }
                        ))
                    }

                    HStack(spacing: 8) {
                        relayCompactTextField(viewModel.text(.usedPath), text: Binding(
                            get: {
                                relayEditorDraft.usedPathInputs[provider.id]
                                    ?? seed.usedJSONPath
                            },
                            set: { relayEditorDraft.usedPathInputs[provider.id] = $0 }
                        ))

                        relayCompactTextField(viewModel.text(.limitPath), text: Binding(
                            get: {
                                relayEditorDraft.limitPathInputs[provider.id]
                                    ?? seed.limitJSONPath
                            },
                            set: { relayEditorDraft.limitPathInputs[provider.id] = $0 }
                        ))
                    }

                    relayCompactTextField(viewModel.text(.successPath), text: Binding(
                        get: {
                            relayEditorDraft.successPathInputs[provider.id]
                                ?? seed.successJSONPath
                        },
                        set: { relayEditorDraft.successPathInputs[provider.id] = $0 }
                    ))
                }
                .padding(.top, 8)
                .padding(.leading, contentLeading)
            }
        }
        .padding(.bottom, 8)
    }

    func relayCredentialTemplate(authHeader: String?, authScheme: String?) -> RelayCredentialTemplate {
        let language = viewModel.language
        let header = (authHeader ?? "Authorization").trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = (authScheme ?? "Bearer").trimmingCharacters(in: .whitespacesAndNewlines)

        if header.caseInsensitiveCompare("Cookie") == .orderedSame {
            if language == .zhHans {
                return RelayCredentialTemplate(
                    kind: .cookie,
                    placeholder: "粘贴完整 Cookie Header，例如 session=...; token=...",
                    hint: "这里填写完整 Cookie Header，不是单个字段。"
                )
            } else {
                return RelayCredentialTemplate(
                    kind: .cookie,
                    placeholder: "Paste the full Cookie header, for example session=...; token=...",
                    hint: "Paste the full Cookie header, not a single cookie field."
                )
            }
        }

        if header.caseInsensitiveCompare("Authorization") == .orderedSame &&
            (scheme.isEmpty || scheme.caseInsensitiveCompare("Bearer") == .orderedSame) {
            if language == .zhHans {
                return RelayCredentialTemplate(
                    kind: .bearer,
                    placeholder: "粘贴 Bearer Token，例如 Bearer eyJ... 或 eyJ...",
                    hint: "这里填写 Authorization Bearer 值，带或不带 Bearer 前缀都可以。"
                )
            } else {
                return RelayCredentialTemplate(
                    kind: .bearer,
                    placeholder: "Paste the bearer token, for example Bearer eyJ... or eyJ...",
                    hint: "Paste the Authorization bearer value, with or without the Bearer prefix."
                )
            }
        }

        let normalizedHeader = header.isEmpty ? "Authorization" : header
        let normalizedScheme = scheme
        if language == .zhHans {
            return RelayCredentialTemplate(
                kind: .custom(header: normalizedHeader, scheme: normalizedScheme),
                placeholder: "粘贴 \(normalizedHeader) 的值：\(normalizedScheme.isEmpty ? "<value>" : "\(normalizedScheme) <value>")",
                hint: "这里填写站点要求的自定义请求头值。"
            )
        } else {
            return RelayCredentialTemplate(
                kind: .custom(header: normalizedHeader, scheme: normalizedScheme),
                placeholder: "Paste the \(normalizedHeader) value: \(normalizedScheme.isEmpty ? "<value>" : "\(normalizedScheme) <value>")",
                hint: "Paste the custom header value required by this site."
            )
        }
    }

    func relayCredentialFieldName(
        isAccount _: Bool,
        templateKind: RelayCredentialTemplateKind
    ) -> String {
        let language = viewModel.language
        switch templateKind {
        case .cookie:
            return language == .zhHans ? "凭证信息" : "Credential"
        case .bearer:
            return language == .zhHans ? "凭证信息" : "Credential"
        case .custom(let header, _):
            if language == .zhHans {
                return "\(header) 值"
            } else {
                return "\(header) value"
            }
        }
    }

    func relayCredentialSectionTitle(
        isAccount: Bool,
        templateKind: RelayCredentialTemplateKind
    ) -> String {
        let fieldName = relayCredentialFieldName(isAccount: isAccount, templateKind: templateKind)
        if viewModel.language == .zhHans {
            return isAccount ? "余额 \(fieldName)" : "配额 \(fieldName)"
        } else {
            return isAccount ? "Balance \(fieldName)" : "Quota \(fieldName)"
        }
    }

    func relayCredentialSaveLabel(templateKind: RelayCredentialTemplateKind) -> String {
        switch templateKind {
        case .cookie:
            return viewModel.language == .zhHans ? "保存 Cookie" : "Save Cookie"
        case .bearer:
            return viewModel.language == .zhHans ? "保存 Access Token" : "Save Access Token"
        case .custom(let header, _):
            return viewModel.language == .zhHans ? "保存 \(header)" : "Save \(header)"
        }
    }

    func relayCredentialLookupHint(templateKind: RelayCredentialTemplateKind) -> String {
        switch templateKind {
        case .cookie:
            return viewModel.language == .zhHans
                ? "可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制完整 Cookie。"
                : "Open the matching request in browser DevTools Network and copy the full Cookie value from Request Headers."
        case .bearer:
            return viewModel.language == .zhHans
                ? "可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制 Authorization 的 Bearer 值。"
                : "Open the matching request in browser DevTools Network and copy the Authorization bearer value from Request Headers."
        case .custom(let header, _):
            return viewModel.language == .zhHans
                ? "可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制 \(header) 的值。"
                : "Open the matching request in browser DevTools Network and copy the \(header) value from Request Headers."
        }
    }

    func relayCredentialHintLines(
        for provider: ProviderDescriptor,
        template: RelayCredentialTemplate,
        setupHint: String?
    ) -> [String] {
        let lookupHint = relayCredentialLookupHint(templateKind: template.kind)
        let rawLines = [template.hint, setupHint, lookupHint].compactMap { $0 }

        var output: [String] = []
        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !shouldStripThirdPartyAccessTokenHint(line, for: provider) else { continue }
            if !output.contains(line) {
                output.append(line)
            }
        }
        return output
    }

    func shouldStripThirdPartyAccessTokenHint(_ line: String, for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .thirdParty else {
            return false
        }

        let normalized = line.lowercased()
        if line.contains("后台") || line.contains("访问令牌") {
            return true
        }
        if normalized.contains("access token generated") {
            return true
        }
        if normalized.contains("generated by"), normalized.contains("token") {
            return true
        }
        if normalized.contains("dashboard"), normalized.contains("token") {
            return true
        }
        return false
    }

    func relayCredentialModeLabel(_ mode: RelayCredentialMode) -> String {
        switch mode {
        case .manualPreferred:
            return viewModel.text(.credentialModeManualPreferred)
        case .browserPreferred:
            return viewModel.text(.credentialModeBrowserPreferred)
        case .browserOnly:
            return viewModel.text(.credentialModeBrowserOnly)
        }
    }

    var relayCredentialModeConfigOptions: [(String, String)] {
        [
            (RelayCredentialMode.browserPreferred.id, relayCredentialModeLabel(.browserPreferred)),
            (RelayCredentialMode.manualPreferred.id, relayCredentialModeLabel(.manualPreferred)),
            (RelayCredentialMode.browserOnly.id, relayCredentialModeLabel(.browserOnly))
        ]
    }

    var relayCredentialModeConfigSegmentWidths: [String: CGFloat] {
        [
            RelayCredentialMode.browserPreferred.id: 92,
            RelayCredentialMode.manualPreferred.id: 80,
            RelayCredentialMode.browserOnly.id: 80
        ]
    }

    func relayTemplateSupportsBrowserImport(_ manifest: RelayAdapterManifest) -> Bool {
        manifest.authStrategies.contains(where: { strategy in
            switch strategy.kind {
            case .browserBearer, .browserCookieHeader, .namedCookie:
                return true
            default:
                return false
            }
        })
    }

    func relayCompactConfigRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsConfigRow(title: title) {
            content()
        }
    }

    func relayPillControl(
        selection: String,
        options: [(String, String)],
        width: CGFloat,
        segmentWidths: [String: CGFloat]? = nil,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        settingsConfigSegmentedControl(
            options: options.map { SettingsPillSegmentOption(id: $0.0, title: $0.1) },
            selection: selection,
            width: width,
            segmentWidths: segmentWidths
        ) { newValue in
            onSelect(newValue)
        }
    }

    func relayReadOnlyField(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.80))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .frame(width: thirdPartyConfigControlWidth, height: 24, alignment: .leading)
            .background(
                SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.15))
            )
    }

    func relayDisplaySiteAddress(_ baseURL: String) -> String {
        guard let components = URLComponents(string: baseURL),
              let scheme = components.scheme,
              let host = components.host else {
            return baseURL
        }
        var output = "\(scheme)://\(host)"
        if let port = components.port {
            output += ":\(port)"
        }
        return output
    }

    func relayCondensedTestStatusText(_ result: RelayDiagnosticResult) -> String {
        if result.success {
            return viewModel.localizedText("链接成功接口正常", "Connection succeeded and endpoint is healthy")
        }
        return result.message
    }
}
