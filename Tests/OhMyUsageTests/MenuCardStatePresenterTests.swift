import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class MenuCardStatePresenterTests: XCTestCase {
    func testPercentageVisualPresentationTreatsLowMimoUsedPercentAsSufficient() {
        let snapshot = UsageSnapshot(
            source: "xiaomi-mimo-official",
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .live,
            remaining: 99.66389942402705,
            used: 0.336100575972948,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Xiaomi MIMO"
        )

        let presentation = MenuCardStatePresenter.percentageVisualPresentation(
            snapshot: snapshot,
            errorText: nil,
            healthPercents: [99.66389942402705],
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertEqual(presentation.status.text, "充足")
        XCTAssertEqual(presentation.status.tone, .normal)
        XCTAssertFalse(presentation.isDisconnected)
    }

    func testPercentageVisualPresentationTreatsCachedFallbackAsHighlightedButNotDisconnected() {
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

        let presentation = MenuCardStatePresenter.percentageVisualPresentation(
            snapshot: snapshot,
            errorText: "cached error",
            healthPercents: [80],
            language: .zhHans,
            tightText: "紧张",
            sufficientText: "充足",
            exhaustedText: "耗尽",
            disconnectedText: "失联"
        )

        XCTAssertFalse(presentation.isDisconnected)
        XCTAssertTrue(presentation.showsErrorHighlight)
        XCTAssertEqual(presentation.errorText, "cached error")
        XCTAssertEqual(presentation.status.text, "故障")
    }

    func testAmountPresentationSuppressesValueAndSecondaryTextForCachedFallback() {
        var provider = ProviderDescriptor.defaultOpenAilinyu()
        provider.relayConfig?.quotaDisplayMode = .used
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            fetchHealth: .ok,
            valueFreshness: .cachedFallback,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: provider.name
        )

        let presentation = MenuCardStatePresenter.amountPresentation(
            provider: provider,
            snapshot: snapshot,
            errorText: "cached fallback",
            language: .en,
            secondaryText: "Requests 42",
            usedLabel: "Used",
            balanceLabel: "Balance",
            tightText: "Tight",
            sufficientText: "Sufficient",
            exhaustedText: "Exhausted",
            disconnectedText: "Disconnected"
        )

        XCTAssertTrue(presentation.visual.isDisconnected)
        XCTAssertFalse(presentation.visual.showsErrorHighlight)
        XCTAssertEqual(presentation.amountText, "-")
        XCTAssertNil(presentation.secondaryText)
        XCTAssertEqual(presentation.balanceLabel, "Used")
    }

    func testAmountPresentationHighlightsDisconnectedLiveError() {
        let provider = ProviderDescriptor.defaultOpenAilinyu()
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .error,
            fetchHealth: .unreachable,
            valueFreshness: .live,
            remaining: 30,
            used: 70,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "fail",
            sourceLabel: provider.name
        )

        let presentation = MenuCardStatePresenter.amountPresentation(
            provider: provider,
            snapshot: snapshot,
            errorText: "network error",
            language: .en,
            secondaryText: "Requests 42",
            usedLabel: "Used",
            balanceLabel: "Balance",
            tightText: "Tight",
            sufficientText: "Sufficient",
            exhaustedText: "Exhausted",
            disconnectedText: "Disconnected"
        )

        XCTAssertTrue(presentation.visual.isDisconnected)
        XCTAssertTrue(presentation.visual.showsErrorHighlight)
        XCTAssertEqual(presentation.amountText, "-")
        XCTAssertNil(presentation.secondaryText)
        XCTAssertEqual(presentation.visual.status.text, "Failure")
    }

    func testSlotActionPresentationOnlyShowsSwitchWhenInactiveAndSwitchable() {
        let inactive = MenuCardStatePresenter.slotActionPresentation(
            isActive: false,
            canSwitch: true,
            isSwitching: true,
            actionLabel: "Switch",
            infoText: "Failed",
            infoIsError: true
        )

        XCTAssertFalse(inactive.showsLeadingAccent)
        XCTAssertEqual(inactive.actionLabel, "Switch")
        XCTAssertTrue(inactive.actionDisabled)
        XCTAssertEqual(inactive.infoTone, .error)

        let active = MenuCardStatePresenter.slotActionPresentation(
            isActive: true,
            canSwitch: true,
            isSwitching: false,
            actionLabel: "Switch",
            infoText: nil,
            infoIsError: false
        )

        XCTAssertTrue(active.showsLeadingAccent)
        XCTAssertNil(active.actionLabel)
        XCTAssertFalse(active.actionDisabled)
        XCTAssertEqual(active.infoTone, .normal)
    }
}
