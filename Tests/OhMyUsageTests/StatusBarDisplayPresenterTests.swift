import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class StatusBarDisplayPresenterTests: XCTestCase {
    func testDisplayNameFallsBackToAPIForBlankRelayName() {
        let provider = makeProvider(name: "   ", family: .thirdParty, type: .relay)

        XCTAssertEqual(StatusBarDisplayPresenter.displayName(for: provider), "API")
    }

    func testBarStyleUsesThirdPartyBaselinePercentWhenLimitIsMissingWithIntegerValueText() {
        let provider = makeProvider(name: "Relay", family: .thirdParty, type: .relay)
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 12.34,
            used: 87.66,
            limit: nil,
            unit: "$",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [],
            sourceLabel: "API"
        )
        let source = StatusBarDisplaySource(
            provider: provider,
            snapshot: snapshot,
            thirdPartyBarPercent: 61
        )

        let item = StatusBarDisplayPresenter.displayItem(for: source, style: .barNamePercent)

        XCTAssertEqual(item.valueText, "12")
        assertPercent(item.percent, equals: 61)
    }

    func testBarStyleUsesRemainingLimitPercentBeforeThirdPartyBaselineForCodexProxy() {
        let provider = makeProvider(name: "Codex代理", family: .thirdParty, type: .relay)
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 319.332608,
            used: 180.667392,
            limit: 500,
            unit: "quota",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [],
            sourceLabel: "API"
        )
        let source = StatusBarDisplaySource(
            provider: provider,
            snapshot: snapshot,
            thirdPartyBarPercent: 9
        )

        let item = StatusBarDisplayPresenter.displayItem(for: source, style: .barNamePercent)

        XCTAssertEqual(item.valueText, "319")
        assertPercent(item.percent, equals: 63.8665216)
    }

    func testBarStyleUsesRemainingLimitPercentBeforeThirdPartyBaselineForCodexSelfUse() {
        let provider = makeProvider(name: "Codex自用", family: .thirdParty, type: .relay)
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 181.178872,
            used: 18.821128,
            limit: 200,
            unit: "quota",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [],
            sourceLabel: "API"
        )
        let source = StatusBarDisplaySource(
            provider: provider,
            snapshot: snapshot,
            thirdPartyBarPercent: 9
        )

        let item = StatusBarDisplayPresenter.displayItem(for: source, style: .barNamePercent)

        XCTAssertEqual(item.valueText, "181")
        assertPercent(item.percent, equals: 90.589436)
    }

    func testBarStyleFallsBackToThirdPartyBaselineWhenLimitIsInvalid() {
        let provider = makeProvider(name: "Relay", family: .thirdParty, type: .relay)
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 42,
            used: 58,
            limit: 0,
            unit: "quota",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [],
            sourceLabel: "API"
        )
        let source = StatusBarDisplaySource(
            provider: provider,
            snapshot: snapshot,
            thirdPartyBarPercent: 37
        )

        let item = StatusBarDisplayPresenter.displayItem(for: source, style: .barNamePercent)

        XCTAssertEqual(item.valueText, "42")
        assertPercent(item.percent, equals: 37)
    }

    func testThirdPartyAmountUsesGroupedIntegerValueText() {
        let provider = makeProvider(name: "Relay", family: .thirdParty, type: .relay)
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 34_746.63,
            used: 1000,
            limit: nil,
            unit: "$",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [],
            sourceLabel: "API"
        )
        let source = StatusBarDisplaySource(provider: provider, snapshot: snapshot, thirdPartyBarPercent: nil)

        let item = StatusBarDisplayPresenter.displayItem(for: source, style: .iconPercent)

        XCTAssertEqual(item.valueText, "34,746")
    }

    func testTraeAmountModeUsesIntegerValueText() {
        let provider = makeProvider(
            name: "Trae SOLO",
            family: .official,
            type: .trae,
            officialConfig: OfficialProviderConfig(
                traeValueDisplayMode: .amount
            )
        )
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 64,
            used: 36,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [],
            sourceLabel: "Official",
            extras: ["dollarRemaining": "12.5"]
        )
        let source = StatusBarDisplaySource(provider: provider, snapshot: snapshot, thirdPartyBarPercent: nil)

        let item = StatusBarDisplayPresenter.displayItem(for: source, style: .iconPercent)

        XCTAssertEqual(item.valueText, "12")
        assertPercent(item.percent, equals: 64)
    }

    func testSessionQuotaDrivesPercentAndValueTextForCodexStyleDisplay() {
        let provider = makeProvider(name: "Codex", family: .official, type: .codex)
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 72,
            used: 28,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "window-session",
                    title: "5h limit",
                    remainingPercent: 72,
                    usedPercent: 28,
                    resetAt: nil,
                    kind: .session
                )
            ],
            sourceLabel: "Codex"
        )
        let source = StatusBarDisplaySource(provider: provider, snapshot: snapshot, thirdPartyBarPercent: nil)

        let item = StatusBarDisplayPresenter.displayItem(for: source, style: .iconPercent)

        XCTAssertEqual(item.valueText, "72%")
        assertPercent(item.percent, equals: 72)
    }

    func testMimoTokenPlanStatusBarUsesRemainingPercentWhenPreferenceIsRemaining() {
        var provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        provider.relayConfig?.quotaDisplayMode = .remaining
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 99.66389942402705,
            used: 0.336100575972948,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "token-plan-total",
                    title: "Total Usage",
                    remainingPercent: 99.66389942402705,
                    usedPercent: 0.336100575972948,
                    kind: .custom
                )
            ],
            sourceLabel: "Xiaomi MIMO"
        )
        let source = StatusBarDisplaySource(provider: provider, snapshot: snapshot, thirdPartyBarPercent: nil)

        let item = StatusBarDisplayPresenter.displayItem(for: source, style: .iconPercent)

        XCTAssertEqual(item.valueText, "100%")
        assertPercent(item.percent, equals: 99.66389942402705)
    }

    func testMimoTokenPlanStatusBarUsesUsedPercentWhenPreferenceIsUsed() {
        var provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        provider.relayConfig?.quotaDisplayMode = .used
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 99.66389942402705,
            used: 0.336100575972948,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "test",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "token-plan-total",
                    title: "Total Usage",
                    remainingPercent: 99.66389942402705,
                    usedPercent: 0.336100575972948,
                    kind: .custom
                )
            ],
            sourceLabel: "Xiaomi MIMO"
        )
        let source = StatusBarDisplaySource(provider: provider, snapshot: snapshot, thirdPartyBarPercent: nil)

        let item = StatusBarDisplayPresenter.displayItem(for: source, style: .iconPercent)

        XCTAssertEqual(item.valueText, "0%")
        assertPercent(item.percent, equals: 0.336100575972948)
    }

    private func makeProvider(
        name: String,
        family: ProviderFamily,
        type: ProviderType,
        officialConfig: OfficialProviderConfig? = nil
    ) -> ProviderDescriptor {
        ProviderDescriptor(
            id: "\(type.rawValue)-\(family.rawValue)",
            name: name,
            family: family,
            type: type,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            officialConfig: officialConfig
        )
    }

    private func assertPercent(
        _ actual: Double?,
        equals expected: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected percent value, got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected, accuracy: 0.0001, file: file, line: line)
    }
}
