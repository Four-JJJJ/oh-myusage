import Foundation
import OhMyUsageDomain

extension ProviderModule {
    static let codex = ProviderModule(
        type: .codex,
        metadata: ProviderTypeMetadata(
            displayName: "Codex",
            iconName: "menu_codex_icon",
            fallbackSystemIcon: "terminal.fill",
            supportsAccountSwitching: true,
            supportsLocalUsageHistory: true,
            supportedSourceModes: ProviderTypeMetadata.localAndWebSourceModes,
            supportedWebModes: ProviderTypeMetadata.importableWebModes
        ),
        defaultBaseURL: "https://chatgpt.com",
        defaultOfficialConfig: OfficialProviderConfig(
            sourceMode: .auto,
            webMode: .autoImport,
            manualCookieAccount: "official/codex/cookie-header",
            oauthAccountImportEnabled: true,
            autoDiscoveryEnabled: true
        ),
        defaults: .official(
            id: "codex-official",
            name: "Official Codex",
            pollIntervalSec: 120,
            auth: AuthConfig(kind: .localCodex)
        ),
        // OAuth usage (1 request to chatgpt.com/backend-api/wham/usage) plus the
        // web overlay usage request when a manual cookie is stored
        // (`shouldIncludeWebOverlay`). 401 adds at most one refresh + retry.
        fetchPlan: ProviderFetchPlan(
            providerType: .codex,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, dependencies in
            CodexProvider(
                descriptor: descriptor,
                keychain: dependencies.keychain,
                browserCookieService: dependencies.browserCookieService
            )
        }
    )
}
