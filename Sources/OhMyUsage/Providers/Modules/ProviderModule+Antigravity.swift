import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let antigravity = ProviderModule(
        type: .antigravity,
        metadata: ProviderTypeMetadata(
            displayName: "Antigravity",
            iconName: "menu_gemini_icon",
            fallbackSystemIcon: "sparkles",
            preferredMetricCount: 4,
            supportsLocalUsageHistory: true,
            supportedSourceModes: ProviderTypeMetadata.cliSourceModes
        ),
        defaultBaseURL: "https://antigravity.google",
        defaults: .official(
            id: "antigravity-official",
            name: "Antigravity",
            pollIntervalSec: 120,
            auth: .none
        ),
        // Uses documented `agy -p /usage --output-format json` (standalone `agy`
        // or bundled helper inside `/Applications/Gemini.app`), coalesced across providers.
        fetchPlan: ProviderFetchPlan(
            providerType: .antigravity,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            AntigravityProvider(
                descriptor: descriptor,
                shell: DefaultShellCommandRunner()
            )
        }
    )
}
