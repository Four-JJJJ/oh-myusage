import Foundation
import OhMyUsageDomain
import SwiftUI

extension SettingsView {
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
        let currentPreset = RelayAdapterRegistry.isGenericRelaySiteTemplate(providerAdapterID)
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
        let usesGenericTemplate = RelayAdapterRegistry.isGenericRelaySiteTemplate(
            relayEditorDraft.selectedRelayTemplateInputs[provider.id] ?? providerAdapterID
        )
        let showNameField = true
        let showBaseURLField = usesGenericTemplate || requiresBaseURLInput(for: selectedTemplate, currentBaseURL: currentBaseURL)
        let tokenSaveButtonTitle = viewModel.text(.save)
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
            if selectedTemplate.id == RelayAdapterRegistry.genericNewAPIAdapterID, viewModel.language == .zhHans {
                return viewModel.text(.relayNewAPIAccessTokenPlaceholder)
            }
            if selectedTemplate.id == RelayAdapterRegistry.genericSub2APIAdapterID, viewModel.language == .zhHans {
                return viewModel.text(.relaySub2APIKeyPlaceholder)
            }
            return balanceCredentialTemplate.placeholder
        }()
        let quotaHintLines = relayCredentialHintLines(
            for: provider,
            template: quotaCredentialTemplate,
            setupHint: relaySetupHint(for: selectedTemplate, field: .quotaAuth)
        )
        let balanceHintLines: [String] = {
            if selectedTemplate.id == RelayAdapterRegistry.genericNewAPIAdapterID, viewModel.language == .zhHans {
                return [viewModel.text(.relayNewAPIAccessTokenHint)]
            }
            if selectedTemplate.id == RelayAdapterRegistry.genericSub2APIAdapterID, viewModel.language == .zhHans {
                return [viewModel.text(.relaySub2APIKeyHint)]
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
                            get: {
                                relayEditorDraft.selectedRelayTemplateInputs[provider.id]
                                    ?? providerAdapterID
                            },
                            set: { newID in
                                relayEditorDraft.selectedRelayTemplateInputs[provider.id] = newID
                                if let manifest = relaySiteTemplates.first(where: { $0.id == newID })?.manifest,
                                   !relayTemplateNeedsManualUserID(manifest) {
                                    relayEditorDraft.userIDInputs[provider.id] = ""
                                }
                            }
                        )) {
                            ForEach(relaySiteTemplates) { preset in
                                Text(relayGenericSiteTypeTitle(for: preset.id)).tag(preset.id)
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

            if showBalanceCredential || showTokenCredential {
                // doc 10.3：凭证输入默认折叠，任一通道已有保存凭证时标题为「重新导入凭证」。
                let hasSavedRelayCredential = (showBalanceCredential
                    && (accountAuth.map { providerConfiguration.hasToken(auth: $0) } ?? false))
                    || (showTokenCredential && providerConfiguration.hasToken(for: provider))
                SettingsCredentialDisclosureBlock(
                    headerTitle: SettingsCredentialDisclosurePresenter.headerTitle(
                        hasSavedCredential: hasSavedRelayCredential,
                        language: viewModel.language
                    ),
                    isExpanded: Binding(
                        get: { relayEditorDraft.relayCredentialDisclosureExpanded[provider.id] ?? false },
                        set: { relayEditorDraft.relayCredentialDisclosureExpanded[provider.id] = $0 }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 24) {
                        if showBalanceCredential {
                            let hasSavedBalanceToken = accountAuth.map { providerConfiguration.hasToken(auth: $0) } ?? false
                            let savedBalanceTokenLength = accountAuth.flatMap { providerConfiguration.savedTokenLength(auth: $0) }
                            let balanceTextBinding = Binding(
                                get: { relayEditorDraft.systemTokenInputs[provider.id, default: ""] },
                                set: { relayEditorDraft.systemTokenInputs[provider.id] = $0 }
                            )
                            let resolvedBalancePlaceholder = hasSavedBalanceToken
                                ? maskedSecretDots(length: savedBalanceTokenLength)
                                : balancePlaceholder

                            if RelayAdapterRegistry.isGenericRelaySiteTemplate(selectedTemplate.id), let accountAuth {
                                // Phase 1 试点：通用站点余额凭证行走 spec 驱动的通用 CredentialFieldRow，
                                // 保存仍走同一 facade 入口，行为与原内联实现逐位一致。
                                let spec = CredentialFieldSpec(
                                    kind: .relayBalanceAuth,
                                    storageTarget: .auth(accountAuth),
                                    requiresExplicitSave: true,
                                    copy: CredentialFieldCopy(
                                        title: balanceFieldTitle,
                                        placeholder: resolvedBalancePlaceholder,
                                        hintLines: balanceHintLines
                                    ),
                                    autoImport: supportsBrowserImport ? .browser : nil
                                )
                                credentialFieldRow(
                                    spec: spec,
                                    text: balanceTextBinding,
                                    saveLabel: tokenSaveButtonTitle,
                                    fallbackTitle: balanceFieldTitle,
                                    fallbackPlaceholder: resolvedBalancePlaceholder,
                                    fallbackHintLines: balanceHintLines,
                                    focus: (binding: $focusedRelayCredentialProviderID, value: provider.id)
                                ) { value in
                                    _ = providerConfiguration.saveCredential(value, field: .authToken(accountAuth), restartPolicy: .restartPolling)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    thirdPartyConfigRow(title: balanceFieldTitle) {
                                        HStack(spacing: 8) {
                                            relayProminentSecureField(resolvedBalancePlaceholder, text: balanceTextBinding)
                                                .focused($focusedRelayCredentialProviderID, equals: provider.id)
                                                .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                                            settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                                                guard let accountAuth else { return }
                                                let token = balanceTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                                guard !token.isEmpty else { return }
                                                _ = providerConfiguration.saveCredential(token, field: .authToken(accountAuth), restartPolicy: .restartPolling)
                                                balanceTextBinding.wrappedValue = ""
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
                        }

                        if showTokenCredential {
                            let hasSavedToken = providerConfiguration.hasToken(for: provider)
                            let savedTokenLength = providerConfiguration.savedTokenLength(for: provider)
                            let tokenTextBinding = Binding(
                                get: { relayEditorDraft.tokenInputs[provider.id, default: ""] },
                                set: { relayEditorDraft.tokenInputs[provider.id] = $0 }
                            )
                            let resolvedQuotaPlaceholder = hasSavedToken
                                ? maskedSecretDots(length: savedTokenLength)
                                : quotaPlaceholder

                            VStack(alignment: .leading, spacing: 8) {
                                thirdPartyConfigRow(title: quotaFieldTitle) {
                                    HStack(spacing: 8) {
                                        // 与 condensed 形态一致：每个 provider 同一时间只有一个凭证框
                                        // 持有 focusedRelayCredentialProviderID，余额通道优先。
                                        Group {
                                            if showBalanceCredential {
                                                relayProminentSecureField(resolvedQuotaPlaceholder, text: tokenTextBinding)
                                            } else {
                                                relayProminentSecureField(resolvedQuotaPlaceholder, text: tokenTextBinding)
                                                    .focused($focusedRelayCredentialProviderID, equals: provider.id)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                                        settingsCapsuleButton(tokenSaveButtonTitle, dismissInputFocus: true) {
                                            let token = relayEditorDraft.tokenInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !token.isEmpty else { return }
                                            _ = providerConfiguration.saveCredential(token, field: .providerToken(provider), restartPolicy: .restartPolling)
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
                    settingsCapsuleButton(viewModel.text(.importFromBrowser)) {
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
                Text(viewModel.text(.relayConnectionStatus))
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
                            knobColor: Color.white.opacity(0.88),
                            accessibilityLabel: viewModel.text(.enableTokenChannel)
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
                            knobColor: Color.white.opacity(0.88),
                            accessibilityLabel: viewModel.text(.enableAccountChannel)
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
        .onAppear { focusPendingRelayCredentialIfNeeded(provider) }
        .onChange(of: navigationState.selectedProviderID) { _, _ in
            focusPendingRelayCredentialIfNeeded(provider)
        }
    }
}
