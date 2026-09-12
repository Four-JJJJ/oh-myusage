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
}
