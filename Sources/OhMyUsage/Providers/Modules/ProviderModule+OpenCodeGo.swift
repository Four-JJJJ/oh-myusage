import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let opencodeGo = ProviderModule(
        type: .opencodeGo,
        metadata: ProviderTypeMetadata(
            displayName: "OpenCode Go",
            iconName: "menu_opencode_icon",
            fallbackSystemIcon: "link",
            supportedSourceModes: ProviderTypeMetadata.webSourceModes,
            supportedWebModes: ProviderTypeMetadata.importableWebModes,
            planTypeDisplayStyle: nil
        ),
        defaultBaseURL: "https://opencode.ai",
        defaultOfficialConfig: OfficialProviderConfig(
            sourceMode: .auto,
            webMode: .autoImport,
            manualCookieAccount: "official/opencode-go/auth-cookie",
            autoDiscoveryEnabled: true
        ),
        defaults: .official(
            id: "opencode-go-official",
            name: "OpenCode Go",
            pollIntervalSec: 60,
            auth: AuthConfig(
                kind: .none,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/opencode-go/workspace-id"
            )
        ),
        // Web-first with local sqlite fallback: 1 remote usage request; manual
        // cookie is primary and browser import only runs on interactive force
        // refresh, so browser access is not required.
        fetchPlan: ProviderFetchPlan(
            providerType: .opencodeGo,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, dependencies in
            OpenCodeGoProvider(
                descriptor: descriptor,
                keychain: dependencies.keychain,
                browserCookieService: dependencies.browserCookieService,
                sqlite: DefaultSQLiteShell()
            )
        }
    )
}
