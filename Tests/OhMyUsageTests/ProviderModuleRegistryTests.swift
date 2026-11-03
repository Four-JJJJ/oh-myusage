import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class ProviderModuleRegistryTests: XCTestCase {
    func testEveryProviderTypeHasExactlyOneModule() {
        let modules = ProviderModuleRegistry.allModules
        for type in ProviderType.allCases {
            XCTAssertEqual(
                modules.filter { $0.type == type }.count,
                1,
                "\(type.rawValue) must have exactly one ProviderModule in ProviderModuleRegistry.allModules"
            )
        }
        XCTAssertEqual(modules.count, ProviderType.allCases.count, "allModules must not list extra modules")
        XCTAssertEqual(ProviderModuleRegistry.registeredProviderTypes, Set(ProviderType.allCases))
    }

    func testModuleLookupReturnsTheModuleForThatType() {
        for type in ProviderType.allCases {
            let module = ProviderModuleRegistry.module(for: type)
            XCTAssertEqual(module.type, type)
            XCTAssertEqual(module.fetchPlan.providerType, type, "\(type.rawValue) fetch plan must name its own type")
        }
    }

    func testOfficialDefaultDescriptorsAreBuiltFromTheirModule() {
        for module in ProviderModuleRegistry.allModules {
            guard let descriptor = module.officialDefaultDescriptor() else { continue }
            XCTAssertEqual(descriptor.type, module.type, descriptor.id)
            XCTAssertEqual(descriptor.family, .official, descriptor.id)
            XCTAssertFalse(descriptor.enabled, descriptor.id)
            XCTAssertEqual(descriptor.baseURL, module.defaultBaseURL, descriptor.id)
            XCTAssertEqual(descriptor.officialConfig, module.defaultOfficialConfig, descriptor.id)
            XCTAssertEqual(module.defaultDescriptors().map(\.id), [descriptor.id])
        }
    }

    func testOnlyRelayModulesListNoOfficialDefaultDescriptor() {
        let typesWithoutOfficialDefault = ProviderModuleRegistry.allModules
            .filter { $0.officialDefaultDescriptor() == nil }
            .map(\.type)
        XCTAssertEqual(Set(typesWithoutOfficialDefault), [.relay, .open, .dragon])
    }

    func testRegistriesAreDrivenByTheModuleTable() {
        XCTAssertEqual(Set(ProviderFetchPlanRegistry.defaultPlans.keys), Set(ProviderType.allCases))
        XCTAssertEqual(ProviderFactoryRegistry().registeredProviderTypes, Set(ProviderType.allCases))
        XCTAssertEqual(ProviderTypeMetadataCatalog.missingProviderTypes, [])
        for module in ProviderModuleRegistry.allModules {
            XCTAssertEqual(ProviderFetchPlanRegistry().plan(for: module.type), module.fetchPlan)
            XCTAssertEqual(
                ProviderTypeMetadataCatalog.metadata(for: module.type).displayName,
                module.metadata.displayName
            )
            XCTAssertEqual(OfficialProviderDefaultCatalog.baseURL(for: module.type), module.defaultBaseURL)
            XCTAssertEqual(OfficialProviderDefaultCatalog.config(for: module.type), module.defaultOfficialConfig)
        }
        XCTAssertEqual(
            ProviderDefaultCatalog.allDefaultProviders.map(\.id),
            ProviderModuleRegistry.allModules.flatMap { $0.defaultDescriptors() }.map(\.id)
        )
    }

    func testRegistryFilesDoNotRegrowPerTypeTables() throws {
        let rootURL = packageRepositoryRootURL()
        let files = [
            "Sources/OhMyUsage/Models/ProviderTypeMetadataCatalog.swift",
            "Sources/OhMyUsage/Models/OfficialProviderDefaultCatalog.swift",
            "Sources/OhMyUsage/Models/ProviderDefaultCatalog.swift",
            "Sources/OhMyUsage/Services/ProviderFetchPlanRegistry.swift",
            "Sources/OhMyUsage/Services/ProviderFactoryRegistry.swift"
        ]
        let caseNames = ProviderType.allCases.map { "\\.\($0)\\b" }.joined(separator: "|")
        let perTypeReference = try NSRegularExpression(pattern: caseNames)
        for file in files {
            let source = try String(contentsOf: rootURL.appendingPathComponent(file), encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            let matches = perTypeReference.matches(in: source, range: range).compactMap { match in
                Range(match.range, in: source).map { String(source[$0]) }
            }
            XCTAssertEqual(
                matches,
                [],
                "\(file) should look per-type facts up through ProviderModuleRegistry instead of naming provider types"
            )
        }
    }
}
