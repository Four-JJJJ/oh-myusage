import Foundation
import OhMyUsageDomain

extension ProviderModule {
    static let trae = ProviderModule(
        type: .trae,
        metadata: ProviderTypeMetadata(
            displayName: "Trae SOLO",
            iconName: "menu_relay_icon",
            fallbackSystemIcon: "link",
            planTypeDisplayStyle: .trae
        ),
        defaultBaseURL: "https://api-sg-central.trae.ai",
        defaultOfficialConfig: OfficialProviderConfig(
            sourceMode: .auto,
            webMode: .disabled,
            manualCookieAccount: nil,
            autoDiscoveryEnabled: true,
            traeValueDisplayMode: .percent
        ),
        defaults: .official(
            id: "trae-official",
            name: "Trae SOLO",
            pollIntervalSec: 60,
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/trae/cloud-ide-jwt"
            )
        ),
        // 1 request to ide_user_ent_usage; keychain JWT is primary, browser
        // bearer-token candidates only participate on auth recovery.
        fetchPlan: ProviderFetchPlan(
            providerType: .trae,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, dependencies in
            TraeProvider(
                descriptor: descriptor,
                keychain: dependencies.keychain,
                browserCredentialService: dependencies.browserCredentialService
            )
        },
        migrateLegacyOfficialConfig: { official in
            // 兼容旧版 Trae：历史 quotaDisplayMode 用于“百分比/数字”开关，新版改为 traeValueDisplayMode。
            if official.traeValueDisplayMode == nil {
                official.traeValueDisplayMode = official.quotaDisplayMode == .used ? .amount : .percent
                official.quotaDisplayMode = .remaining
            }
        }
    )
}
