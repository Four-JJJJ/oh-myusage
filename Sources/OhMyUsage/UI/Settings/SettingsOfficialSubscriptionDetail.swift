import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    func officialSubscriptionDetailPage(_ provider: ProviderDescriptor) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let error = viewModel.errors[provider.id]
        let category = OfficialSettingsCategory.resolve(for: provider) ?? .subscription

        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                officialSubscriptionHeader(provider)
                Text(category.detail(language: viewModel.language))
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            providerDetailStatusSection(provider, snapshot: snapshot, error: error)
            if category == .subscription {
                officialSubscriptionAccountsSection(provider: provider, snapshot: snapshot, error: error)
                if shouldShowOfficialLocalTrendCard(for: provider) {
                    officialSubscriptionUsageSection(provider: provider, snapshot: snapshot)
                }
            } else {
                officialAPIUsageSection(snapshot: snapshot)
            }
            providerDetailProvenanceSection(provider, snapshot: snapshot)
            officialSubscriptionConfigSection(provider)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func officialAPIUsageSection(snapshot: UsageSnapshot?) -> some View {
        officialSubscriptionPanel(title: viewModel.text(.officialBalanceAndUsage)) {
            officialSubscriptionSectionCard(padding: 16, cornerRadius: SettingsVisualTokens.Radius.control) {
                VStack(alignment: .leading, spacing: 16) {
                    if let account = snapshot?.accountLabel, !account.isEmpty {
                        Text(account)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SettingsVisualTokens.Text.primary)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        officialAPIAmount(title: viewModel.text(.officialBalanceRemaining), value: snapshot?.remaining, unit: snapshot?.unit)
                        officialAPIAmount(title: viewModel.text(.used), value: snapshot?.used, unit: snapshot?.unit)
                        officialAPIAmount(title: viewModel.text(.officialTotalLimit), value: snapshot?.limit, unit: snapshot?.unit)
                    }
                    if snapshot == nil {
                        Text(viewModel.text(.officialCredentialsEmptyHint))
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                    }
                }
            }
        }
    }

    func officialAPIAmount(title: String, value: Double?, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(SettingsVisualTokens.Text.tertiary)
            Text(OfficialAPIUsagePresenter.amount(value, unit: unit))
                .font(AppFonts.numeric(size: 14, fallbackWeight: .bold))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func officialSubscriptionHeader(_ provider: ProviderDescriptor) -> some View {
        HStack(alignment: .center, spacing: 8) {
            providerIcon(for: provider, size: SettingsVisualTokens.Sidebar.headerIconSize)
                .frame(
                    width: SettingsVisualTokens.Sidebar.headerIconSize,
                    height: SettingsVisualTokens.Sidebar.headerIconSize
                )
                .opacity(0.8)

            Text(sidebarDisplayName(for: provider))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(settingsTitleColor)

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                Button {
                    Task { await viewModel.refreshSelectedProvider(provider.id) }
                } label: {
                    settingsCompactToolbarIcon(named: "refresh_icon", fallback: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(viewModel.text(.refreshThisProvider))
                .accessibilityLabel(viewModel.text(.refreshThisProvider))

                SettingsToggleSwitch(
                    isOn: Binding(
                        get: { provider.enabled },
                        set: { viewModel.setEnabled($0, providerID: provider.id) }
                    ),
                    offTrackColor: SettingsVisualTokens.Fill.control,
                    onTrackColor: SettingsVisualTokens.Text.tertiary,
                    knobColor: SettingsVisualTokens.Text.primary,
                    accessibilityLabel: Localizer.format(.enableProviderAccessibility, language: viewModel.language, sidebarDisplayName(for: provider))
                )
            }
        }
        .frame(
            width: SettingsVisualTokens.SettingsLayout.configurationWidth,
            height: SettingsVisualTokens.SettingsLayout.rowHeight,
            alignment: .leading
        )
    }

    @ViewBuilder
    func settingsCompactToolbarIcon(named name: String, fallback: String) -> some View {
        if let image = bundledImage(named: name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .opacity(0.8)
        } else {
            Image(systemName: fallback)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .frame(width: 16, height: 16)
        }
    }

    func officialSubscriptionPanel<Content: View>(
        title: String,
        spacing: CGFloat = 12,
        @ViewBuilder controls: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, height: 12, alignment: .leading)

            controls()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func officialSubscriptionUsageSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        let hasNoAccounts = officialSubscriptionHasNoAccounts(provider)
        let shouldShowEmptyState = hasNoAccounts
            || !officialUsageSectionHasData(provider: provider, snapshot: snapshot)

        officialSubscriptionPanel(title: viewModel.text(.usageSection), spacing: 12) {
            if shouldShowEmptyState {
                officialSubscriptionSectionCard(
                    padding: 0,
                    cornerRadius: SettingsVisualTokens.Radius.control,
                    strokeOpacity: 0.15
                ) {
                    officialSubscriptionCenteredPlaceholder(
                        viewModel.text(.noUsageData),
                        minHeight: 80,
                        textColor: settingsMutedHintColor
                    )
                }
                .onAppear {
                    if !hasNoAccounts {
                        refreshOfficialUsageSectionIfNeeded(provider: provider, snapshot: snapshot)
                    }
                }
            } else {
                officialSubscriptionSectionCard(
                    padding: 0,
                    cornerRadius: SettingsVisualTokens.Radius.control,
                    strokeOpacity: 0.15
                ) {
                    officialLocalTrendSection(
                        provider: provider,
                        snapshot: snapshot,
                        showsDivider: false,
                        showsTitle: false,
                        usesSubscriptionUsageLayout: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    func officialSubscriptionAccountsSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(viewModel.text(.officialAccountsAndQuotas))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)

                Spacer(minLength: 0)

                if provider.type == .codex || provider.type == .claude {
                    HStack(spacing: 8) {
                        officialSubscriptionAddAccountButton(
                            viewModel.text(.officialAddJSON),
                            width: 60
                        ) {
                            if provider.type == .codex {
                                openCodexProfileEditor(slotID: viewModel.nextCodexProfileSlotID(), existingProfile: nil)
                            } else {
                                openClaudeProfileEditor(slotID: viewModel.nextClaudeProfileSlotID(), existingProfile: nil)
                            }
                        }
                        officialSubscriptionAddAccountButton(
                            viewModel.text(.officialAddOAuth),
                            width: 69
                        ) {
                            if provider.type == .codex {
                                viewModel.startOAuthImport(providerType: .codex, slotID: viewModel.nextCodexProfileSlotID())
                            } else {
                                viewModel.startOAuthImport(providerType: .claude, slotID: viewModel.nextClaudeProfileSlotID())
                            }
                        }
                    }
                }
            }
            .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, height: 22, alignment: .center)

            officialSubscriptionSectionCard(
                padding: 0,
                cornerRadius: SettingsVisualTokens.Radius.control,
                strokeOpacity: 0.15
            ) {
                if officialSubscriptionHasNoAccounts(provider) {
                    officialSubscriptionCenteredPlaceholder(
                        viewModel.text(.officialAccountsEmptyState),
                        minHeight: 80,
                        textColor: settingsMutedHintColor
                    )
                } else {
                    officialSubscriptionAccountsList(provider: provider, snapshot: snapshot, error: error)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func officialSubscriptionAddAccountButton(
        _ title: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minWidth: width)
                .frame(height: 22)
                .background(Color.clear)
                .overlay(
                    SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.compact)
                        .stroke(SettingsVisualTokens.Text.primary, lineWidth: SettingsVisualTokens.Stroke.hairline)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func officialSubscriptionConfigSection(_ provider: ProviderDescriptor) -> some View {
        settingsConfigurationSection(title: viewModel.text(.configurationSection)) {
            switch SettingsProviderConfigurationSectionPresenter.sectionKind(for: provider) {
            case .official:
                officialProviderConfigurationContent(provider)
            case .relay:
                relayCondensedConfigSection(provider)
            }
        }
    }

    func officialSubscriptionSectionCard<Content: View>(
        padding: CGFloat = 24,
        cornerRadius: CGFloat = 12,
        strokeOpacity: Double = 0.12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(padding)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.clear)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(strokeOpacity), lineWidth: SettingsVisualTokens.Stroke.hairline)
        )
    }

    func officialSubscriptionCenteredPlaceholder(
        _ text: String,
        minHeight: CGFloat,
        textColor: Color? = nil
    ) -> some View {
        VStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(textColor ?? settingsHintColor)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
    }

    @ViewBuilder
    func officialSubscriptionAccountsList(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        switch provider.type {
        case .codex:
            codexProfileManagementSection()
        case .claude:
            claudeProfileManagementSection()
        default:
            officialSingleAccountRow(
                provider: provider,
                snapshot: snapshot,
                error: error
            )
        }
    }

    func officialSubscriptionHasNoAccounts(_ provider: ProviderDescriptor) -> Bool {
        switch provider.type {
        case .codex:
            return viewModel.codexProfilesForSettings().isEmpty
        case .claude:
            return viewModel.claudeProfilesForSettings().isEmpty
        default:
            return false
        }
    }
}
