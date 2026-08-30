import Foundation
import OhMyUsageDomain

enum OfficialProviderDefaultCatalog {
    static func codex() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "codex-official",
            name: "Official Codex",
            family: .official,
            type: .codex,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .localCodex),
            baseURL: baseURL(for: .codex),
            officialConfig: config(for: .codex)
        )
    }

    static func claude() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "claude-official",
            name: "Official Claude",
            family: .official,
            type: .claude,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .claude),
            officialConfig: config(for: .claude)
        )
    }

    static func gemini() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "gemini-official",
            name: "Official Gemini",
            family: .official,
            type: .gemini,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .gemini),
            officialConfig: config(for: .gemini)
        )
    }

    static func copilot() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "copilot-official",
            name: "GitHub Copilot",
            family: .official,
            type: .copilot,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .copilot),
            officialConfig: config(for: .copilot)
        )
    }

    static func microsoftCopilot() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "microsoft-copilot-official",
            name: "Microsoft Copilot",
            family: .official,
            type: .microsoftCopilot,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .microsoftCopilot),
            officialConfig: config(for: .microsoftCopilot)
        )
    }

    static func zai() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "zai-official",
            name: "Z.ai",
            family: .official,
            type: .zai,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: ZaiProvider.codingPlanKeychainAccount
            ),
            baseURL: baseURL(for: .zai),
            officialConfig: config(for: .zai)
        )
    }

    /// 智谱开放平台按量付费余额（bigmodel.cn），与 Coding Plan 额度独立配置。
    static func zaiBalance() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "zai-balance-official",
            name: "Z.ai (API)",
            family: .official,
            type: .zaiBalance,
            enabled: false,
            pollIntervalSec: 300,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: ZaiProvider.balanceKeychainAccount
            ),
            baseURL: baseURL(for: .zaiBalance),
            officialConfig: config(for: .zaiBalance)
        )
    }

    static func amp() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "amp-official",
            name: "Amp",
            family: .official,
            type: .amp,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .amp),
            officialConfig: config(for: .amp)
        )
    }

    static func cursor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "cursor-official",
            name: "Cursor",
            family: .official,
            type: .cursor,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .cursor),
            officialConfig: config(for: .cursor)
        )
    }

    static func jetBrains() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "jetbrains-official",
            name: "JetBrains AI Assistant",
            family: .official,
            type: .jetbrains,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .jetbrains),
            officialConfig: config(for: .jetbrains)
        )
    }

    static func kiro() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "kiro-official",
            name: "Kiro",
            family: .official,
            type: .kiro,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .kiro),
            officialConfig: config(for: .kiro)
        )
    }

    static func windsurf() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "windsurf-official",
            name: "Windsurf",
            family: .official,
            type: .windsurf,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .windsurf),
            officialConfig: config(for: .windsurf)
        )
    }

    static func kimi() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "kimi-official",
            name: "Kimi",
            family: .official,
            type: .kimi,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/kimi/coding-api-key"
            ),
            baseURL: baseURL(for: .kimi),
            officialConfig: config(for: .kimi)
        )
    }

    /// Moonshot 开放平台按量付费余额（api.moonshot.cn），与 Kimi 订阅额度独立配置。
    static func kimiBalance() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "kimi-balance-official",
            name: "Kimi (API)",
            family: .official,
            type: .kimiBalance,
            enabled: false,
            pollIntervalSec: 300,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: MoonshotBalanceProvider.balanceKeychainAccount
            ),
            baseURL: baseURL(for: .kimiBalance),
            officialConfig: config(for: .kimiBalance)
        )
    }

    static func grok() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "grok-official",
            name: "Grok",
            family: .official,
            type: .grok,
            enabled: false,
            pollIntervalSec: 120,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .grok),
            officialConfig: config(for: .grok)
        )
    }

    static func qwen() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "qwen-official",
            name: "Qwen",
            family: .official,
            type: .qwen,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .qwen),
            officialConfig: config(for: .qwen)
        )
    }

    /// 千问AI平台按量付费余额（platform.qianwenai.com），与 Coding Plan 额度独立配置。
    static func qwenBalance() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "qwen-balance-official",
            name: "Qwen (API)",
            family: .official,
            type: .qwenBalance,
            enabled: false,
            pollIntervalSec: 300,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .qwenBalance),
            officialConfig: config(for: .qwenBalance)
        )
    }

    static func trae() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "trae-official",
            name: "Trae SOLO",
            family: .official,
            type: .trae,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/trae/cloud-ide-jwt"
            ),
            baseURL: baseURL(for: .trae),
            officialConfig: config(for: .trae)
        )
    }

    static func openRouterCredits() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "openrouter-credits-official",
            name: "OpenRouter Credits",
            family: .official,
            type: .openrouterCredits,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/openrouter/credits-api-key"
            ),
            baseURL: baseURL(for: .openrouterCredits),
            officialConfig: config(for: .openrouterCredits)
        )
    }

    static func openRouterAPI() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "openrouter-api-official",
            name: "OpenRouter API",
            family: .official,
            type: .openrouterAPI,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/openrouter/api-key"
            ),
            baseURL: baseURL(for: .openrouterAPI),
            officialConfig: config(for: .openrouterAPI)
        )
    }

    static func ollamaCloud() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "ollama-cloud-official",
            name: "Ollama Cloud",
            family: .official,
            type: .ollamaCloud,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            baseURL: baseURL(for: .ollamaCloud),
            officialConfig: config(for: .ollamaCloud)
        )
    }

    static func openCodeGo() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "opencode-go-official",
            name: "OpenCode Go",
            family: .official,
            type: .opencodeGo,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(
                kind: .none,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "official/opencode-go/workspace-id"
            ),
            baseURL: baseURL(for: .opencodeGo),
            officialConfig: config(for: .opencodeGo)
        )
    }

    static func baseURL(for type: ProviderType) -> String {
        switch type {
        case .codex:
            return "https://chatgpt.com"
        case .claude:
            return "https://claude.ai"
        case .gemini:
            return "https://cloudcode-pa.googleapis.com"
        case .copilot:
            return "https://api.github.com"
        case .microsoftCopilot:
            return "https://graph.microsoft.com"
        case .zai:
            return "https://api.z.ai"
        case .zaiBalance:
            // 按量付费余额走国内开放平台；国际站同构，改 Base URL 即可切换。
            return "https://open.bigmodel.cn"
        case .amp:
            return "https://ampcode.com"
        case .cursor:
            return "https://api2.cursor.sh"
        case .jetbrains:
            return "file://jetbrains-local"
        case .kiro:
            return "cli://kiro-cli"
        case .windsurf:
            return "https://server.codeium.com"
        case .kimi:
            return "https://api.kimi.com"
        case .kimiBalance:
            return "https://api.moonshot.cn"
        case .grok:
            return "https://cli-chat-proxy.grok.com"
        case .trae:
            return "https://api-sg-central.trae.ai"
        case .openrouterCredits, .openrouterAPI:
            return "https://openrouter.ai/api/v1"
        case .ollamaCloud:
            return "https://ollama.com"
        case .opencodeGo:
            return "https://opencode.ai"
        case .qwen, .qwenBalance:
            return "https://platform.qianwenai.com"
        case .relay, .open, .dragon:
            return ""
        }
    }

    static func config(for type: ProviderType) -> OfficialProviderConfig {
        switch type {
        case .codex:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: "official/codex/cookie-header",
                oauthAccountImportEnabled: true,
                autoDiscoveryEnabled: true
            )
        case .claude:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: "official/claude/cookie-header",
                oauthAccountImportEnabled: false,
                autoDiscoveryEnabled: true,
                quotaDisplayMode: .used
            )
        case .gemini, .copilot, .microsoftCopilot, .zai, .zaiBalance, .amp, .cursor, .jetbrains, .kiro, .windsurf, .kimi, .kimiBalance, .grok,
             .openrouterCredits, .openrouterAPI:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true
            )
        case .trae:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .disabled,
                manualCookieAccount: nil,
                autoDiscoveryEnabled: true,
                traeValueDisplayMode: .percent
            )
        case .ollamaCloud:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: "official/ollama/session-cookie",
                autoDiscoveryEnabled: true
            )
        case .opencodeGo:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: "official/opencode-go/auth-cookie",
                autoDiscoveryEnabled: true
            )
        case .qwen, .qwenBalance:
            return OfficialProviderConfig(
                sourceMode: .auto,
                webMode: .autoImport,
                manualCookieAccount: QwenProvider.manualCookieAccount,
                autoDiscoveryEnabled: true
            )
        case .relay, .open, .dragon:
            return OfficialProviderConfig()
        }
    }

    static func kimiConfig(auth: AuthConfig) -> KimiProviderConfig {
        KimiProviderConfig(
            authMode: .auto,
            manualTokenAccount: auth.keychainAccount ?? "kimi.com/kimi-auth-manual",
            autoCookieEnabled: true,
            browserOrder: [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]
        )
    }
}
