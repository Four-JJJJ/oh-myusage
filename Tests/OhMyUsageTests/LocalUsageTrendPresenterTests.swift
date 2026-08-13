import XCTest
@testable import OhMyUsage

final class LocalUsageTrendPresenterTests: XCTestCase {
    func testPresentationShowsLoadingStatusWithoutDisplaySummaryWhenSummaryIsEmpty() {
        let state = LocalUsageTrendPresenter.presentation(
            providerType: .codex,
            scope: .allAccounts,
            historyState: LocalUsageHistoryState(
                summary: nil,
                error: nil,
                isLoading: true,
                lastRefreshedAt: nil,
                sourceFingerprint: nil,
                lastFingerprintCheckedAt: nil,
                isStaleFallback: false
            ),
            summary: nil,
            localizedText: Self.english,
            formatInteger: Self.integerText,
            dateText: Self.dateText
        )

        XCTAssertFalse(state.hasTrendData)
        XCTAssertNil(state.displaySummary)
        XCTAssertEqual(state.chartStatus, LocalUsageTrendStatusPresentation(text: "Loading...", tone: .muted))
        XCTAssertNil(state.staleFallbackText)
        XCTAssertNil(state.cacheStatusText)
    }

    func testPresentationShowsCodexCurrentAccountUnattributedEmptyStatus() {
        let summary = Self.emptySummary(diagnostics: LocalUsageTrendDiagnostics(
            matchedRows: 6,
            parsedEvents: 6,
            attributableEvents: 0,
            recoveredByConversationResponses: 0,
            recoveredByConversationTokens: 0,
            unattributedResponses: 3,
            unattributedTokens: 2400,
            latestEventAt: nil,
            source: .strict
        ))

        let state = LocalUsageTrendPresenter.presentation(
            providerType: .codex,
            scope: .currentAccount,
            historyState: Self.historyState(summary: summary),
            summary: summary,
            localizedText: Self.english,
            formatInteger: Self.integerText,
            dateText: Self.dateText
        )

        XCTAssertFalse(state.hasTrendData)
        XCTAssertNil(state.displaySummary)
        XCTAssertEqual(
            state.chartStatus,
            LocalUsageTrendStatusPresentation(
                text: "No attributable events for current account (Unattributed 3/2400 tokens)",
                tone: .muted
            )
        )
    }

    func testPresentationShowsGeminiEmptyStatus() {
        let summary = Self.emptySummary()

        let state = LocalUsageTrendPresenter.presentation(
            providerType: .gemini,
            scope: .allAccounts,
            historyState: Self.historyState(summary: summary),
            summary: summary,
            localizedText: Self.english,
            formatInteger: Self.integerText,
            dateText: Self.dateText
        )

        XCTAssertFalse(state.hasTrendData)
        XCTAssertNil(state.displaySummary)
        XCTAssertEqual(
            state.chartStatus,
            LocalUsageTrendStatusPresentation(text: "No data", tone: .muted)
        )
    }

    func testPresentationKeepsDisplaySummaryAndCacheStatusWhenDataExists() {
        let summary = Self.summaryWithData(generatedAt: Date(timeIntervalSince1970: 3_000))

        let state = LocalUsageTrendPresenter.presentation(
            providerType: .claude,
            scope: .allAccounts,
            historyState: Self.historyState(
                summary: summary,
                lastFingerprintCheckedAt: Date(timeIntervalSince1970: 4_000)
            ),
            summary: summary,
            localizedText: Self.english,
            formatInteger: Self.integerText,
            dateText: Self.dateText
        )

        XCTAssertTrue(state.hasTrendData)
        XCTAssertEqual(state.displaySummary, summary)
        XCTAssertNil(state.chartStatus)
        XCTAssertEqual(state.cacheStatusText, "Cache checked t4000 · Chart generated t3000")
    }

    func testPresentationReportsStaleFallbackTextWithoutTreatingErrorAsChartStatus() {
        let summary = Self.summaryWithData()

        let state = LocalUsageTrendPresenter.presentation(
            providerType: .codex,
            scope: .allAccounts,
            historyState: Self.historyState(
                summary: summary,
                error: "read failed",
                isStaleFallback: true
            ),
            summary: summary,
            localizedText: Self.english,
            formatInteger: Self.integerText,
            dateText: Self.dateText
        )

        XCTAssertTrue(state.hasTrendData)
        XCTAssertEqual(state.displaySummary, summary)
        XCTAssertNil(state.chartStatus)
        XCTAssertEqual(state.staleFallbackText, "Refresh failed, showing cached data: read failed")
    }

    func testHasDataReadsSummaryPeriodsAndTrendPoints() {
        XCTAssertFalse(LocalUsageTrendPresenter.hasData(Self.emptySummary()))

        let hourlySummary = Self.emptySummary(
            hourly24: [
                LocalUsageTrendPoint(
                    id: "h1",
                    startAt: Date(timeIntervalSince1970: 1),
                    totalTokens: 0,
                    responses: 1
                )
            ]
        )

        XCTAssertTrue(LocalUsageTrendPresenter.hasData(hourlySummary))
    }

    private static func historyState(
        summary: LocalUsageSummary?,
        error: String? = nil,
        isLoading: Bool = false,
        lastRefreshedAt: Date? = nil,
        lastFingerprintCheckedAt: Date? = nil,
        isStaleFallback: Bool = false
    ) -> LocalUsageHistoryState {
        LocalUsageHistoryState(
            summary: summary,
            error: error,
            isLoading: isLoading,
            lastRefreshedAt: lastRefreshedAt,
            sourceFingerprint: nil,
            lastFingerprintCheckedAt: lastFingerprintCheckedAt,
            isStaleFallback: isStaleFallback
        )
    }

    private static func emptySummary(
        generatedAt: Date = Date(timeIntervalSince1970: 1_000),
        diagnostics: LocalUsageTrendDiagnostics? = nil,
        hourly24: [LocalUsageTrendPoint] = [],
        daily7: [LocalUsageTrendPoint] = []
    ) -> LocalUsageSummary {
        LocalUsageSummary(
            today: .empty,
            yesterday: .empty,
            last30Days: .empty,
            hourly24: hourly24,
            daily7: daily7,
            sourcePath: "/tmp/local-usage",
            generatedAt: generatedAt,
            diagnostics: diagnostics,
            isApproximateFallback: false
        )
    }

    private static func summaryWithData(
        generatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> LocalUsageSummary {
        LocalUsageSummary(
            today: LocalUsagePeriodSummary(totalTokens: 100, responses: 2, byModel: []),
            yesterday: .empty,
            last30Days: LocalUsagePeriodSummary(totalTokens: 100, responses: 2, byModel: []),
            hourly24: [],
            daily7: [],
            sourcePath: "/tmp/local-usage",
            generatedAt: generatedAt,
            diagnostics: nil,
            isApproximateFallback: false
        )
    }

    private static func english(_ zhHans: String, _ english: String) -> String {
        english
    }

    private static func integerText(_ value: Int) -> String {
        String(value)
    }

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "n/a" }
        return "t\(Int(date.timeIntervalSince1970))"
    }
}
