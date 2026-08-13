import Foundation

public struct UsageAnalyticsFileFingerprint: Codable, Equatable, Sendable {
    public var roots: [String]
    public var fileCount: Int
    public var totalSize: UInt64
    public var latestModificationTime: Date?

    public init(
        roots: [String],
        fileCount: Int,
        totalSize: UInt64,
        latestModificationTime: Date?
    ) {
        self.roots = roots
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.latestModificationTime = latestModificationTime
    }

    public static let empty = UsageAnalyticsFileFingerprint(
        roots: [],
        fileCount: 0,
        totalSize: 0,
        latestModificationTime: nil
    )
}

public struct UsageAnalyticsSourceFingerprint: Codable, Equatable, Sendable {
    public var ccSwitch: UsageAnalyticsFileFingerprint
    public var codex: UsageAnalyticsFileFingerprint
    public var claude: UsageAnalyticsFileFingerprint
    public var kimi: UsageAnalyticsFileFingerprint
    public var cursor: UsageAnalyticsFileFingerprint
    public var grok: UsageAnalyticsFileFingerprint
    public var gemini: UsageAnalyticsFileFingerprint

    public init(
        ccSwitch: UsageAnalyticsFileFingerprint,
        codex: UsageAnalyticsFileFingerprint,
        claude: UsageAnalyticsFileFingerprint,
        kimi: UsageAnalyticsFileFingerprint,
        cursor: UsageAnalyticsFileFingerprint = .empty,
        grok: UsageAnalyticsFileFingerprint = .empty,
        gemini: UsageAnalyticsFileFingerprint = .empty
    ) {
        self.ccSwitch = ccSwitch
        self.codex = codex
        self.claude = claude
        self.kimi = kimi
        self.cursor = cursor
        self.grok = grok
        self.gemini = gemini
    }

    enum CodingKeys: String, CodingKey {
        case ccSwitch, codex, claude, kimi, cursor, grok, gemini
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ccSwitch = try container.decode(UsageAnalyticsFileFingerprint.self, forKey: .ccSwitch)
        codex = try container.decode(UsageAnalyticsFileFingerprint.self, forKey: .codex)
        claude = try container.decode(UsageAnalyticsFileFingerprint.self, forKey: .claude)
        kimi = try container.decode(UsageAnalyticsFileFingerprint.self, forKey: .kimi)
        cursor = try container.decodeIfPresent(UsageAnalyticsFileFingerprint.self, forKey: .cursor) ?? .empty
        grok = try container.decodeIfPresent(UsageAnalyticsFileFingerprint.self, forKey: .grok) ?? .empty
        gemini = try container.decodeIfPresent(UsageAnalyticsFileFingerprint.self, forKey: .gemini) ?? .empty
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ccSwitch, forKey: .ccSwitch)
        try container.encode(codex, forKey: .codex)
        try container.encode(claude, forKey: .claude)
        try container.encode(kimi, forKey: .kimi)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(grok, forKey: .grok)
        try container.encode(gemini, forKey: .gemini)
    }
}

public struct UsageAnalyticsCacheEntry: Codable, Equatable, Sendable {
    public var filter: UsageAnalyticsFilter
    public var snapshot: UsageAnalyticsSnapshot
    public var sourceFingerprint: UsageAnalyticsSourceFingerprint?
    public var refreshedAt: Date
    public var lastFingerprintCheckedAt: Date?

    public init(
        filter: UsageAnalyticsFilter,
        snapshot: UsageAnalyticsSnapshot,
        sourceFingerprint: UsageAnalyticsSourceFingerprint?,
        refreshedAt: Date,
        lastFingerprintCheckedAt: Date?
    ) {
        self.filter = filter
        self.snapshot = snapshot
        self.sourceFingerprint = sourceFingerprint
        self.refreshedAt = refreshedAt
        self.lastFingerprintCheckedAt = lastFingerprintCheckedAt
    }
}

public final class UsageAnalyticsSnapshotCacheStore: @unchecked Sendable {
    private struct CachePayload: Codable {
        var entries: [UsageAnalyticsCacheEntry]
    }

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL
    private let nowProvider: () -> Date
    private let maxEntries: Int
    private let lock = NSLock()
    private var entries: [UsageAnalyticsFilter: UsageAnalyticsCacheEntry] = [:]
    private var lastPersistedCacheData: Data?
    private var lastPersistedEntries: [UsageAnalyticsCacheEntry]?

    public init(
        baseDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init,
        maxEntries: Int? = nil
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.maxEntries = max(1, maxEntries ?? RuntimeDiagnosticsLimits.usageAnalyticsCacheMaxEntries)
        let rootDirectory = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = rootDirectory
            .appendingPathComponent("OhMyUsage", isDirectory: true)
            .appendingPathComponent("usage_analytics_cache.json")
        restoreFromDisk()
    }

    public func entry(for filter: UsageAnalyticsFilter) -> UsageAnalyticsCacheEntry? {
        lock.lock()
        let entry = entries[filter]
        lock.unlock()
        return entry
    }

    public func save(
        snapshot: UsageAnalyticsSnapshot,
        sourceFingerprint: UsageAnalyticsSourceFingerprint?
    ) {
        let now = nowProvider()
        lock.lock()
        entries[snapshot.filter] = UsageAnalyticsCacheEntry(
            filter: snapshot.filter,
            snapshot: snapshot,
            sourceFingerprint: sourceFingerprint,
            refreshedAt: now,
            lastFingerprintCheckedAt: sourceFingerprint == nil ? nil : now
        )
        pruneLocked()
        persistLocked()
        lock.unlock()
    }

    public func markValidated(
        filter: UsageAnalyticsFilter,
        sourceFingerprint: UsageAnalyticsSourceFingerprint,
        at validatedAt: Date
    ) {
        lock.lock()
        if var entry = entries[filter] {
            entry.sourceFingerprint = sourceFingerprint
            entry.refreshedAt = validatedAt
            entry.lastFingerprintCheckedAt = validatedAt
            entries[filter] = entry
            persistLocked()
        }
        lock.unlock()
    }

    public func shouldProbeFingerprint(
        for filter: UsageAnalyticsFilter,
        now: Date,
        interval: TimeInterval? = nil
    ) -> Bool {
        guard let entry = entry(for: filter) else { return true }
        let checkedAt = entry.lastFingerprintCheckedAt ?? entry.refreshedAt
        return now.timeIntervalSince(checkedAt) >= max(
            1,
            interval ?? RuntimeDiagnosticsLimits.usageAnalyticsFingerprintProbeInterval
        )
    }

    public func isEntryTemporallyFresh(
        for filter: UsageAnalyticsFilter,
        now: Date,
        calendar: Calendar,
        ttl: TimeInterval? = nil
    ) -> Bool {
        guard let entry = entry(for: filter) else { return false }
        guard now.timeIntervalSince(entry.refreshedAt) < max(
            30,
            ttl ?? RuntimeDiagnosticsLimits.usageAnalyticsCacheEntryTTL
        ) else { return false }
        return Self.isSnapshotWindowCurrent(
            generatedAt: entry.snapshot.generatedAt,
            now: now,
            range: filter.range,
            calendar: calendar
        )
    }

    private func restoreFromDisk() {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let payload = try? decoder.decode(CachePayload.self, from: data) else {
            return
        }
        lock.lock()
        entries = Dictionary(uniqueKeysWithValues: payload.entries.map { ($0.filter, $0) })
        pruneLocked()
        let persistedEntries = sortedEntriesLocked()
        lastPersistedEntries = persistedEntries
        lastPersistedCacheData = try? encoder.encode(CachePayload(entries: persistedEntries))
        lock.unlock()
    }

    private func persistLocked() {
        do {
            let persistedEntries = sortedEntriesLocked()
            if persistedEntries == lastPersistedEntries,
               fileManager.fileExists(atPath: fileURL.path) {
                return
            }
            let payload = CachePayload(entries: persistedEntries)
            let data = try encoder.encode(payload)
            if data == lastPersistedCacheData,
               fileManager.fileExists(atPath: fileURL.path) {
                lastPersistedEntries = persistedEntries
                return
            }
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            lastPersistedEntries = persistedEntries
            lastPersistedCacheData = data
        } catch {
            return
        }
    }

    private func pruneLocked() {
        guard entries.count > maxEntries else { return }
        let keepFilters = Set(sortedEntriesLocked().prefix(maxEntries).map(\.filter))
        entries = entries.filter { keepFilters.contains($0.key) }
    }

    private func sortedEntriesLocked() -> [UsageAnalyticsCacheEntry] {
        entries.values.sorted { lhs, rhs in
            if lhs.refreshedAt != rhs.refreshedAt {
                return lhs.refreshedAt > rhs.refreshedAt
            }
            return lhs.filter.range.rawValue < rhs.filter.range.rawValue
        }
    }

    private static func isSnapshotWindowCurrent(
        generatedAt: Date,
        now: Date,
        range: UsageAnalyticsRange,
        calendar: Calendar
    ) -> Bool {
        switch range {
        case .last24Hours:
            return calendar.isDate(generatedAt, equalTo: now, toGranularity: .hour)
        case .last7Days, .last30Days:
            return calendar.isDate(generatedAt, equalTo: now, toGranularity: .day)
        case .all:
            return calendar.isDate(generatedAt, equalTo: now, toGranularity: .month)
        }
    }
}
