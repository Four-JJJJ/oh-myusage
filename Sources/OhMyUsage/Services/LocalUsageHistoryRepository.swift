import Foundation
import OhMyUsageApplication
import OhMyUsageDomain

struct LocalUsageHistoryQuery: Codable, Equatable, Hashable, Sendable {
    var providerType: ProviderType
    var providerID: String
    var scope: LocalUsageTrendScope
    var identityKey: String

    init(
        providerType: ProviderType,
        providerID: String,
        scope: LocalUsageTrendScope,
        identityKey: String
    ) {
        self.providerType = providerType
        self.providerID = providerID
        self.scope = scope
        self.identityKey = identityKey
    }
}

struct LocalUsageSourceFingerprint: Codable, Equatable, Sendable {
    var roots: [String]
    var fileCount: Int
    var totalSize: UInt64
    var latestModificationTime: Date?
}

struct LocalUsageHistoryEntry: Codable, Equatable, Sendable {
    var query: LocalUsageHistoryQuery
    var summary: LocalUsageSummary?
    var refreshedAt: Date
    var sourceFingerprint: LocalUsageSourceFingerprint?
    var lastFingerprintCheckedAt: Date?
    var lastError: String?
    var isStaleFallback: Bool
}

struct LocalUsageHistoryState: Equatable, Sendable {
    var summary: LocalUsageSummary?
    var error: String?
    var isLoading: Bool
    var lastRefreshedAt: Date?
    var sourceFingerprint: LocalUsageSourceFingerprint?
    var lastFingerprintCheckedAt: Date?
    var isStaleFallback: Bool
}

struct LocalUsageHistoryLoadResult: Sendable {
    var summary: LocalUsageSummary
    var sourceFingerprint: LocalUsageSourceFingerprint
}

struct LocalUsageFileSnapshot: Equatable, Hashable, Sendable {
    var path: String
    var fileSize: UInt64
    var modifiedAtRef: TimeInterval?
}

final class LocalUsageFileEnumerationCache: @unchecked Sendable {
    private struct CacheKey: Hashable {
        var identifier: String
        var roots: [String]
        var cutoffRef: TimeInterval
    }

    private struct PathSnapshot: Equatable {
        var path: String
        var exists: Bool
        var isDirectory: Bool
        var fileSize: UInt64?
        var modifiedAtRef: TimeInterval?
    }

    private struct Entry {
        var pathSnapshots: [PathSnapshot]
        var files: [LocalUsageFileSnapshot]
    }

    private let lock = NSLock()
    private let maxEntries: Int
    private var entries: [CacheKey: Entry] = [:]

    init(maxEntries: Int = 32) {
        self.maxEntries = max(1, maxEntries)
    }

    func files(
        identifier: String,
        roots: [String],
        cutoff: Date,
        fileManager: FileManager,
        includeFile: (URL) -> Bool
    ) -> [LocalUsageFileSnapshot] {
        let normalizedRoots = roots
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }
            .sorted()
        let key = CacheKey(
            identifier: identifier,
            roots: normalizedRoots,
            cutoffRef: cutoff.timeIntervalSinceReferenceDate
        )

        // Validate filesystem metadata outside the lock. Holding the lock during
        // pathSnapshot I/O can stall other callers (including tests) for a long time
        // when a prior enumeration cached a large directory tree.
        lock.lock()
        let cached = entries[key]
        lock.unlock()

        if let entry = cached, isValid(entry: entry, fileManager: fileManager) {
            return entry.files
        }

        let entry = buildEntry(
            roots: normalizedRoots,
            cutoff: cutoff,
            fileManager: fileManager,
            includeFile: includeFile
        )

        lock.lock()
        entries[key] = entry
        pruneIfNeeded()
        lock.unlock()

        return entry.files
    }

    func removeAllEntries() {
        lock.lock()
        entries.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private func isValid(entry: Entry, fileManager: FileManager) -> Bool {
        for snapshot in entry.pathSnapshots {
            if Self.pathSnapshot(atPath: snapshot.path, fileManager: fileManager) != snapshot {
                return false
            }
        }
        return true
    }

    private func buildEntry(
        roots: [String],
        cutoff: Date,
        fileManager: FileManager,
        includeFile: (URL) -> Bool
    ) -> Entry {
        var pathSnapshots: [PathSnapshot] = []
        var files: [LocalUsageFileSnapshot] = []

        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            let rootSnapshot = Self.pathSnapshot(atPath: root, fileManager: fileManager)
            pathSnapshots.append(rootSnapshot)
            guard rootSnapshot.exists else {
                continue
            }

            if !rootSnapshot.isDirectory {
                guard includeFile(rootURL),
                      let file = Self.fileSnapshot(atPath: root, fileManager: fileManager) else {
                    continue
                }
                if Self.modifiedAtRef(file.modifiedAtRef, isAtOrAfter: cutoff) {
                    files.append(file)
                }
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey,
                        .contentModificationDateKey
                    ]
                ) else {
                    continue
                }

                // Avoid symlink cycles / accidental traversal into huge external trees.
                if values.isSymbolicLink == true {
                    if values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                if values.isDirectory == true {
                    pathSnapshots.append(Self.pathSnapshot(from: fileURL, values: values))
                    continue
                }

                guard includeFile(fileURL),
                      values.isRegularFile == true else {
                    continue
                }

                let size = UInt64(max(0, values.fileSize ?? 0))
                let snapshot = LocalUsageFileSnapshot(
                    path: fileURL.path,
                    fileSize: size,
                    modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate
                )
                pathSnapshots.append(Self.pathSnapshot(from: fileURL, values: values))
                if Self.modifiedAtRef(snapshot.modifiedAtRef, isAtOrAfter: cutoff) {
                    files.append(snapshot)
                }
            }
        }

        return Entry(
            pathSnapshots: pathSnapshots,
            files: files.sorted { $0.path < $1.path }
        )
    }

    private static func modifiedAtRef(_ modifiedAtRef: TimeInterval?, isAtOrAfter cutoff: Date) -> Bool {
        guard let modifiedAtRef else { return true }
        return modifiedAtRef >= cutoff.timeIntervalSinceReferenceDate
    }

    private static func fileSnapshot(
        atPath path: String,
        fileManager: FileManager
    ) -> LocalUsageFileSnapshot? {
        let snapshot = pathSnapshot(atPath: path, fileManager: fileManager)
        guard snapshot.exists,
              !snapshot.isDirectory else {
            return nil
        }
        return LocalUsageFileSnapshot(
            path: path,
            fileSize: snapshot.fileSize ?? 0,
            modifiedAtRef: snapshot.modifiedAtRef
        )
    }

    private static func pathSnapshot(
        atPath path: String,
        fileManager: FileManager
    ) -> PathSnapshot {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return PathSnapshot(
                path: path,
                exists: false,
                isDirectory: false,
                fileSize: nil,
                modifiedAtRef: nil
            )
        }

        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let modifiedAt = attributes?[.modificationDate] as? Date
        let size = attributes?[.size] as? NSNumber
        return PathSnapshot(
            path: path,
            exists: true,
            isDirectory: isDirectory.boolValue,
            fileSize: isDirectory.boolValue ? nil : size.map { UInt64(truncating: $0) },
            modifiedAtRef: modifiedAt?.timeIntervalSinceReferenceDate
        )
    }

    private static func pathSnapshot(
        from url: URL,
        values: URLResourceValues
    ) -> PathSnapshot {
        PathSnapshot(
            path: url.path,
            exists: true,
            isDirectory: values.isDirectory == true,
            fileSize: values.isDirectory == true ? nil : UInt64(max(0, values.fileSize ?? 0)),
            modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate
        )
    }

    private func pruneIfNeeded() {
        guard entries.count > maxEntries else { return }
        let overflow = entries.count - maxEntries
        for key in entries.keys.prefix(overflow) {
            entries.removeValue(forKey: key)
        }
    }
}

final class LocalUsageParsedFileCache<Value>: @unchecked Sendable {
    private struct CacheKey: Hashable {
        var path: String
        var context: String
    }

    private struct Entry {
        var snapshot: LocalUsageFileSnapshot
        var values: [Value]
    }

    private let lock = NSLock()
    private let maxEntries: Int
    private let maxCachedValues: Int
    private var entries: [CacheKey: Entry] = [:]
    private var accessOrder: [CacheKey] = []
    private var cachedValueCount = 0

    init(maxEntries: Int = 512, maxCachedValues: Int? = nil) {
        self.maxEntries = max(1, maxEntries)
        self.maxCachedValues = max(1, maxCachedValues ?? max(1, maxEntries) * 256)
    }

    func values(
        for snapshot: LocalUsageFileSnapshot,
        context: String = "",
        parse: () -> [Value]
    ) -> [Value] {
        let key = CacheKey(path: snapshot.path, context: context)

        lock.lock()
        if let entry = entries[key], entry.snapshot == snapshot {
            let values = entry.values
            markAccessedLocked(key)
            lock.unlock()
            return values
        }
        removeEntryLocked(for: key)
        lock.unlock()

        let parsed = parse()

        lock.lock()
        entries[key] = Entry(snapshot: snapshot, values: parsed)
        cachedValueCount += parsed.count
        markAccessedLocked(key)
        pruneIfNeeded()
        lock.unlock()

        return parsed
    }

    func removeAllEntries() {
        lock.lock()
        entries.removeAll(keepingCapacity: false)
        accessOrder.removeAll(keepingCapacity: false)
        cachedValueCount = 0
        lock.unlock()
    }

    private func markAccessedLocked(_ key: CacheKey) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func removeEntryLocked(for key: CacheKey) {
        if let removed = entries.removeValue(forKey: key) {
            cachedValueCount = max(0, cachedValueCount - removed.values.count)
        }
        accessOrder.removeAll { $0 == key }
    }

    private func pruneIfNeeded() {
        accessOrder.removeAll { entries[$0] == nil }
        while entries.count > maxEntries || (cachedValueCount > maxCachedValues && entries.count > 1) {
            guard let key = accessOrder.first else { return }
            removeEntryLocked(for: key)
        }
    }
}

enum LocalUsageSourceFingerprintBuilder {
    static func codexFingerprint(scope: LocalUsageTrendScope) -> LocalUsageSourceFingerprint {
        let codexRoot = "\(NSHomeDirectory())/.codex"
        switch scope {
        case .allAccounts:
            return fingerprint(
                roots: [
                    "\(codexRoot)/sessions",
                    "\(codexRoot)/archived_sessions"
                ],
                includeFile: { $0.pathExtension.lowercased() == "jsonl" }
            )
        case .currentAccount:
            return fingerprint(
                roots: ["\(codexRoot)/logs_2.sqlite"],
                includeFile: { _ in true }
            )
        }
    }

    static func claudeFingerprint(
        scope: LocalUsageTrendScope,
        currentConfigDir: String?,
        allConfigDirs: [String]
    ) -> LocalUsageSourceFingerprint {
        let defaultRoot = "\(NSHomeDirectory())/.claude/projects"
        let normalizedAllConfigDirs = allConfigDirs.compactMap(normalizedDirectoryPath)
        let allRoots = uniquePaths(
            [defaultRoot] + normalizedAllConfigDirs.map(projectsRoot(fromConfigDir:))
        )

        let roots: [String]
        switch scope {
        case .allAccounts:
            roots = allRoots
        case .currentAccount:
            if let currentConfigDir = normalizedDirectoryPath(currentConfigDir) {
                roots = [projectsRoot(fromConfigDir: currentConfigDir)]
            } else {
                roots = [defaultRoot]
            }
        }

        return fingerprint(
            roots: roots,
            includeFile: { $0.pathExtension.lowercased() == "jsonl" }
        )
    }

    static func kimiFingerprint() -> LocalUsageSourceFingerprint {
        fingerprint(
            roots: [
                "\(NSHomeDirectory())/.kimi/sessions",
                "\(NSHomeDirectory())/.kimi-code/sessions"
            ],
            includeFile: { $0.lastPathComponent == "wire.jsonl" }
        )
    }

    static func cursorFingerprint() -> LocalUsageSourceFingerprint {
        fingerprint(
            roots: [
                "\(NSHomeDirectory())/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
                "\(NSHomeDirectory())/.cursor/projects"
            ],
            includeFile: { url in
                url.lastPathComponent == "state.vscdb" || url.pathExtension.lowercased() == "jsonl"
            }
        )
    }

    static func grokFingerprint() -> LocalUsageSourceFingerprint {
        fingerprint(
            roots: [GrokLocalUsageService.resolvedSessionsRoot(
                homeDirectory: NSHomeDirectory(),
                environment: ProcessInfo.processInfo.environment
            )],
            includeFile: { name in
                let filename = name.lastPathComponent
                return filename == "summary.json" || filename == "updates.jsonl" || filename == "signals.json"
            }
        )
    }

    static func geminiFingerprint() -> LocalUsageSourceFingerprint {
        fingerprint(
            roots: ["\(NSHomeDirectory())/.gemini/tmp"],
            includeFile: { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasPrefix("session-") && (name.hasSuffix(".jsonl") || name.hasSuffix(".json"))
            }
        )
    }

    static func fingerprint(
        roots: [String],
        fileManager: FileManager = .default,
        includeFile: (URL) -> Bool
    ) -> LocalUsageSourceFingerprint {
        let normalizedRoots = roots
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }
            .sorted()
        var accumulator = FingerprintAccumulator()

        for root in normalizedRoots {
            let rootURL = URL(fileURLWithPath: root)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory) else {
                continue
            }

            if !isDirectory.boolValue {
                if includeFile(rootURL) {
                    accumulator.add(rootURL)
                }
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator where includeFile(fileURL) {
                accumulator.add(fileURL)
            }
        }

        return LocalUsageSourceFingerprint(
            roots: normalizedRoots,
            fileCount: accumulator.fileCount,
            totalSize: accumulator.totalSize,
            latestModificationTime: accumulator.latestModificationTime
        )
    }

    private struct FingerprintAccumulator {
        var fileCount = 0
        var totalSize: UInt64 = 0
        var latestModificationTime: Date?

        mutating func add(_ fileURL: URL) {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            ), values.isRegularFile == true else {
                return
            }

            fileCount += 1
            if let fileSize = values.fileSize, fileSize > 0 {
                totalSize += UInt64(fileSize)
            }
            if let modifiedAt = values.contentModificationDate,
               latestModificationTime == nil || modifiedAt > (latestModificationTime ?? .distantPast) {
                latestModificationTime = modifiedAt
            }
        }
    }

    private static func projectsRoot(fromConfigDir configDir: String) -> String {
        URL(fileURLWithPath: configDir, isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .path
    }

    private static func normalizedDirectoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func uniquePaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for path in paths where seen.insert(path).inserted {
            output.append(path)
        }
        return output
    }
}

@MainActor
final class LocalUsageHistoryRepository {
    typealias FingerprintProvider = @Sendable () -> LocalUsageSourceFingerprint
    typealias Loader = @Sendable (_ sourceFingerprint: LocalUsageSourceFingerprint) throws -> LocalUsageHistoryLoadResult

    private struct CachePayload: Codable {
        var entries: [LocalUsageHistoryEntry]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private var entries: [LocalUsageHistoryQuery: LocalUsageHistoryEntry] = [:]
    private var loadingTasks: [LocalUsageHistoryQuery: Task<Void, Never>] = [:]
    private var lastPersistedCacheData: Data?
    private var lastPersistedEntries: [LocalUsageHistoryEntry]?

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        let rootDirectory: URL
        if let baseDirectoryURL {
            rootDirectory = baseDirectoryURL
        } else {
            rootDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }
        self.fileURL = rootDirectory
            .appendingPathComponent("OhMyUsage", isDirectory: true)
            .appendingPathComponent("local_usage_history_cache.json")
        restoreFromDisk()
    }

    func snapshot(for query: LocalUsageHistoryQuery) -> LocalUsageHistoryState {
        let entry = entries[query]
        return LocalUsageHistoryState(
            summary: entry?.summary,
            error: entry?.lastError,
            isLoading: loadingTasks[query] != nil,
            lastRefreshedAt: entry?.refreshedAt,
            sourceFingerprint: entry?.sourceFingerprint,
            lastFingerprintCheckedAt: entry?.lastFingerprintCheckedAt,
            isStaleFallback: entry?.isStaleFallback ?? false
        )
    }

    func refreshIfNeeded(
        query: LocalUsageHistoryQuery,
        force: Bool = false,
        ttl: TimeInterval = RuntimeDiagnosticsLimits.localUsageTrendCacheEntryTTL,
        fingerprintProbeInterval: TimeInterval = RuntimeDiagnosticsLimits.localUsageTrendFingerprintProbeInterval,
        fingerprintProvider: @escaping FingerprintProvider,
        loader: @escaping Loader,
        onStateChange: @escaping @MainActor () -> Void
    ) {
        prune(now: nowProvider())
        guard loadingTasks[query] == nil else { return }

        let now = nowProvider()
        if !force,
           let entry = entries[query],
           let summary = entry.summary,
           now.timeIntervalSince(entry.refreshedAt) < ttl,
           isSummaryTemporallyFresh(summary, now: now),
           !shouldProbeFingerprint(entry: entry, now: now, interval: fingerprintProbeInterval) {
            return
        }

        loadingTasks[query] = Task { @MainActor [weak self] in
            guard let self else { return }
            onStateChange()

            let fingerprint = await Task.detached(priority: .utility) {
                fingerprintProvider()
            }.value

            if !force,
               var entry = entries[query],
               let summary = entry.summary,
               entry.sourceFingerprint == fingerprint,
               isSummaryTemporallyFresh(summary, now: nowProvider()) {
                let validatedAt = nowProvider()
                entry.refreshedAt = validatedAt
                entry.lastFingerprintCheckedAt = validatedAt
                entry.lastError = nil
                entry.isStaleFallback = false
                entries[query] = entry
                loadingTasks.removeValue(forKey: query)
                prune(now: entry.refreshedAt)
                persist()
                onStateChange()
                return
            }

            let result = await Task.detached(priority: .utility) {
                Result<LocalUsageHistoryLoadResult, Error> {
                    try loader(fingerprint)
                }
            }.value

            loadingTasks.removeValue(forKey: query)
            let refreshedAt = nowProvider()
            switch result {
            case .success(let loadResult):
                entries[query] = LocalUsageHistoryEntry(
                    query: query,
                    summary: RuntimeBoundedState.slimmedLocalUsageSummaryForCache(loadResult.summary),
                    refreshedAt: refreshedAt,
                    sourceFingerprint: loadResult.sourceFingerprint,
                    lastFingerprintCheckedAt: refreshedAt,
                    lastError: nil,
                    isStaleFallback: false
                )
            case .failure(let error):
                if var existing = entries[query], existing.summary != nil {
                    existing.refreshedAt = refreshedAt
                    existing.lastFingerprintCheckedAt = refreshedAt
                    existing.lastError = error.localizedDescription
                    existing.isStaleFallback = true
                    entries[query] = existing
                } else {
                    entries[query] = LocalUsageHistoryEntry(
                        query: query,
                        summary: nil,
                        refreshedAt: refreshedAt,
                        sourceFingerprint: fingerprint,
                        lastFingerprintCheckedAt: refreshedAt,
                        lastError: error.localizedDescription,
                        isStaleFallback: false
                    )
                }
            }

            prune(now: refreshedAt)
            persist()
            onStateChange()
        }

        onStateChange()
    }

    func restoreFromDisk() {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let payload = try? decoder.decode(CachePayload.self, from: data) else {
            return
        }
        entries = Dictionary(uniqueKeysWithValues: payload.entries.map { ($0.query, $0) })
        prune(now: nowProvider())
        let persistedEntries = sortedEntries()
        lastPersistedEntries = persistedEntries
        lastPersistedCacheData = try? encoder.encode(CachePayload(entries: persistedEntries))
    }

    func persist() {
        do {
            let persistedEntries = sortedEntries()
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
            try ensureDirectoryExists()
            try data.write(to: fileURL, options: .atomic)
            lastPersistedEntries = persistedEntries
            lastPersistedCacheData = data
        } catch {
            return
        }
    }

    private func prune(now: Date) {
        let ttl = max(30, RuntimeDiagnosticsLimits.localUsageTrendCacheEntryTTL)
        let cutoff = now.addingTimeInterval(-ttl)
        entries = entries.filter { _, entry in
            entry.refreshedAt >= cutoff || entry.summary != nil
        }

        let maxEntries = max(1, RuntimeDiagnosticsLimits.localUsageTrendCacheMaxEntries)
        guard entries.count > maxEntries else { return }

        let keepQueries = Set(
            entries.values
                .sorted { lhs, rhs in
                    if lhs.refreshedAt != rhs.refreshedAt {
                        return lhs.refreshedAt > rhs.refreshedAt
                    }
                    return lhs.query.providerID < rhs.query.providerID
                }
                .prefix(maxEntries)
                .map(\.query)
        )
        entries = entries.filter { keepQueries.contains($0.key) }
    }

    private func sortedEntries() -> [LocalUsageHistoryEntry] {
        entries.values.sorted { lhs, rhs in
            if lhs.refreshedAt != rhs.refreshedAt {
                return lhs.refreshedAt > rhs.refreshedAt
            }
            return lhs.query.providerID < rhs.query.providerID
        }
    }

    private func shouldProbeFingerprint(
        entry: LocalUsageHistoryEntry,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard entry.sourceFingerprint != nil else { return true }
        let reference = entry.lastFingerprintCheckedAt ?? entry.refreshedAt
        return now.timeIntervalSince(reference) >= max(5, interval)
    }

    private func isSummaryTemporallyFresh(_ summary: LocalUsageSummary, now: Date) -> Bool {
        Calendar.current.isDate(summary.generatedAt, equalTo: now, toGranularity: .hour)
    }

    private func ensureDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
