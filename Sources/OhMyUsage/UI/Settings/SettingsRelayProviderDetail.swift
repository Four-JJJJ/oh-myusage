import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    func relayProviderDetailPage(_ provider: ProviderDescriptor) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        // doc 10.3 信息顺序：状态 → 当前账号（站点）→ 额度/余额 → 更新时间/来源/可信度 → 配置。
        return VStack(alignment: .leading, spacing: 24) {
            relayProviderHeader(provider)
            providerDetailStatusSection(provider, snapshot: snapshot, error: viewModel.errors[provider.id])
            relaySitePanel(provider, snapshot: snapshot)
            relayUsagePanel(provider, snapshot: snapshot)
            providerDetailProvenanceSection(provider, snapshot: snapshot)
            relayConfigPanel(provider)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func relayProviderHeader(_ provider: ProviderDescriptor) -> some View {
        let isEditing = editingRelayProviderID == provider.id
        let focusID = "relay-title-\(provider.id)"
        let nameBinding = Binding(
            get: { relayEditorDraft.providerNameInputs[provider.id] ?? provider.name },
            set: { relayEditorDraft.providerNameInputs[provider.id] = $0 }
        )

        return HStack(alignment: .center, spacing: 8) {
            relayProviderIcon(size: SettingsVisualTokens.Sidebar.headerIconSize)
                .frame(
                    width: SettingsVisualTokens.Sidebar.headerIconSize,
                    height: SettingsVisualTokens.Sidebar.headerIconSize
                )

            if isEditing {
                relayTitleEditField(
                    text: nameBinding,
                    focusID: focusID,
                    placeholder: viewModel.text(.providerName),
                    onSubmit: { commitRelayProviderNameEdit(provider) },
                    onCommitButton: { commitRelayProviderNameEdit(provider) }
                )
            } else {
                relayHeaderTitleLabel(sidebarDisplayName(for: provider))

                relayTitleIconButton(
                    systemName: "pencil",
                    accessibilityLabel: viewModel.localizedText("编辑名称", "Edit name"),
                    action: { beginRelayProviderNameEdit(provider) }
                )
            }

            Spacer(minLength: 0)

            relayHeaderTrailingControls(provider)
        }
        .frame(
            width: SettingsVisualTokens.SettingsLayout.configurationWidth,
            height: SettingsVisualTokens.SettingsLayout.rowHeight,
            alignment: .leading
        )
    }

    func relayHeaderTrailingControls(_ provider: ProviderDescriptor) -> some View {
        HStack(spacing: 16) {
            Button {
                Task { await viewModel.refreshSelectedProvider(provider.id) }
            } label: {
                settingsCompactToolbarIcon(named: "refresh_icon", fallback: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(viewModel.localizedText("刷新此来源", "Refresh this provider"))
            .accessibilityLabel(viewModel.localizedText("刷新此来源", "Refresh this provider"))

            SettingsToggleSwitch(
                isOn: Binding(
                    get: { provider.enabled },
                    set: { viewModel.setEnabled($0, providerID: provider.id) }
                ),
                offTrackColor: SettingsVisualTokens.Fill.control,
                onTrackColor: SettingsVisualTokens.Text.tertiary,
                knobColor: SettingsVisualTokens.Text.primary,
                accessibilityLabel: viewModel.localizedText(
                    "启用 \(sidebarDisplayName(for: provider))",
                    "Enable \(sidebarDisplayName(for: provider))"
                )
            )
        }
        .frame(width: 88, height: 24, alignment: .trailing)
    }

    func relayUsagePanel(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        let remaining = snapshot?.remaining
        let used = snapshot?.used
        let limit = snapshot?.limit ?? relayUsageTotalFallback(remaining: remaining, used: used)

        return settingsConfigurationSection(title: viewModel.localizedText("用量", "Usage")) {
            HStack(alignment: .center, spacing: 0) {
                relayUsageMetric(
                    title: viewModel.localizedText("余额", "Balance"),
                    value: formattedRelayUsageAmount(remaining ?? 0)
                )

                Spacer(minLength: 0)

                relayUsageMetric(
                    title: viewModel.localizedText("已消耗", "Used"),
                    value: formattedRelayUsageAmount(used ?? 0)
                )

                Spacer(minLength: 0)

                relayUsageMetric(
                    title: viewModel.localizedText("总额", "Total"),
                    value: formattedRelayUsageAmount(limit ?? 0)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(width: 566, height: 64, alignment: .center)
        }
        .frame(width: 566, alignment: .topLeading)
    }

    func relayUsageMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                .lineLimit(1)
                .frame(height: 10, alignment: .leading)

            Text(value)
                .font(AppFonts.numeric(size: 14, fallbackWeight: .bold))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .lineLimit(1)
                .frame(width: 140, height: 14, alignment: .leading)
        }
        .frame(width: 140, height: 32, alignment: .leading)
    }

    func relayUsageTotalFallback(remaining: Double?, used: Double?) -> Double? {
        guard let remaining, let used else { return nil }
        return remaining + used
    }

    func formattedRelayUsageAmount(_ value: Double) -> String {
        SharedNumberFormatting.decimal(
            value,
            minFractionDigits: 2,
            maxFractionDigits: 2,
            localeID: "en_US_POSIX"
        )
    }

    @ViewBuilder
    func relayConfigPanel(_ provider: ProviderDescriptor) -> some View {
        settingsConfigurationSection(title: viewModel.localizedText("配置", "Configuration")) {
            relayCondensedConfigSection(provider)
        }
    }

    func relaySitePanel(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        settingsConfigurationSection(title: viewModel.localizedText("站点", "Site")) {
            relaySiteRow(provider, snapshot: snapshot)
        }
    }

    func relaySiteRow(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        let status = relayProviderSummaryStatus(
            snapshot: snapshot,
            hasError: (viewModel.errors[provider.id]?.isEmpty == false)
        )
        let metrics = [
            SettingsCompactRecordMetric(
                id: "balance",
                title: viewModel.localizedText("余额", "Balance"),
                valueText: snapshot?.remaining.map(formattedSettingsAmount) ?? "-",
                resetText: nil
            ),
            SettingsCompactRecordMetric(
                id: "used",
                title: viewModel.localizedText("已用", "Used"),
                valueText: snapshot?.used.map(formattedSettingsAmount) ?? "-",
                resetText: nil
            )
        ]
        let actions = [
            SettingsCompactRecordAction(
                id: "delete",
                title: viewModel.localizedText("删除站点", "Delete Site"),
                destructive: true,
                action: { viewModel.removeProvider(providerID: provider.id) }
            )
        ]

        return officialSubscriptionAccountRecordRow(
            title: sidebarDisplayName(for: provider),
            currentText: nil,
            planType: nil,
            statusText: status.text,
            statusColor: status.color,
            errorText: nil,
            metrics: metrics,
            actions: actions,
            showsBottomSeparator: false
        )
    }

    @ViewBuilder
    func relayProviderIcon(size: CGFloat) -> some View {
        if let image = bundledImage(named: "relay_provider_third_icon") {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(settingsTitleColor)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .foregroundStyle(settingsBodyColor)
                .frame(width: size, height: size)
        }
    }
}
