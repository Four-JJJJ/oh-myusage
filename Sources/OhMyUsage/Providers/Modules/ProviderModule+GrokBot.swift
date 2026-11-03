import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let grokBot = ProviderModule(
        type: .grokBot,
        metadata: ProviderTypeMetadata(
            displayName: "Grok Bot",
            iconName: "menu_grokbot_icon",
            fallbackSystemIcon: "sparkle",
            preferredMetricCount: 2,
            planTypeDisplayStyle: .grok
        ),
        defaultBaseURL: "https://api2.cursor.sh",
        defaults: .official(
            id: "grokbot-official",
            name: "Grok Bot",
            pollIntervalSec: 60,
            auth: .none
        ),
        // Sand weekly status (1) + optional current-period on-demand (1);
        // ConnectRPC may fall back to REST. Token from Grok Bot app or Cursor IDE.
        fetchPlan: ProviderFetchPlan(
            providerType: .grokBot,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            GrokBotProvider(descriptor: descriptor, sqlite: DefaultSQLiteShell())
        }
    )
}
