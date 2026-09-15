import XCTest
@testable import OhMyUsage

final class RelayAdapterRegistryTests: XCTestCase {
    func testBundledManifestsIncludeRelayAdapterResources() {
        let ids = Set(RelayAdapterRegistry.shared.builtInManifests().map(\.id))

        XCTAssertTrue(ids.contains("generic-newapi"))
        XCTAssertTrue(ids.contains("generic-sub2api"))
        XCTAssertTrue(ids.contains("xiaomimimo-token-plan"))
        XCTAssertTrue(ids.contains("moonshot"))
    }

    func testBundledManifestsAreUniqueByID() {
        let ids = RelayAdapterRegistry.shared.builtInManifests().map(\.id)

        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testGenericRelaySiteTemplateIDs() {
        XCTAssertTrue(RelayAdapterRegistry.isGenericRelaySiteTemplate("generic-newapi"))
        XCTAssertTrue(RelayAdapterRegistry.isGenericRelaySiteTemplate("generic-sub2api"))
        XCTAssertFalse(RelayAdapterRegistry.isGenericRelaySiteTemplate("moonshot"))
        XCTAssertFalse(RelayAdapterRegistry.isGenericRelaySiteTemplate(nil))
    }

    func testAvailableManifestsReusesLocalDirectoryScanWithinCacheTTL() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("relay-adapter-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var enumerationCount = 0
        let registry = RelayAdapterRegistry(
            builtInManifests: [RelayAdapterRegistry.genericManifest],
            localManifestDirectoryURL: root,
            localManifestCacheTTL: 60,
            now: { Date(timeIntervalSince1970: 100) },
            localManifestEnumerator: { directory in
                enumerationCount += 1
                return FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            }
        )

        _ = registry.availableManifests()
        _ = registry.availableManifests()

        XCTAssertEqual(enumerationCount, 1)
    }
}
