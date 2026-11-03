import Foundation
import OhMyUsageDomain

/// The single table of `ProviderModule`s, one per `ProviderType`.
///
/// `ProviderTypeMetadataCatalog`, `OfficialProviderDefaultCatalog`,
/// `ProviderDefaultCatalog`, `ProviderFetchPlanRegistry` and
/// `ProviderFactoryRegistry` all read their per-type facts from here instead of
/// keeping their own switch or dictionary. `ProviderModuleRegistryTests` fails
/// when a `ProviderType` has no module or more than one.
enum ProviderModuleRegistry {
    /// Every module, in `AppConfig.default` listing order. The relay module sits
    /// where the official relay sites are listed; legacy relay aliases list nothing.
    static let allModules: [ProviderModule] = [
        .codex,
        .claude,
        .gemini,
        .copilot,
        .microsoftCopilot,
        .zai,
        .zaiBalance,
        .amp,
        .cursor,
        .grokBot,
        .jetbrains,
        .kiro,
        .windsurf,
        .grok,
        .kimi,
        .kimiBalance,
        .relay,
        .trae,
        .openrouterCredits,
        .openrouterAPI,
        .ollamaCloud,
        .opencodeGo,
        .qwen,
        .qwenBalance,
        .open,
        .dragon
    ]

    private static let modulesByType: [ProviderType: ProviderModule] = Dictionary(
        allModules.map { ($0.type, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static var registeredProviderTypes: Set<ProviderType> {
        Set(modulesByType.keys)
    }

    static func module(for type: ProviderType) -> ProviderModule {
        guard let module = modulesByType[type] else {
            preconditionFailure("Missing ProviderModule for \(type)")
        }
        return module
    }
}
