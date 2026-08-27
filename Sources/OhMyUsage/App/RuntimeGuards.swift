import AppKit
import Foundation

private enum SingleInstanceActivationBridge {
    static let distributedNotificationName = Notification.Name("com.oh-myusage.activate-existing-instance")

    @MainActor
    static func notifyExistingInstance() {
        DistributedNotificationCenter.default().postNotificationName(
            distributedNotificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

@MainActor
final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private var fd: Int32 = -1
    private let lockPath = "/tmp/com.oh-myusage.app.lock"

    private init() {}

    func acquire() -> Bool {
        if fd != -1 {
            return true
        }

        fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd != -1 else {
            return false
        }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            return true
        }

        close(fd)
        fd = -1
        return false
    }

    deinit {
        if fd != -1 {
            flock(fd, LOCK_UN)
            close(fd)
        }
    }
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var activationObserver: NSObjectProtocol?
    private let postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring = PostUpdateReleaseNotesStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app stays menu-bar only even if started from terminal context.
        applyBundledAppIcon()
        AppFonts.registerBundledFonts()
        NSApp.setActivationPolicy(.accessory)
        // 菜单栏应用没有主菜单时，⌘C/⌘V/⌘X 等快捷键没有派发路径，
        // 输入框会表现为"能输入但粘贴复制全部失效"。挂载标准编辑菜单修复。
        installGlobalKeyboardCommandMenu()

        if !SingleInstanceLock.shared.acquire() {
            SingleInstanceActivationBridge.notifyExistingInstance()
            NSApp.terminate(nil)
            return
        }

        startActivationBridgeObservation()
        SettingsScenePhantomWindowGuard.shared.start()
        let viewModel = AppViewModel()
        statusBarController = StatusBarController(viewModel: viewModel)
        presentPostUpdateReleaseNotesIfNeeded(currentVersion: viewModel.currentAppVersion)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopActivationBridgeObservation()
    }

    /// Intercept the system Settings menu / ⌘, so macOS does not show the
    /// blank SwiftUI `Settings { EmptyView() }` scene instead of our AppKit window.
    @objc
    func showSettingsWindow(_ sender: Any?) {
        statusBarController?.showSettingsWindow()
    }

    /// 给 accessory 应用挂载不可见的编辑菜单，让 ⌘C/⌘V/⌘X/⌘A 沿 responder
    /// 链派发到各文本输入框。菜单本身不会显示（无主窗口菜单栏）。
    private func installGlobalKeyboardCommandMenu() {
        guard NSApp.mainMenu == nil else { return }

        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        editItem.title = "Edit"
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // 常用窗口操作：关闭与最小化（设置窗口可 Cmd-W 关闭）
        let windowItem = NSMenuItem()
        windowItem.title = "Window"
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        statusBarController?.showSettingsWindow()
        return false
    }

    @MainActor
    private func applyBundledAppIcon() {
        AppIconImageProvider.applyApplicationIcon(size: 256)
    }

    @MainActor
    private func startActivationBridgeObservation() {
        stopActivationBridgeObservation()
        let center = DistributedNotificationCenter.default()
        activationObserver = center.addObserver(
            forName: SingleInstanceActivationBridge.distributedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                NSRunningApplication.current.activate(options: [])
                self.statusBarController?.showSettingsWindow()
            }
        }
    }

    @MainActor
    private func stopActivationBridgeObservation() {
        guard let activationObserver else { return }
        DistributedNotificationCenter.default().removeObserver(activationObserver)
        self.activationObserver = nil
    }

    @MainActor
    private func presentPostUpdateReleaseNotesIfNeeded(currentVersion: String) {
        guard let releaseNotes = postUpdateReleaseNotesStore.consumePresentationIfNeeded(
            currentVersion: currentVersion
        ) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            ReleaseNotesWindowController.shared.show(releaseNotes: releaseNotes)
        }
    }
}
