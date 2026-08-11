import XCTest
@testable import OhMyUsage

final class ProviderPresentationRegistryTests: XCTestCase {
    func testOfficialCodexPresentationAndCapabilities() {
        let provider = ProviderDescriptor.defaultOfficialCodex()
        let presentation = ProviderPresentationRegistry.presentation(for: provider)
        let capabilities = ProviderCapabilities.capabilities(for: provider)

        XCTAssertEqual(presentation.displayName, "Codex")
        XCTAssertEqual(presentation.iconName, "menu_codex_icon")
        XCTAssertEqual(presentation.fallbackSystemIcon, "terminal.fill")
        XCTAssertTrue(capabilities.supportsAccountSwitching)
        XCTAssertTrue(capabilities.supportsLocalUsageHistory)
        XCTAssertTrue(capabilities.usesPercentageMenuCard)
    }

    func testRelayPresentationUsesProviderNameAndAmountCardByDefault() {
        let provider = ProviderDescriptor.makeOpenRelay(name: "Relay X", baseURL: "https://relay.example.com")
        let presentation = ProviderPresentationRegistry.presentation(for: provider)
        let capabilities = ProviderCapabilities.capabilities(for: provider)

        XCTAssertEqual(presentation.displayName, "Relay X")
        XCTAssertEqual(presentation.iconName, "menu_relay_icon")
        XCTAssertFalse(capabilities.usesPercentageMenuCard)
        XCTAssertEqual(QuotaMetricDisplayFactory.preferredMetricCount(for: provider), 2)
    }

    func testOfficialDeepSeekUsesBalanceAmountCard() {
        let provider = ProviderDescriptor.defaultOfficialDeepSeek()
        let capabilities = ProviderCapabilities.capabilities(for: provider)

        XCTAssertTrue(capabilities.supportsBalance)
        XCTAssertFalse(capabilities.supportsQuotaWindows)
        XCTAssertFalse(capabilities.usesPercentageMenuCard)
    }

    func testClaudePreferredMetricCountIsFour() {
        let provider = ProviderDescriptor.defaultOfficialClaude()

        XCTAssertEqual(QuotaMetricDisplayFactory.preferredMetricCount(for: provider), 4)
    }
}
