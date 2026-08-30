import Foundation

enum ProviderDefaultCatalog {
    static var allDefaultProviders: [ProviderDescriptor] {
        [
            OfficialProviderDefaultCatalog.codex(),
            OfficialProviderDefaultCatalog.claude(),
            OfficialProviderDefaultCatalog.gemini(),
            OfficialProviderDefaultCatalog.copilot(),
            OfficialProviderDefaultCatalog.microsoftCopilot(),
            OfficialProviderDefaultCatalog.zai(),
            OfficialProviderDefaultCatalog.zaiBalance(),
            OfficialProviderDefaultCatalog.amp(),
            OfficialProviderDefaultCatalog.cursor(),
            OfficialProviderDefaultCatalog.jetBrains(),
            OfficialProviderDefaultCatalog.kiro(),
            OfficialProviderDefaultCatalog.windsurf(),
            OfficialProviderDefaultCatalog.grok(),
            OfficialProviderDefaultCatalog.kimi(),
            OfficialProviderDefaultCatalog.kimiBalance()
        ]
            + OfficialRelayProviderDefaultCatalog.allDefaultProviders
            + [
                OfficialProviderDefaultCatalog.trae(),
                OfficialProviderDefaultCatalog.openRouterCredits(),
                OfficialProviderDefaultCatalog.openRouterAPI(),
                OfficialProviderDefaultCatalog.ollamaCloud(),
                OfficialProviderDefaultCatalog.openCodeGo(),
                OfficialProviderDefaultCatalog.qwen(),
                OfficialProviderDefaultCatalog.qwenBalance()
            ]
    }
}
