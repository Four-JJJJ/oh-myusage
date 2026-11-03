import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let claude = ProviderModule(
        type: .claude,
        metadata: ProviderTypeMetadata(
            displayName: "Claude",
            iconName: "menu_claude_icon",
            fallbackSystemIcon: "sparkles",
            preferredMetricCount: 4,
            supportsAccountSwitching: true,
            supportsLocalUsageHistory: true,
            supportedSourceModes: ProviderTypeMetadata.localAndWebSourceModes,
            supportedWebModes: ProviderTypeMetadata.importableWebModes
        ),
        defaultBaseURL: "https://claude.ai",
        defaultOfficialConfig: OfficialProviderConfig(
            sourceMode: .auto,
            webMode: .autoImport,
            manualCookieAccount: "official/claude/cookie-header",
            oauthAccountImportEnabled: false,
            autoDiscoveryEnabled: true,
            quotaDisplayMode: .used
        ),
        defaults: .official(
            id: "claude-official",
            name: "Official Claude",
            pollIntervalSec: 120,
            auth: .none
        ),
        // OAuth usage (1 request to api.anthropic.com/api/oauth/usage) plus web
        // overlay: 1 request via sessionKey, or organizations + usage +
        // overage_spend_limit + account (4) on the cookie path. Organization ID
        // metadata uses a long TTL (plan §8.4).
        fetchPlan: ProviderFetchPlan(
            providerType: .claude,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 86_400,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, dependencies in
            ClaudeProvider(
                descriptor: descriptor,
                keychain: dependencies.keychain,
                browserCookieService: dependencies.browserCookieService,
                shell: DefaultShellCommandRunner()
            )
        }
    )
}
