import Foundation
import OhMyUsageDomain

/// The per-`ProviderType` facts that used to be spread across several catalogs
/// and registries, gathered in one value so that adding a provider means adding
/// one module file plus one `ProviderModuleRegistry.allModules` entry.
///
/// A module owns:
/// - `metadata`: display name, icons, capability flags and presentation constants
///   (read through `ProviderTypeMetadataCatalog`);
/// - `defaultBaseURL` / `defaultOfficialConfig`: the official defaults used by
///   `OfficialProviderDefaultCatalog` and descriptor normalization;
/// - `defaults`: the descriptors listed in `AppConfig.default`
///   (read through `ProviderDefaultCatalog`);
/// - `fetchPlan`: request-cost policy (read through `ProviderFetchPlanRegistry`);
/// - `makeProvider`: runtime construction (read through `ProviderFactoryRegistry`);
/// - `migrateLegacyOfficialConfig`: optional provider-specific legacy config fix-up
///   applied by `ProviderDescriptorNormalizer`.
///
/// Logic that genuinely differs per provider (parsing, placeholder metric
/// localization, account switching) stays in the provider or presenter that owns it.
struct ProviderModule: Sendable {
    typealias Maker = @Sendable (ProviderDescriptor, ProviderFactoryRegistry.Dependencies) -> UsageProvider
    typealias OfficialConfigMigration = @Sendable (inout OfficialProviderConfig) -> Void

    let type: ProviderType
    let metadata: ProviderTypeMetadata
    let defaultBaseURL: String
    let defaultOfficialConfig: OfficialProviderConfig
    let defaults: ProviderModuleDefaults
    let fetchPlan: ProviderFetchPlan
    let makeProvider: Maker
    let migrateLegacyOfficialConfig: OfficialConfigMigration?

    init(
        type: ProviderType,
        metadata: ProviderTypeMetadata,
        defaultBaseURL: String,
        defaultOfficialConfig: OfficialProviderConfig = ProviderModule.standardOfficialConfig,
        defaults: ProviderModuleDefaults,
        fetchPlan: ProviderFetchPlan,
        makeProvider: @escaping Maker,
        migrateLegacyOfficialConfig: OfficialConfigMigration? = nil
    ) {
        self.type = type
        self.metadata = metadata
        self.defaultBaseURL = defaultBaseURL
        self.defaultOfficialConfig = defaultOfficialConfig
        self.defaults = defaults
        self.fetchPlan = fetchPlan
        self.makeProvider = makeProvider
        self.migrateLegacyOfficialConfig = migrateLegacyOfficialConfig
    }

    /// Official config shared by API/local providers without a web session.
    static let standardOfficialConfig = OfficialProviderConfig(
        sourceMode: .auto,
        webMode: .disabled,
        manualCookieAccount: nil,
        autoDiscoveryEnabled: true
    )

    /// Alert threshold used by every built-in official provider default.
    static let officialDefaultThreshold = AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true)

    /// Descriptors this module contributes to `AppConfig.default`, in listing order.
    func defaultDescriptors() -> [ProviderDescriptor] {
        switch defaults {
        case .none:
            return []
        case let .official(id, name, pollIntervalSec, auth):
            return [officialDescriptor(id: id, name: name, pollIntervalSec: pollIntervalSec, auth: auth)]
        case let .custom(makeDescriptors):
            return makeDescriptors()
        }
    }

    /// The single built-in official descriptor, when the module declares one.
    func officialDefaultDescriptor() -> ProviderDescriptor? {
        guard case let .official(id, name, pollIntervalSec, auth) = defaults else { return nil }
        return officialDescriptor(id: id, name: name, pollIntervalSec: pollIntervalSec, auth: auth)
    }

    private func officialDescriptor(
        id: String,
        name: String,
        pollIntervalSec: Int,
        auth: AuthConfig
    ) -> ProviderDescriptor {
        ProviderDescriptor(
            id: id,
            name: name,
            family: .official,
            type: type,
            enabled: false,
            pollIntervalSec: pollIntervalSec,
            threshold: Self.officialDefaultThreshold,
            auth: auth,
            baseURL: defaultBaseURL,
            officialConfig: defaultOfficialConfig
        )
    }
}

/// How a module contributes to the built-in default provider list.
enum ProviderModuleDefaults: Sendable {
    /// Not listed in `AppConfig.default` (legacy relay aliases).
    case none
    /// One disabled official descriptor built from the module's base URL and official config.
    case official(id: String, name: String, pollIntervalSec: Int, auth: AuthConfig)
    /// Custom construction, e.g. the official relay sites driven by relay metadata.
    case custom(@Sendable () -> [ProviderDescriptor])
}
