import Foundation
import OhMyUsageDomain

extension ProviderModule {
    static let kimi = ProviderModule(
        type: .kimi,
        metadata: ProviderTypeMetadata(
            displayName: "Kimi",
            iconName: "menu_kimi_icon",
            fallbackSystemIcon: "moon.stars.fill",
            supportsLocalUsageHistory: true,
            supportsOfficialBearerCredentialInput: true,
            planTypeDisplayStyle: .kimi
        ),
        defaultBaseURL: "https://api.kimi.com",
        defaults: .official(
            id: "kimi-official",
            name: "Kimi",
            pollIntervalSec: 60,
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/kimi/coding-api-key"
            )
        ),
        // Official API usage (1) with a legacy GetUsages fallback (1) via
        // KimiSmartProvider; the legacy path may read browser tokens as a
        // fallback, not as a requirement.
        fetchPlan: ProviderFetchPlan(
            providerType: .kimi,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, dependencies in
            KimiSmartProvider(
                descriptor: descriptor,
                keychain: dependencies.keychain,
                browserCookieService: dependencies.kimiCookieService
            )
        }
    )

    /// Moonshot 开放平台按量付费余额（api.moonshot.cn），与 Kimi 订阅额度独立配置。
    static let kimiBalance = ProviderModule(
        type: .kimiBalance,
        metadata: ProviderTypeMetadata(
            displayName: "Kimi (API)",
            iconName: "menu_kimi_icon",
            fallbackSystemIcon: "moon.stars.fill",
            preferredMetricCount: 1,
            supportsOfficialBearerCredentialInput: true,
            isPureBalance: true,
            planTypeDisplayStyle: nil
        ),
        defaultBaseURL: "https://api.moonshot.cn",
        defaults: .official(
            id: "kimi-balance-official",
            name: "Kimi (API)",
            pollIntervalSec: 300,
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: MoonshotBalanceProvider.balanceKeychainAccount
            )
        ),
        // 1 request to api.moonshot.cn/v1/users/me/balance; balance changes
        // slowly so both TTLs are longer (catalog poll 300).
        fetchPlan: ProviderFetchPlan(
            providerType: .kimiBalance,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, dependencies in
            MoonshotBalanceProvider(descriptor: descriptor, keychain: dependencies.keychain)
        }
    )
}
