import Foundation
import XCTest

final class ArchitectureBoundaryTests: XCTestCase {
    func testProviderPresentationAndSettingsUseCentralMetadataCatalog() throws {
        let files = [
            "Sources/OhMyUsage/Services/ProviderPresentationRegistry.swift",
            "Sources/OhMyUsage/Models/ProviderSettingsSpec.swift"
        ]

        let rootURL = packageRepositoryRootURL()
        for file in files {
            let fileURL = rootURL.appendingPathComponent(file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(
                source.contains("switch provider.type") || source.contains("switch type"),
                "\(file) should route provider metadata decisions through ProviderMetadataCatalog"
            )
        }
    }
}
