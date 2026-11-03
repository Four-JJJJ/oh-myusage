import AppKit
import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    var dividerLine: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: SettingsVisualTokens.Menu.dividerHeight)
    }

    var enabledSidebarProviders: [ProviderDescriptor] {
        sidebarProviders.filter(\.enabled)
    }

    var disabledSidebarProviders: [ProviderDescriptor] {
        sidebarProviders.filter { !$0.enabled }
    }

    var orderedEnabledSidebarProviders: [ProviderDescriptor] {
        let enabledProviders = enabledSidebarProviders
        guard let previewIDs = navigationState.reorderPreviewProviderIDs else { return enabledProviders }

        let providerByID = Dictionary(uniqueKeysWithValues: enabledProviders.map { ($0.id, $0) })
        let ordered = previewIDs.compactMap { providerByID[$0] }
        let missing = enabledProviders.filter { !previewIDs.contains($0.id) }
        return ordered + missing
    }

    var sidebarProviders: [ProviderDescriptor] {
        let providers = viewModel.config.providers.filter { provider in
            switch navigationState.selectedGroup {
            case .official:
                return provider.family == .official || provider.isOfficialRelayProvider
            case .thirdParty:
                return provider.family == .thirdParty && !provider.isOfficialRelayProvider
            }
        }
        return providers.filter(\.enabled) + providers.filter { !$0.enabled }
    }

    var selectedFamily: ProviderFamily {
        switch navigationState.selectedGroup {
        case .official:
            return .official
        case .thirdParty:
            return .thirdParty
        }
    }

    var selectedProvider: ProviderDescriptor? {
        guard let selectedProviderID = navigationState.selectedProviderID else { return nil }
        return sidebarProviders.first(where: { $0.id == selectedProviderID })
    }

    func syncSelection() {
        let ids = sidebarProviders.map(\.id)
        guard !ids.isEmpty else {
            navigationState.selectedProviderID = nil
            return
        }
        if let selectedProviderID = navigationState.selectedProviderID, ids.contains(selectedProviderID) {
            return
        }
        self.navigationState.selectedProviderID = ids.first
    }

    func sidebarDisplayName(for provider: ProviderDescriptor) -> String {
        SettingsProviderSidebarPresenter.displayName(for: provider)
    }

    func iconName(for provider: ProviderDescriptor) -> String {
        ProviderDefinitionRegistry.definition(for: provider).iconName
    }

    func fallbackIcon(for provider: ProviderDescriptor) -> String {
        ProviderDefinitionRegistry.definition(for: provider).fallbackSystemIcon
    }

    @ViewBuilder
    func providerIcon(for provider: ProviderDescriptor, size: CGFloat) -> some View {
        if let image = themedBundledImage(named: iconName(for: provider)) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackIcon(for: provider))
                .resizable()
                .scaledToFit()
                .foregroundStyle(settingsBodyColor)
                .frame(width: size, height: size)
        }
    }

    func themedBundledImage(named name: String) -> NSImage? {
        if settingsUsesLightAppearance,
           let darkImage = bundledImage(named: "\(name)_dark") {
            return darkImage
        }
        return bundledImage(named: name)
    }

    func bundledImage(named name: String) -> NSImage? {
        if let pngURL = Bundle.module.url(forResource: name, withExtension: "png"),
           let pngImage = NSImage(contentsOf: pngURL) {
            return pngImage
        }
        if let svgURL = Bundle.module.url(forResource: name, withExtension: "svg"),
           let svgImage = NSImage(contentsOf: svgURL) {
            return svgImage
        }
        return nil
    }

    func seedInputsFromConfig() {
        for provider in viewModel.config.providers {
            relayEditorDraft.seed(from: provider)
            officialEditorDraft.seed(from: provider)
        }

        for profile in viewModel.codexProfilesForSettings() {
            let key = profile.slotID.rawValue
            if profileDraftState.codexProfileJSONInputs[key] == nil {
                profileDraftState.codexProfileJSONInputs[key] = profile.authJSON
            }
        }

        for profile in viewModel.claudeProfilesForSettings() {
            let key = profile.slotID.rawValue
            if profileDraftState.claudeProfileJSONInputs[key] == nil {
                profileDraftState.claudeProfileJSONInputs[key] = profile.credentialsJSON ?? ""
            }
            if profileDraftState.claudeProfileConfigDirInputs[key] == nil {
                profileDraftState.claudeProfileConfigDirInputs[key] = profile.configDir ?? ""
            }
        }
    }
}
