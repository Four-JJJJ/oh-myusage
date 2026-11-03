import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let jetbrains = ProviderModule(
        type: .jetbrains,
        metadata: ProviderTypeMetadata(
            displayName: "JetBrains",
            iconName: "menu_jetbrains_icon",
            fallbackSystemIcon: "brain.head.profile",
            planTypeDisplayStyle: nil
        ),
        defaultBaseURL: "file://jetbrains-local",
        defaults: .official(
            id: "jetbrains-official",
            name: "JetBrains AI Assistant",
            pollIntervalSec: 120,
            auth: .none
        ),
        // Local XML parsing only; no network requests.
        fetchPlan: ProviderFetchPlan(
            providerType: .jetbrains,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 0,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            JetBrainsProvider(descriptor: descriptor, localJSONReader: DefaultLocalJSONFileReader())
        }
    )
}
