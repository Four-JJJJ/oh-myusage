import Foundation

final class UsageAnalyticsRepository: @unchecked Sendable {
    typealias CCSwitchSourceFingerprintProvider = (_ ccSwitchReader: CCSwitchUsageLogReader) -> UsageAnalyticsFileFingerprint
    typealias LocalSourceFingerprintProvider = (
        _ claudeAllConfigDirs: [String]
    ) -> CachedLocalSourceFingerprint

    struct CachedLocalSourceFingerprint: Equatable, Sendable {
        var codex: UsageAnalyticsFileFingerprint
        var claude: UsageAnalyticsFileFingerprint
        var kimi: UsageAnalyticsFileFingerprint
        var cursor: UsageAnalyticsFileFingerprint = .empty
        var grok: UsageAnalyticsFileFingerprint = .empty
        var gemini: UsageAnalyticsFileFingerprint = .empty
    }

    private final class LocalSourceFingerprintCache: @unchecked Sendable {
        private struct Entry {
            var fingerprint: CachedLocalSourceFingerprint
            var checkedAt: Date
        }

        private let ttl: TimeInterval
        private let lock = NSLock()
        private var entries: [String: Entry] = [:]

        init(ttl: TimeInterval) {
            self.ttl = ttl
        }

        func fingerprint(for key: String, now: Date) -> CachedLocalSourceFingerprint? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[key] else { return nil }
            guard now.timeIntervalSince(entry.checkedAt) < ttl else {
                entries.removeValue(forKey: key)
                return nil
            }
            return entry.fingerprint
        }

        func store(_ fingerprint: CachedLocalSourceFingerprint, for key: String, now: Date) {
            lock.lock()
            entries[key] = Entry(fingerprint: fingerprint, checkedAt: now)
            if entries.count > 32, let oldest = entries.min(by: { $0.value.checkedAt < $1.value.checkedAt })?.key {
                entries.removeValue(forKey: oldest)
            }
            lock.unlock()
        }

        func removeAll() {
            lock.lock()
            entries.removeAll()
            lock.unlock()
        }
    }

    private static let localSourceFingerprintCache = LocalSourceFingerprintCache(ttl: 60)

    private struct RawEntry {
        var epoch: UInt64
        var range: UsageAnalyticsRange
        var configDirs: [String]
        var fingerprint: UsageAnalyticsSourceFingerprint
        var loadedAt: Date
        var records: [UsageAnalyticsRecord]
        var diagnostics: [String]
    }
    private let rawLock = NSLock()
    private let rawEpochLock = NSLock()
    private var rawEpoch: UInt64 = 0
    private func currentRawEpoch() -> UInt64 { rawEpochLock.withLock { rawEpoch } }
    private var rawEntry: RawEntry?

    private let cursorService: CursorLocalUsageService
    private let ccSwitchReader: CCSwitchUsageLogReader
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let ccSwitchSourceFingerprintProvider: CCSwitchSourceFingerprintProvider
    private let localSourceFingerprintProvider: LocalSourceFingerprintProvider

    init(
        ccSwitchReader: CCSwitchUsageLogReader = CCSwitchUsageLogReader(),
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        ccSwitchSourceFingerprintProvider: @escaping CCSwitchSourceFingerprintProvider = UsageAnalyticsRepository.defaultCCSwitchSourceFingerprint,
        localSourceFingerprintProvider: @escaping LocalSourceFingerprintProvider = UsageAnalyticsRepository.defaultLocalSourceFingerprint
    ) {
        self.cursorService = CursorLocalUsageService(calendar: calendar, nowProvider: nowProvider)
        self.ccSwitchReader = ccSwitchReader
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.ccSwitchSourceFingerprintProvider = ccSwitchSourceFingerprintProvider
        self.localSourceFingerprintProvider = localSourceFingerprintProvider
    }

    func invalidateRawCache() {
        // This independent short lock invalidates reads immediately without waiting for scanners.
        rawEpochLock.withLock { rawEpoch &+= 1 }
    }

    func snapshot(
        filter: UsageAnalyticsFilter,
        claudeAllConfigDirs: [String] = [],
        bypassCache: Bool = false,
        cursorOverride: CursorLocalUsageService.EventResult? = nil
    ) -> UsageAnalyticsSnapshot {
        let now = nowProvider()
        let epoch = currentRawEpoch()
        while !rawLock.try() {
            if Task.isCancelled { return .empty(filter: filter, generatedAt: now) }
            Thread.sleep(forTimeInterval: 0.01)
        }
        defer { rawLock.unlock() }
        if Task.isCancelled { return .empty(filter: filter, generatedAt: now) }
        let fingerprint = sourceFingerprint(claudeAllConfigDirs: claudeAllConfigDirs, bypassCache: bypassCache)
        let dirs = claudeAllConfigDirs.sorted()
        if !bypassCache, let cached = rawEntry, cached.epoch == epoch, epoch == currentRawEpoch(), cached.range == filter.range,
           cached.configDirs == dirs, cached.fingerprint == fingerprint,
           now.timeIntervalSince(cached.loadedAt) >= 0,
           now.timeIntervalSince(cached.loadedAt) < 60,
           calendar.isDate(cached.loadedAt, equalTo: now, toGranularity: .hour) {
            return UsageAnalyticsAggregator.snapshot(records: cached.records, filter: filter,
                calendar: calendar, now: now, diagnostics: cached.diagnostics)
        }
        let interval = UsageAnalyticsAggregator.rangeInterval(filter.range, calendar: calendar, now: now)
        var diagnostics: [String] = []
        var records: [UsageAnalyticsRecord] = []

        let ccSwitchResult = ccSwitchReader.readUsageLogs(since: interval.start, until: interval.end)
        records.reserveCapacity(ccSwitchResult.records.count)
        for record in ccSwitchResult.records {
            records.append(record.analyticsRecord)
        }
        let ccSwitchMissing = ccSwitchResult.sourceStatus == .absent
        if ccSwitchMissing {
            diagnostics.append("未安装 cc-switch，使用官方应用本地用量与 Cursor dashboard（可用时）")
        } else {
            diagnostics.append(contentsOf: ccSwitchResult.diagnostics)
        }
        diagnostics.insert(
            ccSwitchMissing
                ? "统计来源：官方应用本地用量日志 / Cursor dashboard（可用时）"
                : "统计来源：官方应用本地用量 / Cursor dashboard（可用时）+ cc-switch 请求日志",
            at: 0
        )

        let localResult = readLocalRecords(
            since: interval.start,
            claudeAllConfigDirs: claudeAllConfigDirs, cursorOverride: cursorOverride
        )
        records.append(contentsOf: localResult.records)
        diagnostics.append(contentsOf: localResult.diagnostics)

        let isPartial = localResult.isPartial || ccSwitchResult.sourceStatus == .failed
        if !Task.isCancelled && epoch == currentRawEpoch() && records.count <= 100_000 && !isPartial {
            rawEntry = RawEntry(epoch: epoch, range: filter.range, configDirs: dirs, fingerprint: fingerprint,
                                loadedAt: now, records: records, diagnostics: diagnostics)
        } else { rawEntry = nil }
        var snapshot = UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: filter,
            calendar: calendar,
            now: now,
            diagnostics: diagnostics
        )
        snapshot.isPartial = isPartial
        return snapshot
    }

    private func reusableSnapshot(filter: UsageAnalyticsFilter, dirs: [String], now: Date) -> UsageAnalyticsSnapshot? {
        let fingerprint = sourceFingerprint(claudeAllConfigDirs: dirs)
        while !rawLock.try() {
            if Task.isCancelled { return nil }
            Thread.sleep(forTimeInterval: 0.01)
        }
        defer { rawLock.unlock() }
        guard let cached = rawEntry, cached.epoch == currentRawEpoch(), cached.fingerprint == fingerprint, cached.range == filter.range, cached.configDirs == dirs.sorted(),
              now.timeIntervalSince(cached.loadedAt) >= 0, now.timeIntervalSince(cached.loadedAt) < 60,
              calendar.isDate(cached.loadedAt, equalTo: now, toGranularity: .hour) else { return nil }
        return UsageAnalyticsAggregator.snapshot(records: cached.records, filter: filter,
            calendar: calendar, now: now, diagnostics: cached.diagnostics)
    }

    func snapshotAsync(filter: UsageAnalyticsFilter, claudeAllConfigDirs: [String], bypassCache: Bool = false) async throws -> UsageAnalyticsSnapshot {
        try Task.checkCancellation()
        let now = nowProvider()
        if !bypassCache {
            let cacheWorker = Task.detached(priority: .utility) { [self] in
                reusableSnapshot(filter: filter, dirs: claudeAllConfigDirs, now: now)
            }
            let cached = await withTaskCancellationHandler { await cacheWorker.value } onCancel: { cacheWorker.cancel() }
            try Task.checkCancellation()
            if let cached { return cached }
        }
        let interval = UsageAnalyticsAggregator.rangeInterval(filter.range, calendar: calendar, now: now)
        let cursor = try await cursorService.fetchEventResultAsync(since: interval.start, until: interval.end)
        let worker = Task.detached(priority: .utility) { [self] in
            snapshot(filter: filter, claudeAllConfigDirs: claudeAllConfigDirs, bypassCache: bypassCache, cursorOverride: cursor)
        }
        let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return result
    }

    func sourceFingerprint(claudeAllConfigDirs: [String] = [], bypassCache: Bool = false) -> UsageAnalyticsSourceFingerprint {
        let now = nowProvider()
        let ccSwitch = ccSwitchSourceFingerprintProvider(ccSwitchReader)
        let cacheKey = Self.localSourceFingerprintCacheKey(
            claudeAllConfigDirs: claudeAllConfigDirs
        )
        let localFingerprint: CachedLocalSourceFingerprint
        if !bypassCache, let cached = Self.localSourceFingerprintCache.fingerprint(for: cacheKey, now: now) {
            localFingerprint = cached
        } else {
            localFingerprint = localSourceFingerprintProvider(claudeAllConfigDirs)
            Self.localSourceFingerprintCache.store(localFingerprint, for: cacheKey, now: now)
        }
        return UsageAnalyticsSourceFingerprint(
            ccSwitch: ccSwitch,
            codex: localFingerprint.codex,
            claude: localFingerprint.claude,
            kimi: localFingerprint.kimi,
            cursor: localFingerprint.cursor,
            grok: localFingerprint.grok,
            gemini: localFingerprint.gemini
        )
    }

    static func clearSourceFingerprintCacheForTesting() {
        localSourceFingerprintCache.removeAll()
    }

    private func readLocalRecords(
        since: Date,
        claudeAllConfigDirs: [String], cursorOverride: CursorLocalUsageService.EventResult? = nil
    ) -> (records: [UsageAnalyticsRecord], diagnostics: [String], isPartial: Bool) {
        var records: [UsageAnalyticsRecord] = []
        var diagnostics: [String] = []
        var isPartial = false

        if Task.isCancelled { return (records, diagnostics, true) }
        do {
            let codexEvents = try CodexLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, since: since)
            appendAnalyticsRecords(
                codexEvents,
                to: &records,
                appType: "codex",
                providerID: "ohmyusage-codex-local",
                providerName: "Codex"
            )
        } catch {
            isPartial = true
            diagnostics.append("Codex 本地日志读取失败")
        }

        if Task.isCancelled { return (records, diagnostics, true) }
        do {
            let claudeEvents = try ClaudeLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, allConfigDirs: claudeAllConfigDirs, since: since)
            appendAnalyticsRecords(
                claudeEvents,
                to: &records,
                appType: "claude",
                providerID: "ohmyusage-claude-local",
                providerName: "Claude"
            )
        } catch {
            isPartial = true
            diagnostics.append("Claude 本地日志读取失败")
        }

        if Task.isCancelled { return (records, diagnostics, true) }
        do {
            let kimiEvents = try KimiLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, since: since)
            appendAnalyticsRecords(
                kimiEvents,
                to: &records,
                appType: "kimi",
                providerID: "ohmyusage-kimi-local",
                providerName: "Kimi"
            )
        } catch {
            isPartial = true
            diagnostics.append("Kimi 本地日志读取失败")
        }

        if Task.isCancelled { return (records, diagnostics, true) }
        do {
            let cursorResult = try cursorOverride ?? CursorLocalUsageService(
                calendar: calendar,
                nowProvider: nowProvider,
                dashboardFetcher: CursorDashboardUsageClient()
            ).fetchEventResult(since: since)
            diagnostics.append(contentsOf: cursorResult.diagnostics)
            isPartial = isPartial || cursorResult.isPartial
            appendAnalyticsRecords(
                cursorResult.events,
                to: &records,
                appType: "cursor",
                providerID: "ohmyusage-cursor-local",
                providerName: "Cursor"
            )
        } catch {
            isPartial = true
            diagnostics.append("Cursor 用量读取失败")
        }

        if Task.isCancelled { return (records, diagnostics, true) }
        do {
            let grokEvents = try GrokLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(since: since)
            appendAnalyticsRecords(
                grokEvents,
                to: &records,
                appType: "grok",
                providerID: "ohmyusage-grok-local",
                providerName: "Grok"
            )
        } catch {
            isPartial = true
            diagnostics.append("Grok 本地日志读取失败")
        }

        if Task.isCancelled { return (records, diagnostics, true) }
        do {
            let geminiEvents = try GeminiLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(since: since)
            appendAnalyticsRecords(
                geminiEvents,
                to: &records,
                appType: "gemini",
                providerID: "ohmyusage-gemini-local",
                providerName: "Gemini"
            )
        } catch {
            isPartial = true
            diagnostics.append("Gemini 本地日志读取失败")
        }

        return (records, diagnostics, isPartial)
    }

    private func appendAnalyticsRecords(
        _ events: [LocalUsageEvent],
        to records: inout [UsageAnalyticsRecord],
        appType: String,
        providerID: String,
        providerName: String
    ) {
        records.reserveCapacity(records.count + events.count)
        for event in events {
            records.append(
                analyticsRecord(
                    event: event,
                    appType: appType,
                    providerID: providerID,
                    providerName: providerName
                )
            )
        }
    }

    private func analyticsRecord(
        event: LocalUsageEvent,
        appType: String,
        providerID: String,
        providerName: String
    ) -> UsageAnalyticsRecord {
        UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: event.eventAt,
            appType: appType,
            providerID: providerID,
            providerName: providerName,
            modelID: event.modelID,
            requestID: event.signature,
            totals: usageTotals(from: event)
        )
    }

    private func usageTotals(from event: LocalUsageEvent) -> UsageMetricTotals {
        let componentTotal = event.inputTokens
            + event.outputTokens
            + event.cacheReadTokens
            + event.cacheWriteTokens
        if componentTotal > 0 {
            return UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: event.inputTokens,
                outputTokens: event.outputTokens,
                cacheReadTokens: event.cacheReadTokens,
                cacheWriteTokens: event.cacheWriteTokens
            )
        }
        return UsageMetricTotals(
            requestCount: 1,
            successCount: 1,
            outputTokens: event.totalTokens
        )
    }

    private static func defaultCCSwitchSourceFingerprint(
        ccSwitchReader: CCSwitchUsageLogReader
    ) -> UsageAnalyticsFileFingerprint {
        usageAnalyticsFileFingerprint(from: ccSwitchReader.sourceFingerprint())
    }

    private static func defaultLocalSourceFingerprint(
        claudeAllConfigDirs: [String]
    ) -> CachedLocalSourceFingerprint {
        CachedLocalSourceFingerprint(
            codex: usageAnalyticsFileFingerprint(
                from: LocalUsageSourceFingerprintBuilder.codexFingerprint(scope: .allAccounts)
            ),
            claude: usageAnalyticsFileFingerprint(from: LocalUsageSourceFingerprintBuilder.claudeFingerprint(
                scope: .allAccounts,
                currentConfigDir: nil,
                allConfigDirs: claudeAllConfigDirs
            )),
            kimi: usageAnalyticsFileFingerprint(from: LocalUsageSourceFingerprintBuilder.kimiFingerprint()),
            cursor: usageAnalyticsFileFingerprint(from: LocalUsageSourceFingerprintBuilder.cursorFingerprint()),
            grok: usageAnalyticsFileFingerprint(from: LocalUsageSourceFingerprintBuilder.grokFingerprint()),
            gemini: usageAnalyticsFileFingerprint(from: LocalUsageSourceFingerprintBuilder.geminiFingerprint())
        )
    }

    private static func localSourceFingerprintCacheKey(
        claudeAllConfigDirs: [String]
    ) -> String {
        let normalizedDirs = Set(claudeAllConfigDirs.compactMap { dir -> String? in
            let trimmed = dir.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let expanded = (trimmed as NSString).expandingTildeInPath
            return (expanded as NSString).standardizingPath
        })
        return "claude=\(normalizedDirs.sorted().joined(separator: "\u{1F}"))"
    }

    private static func usageAnalyticsFileFingerprint(
        from fingerprint: LocalUsageSourceFingerprint
    ) -> UsageAnalyticsFileFingerprint {
        UsageAnalyticsFileFingerprint(
            roots: fingerprint.roots,
            fileCount: fingerprint.fileCount,
            totalSize: fingerprint.totalSize,
            latestModificationTime: fingerprint.latestModificationTime,
            metadataDigest: fingerprint.metadataDigest
        )
    }
}
