import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class MenuCardStatusPresenterTests: XCTestCase {
    func testPlanTypeRespectsOfficialDisplayToggleAndFallbacks() {
        var official = ProviderDescriptor.defaultOfficialCodex()
        official.officialConfig?.showPlanTypeInMenuBar = true
        let snapshot = UsageSnapshot(
            source: official.id,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Official",
            extras: ["planType": "plus"]
        )

        XCTAssertEqual(
            MenuCardStatusPresenter.planType(for: official, snapshot: snapshot),
            "Plus"
        )

        official.officialConfig?.showPlanTypeInMenuBar = false
        XCTAssertNil(MenuCardStatusPresenter.planType(for: official, snapshot: snapshot))
    }

    func testPercentageStatusNamesAuthFailureForCachedAuthExpired() {
        let snapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            fetchHealth: .authExpired,
            valueFreshness: .cachedFallback,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Relay"
        )

        let status = MenuCardStatusPresenter.percentageStatus(
            healthPercents: [80],
            snapshot: snapshot,
            disconnected: false,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "认证失败")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.error)
    }

    func testPercentageStatusNamesConfigIssueForEmptySnapshotFetchProblem() {
        let snapshot = UsageSnapshot(
            source: "codex",
            status: .ok,
            fetchHealth: .endpointMisconfigured,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: Date(),
            note: "auth expired",
            sourceLabel: "Official"
        )

        let status = MenuCardStatusPresenter.percentageStatus(
            healthPercents: [],
            snapshot: snapshot,
            disconnected: false,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "配置异常")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.error)
    }

    func testAmountStatusWarnsRateLimitedForEmptySnapshotFetchProblem() {
        let snapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            fetchHealth: .rateLimited,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: Date(),
            note: "rate limited",
            sourceLabel: "Relay"
        )

        let status = MenuCardStatusPresenter.amountStatus(
            remaining: nil,
            snapshot: snapshot,
            disconnected: false,
            language: .en,
            tightText: "Tight",
            sufficientText: "Sufficient",
            exhaustedText: "Exhausted",
            disconnectedText: "Disconnected"
        )

        XCTAssertEqual(status.text, "Rate limited")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.warning)
    }

    func testAmountStatusUsesRemainingThresholds() {
        let liveSnapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .live,
            remaining: 12,
            used: 88,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "API"
        )

        let status = MenuCardStatusPresenter.amountStatus(
            remaining: 12,
            snapshot: liveSnapshot,
            disconnected: false,
            language: .en,
            tightText: "Tight",
            sufficientText: "Sufficient",
            exhaustedText: "Exhausted",
            disconnectedText: "Disconnected"
        )

        XCTAssertEqual(status.text, "Tight")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.warning)
    }

    func testPercentageStatusFallsBackToQuotaStatusForLiveHealthyData() {
        let snapshot = UsageSnapshot(
            source: "codex",
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .live,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "API"
        )

        let status = MenuCardStatusPresenter.percentageStatus(
            healthPercents: [80],
            snapshot: snapshot,
            disconnected: false,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "充足")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.normal)
    }

    func testMissingSnapshotReadsAsPendingRefresh() {
        let status = MenuCardStatusPresenter.percentageStatus(
            healthPercents: [],
            snapshot: nil,
            disconnected: false,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "待刷新")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.normal)
    }

    func testEmptyHealthySnapshotReadsAsPendingRefresh() {
        let snapshot = UsageSnapshot(
            source: "codex",
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .empty,
            remaining: nil,
            used: nil,
            limit: nil,
            unit: "%",
            updatedAt: Date(),
            note: "no data",
            sourceLabel: "API"
        )

        let status = MenuCardStatusPresenter.percentageStatus(
            healthPercents: [],
            snapshot: snapshot,
            disconnected: false,
            language: .en,
            tightText: "Tight",
            sufficientText: "Sufficient",
            exhaustedText: "Exhausted",
            disconnectedText: "Disconnected"
        )

        XCTAssertEqual(status.text, "Pending")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.normal)
    }

    func testHealthyCachedFallbackReadsAsLocalCacheWarning() {
        let snapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .cachedFallback,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Relay"
        )

        let status = MenuCardStatusPresenter.percentageStatus(
            healthPercents: [80],
            snapshot: snapshot,
            disconnected: false,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "本地缓存")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.warning)
    }

    func testUnreachableCachedFallbackReadsAsRefreshFailedWithStaleData() {
        let snapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            fetchHealth: .unreachable,
            valueFreshness: .cachedFallback,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Relay"
        )

        let status = MenuCardStatusPresenter.amountStatus(
            remaining: 80,
            snapshot: snapshot,
            disconnected: false,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "刷新失败，显示旧数据")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.error)
    }

    func testLiveLocallyDerivedSourceReadsAsLocalEstimate() {
        let snapshot = UsageSnapshot(
            source: "claude",
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .live,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "CLI"
        )

        let status = MenuCardStatusPresenter.percentageStatus(
            healthPercents: [80],
            snapshot: snapshot,
            disconnected: false,
            language: .en,
            tightText: "Tight",
            sufficientText: "Sufficient",
            exhaustedText: "Exhausted",
            disconnectedText: "Disconnected"
        )

        XCTAssertEqual(status.text, "Estimated")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.warning)
    }

    func testDisconnectedWithoutSnapshotKeepsDisconnectedLabel() {
        let status = MenuCardStatusPresenter.amountStatus(
            remaining: nil,
            snapshot: nil,
            disconnected: true,
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(status.text, "失联")
        XCTAssertEqual(status.tone, MenuCardStatusPresentation.Tone.error)
    }

    func testCachedFetchHealthStatusTextUsesConvergedVocabulary() {
        XCTAssertEqual(
            MenuCardStatusPresenter.cachedFetchHealthStatusText(.authExpired, language: .en),
            "Auth failed"
        )
        XCTAssertEqual(
            MenuCardStatusPresenter.cachedFetchHealthStatusText(.ok, language: .zhHans),
            "本地缓存"
        )
        XCTAssertEqual(
            MenuCardStatusPresenter.cachedFetchHealthStatusText(.unreachable, language: .zhHans),
            "刷新失败，显示旧数据"
        )
    }
}

final class MenuDataCredibilityPresenterTests: XCTestCase {
    func testCredibilityMappingCoversAllFiveStates() {
        func snapshot(
            fetchHealth: FetchHealth,
            valueFreshness: ValueFreshness,
            sourceLabel: String = "API"
        ) -> UsageSnapshot {
            UsageSnapshot(
                source: "p",
                status: .ok,
                fetchHealth: fetchHealth,
                valueFreshness: valueFreshness,
                remaining: 50,
                used: 50,
                limit: 100,
                unit: "%",
                updatedAt: Date(),
                note: "ok",
                sourceLabel: sourceLabel
            )
        }

        XCTAssertEqual(
            MenuDataCredibilityPresenter.credibility(snapshot: nil),
            .pendingRefresh
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.credibility(snapshot: snapshot(fetchHealth: .ok, valueFreshness: .live)),
            .officialLive
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.credibility(snapshot: snapshot(fetchHealth: .ok, valueFreshness: .cachedFallback)),
            .localCache
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.credibility(snapshot: snapshot(fetchHealth: .ok, valueFreshness: .live, sourceLabel: "CLI+Web")),
            .localEstimate
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.credibility(snapshot: snapshot(fetchHealth: .ok, valueFreshness: .empty)),
            .pendingRefresh
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.credibility(snapshot: snapshot(fetchHealth: .unreachable, valueFreshness: .cachedFallback)),
            .refreshFailed(showsStaleData: true)
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.credibility(snapshot: snapshot(fetchHealth: .unreachable, valueFreshness: .empty)),
            .refreshFailed(showsStaleData: false)
        )
    }

    func testLocalEstimateSourceDetectionFollowsCodebaseLabelConvention() {
        XCTAssertTrue(MenuDataCredibilityPresenter.isLocalEstimateSource("CLI"))
        XCTAssertTrue(MenuDataCredibilityPresenter.isLocalEstimateSource("CLI-RPC+Web"))
        XCTAssertTrue(MenuDataCredibilityPresenter.isLocalEstimateSource("Local Fallback"))
        XCTAssertTrue(MenuDataCredibilityPresenter.isLocalEstimateSource("IDE"))
        XCTAssertFalse(MenuDataCredibilityPresenter.isLocalEstimateSource("API"))
        XCTAssertFalse(MenuDataCredibilityPresenter.isLocalEstimateSource("API+Web"))
        XCTAssertFalse(MenuDataCredibilityPresenter.isLocalEstimateSource("Web"))
        XCTAssertFalse(MenuDataCredibilityPresenter.isLocalEstimateSource("Graph API"))
        XCTAssertFalse(MenuDataCredibilityPresenter.isLocalEstimateSource(""))
    }

    func testLabelsAreBilingualAndNeverClaimOfficialForEstimates() {
        XCTAssertEqual(
            MenuDataCredibilityPresenter.label(.officialLive, language: .zhHans),
            "官方实时"
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.label(.officialLive, language: .en),
            "Live"
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.label(.localCache, language: .zhHans),
            "本地缓存"
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.label(.localEstimate, language: .en),
            "Estimated"
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.label(.pendingRefresh, language: .zhHans),
            "待刷新"
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.label(.refreshFailed(showsStaleData: true), language: .zhHans),
            "刷新失败，显示旧数据"
        )
        XCTAssertEqual(
            MenuDataCredibilityPresenter.label(.refreshFailed(showsStaleData: false), language: .en),
            "Refresh failed"
        )
    }

}
