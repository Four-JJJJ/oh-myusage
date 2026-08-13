import Foundation
import OhMyUsageDomain

enum ProviderDescriptorNormalizer {
    static func normalized(_ provider: ProviderDescriptor) -> ProviderDescriptor {
        var copy = provider
        copy.auth = copy.auth.normalizedCredentialServiceName()
        if isLegacyRelayType(copy.type) {
            copy.type = .relay
        }

        switch copy.type {
        case .codex, .claude, .gemini, .copilot, .microsoftCopilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf, .grok, .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo:
            return normalizedOfficialProvider(copy)
        case .relay:
            return normalizedRelayProvider(copy, source: provider)
        case .kimi:
            return normalizedKimiProvider(copy, source: provider)
        case .open, .dragon:
            assertionFailure("Legacy relay provider types must be normalized before provider routing")
            return normalizedRelayProvider(copy, source: provider)
        }
    }

    private static func isLegacyRelayType(_ type: ProviderType) -> Bool {
        type == .open || type == .dragon
    }

    private static func normalizedOfficialProvider(_ provider: ProviderDescriptor) -> ProviderDescriptor {
        var copy = provider
        copy.family = .official
        if copy.officialConfig == nil {
            copy.officialConfig = ProviderDescriptor.defaultOfficialConfig(type: copy.type)
        } else if copy.officialConfig?.manualCookieAccount?.isEmpty ?? true {
            copy.officialConfig?.manualCookieAccount = ProviderDescriptor.defaultOfficialConfig(type: copy.type).manualCookieAccount
        }
        if copy.officialConfig?.oauthAccountImportEnabled == nil {
            copy.officialConfig?.oauthAccountImportEnabled = ProviderDescriptor.defaultOfficialConfig(type: copy.type).oauthAccountImportEnabled
        }
        if copy.type == .trae, var official = copy.officialConfig {
            // 兼容旧版 Trae：历史 quotaDisplayMode 用于“百分比/数字”开关，新版改为 traeValueDisplayMode。
            if official.traeValueDisplayMode == nil {
                official.traeValueDisplayMode = official.quotaDisplayMode == .used ? .amount : .percent
                official.quotaDisplayMode = .remaining
            }
            copy.officialConfig = official
        }
        if copy.baseURL?.isEmpty ?? true {
            copy.baseURL = ProviderDescriptor.defaultOfficialBaseURL(type: copy.type)
        }
        if copy.pollIntervalSec <= 0 {
            copy.pollIntervalSec = 60
        }
        return copy
    }

    private static func normalizedRelayProvider(
        _ provider: ProviderDescriptor,
        source: ProviderDescriptor
    ) -> ProviderDescriptor {
        var copy = provider
        let relayDescriptor = RelayProviderDescriptorModelAdapter.live
        let normalizedBaseURL = ProviderDescriptor.normalizeRelayBaseURL(copy.relayConfig?.baseURL ?? copy.baseURL ?? "")
        copy.baseURL = normalizedBaseURL
        if copy.relayConfig == nil {
            copy.relayConfig = relayDescriptor.defaultRelayConfig(
                id: source.id,
                baseURL: normalizedBaseURL,
                auth: source.auth,
                legacyOpenConfig: copy.openConfig
            )
        } else {
            copy.relayConfig = normalizedRelayConfig(
                copy.relayConfig!,
                descriptorID: source.id,
                descriptorAuth: copy.auth,
                normalizedBaseURL: normalizedBaseURL
            )
        }
        copy.family = copy.isOfficialRelayProvider ? .official : .thirdParty
        if copy.family == .official {
            copy.officialConfig = nil
        }
        copy.openConfig = nil
        if copy.pollIntervalSec <= 0 {
            copy.pollIntervalSec = source.id == "open-ailinyu" ? 120 : 60
        }
        if copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let manifest = relayDescriptor.manifest(
                for: normalizedBaseURL,
                preferredID: copy.relayConfig?.adapterID
            )
            copy.name = manifest.match.defaultDisplayName
                ?? URL(string: normalizedBaseURL)?.host
                ?? "Relay"
        }
        return copy
    }

    private static func normalizedRelayConfig(
        _ config: RelayProviderConfig,
        descriptorID: String,
        descriptorAuth: AuthConfig,
        normalizedBaseURL: String
    ) -> RelayProviderConfig {
        var relay = config
        let relayDescriptor = RelayProviderDescriptorModelAdapter.live
        relay.balanceAuth = relay.balanceAuth.normalizedCredentialServiceName()
        let originalAdapterID = relay.adapterID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowAutoMatch = originalAdapterID == nil
        let manifest = relayDescriptor.manifest(
            for: normalizedBaseURL,
            preferredID: allowAutoMatch ? nil : originalAdapterID
        )
        relay.baseURL = normalizedBaseURL
        if allowAutoMatch {
            relay.adapterID = manifest.id
            if manifest.id != "generic-newapi",
               ProviderDescriptor.looksLikeGenericDefaultOverride(relay.manualOverrides) {
                relay.manualOverrides = nil
            }
        } else {
            relay.adapterID = originalAdapterID ?? manifest.id
        }
        if relay.adapterID == "generic-newapi" {
            relay.manualOverrides = ProviderDescriptor.migrateGenericNewAPIDefaultOverride(relay.manualOverrides)
        }
        let effectiveManifest = relayDescriptor.manifest(
            for: normalizedBaseURL,
            preferredID: relay.adapterID
        )
        if relay.adapterID != "generic-newapi",
           relay.manualOverrides != nil,
           ProviderDescriptor.looksLikeTemplateDefaultOverride(relay.manualOverrides, manifest: effectiveManifest) {
            relay.manualOverrides = nil
        }
        relay.balanceAuth = relay.balanceAuth.withFallback(
            service: descriptorAuth.keychainService ?? KeychainService.defaultServiceName,
            account: relayDescriptor.defaultRelayBalanceAccount(
                id: descriptorID,
                baseURL: normalizedBaseURL,
                adapterID: relay.adapterID ?? manifest.id
            )
        )
        relay.balanceCredentialMode = relay.balanceCredentialMode ?? .manualPreferred
        return relay
    }

    private static func normalizedKimiProvider(
        _ provider: ProviderDescriptor,
        source: ProviderDescriptor
    ) -> ProviderDescriptor {
        var copy = provider
        if copy.family == .official || copy.id == "kimi-official" {
            copy.family = .official
            copy.name = "Kimi Coding"
            if copy.auth.kind == .none {
                copy.auth = OfficialProviderDefaultCatalog.kimi().auth
            }
            if copy.officialConfig == nil {
                copy.officialConfig = ProviderDescriptor.defaultOfficialConfig(type: .kimi)
            } else if copy.officialConfig?.manualCookieAccount?.isEmpty ?? true {
                copy.officialConfig?.manualCookieAccount = ProviderDescriptor.defaultOfficialConfig(type: .kimi).manualCookieAccount
            }
            if copy.baseURL?.isEmpty ?? true {
                copy.baseURL = ProviderDescriptor.defaultOfficialBaseURL(type: .kimi)
            }
            if copy.pollIntervalSec <= 0 {
                copy.pollIntervalSec = 60
            }
            copy.kimiConfig = nil
            return copy
        }

        copy.family = .thirdParty
        if copy.kimiConfig == nil {
            copy.kimiConfig = ProviderDescriptor.defaultKimiConfig(auth: source.auth)
        }
        if copy.baseURL?.isEmpty ?? true {
            copy.baseURL = "https://www.kimi.com"
        }
        return copy
    }
}
