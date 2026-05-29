import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class MenuDashboardStateBuilderTests: XCTestCase {
    func testBuildStateOrdersEnabledProvidersAndPreservesAmountCardPresentation() {
        var relay = ProviderDescriptor.defaultOpenAilinyu()
        relay.enabled = true
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true
        var claude = ProviderDescriptor.defaultOfficialClaude()
        claude.enabled = false

        let state = MenuDashboardStateBuilder.build(
            config: AppConfig(
                language: .en,
                showOfficialAccountEmailInMenuBar: true,
                providers: [relay, claude, codex]
            ),
            snapshots: [
                relay.id: UsageSnapshot(
                    source: relay.id,
                    status: .ok,
                    remaining: 42.5,
                    used: 57.5,
                    limit: 100,
                    unit: "%",
                    updatedAt: Date(timeIntervalSince1970: 100),
                    note: "ok",
                    sourceLabel: relay.name
                )
            ],
            errors: [:],
            lastUpdatedAt: Date(timeIntervalSince1970: 100),
            updateState: .init(
                kind: .idle,
                statusText: nil,
                tone: .neutral,
                retryTitle: nil,
                isRetryEnabled: false
            ),
            now: Date(timeIntervalSince1970: 160),
            shouldShowPermissionGuide: true,
            codexSlots: [],
            claudeSlots: [],
            localization: .englishTest
        )

        XCTAssertEqual(state.header.updatedText, "Updated 1m ago")
        XCTAssertTrue(state.shouldShowPermissionGuide)
        XCTAssertEqual(state.cards.map(\.id), [codex.id, relay.id])

        guard case let .amount(amountCard) = state.cards.last else {
            return XCTFail("Expected the third-party provider to render as an amount card")
        }

        XCTAssertEqual(amountCard.title, "open.ailinyu.de")
        XCTAssertEqual(amountCard.amountText, "42.50")
        XCTAssertEqual(amountCard.balanceLabel, "Balance")
        XCTAssertNil(amountCard.secondaryText)
    }
}

private extension MenuViewLocalization {
    static let englishTest = MenuViewLocalization(
        updatedAgoLabel: "Updated",
        quota: MenuQuotaLocalization(
            quotaFiveHour: "5h",
            quotaWeekly: "Weekly",
            allModels: "All models",
            sonnetOnly: "Sonnet only",
            claudeDesign: "Claude Design",
            session: "Session",
            monthly: "Monthly",
            currentPlan: "Current Plan",
            totalUsage: "Total Usage",
            autocomplete: "Autocomplete",
            dollarBalance: "Dollar Balance"
        ),
        usedLabel: "Used",
        balanceLabel: "Balance",
        tightText: "Tight",
        sufficientText: "Sufficient",
        exhaustedText: "Exhausted",
        disconnectedText: "Disconnected",
        codexSwitchAction: "Switch",
        claudeSwitchAction: "Switch"
    )
}
