import Foundation
import OhMyUsageDomain

extension ProviderDescriptor {
    // MARK: - Official / relay provider constructors (Catalog facades)

    static func defaultOfficialCodex() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .codex)
    }

    static func defaultOfficialClaude() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .claude)
    }

    static func defaultOfficialGemini() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .gemini)
    }

    static func defaultOfficialCopilot() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .copilot)
    }

    static func defaultOfficialMicrosoftCopilot() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .microsoftCopilot)
    }

    static func defaultOfficialZai() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .zai)
    }

    static func defaultOfficialZaiBalance() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .zaiBalance)
    }

    static func defaultOfficialAmp() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .amp)
    }

    static func defaultOfficialCursor() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .cursor)
    }

    static func defaultOfficialGrokBot() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .grokBot)
    }

    static func defaultOfficialJetBrains() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .jetbrains)
    }

    static func defaultOfficialKiro() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .kiro)
    }

    static func defaultOfficialWindsurf() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .windsurf)
    }

    static func defaultOfficialKimi() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .kimi)
    }

    static func defaultOfficialKimiBalance() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .kimiBalance)
    }

    static func defaultOfficialGrok() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .grok)
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
        OfficialProviderDefaultCatalog.descriptor(for: .trae)
    }

    static func defaultOfficialOpenRouterCredits() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .openrouterCredits)
    }

    static func defaultOfficialOpenRouterAPI() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .openrouterAPI)
    }

    static func defaultOfficialOllamaCloud() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .ollamaCloud)
    }

    static func defaultOfficialOpenCodeGo() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .opencodeGo)
    }

    static func defaultOfficialQwen() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .qwen)
    }

    static func defaultOfficialQwenBalance() -> ProviderDescriptor {
        OfficialProviderDefaultCatalog.descriptor(for: .qwenBalance)
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
