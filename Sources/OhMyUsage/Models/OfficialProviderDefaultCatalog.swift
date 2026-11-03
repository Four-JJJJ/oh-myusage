import Foundation
import OhMyUsageDomain

/// Official provider defaults, read from each type's `ProviderModule`.
enum OfficialProviderDefaultCatalog {
    /// The built-in official descriptor declared by the type's module.
    static func descriptor(for type: ProviderType) -> ProviderDescriptor {
        guard let descriptor = ProviderModuleRegistry.module(for: type).officialDefaultDescriptor() else {
            preconditionFailure("ProviderModule for \(type) declares no official default descriptor")
        }
        return descriptor
    }

    static func baseURL(for type: ProviderType) -> String {
        ProviderModuleRegistry.module(for: type).defaultBaseURL
    }

    static func config(for type: ProviderType) -> OfficialProviderConfig {
        ProviderModuleRegistry.module(for: type).defaultOfficialConfig
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
