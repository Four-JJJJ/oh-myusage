import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let cursor = ProviderModule(
        type: .cursor,
        metadata: ProviderTypeMetadata(
            displayName: "Cursor",
            iconName: "menu_cursor_icon",
            fallbackSystemIcon: "cursorarrow.rays",
            supportsLocalUsageHistory: true,
            planTypeDisplayStyle: .cursor
        ),
        defaultBaseURL: "https://api2.cursor.sh",
        defaults: .official(
            id: "cursor-official",
            name: "Cursor",
            pollIntervalSec: 60,
            auth: .none
        ),
        // 1 request to cursor.com/api/usage-summary; auth token from local
        // state.vscdb, refresh adds at most one token request.
        fetchPlan: ProviderFetchPlan(
            providerType: .cursor,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            CursorProvider(descriptor: descriptor, sqlite: DefaultSQLiteShell())
        }
    )
}
