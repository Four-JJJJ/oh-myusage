import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let copilot = ProviderModule(
        type: .copilot,
        metadata: ProviderTypeMetadata(
            displayName: "GitHub Copilot",
            iconName: "menu_github_copilot_icon",
            fallbackSystemIcon: "chevron.left.forwardslash.chevron.right"
        ),
        defaultBaseURL: "https://api.github.com",
        defaults: .official(
            id: "copilot-official",
            name: "GitHub Copilot",
            pollIntervalSec: 60,
            auth: .none
        ),
        // 1 request to api.github.com/copilot_internal/user; token resolved
        // locally (env/keychain/gh CLI).
        fetchPlan: ProviderFetchPlan(
            providerType: .copilot,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            CopilotProvider(descriptor: descriptor, shell: DefaultShellCommandRunner())
        }
    )
}
