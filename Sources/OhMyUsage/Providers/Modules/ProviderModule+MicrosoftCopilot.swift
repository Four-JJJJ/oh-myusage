import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let microsoftCopilot = ProviderModule(
        type: .microsoftCopilot,
        metadata: ProviderTypeMetadata(
            displayName: "Microsoft Copilot",
            iconName: "menu_microsoft_copilot_icon",
            fallbackSystemIcon: "building.2.crop.circle",
            planTypeDisplayStyle: .verbatim
        ),
        defaultBaseURL: "https://graph.microsoft.com",
        defaults: .official(
            id: "microsoft-copilot-official",
            name: "Microsoft Copilot",
            pollIntervalSec: 120,
            auth: .none
        ),
        // Two parallel Graph report requests (D7 + D30); token resolved locally.
        fetchPlan: ProviderFetchPlan(
            providerType: .microsoftCopilot,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            MicrosoftCopilotProvider(descriptor: descriptor, shell: DefaultShellCommandRunner())
        }
    )
}
