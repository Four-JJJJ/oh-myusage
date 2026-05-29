import Foundation

public enum OfficialSourceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case api
    case cli
    case web

    public var id: String { rawValue }
}

public enum OfficialWebMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case disabled
    case autoImport
    case manual

    public var id: String { rawValue }
}

public enum OfficialQuotaDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case remaining
    case used

    public var id: String { rawValue }
}

public enum OfficialTraeValueDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case percent
    case amount

    public var id: String { rawValue }
}

public struct OfficialProviderConfig: Codable, Equatable, Sendable {
    public var sourceMode: OfficialSourceMode
    public var webMode: OfficialWebMode
    public var manualCookieAccount: String?
    public var oauthAccountImportEnabled: Bool?
    public var autoDiscoveryEnabled: Bool
    public var quotaDisplayMode: OfficialQuotaDisplayMode
    public var traeValueDisplayMode: OfficialTraeValueDisplayMode?
    public var showPlanTypeInMenuBar: Bool
    public var showExpirationTimeInMenuBar: Bool

    public init(
        sourceMode: OfficialSourceMode = .auto,
        webMode: OfficialWebMode = .disabled,
        manualCookieAccount: String? = nil,
        oauthAccountImportEnabled: Bool? = nil,
        autoDiscoveryEnabled: Bool = true,
        quotaDisplayMode: OfficialQuotaDisplayMode = .remaining,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil,
        showPlanTypeInMenuBar: Bool = true,
        showExpirationTimeInMenuBar: Bool = true
    ) {
        self.sourceMode = sourceMode
        self.webMode = webMode
        self.manualCookieAccount = manualCookieAccount
        self.oauthAccountImportEnabled = oauthAccountImportEnabled
        self.autoDiscoveryEnabled = autoDiscoveryEnabled
        self.quotaDisplayMode = quotaDisplayMode
        self.traeValueDisplayMode = traeValueDisplayMode
        self.showPlanTypeInMenuBar = showPlanTypeInMenuBar
        self.showExpirationTimeInMenuBar = showExpirationTimeInMenuBar
    }

    private enum CodingKeys: String, CodingKey {
        case sourceMode
        case webMode
        case manualCookieAccount
        case oauthAccountImportEnabled
        case autoDiscoveryEnabled
        case quotaDisplayMode
        case traeValueDisplayMode
        case showPlanTypeInMenuBar
        case showExpirationTimeInMenuBar
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceMode = try container.decodeIfPresent(OfficialSourceMode.self, forKey: .sourceMode) ?? .auto
        self.webMode = try container.decodeIfPresent(OfficialWebMode.self, forKey: .webMode) ?? .disabled
        self.manualCookieAccount = try container.decodeIfPresent(String.self, forKey: .manualCookieAccount)
        self.oauthAccountImportEnabled = try container.decodeIfPresent(Bool.self, forKey: .oauthAccountImportEnabled)
        self.autoDiscoveryEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoDiscoveryEnabled) ?? true
        self.quotaDisplayMode = try container.decodeIfPresent(OfficialQuotaDisplayMode.self, forKey: .quotaDisplayMode) ?? .remaining
        self.traeValueDisplayMode = try container.decodeIfPresent(OfficialTraeValueDisplayMode.self, forKey: .traeValueDisplayMode)
        self.showPlanTypeInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showPlanTypeInMenuBar) ?? true
        self.showExpirationTimeInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showExpirationTimeInMenuBar) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceMode, forKey: .sourceMode)
        try container.encode(webMode, forKey: .webMode)
        try container.encodeIfPresent(manualCookieAccount, forKey: .manualCookieAccount)
        try container.encodeIfPresent(oauthAccountImportEnabled, forKey: .oauthAccountImportEnabled)
        try container.encode(autoDiscoveryEnabled, forKey: .autoDiscoveryEnabled)
        try container.encode(quotaDisplayMode, forKey: .quotaDisplayMode)
        try container.encodeIfPresent(traeValueDisplayMode, forKey: .traeValueDisplayMode)
        try container.encode(showPlanTypeInMenuBar, forKey: .showPlanTypeInMenuBar)
        try container.encode(showExpirationTimeInMenuBar, forKey: .showExpirationTimeInMenuBar)
    }
}
