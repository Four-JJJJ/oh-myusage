import XCTest
@testable import OhMyUsage

final class LocalizerFormatTests: XCTestCase {
    func testFormatSubstitutesPlaceholderInBothLanguages() {
        XCTAssertEqual(
            Localizer.format(.enableProviderAccessibility, language: .zhHans, "Codex"),
            "启用 Codex"
        )
        XCTAssertEqual(
            Localizer.format(.enableProviderAccessibility, language: .en, "Codex"),
            "Enable Codex"
        )
    }

    func testFormatInsertsArgumentsVerbatimWithoutRescanning() {
        XCTAssertEqual(
            Localizer.format(.enableProviderAccessibility, language: .en, "100% %@ site"),
            "Enable 100% %@ site"
        )
    }

    func testFormatFillsMultiplePlaceholdersInOrder() {
        XCTAssertEqual(
            Localizer.format(.updateAvailableBody, language: .en, "2.0.0", "1.0.0"),
            "Latest 2.0.0 (current 1.0.0)"
        )
    }

    func testFormatLeavesUnfilledPlaceholdersAndIgnoresExtraArguments() {
        XCTAssertEqual(
            Localizer.format(.updateAvailableBody, language: .en, "2.0.0"),
            "Latest 2.0.0 (current %@)"
        )
        XCTAssertEqual(
            Localizer.format(.enableProviderAccessibility, language: .en, "A", "B"),
            "Enable A"
        )
    }
}
