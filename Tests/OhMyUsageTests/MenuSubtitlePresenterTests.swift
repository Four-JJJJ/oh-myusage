import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class MenuSubtitlePresenterTests: XCTestCase {
    func testOfficialAccountSubtitleIncludesCodexAliasWhenMultipleTeamsExist() {
        let primary = codexSnapshot(email: "user@example.com", teamID: "team-a")
        let secondary = codexSnapshot(email: "user@example.com", teamID: "team-b")
        let aliases = MenuSubtitlePresenter.codexTeamAliasMap(from: [primary, secondary])

        let subtitle = MenuSubtitlePresenter.officialAccountSubtitle(
            providerType: .codex,
            snapshot: secondary,
            showAccountEmail: true,
            codexTeamAliases: aliases
        )

        XCTAssertEqual(subtitle, "user@example.com · Team B")
    }

    func testOfficialAccountSubtitleCanShowAliasWithoutEmail() {
        let primary = codexSnapshot(email: "user@example.com", teamID: "team-a")
        let secondary = codexSnapshot(email: "user@example.com", teamID: "team-b")
        let aliases = MenuSubtitlePresenter.codexTeamAliasMap(from: [primary, secondary])

        let subtitle = MenuSubtitlePresenter.officialAccountSubtitle(
            providerType: .codex,
            snapshot: primary,
            showAccountEmail: false,
            codexTeamAliases: aliases
        )

        XCTAssertEqual(subtitle, "Team A")
    }

    func testRelaySecondaryTextOnlyAppliesToGenericNewAPI() {
        var provider = ProviderDescriptor.defaultOpenAilinyu()
        provider.relayConfig?.adapterID = "generic-newapi"
        let snapshot = UsageSnapshot(
            source: provider.id,
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: provider.name,
            rawMeta: [
                "account.requestCount": "42"
            ]
        )

        XCTAssertEqual(
            MenuSubtitlePresenter.relaySecondaryText(
                provider: provider,
                snapshot: snapshot,
                language: .en
            ),
            "Requests 42"
        )

        provider.relayConfig?.adapterID = "other-adapter"
        XCTAssertNil(
            MenuSubtitlePresenter.relaySecondaryText(
                provider: provider,
                snapshot: snapshot,
                language: .en
            )
        )
    }

    func testRelayQuotaSubtitleFormatsTokenPlanEndDate() {
        let snapshot = UsageSnapshot(
            source: "relay",
            status: .ok,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Relay",
            rawMeta: [
                "account.tokenPlanCurrentPeriodEnd": "2026-05-09T00:00:00Z"
            ]
        )

        XCTAssertEqual(
            MenuSubtitlePresenter.relayQuotaSubtitle(snapshot: snapshot, language: .zhHans),
            "有效期至 2026-05-09T00:00:00Z (UTC)"
        )
        XCTAssertNil(
            MenuSubtitlePresenter.relayQuotaSubtitle(
                snapshot: snapshot,
                language: .zhHans,
                showExpirationTime: false
            )
        )
    }

    private func codexSnapshot(email: String, teamID: String) -> UsageSnapshot {
        UsageSnapshot(
            source: "codex-official",
            status: .ok,
            remaining: 75,
            used: 25,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Official Codex",
            accountLabel: email,
            rawMeta: [
                "codex.accountLabel": email,
                "codex.accountId": teamID,
                "codex.teamId": teamID
            ]
        )
    }
}
