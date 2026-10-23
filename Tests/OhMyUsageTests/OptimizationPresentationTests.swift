import Foundation
import OhMyUsageApplication
import OhMyUsageDomain
import OhMyUsagePresentation
import OhMyUsageProviders
import XCTest
@testable import OhMyUsage

final class OptimizationPresentationTests: XCTestCase {
    func testUIHasNoDirectProviderImplementationDependency() throws {
        let root = packageRepositoryRootURL()
            .appendingPathComponent("Sources/OhMyUsage/UI")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("import OhMyUsageProviders"), file.lastPathComponent)
            XCTAssertFalse(source.contains("OfficialValueParser."), file.lastPathComponent)
        }
    }

    func testReorderPreviewPreservesNoOpAndDirection() {
        let ids = ["a", "b", "c", "d"]
        XCTAssertEqual(ProviderSidebarReorderPolicy.preview(ids: ids, draggingID: "a", targetID: "c", insertAfter: true), ["b", "c", "a", "d"])
        XCTAssertEqual(ProviderSidebarReorderPolicy.preview(ids: ids, draggingID: "d", targetID: "b", insertAfter: false), ["a", "d", "b", "c"])
        XCTAssertEqual(ProviderSidebarReorderPolicy.preview(ids: ids, draggingID: "b", targetID: "b", insertAfter: true), ids)
        XCTAssertEqual(ProviderSidebarReorderPolicy.preview(ids: ids, draggingID: "a", targetID: "b", insertAfter: false), ids)
        XCTAssertEqual(ProviderSidebarReorderPolicy.preview(ids: ids, draggingID: "missing", targetID: "b", insertAfter: false), ids)
        // Cancel discards the preview; the input remains the original ordering.
        XCTAssertEqual(ids, ["a", "b", "c", "d"])
    }

    func testPercentFactoryRetainsPrecisionAndResetMetadata() {
        let now = Date(timeIntervalSince1970: 123)
        let window = UsageQuotaWindow.percent(
            id: "w", title: "Weekly", usedPercent: 33.125, resetAt: now,
            kind: .weekly, resetSource: .official, observedAt: now,
            serverClockSkew: 2, confidence: .confirmed, windowIdentity: "cycle"
        )
        XCTAssertEqual(window.remainingPercent, 66.875)
        XCTAssertEqual(window.usedPercent, 33.125)
        XCTAssertEqual(window.kind, .weekly)
        XCTAssertEqual(window.resetSource, .official)
        XCTAssertEqual(window.observedAt, now)
        XCTAssertEqual(window.resetAt, now)
        XCTAssertEqual(window.confidence, .confirmed)
        XCTAssertEqual(window.serverClockSkew, 2)
        XCTAssertEqual(window.windowIdentity, "cycle")
        XCTAssertEqual(UsageQuotaWindow.percent(id: "w", title: "", usedPercent: 110, kind: .custom).remainingPercent, 0)
    }

    func testSharedTextParsingPreservesUnicodeCapturesAndBase64() {
        XCTAssertEqual(ProviderTextParsing.regexCaptures(in: "前缀 Bonus credits: 12/20", pattern: #"Bonus credits: (\d+)/(\d+)"#), ["Bonus credits: 12/20", "12", "20"])
        XCTAssertEqual(ProviderTextParsing.regexCaptures(in: "test", pattern: "["), [])
        XCTAssertEqual(ProviderTextParsing.decodeBase64URL("SGVsbG8"), Data("Hello".utf8))
        XCTAssertNil(ProviderTextParsing.decodeBase64URL("!!!"))
        XCTAssertEqual(ProviderTextParsing.clampPercent(12.345), 12.345)
        XCTAssertEqual(ProviderTextParsing.clampPercent(-1), 0)
    }

    func testAccountLabelPresentationDropsOnlyPlaceholders() {
        for label in [nil, "", "  ", " Unknown ", "N/A", "--"] as [String?] {
            XCTAssertNil(AccountLabelPresentation.displayable(label))
        }
        XCTAssertEqual(AccountLabelPresentation.displayable("  示例账号  "), "示例账号")
        XCTAssertEqual(AccountLabelPresentation.displayable("user@example.test"), "user@example.test")
    }

    func testTrendLabelsInBothLanguages() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = Date(timeIntervalSince1970: 1_770_033_600) // 2026-02-02 UTC
        XCTAssertEqual(calendar.component(.weekday, from: monday), 2)
        XCTAssertEqual(LocalUsageTrendFormatter.weeklyLabel(monday, language: .zhHans, calendar: calendar), "周一")
        XCTAssertEqual(LocalUsageTrendFormatter.weeklyLabel(monday, language: .en, calendar: calendar), "Mon")
        XCTAssertEqual(LocalUsageTrendFormatter.diagnosticTime(nil, language: .zhHans), "无")
        XCTAssertEqual(LocalUsageTrendFormatter.diagnosticTime(nil, language: .en), "n/a")
    }

    @MainActor
    func testCredentialTemplateAndDraftMappingRemainBilingualAndScoped() {
        let cookie = RelayCredentialTemplatePresenter.build(authHeader: " cookie ", authScheme: nil, language: .en)
        guard case .cookie = cookie.kind else { return XCTFail("Expected cookie template") }
        XCTAssertTrue(cookie.placeholder.contains("full Cookie"))
        let bearer = RelayCredentialTemplatePresenter.build(authHeader: nil, authScheme: nil, language: .zhHans)
        guard case .bearer = bearer.kind else { return XCTFail("Expected bearer template") }
        XCTAssertTrue(bearer.hint.contains("Bearer"))
        let custom = RelayCredentialTemplatePresenter.build(authHeader: "X-Token", authScheme: "", language: .en)
        guard case .custom(let header, let scheme) = custom.kind else { return XCTFail("Expected custom template") }
        XCTAssertEqual(header, "X-Token")
        XCTAssertEqual(scheme, "")
        let seed = RelaySettingsDraftSeed(provider: ProviderDescriptor.defaultOpenAilinyu())
        var inputs = RelayProviderEditorDraft()
        inputs.accountEnabledInputs[seed.providerID] = false
        inputs.unitInputs[seed.providerID] = "USD"
        inputs.authHeaderInputs["unrelated"] = "Wrong"
        let draft = RelaySettingsDraftBuilder.build(seed: seed, inputs: inputs, name: "Name", baseURL: "https://example.test")
        XCTAssertEqual(draft.name, "Name")
        XCTAssertEqual(draft.baseURL, "https://example.test")
        XCTAssertEqual(draft.unit, "USD")
        XCTAssertFalse(draft.accountEnabled)
        XCTAssertEqual(draft.authHeader, seed.authHeader)
    }
}
