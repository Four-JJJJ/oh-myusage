import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class SettingsViewQuotaDisplayTests: XCTestCase {
    func testResolvedOfficialMonitoringProviderPrefersConfiguredClaudeProvider() {
        var claude = ProviderDescriptor.defaultOfficialClaude()
        claude.officialConfig?.quotaDisplayMode = .remaining

        let resolved = SettingsQuotaPresenter.resolvedOfficialMonitoringProvider(
            type: .claude,
            providers: [claude]
        )

        XCTAssertFalse(resolved.displaysUsedQuota)
    }

    func testResolvedOfficialMonitoringProviderFallsBackToClaudeDefaultWhenMissing() {
        let resolved = SettingsQuotaPresenter.resolvedOfficialMonitoringProvider(
            type: .claude,
            providers: []
        )

        XCTAssertTrue(resolved.displaysUsedQuota)
    }

    func testOfficialRelayDisplaysUsedQuotaReadsRelayConfig() {
        var provider = ProviderDescriptor.defaultOfficialMiniMax()

        provider.relayConfig?.quotaDisplayMode = .used
        XCTAssertTrue(provider.displaysUsedQuota)

        provider.relayConfig?.quotaDisplayMode = .remaining
        XCTAssertFalse(provider.displaysUsedQuota)
    }

    func testOfficialXiaomiMIMODefaultsToUsedQuotaDisplayMode() {
        let provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()

        XCTAssertEqual(provider.relayConfig?.quotaDisplayMode, .used)
        XCTAssertTrue(provider.displaysUsedQuota)
    }

    func testOfficialXiaomiMIMOCanSwitchToRemainingQuotaDisplayMode() {
        var provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()

        provider.relayConfig?.quotaDisplayMode = .remaining

        XCTAssertFalse(provider.displaysUsedQuota)
    }

    func testOfficialXiaomiMIMOSupportsExpirationTimeDisplayToggle() {
        var provider = ProviderDescriptor.defaultOfficialXiaomiMIMO()

        XCTAssertTrue(provider.supportsExpirationTimeDisplay(snapshot: nil))
        XCTAssertTrue(provider.showsExpirationTimeInMenuBar)

        provider.relayConfig?.showExpirationTimeInMenuBar = false

        XCTAssertFalse(provider.showsExpirationTimeInMenuBar)
    }

    func testQuotaMetricPercentsKeepDisplayAndHealthSeparateInUsedMode() {
        let window = UsageQuotaWindow(
            id: "claude-session",
            title: "5h limit",
            remainingPercent: 71,
            usedPercent: 29,
            resetAt: nil,
            kind: .session
        )

        let percents = SettingsQuotaPresenter.quotaMetricPercents(
            for: window,
            displaysUsedQuota: true
        )

        XCTAssertEqual(percents.displayPercent, 29, accuracy: 0.0001)
        XCTAssertEqual(percents.healthPercent, 71, accuracy: 0.0001)
    }

    func testSessionQuotaIsBlockedWhenWeeklyQuotaIsDepleted() {
        let session = UsageQuotaWindow(
            id: "codex-session",
            title: "5h",
            remainingPercent: 127,
            usedPercent: 0,
            resetAt: nil,
            kind: .session
        )
        let weekly = UsageQuotaWindow(
            id: "codex-weekly",
            title: "Weekly",
            remainingPercent: 0,
            usedPercent: 100,
            resetAt: nil,
            kind: .weekly
        )

        let blocked = QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(
            window: session,
            in: [session, weekly],
            provider: .defaultOfficialCodex()
        )

        XCTAssertTrue(blocked)
    }

    func testSessionQuotaIsNotBlockedWhenWeeklyQuotaHasRemainingCapacity() {
        let session = UsageQuotaWindow(
            id: "codex-session",
            title: "5h",
            remainingPercent: 127,
            usedPercent: 0,
            resetAt: nil,
            kind: .session
        )
        let weekly = UsageQuotaWindow(
            id: "codex-weekly",
            title: "Weekly",
            remainingPercent: 1,
            usedPercent: 99,
            resetAt: nil,
            kind: .weekly
        )

        let blocked = QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(
            window: session,
            in: [session, weekly],
            provider: .defaultOfficialCodex()
        )

        XCTAssertFalse(blocked)
    }

    func testSessionQuotaIsNotBlockedWhenSessionQuotaIsDepleted() {
        let session = UsageQuotaWindow(
            id: "codex-session",
            title: "5h",
            remainingPercent: 0,
            usedPercent: 100,
            resetAt: nil,
            kind: .session
        )
        let weekly = UsageQuotaWindow(
            id: "codex-weekly",
            title: "Weekly",
            remainingPercent: 0,
            usedPercent: 100,
            resetAt: nil,
            kind: .weekly
        )

        let blocked = QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(
            window: session,
            in: [session, weekly],
            provider: .defaultOfficialCodex()
        )

        XCTAssertFalse(blocked)
    }

    func testKimiOverallCustomWindowCountsAsWeeklyQuotaForBlocking() {
        let session = UsageQuotaWindow(
            id: "kimi-session",
            title: "5h",
            remainingPercent: 42,
            usedPercent: 58,
            resetAt: nil,
            kind: .session
        )
        let overall = UsageQuotaWindow(
            id: "kimi-overall",
            title: "Overall",
            remainingPercent: 0,
            usedPercent: 100,
            resetAt: nil,
            kind: .custom
        )

        let blocked = QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(
            window: session,
            in: [session, overall],
            provider: .defaultOfficialKimi()
        )

        XCTAssertTrue(blocked)
    }

    func testKimiOverallCandidateBlocksEvenWhenOtherCustomWindowsExist() {
        let session = UsageQuotaWindow(
            id: "kimi-session",
            title: "5h",
            remainingPercent: 42,
            usedPercent: 58,
            resetAt: nil,
            kind: .session
        )
        let otherCustom = UsageQuotaWindow(
            id: "kimi-model",
            title: "Model Window",
            remainingPercent: 100,
            usedPercent: 0,
            resetAt: nil,
            kind: .custom
        )
        let overall = UsageQuotaWindow(
            id: "kimi-overall",
            title: "Overall",
            remainingPercent: 0,
            usedPercent: 100,
            resetAt: nil,
            kind: .custom
        )

        let blocked = QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(
            window: session,
            in: [session, otherCustom, overall],
            provider: .defaultOfficialKimi()
        )

        XCTAssertTrue(blocked)
    }

    func testOfficialMonitoringHealthStatusUsesRemainingHealthWhenDisplayModeIsUsed() {
        let snapshot = UsageSnapshot(
            source: "claude-official",
            status: .ok,
            remaining: 71,
            used: 29,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "claude-session",
                    title: "5h limit",
                    remainingPercent: 71,
                    usedPercent: 29,
                    resetAt: nil,
                    kind: .session
                )
            ],
            sourceLabel: "API"
        )

        let status = SettingsQuotaPresenter.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: [71]
        )

        XCTAssertEqual(status, .sufficient)
    }

    func testOfficialMonitoringHealthStatusKeepsRemainingThresholdBehavior() {
        let snapshot = UsageSnapshot(
            source: "claude-official",
            status: .ok,
            remaining: 25,
            used: 75,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 1),
            note: "ok",
            quotaWindows: [
                UsageQuotaWindow(
                    id: "claude-session",
                    title: "5h limit",
                    remainingPercent: 25,
                    usedPercent: 75,
                    resetAt: nil,
                    kind: .session
                )
            ],
            sourceLabel: "API"
        )

        let status = SettingsQuotaPresenter.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: [25]
        )

        XCTAssertEqual(status, .tight)
    }
}
