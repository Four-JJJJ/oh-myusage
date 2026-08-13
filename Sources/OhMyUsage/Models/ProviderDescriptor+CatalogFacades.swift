import Foundation
import OhMyUsageDomain

extension ProviderDescriptor {
    // MARK: - Official / relay provider constructors (Catalog facades)

    static func defaultOfficialCodex() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.codex()
    }

    static func defaultOfficialClaude() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.claude()
    }

    static func defaultOfficialGemini() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.gemini()
    }

    static func defaultOfficialCopilot() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.copilot()
    }

    static func defaultOfficialMicrosoftCopilot() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.microsoftCopilot()
    }

    static func defaultOfficialZai() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.zai()
    }

    static func defaultOfficialAmp() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.amp()
    }

    static func defaultOfficialCursor() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.cursor()
    }

    static func defaultOfficialJetBrains() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.jetBrains()
    }

    static func defaultOfficialKiro() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.kiro()
    }

    static func defaultOfficialWindsurf() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.windsurf()
    }

    static func defaultOfficialKimi() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.kimi()
    }

    static func defaultOfficialGrok() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.grok()
    }

    static func defaultOfficialMoonshot() -> ProviderDescriptor {
        OfficialRelayProviderDefaultCatalog.moonshot()
    }

    static func defaultOfficialMiniMax() -> ProviderDescriptor {
        OfficialRelayProviderDefaultCatalog.miniMax()
    }

    static func defaultOfficialDeepSeek() -> ProviderDescriptor {
        OfficialRelayProviderDefaultCatalog.deepSeek()
    }

    static func defaultOfficialXiaomiMIMO() -> ProviderDescriptor {
        OfficialRelayProviderDefaultCatalog.xiaomiMIMO()
    }

    static func defaultOfficialTrae() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.trae()
    }

    static func defaultOfficialOpenRouterCredits() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.openRouterCredits()
    }

    static func defaultOfficialOpenRouterAPI() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.openRouterAPI()
    }

    static func defaultOfficialOllamaCloud() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.ollamaCloud()
    }

    static func defaultOfficialOpenCodeGo() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.openCodeGo()
    }

    static func defaultOpenAilinyu() -> ProviderDescriptor {
        RelayProviderDefaultCatalog.defaultOpenAilinyu()
    }

    // MARK: - Official default configuration helpers

    static func defaultOfficialBaseURL(type: ProviderType) -> String {
        OfficialProviderDefaultCatalog.baseURL(for: type)
    }

    static func defaultOfficialConfig(type: ProviderType) -> OfficialProviderConfig {
        OfficialProviderDefaultCatalog.config(for: type)
    }

    static func defaultKimiConfig(auth: AuthConfig) -> KimiProviderConfig {
        OfficialProviderDefaultCatalog.kimiConfig(auth: auth)
    }

    // MARK: - Relay default / normalize helpers

    static func makeOpenRelay(
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> ProviderDescriptor {
        RelayProviderDefaultCatalog.makeOpenRelay(
            name: name,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID,
            keychainService: keychainService
        )
    }

    static func defaultRelayConfig(
        id: String,
        baseURL: String?,
        preferredAdapterID: String? = nil,
        auth: AuthConfig = AuthConfig.none,
        legacyOpenConfig: OpenProviderConfig? = nil,
        keychainService: String = KeychainService.defaultServiceName
    ) -> RelayProviderConfig {
        RelayProviderDefaultCatalog.defaultConfig(
            id: id,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID,
            auth: auth,
            legacyOpenConfig: legacyOpenConfig,
            keychainService: keychainService
        )
    }

    static func defaultRelayBalanceAccount(
        id: String,
        baseURL: String?,
        adapterID: String
    ) -> String {
        RelayProviderDefaultCatalog.defaultBalanceAccount(
            id: id,
            baseURL: baseURL,
            adapterID: adapterID
        )
    }

    static func normalizeRelayBaseURL(_ raw: String) -> String {
        RelayProviderDefaultCatalog.normalizeBaseURL(raw)
    }
}
