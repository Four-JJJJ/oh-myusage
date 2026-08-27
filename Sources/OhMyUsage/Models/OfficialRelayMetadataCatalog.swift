import Foundation

struct OfficialRelayMetadata {
    var providerID: String
    var adapterAliases: Set<String>
    var defaultAdapterID: String
    var displayName: String
    var baseURL: String
    var iconName: String
    var keychainAccount: String
    /// 是否出现在默认添加列表。false 时保留元数据（图标、站点识别、旧配置兼容），
    /// 只是不再作为可添加的官方预设出现。
    var isDefaultListed: Bool = true
}

enum OfficialRelayMetadataCatalog {
    static var defaultProviderOrder: [String] {
        metadata.map(\.providerID)
    }

    static var defaultListedProviderOrder: [String] {
        metadata.filter(\.isDefaultListed).map(\.providerID)
    }

    static func metadata(forAdapterID adapterID: String) -> OfficialRelayMetadata? {
        let normalized = adapterID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return metadata.first { $0.adapterAliases.contains(normalized) }
    }

    static func metadata(forProviderID providerID: String) -> OfficialRelayMetadata? {
        let normalized = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return metadata.first { $0.providerID.lowercased() == normalized }
    }

    static func metadata(forBaseURL baseURL: String) -> OfficialRelayMetadata? {
        let normalized = ProviderDescriptor.normalizeRelayBaseURL(baseURL).lowercased()
        guard !normalized.isEmpty else { return nil }
        return metadata.first {
            ProviderDescriptor.normalizeRelayBaseURL($0.baseURL).lowercased() == normalized
        }
    }

    private static let metadata: [OfficialRelayMetadata] = [
        // Moonshot 按量余额已由官方卡「Kimi (API)」覆盖，不再默认提供中转预设；
        // 元数据保留用于图标、同站点识别与已添加用户的兼容。
        OfficialRelayMetadata(
            providerID: "moonshot-official",
            adapterAliases: ["moonshot"],
            defaultAdapterID: "moonshot",
            displayName: "Moonshot",
            baseURL: "https://platform.moonshot.cn",
            iconName: "menu_kimi_icon",
            keychainAccount: "platform.moonshot.cn/auth_token",
            isDefaultListed: false
        ),
        OfficialRelayMetadata(
            providerID: "minimax-official",
            adapterAliases: ["minimax"],
            defaultAdapterID: "minimax",
            displayName: "MiniMax",
            baseURL: "https://platform.minimaxi.com",
            iconName: "menu_minimax_icon",
            keychainAccount: "platform.minimaxi.com/system-token"
        ),
        OfficialRelayMetadata(
            providerID: "deepseek-official",
            adapterAliases: ["deepseek"],
            defaultAdapterID: "deepseek",
            displayName: "DeepSeek",
            baseURL: "https://platform.deepseek.com",
            iconName: "menu_deepseek_icon",
            keychainAccount: "platform.deepseek.com/system-token"
        ),
        OfficialRelayMetadata(
            providerID: "xiaomi-mimo-official",
            adapterAliases: ["xiaomimimo", "xiaomimimo-token-plan"],
            defaultAdapterID: "xiaomimimo-token-plan",
            displayName: "Xiaomi MIMO",
            baseURL: "https://platform.xiaomimimo.com",
            iconName: "menu_mimo_icon",
            keychainAccount: "platform.xiaomimimo.com/session-cookie"
        )
    ]
}
