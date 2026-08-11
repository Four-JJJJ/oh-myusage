import Foundation
import OhMyUsageDomain

enum RelayIconMetadataCatalog {
    static func iconOverrideName(for provider: ProviderDescriptor) -> String? {
        guard provider.type == .relay || provider.type == .open || provider.type == .dragon else {
            return nil
        }

        let adapterID = provider.relayConfig?.adapterID ?? provider.relayManifest?.id ?? ""
        if let iconName = OfficialRelayMetadataCatalog.metadata(forAdapterID: adapterID)?.iconName {
            return iconName
        }
        if let iconName = OfficialRelayMetadataCatalog.metadata(forProviderID: provider.id)?.iconName {
            return iconName
        }
        let baseURL = provider.relayConfig?.baseURL ?? provider.baseURL ?? ""
        if let iconName = OfficialRelayMetadataCatalog.metadata(forBaseURL: baseURL)?.iconName {
            return iconName
        }

        // Official catalog covers known adapter / provider / baseURL icons.
        // Keep no parallel string heuristics for moonshot/kimi/deepseek/mimo/minimax.
        return nil
    }
}
