import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let zai = ProviderModule(
        type: .zai,
        metadata: ProviderTypeMetadata(
            displayName: "Z.ai",
            iconName: "menu_zai_icon",
            fallbackSystemIcon: "z.square.fill",
            supportsOfficialBearerCredentialInput: true,
            planTypeDisplayStyle: .verbatim
        ),
        defaultBaseURL: "https://api.z.ai",
        defaults: .official(
            id: "zai-official",
            name: "Z.ai",
            pollIntervalSec: 60,
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: ZaiProvider.codingPlanKeychainAccount
            )
        ),
        // Coding Plan quota (1) + optional subscription/list (1, must not hide
        // quota per plan §8.4). Mirror retry can double the worst case.
        fetchPlan: ProviderFetchPlan(
            providerType: .zai,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: makeZaiProvider
    )

    /// 智谱开放平台按量付费余额（bigmodel.cn），与 Coding Plan 额度独立配置。
    static let zaiBalance = ProviderModule(
        type: .zaiBalance,
        metadata: ProviderTypeMetadata(
            displayName: "Z.ai (API)",
            iconName: "menu_zai_icon",
            fallbackSystemIcon: "z.square.fill",
            preferredMetricCount: 1,
            supportsOfficialBearerCredentialInput: true,
            isPureBalance: true,
            planTypeDisplayStyle: nil
        ),
        // 按量付费余额走国内开放平台；国际站同构，改 Base URL 即可切换。
        defaultBaseURL: "https://open.bigmodel.cn",
        defaults: .official(
            id: "zai-balance-official",
            name: "Z.ai (API)",
            pollIntervalSec: 300,
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: ZaiProvider.balanceKeychainAccount
            )
        ),
        // 1 request to /api/biz/account/query-customer-account-report; balance
        // changes slowly so both TTLs are longer (catalog poll 300).
        fetchPlan: ProviderFetchPlan(
            providerType: .zaiBalance,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: makeZaiProvider
    )

    private static let makeZaiProvider: Maker = { descriptor, dependencies in
        ZaiProvider(
            descriptor: descriptor,
            keychain: dependencies.keychain,
            localJSONReader: DefaultLocalJSONFileReader()
        )
    }
}
