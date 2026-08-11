import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var activationPolicyBeforeShowingSettings: NSApplication.ActivationPolicy?
    private weak var currentViewModel: AppViewModel?

    private override init() {
        super.init()
    }

    func show(viewModel: AppViewModel) {
        currentViewModel = viewModel
        showAppInDockForSettingsWindow()

        let initialContentSize = NSSize(width: 1000, height: 720)
        let minimumContentSize = NSSize(width: 1000, height: 720)
        if window == nil {
            // 窗口基础尺寸：首次打开使用推荐尺寸，之后允许用户自由拖拽调整。
            let panel = NSWindow(
                contentRect: NSRect(origin: .zero, size: initialContentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            // 标题文案仅用于系统信息，页面视觉里隐藏。
            panel.title = "oh-myusage Settings"
            // 隐藏默认标题文字，保留 macOS 原生三色按钮区域。
            panel.titleVisibility = .hidden
            // 让标题栏区域与内容区视觉融合，三色按钮看起来“贴”在页面背景上。
            panel.titlebarAppearsTransparent = true
            panel.toolbar = nil
            // 关闭标题栏和内容区之间的系统分割线。
            panel.titlebarSeparatorStyle = .none
            // 明确清零内容边界，避免顶部出现额外横线。
            panel.setContentBorderThickness(0, for: .minY)
            // 整个窗口使用纯不透明背景。
            panel.isOpaque = true
            // 设置窗口使用独立深色样式；菜单栏外观配置不影响这里。
            SettingsWindowAppearanceResolver.apply(to: panel, usesLightAppearance: false)
            // 避免设置页列表拖拽、滑块等交互被窗口背景拖动截获。
            panel.isMovableByWindowBackground = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace]
            panel.delegate = self
            let minimumFrameSize = panel.frameRect(
                forContentRect: NSRect(origin: .zero, size: minimumContentSize)
            ).size
            panel.minSize = minimumFrameSize
            panel.setContentSize(initialContentSize)
            panel.center()
            window = panel
        }

        if let panel = window {
            applySettingsWindowAppearance(to: panel)
        }

        let rootView = AnyView(
            SettingsView(viewModel: viewModel, onDone: { [weak self] in
                self?.hideSettingsWindow()
            })
            .frame(
                minWidth: minimumContentSize.width,
                maxWidth: .infinity,
                minHeight: minimumContentSize.height,
                maxHeight: .infinity
            )
        )

        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let controller = NSHostingController(rootView: rootView)
            hostingController = controller
            window?.contentViewController = controller
        }
        ensureSingleBorderContentAppearance()

        viewModel.setSettingsWindowVisible(true)
        if let panel = window {
            // Switching to `.regular` can make SwiftUI's `Settings { EmptyView() }`
            // scene appear as a second blank "oh-myusage Settings" window.
            SettingsSceneWindowPolicy.dismissPhantomWindows(keeping: panel)
            bringSettingsWindowToFront(panel)
            clearSettingsInputFocus(in: panel)
            layoutTrafficLights(in: panel)
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self, let panel else { return }
                SettingsSceneWindowPolicy.dismissPhantomWindows(keeping: panel)
                self.bringSettingsWindowToFront(panel)
                self.clearSettingsInputFocus(in: panel)
                self.layoutTrafficLights(in: panel)
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow else { return }
        layoutTrafficLights(in: panel)
    }

    func windowWillClose(_ notification: Notification) {
        currentViewModel?.setSettingsWindowVisible(false)
        restoreActivationPolicyAfterSettingsWindow()
    }

    private func showAppInDockForSettingsWindow() {
        guard NSApp.activationPolicy() != .regular else { return }
        if activationPolicyBeforeShowingSettings == nil {
            activationPolicyBeforeShowingSettings = NSApp.activationPolicy()
        }
        NSApp.setActivationPolicy(.regular)
    }

    private func hideSettingsWindow() {
        currentViewModel?.setSettingsWindowVisible(false)
        window?.orderOut(nil)
        restoreActivationPolicyAfterSettingsWindow()
    }

    private func restoreActivationPolicyAfterSettingsWindow() {
        guard let activationPolicyBeforeShowingSettings else { return }
        NSApp.setActivationPolicy(activationPolicyBeforeShowingSettings)
        self.activationPolicyBeforeShowingSettings = nil
    }

    private func ensureSingleBorderContentAppearance() {
        guard let panel = window, let contentView = panel.contentView else { return }
        // 只保留 NSWindow 外层边界；内容视图不再额外绘制轮廓。
        contentView.wantsLayer = true
        contentView.layer?.borderWidth = 0
        contentView.layer?.cornerRadius = 0
        contentView.layer?.masksToBounds = false
    }

    private func applySettingsWindowAppearance(to panel: NSWindow) {
        SettingsWindowAppearanceResolver.apply(to: panel, usesLightAppearance: false)
    }

    private func bringSettingsWindowToFront(_ panel: NSWindow) {
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func clearSettingsInputFocus(in panel: NSWindow) {
        panel.makeFirstResponder(nil)
    }

    private func layoutTrafficLights(in panel: NSWindow) {
        guard
            let close = panel.standardWindowButton(.closeButton),
            let mini = panel.standardWindowButton(.miniaturizeButton),
            let zoom = panel.standardWindowButton(.zoomButton),
            let container = close.superview
        else {
            return
        }

        let buttonSize = close.frame.size
        let spacing: CGFloat = 6
        let leftInset: CGFloat = 14
        let topInset: CGFloat = 12
        let y = max(0, container.bounds.height - topInset - buttonSize.height)

        // 固定尺寸窗口下，系统可能把 zoom 按钮置灰；强制维持视觉可用态。
        zoom.isEnabled = true
        zoom.alphaValue = 1.0

        close.setFrameOrigin(NSPoint(x: leftInset, y: y))
        mini.setFrameOrigin(NSPoint(x: leftInset + buttonSize.width + spacing, y: y))
        zoom.setFrameOrigin(NSPoint(x: leftInset + (buttonSize.width + spacing) * 2, y: y))
    }
}
