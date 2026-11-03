import Foundation
import OhMyUsageDomain

extension ProviderModule {
    static let openrouterCredits = ProviderModule(
        type: .openrouterCredits,
        metadata: ProviderTypeMetadata(
            displayName: "OpenRouter Credits",
            iconName: "menu_openrouter_icon",
            fallbackSystemIcon: "link",
            supportsOfficialBearerCredentialInput: true,
            planTypeDisplayStyle: nil
        ),
        defaultBaseURL: openRouterBaseURL,
        defaults: .official(
            id: "openrouter-credits-official",
            name: "OpenRouter Credits",
            pollIntervalSec: 60,
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/openrouter/credits-api-key"
            )
        ),
        // 1 request per OpenRouter channel; API key from keychain.
        fetchPlan: ProviderFetchPlan(
            providerType: .openrouterCredits,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: makeOpenRouterProvider
    )

    static let openrouterAPI = ProviderModule(
        type: .openrouterAPI,
        metadata: ProviderTypeMetadata(
            displayName: "OpenRouter API",
            iconName: "menu_openrouter_icon",
            fallbackSystemIcon: "link",
            supportsOfficialBearerCredentialInput: true,
            planTypeDisplayStyle: nil
        ),
        defaultBaseURL: openRouterBaseURL,
        defaults: .official(
            id: "openrouter-api-official",
            name: "OpenRouter API",
            pollIntervalSec: 60,
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/openrouter/api-key"
            )
        ),
        // 1 request per OpenRouter channel; API key from keychain.
        fetchPlan: ProviderFetchPlan(
            providerType: .openrouterAPI,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: makeOpenRouterProvider
    )

    private static let openRouterBaseURL = "https://openrouter.ai/api/v1"

    private static let makeOpenRouterProvider: Maker = { descriptor, dependencies in
        OpenRouterProvider(descriptor: descriptor, keychain: dependencies.keychain)
    }
}
