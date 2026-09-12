import XCTest
@testable import OhMyUsage

final class ProviderMenuIconCatalogTests: XCTestCase {
    func testGrokBotMenuIconsAreBundled() {
        XCTAssertEqual(ProviderMenuIconCatalog.grokBot, "menu_grokbot_icon")

        for pair in ProviderMenuIconCatalog.bundledLightDarkPairs {
            XCTAssertNotNil(
                Bundle.module.url(forResource: pair.baseName, withExtension: "svg"),
                "Missing bundled icon: \(pair.baseName).svg"
            )
            XCTAssertNotNil(
                Bundle.module.url(forResource: pair.darkName, withExtension: "svg"),
                "Missing bundled icon: \(pair.darkName).svg"
            )
        }
    }

    func testGrokBotIconIsDistinctFromGrokCLI() {
        XCTAssertNotEqual(ProviderMenuIconCatalog.grokBot, "menu_grok_icon")
        XCTAssertTrue(ProviderMenuIconCatalog.grokBot.hasSuffix("_icon"))
    }

    func testGrokBotIconsUseLobeHubGrokMark() throws {
        let lightURL = try XCTUnwrap(
            Bundle.module.url(forResource: ProviderMenuIconCatalog.grokBot, withExtension: "svg")
        )
        let darkURL = try XCTUnwrap(
            Bundle.module.url(forResource: "\(ProviderMenuIconCatalog.grokBot)_dark", withExtension: "svg")
        )
        let grokCLIURL = try XCTUnwrap(
            Bundle.module.url(forResource: "menu_grok_icon", withExtension: "svg")
        )

        let light = try String(contentsOf: lightURL, encoding: .utf8)
        let dark = try String(contentsOf: darkURL, encoding: .utf8)
        let grokCLI = try String(contentsOf: grokCLIURL, encoding: .utf8)

        let lobehubPath = "M9.27 15.29l7.978-5.897"
        XCTAssertTrue(light.contains(lobehubPath), "Grok Bot light icon should use the LobeHub Grok mark")
        XCTAssertTrue(dark.contains(lobehubPath), "Grok Bot dark icon should use the LobeHub Grok mark")
        XCTAssertTrue(grokCLI.contains(lobehubPath), "Grok CLI icon should keep the LobeHub Grok mark")
        XCTAssertFalse(light.contains("translate(128,128)"), "Grok Bot icon should not use the Cursor onboarding face mark")
    }
}
