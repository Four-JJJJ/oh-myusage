import AppKit

/// Identifies the blank SwiftUI `Settings { EmptyView() }` scene window that macOS
/// materializes when a menu-bar app switches to `.regular` activation policy.
enum SettingsSceneWindowPolicy {
    /// Delays (in seconds) for repeated phantom sweeps. The SwiftUI Settings
    /// scene window materializes asynchronously after the activation policy
    /// flips or during launch restoration, and the exact timing varies by
    /// macOS version — a single next-runloop pass is not reliable.
    static let sweepDelays: [TimeInterval] = [0, 0.3, 1.0, 2.5]

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

    /// Whether a window is a phantom SwiftUI Settings scene. A window counts
    /// as a phantom iff it is not our custom settings window, its title matches
    /// the scene ("oh-myusage Settings"), and its content is not the real
    /// settings UI. The content check is the decisive signal: the phantom hosts
    /// an empty SwiftUI view controller, never our `hostingController`.
    static func isPhantomWindow(
        _ window: NSWindow,
        ownedWindow: NSWindow?,
        settingsHostingController: NSViewController?
    ) -> Bool {
        guard window !== ownedWindow else { return false }
        guard window.title.localizedCaseInsensitiveContains("Settings") else { return false }
        return window.contentViewController !== settingsHostingController
    }

    @MainActor
    static func dismissPhantomWindows(keeping keptWindow: NSWindow?) {
        // `NSApp` may not exist yet (unit-test host, early launch before
        // NSApplication is created) — treat that as "no windows to sweep".
        guard let app = NSApp else { return }
        for window in app.windows {
            let shouldClose = shouldDismiss(
                title: window.title,
                titleVisibility: window.titleVisibility,
                isKeptWindow: window === keptWindow
            )
            guard shouldClose else { continue }
            window.close()
        }
    }

    /// Runs one sweep immediately and repeats it after each delay in
    /// `sweepDelays`, so a phantom materialized late (restoration, async scene
    /// creation after the policy flip) is still closed.
    @MainActor
    static func schedulePhantomSweeps(keeping keptWindow: NSWindow?) {
        for delay in sweepDelays {
            if delay <= 0 {
                dismissPhantomWindows(keeping: keptWindow)
                continue
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak keptWindow] in
                dismissPhantomWindows(keeping: keptWindow)
            }
        }
    }
}
