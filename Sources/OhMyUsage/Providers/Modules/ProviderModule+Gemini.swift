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
            supportsLocalUsageHistory: true,
            supportedSourceModes: ProviderTypeMetadata.localAndWebSourceModes,
            supportedWebModes: ProviderTypeMetadata.importableWebModes
        ),
        defaultBaseURL: "https://cloudcode-pa.googleapis.com",
        defaultOfficialConfig: OfficialProviderConfig(
            sourceMode: .auto,
            webMode: .autoImport,
            manualCookieAccount: GeminiProvider.manualCookieAccount,
            autoDiscoveryEnabled: true
        ),
        defaults: .official(
            id: "gemini-official",
            name: "Official Gemini",
            pollIntervalSec: 60,
            auth: .none
        ),
        // loadCodeAssist + retrieveUserQuota are the two required requests on
        // the CLI/API path (plan §8.4); the Gemini web session path issues 1
        // persisted GraphQL query (`UsagePageQuery`).
        fetchPlan: ProviderFetchPlan(
            providerType: .gemini,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        makeProvider: { descriptor, dependencies in
            // doc 8.4：OAuth refresh 成功后的新 token 必须持久化到 vault，
            // 同时注入 browserCookieService 以支持 gemini.google.com/usage 网页额度。
            GeminiProvider(
                descriptor: descriptor,
                shell: DefaultShellCommandRunner(),
                keychain: dependencies.keychain,
                browserCookieService: dependencies.browserCookieService
            )
        }
    )
}
