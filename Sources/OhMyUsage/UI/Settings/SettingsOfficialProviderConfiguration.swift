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

        settingsConfigurationRows {
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

            ForEach(settingsSpec.credentialFields) { credentialField in
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
    func officialConfigSection(_ provider: ProviderDescriptor) -> some View {
        let providerConfiguration = providerConfigurationFacade
        let settingsSpec = ProviderSettingsSpec.resolve(for: provider)
        let supportedSourceModes = settingsSpec.supportedSourceModes
        let supportedWebModes = settingsSpec.supportedWebModes
        let supportsManualInput = settingsSpec.credentialFields.contains { $0.kind == .manualCookie }
        let supportsBearerCredentialInput = settingsSpec.credentialFields.contains { $0.kind == .bearerToken }
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
                return supportedWebModes.contains(current) ? current : (supportedWebModes.first ?? .disabled)
            },
            set: { officialEditorDraft.officialWebModeInputs[provider.id] = $0 }
        )

        VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
            if provider.type == .opencodeGo {
                VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
                    if supportedWebModes.count > 1 {
                        officialConfigRow(title: viewModel.text(.sourceMode)) {
                            officialSegmentControl(
                                selection: sourceBinding,
                                options: supportedSourceModes,
                                label: sourceModeLabel
                            )
                        }

                        officialConfigRow(title: viewModel.text(.webMode)) {
                            officialSegmentControl(
                                selection: webBinding,
                                options: supportedWebModes,
                                label: webModeLabel
                            )
                        }
                    } else {
                        officialConfigRow(title: viewModel.text(.sourceMode)) {
                            officialSegmentControl(
                                selection: sourceBinding,
                                options: supportedSourceModes,
                                label: sourceModeLabel
                            )
                        }
                    }

                    officialConfigHintText(officialSourceHintText(for: provider))
                    officialUsagePreferenceSection(quotaDisplayBinding)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            let hasSavedWorkspaceID = providerConfiguration.hasToken(for: provider)
                            let savedWorkspaceLength = providerConfiguration.savedTokenLength(for: provider)

                            Text("Workspace ID")
                                .font(settingsLabelFont)
                                .foregroundStyle(settingsBodyColor)
                                .frame(width: 82, alignment: .leading)

                            relayProminentTextField(
                                hasSavedWorkspaceID
                                    ? maskedSecretDots(length: savedWorkspaceLength)
                                    : viewModel.localizedText("粘贴 wrk_... (必填)", "Paste wrk_... (Required)"),
                                text: Binding(
                                    get: { officialEditorDraft.officialWorkspaceInputs[provider.id, default: ""] },
                                    set: { officialEditorDraft.officialWorkspaceInputs[provider.id] = $0 }
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                                let raw = officialEditorDraft.officialWorkspaceInputs[provider.id, default: ""]
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !raw.isEmpty {
                                    _ = providerConfiguration.saveToken(raw, for: provider)
                                }
                                providerConfiguration.updateOfficialProviderSettings(
                                    providerID: provider.id,
                                    sourceMode: sourceBinding.wrappedValue,
                                    webMode: webBinding.wrappedValue,
                                    quotaDisplayMode: quotaDisplayBinding.wrappedValue
                                )
                                officialEditorDraft.officialWorkspaceInputs[provider.id] = ""
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 8) {
                            let hasSavedManualCookie = providerConfiguration.hasOfficialManualCookie(for: provider)
                            let savedManualCookieLength = providerConfiguration.savedOfficialManualCookieLength(for: provider)

                            Text("Cookie")
                                .font(settingsLabelFont)
                                .foregroundStyle(settingsBodyColor)
                                .frame(width: 82, alignment: .leading)

                            relayProminentSecureField(
                                hasSavedManualCookie
                                    ? maskedSecretDots(length: savedManualCookieLength)
                                    : viewModel.localizedText("auth=... (可选，自动导入可留空)", "auth=... (Optional when auto import is enabled)"),
                                text: Binding(
                                    get: { officialEditorDraft.officialCookieInputs[provider.id, default: ""] },
                                    set: { officialEditorDraft.officialCookieInputs[provider.id] = $0 }
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                                let raw = officialEditorDraft.officialCookieInputs[provider.id, default: ""]
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !raw.isEmpty {
                                    _ = providerConfiguration.saveOfficialManualCookie(raw, providerID: provider.id)
                                }
                                providerConfiguration.updateOfficialProviderSettings(
                                    providerID: provider.id,
                                    sourceMode: sourceBinding.wrappedValue,
                                    webMode: webBinding.wrappedValue,
                                    quotaDisplayMode: quotaDisplayBinding.wrappedValue
                                )
                                officialEditorDraft.officialCookieInputs[provider.id] = ""
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if provider.type == .trae {
                VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            let hasSavedToken = providerConfiguration.hasToken(for: provider)
                            let savedTokenLength = providerConfiguration.savedTokenLength(for: provider)

                            Text(viewModel.language == .zhHans ? "凭证信息" : "Credential")
                                .font(settingsLabelFont)
                                .foregroundStyle(settingsBodyColor)
                                .lineLimit(1)
                                .frame(width: officialConfigLabelWidth, alignment: .leading)

                            relayProminentSecureField(
                                hasSavedToken
                                    ? maskedSecretDots(length: savedTokenLength)
                                    : viewModel.localizedText("粘贴 Cloud-IDE-JWT / JWT", "Paste Cloud-IDE-JWT / JWT"),
                                text: Binding(
                                    get: { officialEditorDraft.officialCookieInputs[provider.id, default: ""] },
                                    set: { officialEditorDraft.officialCookieInputs[provider.id] = $0 }
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                                let raw = officialEditorDraft.officialCookieInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                if !raw.isEmpty {
                                    _ = providerConfiguration.saveToken(raw, for: provider)
                                }
                                providerConfiguration.updateOfficialProviderSettings(
                                    providerID: provider.id,
                                    sourceMode: .auto,
                                    webMode: .disabled,
                                    quotaDisplayMode: quotaDisplayBinding.wrappedValue,
                                    traeValueDisplayMode: traeValueDisplayBinding.wrappedValue
                                )
                                officialEditorDraft.officialCookieInputs[provider.id] = ""
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        officialConfigHintText(
                            viewModel.localizedText(
                                "获取说明：登录 trae.ai 后打开开发者工具 Network，刷新页面，复制 /trae/api/v1/pay/ide_user_ent_usage 请求头 Authorization（Cloud-IDE-JWT ...）粘贴到上方。",
                                "How to get token: sign in to trae.ai, open DevTools Network, refresh, then copy Authorization from /trae/api/v1/pay/ide_user_ent_usage (Cloud-IDE-JWT ...) and paste above."
                            )
                        )
                    }

                    officialConfigRow(title: viewModel.localizedText("用量显示", "Usage Display")) {
                        officialSegmentControl(
                            selection: traeValueDisplayBinding,
                            options: [.percent, .amount],
                            label: { mode in
                                switch mode {
                                case .percent:
                                    viewModel.localizedText("百分比", "Percent")
                                case .amount:
                                    viewModel.localizedText("数字", "Amount")
                                }
                            }
                        )
                    }

                    officialUsagePreferenceSection(quotaDisplayBinding)
                }
            } else if supportsBearerCredentialInput {
                VStack(alignment: .leading, spacing: modelSettingsItemSpacing) {
                    HStack(spacing: 8) {
                        let hasSavedToken = providerConfiguration.hasToken(for: provider)
                        let savedTokenLength = providerConfiguration.savedTokenLength(for: provider)

                        Text(viewModel.language == .zhHans ? "凭证信息" : "Credential")
                            .font(settingsLabelFont)
                            .foregroundStyle(settingsBodyColor)
                            .lineLimit(1)
                            .frame(width: officialConfigLabelWidth, alignment: .leading)

                        relayProminentSecureField(
                            hasSavedToken
                                ? maskedSecretDots(length: savedTokenLength)
                                : viewModel.localizedText("粘贴 API Key", "Paste API Key"),
                            text: Binding(
                                get: { officialEditorDraft.officialCookieInputs[provider.id, default: ""] },
                                set: { officialEditorDraft.officialCookieInputs[provider.id] = $0 }
                            )
                        )
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                        settingsCapsuleButton(viewModel.text(.save), dismissInputFocus: true) {
                            let raw = officialEditorDraft.officialCookieInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                            if !raw.isEmpty {
                                _ = providerConfiguration.saveToken(raw, for: provider)
                            }
                            providerConfiguration.updateOfficialProviderSettings(
                                providerID: provider.id,
                                sourceMode: sourceBinding.wrappedValue,
                                webMode: webBinding.wrappedValue,
                                quotaDisplayMode: quotaDisplayBinding.wrappedValue
                            )
                            officialEditorDraft.officialCookieInputs[provider.id] = ""
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        officialConfigRow(title: viewModel.text(.sourceMode)) {
                            officialSegmentControl(
                                selection: sourceBinding,
                                options: supportedSourceModes,
                                label: sourceModeLabel
                            )
                        }
                        officialConfigHintText(officialSourceHintText(for: provider))
                    }

                    officialUsagePreferenceSection(quotaDisplayBinding)
                }
            } else {
                if supportedWebModes.count > 1 {
                    officialConfigRow(title: viewModel.text(.sourceMode)) {
                        officialSegmentControl(
                            selection: sourceBinding,
                            options: supportedSourceModes,
                            label: sourceModeLabel
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        officialConfigRow(title: viewModel.text(.webMode)) {
                            officialSegmentControl(
                                selection: webBinding,
                                options: supportedWebModes,
                                label: webModeLabel
                            )
                        }

                        officialConfigHintText(officialSourceHintText(for: provider))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        officialConfigRow(title: viewModel.text(.sourceMode)) {
                            officialSegmentControl(
                                selection: sourceBinding,
                                options: supportedSourceModes,
                                label: sourceModeLabel
                            )
                        }

                        officialConfigHintText(officialSourceHintText(for: provider))
                    }
                }

                officialUsagePreferenceSection(quotaDisplayBinding)

                if supportsManualInput {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            let hasSavedManualCookie = providerConfiguration.hasOfficialManualCookie(for: provider)
                            let savedManualCookieLength = providerConfiguration.savedOfficialManualCookieLength(for: provider)

                            Text("Token")
                                .font(settingsLabelFont)
                                .foregroundStyle(settingsBodyColor)
                                .lineLimit(1)
                                .frame(width: officialConfigLabelWidth, alignment: .leading)

                            relayProminentSecureField(
                                hasSavedManualCookie ? maskedSecretDots(length: savedManualCookieLength) : viewModel.text(.manualCookieHeader),
                                text: Binding(
                                    get: { officialEditorDraft.officialCookieInputs[provider.id, default: ""] },
                                    set: { officialEditorDraft.officialCookieInputs[provider.id] = $0 }
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)

                            settingsCapsuleButton(viewModel.text(.save)) {
                                let raw = officialEditorDraft.officialCookieInputs[provider.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                if !raw.isEmpty {
                                    _ = providerConfiguration.saveOfficialManualCookie(raw, providerID: provider.id)
                                }
                                providerConfiguration.updateOfficialProviderSettings(
                                    providerID: provider.id,
                                    sourceMode: sourceBinding.wrappedValue,
                                    webMode: webBinding.wrappedValue,
                                    quotaDisplayMode: quotaDisplayBinding.wrappedValue
                                )
                                officialEditorDraft.officialCookieInputs[provider.id] = ""
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onChange(of: sourceBinding.wrappedValue) { _, newValue in
            guard provider.type != .trae, !supportsManualInput else { return }
            providerConfiguration.updateOfficialProviderSettings(
                providerID: provider.id,
                sourceMode: newValue,
                webMode: webBinding.wrappedValue,
                quotaDisplayMode: quotaDisplayBinding.wrappedValue
            )
        }
        .onChange(of: webBinding.wrappedValue) { _, newValue in
            guard provider.type != .trae, !supportsManualInput else { return }
            providerConfiguration.updateOfficialProviderSettings(
                providerID: provider.id,
                sourceMode: sourceBinding.wrappedValue,
                webMode: newValue,
                quotaDisplayMode: quotaDisplayBinding.wrappedValue
            )
        }
        .onChange(of: quotaDisplayBinding.wrappedValue) { _, newValue in
            providerConfiguration.updateOfficialProviderSettings(
                providerID: provider.id,
                sourceMode: sourceBinding.wrappedValue,
                webMode: webBinding.wrappedValue,
                quotaDisplayMode: newValue,
                traeValueDisplayMode: provider.type == .trae ? traeValueDisplayBinding.wrappedValue : nil
            )
        }
        .onChange(of: traeValueDisplayBinding.wrappedValue) { _, newValue in
            guard provider.type == .trae else { return }
            providerConfiguration.updateOfficialProviderSettings(
                providerID: provider.id,
                sourceMode: .auto,
                webMode: .disabled,
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

    func officialPrimaryCredentialField(_ fields: [CredentialFieldSpec]) -> CredentialFieldSpec? {
        if let workspaceField = fields.first(where: { $0.kind == .opencodeWorkspaceID }) {
            return workspaceField
        }
        if let bearerField = fields.first(where: { $0.kind == .bearerToken || $0.kind == .traeAuthorization }) {
            return bearerField
        }
        return fields.first
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
        }
    }

    func officialConfigCredentialTitle(for field: CredentialFieldSpec) -> String {
        switch field.kind {
        case .opencodeWorkspaceID:
            return "Workspace"
        case .opencodeManualCookie:
            return "Cookie"
        case .bearerToken, .manualCookie, .traeAuthorization:
            return viewModel.localizedText("凭证", "Credential")
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
        case .bearerToken, .manualCookie, .opencodeManualCookie, .traeAuthorization:
            settingsConfigSecureField(
                officialConfigCredentialPlaceholder(for: field, provider: provider),
                text: inputBinding
            )
            .onSubmit(submit)
        }
    }

    func officialConfigCredentialInput(
        for field: CredentialFieldSpec,
        providerID: String
    ) -> String {
        switch field.kind {
        case .opencodeWorkspaceID:
            return officialEditorDraft.officialWorkspaceInputs[providerID, default: ""]
        case .bearerToken, .manualCookie, .opencodeManualCookie, .traeAuthorization:
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
        case .bearerToken, .manualCookie, .opencodeManualCookie, .traeAuthorization:
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
                _ = providerConfigurationFacade.saveToken(raw, for: provider)
            case .officialManualCookie:
                _ = providerConfigurationFacade.saveOfficialManualCookie(raw, providerID: provider.id)
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

    func officialUsagePreferenceSection(_ quotaDisplayBinding: Binding<OfficialQuotaDisplayMode>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            officialConfigRow(title: viewModel.localizedText("用量偏好", "Usage Preference")) {
                officialSegmentControl(
                    selection: quotaDisplayBinding,
                    options: [.remaining, .used],
                    label: { mode in
                        switch mode {
                        case .remaining:
                            viewModel.text(.quotaDisplayRemaining)
                        case .used:
                            viewModel.text(.quotaDisplayUsed)
                        }
                    }
                )
            }
            officialConfigHintText(viewModel.text(.claudeQuotaDisplayHint))
        }
    }

    func officialConfigRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)
                .frame(width: officialConfigLabelWidth, alignment: .leading)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
    }

    func officialConfigHintText(_ text: String) -> some View {
        Text(text)
            .font(settingsHintFont)
            .foregroundStyle(settingsHintColor)
            .lineSpacing(settingsHintMultilineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, officialConfigLabelWidth + 10)
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
