import Foundation

/// Bundled menu icon names for official providers.
///
/// Icons follow the `menu_<provider>_icon` / `menu_<provider>_icon_dark` pair used by
/// `StatusBarController` and settings sidebar rendering.
enum ProviderMenuIconCatalog {
    /// Cursor Grok Bot cloud agent. Distinct from xAI Grok CLI `menu_grok_icon`.
    static let grokBot = "menu_grokbot_icon"

    /// Icon base names that ship light/dark SVG pairs in `Resources/`.
    static let bundledLightDarkPairs: [(baseName: String, darkName: String)] = [
        (grokBot, "\(grokBot)_dark")
    ]
}
