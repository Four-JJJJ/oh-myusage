import Foundation
import OhMyUsageDomain

enum CredentialFieldKind: String, Equatable {
    case bearerToken
    case manualCookie
    case opencodeWorkspaceID
    case opencodeManualCookie
    case traeAuthorization
    case relayBalanceAuth
    case relayQuotaAuth
}

enum CredentialStorageTarget: Equatable {
    case providerToken
    case officialManualCookie
    /// relay 余额凭证等独立 AuthConfig 槽位
    case auth(AuthConfig)
}

/// 凭证字段文案（调用方按当前语言解析后传入）
struct CredentialFieldCopy: Equatable {
    var title: String
    var placeholder: String
    var hintLines: [String] = []
}

/// 字段级自动获取能力声明；Phase 3 把 OAuth / 本地导入 / 浏览器导入挂到该槽位
enum CredentialAutoImportCapability: String, Equatable {
    case browser
    case claudeCodeConfig
    case oauth
    case localCLI
}

struct CredentialFieldSpec: Equatable, Identifiable {
    var kind: CredentialFieldKind
    var storageTarget: CredentialStorageTarget
    var requiresExplicitSave: Bool
    var copy: CredentialFieldCopy? = nil
    var autoImport: CredentialAutoImportCapability? = nil

    var id: String { kind.rawValue }
}

struct ProviderSettingsSpec: Equatable {
    var providerType: ProviderType
    var supportedSourceModes: [OfficialSourceMode]
    var supportedWebModes: [OfficialWebMode]
    var credentialFields: [CredentialFieldSpec]
    var showsQuotaDisplayPreference: Bool
    var showsTraeValueDisplayMode: Bool

    static func resolve(for provider: ProviderDescriptor) -> ProviderSettingsSpec {
        ProviderDefinitionRegistry.settingsSpec(for: provider)
    }
}

extension ProviderDescriptor {
    var supportsOfficialBearerCredentialInput: Bool {
        ProviderDefinitionRegistry.settingsSpec(for: self).credentialFields.contains { field in
            field.kind == .bearerToken
        }
    }
}
