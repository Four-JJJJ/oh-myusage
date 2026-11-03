import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let kiro = ProviderModule(
        type: .kiro,
        metadata: ProviderTypeMetadata(
            displayName: "Kiro",
            iconName: "menu_kiro_icon",
            fallbackSystemIcon: "wand.and.stars.inverse",
            supportedSourceModes: ProviderTypeMetadata.cliSourceModes,
            planTypeDisplayStyle: nil
        ),
        defaultBaseURL: "cli://kiro-cli",
        defaults: .official(
            id: "kiro-official",
            name: "Kiro",
            pollIntervalSec: 60,
            auth: .none
        ),
        // Local kiro-cli + sqlite output only; no network requests.
        fetchPlan: ProviderFetchPlan(
            providerType: .kiro,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 0,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, _ in
            KiroProvider(
                descriptor: descriptor,
                shell: DefaultShellCommandRunner(),
                sqlite: DefaultSQLiteShell(),
                localJSONReader: DefaultLocalJSONFileReader()
            )
        }
    )
}
