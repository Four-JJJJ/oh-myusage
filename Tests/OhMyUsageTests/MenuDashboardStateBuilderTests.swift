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

    func testOfficialLiveLabelIsNotAddedToPercentageCardSubtitle() {
        var kimi = ProviderDescriptor.defaultOfficialKimi()
        kimi.enabled = true
        let snapshot = UsageSnapshot(
            source: kimi.id,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 100),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "5h",
                    remainingPercent: 80,
                    usedPercent: 20,
                    kind: .session
                )
            ],
            sourceLabel: "API"
        )

        let state = MenuDashboardStateBuilder.build(
            config: AppConfig(language: .zhHans, providers: [kimi]),
            snapshots: [kimi.id: snapshot],
            errors: [:],
            lastUpdatedAt: snapshot.updatedAt,
            updateState: .init(kind: .idle, statusText: nil, tone: .neutral, retryTitle: nil, isRetryEnabled: false),
            now: Date(timeIntervalSince1970: 160),
            shouldShowPermissionGuide: false,
            codexSlots: [],
            claudeSlots: [],
            localization: .englishTest
        )

        guard case let .percentage(card) = state.cards.first else {
            return XCTFail("Expected Kimi to render as a percentage card")
        }
        XCTAssertNil(card.subtitle)
    }

    func testOfficialDeepSeekRendersCurrencyBalanceInsteadOfQuotaPlaceholders() {
        var deepSeek = ProviderDescriptor.defaultOfficialDeepSeek()
        deepSeek.enabled = true
        let snapshot = UsageSnapshot(
            source: deepSeek.id,
            status: .ok,
            remaining: 88.5,
            used: nil,
            limit: nil,
            unit: "CNY",
            updatedAt: Date(timeIntervalSince1970: 100),
            note: "ok",
            sourceLabel: deepSeek.name
        )

        let state = MenuDashboardStateBuilder.build(
            config: AppConfig(language: .en, providers: [deepSeek]),
            snapshots: [deepSeek.id: snapshot],
            errors: [:],
            lastUpdatedAt: snapshot.updatedAt,
            updateState: .init(kind: .idle, statusText: nil, tone: .neutral, retryTitle: nil, isRetryEnabled: false),
            now: Date(timeIntervalSince1970: 160),
            shouldShowPermissionGuide: false,
            codexSlots: [],
            claudeSlots: [],
            localization: .englishTest
        )

        guard case let .amount(card) = state.cards.first else {
            return XCTFail("Expected DeepSeek to render as a balance amount card")
        }
        XCTAssertEqual(card.title, "DeepSeek")
        XCTAssertEqual(card.amountText, "88.50")
        XCTAssertEqual(card.balanceLabel, "Balance")
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
