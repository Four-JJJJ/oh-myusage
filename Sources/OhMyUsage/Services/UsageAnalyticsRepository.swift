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
            lock.unlock()
        }

        func removeAll() {
            lock.lock()
            entries.removeAll()
            lock.unlock()
        }
    }

    private static let localSourceFingerprintCache = LocalSourceFingerprintCache(ttl: 60)

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
        self.ccSwitchReader = ccSwitchReader
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.ccSwitchSourceFingerprintProvider = ccSwitchSourceFingerprintProvider
        self.localSourceFingerprintProvider = localSourceFingerprintProvider
    }

    func snapshot(
        filter: UsageAnalyticsFilter,
        claudeAllConfigDirs: [String] = []
    ) -> UsageAnalyticsSnapshot {
        let now = nowProvider()
        let interval = UsageAnalyticsAggregator.rangeInterval(filter.range, calendar: calendar, now: now)
        var diagnostics: [String] = []
        var records: [UsageAnalyticsRecord] = []

        let ccSwitchResult = ccSwitchReader.readUsageLogs(since: interval.start, until: interval.end)
        records.append(contentsOf: ccSwitchResult.records.map(\.analyticsRecord))
        let ccSwitchMissing = ccSwitchResult.diagnostics.contains { $0.contains("未安装 cc-switch") }
        if ccSwitchMissing {
            diagnostics.append("未安装 cc-switch，已仅使用各官方应用的本地用量日志")
        } else {
            diagnostics.append(contentsOf: ccSwitchResult.diagnostics)
        }
        diagnostics.insert(
            ccSwitchMissing
                ? "统计来源：Codex / Claude / Kimi / Cursor / Grok / Gemini 本地用量"
                : "统计来源：本地官方用量 + cc-switch 请求日志",
            at: 0
        )

        let localResult = readLocalRecords(
            since: interval.start,
            claudeAllConfigDirs: claudeAllConfigDirs
        )
        records.append(contentsOf: localResult.records)
        diagnostics.append(contentsOf: localResult.diagnostics)

        return UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: filter,
            calendar: calendar,
            now: now,
            diagnostics: diagnostics
        )
    }

    func sourceFingerprint(claudeAllConfigDirs: [String] = []) -> UsageAnalyticsSourceFingerprint {
        let now = nowProvider()
        let ccSwitch = ccSwitchSourceFingerprintProvider(ccSwitchReader)
        let cacheKey = Self.localSourceFingerprintCacheKey(
            claudeAllConfigDirs: claudeAllConfigDirs
        )
        let localFingerprint: CachedLocalSourceFingerprint
        if let cached = Self.localSourceFingerprintCache.fingerprint(for: cacheKey, now: now) {
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
        claudeAllConfigDirs: [String]
    ) -> (records: [UsageAnalyticsRecord], diagnostics: [String]) {
        var records: [UsageAnalyticsRecord] = []
        var diagnostics: [String] = []

        do {
            let codexEvents = try CodexLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, since: since)
            records.append(contentsOf: codexEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "codex",
                    providerID: "ohmyusage-codex-local",
                    providerName: "Codex"
                )
            })
        } catch {
            diagnostics.append("Codex 本地日志读取失败：\(error.localizedDescription)")
        }

        do {
            let claudeEvents = try ClaudeLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, allConfigDirs: claudeAllConfigDirs, since: since)
            records.append(contentsOf: claudeEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "claude",
                    providerID: "ohmyusage-claude-local",
                    providerName: "Claude"
                )
            })
        } catch {
            diagnostics.append("Claude 本地日志读取失败：\(error.localizedDescription)")
        }

        do {
            let kimiEvents = try KimiLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, since: since)
            records.append(contentsOf: kimiEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "kimi",
                    providerID: "ohmyusage-kimi-local",
                    providerName: "Kimi"
                )
            })
        } catch {
            diagnostics.append("Kimi 本地日志读取失败：\(error.localizedDescription)")
        }

        do {
            let cursorEvents = try CursorLocalUsageService(
                calendar: calendar,
                nowProvider: nowProvider,
                dashboardFetcher: CursorDashboardUsageClient()
            ).fetchEvents(since: since)
            records.append(contentsOf: cursorEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "cursor",
                    providerID: "ohmyusage-cursor-local",
                    providerName: "Cursor"
                )
            })
        } catch {
            diagnostics.append("Cursor 用量读取失败：\(error.localizedDescription)")
        }

        do {
            let grokEvents = try GrokLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(since: since)
            records.append(contentsOf: grokEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "grok",
                    providerID: "ohmyusage-grok-local",
                    providerName: "Grok"
                )
            })
        } catch {
            diagnostics.append("Grok 本地日志读取失败：\(error.localizedDescription)")
        }

        do {
            let geminiEvents = try GeminiLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(since: since)
            records.append(contentsOf: geminiEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "gemini",
                    providerID: "ohmyusage-gemini-local",
                    providerName: "Gemini"
                )
            })
        } catch {
            diagnostics.append("Gemini 本地日志读取失败：\(error.localizedDescription)")
        }

        return (records, diagnostics)
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
            latestModificationTime: fingerprint.latestModificationTime
        )
    }
}
