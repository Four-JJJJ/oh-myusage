import Foundation
import OhMyUsageDomain

enum LocalUsageTrendStatusTone: Equatable, Sendable {
    case muted
    case error
}

struct LocalUsageTrendStatusPresentation: Equatable, Sendable {
    var text: String
    var tone: LocalUsageTrendStatusTone
}

struct LocalUsageTrendPresentation: Equatable, Sendable {
    var hasTrendData: Bool
    var displaySummary: LocalUsageSummary?
    var chartStatus: LocalUsageTrendStatusPresentation?
    var staleFallbackText: String?
    var cacheStatusText: String?
}

struct LocalUsageTrendTooltipRow: Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var value: String
}

struct LocalUsageTrendPointTooltip: Equatable, Sendable {
    var title: String
    var rows: [LocalUsageTrendTooltipRow]
}

enum LocalUsageTrendPresenter {
    typealias LocalizedText = (String, String) -> String
    typealias IntegerFormatter = (Int) -> String
    typealias DateTextFormatter = (Date?) -> String

    static func presentation(
        providerType: ProviderType,
        scope: LocalUsageTrendScope,
        historyState: LocalUsageHistoryState,
        summary: LocalUsageSummary?,
        localizedText: LocalizedText,
        formatInteger: IntegerFormatter,
        dateText: DateTextFormatter
    ) -> LocalUsageTrendPresentation {
        let chartError = historyState.isStaleFallback && historyState.summary != nil
            ? nil
            : historyState.error
        let hasTrendData = summary.map { hasData($0) } ?? false
        let chartStatus = chartStatus(
            providerType: providerType,
            scope: scope,
            summary: summary,
            loading: historyState.isLoading,
            error: chartError,
            hasData: hasTrendData,
            localizedText: localizedText,
            formatInteger: formatInteger
        )

        return LocalUsageTrendPresentation(
            hasTrendData: hasTrendData,
            displaySummary: hasTrendData ? summary : nil,
            chartStatus: chartStatus,
            staleFallbackText: staleFallbackText(
                historyState,
                localizedText: localizedText
            ),
            cacheStatusText: cacheStatusText(
                historyState,
                summary: summary,
                localizedText: localizedText,
                dateText: dateText
            )
        )
    }

    static func pointTooltip(
        for point: LocalUsageTrendPoint,
        language: AppLanguage,
        localizedText: LocalizedText
    ) -> LocalUsageTrendPointTooltip {
        let compactToken = { (value: Int) in
            LocalTrendValueFormatter.compactNumber(max(0, value), language: language)
        }

        return LocalUsageTrendPointTooltip(
            title: hourRangeTitle(startAt: point.startAt),
            rows: [
                LocalUsageTrendTooltipRow(
                    id: "total",
                    label: localizedText("总Token", "Total"),
                    value: compactToken(point.totalTokens)
                ),
                LocalUsageTrendTooltipRow(
                    id: "input",
                    label: localizedText("输入", "Input"),
                    value: compactToken(point.inputTokens)
                ),
                LocalUsageTrendTooltipRow(
                    id: "output",
                    label: localizedText("输出", "Output"),
                    value: compactToken(point.outputTokens)
                ),
                LocalUsageTrendTooltipRow(
                    id: "cacheRead",
                    label: localizedText("缓存命中", "Cache Hit"),
                    value: compactToken(point.cacheReadTokens)
                ),
                LocalUsageTrendTooltipRow(
                    id: "cacheWrite",
                    label: localizedText("缓存写入", "Cache Write"),
                    value: compactToken(point.cacheWriteTokens)
                ),
                LocalUsageTrendTooltipRow(
                    id: "responses",
                    label: localizedText("请求", "Requests"),
                    value: LocalTrendValueFormatter.responseCountText(point.responses, language: language)
                )
            ]
        )
    }

    static func hourRangeTitle(startAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:00"
        let startText = formatter.string(from: startAt)
        let endDate = Calendar(identifier: .gregorian).date(byAdding: .hour, value: 1, to: startAt)
            ?? startAt.addingTimeInterval(3600)
        let endText = formatter.string(from: endDate)
        return "\(startText)–\(endText)"
    }

    static func hasData(_ summary: LocalUsageSummary) -> Bool {
        if summary.today.totalTokens > 0 || summary.today.responses > 0 { return true }
        if summary.yesterday.totalTokens > 0 || summary.yesterday.responses > 0 { return true }
        if summary.last30Days.totalTokens > 0 || summary.last30Days.responses > 0 { return true }
        if summary.hourly24.contains(where: { $0.totalTokens > 0 || $0.responses > 0 }) { return true }
        if summary.daily7.contains(where: { $0.totalTokens > 0 || $0.responses > 0 }) { return true }
        return false
    }

    private static func chartStatus(
        providerType: ProviderType,
        scope: LocalUsageTrendScope,
        summary: LocalUsageSummary?,
        loading: Bool,
        error: String?,
        hasData: Bool,
        localizedText: LocalizedText,
        formatInteger: IntegerFormatter
    ) -> LocalUsageTrendStatusPresentation? {
        if loading {
            return LocalUsageTrendStatusPresentation(
                text: localizedText("加载中...", "Loading..."),
                tone: .muted
            )
        }
        if let error, !error.isEmpty {
            return LocalUsageTrendStatusPresentation(
                text: error,
                tone: .error
            )
        }
        if !hasData {
            if providerType == .codex, scope == .currentAccount {
                if let diagnostics = summary?.diagnostics,
                   diagnostics.unattributedResponses > 0 || diagnostics.unattributedTokens > 0 {
                    let unattributedResponses = formatInteger(diagnostics.unattributedResponses)
                    let unattributedTokens = formatInteger(diagnostics.unattributedTokens)
                    let text = localizedText(
                        "当前账号暂无可归属事件（未归属 \(unattributedResponses) 条/\(unattributedTokens) Token）",
                        "No attributable events for current account (Unattributed \(unattributedResponses)/\(unattributedTokens) tokens)"
                    )
                    return LocalUsageTrendStatusPresentation(text: text, tone: .muted)
                }
                return LocalUsageTrendStatusPresentation(
                    text: localizedText("当前账号暂无可归属事件", "No attributable events for current account"),
                    tone: .muted
                )
            }

            let noDataText = localizedText("暂无数据", "No data")
            return LocalUsageTrendStatusPresentation(
                text: noDataText,
                tone: .muted
            )
        }
        return nil
    }

    private static func staleFallbackText(
        _ state: LocalUsageHistoryState,
        localizedText: LocalizedText
    ) -> String? {
        guard state.isStaleFallback,
              state.summary != nil,
              let error = trimmed(state.error) else {
            return nil
        }
        return localizedText(
            "刷新失败，显示旧缓存：\(error)",
            "Refresh failed, showing cached data: \(error)"
        )
    }

    private static func cacheStatusText(
        _ state: LocalUsageHistoryState,
        summary: LocalUsageSummary?,
        localizedText: LocalizedText,
        dateText: DateTextFormatter
    ) -> String? {
        guard let summary else { return nil }

        let generatedText = dateText(summary.generatedAt)
        if let checkedAt = state.lastFingerprintCheckedAt {
            let checkedText = dateText(checkedAt)
            return localizedText(
                "缓存已校验 \(checkedText) · 图表生成 \(generatedText)",
                "Cache checked \(checkedText) · Chart generated \(generatedText)"
            )
        }

        if let refreshedAt = state.lastRefreshedAt {
            let refreshedText = dateText(refreshedAt)
            return localizedText(
                "缓存生成 \(refreshedText) · 图表生成 \(generatedText)",
                "Cache generated \(refreshedText) · Chart generated \(generatedText)"
            )
        }

        return nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
