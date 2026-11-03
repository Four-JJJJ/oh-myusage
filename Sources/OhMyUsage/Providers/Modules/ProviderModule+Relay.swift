import Foundation
import OhMyUsageDomain

extension ProviderModule {
    /// Relay sites (official relay sites and user-added third-party relays).
    static let relay = relayModule(
        type: .relay,
        // Official relay sites are listed from `OfficialRelayMetadataCatalog`
        // order; user-added relays are not part of the default list.
        defaults: .custom { OfficialRelayProviderDefaultCatalog.allDefaultProviders }
    )

    /// Legacy relay alias; normalized to `.relay` before routing.
    static let open = relayModule(type: .open, defaults: .none)

    /// Legacy relay alias; normalized to `.relay` before routing.
    static let dragon = relayModule(type: .dragon, defaults: .none)

    private static func relayModule(type: ProviderType, defaults: ProviderModuleDefaults) -> ProviderModule {
        ProviderModule(
            type: type,
            metadata: .relay,
            defaultBaseURL: "",
            defaultOfficialConfig: OfficialProviderConfig(),
            defaults: defaults,
            // Token channel (usage + optional subscription/billing usage) and
            // balance channel run as two independent channels (plan §8.4); two
            // requests is the typical full refresh. Browser credentials are a
            // recovery fallback behind Manual Preferred defaults.
            fetchPlan: ProviderFetchPlan(
                providerType: type,
                activeTTL: 120,
                backgroundTTL: 900,
                metadataTTL: 21_600,
                estimatedRequestCount: 2,
                supportsWebOverlay: true,
                requiresBrowserAccess: false
            ),
            makeProvider: { descriptor, dependencies in
                RelayProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCredentialService: dependencies.browserCredentialService
                )
            }
        )
    }
}
