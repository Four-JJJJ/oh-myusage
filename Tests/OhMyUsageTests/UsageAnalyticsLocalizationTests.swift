import OhMyUsageApplication
import OhMyUsageProviders

import OhMyUsageDomain

import AppKit
import SwiftUI
import XCTest
@testable import OhMyUsage

final class UsageAnalyticsLocalizationTests: XCTestCase {
    func testEveryVisibleCopyHasBothTranslations() {
        let chinese = UsageAnalyticsCopy(language: .zhHans)
        let english = UsageAnalyticsCopy(language: .en)
        let expected: [(UsageAnalyticsCopy.Key, String, String)] = [
            (.refresh, "刷新使用统计", "Refresh usage statistics"),
            (.overview, "总览", "Overview"), (.trend, "使用趋势", "Usage trend"),
            (.statistics, "统计", "Analytics"), (.provider, "供应商", "Provider"), (.model, "模型", "Model"),
            (.all, "全部", "All"), (.last24Hours, "近24小时", "Last 24h"),
            (.last7Days, "近7天", "Last 7d"), (.last30Days, "近30天", "Last 30d"),
            (.requests, "总请求", "Requests"), (.tokens, "总Token", "Tokens"),
            (.input, "输入", "Input"), (.output, "输出", "Output"),
            (.cacheRead, "缓存命中", "Cache read"), (.cacheWrite, "缓存写入", "Cache write"),
            (.cacheRate, "缓存率", "Cache rate"), (.successRate, "成功率", "Success rate"),
            (.emptyTrend, "暂无趋势数据", "No trend data yet"),
            (.emptyData, "暂无匹配的使用数据", "No matching usage data")
        ]
        XCTAssertEqual(expected.count, UsageAnalyticsCopy.Key.allCases.count)
        for (key, zh, en) in expected {
            XCTAssertEqual(chinese.text(key), zh)
            XCTAssertEqual(english.text(key), en)
        }
        XCTAssertEqual(english.timeRangeTitle(.last24Hours), "Last 24h")
        XCTAssertEqual(chinese.timeRangeTitle(.last30Days), "近30天")
    }

    func testMonthTicksAndSourceSubtitleFollowSelectedLanguage() {
        let date = Date(timeIntervalSince1970: 1_778_932_800)
        let end = date.addingTimeInterval(30 * 86400)
        let zh = UsageAnalyticsCopy(language: .zhHans)
        let en = UsageAnalyticsCopy(language: .en)
        XCTAssertTrue(zh.trendTickLabel(date, endAt: end).hasSuffix("月"))
        XCTAssertEqual(en.trendTickLabel(date, endAt: end), "May")
        let source = "统计来源：官方应用本地用量日志 / Cursor dashboard（可用时）"
        XCTAssertEqual(zh.diagnostic(source), source)
        XCTAssertEqual(en.diagnostic(source), "Sources: local app usage logs / Cursor dashboard (when available)")
        XCTAssertEqual(en.diagnostic("Unknown future diagnostic"), "Unknown future diagnostic")
    }

    func testEveryKeyCarriesDistinctNonEmptyTranslations() {
        let chinese = UsageAnalyticsCopy(language: .zhHans)
        let english = UsageAnalyticsCopy(language: .en)
        for key in UsageAnalyticsCopy.Key.allCases {
            let zh = chinese.text(key)
            let en = english.text(key)
            XCTAssertFalse(zh.isEmpty, "missing zh copy for \(key)")
            XCTAssertFalse(en.isEmpty, "missing en copy for \(key)")
            XCTAssertNotEqual(zh, en, "copy for \(key) is not bilingual")
        }
    }

    func testCcSwitchSourceSubtitleTranslatesToEnglish() {
        let source = "统计来源：官方应用本地用量 / Cursor dashboard（可用时）+ cc-switch 请求日志"
        XCTAssertEqual(
            UsageAnalyticsCopy(language: .en).diagnostic(source),
            "Sources: local app usage / Cursor dashboard (when available) + cc-switch request logs"
        )
        XCTAssertEqual(UsageAnalyticsCopy(language: .zhHans).diagnostic(source), source)
    }

    @MainActor
    func testRenderActualStatisticsPageInBothLanguages() throws {
        let directory = URL(fileURLWithPath: "/tmp/omu-analytics-localization")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.zhHans, .en] {
            for populated in [false, true] {
                var config = AppConfig.default
                config.language = language
                config.providers = []
                let model = AppViewModel(testingConfig: config, appUpdateService: AnalyticsNoopUpdateService())
                let theme = SettingsView(viewModel: model).theme
                var snapshot = UsageAnalyticsSnapshot.empty(filter: UsageAnalyticsFilter())
                if populated {
                    let date = Date(timeIntervalSince1970: 1_778_932_800)
                    snapshot.trendBuckets = [UsageTrendBucket(id: "fixture", startAt: date, endAt: date.addingTimeInterval(30 * 86400), totals: snapshot.totals, topProviders: [], topModels: [])]
                    snapshot.providerStats = [UsageProviderStats(id: "fixture", providerID: "fixture", providerName: "Fixture provider", categoryName: "Official", totals: snapshot.totals, share: 1)]
                }
                let view = UsageAnalyticsSettingsView(viewModel: model, theme: theme, rendersLocalizationFixture: true, localizationFixtureSnapshot: snapshot)
                    .frame(width: 820, height: 1000)
                    .background(Color.black)
                    .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(image.width, 820)
                XCTAssertEqual(image.height, 1000)
                let bitmap = NSBitmapImageRep(cgImage: image)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("statistics-\(language.rawValue)-\(populated ? "data" : "empty").png"))
            }
        }
    }
}

private actor AnalyticsNoopUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo { throw ProviderError.unavailable("unused") }
    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate { throw ProviderError.unavailable("unused") }
    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {}
}
