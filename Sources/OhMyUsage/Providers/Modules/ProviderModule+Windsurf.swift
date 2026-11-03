import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let windsurf = ProviderModule(
        type: .windsurf,
        metadata: ProviderTypeMetadata(
            displayName: "Windsurf",
            iconName: "menu_windsurf_icon",
            fallbackSystemIcon: "wind"
        ),
        defaultBaseURL: "https://server.codeium.com",
        defaults: .official(
            id: "windsurf-official",
            name: "Windsurf",
            pollIntervalSec: 60,
            auth: .none
        ),
        // 1 request to GetUserStatus; API key from local state.vscdb.
        fetchPlan: ProviderFetchPlan(
            providerType: .windsurf,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            WindsurfProvider(descriptor: descriptor, sqlite: DefaultSQLiteShell())
        }
    )
}
