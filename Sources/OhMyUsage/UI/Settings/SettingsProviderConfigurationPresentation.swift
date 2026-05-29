import Foundation

enum SettingsProviderConfigurationSectionKind: Equatable {
    case official
    case relay
}

enum SettingsProviderConfigurationSectionPresenter {
    static func sectionKind(for provider: ProviderDescriptor) -> SettingsProviderConfigurationSectionKind {
        provider.isRelay ? .relay : .official
    }
}
