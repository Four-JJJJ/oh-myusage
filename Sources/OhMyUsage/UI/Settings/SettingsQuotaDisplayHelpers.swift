import AppKit
import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    @ViewBuilder
    func quotaMetricLayout(
        metrics: [CodexQuotaMetricDisplay],
        twoByTwo: Bool
    ) -> some View {
        if twoByTwo {
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(metricsForRow(metrics: metrics, row: row), id: \.id) { metric in
                            codexQuotaMetricView(metric)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 24) {
                ForEach(metrics.prefix(2)) { metric in
                    codexQuotaMetricView(metric)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    func metricsForRow(metrics: [CodexQuotaMetricDisplay], row: Int) -> [CodexQuotaMetricDisplay] {
        let start = row * 2
        guard start < metrics.count else { return [] }
        let end = min(start + 2, metrics.count)
        return Array(metrics[start..<end])
    }

    func codexQuotaMetricView(_ metric: CodexQuotaMetricDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(metric.title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(0)
                    .lineLimit(1)

                Spacer(minLength: 4)

                HStack(spacing: 2) {
                    if let image = bundledImage(named: "menu_reset_clock_icon") {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(settingsHintColor)
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(settingsHintColor)
                    }

                    Text(metric.resetText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(settingsMutedHintColor)
                        .monospacedDigit()
                        .lineSpacing(0)
                        .frame(minWidth: 42, alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                }
                .frame(minWidth: 54, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .frame(height: 10)
            }
            .frame(height: 10)

            HStack(spacing: 5) {
                Text(metric.valueText)
                    .font(AppFonts.numeric(size: 16, fallbackWeight: .semibold))
                    .foregroundStyle(settingsBodyColor)
                    .lineSpacing(0)
                    .frame(width: MetricValueLayoutFormatter.metricValueColumnWidth, alignment: .leading)
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                            .fill(settingsQuotaTrackColor)
                        if let percent = metric.percent, percent > 0 {
                            RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                                .fill(metric.barColor)
                                .frame(width: max(1, proxy.size.width * percent / 100))
                                .clipShape(RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous))
                        }
                        if metric.isBlockedByDepletedQuota {
                            QuotaBlockedStripePattern()
                                .fill(SettingsVisualTokens.Status.blockedStripe)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous))
                }
                .frame(height: SettingsVisualTokens.Menu.progressTrackHeight)
            }

            if let detailText = metric.detailText, !detailText.isEmpty {
                Text(detailText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(settingsMutedHintColor)
                    .lineSpacing(0)
                    .lineLimit(1)
            }
        }
    }

    func codexAccountActionButton(
        _ title: String,
        destructive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(destructive ? SettingsVisualTokens.Status.error : settingsAccentBlue)
        .disabled(disabled)
    }

    func codexAccountIcon(size: CGFloat) -> some View {
        Group {
            if let image = themedBundledImage(named: "menu_codex_icon") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "terminal.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(settingsBodyColor)
            }
        }
        .frame(width: size, height: size)
    }

    func claudeAccountIcon(size: CGFloat) -> some View {
        Group {
            if let image = themedBundledImage(named: "menu_claude_icon") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(settingsBodyColor)
            }
        }
        .frame(width: size, height: size)
    }

    func officialMonitoringProvider(for type: ProviderType) -> ProviderDescriptor {
        Self.resolvedOfficialMonitoringProvider(
            type: type,
            providers: viewModel.config.providers
        )
    }

    func localizedOfficialMonitoringStatus(
        _ status: OfficialMonitoringHealthStatus
    ) -> (text: String, color: Color) {
        switch status {
        case .unknown:
            return (viewModel.language == .zhHans ? "未知" : "Unknown", settingsHintColor)
        case .authError:
            return (viewModel.language == .zhHans ? "认证故障" : "Auth Error", SettingsVisualTokens.Status.error)
        case .configError:
            return (viewModel.language == .zhHans ? "配置异常" : "Config Error", SettingsVisualTokens.Status.error)
        case .rateLimited:
            return (viewModel.language == .zhHans ? "限流" : "Rate Limited", SettingsVisualTokens.Status.warningStrong)
        case .disconnected:
            return (viewModel.language == .zhHans ? "连接失败" : "Disconnected", SettingsVisualTokens.Status.error)
        case .sufficient:
            return (viewModel.text(.statusSufficient), SettingsVisualTokens.Status.sufficient)
        case .tight:
            return (viewModel.text(.statusTight), SettingsVisualTokens.Status.warningStrong)
        case .exhausted:
            return (viewModel.text(.statusExhausted), SettingsVisualTokens.Status.error)
        }
    }

    func codexSlotStatus(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> (text: String, color: Color) {
        let healthPercents = codexQuotaMetrics(provider: provider, snapshot: snapshot).compactMap(\.healthPercent)
        let status = Self.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: healthPercents
        )
        return localizedOfficialMonitoringStatus(status)
    }

    func officialMonitorSubtitle(snapshot: UsageSnapshot?) -> String? {
        guard viewModel.showOfficialAccountEmailInMenuBar else { return nil }
        return OfficialValueParser.nonPlaceholderString(snapshot?.accountLabel)
    }

    func officialMonitorPlanType(providerType: ProviderType, snapshot: UsageSnapshot?) -> String? {
        PlanTypeDisplayFormatter.resolvedPlanType(
            providerType: providerType,
            extrasPlanType: snapshot?.extras["planType"],
            rawPlanType: snapshot?.rawMeta["planType"]
        )
    }

    func settingsProviderPlanType(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> String? {
        if provider.family == .official {
            return officialMonitorPlanType(providerType: provider.type, snapshot: snapshot)
        }
        return PlanTypeDisplayFormatter.normalizedPlanType(
            snapshot?.extras["planType"],
            providerType: provider.type
        ) ?? PlanTypeDisplayFormatter.normalizedPlanType(
            snapshot?.rawMeta["planType"],
            providerType: provider.type
        )
    }

    func codexQuotaMetrics(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> [CodexQuotaMetricDisplay] {
        if provider.type == .claude {
            if let snapshot, !snapshot.quotaWindows.isEmpty {
                return claudeCodexQuotaMetrics(provider: provider, snapshot: snapshot)
            }
            return claudeCodexQuotaPlaceholderMetrics(provider: provider)
        }

        let windows: [UsageQuotaWindow]
        if let snapshot, !snapshot.quotaWindows.isEmpty {
            windows = snapshot.quotaWindows
                .sorted { codexQuotaRank($0.kind) < codexQuotaRank($1.kind) }
        } else {
            switch provider.type {
            case .trae:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-dollar",
                        title: traeQuotaMetricTitle(baseTitle: "Dollar"),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-autocomplete",
                        title: traeQuotaMetricTitle(baseTitle: "Autocomplete"),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    )
                ]
            case .copilot:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-premium",
                        title: "Premium",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-chat",
                        title: "Chat",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    )
                ]
            case .microsoftCopilot:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-d7",
                        title: "D7",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-d30",
                        title: "D30",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .custom
                    )
                ]
            case .openrouterCredits:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-credits",
                        title: "Credits",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .credits
                    )
                ]
            case .openrouterAPI:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-limit",
                        title: "Limit",
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .credits
                    )
                ]
            case .ollamaCloud:
                windows = [
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-session",
                        title: viewModel.localizedText("会话", "Session"),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .session
                    ),
                    UsageQuotaWindow(
                        id: "\(provider.id)-placeholder-weekly",
                        title: viewModel.text(.quotaWeekly),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .weekly
                    )
                ]
            default:
                windows = [
                    UsageQuotaWindow(
                        id: "codex-placeholder-session",
                        title: viewModel.text(.quotaFiveHour),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .session
                    ),
                    UsageQuotaWindow(
                        id: "codex-placeholder-weekly",
                        title: viewModel.text(.quotaWeekly),
                        remainingPercent: 0,
                        usedPercent: 100,
                        resetAt: nil,
                        kind: .weekly
                    )
                ]
            }
        }

        return windows.prefix(2).map { window in
            let percents = Self.quotaMetricPercents(
                for: window,
                displaysUsedQuota: provider.displaysUsedQuota
            )
            return CodexQuotaMetricDisplay(
                id: window.id,
                title: codexQuotaDisplayTitle(window, provider: provider),
                valueText: codexQuotaValueText(
                    window: window,
                    provider: provider,
                    snapshot: snapshot,
                    displayPercent: percents.displayPercent
                ),
                resetText: provider.showsExpirationTimeInMenuBar
                    ? codexResetCountdownText(for: window, snapshot: snapshot)
                    : "-",
                percent: percents.displayPercent,
                barColor: codexQuotaBarColor(remainingPercent: percents.healthPercent),
                healthPercent: percents.healthPercent,
                isBlockedByDepletedQuota: QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(
                    window: window,
                    in: windows,
                    provider: provider
                )
            )
        }
    }

    func claudeCodexQuotaPlaceholderMetrics(provider: ProviderDescriptor) -> [CodexQuotaMetricDisplay] {
        [
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-session",
                title: usagePreferredQuotaTitle(viewModel.text(.quotaFiveHour), provider: provider),
                valueText: "0%",
                resetText: codexResetCountdownText(to: nil),
                percent: 0,
                barColor: codexQuotaBarColor(remainingPercent: 0),
                healthPercent: 0
            ),
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-weekly-all",
                title: usagePreferredQuotaTitle(
                    viewModel.localizedText("全部模型", "All models"),
                    provider: provider
                ),
                valueText: "0%",
                resetText: codexResetCountdownText(to: nil),
                percent: 0,
                barColor: codexQuotaBarColor(remainingPercent: 0),
                healthPercent: 0
            ),
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-weekly-sonnet",
                title: usagePreferredQuotaTitle(
                    viewModel.localizedText("Sonnet 专用", "Sonnet only"),
                    provider: provider
                ),
                valueText: "N/A",
                resetText: codexResetCountdownText(to: nil),
                percent: nil,
                barColor: .clear,
                isAvailable: false
            ),
            CodexQuotaMetricDisplay(
                id: "\(provider.id)-placeholder-weekly-design",
                title: usagePreferredQuotaTitle(
                    viewModel.localizedText("Claude Design", "Claude Design"),
                    provider: provider
                ),
                valueText: "N/A",
                resetText: codexResetCountdownText(to: nil),
                percent: nil,
                barColor: .clear,
                isAvailable: false
            )
        ]
    }

    func claudeCodexQuotaMetrics(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot
    ) -> [CodexQuotaMetricDisplay] {
        let windows = snapshot.quotaWindows
        let sessionWindow = windows.first(where: { $0.kind == .session })
        return [
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-session",
                title: viewModel.text(.quotaFiveHour),
                window: sessionWindow,
                snapshot: snapshot,
                isBlockedByDepletedQuota: sessionWindow.map {
                    QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(window: $0, in: windows, provider: provider)
                } ?? false
            ),
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-weekly-all",
                title: viewModel.localizedText("全部模型", "All models"),
                window: windows.first(where: { $0.kind == .weekly }),
                snapshot: snapshot
            ),
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-weekly-sonnet",
                title: viewModel.localizedText("Sonnet 专用", "Sonnet only"),
                window: windows.first(where: isClaudeSonnetWindow(_:)),
                snapshot: snapshot
            ),
            claudeCodexQuotaMetric(
                provider: provider,
                id: "\(provider.id)-weekly-design",
                title: viewModel.localizedText("Claude Design", "Claude Design"),
                window: windows.first(where: isClaudeDesignWindow(_:)),
                snapshot: snapshot
            )
        ]
    }

    func claudeCodexQuotaMetric(
        provider: ProviderDescriptor,
        id: String,
        title: String,
        window: UsageQuotaWindow?,
        snapshot: UsageSnapshot,
        isBlockedByDepletedQuota: Bool = false
    ) -> CodexQuotaMetricDisplay {
        guard let window else {
            return CodexQuotaMetricDisplay(
                id: id,
                title: usagePreferredQuotaTitle(title, provider: provider),
                valueText: "N/A",
                resetText: codexResetCountdownText(to: nil),
                percent: nil,
                barColor: .clear,
                isAvailable: false
            )
        }

        let percents = Self.quotaMetricPercents(
            for: window,
            displaysUsedQuota: provider.displaysUsedQuota
        )
        return CodexQuotaMetricDisplay(
            id: id,
            title: usagePreferredQuotaTitle(title, provider: provider),
            valueText: codexQuotaValueText(
                window: window,
                provider: provider,
                snapshot: snapshot,
                displayPercent: percents.displayPercent
            ),
            resetText: provider.showsExpirationTimeInMenuBar
                ? codexResetCountdownText(for: window, snapshot: snapshot)
                : "-",
            percent: percents.displayPercent,
            barColor: codexQuotaBarColor(remainingPercent: percents.healthPercent),
            isAvailable: true,
            healthPercent: percents.healthPercent,
            isBlockedByDepletedQuota: isBlockedByDepletedQuota
        )
    }

    func codexQuotaBarColor(remainingPercent: Double?) -> Color {
        guard let remainingPercent else {
            return .clear
        }
        if remainingPercent > 30 {
            return SettingsVisualTokens.Status.sufficient
        }
        if remainingPercent > 10 {
            return SettingsVisualTokens.Status.warningStrong
        }
        return SettingsVisualTokens.Status.error
    }

    func isClaudeSonnetWindow(_ window: UsageQuotaWindow) -> Bool {
        let normalizedID = window.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedID.contains("sonnet")
            || normalizedTitle.contains("sonnet")
    }

    func isClaudeDesignWindow(_ window: UsageQuotaWindow) -> Bool {
        let normalizedID = window.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedID.contains("design")
            || normalizedTitle.contains("design")
    }

    func codexQuotaDisplayTitle(_ window: UsageQuotaWindow, provider: ProviderDescriptor) -> String {
        let baseTitle: String
        if provider.type == .trae {
            baseTitle = traeQuotaMetricTitle(baseTitle: window.title)
            return usagePreferredQuotaTitle(baseTitle, provider: provider)
        }
        switch window.kind {
        case .session:
            if provider.type == .ollamaCloud {
                baseTitle = viewModel.localizedText("会话", "Session")
            } else {
                baseTitle = viewModel.text(.quotaFiveHour)
            }
        case .weekly, .modelWeekly:
            baseTitle = viewModel.text(.quotaWeekly)
        default:
            baseTitle = relayTokenPlanMetricTitle(window.title, provider: provider)
        }
        return usagePreferredQuotaTitle(baseTitle, provider: provider)
    }

    func relayTokenPlanMetricTitle(_ rawTitle: String, provider: ProviderDescriptor) -> String {
        let normalizedAdapterID = provider.relayConfig?.adapterID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalizedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedAdapterID == "xiaomimimo-token-plan" else { return rawTitle }
        if normalizedTitle == "current plan" || normalizedTitle == "total usage" {
            return viewModel.localizedText("总用量", "Total Usage")
        }
        return rawTitle
    }

    func usagePreferredQuotaTitle(_ baseTitle: String, provider: ProviderDescriptor) -> String {
        guard provider.displaysUsedQuota else { return baseTitle }
        switch viewModel.language {
        case .zhHans:
            return "\(baseTitle)已用"
        case .en:
            return "\(baseTitle) used"
        }
    }

    func codexQuotaValueText(
        window: UsageQuotaWindow,
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        displayPercent: Double
    ) -> String {
        if provider.type == .trae, provider.traeDisplaysAmount {
            if let amount = traeAmountValue(
                window: window,
                snapshot: snapshot,
                displaysUsedQuota: provider.displaysUsedQuota
            ),
               let kind = TraeMetricKind.detect(id: window.id, title: window.title) {
                return TraeValueDisplayFormatter.format(
                    amount,
                    kind: kind,
                    maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
                )
            }
            return "-"
        }
        return "\(Int(displayPercent.rounded()))%"
    }

    func traeAmountValue(
        window: UsageQuotaWindow,
        snapshot: UsageSnapshot?,
        displaysUsedQuota: Bool
    ) -> Double? {
        guard let snapshot else { return nil }
        let primaryKey: String?
        let fallbackKey: String?
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if window.id.lowercased().contains("autocomplete") || normalizedTitle.contains("autocomplete") || normalizedTitle.contains("自动补全") {
            primaryKey = displaysUsedQuota ? "autocompleteUsed" : "autocompleteRemaining"
            fallbackKey = displaysUsedQuota ? "autocompleteRemaining" : nil
        } else if window.id.lowercased().contains("dollar") || normalizedTitle.contains("dollar") || normalizedTitle.contains("美元") {
            primaryKey = displaysUsedQuota ? "dollarUsed" : "dollarRemaining"
            fallbackKey = displaysUsedQuota ? "dollarRemaining" : nil
        } else {
            primaryKey = nil
            fallbackKey = nil
        }
        guard let key = primaryKey else { return nil }
        let resolvedRaw = snapshot.extras[key] ?? fallbackKey.flatMap { snapshot.extras[$0] }
        guard let raw = resolvedRaw else { return nil }
        return Double(raw)
    }

    func traeQuotaMetricTitle(baseTitle: String) -> String {
        let normalized = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("autocomplete") || normalized.contains("自动补全") {
            return viewModel.localizedText("自动补全", "Autocomplete")
        }
        if normalized.contains("dollar") || normalized.contains("美元") {
            return viewModel.localizedText("美元余额", "Dollar Balance")
        }
        return baseTitle
    }

    func codexQuotaRank(_ kind: UsageQuotaKind) -> Int {
        switch kind {
        case .session: return 0
        case .weekly: return 1
        case .reviews: return 2
        case .modelWeekly: return 3
        case .credits: return 4
        case .extraUsage: return 5
        case .custom: return 6
        }
    }

    func codexResetCountdownText(to target: Date?) -> String {
        Self.codexCountdownText(to: target, now: runtimeState.settingsNow, language: viewModel.language)
    }

    func codexResetCountdownText(for window: UsageQuotaWindow, snapshot: UsageSnapshot?) -> String {
        codexResetCountdownText(to: window.resetAt)
    }

    static func codexCountdownText(to target: Date?, now: Date, language: AppLanguage) -> String {
        SettingsCountdownPresenter.codexCountdownText(to: target, now: now, language: language)
    }

    var codexEditButtonTitle: String {
        viewModel.language == .zhHans ? "编辑" : "Edit"
    }

    var codexDeleteButtonTitle: String {
        viewModel.language == .zhHans ? "删除账号" : "Delete"
    }

    var codexAddButtonTitle: String {
        viewModel.language == .zhHans ? "添加" : "Add"
    }

    func sourceModeLabel(_ mode: OfficialSourceMode) -> String {
        switch mode {
        case .auto: return "Auto"
        case .api: return "API"
        case .cli: return "CLI"
        case .web: return "Web"
        }
    }

    func officialSourceHintText(for provider: ProviderDescriptor) -> String {
        if provider.type == .kiro {
            return viewModel.localizedText(
                "默认会自动发现本地 CLI 或 Kiro IDE 登录态；当 CLI 不可用时会回退读取 IDE 缓存。",
                "Local Kiro CLI sessions are auto-discovered by default. When CLI is unavailable, the app falls back to Kiro IDE cache."
            )
        }
        if provider.type == .copilot {
            return viewModel.localizedText(
                "默认按顺序自动读取 COPILOT_GITHUB_TOKEN、GH_TOKEN、GITHUB_TOKEN、Copilot CLI 钥匙串与 GitHub CLI 登录态；当前仅支持 API 检测。",
                "Automatically checks COPILOT_GITHUB_TOKEN, GH_TOKEN, GITHUB_TOKEN, Copilot CLI keychain, and GitHub CLI login in order. API detection only."
            )
        }
        if provider.type == .openrouterCredits {
            return viewModel.localizedText(
                "OpenRouter Credits 需要管理密钥（Management Key），用于读取 /credits 的总额度数据。",
                "OpenRouter Credits requires a Management Key to read total credit usage from /credits."
            )
        }
        if provider.type == .opencodeGo {
            return viewModel.localizedText(
                "Workspace ID 请从 opencode.ai 的 workspace URL 中复制 wrk_...；Cookie 可开启浏览器自动导入 auth，或手动粘贴。若远端接口 hash 变更，可用环境变量 OPENCODE_USAGE_ENDPOINT_ID 覆盖。",
                "Copy Workspace ID (wrk_...) from the opencode.ai workspace URL. Cookie can be auto-imported from browser auth or pasted manually. If endpoint hash changes, override with OPENCODE_USAGE_ENDPOINT_ID."
            )
        }
        if provider.type == .openrouterAPI {
            return viewModel.localizedText(
                "OpenRouter API 使用普通 API Key，读取 /key 的 limit 与 remaining。",
                "OpenRouter API uses a regular API key to read limit and remaining from /key."
            )
        }
        if provider.type == .ollamaCloud {
            return viewModel.localizedText(
                "默认从浏览器自动导入 ollama.com 的 __Secure-session Cookie，也可切到手动模式粘贴。",
                "By default, __Secure-session is auto-imported from ollama.com browser cookies. You can switch to manual mode and paste it."
            )
        }
        return viewModel.text(.officialAutoDiscoveryHint)
    }

    func webModeLabel(_ mode: OfficialWebMode) -> String {
        switch mode {
        case .disabled: return viewModel.text(.webDisabled)
        case .autoImport: return viewModel.text(.webAutoImport)
        case .manual: return viewModel.text(.webManual)
        }
    }

    func firstExistingRelayIconName(_ candidates: [String]) -> String? {
        candidates.first { bundledImage(named: $0) != nil }
    }
}
