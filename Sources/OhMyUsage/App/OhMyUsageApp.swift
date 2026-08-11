import AppKit
import SwiftUI

@main
struct OhMyUsageApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI.App requires at least one Scene. Prefer `Settings` over
        // `WindowGroup` so launch does not create a main window.
        // Content stays empty on purpose: the real settings UI is hosted by
        // `SettingsWindowController`. When activationPolicy becomes `.regular`,
        // macOS may still materialize this scene as a blank titled window;
        // `SettingsSceneWindowPolicy` dismisses that phantom.
        Settings {
            EmptyView()
        }
    }
}
