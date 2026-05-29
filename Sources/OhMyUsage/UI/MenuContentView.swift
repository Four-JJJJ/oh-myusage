import OhMyUsageDomain
import AppKit
import SwiftUI
import OhMyUsageApplication

private struct MenuCardsContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuContentView: View {
    @Bindable var viewModel: AppViewModel
    var onOpenSettings: (() -> Void)?
    @State private var now = Date()
    @State private var onboardingDiscoveryMessage: String?
    @State private var onboardingDiscoveryIsError = false
    @State private var onboardingDiscoveryInFlight = false
    @State private var cardsContentHeight: CGFloat = 0
    @State private var clockTask: Task<Void, Never>?
    private let clockController = VisibleClockController()

    // MARK: - Menubar 视觉 Token（改这里可全局影响首页样式）
    // menubar 面板外层背景。
    private let panelBackground = SettingsVisualTokens.Menu.panelBackground
    // menubar 内部卡片背景。
    private let cardBackground = SettingsVisualTokens.Menu.cardBackground
    // 卡片垂直间距。
    private let cardSpacing = SettingsVisualTokens.Menu.cardSpacing
    // 状态颜色：健康/警告/错误。
    private let sufficientColor = SettingsVisualTokens.Status.sufficient
    private let warningColor = SettingsVisualTokens.Status.warning
    private let errorColor = SettingsVisualTokens.Status.error
    // 顶部操作按钮尺寸与间距（Figma: 16x16，间距 12）。
    private let headerActionIconSize = SettingsVisualTokens.Menu.headerActionIconSize
    private let headerActionSpacing = SettingsVisualTokens.Menu.headerActionSpacing
    private let headerHeight = SettingsVisualTokens.Menu.headerHeight
    private let headerActionIconOpacity = SettingsVisualTokens.Menu.headerActionIconOpacity
    private let updateHintColor = SettingsVisualTokens.Status.positive
    private let updateErrorColor = SettingsVisualTokens.Status.error
    // menubar 面板最高 800px，超出后只滚动卡片区。
    private let panelMaxHeight = SettingsVisualTokens.Menu.panelMaxHeight
    private let panelTopPadding = SettingsVisualTokens.Menu.panelTopPadding
    private let panelBottomPadding = SettingsVisualTokens.Menu.panelBottomPadding
    private let panelHorizontalPadding = SettingsVisualTokens.Menu.panelHorizontalPadding
    private let panelContentSpacing = SettingsVisualTokens.Menu.panelContentSpacing
    private let cardsViewportCornerRadius = SettingsVisualTokens.Menu.cardsViewportCornerRadius

    var body: some View {
        let state = viewModel.menuViewState(now: now)

        // menubar 主面板布局：顶部 header + 下方卡片列表。
        VStack(alignment: .leading, spacing: panelContentSpacing) {
            header(state.header)
            cards(state)
        }
        .frame(width: SettingsVisualTokens.Menu.panelWidth)
        .padding(.top, panelTopPadding)
        .padding(.bottom, panelBottomPadding)
        .padding(.horizontal, panelHorizontalPadding)
        .background(
            SettingsSmoothedRoundedRectangle(
                cornerRadius: SettingsVisualTokens.Radius.menuPanel,
                smoothing: SettingsVisualTokens.Smoothing.continuous
            )
                // menubar 外层圆角背景。
                .fill(panelBackground)
        )
        .clipShape(
            SettingsSmoothedRoundedRectangle(
                cornerRadius: SettingsVisualTokens.Radius.menuPanel,
                smoothing: SettingsVisualTokens.Smoothing.continuous
            )
        )
        .environment(\.colorScheme, .dark)
        .onAppear {
            restartClockIfNeeded()
        }
        .onDisappear {
            stopClock()
        }
        .onChange(of: viewModel.menuPanelVisible) { _, _ in
            restartClockIfNeeded()
        }
    }

    private func header(_ presentation: MenuDashboardHeaderPresentation) -> some View {
        // 顶部工具条：更新时间 + 新版本入口 + 刷新/设置/退出三个图标按钮。
        HStack(spacing: 12) {
            Text(presentation.updatedText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.muted)
                .lineSpacing(0)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let update = presentation.update {
                headerUpdateButton(update)
            }

            HStack(spacing: headerActionSpacing) {
                headerIconButton(iconName: "refresh_icon", fallback: "arrow.clockwise") {
                    viewModel.refreshNow()
                }
                headerIconButton(iconName: "settings_icon", fallback: "gearshape") {
                    if let onOpenSettings {
                        onOpenSettings()
                    } else {
                        SettingsWindowController.shared.show(viewModel: viewModel)
                    }
                }
                headerIconButton(iconName: "quit_icon", fallback: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(height: headerHeight)
        // 外层已有 horizontal 8，这里补 12 => 距离外边框 20px。
        .padding(.horizontal, SettingsVisualTokens.Menu.headerHorizontalPadding)
    }

    private func cards(_ state: MenuViewState) -> some View {
        // 卡片流容器：内容不足按实际高度；超过上限时在区内滚动。
        ScrollView {
            VStack(spacing: cardSpacing) {
                if state.shouldShowPermissionGuide {
                    permissionGuideCard
                }

                ForEach(state.cards) { card in
                    menuCard(card)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: MenuCardsContentHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
        }
        .scrollIndicators(.never)
        .frame(height: cardsViewportHeight)
        .clipShape(
            SettingsSmoothedRoundedRectangle(
                cornerRadius: cardsViewportCornerRadius,
                smoothing: SettingsVisualTokens.Smoothing.continuous
            )
        )
        .onPreferenceChange(MenuCardsContentHeightPreferenceKey.self) { height in
            if abs(cardsContentHeight - height) > 0.5 {
                cardsContentHeight = height
            }
        }
    }

    private var cardsViewportHeight: CGFloat {
        let maxHeight = max(
            0,
            panelMaxHeight - panelTopPadding - panelBottomPadding - headerHeight - panelContentSpacing
        )
        let measured = cardsContentHeight > 0 ? cardsContentHeight : maxHeight
        return min(maxHeight, measured)
    }

    private func headerIconButton(iconName: String, fallback: String, action: @escaping () -> Void) -> some View {
        // 顶部图标按钮样式入口（尺寸、图标颜色、点击样式）。
        Button(action: action) {
            BundledIconView(
                name: iconName,
                fallback: fallback,
                size: headerActionIconSize,
                iconOpacity: headerActionIconOpacity
            )
        }
        .buttonStyle(.plain)
        .frame(width: headerActionIconSize, height: headerActionIconSize)
    }

    private func headerUpdateTint(for tone: MenuDashboardHeaderUpdatePresentation.Tone) -> Color {
        switch tone {
        case .neutral, .positive:
            return updateHintColor
        case .negative:
            return updateErrorColor
        }
    }

    private func headerUpdateButton(_ update: MenuDashboardHeaderUpdatePresentation) -> some View {
        let tint = headerUpdateTint(for: update.tone)

        return HStack(spacing: 4) {
            BundledIconView(
                name: "settings_download_icon",
                fallback: "arrow.down",
                size: headerActionIconSize,
                tint: tint
            )
            if update.showsPrimaryAction {
                Button {
                    viewModel.performMenuUpdateAction()
                } label: {
                    Text(update.title)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(tint)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(!update.isRetryEnabled)
            } else {
                Text(update.title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(tint)
                    .lineSpacing(0)
                    .lineLimit(1)
            }

            if let retryTitle = update.retryTitle {
                Button {
                    viewModel.performMenuUpdateAction()
                } label: {
                    Text(retryTitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(updateErrorColor)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(!update.isRetryEnabled)
            }
        }
        .accessibilityLabel(update.accessibilityLabel)
    }

    private var permissionGuideCard: some View {
        MenuPermissionGuideView(
            presentation: permissionGuidePresentation,
            discoveryMessage: onboardingDiscoveryMessage,
            discoveryIsError: onboardingDiscoveryIsError,
            actionProvider: permissionGuideAction
        )
    }

    private var permissionGuidePresentation: MenuPermissionGuidePresentation {
        MenuPermissionGuidePresenter.build(
            language: viewModel.language,
            hasNotificationPermission: viewModel.hasNotificationPermission,
            secureStorageReady: viewModel.secureStorageReady,
            fullDiskAccessRelevant: viewModel.fullDiskAccessRelevant,
            fullDiskAccessRequested: viewModel.fullDiskAccessRequested,
            fullDiskAccessGranted: viewModel.fullDiskAccessGranted,
            canRunLocalDiscovery: viewModel.canRunLocalDiscoveryFromOnboarding,
            localDiscoveryState: localDiscoveryState
        )
    }

    private var localDiscoveryState: MenuPermissionGuidePresenter.LocalDiscoveryState {
        if onboardingDiscoveryInFlight {
            return .inFlight
        }
        return onboardingDiscoveryMessage == nil ? .idle : .completed
    }

    private func permissionGuideAction(_ actionKind: MenuPermissionGuideRowPresentation.ActionKind?) -> (() -> Void)? {
        guard let actionKind else {
            return nil
        }

        switch actionKind {
        case .requestNotifications:
            return { viewModel.requestNotificationPermission() }
        case .prepareKeychain:
            return { _ = viewModel.prepareSecureStorageAccess() }
        case .openFullDiskSettings:
            return { viewModel.openFullDiskAccessSettings() }
        case .runLocalDiscovery:
            return {
                onboardingDiscoveryMessage = viewModel.text(.localDiscoveryScanning)
                onboardingDiscoveryIsError = false
                onboardingDiscoveryInFlight = true
                Task {
                    let result = await viewModel.discoverLocalProviders()
                    await MainActor.run {
                        onboardingDiscoveryMessage = result
                        onboardingDiscoveryIsError = result == viewModel.text(.localDiscoveryNothingFound)
                        onboardingDiscoveryInFlight = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menuCard(_ card: MenuCardViewState) -> some View {
        switch card {
        case let .percentage(card):
            PercentageModelCard(
                title: card.title,
                planType: card.planType,
                iconName: card.iconName,
                iconFallback: card.iconFallback,
                subtitle: card.subtitle,
                status: cardStatus(card.status),
                metrics: percentageMetricViews(from: card.metrics),
                errorText: card.errorText,
                backgroundColor: cardBackground,
                isDisconnected: card.isDisconnected,
                highlightColor: card.showsErrorHighlight ? errorColor : nil
            )
        case let .amount(card):
            AmountModelCard(
                title: card.title,
                planType: card.planType,
                iconName: card.iconName,
                iconFallback: card.iconFallback,
                status: cardStatus(card.status),
                amountText: card.amountText,
                secondaryText: card.secondaryText,
                errorText: card.errorText,
                backgroundColor: cardBackground,
                isDisconnected: card.isDisconnected,
                highlightColor: card.showsErrorHighlight ? errorColor : nil,
                balanceLabel: card.balanceLabel
            )
        case let .officialGroup(card):
            officialProviderGroupCard(
                card.group,
                iconName: card.iconName,
                iconFallback: card.iconFallback
            ) { slotID in
                Task {
                    switch card.switchKind {
                    case .codex:
                        await viewModel.switchCodexProfile(slotID: slotID)
                    case .claude:
                        await viewModel.switchClaudeProfile(slotID: slotID)
                    }
                }
            }
        }
    }

    private func percentageMetricViews(
        from metrics: [MenuQuotaMetricDisplayPresentation]
    ) -> [PercentageMetricDisplay] {
        metrics.map { metric in
            PercentageMetricDisplay(
                id: metric.id,
                title: metric.title,
                valueText: metric.valueText,
                resetText: metric.resetText,
                detailText: metric.detailText,
                percent: metric.percent,
                barColor: percentageBarColor(for: metric.barTone),
                isBlockedByDepletedQuota: metric.isBlockedByDepletedQuota
            )
        }
    }

    nonisolated static func cachedFetchHealthStatusText(_ health: FetchHealth, language: AppLanguage) -> String {
        MenuCardStatusPresenter.cachedFetchHealthStatusText(health, language: language)
    }

    private func cardStatus(_ presentation: MenuCardStatusPresentation) -> CardStatus {
        CardStatus(
            text: presentation.text,
            color: color(for: presentation.tone)
        )
    }

    private func color(for tone: MenuCardStatusPresentation.Tone) -> Color {
        switch tone {
        case .normal:
            return sufficientColor
        case .warning:
            return warningColor
        case .error:
            return errorColor
        }
    }

    private func percentageBarColor(for tone: MenuQuotaMetricDisplayPresentation.BarTone) -> Color {
        switch tone {
        case .clear:
            return .clear
        case .normal:
            return sufficientColor
        case .warning:
            return warningColor
        case .error:
            return errorColor
        }
    }

    @ViewBuilder
    private func officialProviderGroupCard(
        _ group: MenuOfficialProviderGroupPresentation<CodexSlotID>,
        iconName: String,
        iconFallback: String,
        switchAction: @escaping (CodexSlotID) -> Void
    ) -> some View {
        OfficialProviderGroupCard(
            iconName: iconName,
            iconFallback: iconFallback,
            primary: group.primary,
            primaryMetrics: percentageMetricViews(from: group.primary.metricDisplays),
            secondary: group.secondary,
            backgroundColor: cardBackground,
            statusColor: { cardStatus($0).color },
            switchAction: switchAction
        )
    }

    private func restartClockIfNeeded() {
        clockController.restartClockIfNeeded(
            isVisible: viewModel.menuPanelVisible,
            existingTask: &clockTask,
            intervalSeconds: RuntimeDiagnosticsLimits.menuClockIntervalSeconds
        ) { referenceDate in
            tickClock(referenceDate: referenceDate)
        }
    }

    private func stopClock() {
        clockController.stopClock(existingTask: &clockTask)
    }

    private func tickClock(referenceDate: Date = Date()) {
        clockController.tick(referenceDate: referenceDate) { resolvedDate in
            now = resolvedDate
            if viewModel.shouldShowPermissionGuide {
                viewModel.refreshPermissionStatusesIfNeeded(referenceDate: resolvedDate)
            }
        }
    }

    static func countdownText(to target: Date?, now: Date, language: AppLanguage) -> String {
        // menubar 倒计时文案统一走 CountdownFormatter，避免与设置页实现漂移。
        CountdownFormatter.text(to: target, now: now, placeholder: "-", language: language)
    }
}
