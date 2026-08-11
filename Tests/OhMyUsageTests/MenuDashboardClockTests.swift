import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class MenuDashboardClockTests: XCTestCase {
    func testApplyClockUpdatesOnlyUpdatedTextAndResetText() {
        var kimi = ProviderDescriptor.defaultOfficialKimi()
        kimi.enabled = true
        kimi.officialConfig?.showExpirationTimeInMenuBar = true

        let resetAt = Date(timeIntervalSince1970: 1_000)
        let lastUpdatedAt = Date(timeIntervalSince1970: 100)
        let now1 = Date(timeIntervalSince1970: 160)
        let now2 = Date(timeIntervalSince1970: 220)

        let state1 = MenuDashboardStateBuilder.build(
            config: AppConfig(language: .en, providers: [kimi]),
            snapshots: [
                kimi.id: UsageSnapshot(
                    source: kimi.id,
                    status: .ok,
                    remaining: 80,
                    used: 20,
                    limit: 100,
                    unit: "%",
                    updatedAt: lastUpdatedAt,
                    note: "ok",
                    quotaWindows: [
                        UsageQuotaWindow(
                            id: "session",
                            title: "5h",
                            remainingPercent: 80,
                            usedPercent: 20,
                            resetAt: resetAt,
                            kind: .session
                        ),
                        UsageQuotaWindow(
                            id: "weekly",
                            title: "Weekly",
                            remainingPercent: 60,
                            usedPercent: 40,
                            resetAt: resetAt,
                            kind: .weekly
                        )
                    ],
                    sourceLabel: kimi.name
                )
            ],
            errors: [:],
            lastUpdatedAt: lastUpdatedAt,
            updateState: .init(
                kind: .idle,
                statusText: nil,
                tone: .neutral,
                retryTitle: nil,
                isRetryEnabled: false
            ),
            now: now1,
            shouldShowPermissionGuide: false,
            codexSlots: [],
            claudeSlots: [],
            localization: .englishTest
        )

        var state2 = state1
        MenuDashboardStateBuilder.applyClock(to: &state2, now: now2)

        XCTAssertNotEqual(state1.header.updatedText, state2.header.updatedText)
        XCTAssertEqual(state2.header.updatedText, "Updated 2m ago")
        XCTAssertEqual(state2.header.update, state1.header.update)
        XCTAssertEqual(state2.shouldShowPermissionGuide, state1.shouldShowPermissionGuide)
        XCTAssertEqual(state2.cards.count, state1.cards.count)

        guard case let .percentage(card1) = state1.cards.first,
              case let .percentage(card2) = state2.cards.first else {
            return XCTFail("Expected percentage cards")
        }

        XCTAssertEqual(card2.id, card1.id)
        XCTAssertEqual(card2.title, card1.title)
        XCTAssertEqual(card2.status, card1.status)
        XCTAssertEqual(card2.metrics.count, card1.metrics.count)

        let metrics1 = card1.metrics
        let metrics2 = card2.metrics
        XCTAssertEqual(metrics2.map { $0.id }, metrics1.map { $0.id })
        XCTAssertEqual(metrics2.map { $0.valueText }, metrics1.map { $0.valueText })
        XCTAssertEqual(metrics2.map { $0.percent }, metrics1.map { $0.percent })
        XCTAssertNotEqual(metrics2.map { $0.resetText }, metrics1.map { $0.resetText })

        let expectedReset = CountdownFormatter.text(
            to: resetAt,
            now: now2,
            placeholder: "-",
            language: .en
        )
        XCTAssertEqual(Set(metrics2.map { $0.resetText }), [expectedReset])
    }

    func testApplyClockIsPureAndDoesNotRequireSlotRebuild() {
        let resetAt = Date(timeIntervalSince1970: 500)
        var state = MenuViewState(
            header: MenuDashboardHeaderPresentation(
                updatedText: "Updated 1m ago",
                update: nil
            ),
            shouldShowPermissionGuide: false,
            cards: [
                .percentage(
                    MenuPercentageCardViewState(
                        id: "codex",
                        title: "Codex",
                        planType: nil,
                        iconName: "menu_codex_icon",
                        iconFallback: "terminal.fill",
                        subtitle: nil,
                        status: MenuCardStatusPresentation(
                            text: "Sufficient",
                            tone: .normal
                        ),
                        metrics: [
                            MenuQuotaMetricDisplayPresentation(
                                id: "5h",
                                title: "5h",
                                valueText: "80%",
                                resetText: "old",
                                percent: 80,
                                barTone: .normal,
                                isBlockedByDepletedQuota: false,
                                resetAt: resetAt
                            )
                        ],
                        errorText: nil,
                        isDisconnected: false,
                        showsErrorHighlight: false
                    )
                )
            ],
            clockContext: MenuViewClockContext(
                lastUpdatedAt: Date(timeIntervalSince1970: 100),
                language: .en,
                updatedAgoLabel: "Updated"
            )
        )

        MenuDashboardStateBuilder.applyClock(
            to: &state,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(state.header.updatedText, "Updated 1m ago")
        guard case let .percentage(card) = state.cards.first else {
            return XCTFail("Expected percentage card")
        }
        XCTAssertEqual(card.metrics[0].valueText, "80%")
        XCTAssertEqual(
            card.metrics[0].resetText,
            CountdownFormatter.text(
                to: resetAt,
                now: Date(timeIntervalSince1970: 200),
                placeholder: "-",
                language: .en
            )
        )
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
