import Foundation
import OhMyUsageDomain

extension ProviderModule {
    static let ollamaCloud = ProviderModule(
        type: .ollamaCloud,
        metadata: ProviderTypeMetadata(
            displayName: "Ollama Cloud",
            iconName: "menu_ollama_icon",
            fallbackSystemIcon: "link",
            supportedSourceModes: ProviderTypeMetadata.webSourceModes,
            supportedWebModes: ProviderTypeMetadata.importableWebModes,
            titlesSessionQuotaAsSession: true
        ),
        defaultBaseURL: "https://ollama.com",
        defaultOfficialConfig: OfficialProviderConfig(
            sourceMode: .auto,
            webMode: .autoImport,
            manualCookieAccount: "official/ollama/session-cookie",
            autoDiscoveryEnabled: true
        ),
        defaults: .official(
            id: "ollama-cloud-official",
            name: "Ollama Cloud",
            pollIntervalSec: 60,
            auth: .none
        ),
        // Web session only: 1 request for the settings HTML. Cookie comes from
        // the stored manual credential or browser auto-import, so browser access
        // is required for a live snapshot; web-only providers use longer TTLs
        // (plan §8.4) to keep console session traffic low.
        fetchPlan: ProviderFetchPlan(
            providerType: .ollamaCloud,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: true,
            requiresBrowserAccess: true
        ),
        makeProvider: { descriptor, dependencies in
            OllamaCloudProvider(
                descriptor: descriptor,
                keychain: dependencies.keychain,
                browserCookieService: dependencies.browserCookieService
            )
        }
    )
}
