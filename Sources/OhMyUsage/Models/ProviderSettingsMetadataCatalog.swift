import Foundation
import OhMyUsageDomain

enum ProviderSettingsMetadataCatalog {
    static func settingsSpec(for provider: ProviderDescriptor) -> ProviderSettingsSpec {
        ProviderSettingsSpec(
            providerType: provider.type,
            supportedSourceModes: supportedOfficialSourceModes(for: provider),
            supportedWebModes: supportedOfficialWebModes(for: provider),
            credentialFields: credentialFields(for: provider),
            showsQuotaDisplayPreference: provider.family == .official,
            showsTraeValueDisplayMode: provider.type == .trae
        )
    }

    static func supportedOfficialSourceModes(for provider: ProviderDescriptor) -> [OfficialSourceMode] {
        guard provider.family == .official else { return [] }
        return typeMetadata(for: provider.type).supportedSourceModes
    }

    static func supportedOfficialWebModes(for provider: ProviderDescriptor) -> [OfficialWebMode] {
        guard provider.family == .official else { return [] }
        return typeMetadata(for: provider.type).supportedWebModes
    }

    static func supportsOfficialBearerCredentialInput(for provider: ProviderDescriptor) -> Bool {
        guard provider.family == .official else { return false }
        guard provider.auth.kind == .bearer else { return false }
        return typeMetadata(for: provider.type).supportsOfficialBearerCredentialInput
    }

    private static func credentialFields(for provider: ProviderDescriptor) -> [CredentialFieldSpec] {
        guard provider.family == .official else { return [] }
        if provider.type == .opencodeGo {
            return [
                CredentialFieldSpec(kind: .opencodeWorkspaceID, storageTarget: .providerToken, requiresExplicitSave: true),
                CredentialFieldSpec(kind: .opencodeManualCookie, storageTarget: .officialManualCookie, requiresExplicitSave: true)
            ]
        }
        if provider.type == .trae {
            return [
                CredentialFieldSpec(kind: .traeAuthorization, storageTarget: .providerToken, requiresExplicitSave: true)
            ]
        }
        if supportsOfficialBearerCredentialInput(for: provider) {
            let autoImport: CredentialAutoImportCapability? =
                (provider.type == .zai || provider.type == .zaiBalance) ? .claudeCodeConfig : nil
            return [
                CredentialFieldSpec(
                    kind: .bearerToken,
                    storageTarget: .providerToken,
                    requiresExplicitSave: true,
                    autoImport: autoImport
                )
            ]
        }
        if provider.supportsOfficialManualCookieInput {
            return [
                CredentialFieldSpec(kind: .manualCookie, storageTarget: .officialManualCookie, requiresExplicitSave: true)
            ]
        }
        return []
    }

    private static func typeMetadata(for type: ProviderType) -> ProviderTypeMetadata {
        ProviderTypeMetadataCatalog.metadata(for: type)
    }
}
