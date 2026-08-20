import AppKit

/// AppKit entry point. The app deliberately has NO SwiftUI `Settings` scene:
/// the real settings UI is hosted by `SettingsWindowController`, and macOS
/// materializes a blank `Settings { ... }` window whenever the activation
/// policy flips to `.regular` — a phantom we could never reliably dismiss.
/// With no Settings scene at all, that phantom cannot exist.
@main
enum OhMyUsageMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppLifecycleDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
