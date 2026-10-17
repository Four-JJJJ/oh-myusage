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

enum SettingsProviderSidebarPresenter {
    static func displayName(for provider: ProviderDescriptor) -> String {
        let name = ProviderDefinitionRegistry.definition(for: provider).displayName
        guard OfficialSettingsCategory.resolve(for: provider) == .api else { return name }
        if name.hasSuffix(" (API)") { return name }
        let baseName = name.hasSuffix(" API") ? String(name.dropLast(4)) : name
        return "\(baseName) (API)"
    }
}

enum SettingsProviderReorderPresenter {
    static func destination(providerID: String, previewIDs: [String], allEnabledIDs: [String]) -> Int? {
        let visibleIDs = Set(previewIDs)
        guard visibleIDs.count == previewIDs.count,
              let destination = previewIDs.firstIndex(of: providerID) else { return nil }
        let visibleIndices = allEnabledIDs.indices.filter { visibleIDs.contains(allEnabledIDs[$0]) }
        guard visibleIndices.count == previewIDs.count else { return nil }
        return visibleIndices[destination]
    }
}
