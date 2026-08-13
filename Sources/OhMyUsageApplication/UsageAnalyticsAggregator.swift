import Foundation

public enum UsageAnalyticsAggregator {
    private enum TrendBucketGranularity: String {
        case hour
        case day
        case sevenDay
        case month
        case quarter
    }

    private struct TrendBucketPlan {
        var starts: [Date]
        var granularity: TrendBucketGranularity
    }

    private struct ProviderKey: Hashable {
        var providerID: String
        var providerName: String
        var categoryName: String
    }

    private struct ModelOptionAccumulator {
        var title: String
        var firstEventAt: Date
        var firstRequestID: String
        var totalTokens: Int

        init(record: UsageAnalyticsRecord) {
            title = displayValue(record.modelID)
            firstEventAt = record.eventAt
            firstRequestID = record.requestID
            totalTokens = 0
            add(record)
        }

        mutating func add(_ record: UsageAnalyticsRecord) {
            totalTokens += record.totals.totalTokens
            if record.eventAt < firstEventAt
                || (record.eventAt == firstEventAt && record.requestID < firstRequestID) {
                title = displayValue(record.modelID)
                firstEventAt = record.eventAt
                firstRequestID = record.requestID
            }
        }
    }

    private struct ModelGroup {
        var modelID: String
        var firstEventAt: Date
        var firstRequestID: String
        var appTypes: Set<String>
        var providerNames: Set<String>
        var totals: UsageMetricTotals

        init(record: UsageAnalyticsRecord) {
            modelID = displayValue(record.modelID)
            firstEventAt = record.eventAt
            firstRequestID = record.requestID
            appTypes = []
            providerNames = []
            totals = UsageMetricTotals()
            add(record)
        }

        mutating func add(_ record: UsageAnalyticsRecord) {
            if record.eventAt < firstEventAt
                || (record.eventAt == firstEventAt && record.requestID < firstRequestID) {
                modelID = displayValue(record.modelID)
                firstEventAt = record.eventAt
                firstRequestID = record.requestID
            }
            appTypes.insert(displayValue(record.appType))
            providerNames.insert(displayValue(record.providerName))
            totals.add(record.totals)
        }
    }

    private struct SnapshotAccumulator {
        var totals = UsageMetricTotals()
        var availableModelsByModel: [String: ModelOptionAccumulator] = [:]
        var categoryTotals: [String: UsageMetricTotals] = [:]
        var providerTotals: [ProviderKey: UsageMetricTotals] = [:]
        var modelGroups: [String: ModelGroup] = [:]
        var firstEventAt: Date?
        var lastEventAt: Date?

        mutating func addAvailableModel(_ record: UsageAnalyticsRecord) {
            let key = modelKey(record.modelID)
            if var item = availableModelsByModel[key] {
                item.add(record)
                availableModelsByModel[key] = item
            } else {
                availableModelsByModel[key] = ModelOptionAccumulator(record: record)
            }
        }

        mutating func addFilteredRecord(_ record: UsageAnalyticsRecord) {
            totals.add(record.totals)
            let categoryName = providerCategory(for: record)
            categoryTotals[categoryName, default: UsageMetricTotals()].add(record.totals)
            let providerKey = ProviderKey(
                providerID: record.providerID,
                providerName: record.providerName,
                categoryName: categoryName
            )
            providerTotals[providerKey, default: UsageMetricTotals()].add(record.totals)

            let modelGroupKey = modelKey(record.modelID)
            if var group = modelGroups[modelGroupKey] {
                group.add(record)
                modelGroups[modelGroupKey] = group
            } else {
                modelGroups[modelGroupKey] = ModelGroup(record: record)
            }

            if firstEventAt == nil || record.eventAt < firstEventAt! {
                firstEventAt = record.eventAt
            }
            if lastEventAt == nil || record.eventAt > lastEventAt! {
                lastEventAt = record.eventAt
            }
        }
    }

    private struct TrendBucketAccumulator {
        var totals = UsageMetricTotals()
        var providerTotals: [String: UsageMetricTotals] = [:]
        var modelTotals: [String: UsageMetricTotals] = [:]

        mutating func add(_ record: UsageAnalyticsRecord) {
            totals.add(record.totals)
            providerTotals[record.providerName, default: UsageMetricTotals()].add(record.totals)
            modelTotals[modelKey(record.modelID), default: UsageMetricTotals()].add(record.totals)
        }
    }

    public static func snapshot(
        records: [UsageAnalyticsRecord],
        filter: UsageAnalyticsFilter,
        calendar: Calendar,
        now: Date,
        diagnostics: [String]
    ) -> UsageAnalyticsSnapshot {
        let interval = rangeInterval(filter.range, calendar: calendar, now: now)
        let dedupedRecords = deduplicated(records, in: interval)
        let selectedModelKey = selectedModelKey(for: filter)
        var accumulator = SnapshotAccumulator()
        for record in dedupedRecords.values {
            accumulator.addAvailableModel(record)
            if matchesModelFilter(record, selectedModelKey: selectedModelKey) {
                accumulator.addFilteredRecord(record)
            }
        }

        let totals = accumulator.totals
        let buckets = trendBuckets(
            from: dedupedRecords.values,
            selectedModelKey: selectedModelKey,
            range: filter.range,
            firstEventAt: accumulator.firstEventAt,
            lastEventAt: accumulator.lastEventAt,
            calendar: calendar,
            now: now
        )

        return UsageAnalyticsSnapshot(
            generatedAt: now,
            filter: filter,
            totals: totals,
            trendBuckets: buckets,
            providerCategoryStats: categoryStats(from: accumulator.categoryTotals, totalTokens: totals.totalTokens),
            providerStats: concreteProviderStats(from: accumulator.providerTotals, totalTokens: totals.totalTokens),
            modelStats: concreteModelStats(from: accumulator.modelGroups, totalTokens: totals.totalTokens),
            availableModels: modelOptions(from: accumulator.availableModelsByModel),
            diagnostics: diagnostics
        )
    }

    public static func providerCategory(for record: UsageAnalyticsRecord) -> String {
        if record.source == .ccswitchProxy {
            return "中转代理"
        }
        if let officialName = officialCategoryName(for: record.appType)
            ?? officialCategoryName(for: record.providerName)
            ?? officialCategoryName(for: record.providerID) {
            return officialName
        }
        if record.source == .ohMyUsageLocal {
            let trimmed = record.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "本地官方" : trimmed
        }
        return "中转代理"
    }

    public static func officialCategoryName(for raw: String) -> String? {
        let appType = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !appType.isEmpty else { return nil }
        if appType.contains("claude") { return "Claude" }
        if appType.contains("codex") || appType.contains("openai") || appType.contains("gpt") {
            return "GPT 官方"
        }
        if appType.contains("kimi") || appType.contains("moonshot") { return "Kimi" }
        if appType.contains("gemini") { return "Gemini" }
        if appType.contains("grok") || appType.contains("xai") { return "Grok" }
        if appType.contains("cursor") { return "Cursor" }
        if appType.contains("copilot") { return "Copilot" }
        if appType.contains("windsurf") || appType.contains("cascade") { return "Windsurf" }
        return nil
    }

    public static func rangeInterval(
        _ range: UsageAnalyticsRange,
        calendar: Calendar,
        now: Date
    ) -> DateInterval {
        switch range {
        case .last24Hours:
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let start = calendar.date(byAdding: .hour, value: -23, to: currentHour) ?? currentHour
            let end = calendar.date(byAdding: .hour, value: 1, to: currentHour) ?? now
            return DateInterval(start: start, end: end)
        case .last7Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return DateInterval(start: start, end: end)
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return DateInterval(start: start, end: end)
        case .all:
            return DateInterval(start: .distantPast, end: .distantFuture)
        }
    }

    private static func deduplicated(
        _ records: [UsageAnalyticsRecord],
        in interval: DateInterval
    ) -> [String: UsageAnalyticsRecord] {
        var selectedByIdentity: [String: UsageAnalyticsRecord] = [:]
        var unmatched: [UsageAnalyticsRecord] = []

        for record in records {
            guard record.eventAt >= interval.start && record.eventAt < interval.end else {
                continue
            }
            if let identity = record.stableIdentity {
                if let existing = selectedByIdentity[identity] {
                    if record.source.priority > existing.source.priority {
                        selectedByIdentity[identity] = record
                    }
                } else {
                    selectedByIdentity[identity] = record
                }
            } else {
                unmatched.append(record)
            }
        }

        var selected = Array(selectedByIdentity.values)
        selected.append(contentsOf: unmatched)

        var collapsed: [UsageAnalyticsRecord] = []
        for record in selected {
            if let index = collapsed.firstIndex(where: { fuzzyDuplicate($0, record) }) {
                if record.source.priority > collapsed[index].source.priority {
                    collapsed[index] = record
                }
            } else {
                collapsed.append(record)
            }
        }

        var keyed: [String: UsageAnalyticsRecord] = [:]
        for record in collapsed {
            keyed[record.dedupKey + "|" + record.requestID] = record
        }
        return keyed
    }

    private static func fuzzyDuplicate(_ lhs: UsageAnalyticsRecord, _ rhs: UsageAnalyticsRecord) -> Bool {
        guard lhs.source != rhs.source else { return false }
        guard lhs.normalizedAppType == rhs.normalizedAppType else { return false }
        guard lhs.normalizedModelID == rhs.normalizedModelID else { return false }
        guard lhs.totals.inputTokens == rhs.totals.inputTokens,
              lhs.totals.outputTokens == rhs.totals.outputTokens,
              lhs.totals.cacheReadTokens == rhs.totals.cacheReadTokens,
              lhs.totals.cacheWriteTokens == rhs.totals.cacheWriteTokens else {
            return false
        }
        return abs(lhs.eventAt.timeIntervalSince(rhs.eventAt)) < 120
    }

    private static func selectedModelKey(for filter: UsageAnalyticsFilter) -> String? {
        guard filter.mode == .byModel, let selectedModelID = filter.selectedModelID else {
            return nil
        }
        return modelKey(selectedModelID)
    }

    private static func matchesModelFilter(
        _ record: UsageAnalyticsRecord,
        selectedModelKey: String?
    ) -> Bool {
        guard let selectedModelKey else { return true }
        return modelKey(record.modelID) == selectedModelKey
    }

    private static func modelOptions(
        from totalsByModel: [String: ModelOptionAccumulator]
    ) -> [UsageAnalyticsModelOption] {
        totalsByModel.map { key, item in
            UsageAnalyticsModelOption(id: key, title: item.title, totalTokens: item.totalTokens)
        }
        .sorted { lhs, rhs in
            if lhs.totalTokens == rhs.totalTokens {
                return lhs.title < rhs.title
            }
            return lhs.totalTokens > rhs.totalTokens
        }
    }

    private static func categoryStats(
        from totalsByCategory: [String: UsageMetricTotals],
        totalTokens: Int
    ) -> [UsageProviderCategoryStats] {
        totalsByCategory.map { key, totals in
            UsageProviderCategoryStats(
                name: key,
                totals: totals,
                share: share(tokens: totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: statsSort)
    }

    private static func concreteProviderStats(
        from totalsByProvider: [ProviderKey: UsageMetricTotals],
        totalTokens: Int
    ) -> [UsageProviderStats] {
        totalsByProvider.map { key, totals in
            UsageProviderStats(
                id: "\(key.categoryName)|\(key.providerID)|\(key.providerName)",
                providerID: key.providerID,
                providerName: key.providerName,
                categoryName: key.categoryName,
                totals: totals,
                share: share(tokens: totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: providerSort)
    }

    private static func concreteModelStats(
        from groupsByModel: [String: ModelGroup],
        totalTokens: Int
    ) -> [UsageModelStats] {
        groupsByModel.map { _, group in
            UsageModelStats(
                modelID: group.modelID,
                appType: summaryValue(group.appTypes, multipleLabel: "mixed"),
                providerName: summaryValue(group.providerNames, multipleLabel: "多个来源"),
                totals: group.totals,
                share: share(tokens: group.totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: modelSort)
    }

    private static func trendBuckets(
        from records: Dictionary<String, UsageAnalyticsRecord>.Values,
        selectedModelKey: String?,
        range: UsageAnalyticsRange,
        firstEventAt: Date?,
        lastEventAt: Date?,
        calendar: Calendar,
        now: Date
    ) -> [UsageTrendBucket] {
        let plan: TrendBucketPlan
        switch range {
        case .last24Hours:
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            plan = TrendBucketPlan(
                starts: (0..<24).compactMap { calendar.date(byAdding: .hour, value: -(23 - $0), to: currentHour) },
                granularity: .hour
            )
        case .last7Days:
            let today = calendar.startOfDay(for: now)
            plan = TrendBucketPlan(
                starts: (0..<7).compactMap { calendar.date(byAdding: .day, value: -(6 - $0), to: today) },
                granularity: .day
            )
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            plan = TrendBucketPlan(
                starts: (0..<30).compactMap { calendar.date(byAdding: .day, value: -(29 - $0), to: today) },
                granularity: .day
            )
        case .all:
            plan = allRangeTrendPlan(
                firstEventAt: firstEventAt,
                lastEventAt: lastEventAt,
                calendar: calendar
            )
        }

        var bucketsByStart: [Date: TrendBucketAccumulator] = [:]
        for record in records {
            guard matchesModelFilter(record, selectedModelKey: selectedModelKey) else {
                continue
            }
            let bucketStart = trendBucketStart(
                for: record.eventAt,
                plan: plan,
                calendar: calendar
            )
            if let bucketStart {
                bucketsByStart[bucketStart, default: TrendBucketAccumulator()].add(record)
            }
        }

        return plan.starts.map { start in
            let end = trendBucketEnd(
                for: start,
                granularity: plan.granularity,
                calendar: calendar
            )
            let accumulator = bucketsByStart[start] ?? TrendBucketAccumulator()
            let totals = accumulator.totals
            return UsageTrendBucket(
                id: "\(plan.granularity.rawValue)-\(Int(start.timeIntervalSince1970))",
                startAt: start,
                endAt: end,
                totals: totals,
                topProviders: breakdown(from: accumulator.providerTotals, totalTokens: totals.totalTokens),
                topModels: breakdown(from: accumulator.modelTotals, totalTokens: totals.totalTokens)
            )
        }
    }

    private static func allRangeTrendPlan(
        firstEventAt: Date?,
        lastEventAt: Date?,
        calendar: Calendar
    ) -> TrendBucketPlan {
        guard let firstEventAt, let lastEventAt else {
            return TrendBucketPlan(starts: [], granularity: .day)
        }

        let firstDay = calendar.startOfDay(for: firstEventAt)
        let lastDay = calendar.startOfDay(for: lastEventAt)
        let dayCount = max(0, calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1

        if dayCount <= 180 {
            var starts: [Date] = []
            var cursor = firstDay
            while cursor <= lastDay {
                starts.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: 7, to: cursor),
                      next > cursor else {
                    break
                }
                cursor = next
            }
            return TrendBucketPlan(starts: starts, granularity: .sevenDay)
        }

        let firstMonth = calendar.dateInterval(of: .month, for: firstEventAt)?.start ?? firstDay
        let lastMonth = calendar.dateInterval(of: .month, for: lastEventAt)?.start ?? lastDay
        let monthCount = max(0, calendar.dateComponents([.month], from: firstMonth, to: lastMonth).month ?? 0) + 1
        if monthCount <= 24 {
            return TrendBucketPlan(
                starts: continuousStarts(from: firstMonth, through: lastMonth, component: .month, step: 1, calendar: calendar),
                granularity: .month
            )
        }

        let firstQuarter = quarterStart(for: firstEventAt, calendar: calendar) ?? firstMonth
        let lastQuarter = quarterStart(for: lastEventAt, calendar: calendar) ?? lastMonth
        return TrendBucketPlan(
            starts: continuousStarts(from: firstQuarter, through: lastQuarter, component: .month, step: 3, calendar: calendar),
            granularity: .quarter
        )
    }

    private static func continuousStarts(
        from start: Date,
        through end: Date,
        component: Calendar.Component,
        step: Int,
        calendar: Calendar
    ) -> [Date] {
        var starts: [Date] = []
        var cursor = start
        while cursor <= end {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: component, value: step, to: cursor),
                  next > cursor else {
                break
            }
            cursor = next
        }
        return starts
    }

    private static func trendBucketStart(
        for date: Date,
        plan: TrendBucketPlan,
        calendar: Calendar
    ) -> Date? {
        switch plan.granularity {
        case .hour:
            return calendar.dateInterval(of: .hour, for: date)?.start
        case .day:
            return calendar.startOfDay(for: date)
        case .sevenDay:
            guard let firstStart = plan.starts.first else { return nil }
            let recordDay = calendar.startOfDay(for: date)
            let dayOffset = calendar.dateComponents([.day], from: firstStart, to: recordDay).day ?? 0
            guard dayOffset >= 0 else { return nil }
            return calendar.date(byAdding: .day, value: (dayOffset / 7) * 7, to: firstStart)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start
        case .quarter:
            return quarterStart(for: date, calendar: calendar)
        }
    }

    private static func trendBucketEnd(
        for start: Date,
        granularity: TrendBucketGranularity,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .hour:
            return calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .sevenDay:
            return calendar.date(byAdding: .day, value: 7, to: start) ?? start
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: start) ?? start
        case .quarter:
            return calendar.date(byAdding: .month, value: 3, to: start) ?? start
        }
    }

    private static func quarterStart(
        for date: Date,
        calendar: Calendar
    ) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year,
              let month = components.month else {
            return nil
        }
        let firstMonth = ((month - 1) / 3) * 3 + 1
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: firstMonth,
            day: 1
        ))
    }

    private static func breakdown(
        from totalsByName: [String: UsageMetricTotals],
        totalTokens: Int
    ) -> [UsageAnalyticsBreakdownItem] {
        totalsByName.map { name, totals in
            UsageAnalyticsBreakdownItem(
                name: name,
                totals: totals,
                share: share(tokens: totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: breakdownSort)
        .prefix(5)
        .map { $0 }
    }

    private static func share(tokens: Int, totalTokens: Int) -> Double {
        guard totalTokens > 0 else { return 0 }
        return Double(tokens) / Double(totalTokens)
    }

    private static func modelKey(_ value: String) -> String {
        displayValue(value).lowercased()
    }

    private static func displayValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func summaryValue(_ values: Set<String>, multipleLabel: String) -> String {
        let cleaned = values.map(displayValue).filter { $0 != "unknown" }.sorted()
        if cleaned.count == 1 {
            return cleaned[0]
        }
        if cleaned.isEmpty {
            return "unknown"
        }
        return multipleLabel
    }

    private static func statsSort(lhs: UsageProviderCategoryStats, rhs: UsageProviderCategoryStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.name < rhs.name
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func providerSort(lhs: UsageProviderStats, rhs: UsageProviderStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.providerName < rhs.providerName
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func modelSort(lhs: UsageModelStats, rhs: UsageModelStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.modelID < rhs.modelID
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func breakdownSort(lhs: UsageAnalyticsBreakdownItem, rhs: UsageAnalyticsBreakdownItem) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.name < rhs.name
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }
}
