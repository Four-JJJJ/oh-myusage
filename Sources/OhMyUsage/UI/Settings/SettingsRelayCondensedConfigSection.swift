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
        return RelaySettingsDraftBuilder.build(
            seed: seed,
            inputs: relayEditorDraft,
            name: resolvedRelayNameInput(typedName: relayEditorDraft.providerNameInputs[provider.id] ?? seed.name, manifest: selectedTemplate),
            baseURL: resolvedRelayBaseURLInput(typedBaseURL: relayEditorDraft.baseURLInputs[provider.id] ?? seed.baseURL, manifest: selectedTemplate)
        )
    }

    @ViewBuilder
    func relayCondensedConfigSection(_ provider: ProviderDescriptor) -> some View {
        let providerConfiguration = providerConfigurationFacade
        let officialCategory = OfficialSettingsCategory.resolve(for: provider)
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
            _ = providerConfiguration.saveCredential(token, field: .authToken(accountAuth), restartPolicy: .restartPolling)
            relayEditorDraft.systemTokenInputs[provider.id] = ""
        }

        let saveQuotaCredential: () -> Void = {
            let token = relayEditorDraft.tokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return }
            _ = providerConfiguration.saveCredential(token, field: .providerToken(provider), restartPolicy: .restartPolling)
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
            if officialCategory != nil {
                settingsDetailGroupCaption(viewModel.localizedText("授权与导入", "Authorization & Import"))
            } else {
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
                let hasSavedRelayCredential: Bool = {
                    if showBalanceCredential {
                        return accountAuth.map { providerConfiguration.hasToken(auth: $0) } ?? false
                    }
                    return providerConfiguration.hasToken(for: provider)
                }()
                SettingsCredentialDisclosureBlock(
                    headerTitle: hasSavedRelayCredential
                        ? viewModel.text(.credentialDisclosureReimport)
                        : viewModel.text(.credentialDisclosureManualSetup),
                    isExpanded: Binding(
                        get: { relayEditorDraft.relayCredentialDisclosureExpanded[provider.id] ?? false },
                        set: { relayEditorDraft.relayCredentialDisclosureExpanded[provider.id] = $0 }
                    )
                ) {
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
                                        .focused($focusedRelayCredentialProviderID, equals: provider.id)
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
                                        .focused($focusedRelayCredentialProviderID, equals: provider.id)
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

            if officialCategory == nil {
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

            if officialCategory != nil {
                officialDisplayConfigurationRows(provider, quotaDisplayBinding: quotaDisplayBinding)
            }
        }
        .onAppear { focusPendingRelayCredentialIfNeeded(provider) }
        .onChange(of: navigationState.selectedProviderID) { _, _ in
            focusPendingRelayCredentialIfNeeded(provider)
        }
    }

    /// 保存新站点后若缺凭证，编辑页出现时自动展开凭证折叠区并聚焦输入框补录
    func focusPendingRelayCredentialIfNeeded(_ provider: ProviderDescriptor) {
        guard pendingRelayCredentialFocusProviderID == provider.id else { return }
        pendingRelayCredentialFocusProviderID = nil
        relayEditorDraft.relayCredentialDisclosureExpanded[provider.id] = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            focusedRelayCredentialProviderID = provider.id
        }
    }
}
