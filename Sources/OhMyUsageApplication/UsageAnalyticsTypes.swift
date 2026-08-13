import Foundation

public struct UsageMetricTotals: Codable, Equatable, Sendable {
    public var requestCount: Int
    public var successCount: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int

    public init(
        requestCount: Int = 0,
        successCount: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0
    ) {
        self.requestCount = requestCount
        self.successCount = successCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    public var successRate: Double {
        guard requestCount > 0 else { return 0 }
        return Double(successCount) / Double(requestCount)
    }

    public var cacheRate: Double {
        let denominator = inputTokens + cacheReadTokens + cacheWriteTokens
        guard denominator > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(denominator)
    }

    public mutating func add(_ other: UsageMetricTotals) {
        requestCount += other.requestCount
        successCount += other.successCount
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheWriteTokens += other.cacheWriteTokens
    }
}

public enum UsageAnalyticsFilterMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case byModel

    public var id: String { rawValue }
}

public enum UsageAnalyticsRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case last24Hours
    case last7Days
    case last30Days
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .last24Hours: return "最近24小时"
        case .last7Days: return "7天"
        case .last30Days: return "30天"
        case .all: return "全部"
        }
    }
}

public struct UsageAnalyticsFilter: Codable, Equatable, Hashable, Sendable {
    public var mode: UsageAnalyticsFilterMode
    public var selectedModelID: String?
    public var range: UsageAnalyticsRange

    public init(
        mode: UsageAnalyticsFilterMode = .all,
        selectedModelID: String? = nil,
        range: UsageAnalyticsRange = .last30Days
    ) {
        self.mode = mode
        self.selectedModelID = selectedModelID
        self.range = range
    }
}

public enum UsageAnalyticsRecordSource: Int, Codable, Equatable, Sendable {
    case ccswitchDailyRollup = 0
    case ohMyUsageLocal = 1
    case ccswitchSession = 2
    case ccswitchProxy = 3

    public var priority: Int { rawValue }
}

public struct UsageAnalyticsRecord: Equatable, Sendable {
    public var source: UsageAnalyticsRecordSource
    public var eventAt: Date
    public var appType: String
    public var providerID: String
    public var providerName: String
    public var modelID: String
    public var requestID: String
    public var totals: UsageMetricTotals

    public init(
        source: UsageAnalyticsRecordSource,
        eventAt: Date,
        appType: String,
        providerID: String,
        providerName: String,
        modelID: String,
        requestID: String,
        totals: UsageMetricTotals
    ) {
        self.source = source
        self.eventAt = eventAt
        self.appType = appType
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
        self.requestID = requestID
        self.totals = totals
    }

    public var dedupKey: String {
        if let stableIdentity {
            return "id|\(stableIdentity)"
        }
        let minute = Int(eventAt.timeIntervalSince1970 / 60)
        return [
            normalizedAppType,
            normalizedModelID,
            "\(totals.inputTokens)",
            "\(totals.outputTokens)",
            "\(totals.cacheReadTokens)",
            "\(totals.cacheWriteTokens)",
            "\(minute)"
        ].joined(separator: "|")
    }

    public var stableIdentity: String? {
        let trimmed = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("rollup|") {
            return trimmed.lowercased()
        }
        return trimmed.lowercased()
    }

    public var normalizedAppType: String {
        normalized(appType)
    }

    public var normalizedModelID: String {
        normalized(modelID)
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct UsageAnalyticsBreakdownItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var totals: UsageMetricTotals
    public var share: Double

    public init(name: String, totals: UsageMetricTotals, share: Double) {
        self.name = name
        self.totals = totals
        self.share = share
    }
}

public struct UsageTrendBucket: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var startAt: Date
    public var endAt: Date
    public var totals: UsageMetricTotals
    public var topProviders: [UsageAnalyticsBreakdownItem]
    public var topModels: [UsageAnalyticsBreakdownItem]

    public init(
        id: String,
        startAt: Date,
        endAt: Date,
        totals: UsageMetricTotals,
        topProviders: [UsageAnalyticsBreakdownItem],
        topModels: [UsageAnalyticsBreakdownItem]
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.totals = totals
        self.topProviders = topProviders
        self.topModels = topModels
    }
}

public struct UsageProviderCategoryStats: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var totals: UsageMetricTotals
    public var share: Double

    public init(name: String, totals: UsageMetricTotals, share: Double) {
        self.name = name
        self.totals = totals
        self.share = share
    }
}

public struct UsageProviderStats: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var providerID: String
    public var providerName: String
    public var categoryName: String
    public var totals: UsageMetricTotals
    public var share: Double

    public init(
        id: String,
        providerID: String,
        providerName: String,
        categoryName: String,
        totals: UsageMetricTotals,
        share: Double
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.categoryName = categoryName
        self.totals = totals
        self.share = share
    }
}

public struct UsageModelStats: Identifiable, Codable, Equatable, Sendable {
    public var id: String { modelID }
    public var modelID: String
    public var appType: String
    public var providerName: String
    public var totals: UsageMetricTotals
    public var share: Double

    public init(
        modelID: String,
        appType: String,
        providerName: String,
        totals: UsageMetricTotals,
        share: Double
    ) {
        self.modelID = modelID
        self.appType = appType
        self.providerName = providerName
        self.totals = totals
        self.share = share
    }
}

public struct UsageAnalyticsModelOption: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var totalTokens: Int

    public init(id: String, title: String, totalTokens: Int) {
        self.id = id
        self.title = title
        self.totalTokens = totalTokens
    }
}

public struct UsageAnalyticsSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var filter: UsageAnalyticsFilter
    public var totals: UsageMetricTotals
    public var trendBuckets: [UsageTrendBucket]
    public var providerCategoryStats: [UsageProviderCategoryStats]
    public var providerStats: [UsageProviderStats]
    public var modelStats: [UsageModelStats]
    public var availableModels: [UsageAnalyticsModelOption]
    public var diagnostics: [String]

    public init(
        generatedAt: Date,
        filter: UsageAnalyticsFilter,
        totals: UsageMetricTotals,
        trendBuckets: [UsageTrendBucket],
        providerCategoryStats: [UsageProviderCategoryStats],
        providerStats: [UsageProviderStats],
        modelStats: [UsageModelStats],
        availableModels: [UsageAnalyticsModelOption],
        diagnostics: [String]
    ) {
        self.generatedAt = generatedAt
        self.filter = filter
        self.totals = totals
        self.trendBuckets = trendBuckets
        self.providerCategoryStats = providerCategoryStats
        self.providerStats = providerStats
        self.modelStats = modelStats
        self.availableModels = availableModels
        self.diagnostics = diagnostics
    }

    public static func empty(filter: UsageAnalyticsFilter, generatedAt: Date = Date()) -> UsageAnalyticsSnapshot {
        UsageAnalyticsSnapshot(
            generatedAt: generatedAt,
            filter: filter,
            totals: UsageMetricTotals(),
            trendBuckets: [],
            providerCategoryStats: [],
            providerStats: [],
            modelStats: [],
            availableModels: [],
            diagnostics: []
        )
    }
}
