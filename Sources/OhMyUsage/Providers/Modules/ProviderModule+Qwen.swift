import Foundation
import OhMyUsageDomain

extension ProviderModule {
    static let qwen = ProviderModule(
        type: .qwen,
        metadata: ProviderTypeMetadata(
            displayName: "Qwen",
            iconName: "menu_qwen_icon",
            fallbackSystemIcon: "sparkles",
            supportedSourceModes: ProviderTypeMetadata.webSourceModes,
            supportedWebModes: ProviderTypeMetadata.importableWebModes
        ),
        defaultBaseURL: qwenBaseURL,
        defaultOfficialConfig: qwenOfficialConfig,
        defaults: .official(
            id: "qwen-official",
            name: "Qwen",
            pollIntervalSec: 60,
            auth: .none
        ),
        // Web session only (no open API): user/info.json (1) + Token Plan usage
        // (1) + subscription (1) + addon/list (1). sec_token/plan metadata is
        // cached with a long TTL (plan §8.4); web-only providers use longer
        // quota TTLs to limit console session traffic.
        fetchPlan: ProviderFetchPlan(
            providerType: .qwen,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 86_400,
            estimatedRequestCount: 4,
            supportsWebOverlay: true,
            requiresBrowserAccess: true
        ),
        makeProvider: makeQwenProvider
    )

    /// 千问AI平台按量付费余额（platform.qianwenai.com），与 Coding Plan 额度独立配置。
    static let qwenBalance = ProviderModule(
        type: .qwenBalance,
        metadata: ProviderTypeMetadata(
            displayName: "Qwen (API)",
            iconName: "menu_qwen_icon",
            fallbackSystemIcon: "sparkles",
            preferredMetricCount: 1,
            supportedSourceModes: ProviderTypeMetadata.webSourceModes,
            supportedWebModes: ProviderTypeMetadata.importableWebModes,
            isPureBalance: true,
            planTypeDisplayStyle: nil
        ),
        defaultBaseURL: qwenBaseURL,
        defaultOfficialConfig: qwenOfficialConfig,
        defaults: .official(
            id: "qwen-balance-official",
            name: "Qwen (API)",
            pollIntervalSec: 300,
            auth: .none
        ),
        // Web session only: user/info.json (1) + GetBillingAccountAvailableAmount
        // (1); balance changes slowly so both TTLs are longer (catalog poll 300).
        fetchPlan: ProviderFetchPlan(
            providerType: .qwenBalance,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 86_400,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: true
        ),
        makeProvider: makeQwenProvider
    )

    private static let qwenBaseURL = "https://platform.qianwenai.com"

    private static let qwenOfficialConfig = OfficialProviderConfig(
        sourceMode: .auto,
        webMode: .autoImport,
        manualCookieAccount: QwenProvider.manualCookieAccount,
        autoDiscoveryEnabled: true
    )

    private static let makeQwenProvider: Maker = { descriptor, dependencies in
        QwenProvider(
            descriptor: descriptor,
            keychain: dependencies.keychain,
            browserCookieService: dependencies.browserCookieService
        )
    }
}
