import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    func relayRecoveryStatusText(_ snapshot: UsageSnapshot?) -> String? {
        let relayMetadata = RelaySnapshotDisplayMetadata(snapshot: snapshot)
        guard let recovery = relayMetadata.recovery else {
            return nil
        }

        let timeSuffix: String
        if let recoveredAt = recovery.recoveredAt {
            timeSuffix = settingsElapsedText(from: recoveredAt)
        } else {
            timeSuffix = viewModel.language == .zhHans ? "刚刚" : "just now"
        }

        return viewModel.language == .zhHans
            ? "最近自动恢复：\(recovery.source)｜\(timeSuffix)"
            : "Last auto recovery: \(recovery.source) | \(timeSuffix)"
    }

    func formattedSettingsAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    @ViewBuilder
    func relayDiagnosticSection(_ provider: ProviderDescriptor, _ result: RelayDiagnosticResult) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let recoveryText = relayRecoveryStatusText(snapshot)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(result.success ? viewModel.text(.connectionSuccess) : viewModel.text(.connectionFailed))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.success ? .green : Color(hex: 0xD83E3E))

                Text(relayFetchHealthLabel(result.fetchHealth))
                    .font(.caption)
                    .foregroundStyle(relayFetchHealthColor(result.fetchHealth))
            }

            Text("\(viewModel.text(.matchedAdapter)): \(result.resolvedAdapterID)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let authSource = result.resolvedAuthSource, !authSource.isEmpty {
                Text("\(viewModel.text(.authSourceLabel)): \(authSource)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let recoveryText, !recoveryText.isEmpty {
                Text(recoveryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(result.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let preview = result.snapshotPreview {
                Text(relayDiagnosticPreviewText(preview))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(settingsSubtlePanelFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    func relayRuntimeStatusSection(_ provider: ProviderDescriptor, selectedTemplate: RelayAdapterManifest) -> AnyView {
        let snapshot = viewModel.snapshots[provider.id]
        let authSource = viewModel.relayAuthSource(for: provider.id)
        let fetchHealth = viewModel.relayFetchHealth(for: provider.id)
        let freshness = viewModel.relayValueFreshness(for: provider.id)
        let error = viewModel.errors[provider.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveHealth = fetchHealth ?? snapshot?.fetchHealth
        let hasError = error?.isEmpty == false
        let summaryStatus = relayProviderSummaryStatus(snapshot: snapshot, hasError: hasError)
        let healthStatus = relayFetchHealthDisplayStatus(
            health: effectiveHealth,
            hasError: hasError
        )

        let balanceValue = snapshot?.remaining ?? snapshot?.limit ?? snapshot?.used
        let balanceText = balanceValue.map(formattedSettingsAmount) ?? "--"
        let updatedText = snapshot.map { "\(viewModel.text(.updatedAgo)) \(settingsElapsedText(from: $0.updatedAt))" }
            ?? (viewModel.language == .zhHans ? "更新于 --" : "Updated --")
        let freshnessText = freshness.map(relayValueFreshnessLabel) ?? (viewModel.language == .zhHans ? "未知" : "Unknown")
        let sourceValue = authSource?.isEmpty == false ? authSource! : selectedTemplate.displayName
        let sourceLine = viewModel.language == .zhHans
            ? "来源：\(sourceValue)｜\(freshnessText)"
            : "Source: \(sourceValue) | \(freshnessText)"
        let recoveryLine = relayRecoveryStatusText(snapshot)

        if provider.relayDisplayMode == .quotaPercent {
            let metrics = relayQuotaMetricDisplays(provider: provider, snapshot: snapshot)
            let subtitle = relayTokenPlanSubtitle(provider: provider, snapshot: snapshot)
            let planType = settingsProviderPlanType(provider: provider, snapshot: snapshot)

            return AnyView(
                officialAccountMonitorCard(
                    highlightColor: hasError ? Color(hex: 0xD05757) : nil
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 8) {
                            providerIcon(for: provider, size: 12)

                            VStack(alignment: .leading, spacing: 2) {
                                settingsModelTitleWithPlanType(
                                    title: sidebarDisplayName(for: provider),
                                    planType: planType
                                )
                                if let subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(settingsHintColor)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            Spacer(minLength: 8)

                            Text(summaryStatus.text)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(summaryStatus.color)
                                .lineLimit(1)
                        }
                        .frame(height: 24)

                        quotaMetricLayout(metrics: metrics, twoByTwo: false)
                            .padding(.top, 8)

                        if let error, !error.isEmpty {
                            Text(error)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color(hex: 0xD05757))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 8)
                        }

                        dividerLine
                            .padding(.top, error?.isEmpty == false ? 8 : 10)

                        HStack(spacing: 8) {
                            Text(healthStatus.text)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(healthStatus.color)
                                .lineLimit(1)

                            Text(updatedText)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(settingsHintColor)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(sourceLine)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(settingsHintColor)
                                .lineLimit(1)
                        }
                        .frame(height: 10)

                        if let recoveryLine, !recoveryLine.isEmpty {
                            Text(recoveryLine)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(settingsHintColor)
                                .lineLimit(1)
                        }
                    }
                }
            )
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    providerIcon(for: provider, size: 12)
                    Text(sidebarDisplayName(for: provider))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settingsBodyColor)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(summaryStatus.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(summaryStatus.color)
                        .lineLimit(1)
                }
                .frame(height: 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.text(.balanceLabel))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)

                    HStack(spacing: 6) {
                        if let image = bundledImage(named: "menu_balance_icon") {
                            Image(nsImage: image)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(settingsBodyColor)
                        } else {
                            Image(systemName: "dollarsign.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(settingsBodyColor)
                        }
                        Text(balanceText)
                            .font(AppFonts.numeric(size: 16, fallbackWeight: .semibold))
                            .foregroundStyle(settingsBodyColor)
                    }
                }

                if let error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color(hex: 0xD05757))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                dividerLine

                HStack(spacing: 8) {
                    Text(healthStatus.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(healthStatus.color)
                        .lineLimit(1)

                    Text(updatedText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(sourceLine)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)
                        .lineLimit(1)
                }
                .frame(height: 10)

                if let recoveryLine, !recoveryLine.isEmpty {
                    Text(recoveryLine)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsHintColor)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
        )
    }

    func relayQuotaMetricDisplays(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> [CodexQuotaMetricDisplay] {
        let relayMetadata = RelaySnapshotDisplayMetadata(
            snapshot: snapshot,
            fallbackAdapterID: provider.relayConfig?.adapterID
        )
        let windows = snapshot?.quotaWindows ?? [
            UsageQuotaWindow(
                id: "\(provider.id)-placeholder-token-plan-total",
                title: "Total Usage",
                remainingPercent: 0,
                usedPercent: 100,
                resetAt: nil,
                kind: .custom
            )
        ]

        return windows.map { window in
            let displayPercent = provider.displaysUsedQuota
                ? min(100, max(0, window.usedPercent))
                : min(100, max(0, window.remainingPercent))
            let valueText = relayQuotaValueTextOverride(
                window: window,
                provider: provider,
                relayMetadata: relayMetadata
            )
                ?? codexQuotaValueText(
                    window: window,
                    provider: provider,
                    snapshot: snapshot,
                    displayPercent: displayPercent
                )
            let healthPercent = min(100, max(0, window.remainingPercent))
            return CodexQuotaMetricDisplay(
                id: window.id,
                title: codexQuotaDisplayTitle(window, provider: provider),
                valueText: valueText,
                resetText: provider.showsExpirationTimeInMenuBar
                    ? codexResetCountdownText(for: window, snapshot: snapshot)
                    : "-",
                detailText: relayQuotaDetailTextOverride(
                    window: window,
                    provider: provider,
                    relayMetadata: relayMetadata
                ),
                percent: displayPercent > 0 ? displayPercent : 0,
                barColor: codexQuotaBarColor(remainingPercent: healthPercent),
                isAvailable: snapshot != nil
            )
        }
    }

    func relayQuotaValueTextOverride(
        window: UsageQuotaWindow,
        provider: ProviderDescriptor,
        relayMetadata: RelaySnapshotDisplayMetadata
    ) -> String? {
        guard !provider.usesXiaomimimoTokenPlanQuota else {
            return nil
        }
        return relayMetadata.quotaValueText(for: window.id)
    }

    func relayQuotaDetailTextOverride(
        window: UsageQuotaWindow,
        provider: ProviderDescriptor,
        relayMetadata: RelaySnapshotDisplayMetadata
    ) -> String? {
        guard provider.usesXiaomimimoTokenPlanQuota,
              window.id == "token-plan-total",
              let remainingTokens = relayTokenPlanRemainingTokens(from: relayMetadata) else {
            return nil
        }
        let formatted = formattedSettingsWholeNumber(remainingTokens)
        switch viewModel.language {
        case .zhHans:
            return "剩余 \(formatted) tokens"
        case .en:
            return "\(formatted) tokens remaining"
        }
    }

    func relayTokenPlanRemainingTokens(from relayMetadata: RelaySnapshotDisplayMetadata) -> Double? {
        if let remaining = relayMetadata.tokenPlanRemainingTokens {
            return remaining
        }
        guard let used = relayMetadata.tokenPlanUsedTokens,
              let limit = relayMetadata.tokenPlanLimitTokens else {
            return nil
        }
        return max(0, limit - used)
    }

    func formattedSettingsWholeNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
    }

    func relayTokenPlanSubtitle(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> String? {
        guard provider.showsExpirationTimeInMenuBar else {
            return nil
        }
        let relayMetadata = RelaySnapshotDisplayMetadata(snapshot: snapshot)
        guard let raw = relayMetadata.tokenPlanCurrentPeriodEnd else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch viewModel.language {
        case .zhHans:
            return "有效期至 \(trimmed) (UTC)"
        case .en:
            return "Valid until \(trimmed) (UTC)"
        }
    }

    func relayProviderSummaryStatus(
        snapshot: UsageSnapshot?,
        hasError: Bool
    ) -> (text: String, color: Color) {
        let status = RelayStatusPresenter.providerSummaryStatus(
            snapshot: snapshot,
            hasError: hasError,
            language: viewModel.language
        )
        return (status.text, status.color)
    }

    func relayCachedRelayStatus(fetchHealth: FetchHealth) -> (text: String, color: Color) {
        let status = RelayStatusPresenter.cachedRelayStatus(
            fetchHealth: fetchHealth,
            language: viewModel.language
        )
        return (status.text, status.color)
    }

    func relayFetchHealthDisplayStatus(
        health: FetchHealth?,
        hasError: Bool
    ) -> (text: String, color: Color) {
        let status = RelayStatusPresenter.fetchHealthDisplayStatus(
            health: health,
            hasError: hasError,
            language: viewModel.language
        )
        return (status.text, status.color)
    }

    func relayFetchHealthLabel(_ health: FetchHealth) -> String {
        RelayStatusPresenter.fetchHealthLabel(health, language: viewModel.language)
    }

    func relayFetchHealthColor(_ health: FetchHealth) -> Color {
        RelayStatusPresenter.fetchHealthColor(health)
    }

    func relayValueFreshnessLabel(_ freshness: ValueFreshness) -> String {
        RelayStatusPresenter.valueFreshnessLabel(freshness, language: viewModel.language)
    }

    func relayRuntimeStatusTitle() -> String {
        switch viewModel.language {
        case .zhHans:
            return "当前连接状态"
        case .en:
            return "Current connection status"
        }
    }

    func relayFetchHealthTitle() -> String {
        switch viewModel.language {
        case .zhHans:
            return "抓取状态"
        case .en:
            return "Fetch health"
        }
    }

    func relayFreshnessTitle() -> String {
        switch viewModel.language {
        case .zhHans:
            return "数据状态"
        case .en:
            return "Value state"
        }
    }

    func relayDiagnosticPreviewText(_ preview: RelayDiagnosticSnapshotPreview) -> String {
        let unit = preview.unit.isEmpty ? "" : " \(preview.unit)"
        let remaining = preview.remaining.map { formattedSettingsAmount($0) } ?? "-"
        let used = preview.used.map { formattedSettingsAmount($0) } ?? "-"
        let limit = preview.limit.map { formattedSettingsAmount($0) } ?? "-"
        if viewModel.language == .zhHans {
            return "预览: 剩余 \(remaining)\(unit) / 已用 \(used)\(unit) / 上限 \(limit)\(unit)"
        }
        return "Preview: remaining \(remaining)\(unit) / used \(used)\(unit) / limit \(limit)\(unit)"
    }
}
