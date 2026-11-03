import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension ProviderModule {
    static let gemini = ProviderModule(
        type: .gemini,
        metadata: ProviderTypeMetadata(
            displayName: "Gemini",
            iconName: "menu_gemini_icon",
            fallbackSystemIcon: "sparkles",
            supportsLocalUsageHistory: true
        ),
        defaultBaseURL: "https://cloudcode-pa.googleapis.com",
        defaults: .official(
            id: "gemini-official",
            name: "Official Gemini",
            pollIntervalSec: 60,
            auth: .none
        ),
        // loadCodeAssist + retrieveUserQuota are the two required requests
        // (plan §8.4); project-name resolution adds a rare third. Project/plan
        // context from loadCodeAssist is cacheable metadata.
        fetchPlan: ProviderFetchPlan(
            providerType: .gemini,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, dependencies in
            // doc 8.4：OAuth refresh 成功后的新 token 必须持久化到 vault，
            // 否则每次轮询都会重复刷新并丢弃结果（请求放大）。
            GeminiProvider(
                descriptor: descriptor,
                shell: DefaultShellCommandRunner(),
                keychain: dependencies.keychain
            )
        }
    )
}
