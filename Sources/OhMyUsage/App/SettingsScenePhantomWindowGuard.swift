import AppKit

/// Permanently watches for the blank SwiftUI `Settings { EmptyView() }` scene
/// window and closes it whenever it appears — not only while the custom
/// settings window is being shown.
///
/// The phantom can materialize at arbitrary times: launch-time window
/// restoration, asynchronous scene creation after the activation policy flips
/// to `.regular`, app re-activation, or a re-created scene after the policy
/// flips back and forth. Fixed one-shot sweeps inside
/// `SettingsWindowController.show()` and event-driven checks miss those cases,
/// so this guard stays registered for the whole app lifetime and additionally
/// runs a low-frequency poll that closes any matching window no matter when it
/// appeared.
@MainActor
final class SettingsScenePhantomWindowGuard {
    static let shared = SettingsScenePhantomWindowGuard()

    /// How often the low-frequency poll sweeps the window list.
    private static let pollInterval: TimeInterval = 0.75

    private var observers: [NSObjectProtocol] = []
    private var sweepTimer: Timer?
    private var isStarted = false

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

        // The phantom can appear without any of the above events (e.g. window
        // restoration finishing long after launch), so keep polling the whole
        // window list for the app's lifetime.
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { _ in
            MainActor.assumeIsolated {
                Self.performSweep()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer

        // Catch anything that already appeared before the timer's first tick.
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
