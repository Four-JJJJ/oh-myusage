import OhMyUsageDomain
import SwiftUI

/// doc 10.3：凭证折叠区的标题文案。已有凭证 → 重新导入；没有 → 手动配置。
enum SettingsCredentialDisclosurePresenter {
    static func headerTitle(hasSavedCredential: Bool, language: AppLanguage) -> String {
        Localizer.text(
            hasSavedCredential ? .credentialDisclosureReimport : .credentialDisclosureManualSetup,
            language: language
        )
    }
}

/// doc 10.3 第 4 层：更新时间、来源和可信度。任何估算/缓存值都不会显示成“官方确认”——
/// 可信度段与菜单栏共用 MenuDataCredibilityPresenter 的五态文案
/// （官方实时 / 本地缓存 / 本地估算 / 待刷新 / 刷新失败，显示旧数据）。
enum SettingsProviderProvenancePresenter {
    static func provenanceLine(
        updatedAt: Date?,
        sourceLabel: String?,
        snapshot: UsageSnapshot?,
        now: Date,
        language: AppLanguage
    ) -> String? {
        guard let updatedAt else { return nil }
        let updatedText = "\(Localizer.text(.updatedAgo, language: language)) \(SettingsOverviewPresenter.elapsedText(from: updatedAt, now: now, language: language))"
        var segments = [updatedText]

        let trimmedSource = sourceLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSource.isEmpty {
            switch language {
            case .zhHans:
                segments.append("来源：\(trimmedSource)")
            case .en:
                segments.append("Source: \(trimmedSource)")
            }
        }

        if let snapshot {
            let credibility = MenuDataCredibilityPresenter.credibility(snapshot: snapshot)
            segments.append(MenuDataCredibilityPresenter.label(credibility, language: language))
        }

        let separator = language == .zhHans ? "｜" : " | "
        return segments.joined(separator: separator)
    }
}

extension SettingsView {
    @ViewBuilder
    func providerSettingsCard(_ provider: ProviderDescriptor) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let error = viewModel.errors[provider.id]

        if provider.isRelay {
            thirdPartyProviderSettingsCard(provider, snapshot: snapshot, error: error)
        } else if provider.family == .official {
            officialProviderSettingsCard(provider, snapshot: snapshot, error: error)
        } else {
            thirdPartyProviderSettingsCard(provider, snapshot: snapshot, error: error)
        }
    }

    func providerSettingsHeader(_ provider: ProviderDescriptor) -> some View {
        SettingsProviderHeaderView(
            title: sidebarDisplayName(for: provider),
            titleColor: settingsTitleColor,
            dividerColor: dividerColor,
            isEnabled: Binding(
                get: { provider.enabled },
                set: { viewModel.setEnabled($0, providerID: provider.id) }
            )
        )
    }

    func thirdPartyProviderSettingsCard(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        ThirdPartyProviderDetailCardView(itemSpacing: modelSettingsItemSpacing) {
            providerSettingsHeader(provider)
        } mainSettings: {
            thirdPartyThresholdRow(provider)

            providerNameToggleRow(title: officialStatusBarTitle, isOn: Binding(
                get: { viewModel.isStatusBarProvider(providerID: provider.id) },
                set: { newValue in
                    viewModel.setStatusBarDisplayEnabled(newValue, providerID: provider.id)
                }
            ))

            if provider.isRelay {
                thirdPartyUsagePreferenceRow(provider)
                if shouldShowExpirationTimeToggle(for: provider) {
                    relayExpirationTimeToggleRow(provider)
                }
                openRelayConfigSection(provider)
            }
        }
    }

    func thirdPartyThresholdRow(_ provider: ProviderDescriptor) -> some View {
        SettingsThresholdControlRowView(
            title: officialThresholdTitle,
            labelFont: settingsLabelFont,
            bodyColor: settingsBodyColor,
            sliderTintColor: settingsSliderTintColor,
            labelWidth: thirdPartyConfigLabelWidth,
            spacing: thirdPartyConfigLabelSpacing,
            sliderValue: Binding(
                get: { thresholdValue(for: provider) },
                set: { newValue in
                    setOfficialThresholdValue(newValue, providerID: provider.id)
                }
            ),
            stepperValue: Binding(
                get: { thresholdValue(for: provider) },
                set: { setOfficialThresholdValue($0, providerID: provider.id, persist: true) }
            ),
            displayText: formattedOfficialThresholdValue(thresholdValue(for: provider)),
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

    func thirdPartyUsagePreferenceRow(_ provider: ProviderDescriptor) -> some View {
        let quotaDisplayBinding: Binding<OfficialQuotaDisplayMode> = Binding(
            get: {
                relayEditorDraft.thirdPartyQuotaDisplayModeInputs[provider.id]
                    ?? provider.relayConfig?.quotaDisplayMode
                    ?? .remaining
            },
            set: { newValue in
                relayEditorDraft.thirdPartyQuotaDisplayModeInputs[provider.id] = newValue
                viewModel.updateThirdPartyQuotaDisplayMode(
                    providerID: provider.id,
                    quotaDisplayMode: newValue
                )
            }
        )
        return VStack(alignment: .leading, spacing: 8) {
            thirdPartyConfigRow(title: viewModel.localizedText("用量偏好", "Usage Preference")) {
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
            thirdPartyHintText(viewModel.text(.claudeQuotaDisplayHint))
        }
    }

    func relayExpirationTimeToggleRow(_ provider: ProviderDescriptor) -> some View {
        SettingsToggleRowView(
            title: relayExpirationTimeTitle,
            labelFont: settingsLabelFont,
            bodyColor: settingsBodyColor,
            labelWidth: thirdPartyConfigLabelWidth,
            spacing: thirdPartyConfigLabelSpacing,
            isOn: relayExpirationTimeBinding(provider)
        )
    }

    func relayExpirationTimeBinding(
        _ provider: ProviderDescriptor,
        providerConfiguration: SettingsProviderConfigurationFacade? = nil
    ) -> Binding<Bool> {
        let providerConfiguration = providerConfiguration ?? providerConfigurationFacade
        return Binding(
            get: {
                relayEditorDraft.relayShowExpirationTimeInputs[provider.id]
                    ?? providerConfiguration.showExpirationTimeInMenuBar(providerID: provider.id)
            },
            set: { newValue in
                relayEditorDraft.relayShowExpirationTimeInputs[provider.id] = newValue
                providerConfiguration.setShowExpirationTimeInMenuBar(newValue, providerID: provider.id)
            }
        )
    }

    func shouldShowExpirationTimeToggle(for provider: ProviderDescriptor) -> Bool {
        provider.supportsExpirationTimeDisplay(snapshot: viewModel.snapshots[provider.id])
    }

    var relayExpirationTimeTitle: String {
        viewModel.localizedText("显示到期时间", "Show Expiration")
    }

    func providerNameToggleRow(
        title: String,
        isOn: Binding<Bool>,
        labelWidth: CGFloat? = nil,
        spacing: CGFloat = 12
    ) -> some View {
        SettingsToggleRowView(
            title: title,
            labelFont: settingsLabelFont,
            bodyColor: settingsBodyColor,
            labelWidth: labelWidth ?? officialConfigLabelWidth,
            spacing: spacing,
            isOn: isOn
        )
    }

    @ViewBuilder
    func claudeStatusBarDisplayRow() -> some View {
        let profiles = viewModel.claudeProfilesForSettings()
        if !profiles.isEmpty {
            let options = profiles.map { profile in
                ClaudeStatusBarDisplayRowView.Option(
                    id: profile.slotID.rawValue,
                    title: claudeStatusBarDisplayOptionTitle(profile)
                )
            }
            let currentMenubarTitle: String? = {
                guard let slotID = viewModel.claudeStatusBarResolvedDisplaySlotID(),
                      let profile = profiles.first(where: { $0.slotID == slotID }) else {
                    return nil
                }
                let title = claudeStatusBarDisplayOptionTitle(profile)
                return viewModel.localizedText(
                    "当前菜单栏展示：\(title)",
                    "Current menubar account: \(title)"
                )
            }()
            ClaudeStatusBarDisplayRowView(
                labelTitle: officialDisplayAccountTitle,
                autoTitle: viewModel.localizedText("自动", "Auto"),
                currentMenubarTitle: currentMenubarTitle,
                options: options,
                labelFont: settingsLabelFont,
                bodyColor: settingsBodyColor,
                hintColor: settingsHintColor,
                labelWidth: officialConfigLabelWidth,
                selection: Binding(
                    get: { viewModel.claudeStatusBarDisplaySlotID?.rawValue ?? "auto" },
                    set: { newValue in
                        viewModel.setClaudeStatusBarDisplaySlotID(
                            newValue == "auto" ? nil : CodexSlotID(rawValue: newValue)
                        )
                    }
                )
            )
        }
    }

    func claudeStatusBarDisplayOptionTitle(_ profile: ClaudeAccountProfile) -> String {
        let fallback = viewModel.localizedText("未识别账号", "Account unavailable")
        let subtitle = claudeProfileIdentitySubtitle(profile: profile, fallback: fallback)
        if subtitle == fallback {
            return profile.displayName
        }
        return "\(profile.displayName) · \(subtitle)"
    }

    func officialProviderSettingsCard(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        OfficialProviderDetailCardView(itemSpacing: modelSettingsItemSpacing) {
            providerSettingsHeader(provider)
        } mainSettings: {
            officialProviderConfigurationContent(provider)
        } supplemental: {
            if provider.type == .codex {
                dividerLine
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                Text(viewModel.language == .zhHans ? "本机Codex账号" : viewModel.text(.codexProfiles))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)

                officialSubscriptionSectionCard(
                    padding: 0,
                    cornerRadius: 8,
                    strokeOpacity: 0.15
                ) {
                    if officialSubscriptionHasNoAccounts(provider) {
                        officialSubscriptionCenteredPlaceholder(
                            viewModel.localizedText("快来添加你的第一个账号吧～", "Add your first account to get started"),
                            minHeight: 80,
                            textColor: settingsMutedHintColor
                        )
                    } else {
                        codexProfileManagementSection()
                    }
                }
                .padding(.top, 12)
            } else if provider.type == .claude {
                dividerLine
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                Text(viewModel.localizedText("本机 Claude 账号", "Local Claude Accounts"))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)

                officialSubscriptionSectionCard(
                    padding: 0,
                    cornerRadius: 8,
                    strokeOpacity: 0.15
                ) {
                    if officialSubscriptionHasNoAccounts(provider) {
                        officialSubscriptionCenteredPlaceholder(
                            viewModel.localizedText("快来添加你的第一个账号吧～", "Add your first account to get started"),
                            minHeight: 80,
                            textColor: settingsMutedHintColor
                        )
                    } else {
                        claudeProfileManagementSection()
                    }
                }
                .padding(.top, 12)
            } else if snapshot != nil || error != nil {
                dividerLine
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                Text(localOfficialAccountSectionTitle(for: provider))
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsBodyColor)

                officialSingleAccountCardsSection(
                    provider: provider,
                    snapshot: snapshot,
                    error: error
                )
                .padding(.top, 12)
            }
        }
    }

    @ViewBuilder
    func officialProviderConfigurationContent(_ provider: ProviderDescriptor) -> some View {
        officialConfigurationRows(provider)
    }

    func officialThresholdRow(_ provider: ProviderDescriptor) -> some View {
        SettingsThresholdControlRowView(
            title: officialThresholdTitle,
            labelFont: settingsLabelFont,
            bodyColor: settingsBodyColor,
            sliderTintColor: settingsSliderTintColor,
            labelWidth: 60,
            spacing: 12,
            sliderValue: Binding(
                get: { thresholdValue(for: provider) },
                set: { newValue in
                    setOfficialThresholdValue(newValue, providerID: provider.id)
                }
            ),
            stepperValue: Binding(
                get: { thresholdValue(for: provider) },
                set: { setOfficialThresholdValue($0, providerID: provider.id, persist: true) }
            ),
            displayText: formattedOfficialThresholdValue(thresholdValue(for: provider)),
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

    func localOfficialAccountSectionTitle(for provider: ProviderDescriptor) -> String {
        let displayName = sidebarDisplayName(for: provider)
        if viewModel.language == .zhHans {
            return "本机\(displayName)账号"
        }
        return "Local \(displayName) Account"
    }

    @ViewBuilder
    func officialSingleAccountCardsSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        officialSubscriptionSectionCard(
            padding: 0,
            cornerRadius: 8,
            strokeOpacity: 0.15
        ) {
            officialSingleAccountRow(provider: provider, snapshot: snapshot, error: error)
        }
    }

    func officialSingleAccountRow(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        let metrics = codexQuotaMetrics(provider: provider, snapshot: snapshot)
        let title = officialSingleAccountTitle(provider: provider, snapshot: snapshot)
        let visibleError = officialSingleAccountError(snapshot: snapshot, error: error)
        let status = officialSingleAccountStatus(
            provider: provider,
            snapshot: snapshot,
            visibleError: visibleError
        )

        return officialSubscriptionReadOnlyAccountRow(
            title: title,
            isCurrent: provider.enabled,
            planType: officialMonitorPlanType(providerType: provider.type, snapshot: snapshot),
            statusText: provider.enabled ? status.text : "",
            statusColor: provider.enabled ? status.color : .clear,
            metrics: metrics,
            errorText: visibleError
        )
    }

    func officialSingleAccountTitle(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> String {
        if let subtitle = officialMonitorSubtitle(snapshot: snapshot), !subtitle.isEmpty {
            return subtitle
        }

        return sidebarDisplayName(for: provider)
    }

    func officialSingleAccountStatus(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        visibleError: String?
    ) -> (text: String, color: Color) {
        if visibleError != nil {
            return (viewModel.language == .zhHans ? "认证故障" : "Auth Error", Color(hex: 0xD05858))
        }
        return officialSubscriptionAccountStatus(provider: provider, snapshot: snapshot)
    }

    func officialSingleAccountError(snapshot: UsageSnapshot?, error: String?) -> String? {
        if let error = officialSubscriptionAccountVisibleError(error) {
            return error
        }
        guard snapshot?.valueFreshness == .empty else { return nil }
        return officialSubscriptionAccountVisibleError(snapshot?.note)
    }

    // MARK: - doc 10.3 详情区信息层级

    /// 第 1 层：Provider 状态。正常状态保持低视觉噪音，只有异常才使用突出颜色。
    @ViewBuilder
    func providerDetailStatusSection(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        let status = providerDetailStatusPresentation(
            provider: provider,
            snapshot: snapshot,
            error: error
        )
        settingsConfigurationSection(title: viewModel.localizedText("状态", "Status")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                    Text(status.text)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(SettingsVisualTokens.Text.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if provider.enabled,
                   let visibleError = officialSubscriptionAccountVisibleError(error),
                   !visibleError.isEmpty {
                    Text(visibleError)
                        .font(settingsHintFont)
                        .foregroundStyle(Color(hex: 0xD05757))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    func providerDetailStatusPresentation(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> (text: String, color: Color) {
        guard provider.enabled else {
            return (viewModel.localizedText("已停用", "Disabled"), settingsMutedHintColor)
        }
        if provider.isRelay {
            return relayProviderSummaryStatus(
                snapshot: snapshot,
                hasError: officialSubscriptionAccountVisibleError(error) != nil
            )
        }
        if officialSubscriptionAccountVisibleError(error) != nil {
            return (viewModel.localizedText("认证故障", "Auth Error"), Color(hex: 0xD05858))
        }
        guard snapshot != nil else {
            return (viewModel.localizedText("待刷新", "Pending refresh"), settingsMutedHintColor)
        }
        return officialSingleAccountStatus(provider: provider, snapshot: snapshot, visibleError: nil)
    }

    /// 第 4 层：更新时间、来源和可信度。以低噪音提示行呈现。
    @ViewBuilder
    func providerDetailProvenanceSection(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        if let snapshot {
            let line = SettingsProviderProvenancePresenter.provenanceLine(
                updatedAt: snapshot.updatedAt,
                sourceLabel: providerDetailSourceLabel(provider: provider, snapshot: snapshot),
                snapshot: snapshot,
                now: runtimeState.settingsNow,
                language: viewModel.language
            )
            if let line, !line.isEmpty {
                Text(line)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                    .accessibilityLabel(line)
            }
        }
    }

    func providerDetailSourceLabel(provider: ProviderDescriptor, snapshot: UsageSnapshot) -> String? {
        let trimmed = snapshot.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return viewModel.relayAuthSource(for: provider.id)
    }

    /// 详情配置区的小节标题（doc 10.3 第 5/6/7 层分组）。
    func settingsDetailGroupCaption(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SettingsVisualTokens.Text.tertiary)
            .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
            .padding(.top, 4)
    }
}
