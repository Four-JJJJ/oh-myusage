import SwiftUI

extension SettingsView {
    var appBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsGeneralControlRow(title: settingsLanguageTitle) {
                languageSegmentControl
            }

            VStack(alignment: .leading, spacing: 8) {
                settingsGeneralControlRow(title: settingsLaunchTitle) {
                    SettingsToggleSwitch(
                        isOn: Binding(
                            get: { viewModel.launchAtLoginEnabled },
                            set: { viewModel.setLaunchAtLoginEnabled($0) }
                        ),
                        offTrackColor: Color.white.opacity(0.15),
                        onTrackColor: Color.white.opacity(0.40),
                        knobColor: Color.white.opacity(0.80),
                        accessibilityLabel: settingsLaunchTitle
                    )
                }

                Text(settingsLaunchHint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(settingsHintMultilineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsGeneralHintLeadingPadding)
            }

            VStack(alignment: .leading, spacing: 8) {
                settingsGeneralControlRow(title: settingsRefreshIntervalTitle) {
                    refreshIntervalSegmentControl
                }

                Text(settingsRefreshIntervalHint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(settingsHintMultilineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsGeneralHintLeadingPadding)
            }

            VStack(alignment: .leading, spacing: 8) {
                settingsGeneralControlRow(title: settingsBackgroundRefreshTitle) {
                    backgroundRefreshSegmentControl
                }

                Text(settingsBackgroundRefreshHint)
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(settingsHintMultilineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsGeneralHintLeadingPadding)
            }

            resourceDiagnosticsPanel
        }
    }

    var resourceDiagnosticsPanel: some View {
        let presentation = SettingsResourceDiagnosticsPresenter.presentation(
            diagnostics: viewModel.runtimeMemoryDiagnostics(),
            localizedText: viewModel.localizedText
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text(presentation.title)
                .font(settingsLabelFont)
                .foregroundStyle(settingsTitleColor)

            HStack(alignment: .top, spacing: 8) {
                ForEach(presentation.rows) { row in
                    resourceDiagnosticMetric(row)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: settingsSectionCornerRadius)
                .fill(Color.clear)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: settingsSectionCornerRadius)
                .stroke(settingsSubtlePanelStrokeColor, lineWidth: 1)
        )
    }

    func resourceDiagnosticMetric(_ row: SettingsResourceDiagnosticRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.title)
                .font(settingsHintFont)
                .foregroundStyle(settingsHintColor)
                .lineLimit(1)

            Text(row.value)
                .font(AppFonts.numeric(size: 15, fallbackWeight: .semibold))
                .foregroundStyle(settingsTitleColor)
                .lineLimit(1)

            Text(row.detail)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(settingsMutedHintColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }

    var menuBarPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                settingsMenuBarControlRow(title: settingsStatusBarMultiUsageTitle) {
                    SettingsToggleSwitch(
                        isOn: Binding(
                            get: { viewModel.statusBarMultiUsageEnabled },
                            set: { viewModel.setStatusBarMultiUsageEnabled($0) }
                        ),
                        offTrackColor: Color.white.opacity(0.15),
                        onTrackColor: Color.white.opacity(0.40),
                        knobColor: Color.white.opacity(0.80),
                        accessibilityLabel: settingsStatusBarMultiUsageTitle
                    )
                }

                Text(settingsStatusBarMultiUsageHint)
                    .font(settingsHintFont)
                    .foregroundStyle(Color.white.opacity(0.40))
                    .lineSpacing(settingsHintMultilineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsMenuBarHintLeadingPadding)
            }

            HStack(alignment: .center, spacing: 16) {
                settingsMenuBarLabel(settingsStatusBarDisplayStyleTitle)

                HStack(spacing: 8) {
                    menuBarStyleCard(
                        title: viewModel.localizedText("图标+百分比", "Icon + Percent"),
                        selected: viewModel.statusBarDisplayStyle == .iconPercent
                    ) {
                        iconPercentPreview
                    } action: {
                        viewModel.setStatusBarDisplayStyle(.iconPercent)
                    }

                    menuBarStyleCard(
                        title: viewModel.localizedText("柱状图+名称", "Bar + Name"),
                        selected: viewModel.statusBarDisplayStyle == .barNamePercent
                    ) {
                        barNamePercentPreview
                    } action: {
                        viewModel.setStatusBarDisplayStyle(.barNamePercent)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                settingsMenuBarControlRow(title: settingsAppearanceModeTitle) {
                    settingsAppearanceModeSegmentControl
                }

                Text(settingsAppearanceModeHint)
                    .font(settingsHintFont)
                    .foregroundStyle(Color.white.opacity(0.40))
                    .lineSpacing(settingsHintMultilineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsMenuBarHintLeadingPadding)
            }
        }
    }

    var generalBasicsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            appBehaviorSection
            dividerLine
            menuBarPreferencesSection
        }
    }

    var topGeneralSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            generalBasicsSection
            permissionsSection
        }
    }

    var settingsAppearanceModeSection: some View {
        settingsDetailControlRow(title: settingsAppearanceModeTitle) {
            settingsAppearanceModeSegmentControl
        }
    }

    var settingsAppearanceModeSegmentControl: some View {
        let followWallpaperWidth = viewModel.language == .zhHans ? CGFloat(80) : CGFloat(116)
        let lightWidth = CGFloat(56)
        let darkWidth = CGFloat(56)

        return SettingsPillSegmentedControl(
            options: [
                SettingsPillSegmentOption(id: StatusBarAppearanceMode.followWallpaper.id, title: settingsAppearanceFollowWallpaper),
                SettingsPillSegmentOption(id: StatusBarAppearanceMode.light.id, title: settingsAppearanceLight),
                SettingsPillSegmentOption(id: StatusBarAppearanceMode.dark.id, title: settingsAppearanceDark)
            ],
            selection: viewModel.statusBarAppearanceMode.id,
            backgroundColor: Color.white.opacity(0.15),
            selectedFillColor: Color.white.opacity(0.80),
            selectedTextColor: Color.black,
            textColor: Color.white.opacity(0.80),
            segmentWidths: [
                StatusBarAppearanceMode.followWallpaper.id: followWallpaperWidth,
                StatusBarAppearanceMode.light.id: lightWidth,
                StatusBarAppearanceMode.dark.id: darkWidth
            ]
        ) { newValue in
            if let mode = StatusBarAppearanceMode.allCases.first(where: { $0.id == newValue }) {
                viewModel.setStatusBarAppearanceMode(mode)
            }
        }
        .frame(width: followWallpaperWidth + lightWidth + darkWidth, height: 24)
    }

    var backgroundRefreshSegmentControl: some View {
        SettingsPillSegmentedControl(
            options: [
                SettingsPillSegmentOption(id: ResourceMode.background3Minutes.id, title: viewModel.localizedText("3分钟", "3m")),
                SettingsPillSegmentOption(id: ResourceMode.background5Minutes.id, title: viewModel.localizedText("5分钟", "5m")),
                SettingsPillSegmentOption(id: ResourceMode.background10Minutes.id, title: viewModel.localizedText("10分钟", "10m")),
                SettingsPillSegmentOption(id: ResourceMode.background15Minutes.id, title: viewModel.localizedText("15分钟", "15m"))
            ],
            selection: viewModel.resourceMode.id,
            backgroundColor: Color.white.opacity(0.15),
            selectedFillColor: Color.white.opacity(0.80),
            selectedTextColor: Color.black,
            textColor: Color.white.opacity(0.80),
            segmentWidths: [
                ResourceMode.background3Minutes.id: 58,
                ResourceMode.background5Minutes.id: 58,
                ResourceMode.background10Minutes.id: 64,
                ResourceMode.background15Minutes.id: 64
            ]
        ) { newValue in
            if let mode = ResourceMode.allCases.first(where: { $0.id == newValue }) {
                viewModel.setResourceMode(mode)
            }
        }
        .frame(width: 244, height: 24)
    }

    var statusBarDisplayStyleSegmentControl: some View {
        SettingsPillSegmentedControl(
            options: [
                SettingsPillSegmentOption(id: StatusBarDisplayStyle.iconPercent.id, title: settingsStatusBarStyleIconPercent),
                SettingsPillSegmentOption(id: StatusBarDisplayStyle.barNamePercent.id, title: settingsStatusBarStyleBarNamePercent)
            ],
            selection: viewModel.statusBarDisplayStyle.id,
            backgroundColor: Color.white.opacity(0.15),
            selectedFillColor: Color.white.opacity(0.82),
            selectedTextColor: Color.black.opacity(0.88),
            textColor: Color.white.opacity(0.78)
        ) { newValue in
            if let style = StatusBarDisplayStyle.allCases.first(where: { $0.id == newValue }) {
                viewModel.setStatusBarDisplayStyle(style)
            }
        }
        .frame(width: 180, height: 24)
    }

    var refreshIntervalSegmentControl: some View {
        SettingsPillSegmentedControl(
            options: [
                SettingsPillSegmentOption(id: 15, title: viewModel.localizedText("15秒", "15s")),
                SettingsPillSegmentOption(id: 30, title: viewModel.localizedText("30秒", "30s")),
                SettingsPillSegmentOption(id: 60, title: viewModel.localizedText("1分钟", "1m")),
                SettingsPillSegmentOption(id: 300, title: viewModel.localizedText("5分钟", "5m"))
            ],
            selection: viewModel.globalRefreshIntervalSeconds,
            backgroundColor: Color.white.opacity(0.15),
            selectedFillColor: Color.white.opacity(0.80),
            selectedTextColor: Color.black,
            textColor: Color.white.opacity(0.80),
            segmentWidths: [
                15: 57,
                30: 59,
                60: 61,
                300: 64
            ]
        ) { newValue in
            viewModel.setGlobalRefreshIntervalSeconds(newValue)
        }
        .frame(width: 241, height: 24)
    }

    @ViewBuilder
    var statusBarDisplayStylePreview: some View {
        switch viewModel.statusBarDisplayStyle {
        case .iconPercent:
            statusBarDisplayStylePreviewIconPercent
        case .barNamePercent:
            statusBarDisplayStylePreviewBarNamePercent
        }
    }

    var statusBarPreviewCardHeight: CGFloat { 64 }

    var statusBarDisplayStylePreviewIconPercent: some View {
        let items: [(icon: String, value: String)] = [
            ("menu_codex_icon", "78%"),
            ("menu_claude_icon", "53%"),
            ("menu_kimi_icon", "96%")
        ]
        return ZStack(alignment: .leading) {
            SettingsSmoothedRoundedRectangle(cornerRadius: 12)
                .fill(settingsUsesLightAppearance ? Color(hex: 0xF4F5F7) : Color.black)
            SettingsSmoothedRoundedRectangle(cornerRadius: 12)
                .stroke(settingsRowStrokeColor, lineWidth: 1)

            HStack(spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 4) {
                        if let image = themedBundledImage(named: item.icon) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .opacity(0.8)
                        }
                        Text(item.value)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(settingsBodyColor)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 16)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 16, alignment: .leading)
            .padding(.horizontal, 24)
        }
        .frame(height: statusBarPreviewCardHeight, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    var statusBarDisplayStylePreviewBarNamePercent: some View {
        let items: [(name: String, value: String, percent: CGFloat)] = [
            ("Codex", "78%", 78),
            ("Claude", "100%", 100),
            ("Kimi", "10%", 10)
        ]
        return ZStack(alignment: .leading) {
            SettingsSmoothedRoundedRectangle(cornerRadius: 12)
                .fill(settingsUsesLightAppearance ? Color(hex: 0xF4F5F7) : Color.black)
            SettingsSmoothedRoundedRectangle(cornerRadius: 12)
                .stroke(settingsRowStrokeColor, lineWidth: 1)

            HStack(spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            SettingsSmoothedRoundedRectangle(cornerRadius: 3)
                                .fill(settingsQuotaTrackColor)
                                .frame(width: 10, height: 20)
                            SettingsSmoothedRoundedRectangle(cornerRadius: 2)
                                .fill(settingsUsesLightAppearance ? Color.black.opacity(0.72) : Color.white.opacity(0.8))
                                .frame(width: 6, height: max(0, round(16 * item.percent / 100)))
                                .offset(y: -2)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(settingsHintColor)
                                .lineLimit(1)
                            Text(item.value)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(settingsBodyColor)
                                .lineLimit(1)
                        }
                        .offset(y: 1)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 20)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 20, alignment: .leading)
            .offset(y: 1)
            .padding(.horizontal, 24)
        }
        .frame(height: statusBarPreviewCardHeight, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    var languageSegmentControl: some View {
        SettingsPillSegmentedControl(
            options: [
                SettingsPillSegmentOption(id: AppLanguage.zhHans.id, title: viewModel.text(.chinese)),
                SettingsPillSegmentOption(id: AppLanguage.en.id, title: viewModel.text(.english))
            ],
            selection: viewModel.language.id,
            backgroundColor: Color.white.opacity(0.15),
            selectedFillColor: Color.white.opacity(0.80),
            selectedTextColor: Color.black,
            textColor: Color.white.opacity(0.80),
            segmentWidths: [
                AppLanguage.zhHans.id: 80,
                AppLanguage.en.id: 73
            ]
        ) { newValue in
            if let language = AppLanguage.allCases.first(where: { $0.id == newValue }) {
                viewModel.setLanguage(language)
            }
        }
        .frame(width: 153, height: 24)
    }

    var settingsLanguageTitle: String {
        viewModel.language == .zhHans ? "选择语言" : viewModel.text(.language)
    }

    var settingsLaunchTitle: String {
        viewModel.language == .zhHans ? "开机启动" : viewModel.text(.launchAtLogin)
    }

    var settingsLaunchHint: String {
        viewModel.language == .zhHans
            ? "开启后会把 oh-myusage 注册为登录项。建议安装到“应用程序”后再启用"
            : viewModel.text(.launchAtLoginHint)
    }

    var settingsRefreshIntervalTitle: String {
        viewModel.localizedText("前台刷新", "Foreground Refresh")
    }

    var settingsRefreshIntervalHint: String {
        viewModel.localizedText(
            "菜单栏当前展示的服务按此频率刷新。",
            "Providers shown in the menu bar refresh at this interval."
        )
    }

    var settingsBackgroundRefreshTitle: String {
        viewModel.localizedText("后台刷新", "Background Refresh")
    }

    var settingsBackgroundRefreshHint: String {
        viewModel.localizedText(
            "未显示在菜单栏的服务按此频率刷新。",
            "Providers hidden from the menu bar refresh at this interval."
        )
    }

    var settingsStatusBarMultiUsageTitle: String {
        viewModel.localizedText("多模展示", "Multi-Model Display")
    }

    var settingsStatusBarMultiUsageHint: String {
        viewModel.localizedText(
            "开启后菜单栏展示多个模型监控，过多的展示可能挤压菜单栏空间",
            "Show multiple monitored models in the menu bar; too many items may crowd the menu bar."
        )
    }

    var settingsStatusBarDisplayStyleTitle: String {
        viewModel.text(.statusBarDisplayStyle)
    }

    var settingsAppearanceModeTitle: String {
        viewModel.text(.statusBarAppearanceMode)
    }

    var settingsAppearanceFollowWallpaper: String {
        viewModel.localizedText("跟随壁纸", "Follow Wallpaper")
    }

    var settingsAppearanceDark: String {
        viewModel.text(.statusBarAppearanceDark)
    }

    var settingsAppearanceModeHint: String {
        viewModel.localizedText(
            "根据壁纸自动选择清晰易读的显示外观",
            "Automatically picks a readable appearance from the wallpaper."
        )
    }

    var settingsAppearanceLight: String {
        viewModel.text(.statusBarAppearanceLight)
    }

    var settingsStatusBarStyleIconPercent: String {
        viewModel.text(.statusBarStyleIconPercent)
    }

    var settingsStatusBarStyleBarNamePercent: String {
        viewModel.text(.statusBarStyleBarNamePercent)
    }

    func settingsDetailControlRow<Control: View>(
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(settingsLabelFont)
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)
                .frame(width: settingsDetailLabelWidth, alignment: .leading)

            control()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }

    func settingsGeneralControlRow<Control: View>(
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(1)
                .frame(width: settingsGeneralLabelWidth, alignment: .leading)

            control()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }

    func settingsMenuBarControlRow<Control: View>(
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 16) {
            settingsMenuBarLabel(title)

            control()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }

    func settingsMenuBarLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.80))
            .lineLimit(1)
            .frame(width: settingsMenuBarLabelWidth, alignment: .leading)
    }

    func menuBarStyleCard<Preview: View>(
        title: String,
        selected: Bool,
        @ViewBuilder preview: () -> Preview,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 24) {
                preview()
                    .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .center)

                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(selected ? 0.8 : 0.15), lineWidth: 1.5)
                            .frame(width: 12, height: 12)

                        if selected {
                            Circle()
                                .fill(Color.white.opacity(0.8))
                                .frame(width: 8, height: 8)
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(title)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(width: 240, height: 102)
            .background(Color.clear)
            .contentShape(Rectangle())
            .overlay(
                SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(selected ? 0.8 : 0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var iconPercentPreview: some View {
        HStack(spacing: 8) {
            iconPercentPreviewMetric(iconName: "menu_codex_icon", value: "78%")
            previewSeparator
            iconPercentPreviewMetric(iconName: "menu_claude_icon", value: "53%")
            previewSeparator
            iconPercentPreviewMetric(iconName: "menu_kimi_icon", value: "96%")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    func iconPercentPreviewMetric(iconName: String, value: String) -> some View {
        HStack(spacing: 4) {
            if let image = themedBundledImage(named: iconName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .opacity(0.8)
            }

            Text(value)
                .font(AppFonts.numeric(size: 12, fallbackWeight: .bold))
                .foregroundStyle(Color.white.opacity(0.80))
        }
        .frame(height: 16)
        .fixedSize(horizontal: true, vertical: false)
    }

    var barNamePercentPreview: some View {
        HStack(spacing: 8) {
            barNamePreviewMetric(title: "Codex", value: "78%", percent: 0.78)
            previewSeparator
            barNamePreviewMetric(title: "Claude", value: "100%", percent: 1.0)
            previewSeparator
            barNamePreviewMetric(title: "Kimi", value: "10%", percent: 0.10)
        }
    }

    var previewSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.4))
            .frame(width: 1, height: 8)
    }

    func barNamePreviewMetric(title: String, value: String, percent: CGFloat) -> some View {
        HStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                SettingsSmoothedRoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 8, height: 18)

                SettingsSmoothedRoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 6, height: max(2, round(16 * percent)))
                    .padding(.bottom, 1)
            }
            .frame(width: 8, height: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.78))
                Text(value)
                    .font(AppFonts.numeric(size: 10, fallbackWeight: .bold))
                    .foregroundStyle(Color.white.opacity(0.80))
            }
        }
        .frame(height: 18)
        .fixedSize(horizontal: true, vertical: false)
    }
}
