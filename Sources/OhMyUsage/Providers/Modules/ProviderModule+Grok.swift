import Foundation
import OhMyUsageDomain

extension ProviderModule {
    static let grok = ProviderModule(
        type: .grok,
        metadata: ProviderTypeMetadata(
            displayName: "Grok",
            iconName: "menu_grok_icon",
            fallbackSystemIcon: "sparkle",
            supportsLocalUsageHistory: true,
            planTypeDisplayStyle: .grok
        ),
        defaultBaseURL: "https://cli-chat-proxy.grok.com",
        defaults: .official(
            id: "grok-official",
            name: "Grok",
            pollIntervalSec: 120,
            auth: .none
        ),
        // Billing (1) + best-effort plan name (/v1/settings, 1); OAuth refresh
        // from local ~/.grok/auth.json is rare.
        fetchPlan: ProviderFetchPlan(
            providerType: .grok,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            GrokProvider(descriptor: descriptor)
        }
    )
}
