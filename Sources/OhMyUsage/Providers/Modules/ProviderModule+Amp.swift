import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let amp = ProviderModule(
        type: .amp,
        metadata: ProviderTypeMetadata(
            displayName: "Amp",
            iconName: "menu_amp_icon",
            fallbackSystemIcon: "bolt.fill",
            planTypeDisplayStyle: .verbatim
        ),
        defaultBaseURL: "https://ampcode.com",
        defaults: .official(
            id: "amp-official",
            name: "Amp",
            pollIntervalSec: 60,
            auth: .none
        ),
        // 1 request to ampcode.com/api/internal; key from local secrets.json.
        fetchPlan: ProviderFetchPlan(
            providerType: .amp,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            AmpProvider(descriptor: descriptor, localJSONReader: DefaultLocalJSONFileReader())
        }
    )
}
