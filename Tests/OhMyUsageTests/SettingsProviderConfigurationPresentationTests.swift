import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class SettingsProviderConfigurationPresentationTests: XCTestCase {
    func testOfficialRelayProvidersUseRelayConfigurationSectionAndExposeCredentialModeDefaults() {
        let providers = [
            ProviderDescriptor.defaultOfficialMoonshot(),
            ProviderDescriptor.defaultOfficialMiniMax(),
            ProviderDescriptor.defaultOfficialDeepSeek(),
            ProviderDescriptor.defaultOfficialXiaomiMIMO()
        ]

        for provider in providers {
            XCTAssertEqual(
                SettingsProviderConfigurationSectionPresenter.sectionKind(for: provider),
                .relay,
                "\(provider.id) should render the relay configuration controls in Official subscriptions"
            )
            XCTAssertEqual(provider.relayConfig?.balanceCredentialMode, .manualPreferred)
            XCTAssertEqual(RelaySettingsDraftSeed(provider: provider).balanceCredentialMode, .manualPreferred)
        }
    }

    func testNonRelayOfficialProvidersUseOfficialConfigurationSection() {
        let providers = [
            ProviderDescriptor.defaultOfficialKimi(),
            ProviderDescriptor.defaultOfficialCodex(),
            ProviderDescriptor.defaultOfficialClaude()
        ]

        for provider in providers {
            XCTAssertEqual(
                SettingsProviderConfigurationSectionPresenter.sectionKind(for: provider),
                .official,
                "\(provider.id) should keep the standard official configuration controls"
            )
        }
    }

    func testRelayDraftPersistsCredentialModeForOfficialRelayProvider() {
        let provider = ProviderDescriptor.defaultOfficialMiniMax()
        var draft = RelaySettingsDraftSeed(provider: provider).draft
        draft.balanceCredentialMode = .browserPreferred

        let preview = RelayDescriptorPreviewBuilder().build(
            draft: draft,
            providers: [provider]
        )

        XCTAssertEqual(preview?.family, .official)
        XCTAssertEqual(preview?.type, .relay)
        XCTAssertEqual(preview?.relayConfig?.adapterID, "minimax")
        XCTAssertEqual(preview?.relayConfig?.balanceCredentialMode, .browserPreferred)
    }

    // MARK: - doc 10.3 凭证折叠区

    func testCredentialDisclosureHeaderAsksForManualSetupWithoutSavedCredential() {
        XCTAssertEqual(
            SettingsCredentialDisclosurePresenter.headerTitle(hasSavedCredential: false, language: .zhHans),
            "手动配置凭证"
        )
        XCTAssertEqual(
            SettingsCredentialDisclosurePresenter.headerTitle(hasSavedCredential: false, language: .en),
            "Set Up Manually"
        )
    }

    func testCredentialDisclosureHeaderOffersReimportWithSavedCredential() {
        XCTAssertEqual(
            SettingsCredentialDisclosurePresenter.headerTitle(hasSavedCredential: true, language: .zhHans),
            "重新导入凭证"
        )
        XCTAssertEqual(
            SettingsCredentialDisclosurePresenter.headerTitle(hasSavedCredential: true, language: .en),
            "Re-import Credentials"
        )
    }

    // MARK: - doc 10.3 更新时间、来源和可信度

    private func provenanceSnapshot(
        freshness: ValueFreshness,
        sourceLabel: String,
        fetchHealth: FetchHealth = .ok
    ) -> UsageSnapshot {
        UsageSnapshot(
            source: "provenance-test",
            status: .ok,
            fetchHealth: fetchHealth,
            valueFreshness: freshness,
            remaining: 80,
            used: 20,
            limit: 100,
            unit: "%",
            updatedAt: Date(timeIntervalSince1970: 0),
            note: "",
            sourceLabel: sourceLabel
        )
    }

    func testProvenanceLineIncludesUpdatedTimeSourceAndFreshness() {
        let line = SettingsProviderProvenancePresenter.provenanceLine(
            updatedAt: Date(timeIntervalSince1970: 0),
            sourceLabel: "API",
            snapshot: provenanceSnapshot(freshness: .live, sourceLabel: "API"),
            now: Date(timeIntervalSince1970: 300),
            language: .zhHans
        )

        XCTAssertEqual(line, "更新于 5 分钟前｜来源：API｜官方实时")
    }

    func testProvenanceLineEnglishKeepsSourceAndFreshnessSegments() {
        let line = SettingsProviderProvenancePresenter.provenanceLine(
            updatedAt: Date(timeIntervalSince1970: 0),
            sourceLabel: "Web",
            snapshot: provenanceSnapshot(freshness: .cachedFallback, sourceLabel: "Web"),
            now: Date(timeIntervalSince1970: 300),
            language: .en
        )

        XCTAssertEqual(line, "Updated 5m ago | Source: Web | Cached")
    }

    func testProvenanceLineNeverPresentsLocalEstimateAsOfficial() {
        let line = SettingsProviderProvenancePresenter.provenanceLine(
            updatedAt: Date(timeIntervalSince1970: 0),
            sourceLabel: "CLI",
            snapshot: provenanceSnapshot(freshness: .live, sourceLabel: "CLI"),
            now: Date(timeIntervalSince1970: 300),
            language: .zhHans
        )

        XCTAssertEqual(line, "更新于 5 分钟前｜来源：CLI｜本地估算")
    }

    func testProvenanceLineMarksFailedRefreshWithStaleData() {
        let line = SettingsProviderProvenancePresenter.provenanceLine(
            updatedAt: Date(timeIntervalSince1970: 0),
            sourceLabel: "API",
            snapshot: provenanceSnapshot(freshness: .cachedFallback, sourceLabel: "API", fetchHealth: .unreachable),
            now: Date(timeIntervalSince1970: 300),
            language: .zhHans
        )

        XCTAssertEqual(line, "更新于 5 分钟前｜来源：API｜刷新失败，显示旧数据")
    }

    func testProvenanceLineOmitsMissingSourceAndFreshness() {
        let line = SettingsProviderProvenancePresenter.provenanceLine(
            updatedAt: Date(timeIntervalSince1970: 0),
            sourceLabel: "   ",
            snapshot: nil,
            now: Date(timeIntervalSince1970: 300),
            language: .zhHans
        )

        XCTAssertEqual(line, "更新于 5 分钟前")
    }

    func testProvenanceLineTrimsSourceLabel() {
        let line = SettingsProviderProvenancePresenter.provenanceLine(
            updatedAt: Date(timeIntervalSince1970: 0),
            sourceLabel: "  CLI  ",
            snapshot: nil,
            now: Date(timeIntervalSince1970: 300),
            language: .en
        )

        XCTAssertEqual(line, "Updated 5m ago | Source: CLI")
    }

    func testProvenanceLineReturnsNilWithoutSnapshotUpdatedAt() {
        let line = SettingsProviderProvenancePresenter.provenanceLine(
            updatedAt: nil,
            sourceLabel: "API",
            snapshot: provenanceSnapshot(freshness: .live, sourceLabel: "API"),
            now: Date(timeIntervalSince1970: 300),
            language: .zhHans
        )

        XCTAssertNil(line)
    }
}
