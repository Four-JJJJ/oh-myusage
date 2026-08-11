import AppKit

/// Identifies the blank SwiftUI `Settings { EmptyView() }` scene window that macOS
/// materializes when a menu-bar app switches to `.regular` activation policy.
enum SettingsSceneWindowPolicy {
    static func shouldDismiss(
        title: String,
        titleVisibility: NSWindow.TitleVisibility,
        isKeptWindow: Bool
    ) -> Bool {
        guard !isKeptWindow else { return false }
        // Custom `SettingsWindowController` hides the title; the SwiftUI Settings
        // scene keeps the system title visible ("oh-myusage Settings").
        guard titleVisibility == .visible else { return false }
        return title.localizedCaseInsensitiveContains("Settings")
    }

    @MainActor
    static func dismissPhantomWindows(keeping keptWindow: NSWindow?) {
        for window in NSApp.windows {
            let shouldClose = shouldDismiss(
                title: window.title,
                titleVisibility: window.titleVisibility,
                isKeptWindow: window === keptWindow
            )
            guard shouldClose else { continue }
            window.close()
        }
    }
}
