import Foundation

enum LocalUsageTrendScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case currentAccount
    case allAccounts

    var id: String { rawValue }
}

enum LocalUsageTrendDiagnosticsSource: String, Codable, Sendable {
    case strict
    case sessions
    case approximate
}

struct LocalUsageTrendDiagnostics: Codable, Equatable, Sendable {
    var matchedRows: Int
    var parsedEvents: Int
    var attributableEvents: Int
    var recoveredByConversationResponses: Int
    var recoveredByConversationTokens: Int
    var unattributedResponses: Int
    var unattributedTokens: Int
    var latestEventAt: Date?
    var source: LocalUsageTrendDiagnosticsSource
}

struct LocalUsageTrendPoint: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var startAt: Date
    var totalTokens: Int
    var responses: Int
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
}

struct LocalUsageModelBreakdown: Codable, Equatable, Identifiable, Sendable {
    var id: String { modelID }
    var modelID: String
    var totalTokens: Int
    var responses: Int
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
}

struct LocalUsagePeriodSummary: Codable, Equatable, Sendable {
    var totalTokens: Int
    var responses: Int
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var byModel: [LocalUsageModelBreakdown]

    static let empty = LocalUsagePeriodSummary(totalTokens: 0, responses: 0, byModel: [])
}

struct LocalUsageSummary: Codable, Equatable, Sendable {
    var today: LocalUsagePeriodSummary
    var yesterday: LocalUsagePeriodSummary
    var last30Days: LocalUsagePeriodSummary
    var hourly24: [LocalUsageTrendPoint]
    var daily7: [LocalUsageTrendPoint]
    var sourcePath: String
    var generatedAt: Date
    var diagnostics: LocalUsageTrendDiagnostics?
    var isApproximateFallback: Bool

    func markedApproximateFallback(using diagnostics: LocalUsageTrendDiagnostics?) -> LocalUsageSummary {
        LocalUsageSummary(
            today: today,
            yesterday: yesterday,
            last30Days: last30Days,
            hourly24: hourly24,
            daily7: daily7,
            sourcePath: sourcePath,
            generatedAt: generatedAt,
            diagnostics: diagnostics ?? self.diagnostics,
            isApproximateFallback: true
        )
    }
}

struct LocalUsageEvent: Equatable, Sendable {
    var signature: String
    var eventAt: Date
    var modelID: String
    var totalTokens: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int

    init(
        signature: String,
        eventAt: Date,
        modelID: String,
        totalTokens: Int? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0
    ) {
        self.signature = signature
        self.eventAt = eventAt
        self.modelID = modelID
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cacheReadTokens = max(0, cacheReadTokens)
        self.cacheWriteTokens = max(0, cacheWriteTokens)
        self.totalTokens = max(
            0,
            totalTokens ?? (self.inputTokens + self.outputTokens + self.cacheReadTokens + self.cacheWriteTokens)
        )
    }
}

enum LocalUsageJSONParsing {
    static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value.rounded()) }
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let integer = Int(trimmed) { return integer }
            if let double = Double(trimmed) { return Int(double.rounded()) }
        }
        return nil
    }

    static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    static func firstInt(in container: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = intValue(container[key]) {
                return value
            }
        }
        return nil
    }

    static func parseISODate(_ raw: String?) -> Date? {
        guard let raw = stringValue(raw) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }

    static func parseTimestamp(_ raw: Any?) -> Date? {
        if let date = parseISODate(stringValue(raw)) {
            return date
        }
        let epochValue: Double?
        if let value = raw as? Double {
            epochValue = value
        } else if let value = raw as? Int {
            epochValue = Double(value)
        } else if let value = raw as? NSNumber {
            epochValue = value.doubleValue
        } else if let value = stringValue(raw), let parsed = Double(value) {
            epochValue = parsed
        } else {
            epochValue = nil
        }
        guard let epoch = epochValue, epoch > 0 else { return nil }
        if epoch > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: epoch / 1_000)
        }
        return Date(timeIntervalSince1970: epoch)
    }
}

struct LocalUsageTokenComponents: Equatable, Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    func delta(from previous: LocalUsageTokenComponents, fallbackTotal: Int) -> LocalUsageTokenComponents {
        let input = max(0, inputTokens - previous.inputTokens)
        let output = max(0, outputTokens - previous.outputTokens)
        let cacheRead = max(0, cacheReadTokens - previous.cacheReadTokens)
        let cacheWrite = max(0, cacheWriteTokens - previous.cacheWriteTokens)
        let componentTotal = input + output + cacheRead + cacheWrite
        if componentTotal == 0, fallbackTotal > 0 {
            return LocalUsageTokenComponents(outputTokens: fallbackTotal)
        }
        return LocalUsageTokenComponents(
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite
        )
    }
}

enum LocalUsageSummaryBuilder {
    static func build(
        events: [LocalUsageEvent],
        calendar: Calendar,
        now: Date,
        sourcePath: String
    ) -> LocalUsageSummary {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOf7Days = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let startOfLast30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfYesterday
        let startOfCurrentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let startOf24Hours = calendar.date(byAdding: .hour, value: -23, to: startOfCurrentHour) ?? startOfCurrentHour

        var todayAccumulator = PeriodAccumulator()
        var yesterdayAccumulator = PeriodAccumulator()
        var last30Accumulator = PeriodAccumulator()
        var hourly24Buckets: [Date: PeriodAccumulator] = [:]
        var daily7Buckets: [Date: PeriodAccumulator] = [:]

        for event in events {
            guard event.eventAt >= startOfLast30Days else {
                continue
            }

            last30Accumulator.consume(event: event)
            if event.eventAt >= startOfToday {
                todayAccumulator.consume(event: event)
            } else if event.eventAt >= startOfYesterday {
                yesterdayAccumulator.consume(event: event)
            }

            if event.eventAt >= startOf24Hours,
               let hourStart = calendar.dateInterval(of: .hour, for: event.eventAt)?.start {
                var accumulator = hourly24Buckets[hourStart, default: PeriodAccumulator()]
                accumulator.consume(event: event)
                hourly24Buckets[hourStart] = accumulator
            }

            if event.eventAt >= startOf7Days {
                let dayStart = calendar.startOfDay(for: event.eventAt)
                var accumulator = daily7Buckets[dayStart, default: PeriodAccumulator()]
                accumulator.consume(event: event)
                daily7Buckets[dayStart] = accumulator
            }
        }

        return LocalUsageSummary(
            today: todayAccumulator.summary,
            yesterday: yesterdayAccumulator.summary,
            last30Days: last30Accumulator.summary,
            hourly24: buildHourlyTrendPoints(
                buckets: hourly24Buckets,
                calendar: calendar,
                startOfCurrentHour: startOfCurrentHour
            ),
            daily7: buildDailyTrendPoints(
                buckets: daily7Buckets,
                calendar: calendar,
                startOfToday: startOfToday
            ),
            sourcePath: sourcePath,
            generatedAt: now,
            diagnostics: nil,
            isApproximateFallback: false
        )
    }

    private static func buildHourlyTrendPoints(
        buckets: [Date: PeriodAccumulator],
        calendar: Calendar,
        startOfCurrentHour: Date
    ) -> [LocalUsageTrendPoint] {
        (0..<24).compactMap { offset -> LocalUsageTrendPoint? in
            guard let hourStart = calendar.date(byAdding: .hour, value: -(23 - offset), to: startOfCurrentHour) else {
                return nil
            }
            let accumulator = buckets[hourStart] ?? PeriodAccumulator()
            return LocalUsageTrendPoint(
                id: "h-\(Int(hourStart.timeIntervalSince1970))",
                startAt: hourStart,
                totalTokens: accumulator.totalTokens,
                responses: accumulator.responses,
                inputTokens: accumulator.inputTokens,
                outputTokens: accumulator.outputTokens,
                cacheReadTokens: accumulator.cacheReadTokens,
                cacheWriteTokens: accumulator.cacheWriteTokens
            )
        }
    }

    private static func buildDailyTrendPoints(
        buckets: [Date: PeriodAccumulator],
        calendar: Calendar,
        startOfToday: Date
    ) -> [LocalUsageTrendPoint] {
        (0..<7).compactMap { offset -> LocalUsageTrendPoint? in
            guard let dayStart = calendar.date(byAdding: .day, value: -(6 - offset), to: startOfToday) else {
                return nil
            }
            let accumulator = buckets[dayStart] ?? PeriodAccumulator()
            return LocalUsageTrendPoint(
                id: "d-\(Int(dayStart.timeIntervalSince1970))",
                startAt: dayStart,
                totalTokens: accumulator.totalTokens,
                responses: accumulator.responses,
                inputTokens: accumulator.inputTokens,
                outputTokens: accumulator.outputTokens,
                cacheReadTokens: accumulator.cacheReadTokens,
                cacheWriteTokens: accumulator.cacheWriteTokens
            )
        }
    }
}

extension LocalUsageSummary {
    init(codex summary: CodexLocalUsageSummary) {
        self.today = LocalUsagePeriodSummary(codex: summary.today)
        self.yesterday = LocalUsagePeriodSummary(codex: summary.yesterday)
        self.last30Days = LocalUsagePeriodSummary(codex: summary.last30Days)
        self.hourly24 = summary.hourly24.map(LocalUsageTrendPoint.init(codex:))
        self.daily7 = summary.daily7.map(LocalUsageTrendPoint.init(codex:))
        self.sourcePath = summary.databasePath
        self.generatedAt = summary.generatedAt
        self.diagnostics = summary.diagnostics.map(LocalUsageTrendDiagnostics.init(codex:))
        self.isApproximateFallback = false
    }
}

private extension LocalUsageTrendPoint {
    init(codex point: CodexLocalUsageTrendPoint) {
        self.init(
            id: point.id,
            startAt: point.startAt,
            totalTokens: point.totalTokens,
            responses: point.responses,
            inputTokens: point.inputTokens,
            outputTokens: point.outputTokens,
            cacheReadTokens: point.cacheReadTokens,
            cacheWriteTokens: point.cacheWriteTokens
        )
    }
}

private extension LocalUsagePeriodSummary {
    init(codex summary: CodexLocalUsagePeriodSummary) {
        self.init(
            totalTokens: summary.totalTokens,
            responses: summary.responses,
            inputTokens: summary.inputTokens,
            outputTokens: summary.outputTokens,
            cacheReadTokens: summary.cacheReadTokens,
            cacheWriteTokens: summary.cacheWriteTokens,
            byModel: summary.byModel.map(LocalUsageModelBreakdown.init(codex:))
        )
    }
}

private extension LocalUsageModelBreakdown {
    init(codex value: CodexLocalUsageModelBreakdown) {
        self.init(
            modelID: value.modelID,
            totalTokens: value.totalTokens,
            responses: value.responses,
            inputTokens: value.inputTokens,
            outputTokens: value.outputTokens,
            cacheReadTokens: value.cacheReadTokens,
            cacheWriteTokens: value.cacheWriteTokens
        )
    }
}

private extension LocalUsageTrendDiagnostics {
    init(codex value: CodexLocalUsageDiagnostics) {
        self.init(
            matchedRows: value.matchedRows,
            parsedEvents: value.parsedEvents,
            attributableEvents: value.attributableEvents,
            recoveredByConversationResponses: value.recoveredByConversationResponses,
            recoveredByConversationTokens: value.recoveredByConversationTokens,
            unattributedResponses: value.unattributedResponses,
            unattributedTokens: value.unattributedTokens,
            latestEventAt: value.latestEventAt,
            source: LocalUsageTrendDiagnosticsSource(codex: value.source)
        )
    }
}

private extension LocalUsageTrendDiagnosticsSource {
    init(codex source: CodexLocalUsageDiagnosticsSource) {
        switch source {
        case .strict:
            self = .strict
        case .sessions:
            self = .sessions
        case .approximate:
            self = .approximate
        }
    }
}

private struct PeriodAccumulator {
    var totalTokens = 0
    var responses = 0
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0
    var byModel: [String: ModelAccumulator] = [:]

    mutating func consume(event: LocalUsageEvent) {
        totalTokens += event.totalTokens
        responses += 1
        inputTokens += event.inputTokens
        outputTokens += event.outputTokens
        cacheReadTokens += event.cacheReadTokens
        cacheWriteTokens += event.cacheWriteTokens
        var model = byModel[event.modelID, default: ModelAccumulator()]
        model.consume(event: event)
        byModel[event.modelID] = model
    }

    var summary: LocalUsagePeriodSummary {
        let models = byModel.map { key, value in
            LocalUsageModelBreakdown(
                modelID: key,
                totalTokens: value.totalTokens,
                responses: value.responses,
                inputTokens: value.inputTokens,
                outputTokens: value.outputTokens,
                cacheReadTokens: value.cacheReadTokens,
                cacheWriteTokens: value.cacheWriteTokens
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalTokens == rhs.totalTokens {
                if lhs.responses == rhs.responses {
                    return lhs.modelID < rhs.modelID
                }
                return lhs.responses > rhs.responses
            }
            return lhs.totalTokens > rhs.totalTokens
        }

        return LocalUsagePeriodSummary(
            totalTokens: totalTokens,
            responses: responses,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            byModel: models
        )
    }
}

private struct ModelAccumulator {
    var totalTokens = 0
    var responses = 0
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0

    mutating func consume(event: LocalUsageEvent) {
        totalTokens += event.totalTokens
        responses += 1
        inputTokens += event.inputTokens
        outputTokens += event.outputTokens
        cacheReadTokens += event.cacheReadTokens
        cacheWriteTokens += event.cacheWriteTokens
    }
}
