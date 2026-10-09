import Foundation
import CryptoKit
import OSLog
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
    var metadataDigest: String? = nil
}

struct LocalUsageHistoryEntry: Codable, Equatable, Sendable {
    var query: LocalUsageHistoryQuery
    var summary: LocalUsageSummary?
    var refreshedAt: Date
    var sourceFingerprint: LocalUsageSourceFingerprint?
    var lastFingerprintCheckedAt: Date?
    var lastError: String?
    var isStaleFallback: Bool
    var lastAttemptAt: Date? = nil
    var retryNotBefore: Date? = nil
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
    var fileIdentity: UInt64? = nil
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
        var fileIdentity: UInt64? = nil
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
        guard !Task.isCancelled else { return entry.files }

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
            if Task.isCancelled { return false }
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
            if Task.isCancelled { break }
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
                if Task.isCancelled { break }
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
                    modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate,
                    fileIdentity: Self.fileIdentity(atPath: fileURL.path)
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
            modifiedAtRef: snapshot.modifiedAtRef,
            fileIdentity: snapshot.fileIdentity
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
            modifiedAtRef: modifiedAt?.timeIntervalSinceReferenceDate,
            fileIdentity: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
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
            modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate,
            fileIdentity: fileIdentity(atPath: url.path)
        )
    }

    private static func fileIdentity(atPath path: String) -> UInt64? {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.systemFileNumber] as? NSNumber)?.uint64Value
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
        var parsedAt: Date
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
        if let entry = entries[key], entry.snapshot == snapshot,
           Date().timeIntervalSince(entry.parsedAt) < 30 * 60 {
            let values = entry.values
            markAccessedLocked(key)
            lock.unlock()
            return values
        }
        removeEntryLocked(for: key)
        lock.unlock()

        let parsed = parse()
        guard !Task.isCancelled else { return parsed }

        lock.lock()
        // Another caller may have populated the same key while parsing happened
        // outside the lock. Replace that entry without leaking its count.
        removeEntryLocked(for: key)
        guard parsed.count <= maxCachedValues else {
            lock.unlock()
            return parsed
        }
        entries[key] = Entry(snapshot: snapshot, values: parsed, parsedAt: Date())
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

/// Explicit filter identities prevent different parsers sharing an incompatible inventory.
enum LocalUsageSourceInventory {
    enum Descriptor: String {
        case codexSessionJSONL
        case kimiWireJSONL

        func includes(_ url: URL) -> Bool {
            switch self {
            case .codexSessionJSONL: return url.pathExtension.lowercased() == "jsonl"
            case .kimiWireJSONL: return url.lastPathComponent == "wire.jsonl"
            }
        }
    }

    private static let cache = LocalUsageFileEnumerationCache(maxEntries: 8)

    static func files(descriptor: Descriptor, roots: [String], fileManager: FileManager = .default) -> [LocalUsageFileSnapshot] {
        cache.files(identifier: descriptor.rawValue, roots: roots, cutoff: .distantPast,
                    fileManager: fileManager, includeFile: descriptor.includes)
    }
}

enum LocalUsageSourceFingerprintBuilder {
    static func codexFingerprint(scope: LocalUsageTrendScope) -> LocalUsageSourceFingerprint {
        let codexRoot = "\(NSHomeDirectory())/.codex"
        switch scope {
        case .allAccounts:
            let roots = [
                    "\(codexRoot)/sessions",
                    "\(codexRoot)/archived_sessions"
                ]
            return fingerprint(roots: roots, inventory: LocalUsageSourceInventory.files(descriptor: .codexSessionJSONL, roots: roots))
        case .currentAccount:
            return fingerprint(
                roots: ["\(codexRoot)/logs_2.sqlite", "\(codexRoot)/logs_2.sqlite-wal"],
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
                "\(NSHomeDirectory())/Library/Application Support/Cursor/User/globalStorage/state.vscdb-wal",
                "\(NSHomeDirectory())/.cursor/projects"
            ],
            includeFile: { url in
                ["state.vscdb", "state.vscdb-wal"].contains(url.lastPathComponent) || url.pathExtension.lowercased() == "jsonl"
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
            if Task.isCancelled { break }
            let rootURL = URL(fileURLWithPath: root)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory) else {
                continue
            }

            if !isDirectory.boolValue {
                if includeFile(rootURL) {
                    accumulator.add(rootURL, fileManager: fileManager)
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
                if Task.isCancelled { break }
                accumulator.add(fileURL, fileManager: fileManager)
            }
        }

        return LocalUsageSourceFingerprint(
            roots: normalizedRoots,
            fileCount: accumulator.fileCount,
            totalSize: accumulator.totalSize,
            latestModificationTime: accumulator.latestModificationTime,
            metadataDigest: accumulator.digest
        )
    }

    static func fingerprint(roots: [String], inventory: [LocalUsageFileSnapshot]) -> LocalUsageSourceFingerprint {
        var accumulator = FingerprintAccumulator()
        for file in inventory {
            accumulator.add(path: file.path, size: file.fileSize, modifiedAt: file.modifiedAtRef.map(Date.init(timeIntervalSinceReferenceDate:)), inode: file.fileIdentity)
        }
        return LocalUsageSourceFingerprint(
            roots: roots.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }.sorted(),
            fileCount: accumulator.fileCount, totalSize: accumulator.totalSize,
            latestModificationTime: accumulator.latestModificationTime, metadataDigest: accumulator.digest)
    }

    private struct FingerprintAccumulator {
        var fileCount = 0
        var totalSize: UInt64 = 0
        var latestModificationTime: Date?
        var metadataTuples: [String] = []

        var digest: String {
            let data = Data(metadataTuples.sorted().joined(separator: "\n").utf8)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        mutating func add(_ fileURL: URL, fileManager: FileManager) {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            ), values.isRegularFile == true else {
                return
            }

            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
            add(path: fileURL.standardizedFileURL.path, size: UInt64(max(0, values.fileSize ?? 0)),
                modifiedAt: values.contentModificationDate, inode: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value)
        }

        mutating func add(path: String, size: UInt64, modifiedAt: Date?, inode: UInt64?) {
            let tuple = [path, String(size), String(modifiedAt?.timeIntervalSinceReferenceDate ?? 0), inode.map(String.init) ?? ""]
            // JSON framing avoids ambiguity for paths containing delimiters or newlines.
            if let data = try? JSONEncoder().encode(tuple), let text = String(data: data, encoding: .utf8) {
                metadataTuples.append(text)
            }
            fileCount += 1
            totalSize += size
            if let modifiedAt,
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
    typealias AsyncLoader = @Sendable (_ sourceFingerprint: LocalUsageSourceFingerprint) async throws -> LocalUsageHistoryLoadResult
    typealias Loader = @Sendable (_ sourceFingerprint: LocalUsageSourceFingerprint) throws -> LocalUsageHistoryLoadResult


    private let fileURL: URL
    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private var entries: [LocalUsageHistoryQuery: LocalUsageHistoryEntry] = [:]
    private var loadingTasks: [LocalUsageHistoryQuery: Task<Void, Never>] = [:]
    private let io: LocalUsageHistoryCacheIO
    private let asynchronousIO: Bool
    private var touchedQueries: Set<LocalUsageHistoryQuery> = []
    private var restoreTask: Task<Void, Never>?
    private var restoreRevision = 0
    private var restoreInFlight = false
    private var removedProvidersDuringRestore: Set<String> = []
    private var taskTokens: [LocalUsageHistoryQuery: UUID] = [:]
    var onRestore: (@MainActor () -> Void)?

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        asynchronousIO: Bool = true,
        beforeCacheRead: @escaping @Sendable () -> Void = {},
        cacheDiagnostic: @escaping @Sendable (String) -> Void = { category in
            Logger(subsystem: "OhMyUsage", category: "LocalUsageHistoryCache").notice("cache event: \(category, privacy: .public)")
        }
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
        self.asynchronousIO = asynchronousIO
        self.io = LocalUsageHistoryCacheIO(fileURL: fileURL, fileManager: fileManager,
            beforeRead: beforeCacheRead, diagnostic: cacheDiagnostic)
        restoreFromDisk()
    }

    func snapshot(for query: LocalUsageHistoryQuery) -> LocalUsageHistoryState {
        let entry = entries[query]
        return LocalUsageHistoryState(
            summary: entry?.summary,
            error: entry?.lastError,
            isLoading: loadingTasks[query] != nil,
            lastRefreshedAt: entry?.summary == nil ? nil : entry?.refreshedAt,
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
        asyncLoader: AsyncLoader? = nil,
        onStateChange: @escaping @MainActor () -> Void
    ) {
        prune(now: nowProvider())
        guard loadingTasks[query] == nil else { return }

        let now = nowProvider()
        if !force, let deadline = entries[query]?.retryNotBefore, now < deadline { return }
        if !force,
           let entry = entries[query],
           entry.lastError == nil,
           let summary = entry.summary,
           now.timeIntervalSince(entry.refreshedAt) < ttl,
           now.timeIntervalSince(entry.refreshedAt) < maximumLoadAge(for: query),
           isSummaryTemporallyFresh(summary, now: now),
           !shouldProbeFingerprint(entry: entry, now: now, interval: fingerprintProbeInterval) {
            return
        }

        let token = UUID()
        taskTokens[query] = token
        loadingTasks[query] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if taskTokens[query] == token {
                    loadingTasks.removeValue(forKey: query)
                    taskTokens.removeValue(forKey: query)
                }
            }
            await restoreTask?.value
            guard !Task.isCancelled, taskTokens[query] == token else { return }
            if restoreInFlight { touchedQueries.insert(query) }
            onStateChange()

            let fingerprintWorker = Task.detached(priority: .utility) {
                fingerprintProvider()
            }
            let fingerprint = await withTaskCancellationHandler {
                await fingerprintWorker.value
            } onCancel: { fingerprintWorker.cancel() }
            guard !Task.isCancelled, taskTokens[query] == token else { onStateChange(); return }

            if !force,
               var entry = entries[query],
               let summary = entry.summary,
               entry.lastError == nil,
               entry.sourceFingerprint == fingerprint,
               nowProvider().timeIntervalSince(entry.refreshedAt) < maximumLoadAge(for: query),
               isSummaryTemporallyFresh(summary, now: nowProvider()) {
                let validatedAt = nowProvider()
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

            let loaderWorker = Task.detached(priority: .utility) {
                do {
                    try Task.checkCancellation()
                    let result: LocalUsageHistoryLoadResult
                    if let asyncLoader { result = try await asyncLoader(fingerprint) }
                    else { result = try loader(fingerprint) }
                    try Task.checkCancellation()
                    return Result<LocalUsageHistoryLoadResult, Error>.success(result)
                } catch { return Result<LocalUsageHistoryLoadResult, Error>.failure(error) }
            }
            let result = await withTaskCancellationHandler {
                await loaderWorker.value
            } onCancel: { loaderWorker.cancel() }
            guard !Task.isCancelled, taskTokens[query] == token else { onStateChange(); return }

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
                    isStaleFallback: false,
                    lastAttemptAt: refreshedAt
                )
            case .failure(let error):
                if var existing = entries[query], existing.summary != nil {
                    existing.lastAttemptAt = refreshedAt
                    existing.retryNotBefore = refreshedAt.addingTimeInterval(30)
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
                        isStaleFallback: false,
                        lastAttemptAt: refreshedAt,
                        retryNotBefore: refreshedAt.addingTimeInterval(30)
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
        restoreRevision += 1
        let revision = restoreRevision
        restoreInFlight = true
        if !asynchronousIO {
            mergeRestored(io.restore())
            touchedQueries.removeAll(keepingCapacity: false)
            restoreInFlight = false
            return
        }
        restoreTask = Task { @MainActor [weak self, io] in
            let restored = await withCheckedContinuation { continuation in
                io.queue.async { continuation.resume(returning: io.restore()) }
            }
            guard let self, self.restoreRevision == revision else { return }
            self.mergeRestored(restored)
            self.touchedQueries.removeAll(keepingCapacity: false)
            self.restoreInFlight = false
        }
    }

    private func mergeRestored(_ restored: [LocalUsageHistoryEntry]) {
        for entry in restored where !touchedQueries.contains(entry.query) && !removedProvidersDuringRestore.contains(entry.query.providerID) {
            if let existing = entries[entry.query], existing.refreshedAt >= entry.refreshedAt { continue }
            entries[entry.query] = entry
        }
        prune(now: nowProvider())
        if !removedProvidersDuringRestore.isEmpty {
            removedProvidersDuringRestore.removeAll(keepingCapacity: false)
            persist()
        }
        onRestore?()
    }

    func persist() {
        let snapshot = sortedEntries()
        if asynchronousIO {
            io.enqueue(snapshot)
        } else {
            io.persist(snapshot)
        }
    }

    func cancelRefresh(for query: LocalUsageHistoryQuery) {
        loadingTasks.removeValue(forKey: query)?.cancel()
        taskTokens.removeValue(forKey: query)
    }

    func cancelAllRefreshes() {
        for task in loadingTasks.values { task.cancel() }
        loadingTasks.removeAll(keepingCapacity: false)
        taskTokens.removeAll(keepingCapacity: false)
    }

    func removeEntries(providerID: String) {
        if restoreInFlight { removedProvidersDuringRestore.insert(providerID) }
        for query in Array(loadingTasks.keys) where query.providerID == providerID { cancelRefresh(for: query) }
        entries = entries.filter { $0.key.providerID != providerID }
        touchedQueries = touchedQueries.filter { $0.providerID != providerID }
        // Persist only after the pending restore merges unrelated providers.
        if !restoreInFlight { persist() }
    }

    func reset() {
        restoreRevision += 1
        restoreInFlight = false
        removedProvidersDuringRestore.removeAll(keepingCapacity: false)
        cancelAllRefreshes()
        entries.removeAll(keepingCapacity: false)
        touchedQueries.removeAll(keepingCapacity: false)
        persist()
    }

    func shutdown() async {
        cancelAllRefreshes()
        await flushPersistence()
    }

    /// Await this at orderly shutdown/tests; abrupt termination can lose queued cache writes.
    func flushPersistence() async {
        guard asynchronousIO else { return }
        await restoreTask?.value
        await withCheckedContinuation { continuation in
            io.queue.async { continuation.resume() }
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
                    return sortKey(lhs.query) < sortKey(rhs.query)
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
            return sortKey(lhs.query) < sortKey(rhs.query)
        }
    }

    private func sortKey(_ query: LocalUsageHistoryQuery) -> String {
        [query.providerType.rawValue, query.providerID, query.scope.rawValue, query.identityKey].joined(separator: "\u{0}")
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

    private func maximumLoadAge(for query: LocalUsageHistoryQuery) -> TimeInterval {
        query.providerType == .cursor ? 60 : 30 * 60
    }

    private func isSummaryTemporallyFresh(_ summary: LocalUsageSummary, now: Date) -> Bool {
        Calendar.current.isDate(summary.generatedAt, equalTo: now, toGranularity: .hour)
    }

}

private final class LocalUsageHistoryCacheIO: @unchecked Sendable {
    struct Payload: Codable {
        var schemaVersion: Int? = 2
        var entries: [LocalUsageHistoryEntry]
    }

    let queue = DispatchQueue(label: "OhMyUsage.localUsageHistory.cache", qos: .utility)
    private let fileURL: URL
    private let fileManager: FileManager
    private let beforeRead: @Sendable () -> Void
    private let diagnostic: @Sendable (String) -> Void
    private var lastPersistedEntries: [LocalUsageHistoryEntry]?
    private let pendingLock = NSLock()
    private var pending: [LocalUsageHistoryEntry]?
    private var writeScheduled = false
    // 24 slimmed entries fit well below this budget, including model breakdowns.
    static let maximumBytes = 16 * 1024 * 1024

    init(fileURL: URL, fileManager: FileManager,
         beforeRead: @escaping @Sendable () -> Void, diagnostic: @escaping @Sendable (String) -> Void) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.beforeRead = beforeRead
        self.diagnostic = diagnostic
    }

    func enqueue(_ entries: [LocalUsageHistoryEntry]) {
        pendingLock.lock()
        pending = entries
        let schedule = !writeScheduled
        writeScheduled = true
        pendingLock.unlock()
        guard schedule else { return }
        queue.async { [self] in
            while true {
                pendingLock.lock()
                guard let snapshot = pending else {
                    writeScheduled = false
                    pendingLock.unlock()
                    return
                }
                pending = nil
                pendingLock.unlock()
                persist(snapshot)
            }
        }
    }

    func restore() -> [LocalUsageHistoryEntry] {
        beforeRead()
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumBytes + 1), data.count <= Self.maximumBytes else {
            diagnostic("restoreSizeOrReadFailure")
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data),
              payload.schemaVersion == nil || payload.schemaVersion == 2 else {
            diagnostic("restoreSchemaOrDecodeFailure")
            return []
        }
        var restored: [LocalUsageHistoryQuery: LocalUsageHistoryEntry] = [:]
        for entry in payload.entries where Self.isValid(entry) {
            // First wins ties; newest successful refresh wins duplicate keys.
            if let old = restored[entry.query], old.refreshedAt >= entry.refreshedAt { continue }
            restored[entry.query] = entry
        }
        if restored.count < payload.entries.count { diagnostic("restoreDiscardedEntries") }
        return Array(restored.values)
    }

    func persist(_ entries: [LocalUsageHistoryEntry]) {
        guard entries != lastPersistedEntries || !fileManager.fileExists(atPath: fileURL.path) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(Payload(entries: entries))
            guard data.count <= Self.maximumBytes else { return }
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lastPersistedEntries = entries
        } catch {
            diagnostic("persistFailure")
            // This reconstructible display cache never invalidates the in-memory result.
            return
        }
    }

    private static func isValid(_ entry: LocalUsageHistoryEntry) -> Bool {
        guard !entry.query.providerID.isEmpty, !entry.query.identityKey.isEmpty,
              entry.refreshedAt.timeIntervalSinceReferenceDate.isFinite,
              entry.sourceFingerprint.map({ $0.fileCount >= 0 && $0.roots.count <= 1024 }) ?? true else { return false }
        guard let summary = entry.summary else { return true }
        let periods = [summary.today, summary.yesterday, summary.last30Days]
        return summary.generatedAt.timeIntervalSinceReferenceDate.isFinite &&
            periods.allSatisfy {
                $0.totalTokens >= 0 && $0.responses >= 0 && $0.inputTokens >= 0 && $0.outputTokens >= 0 &&
                $0.cacheReadTokens >= 0 && $0.cacheWriteTokens >= 0 && $0.byModel.count <= 1024 &&
                $0.byModel.allSatisfy { $0.totalTokens >= 0 && $0.responses >= 0 }
            } &&
            summary.hourly24.count <= 48 && summary.daily7.count <= 32 &&
            (summary.hourly24 + summary.daily7).allSatisfy { $0.totalTokens >= 0 && $0.responses >= 0 }
    }
}
