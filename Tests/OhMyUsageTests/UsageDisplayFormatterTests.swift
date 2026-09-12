import XCTest
@testable import OhMyUsage

final class UsageDisplayFormatterTests: XCTestCase {
    func testPlanTypeResolutionUsesExtrasThenRawMetaAndFiltersPlaceholderValues() {
        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .codex,
                extrasPlanType: "business plan",
                rawPlanType: "Plan Plus"
            ),
            "Business Plan"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .claude,
                extrasPlanType: " unknown ",
                rawPlanType: "team-pro"
            ),
            "Team-Pro"
        )

        XCTAssertNil(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .gemini,
                extrasPlanType: "-",
                rawPlanType: nil
            )
        )
    }

    func testPlanTypeResolutionIsOnlyEnabledForSelectedOfficialModels() {
        XCTAssertNil(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .jetbrains,
                extrasPlanType: "Ultimate",
                rawPlanType: "Pro"
            )
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .relay,
                extrasPlanType: "Coding Plan",
                rawPlanType: nil
            ),
            "Coding Plan"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .copilot,
                extrasPlanType: "pro",
                rawPlanType: nil
            ),
            "Pro"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .gemini,
                extrasPlanType: "pro",
                rawPlanType: nil
            ),
            "Pro"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .microsoftCopilot,
                extrasPlanType: "M365",
                rawPlanType: nil
            ),
            "M365"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .zai,
                extrasPlanType: "GLM Coding Max",
                rawPlanType: nil
            ),
            "GLM Coding Max"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .amp,
                extrasPlanType: "Free",
                rawPlanType: nil
            ),
            "Free"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .windsurf,
                extrasPlanType: "Pro",
                rawPlanType: nil
            ),
            "Pro"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .grok,
                extrasPlanType: "SuperGrok",
                rawPlanType: nil
            ),
            "SuperGrok"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .grokBot,
                extrasPlanType: "SuperGrok Plus",
                rawPlanType: nil
            ),
            "SuperGrok Plus"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .qwen,
                extrasPlanType: "Standard",
                rawPlanType: nil
            ),
            "Standard"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .ollamaCloud,
                extrasPlanType: "free",
                rawPlanType: nil
            ),
            "Free"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .cursor,
                extrasPlanType: "pro",
                rawPlanType: nil
            ),
            "Pro"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .cursor,
                extrasPlanType: "pro_plus",
                rawPlanType: nil
            ),
            "Pro+"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .cursor,
                extrasPlanType: "ultra",
                rawPlanType: nil
            ),
            "Ultra"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .cursor,
                extrasPlanType: "hobby",
                rawPlanType: nil
            ),
            "Free"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .kimi,
                extrasPlanType: "intermediate",
                rawPlanType: nil
            ),
            "Allegretto"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .kimi,
                extrasPlanType: "LEVEL_ADVANCED",
                rawPlanType: nil
            ),
            "Allegro"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .kimi,
                extrasPlanType: nil,
                rawPlanType: "student plus"
            ),
            "student plus"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .trae,
                extrasPlanType: "solo annual",
                rawPlanType: nil
            ),
            "solo annual"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .trae,
                extrasPlanType: "Free plan",
                rawPlanType: nil
            ),
            "Free"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .trae,
                extrasPlanType: "Pro plan",
                rawPlanType: nil
            ),
            "Pro"
        )

        XCTAssertNil(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .trae,
                extrasPlanType: "plan",
                rawPlanType: nil
            )
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .trae,
                extrasPlanType: "Ultra",
                rawPlanType: nil
            ),
            "Ultra"
        )

        XCTAssertEqual(
            PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: .codex,
                extrasPlanType: "Business Plan",
                rawPlanType: nil
            ),
            "Business Plan"
        )
    }

    func testCompactNumberZhHansBoundaries() {
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(9_999, language: .zhHans), "9999")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(10_000, language: .zhHans), "1万")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(65_300, language: .zhHans), "6.5万")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(3_200_000, language: .zhHans), "320万")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(219_000_000, language: .zhHans), "2.2亿")
    }

    func testCompactNumberEnglishBoundaries() {
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(999, language: .en), "999")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(1_000, language: .en), "1K")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(2_981, language: .en), "3K")
        XCTAssertEqual(LocalTrendValueFormatter.compactNumber(2_900_000, language: .en), "2.9M")
    }

    func testMetricValueTextUsesExpectedUnits() {
        XCTAssertEqual(
            LocalTrendValueFormatter.metricValueText(value: 65_300, metric: .tokens, language: .zhHans),
            "6.5万 tokens"
        )
        XCTAssertEqual(
            LocalTrendValueFormatter.metricValueText(value: 29_000, metric: .responses, language: .zhHans),
            "2.9万次"
        )
        XCTAssertEqual(
            LocalTrendValueFormatter.metricValueText(value: 2_981, metric: .responses, language: .en),
            "3K req"
        )
    }

    func testTraeValueFormattingSupportsAdaptiveDollarAndAutocompleteCompaction() {
        XCTAssertEqual(
            TraeValueDisplayFormatter.format(
                0.2,
                kind: .dollarBalance,
                maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
            ),
            "0.20"
        )
        XCTAssertEqual(
            TraeValueDisplayFormatter.format(
                3,
                kind: .dollarBalance,
                maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
            ),
            "3"
        )
        XCTAssertEqual(
            TraeValueDisplayFormatter.format(
                5_000,
                kind: .dollarBalance,
                maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
            ),
            "5,000"
        )
        XCTAssertEqual(
            TraeValueDisplayFormatter.format(
                50_000,
                kind: .dollarBalance,
                maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
            ),
            "5W"
        )
        XCTAssertEqual(TraeValueDisplayFormatter.format(950, kind: .autocomplete), "950")
        XCTAssertEqual(TraeValueDisplayFormatter.format(1_500, kind: .autocomplete), "1.5K")
        XCTAssertEqual(TraeValueDisplayFormatter.format(23_000, kind: .autocomplete), "2.3W")
    }

    func testMetricValueColumnWidthFits900PercentReference() {
        XCTAssertGreaterThanOrEqual(MetricValueLayoutFormatter.metricValueColumnWidth, 46)
        XCTAssertGreaterThanOrEqual(
            MetricValueLayoutFormatter.metricValueColumnWidth,
            MetricValueLayoutFormatter.metricValueReferenceTextWidth
        )
    }

    func testPercentageMetricValueColumnWidthFits100PercentReference() {
        XCTAssertEqual(
            MetricValueLayoutFormatter.percentageMetricValueColumnWidth,
            MetricValueLayoutFormatter.percentageMetricValueReferenceTextWidth
        )
        XCTAssertLessThan(
            MetricValueLayoutFormatter.percentageMetricValueColumnWidth,
            MetricValueLayoutFormatter.metricValueColumnWidth
        )
    }
}
