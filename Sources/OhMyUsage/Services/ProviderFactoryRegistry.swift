import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

struct ProviderFactoryRegistry {
    struct Dependencies {
        let keychain: any TokenCredentialStoring
        let kimiCookieService: any KimiBrowserCookieDetecting
        let browserCookieService: any BrowserCookieDetecting
        let browserCredentialService: any BrowserCredentialProviding
    }

    typealias Maker = (ProviderDescriptor, Dependencies) -> UsageProvider

    private let makers: [ProviderType: Maker]

    init(makers: [ProviderType: Maker] = Self.makeDefaultMakers()) {
        self.makers = makers
        precondition(
            Set(makers.keys) == Set(ProviderType.allCases),
            "ProviderFactoryRegistry must register every ProviderType"
        )
    }

    var registeredProviderTypes: Set<ProviderType> {
        Set(makers.keys)
    }

    func makeProvider(
        for descriptor: ProviderDescriptor,
        dependencies: Dependencies
    ) -> UsageProvider {
        guard let maker = makers[descriptor.type] else {
            preconditionFailure("Missing provider maker for \(descriptor.type)")
        }
        return maker(descriptor, dependencies)
    }

    /// One maker per `ProviderModule` (`Providers/Modules/ProviderModule+*.swift`).
    private static func makeDefaultMakers() -> [ProviderType: Maker] {
        Dictionary(
            ProviderModuleRegistry.allModules.map { module in
                (module.type, module.makeProvider as Maker)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
