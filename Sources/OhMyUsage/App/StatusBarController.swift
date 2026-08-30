import OhMyUsageDomain
import AppKit
import OhMyUsageApplication
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let viewModel: AppViewModel
    private let statusItemController: StatusItemController
    private let menuPanelController: MenuPanelController
    private let statusBarAppearanceController: StatusBarAppearanceController
    private let visibleRefreshClockController = VisibleClockController()
    private var visibleRefreshTask: Task<Void, Never>?
    private let statusIconSize: CGFloat = 16
    private var providerStatusImageCache: [String: NSImage] = [:]
    private lazy var appStatusImage: NSImage? = {
        AppIconImageProvider.image(size: statusIconSize)
    }()

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.statusItemController = StatusItemController()
        self.menuPanelController = MenuPanelController()
        self.statusBarAppearanceController = StatusBarAppearanceController()
        super.init()
        configureStatusItem()
        configureMenuPanel()
        startAppearanceObservation()
        viewModel.start()
        refreshStatusDisplay()
        statusBarAppearanceController.scheduleFollowUpRefreshes(
            mode: viewModel.statusBarAppearanceMode
        ) { [weak self] in
            self?.refreshStatusDisplay()
        }
        showInitialPopoverIfNeeded()
    }

    deinit {
        visibleRefreshTask?.cancel()
    }

    private func configureStatusItem() {
        statusItemController.configure(
            target: self,
            action: #selector(togglePopover(_:))
        )
    }

    private func configureMenuPanel() {
        menuPanelController.configure(
            rootView: MenuContentView(
                viewModel: viewModel,
                onOpenSettings: { [weak self] in
                    self?.showSettingsWindowFromMenu()
                }
            )
        )
        updatePopoverContentSizeIfNeeded()
    }

    private func refreshStatusDisplay() {
        guard let button = statusItemController.button else { return }
        let foregroundStyle = resolvedForegroundStyle(for: button.window?.screen)
        statusBarAppearanceController.updateRenderedForegroundStyle(foregroundStyle)
        let entries = statusDisplayEntries(foregroundStyle: foregroundStyle)
        let didRenderStatusItem = statusItemController.render(
            entries: entries,
            style: viewModel.statusBarDisplayStyle,
            foregroundStyle: foregroundStyle,
            fallbackImage: appStatusImage
        )
        if didRenderStatusItem || menuPanelController.isShown {
            updatePopoverContentSizeIfNeeded()
        }
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        if menuPanelController.isShown {
            closeMenuPanel()
            return
        }
        guard let button = statusItemController.button else { return }
        showPopover(attachedTo: button)
    }

    private func closeMenuPanel() {
        menuPanelController.close { [weak self] in
            guard let self else { return }
            self.viewModel.setMenuPanelVisible(false)
            self.restartVisibleRefreshClock()
            self.refreshStatusDisplay()
        }
    }

    private func showSettingsWindowFromMenu() {
        if menuPanelController.isShown {
            menuPanelController.close { [weak self] in
                guard let self else { return }
                self.viewModel.setMenuPanelVisible(false)
                self.restartVisibleRefreshClock()
                self.refreshStatusDisplay()
                self.showSettingsWindow()
            }
        } else {
            showSettingsWindow()
        }
    }

    private func updatePopoverContentSizeIfNeeded() {
        menuPanelController.updateContentSizeIfNeeded(
            attachedButton: statusItemController.button
        )
    }

    private func showPopover(attachedTo button: NSStatusBarButton) {
        refreshStatusDisplay()
        menuPanelController.show(
            attachedTo: button,
            onDidShow: { [weak self] in
                guard let self else { return }
                self.viewModel.setMenuPanelVisible(true)
                self.restartVisibleRefreshClock()
            },
            onDidClose: { [weak self] in
                guard let self else { return }
                self.viewModel.setMenuPanelVisible(false)
                self.restartVisibleRefreshClock()
                self.refreshStatusDisplay()
            }
        )
    }

    private func restartVisibleRefreshClock() {
        visibleRefreshClockController.restartClockIfNeeded(
            isVisible: menuPanelController.isShown,
            existingTask: &visibleRefreshTask,
            intervalSeconds: RuntimeDiagnosticsLimits.statusBarVisibleRefreshIntervalSeconds
        ) { [weak self] _ in
            self?.refreshStatusDisplay()
        }
    }

    private func startAppearanceObservation() {
        statusBarAppearanceController.startObservation(
            onWallpaperContextDidChange: { [weak self] in
                guard let self else { return }
                self.statusBarAppearanceController.handleWallpaperContextDidChange(
                    mode: self.viewModel.statusBarAppearanceMode
                ) { [weak self] in
                    self?.refreshStatusDisplay()
                }
            },
            onScreenParametersChanged: { [weak self] in
                self?.refreshStatusDisplay()
            },
            onDisplayConfigChanged: { [weak self] in
                guard let self else { return }
                self.refreshStatusDisplay()
                self.refreshWallpaperProbeState()
            }
        )
        refreshWallpaperProbeState()
    }

    private func showInitialPopoverIfNeeded() {
        guard viewModel.shouldShowPermissionGuide else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  self.viewModel.shouldShowPermissionGuide,
                  !self.menuPanelController.isShown,
                  let button = self.statusItemController.button else { return }
            self.showPopover(attachedTo: button)
        }
    }

    private func statusDisplayEntries(
        foregroundStyle: StatusBarForegroundStyle
    ) -> [StatusBarDisplayEntry] {
        let codexActiveSnapshot = viewModel.codexSlotViewModels().first(where: { $0.isActive })?.snapshot
        let claudeDisplaySnapshot = viewModel.claudeStatusBarDisplaySnapshot()
        let sources = StatusBarDisplaySourceBuilder.displaySources(
            for: viewModel.statusBarProvidersForDisplay(),
            style: viewModel.statusBarDisplayStyle,
            providerSnapshots: viewModel.snapshots,
            codexActiveSnapshot: codexActiveSnapshot,
            claudeDisplaySnapshot: claudeDisplaySnapshot
        ) { [viewModel] providerID in
            viewModel.thirdPartyBarPercent(for: providerID)
        }
        let items = StatusBarDisplayPresenter.displayItems(
            for: sources,
            style: viewModel.statusBarDisplayStyle
        )
        return items.map { item in
            StatusBarDisplayEntry(
                icon: image(for: item.provider, foregroundStyle: foregroundStyle),
                name: item.name,
                valueText: item.valueText,
                percent: item.percent
            )
        }
    }

    nonisolated static func traePrimaryPercent(
        snapshot: UsageSnapshot,
        displaysUsedQuota: Bool = false
    ) -> Double? {
        StatusBarDisplayPresenter.traePrimaryPercent(
            snapshot: snapshot,
            displaysUsedQuota: displaysUsedQuota
        )
    }

    nonisolated static func fiveHourPercent(
        from snapshot: UsageSnapshot,
        displaysUsedQuota: Bool = false
    ) -> Double? {
        StatusBarDisplayPresenter.fiveHourPercent(
            from: snapshot,
            displaysUsedQuota: displaysUsedQuota
        )
    }

    private func resolvedForegroundStyle(for screen: NSScreen?) -> StatusBarForegroundStyle {
        statusBarAppearanceController.resolvedForegroundStyle(
            mode: viewModel.statusBarAppearanceMode,
            probe: wallpaperProbe(for: screen),
            fallbackStyle: foregroundStyleFromStatusItemAppearance()
        )
    }

    private func foregroundStyleFromStatusItemAppearance() -> StatusBarForegroundStyle? {
        guard let button = statusItemController.button else { return nil }
        let appearance = button.effectiveAppearance
        let names: [NSAppearance.Name] = [
            .darkAqua,
            .vibrantDark,
            .aqua,
            .vibrantLight
        ]
        guard let matched = appearance.bestMatch(from: names) else {
            return nil
        }
        switch matched {
        case .darkAqua, .vibrantDark:
            return .light
        case .aqua, .vibrantLight:
            return .dark
        default:
            return nil
        }
    }

    private func wallpaperProbe(for screen: NSScreen?) -> WallpaperAppearanceProbe? {
        guard viewModel.statusBarAppearanceMode == .followWallpaper else {
            return nil
        }
        guard
            let resolvedScreen = screen ?? NSScreen.main,
            let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: resolvedScreen)
        else {
            return nil
        }
        let screenID = (resolvedScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
        return WallpaperAppearanceProbe(
            screenID: screenID,
            wallpaperURL: wallpaperURL,
            horizontalCenterRatio: statusItemHorizontalCenterRatio(on: resolvedScreen)
        )
    }

    private func refreshWallpaperProbeState() {
        statusBarAppearanceController.refreshWallpaperProbeState(
            mode: viewModel.statusBarAppearanceMode,
            resolveCurrentStyle: { [weak self] in
                guard let self,
                      let button = self.statusItemController.button else {
                    return .light
                }
                return self.resolvedForegroundStyle(for: button.window?.screen)
            },
            onRefreshNeeded: { [weak self] in
                self?.refreshStatusDisplay()
            }
        )
    }

    private func statusItemHorizontalCenterRatio(on screen: NSScreen) -> Double {
        guard
            let button = statusItemController.button,
            let window = button.window
        else {
            return 0.5
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        return MenuPanelGeometryResolver.horizontalCenterRatio(
            rectOnScreen: rectOnScreen,
            screenFrame: screen.frame
        )
    }

    func showSettingsWindow() {
        SettingsWindowController.shared.show(viewModel: viewModel)
    }

    private func image(
        for provider: ProviderDescriptor?,
        foregroundStyle: StatusBarForegroundStyle
    ) -> NSImage? {
        guard let provider else {
            return appStatusImage ?? AppIconImageProvider.image(size: statusIconSize)
        }
        if let providerIcon = providerStatusImage(for: provider, foregroundStyle: foregroundStyle) {
            return providerIcon
        }
        switch provider.type {
        case .codex:
            let fallback = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex")
            fallback?.isTemplate = true
            return fallback
        case .kimi, .kimiBalance:
            let fallback = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "Kimi")
            fallback?.isTemplate = true
            return fallback
        case .relay, .open, .dragon, .claude, .gemini, .copilot, .microsoftCopilot, .zai, .zaiBalance, .amp, .cursor, .jetbrains, .kiro, .windsurf, .grok, .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo, .qwen, .qwenBalance:
            let fallback = NSImage(systemSymbolName: "globe", accessibilityDescription: "Relay")
            fallback?.isTemplate = true
            return fallback
        }
    }

    private func providerStatusImage(
        for provider: ProviderDescriptor,
        foregroundStyle: StatusBarForegroundStyle
    ) -> NSImage? {
        let baseIconName = menuIconName(for: provider)
        let candidates = iconNameCandidates(baseIconName: baseIconName, foregroundStyle: foregroundStyle)
        for iconName in candidates {
            if let cached = providerStatusImageCache[iconName] {
                return cached
            }
            if let image = bundledImage(named: iconName, ext: "png") ?? bundledImage(named: iconName, ext: "svg") {
                image.size = NSSize(width: statusIconSize, height: statusIconSize)
                image.isTemplate = false
                providerStatusImageCache[iconName] = image
                return image
            }
        }
        return nil
    }

    private func iconNameCandidates(baseIconName: String, foregroundStyle: StatusBarForegroundStyle) -> [String] {
        switch foregroundStyle {
        case .light:
            return [baseIconName]
        case .dark:
            return ["\(baseIconName)_dark", baseIconName]
        }
    }

    private func menuIconName(for provider: ProviderDescriptor) -> String {
        ProviderPresentationRegistry.iconName(for: provider)
    }

    private func bundledImage(named name: String, ext: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func bundledMainImage(named name: String, ext: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
