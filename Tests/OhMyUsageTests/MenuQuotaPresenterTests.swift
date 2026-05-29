import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class MenuQuotaPresenterTests: XCTestCase {
    func testVisibleMetricsFallbackUsesClaudePlaceholdersAndUsedSuffix() {
        let provider = ProviderDescriptor.defaultOfficialClaude()

        let metrics = MenuQuotaPresenter.visibleMetrics(
            provider: provider,
            metrics: [],
            language: .en,
            localization: Self.localization
        )

        XCTAssertEqual(metrics.count, 4)
        XCTAssertEqual(metrics[0].title, "5h used")
        XCTAssertEqual(metrics[1].title, "All models used")
        XCTAssertFalse(metrics[2].isAvailable)
        XCTAssertEqual(metrics[2].valueTextOverride, "N/A")
    }

    func testClaudeQuotaMetricsResolveSonnetAndDesignWindows() {
        let provider = ProviderDescriptor.defaultOfficialClaude()
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "session",
                    title: "Session",
                    remainingPercent: 75,
                    usedPercent: 25,
                    kind: .session
                ),
                UsageQuotaWindow(
                    id: "weekly",
                    title: "Weekly",
                    remainingPercent: 60,
                    usedPercent: 40,
                    kind: .weekly
                ),
                UsageQuotaWindow(
                    id: "sonnet-window",
                    title: "Sonnet Window",
                    remainingPercent: 50,
                    usedPercent: 50,
                    kind: .custom
                ),
                UsageQuotaWindow(
                    id: "design-window",
                    title: "Claude Design",
                    remainingPercent: 40,
                    usedPercent: 60,
                    kind: .custom
                )
            ],
            sourceLabel: "API"
        )

        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: snapshot,
            language: .en,
            localization: Self.localization
        )

        XCTAssertEqual(metrics.count, 4)
        XCTAssertEqual(metrics[0].title, "5h used")
        XCTAssertEqual(metrics[1].title, "All models used")
        XCTAssertEqual(metrics[2].title, "Sonnet only used")
        XCTAssertEqual(metrics[3].title, "Claude Design used")
        XCTAssertEqual(metrics[2].healthPercent ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(metrics[3].healthPercent ?? -1, 40, accuracy: 0.0001)
    }

    func testMetricDisplaysUseTraeAmountFallbackWhenUsedValueMissing() {
        var provider = ProviderDescriptor.defaultOfficialTrae()
        provider.officialConfig?.traeValueDisplayMode = .amount

        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 88,
            used: 12,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "API",
            extras: [
                "dollarRemaining": "12.5"
            ]
        )

        let presentations = MenuQuotaPresenter.metricDisplays(
            metrics: [
                MenuQuotaMetric(
                    id: "trae-dollar",
                    title: "Dollar Balance",
                    displayPercent: 88,
                    healthPercent: 88,
                    resetAt: nil,
                    isAvailable: true,
                    valueTextOverride: nil,
                    kind: .credits
                )
            ],
            blockageCandidates: [],
            provider: provider,
            snapshot: snapshot,
            disconnected: false,
            language: .en,
            now: Date()
        )

        XCTAssertEqual(presentations.count, 1)
        XCTAssertEqual(
            presentations[0].valueText,
            TraeValueDisplayFormatter.format(
                12.5,
                kind: .dollarBalance,
                maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
            )
        )
        XCTAssertEqual(presentations[0].resetText, "-")
        XCTAssertEqual(presentations[0].barTone, .normal)
    }

    func testMetricDisplaysMarkSessionBlockedWhenWeeklyQuotaDepleted() {
        let provider = ProviderDescriptor.defaultOfficialCodex()
        let session = MenuQuotaMetric(
            id: "session",
            title: "5h",
            displayPercent: 42,
            healthPercent: 42,
            resetAt: nil,
            isAvailable: true,
            valueTextOverride: nil,
            kind: .session
        )
        let weekly = MenuQuotaMetric(
            id: "weekly",
            title: "Weekly",
            displayPercent: 0,
            healthPercent: 0,
            resetAt: nil,
            isAvailable: true,
            valueTextOverride: nil,
            kind: .weekly
        )

        let presentations = MenuQuotaPresenter.metricDisplays(
            metrics: [session],
            blockageCandidates: [session, weekly],
            provider: provider,
            snapshot: nil,
            disconnected: false,
            language: .en,
            now: Date()
        )

        XCTAssertTrue(presentations[0].isBlockedByDepletedQuota)
    }

    func testQuotaMetricsUseMimoTotalUsageRemainingDisplayWithRemainingTokensDetail() {
        var provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        provider.relayConfig?.quotaDisplayMode = .remaining
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 99.66389942402705,
            used: 0.336100575972948,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "token-plan-total",
                    title: "Total Usage",
                    remainingPercent: 99.66389942402705,
                    usedPercent: 0.336100575972948,
                    kind: .custom
                )
            ],
            sourceLabel: "Relay",
            rawMeta: [
                "account.quotaValueText.token-plan-total": "48,014,368 / 14,285,714,286",
                "account.tokenPlanUsed": "48014368",
                "account.tokenPlanRemaining": "14237699918",
                "account.tokenPlanLimit": "14285714286"
            ]
        )

        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: snapshot,
            language: .en,
            localization: Self.localization
        )

        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.title, "Total Usage")
        XCTAssertEqual(metrics.first?.displayPercent ?? -1, 99.66389942402705, accuracy: 0.000001)
        XCTAssertEqual(metrics.first?.healthPercent ?? -1, 99.66389942402705, accuracy: 0.000001)
        XCTAssertNil(metrics.first?.valueTextOverride)
        XCTAssertEqual(metrics.first?.detailTextOverride, "14,237,699,918 tokens remaining")

        let presentations = MenuQuotaPresenter.metricDisplays(
            metrics: metrics,
            blockageCandidates: metrics,
            provider: provider,
            snapshot: snapshot,
            disconnected: false,
            language: .en,
            now: Date()
        )
        XCTAssertEqual(presentations.first?.valueText, "100%")
        XCTAssertEqual(presentations.first?.detailText, "14,237,699,918 tokens remaining")
        XCTAssertEqual(presentations.first?.barTone, .normal)
        XCTAssertFalse(presentations.first?.isBlockedByDepletedQuota ?? true)
    }

    func testQuotaMetricsUseMimoTotalUsageUsedDisplayWhenPreferenceIsUsed() {
        var provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        provider.relayConfig?.quotaDisplayMode = .used
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 99.66389942402705,
            used: 0.336100575972948,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "token-plan-total",
                    title: "Total Usage",
                    remainingPercent: 99.66389942402705,
                    usedPercent: 0.336100575972948,
                    kind: .custom
                )
            ],
            sourceLabel: "Relay",
            rawMeta: [
                "account.tokenPlanRemaining": "14237699918"
            ]
        )

        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: snapshot,
            language: .en,
            localization: Self.localization
        )

        XCTAssertEqual(metrics.first?.title, "Total Usage used")
        XCTAssertEqual(metrics.first?.displayPercent ?? -1, 0.336100575972948, accuracy: 0.000001)
        XCTAssertEqual(metrics.first?.healthPercent ?? -1, 99.66389942402705, accuracy: 0.000001)

        let presentations = MenuQuotaPresenter.metricDisplays(
            metrics: metrics,
            blockageCandidates: metrics,
            provider: provider,
            snapshot: snapshot,
            disconnected: false,
            language: .en,
            now: Date()
        )

        XCTAssertEqual(presentations.first?.valueText, "0%")
        XCTAssertEqual(presentations.first?.detailText, "14,237,699,918 tokens remaining")
        XCTAssertEqual(presentations.first?.barTone, .normal)
    }

    func testQuotaMetricsHideResetTextWhenExpirationDisplayIsDisabled() {
        var provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        provider.relayConfig?.showExpirationTimeInMenuBar = false
        let resetAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "token-plan-total",
                    title: "Total Usage",
                    remainingPercent: 80,
                    usedPercent: 20,
                    resetAt: resetAt,
                    kind: .custom
                )
            ],
            sourceLabel: "Relay"
        )

        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: snapshot,
            language: .en,
            localization: Self.localization
        )
        let presentations = MenuQuotaPresenter.metricDisplays(
            metrics: metrics,
            blockageCandidates: metrics,
            provider: provider,
            snapshot: snapshot,
            disconnected: false,
            language: .en,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertNil(metrics.first?.resetAt)
        XCTAssertEqual(presentations.first?.resetText, "-")
    }

    private static let localization = MenuQuotaLocalization(
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
    )
}
