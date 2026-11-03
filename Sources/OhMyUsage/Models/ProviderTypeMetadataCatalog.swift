import Foundation
import OhMyUsageDomain

struct ProviderTypeMetadata: Sendable {
    var displayName: String
    var officialDisplayName: String?
    var iconName: String
    var fallbackSystemIcon: String
    var preferredMetricCount: Int = 2
    var supportsAccountSwitching: Bool = false
    var supportsLocalUsageHistory: Bool = false
    var supportsOfficialBearerCredentialInput: Bool = false
    var supportedSourceModes: [OfficialSourceMode] = [.auto, .api]
    var supportedWebModes: [OfficialWebMode] = [.disabled]
    /// Pure money balance (no quota windows): rendered as a balance card.
    var isPureBalance: Bool = false
    /// How plan/tier names are shown; `nil` hides the plan type for this provider.
    var planTypeDisplayStyle: PlanTypeDisplayStyle? = .titleCased
    /// Titles `.session` quota windows "Session" instead of the five-hour label.
    var titlesSessionQuotaAsSession: Bool = false

    static let localAndWebSourceModes: [OfficialSourceMode] = [.auto, .api, .cli, .web]
    static let cliSourceModes: [OfficialSourceMode] = [.auto, .cli]
    static let webSourceModes: [OfficialSourceMode] = [.auto, .web]
    static let importableWebModes: [OfficialWebMode] = [.disabled, .autoImport, .manual]

    static let relay = ProviderTypeMetadata(
        displayName: "第三方中转站",
        iconName: "menu_relay_icon",
        fallbackSystemIcon: "link",
        supportedSourceModes: [],
        supportedWebModes: []
    )
}

/// Type-level metadata lookup. The metadata itself is declared by each
/// `ProviderModule` (`Sources/OhMyUsage/Providers/Modules`).
enum ProviderTypeMetadataCatalog {
    static var registeredProviderTypes: Set<ProviderType> {
        ProviderModuleRegistry.registeredProviderTypes
    }

    static var missingProviderTypes: [ProviderType] {
        ProviderType.allCases.filter { !registeredProviderTypes.contains($0) }
    }

    static func metadata(for type: ProviderType) -> ProviderTypeMetadata {
        ProviderModuleRegistry.module(for: type).metadata
    }
}
