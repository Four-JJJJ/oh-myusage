import Foundation
import OhMyUsageDomain

struct ProviderTypeMetadata {
    var displayName: String
    var officialDisplayName: String?
    var iconName: String
    var fallbackSystemIcon: String
    var preferredMetricCount: Int = 2
    var supportsAccountSwitching: Bool = false
    var supportsLocalUsageHistory: Bool = false
    var supportsOfficialBearerCredentialInput: Bool = false
    var supportedSourceModes: [OfficialSourceMode] = [.auto, .api]
    var supportedWebModes: [OfficialWebMode] = [.disabled]
}

enum ProviderTypeMetadataCatalog {
    static var registeredProviderTypes: Set<ProviderType> {
        Set(providerTypeMetadata.keys)
    }

    static var missingProviderTypes: [ProviderType] {
        ProviderType.allCases.filter { !registeredProviderTypes.contains($0) }
    }

    static func metadata(for type: ProviderType) -> ProviderTypeMetadata {
        providerTypeMetadata[type] ?? relayMetadata
    }

    private static let localAndWebSourceModes: [OfficialSourceMode] = [.auto, .api, .cli, .web]
    private static let cliSourceModes: [OfficialSourceMode] = [.auto, .cli]
    private static let webSourceModes: [OfficialSourceMode] = [.auto, .web]
    private static let importableWebModes: [OfficialWebMode] = [.disabled, .autoImport, .manual]

    private static let relayMetadata = ProviderTypeMetadata(
        displayName: "第三方中转站",
        iconName: "menu_relay_icon",
        fallbackSystemIcon: "link",
        supportedSourceModes: [],
        supportedWebModes: []
    )

    private static let providerTypeMetadata: [ProviderType: ProviderTypeMetadata] = [
        .codex: ProviderTypeMetadata(
            displayName: "Codex",
            iconName: "menu_codex_icon",
            fallbackSystemIcon: "terminal.fill",
            supportsAccountSwitching: true,
            supportsLocalUsageHistory: true,
            supportedSourceModes: localAndWebSourceModes,
            supportedWebModes: importableWebModes
        ),
        .claude: ProviderTypeMetadata(
            displayName: "Claude",
            iconName: "menu_claude_icon",
            fallbackSystemIcon: "sparkles",
            preferredMetricCount: 4,
            supportsAccountSwitching: true,
            supportsLocalUsageHistory: true,
            supportedSourceModes: localAndWebSourceModes,
            supportedWebModes: importableWebModes
        ),
        .gemini: ProviderTypeMetadata(displayName: "Gemini", iconName: "menu_gemini_icon", fallbackSystemIcon: "sparkles"),
        .copilot: ProviderTypeMetadata(displayName: "GitHub Copilot", iconName: "menu_github_copilot_icon", fallbackSystemIcon: "chevron.left.forwardslash.chevron.right"),
        .microsoftCopilot: ProviderTypeMetadata(displayName: "Microsoft Copilot", iconName: "menu_microsoft_copilot_icon", fallbackSystemIcon: "building.2.crop.circle"),
        .zai: ProviderTypeMetadata(displayName: "Z.ai", iconName: "menu_zai_icon", fallbackSystemIcon: "z.square.fill"),
        .amp: ProviderTypeMetadata(displayName: "Amp", iconName: "menu_amp_icon", fallbackSystemIcon: "bolt.fill"),
        .cursor: ProviderTypeMetadata(displayName: "Cursor", iconName: "menu_cursor_icon", fallbackSystemIcon: "cursorarrow.rays"),
        .jetbrains: ProviderTypeMetadata(displayName: "JetBrains", iconName: "menu_jetbrains_icon", fallbackSystemIcon: "brain.head.profile"),
        .kiro: ProviderTypeMetadata(
            displayName: "Kiro",
            iconName: "menu_kiro_icon",
            fallbackSystemIcon: "wand.and.stars.inverse",
            supportedSourceModes: cliSourceModes
        ),
        .windsurf: ProviderTypeMetadata(displayName: "Windsurf", iconName: "menu_windsurf_icon", fallbackSystemIcon: "wind"),
        .kimi: ProviderTypeMetadata(
            displayName: "KIMI",
            officialDisplayName: "Kimi Coding",
            iconName: "menu_kimi_icon",
            fallbackSystemIcon: "moon.stars.fill",
            supportsLocalUsageHistory: true,
            supportsOfficialBearerCredentialInput: true
        ),
        .trae: ProviderTypeMetadata(displayName: "Trae SOLO", iconName: "menu_relay_icon", fallbackSystemIcon: "link"),
        .openrouterCredits: ProviderTypeMetadata(
            displayName: "OpenRouter Credits",
            iconName: "menu_openrouter_icon",
            fallbackSystemIcon: "link",
            supportsOfficialBearerCredentialInput: true
        ),
        .openrouterAPI: ProviderTypeMetadata(
            displayName: "OpenRouter API",
            iconName: "menu_openrouter_icon",
            fallbackSystemIcon: "link",
            supportsOfficialBearerCredentialInput: true
        ),
        .ollamaCloud: ProviderTypeMetadata(
            displayName: "Ollama Cloud",
            iconName: "menu_ollama_icon",
            fallbackSystemIcon: "link",
            supportedSourceModes: webSourceModes,
            supportedWebModes: importableWebModes
        ),
        .opencodeGo: ProviderTypeMetadata(
            displayName: "OpenCode Go",
            iconName: "menu_opencode_icon",
            fallbackSystemIcon: "link",
            supportedSourceModes: webSourceModes,
            supportedWebModes: importableWebModes
        ),
        .relay: relayMetadata,
        .open: relayMetadata,
        .dragon: relayMetadata
    ]
}
