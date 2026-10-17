import AppKit

/// Event-driven compatibility guard for restored blank SwiftUI Settings windows.
/// The AppKit entry point no longer creates a Settings scene, so there is no
/// reason to poll the window list while the application is idle.
@MainActor
final class SettingsScenePhantomWindowGuard {
    static let shared = SettingsScenePhantomWindowGuard()

    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    var registeredObserverCount: Int { observers.count }

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let center = NotificationCenter.default

        // Any window that becomes key/main is checked immediately, regardless
        // of when or why it appeared.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { notification in
                    guard let window = notification.object as? NSWindow else { return }
                    MainActor.assumeIsolated {
                        Self.dismissIfPhantom(window)
                    }
                }
            )
        }

        // Policy flips and re-activations can spawn the phantom without any
        // window notification, so sweep the whole window list as well.
        observers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    Self.performSweep()
                }
            }
        )

        // Catch restored windows present before observation starts. Later windows
        // are covered by activation/key/main notifications and the controller's
        // existing finite activation-policy sweeps.
        Self.performSweep()
    }

    private static func dismissIfPhantom(_ window: NSWindow) {
        guard isPhantomWindow(window) else { return }
        // Defer the close so we never tear down a window in the middle of its
        // own notification delivery.
        DispatchQueue.main.async {
            window.close()
        }
    }

    @MainActor
    private static func performSweep() {
        guard let app = NSApp else { return }
        for window in app.windows {
            dismissIfPhantom(window)
        }
    }

    private static func isPhantomWindow(_ window: NSWindow) -> Bool {
        let controller = SettingsWindowController.shared
        return SettingsSceneWindowPolicy.isPhantomWindow(
            window,
            ownedWindow: controller.ownedWindow,
            settingsHostingController: controller.settingsHostingController
        )
    }
}
