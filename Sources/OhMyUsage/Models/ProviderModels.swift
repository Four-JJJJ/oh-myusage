import Foundation
import OhMyUsageDomain

struct ProviderDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var family: ProviderFamily
    var type: ProviderType
    var enabled: Bool
    var pollIntervalSec: Int
    var threshold: AlertRule
    var auth: AuthConfig
    var showInMenuBar: Bool?
    var baseURL: String?
    var officialConfig: OfficialProviderConfig?
    var relayConfig: RelayProviderConfig?
    // Legacy decode-only relay config. Current relay providers use relayConfig.
    var openConfig: OpenProviderConfig?
    var kimiConfig: KimiProviderConfig?

    init(
        id: String,
        name: String,
        family: ProviderFamily = .thirdParty,
        type: ProviderType,
        enabled: Bool,
        pollIntervalSec: Int,
        threshold: AlertRule,
        auth: AuthConfig,
        showInMenuBar: Bool? = nil,
        baseURL: String? = nil,
        officialConfig: OfficialProviderConfig? = nil,
        relayConfig: RelayProviderConfig? = nil,
        openConfig: OpenProviderConfig? = nil,
        kimiConfig: KimiProviderConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.type = type
        self.enabled = enabled
        self.pollIntervalSec = pollIntervalSec
        self.threshold = threshold
        self.auth = auth
        self.showInMenuBar = showInMenuBar
        self.baseURL = baseURL
        self.officialConfig = officialConfig
        self.relayConfig = relayConfig
        self.openConfig = openConfig
        self.kimiConfig = kimiConfig
    }
}

extension ProviderDescriptor {
    var showsInMenuBar: Bool {
        showInMenuBar ?? true
    }

    var isRelay: Bool {
        switch type {
        case .relay, .open, .dragon:
            return true
        case .codex, .claude, .gemini, .copilot, .microsoftCopilot, .zai, .zaiBalance, .amp, .cursor, .jetbrains, .kiro, .windsurf, .kimi, .kimiBalance, .grok, .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo:
            return false
        }
    }

}
