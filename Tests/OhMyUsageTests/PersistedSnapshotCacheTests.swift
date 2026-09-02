import OhMyUsageDomain
import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class PersistedSnapshotCacheTests: XCTestCase {
    // MARK: - Helpers

    private func makeTemporaryCacheDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        // Unique temp directories are intentionally left behind (existing repo
        // test practice); XCTest teardown blocks cannot capture self under
        // strict concurrency.
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OhMyUsageSnapshotCacheTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeCache(
        fileManager: FileManager = .default,
        directory: URL
    ) -> PersistedSnapshotCache {
        PersistedSnapshotCache(
            fileManager: fileManager,
            fileURL: directory.appendingPathComponent("provider_snapshots.json")
        )
    }

    private static func makeSnapshot(
        source: String,
        remaining: Double? = 42,
        used: Double? = 8,
        limit: Double? = 50,
        rawMeta: [String: String] = [:],
        extras: [String: String] = [:],
        note: String = "ok",
        quotaWindows: [UsageQuotaWindow] = [],
        updatedAt: Date = Date()
    ) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: remaining,
            used: used,
            limit: limit,
            unit: "%",
            updatedAt: updatedAt,
            note: note,
            quotaWindows: quotaWindows,
            sourceLabel: "Test Source",
            authSourceLabel: "OAuth",
            extras: extras,
            rawMeta: rawMeta
        )
    }

    private static func makeWindow(id: String, title: String = "5h") -> UsageQuotaWindow {
        UsageQuotaWindow(
            id: id,
            title: title,
            remainingPercent: 61,
            usedPercent: 39,
            resetAt: Date(timeIntervalSince1970: 1_800_000_000),
            kind: .session,
            resetSource: .official,
            observedAt: Date(timeIntervalSince1970: 1_799_000_000),
            serverClockSkew: 1.5,
            confidence: .confirmed,
            windowIdentity: "session:1800000000"
        )
    }

    // MARK: - Cold start restore

    func testSaveAndColdStartRestoreRoundTripsWhitelistedFields() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        let updatedAt = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = Self.makeSnapshot(
            source: "codex-official",
            rawMeta: ["codex.identityKey": "identity-alpha"],
            quotaWindows: [Self.makeWindow(id: "w1")],
            updatedAt: updatedAt
        )

        cache.save(providerID: "codex-official", snapshot: snapshot)

        // Simulate a cold start with a fresh cache instance over the same file.
        let reloaded = makeCache(directory: directory)
        let restored = reloaded.loadLatestSnapshots()
        guard let entry = restored["codex-official"] else {
            return XCTFail("Expected a restored cache entry for codex-official")
        }
        let restoredSnapshot = entry.restoredSnapshot
        XCTAssertEqual(restoredSnapshot.source, "codex-official")
        XCTAssertEqual(restoredSnapshot.remaining, 42)
        XCTAssertEqual(restoredSnapshot.used, 8)
        XCTAssertEqual(restoredSnapshot.limit, 50)
        XCTAssertEqual(restoredSnapshot.unit, "%")
        XCTAssertEqual(restoredSnapshot.updatedAt, updatedAt)
        XCTAssertEqual(restoredSnapshot.sourceLabel, "Test Source")
        XCTAssertEqual(restoredSnapshot.authSourceLabel, "OAuth")
        XCTAssertEqual(restoredSnapshot.fetchHealth, .ok)
        XCTAssertEqual(restoredSnapshot.valueFreshness, .cachedFallback, "Restored values must be marked as cache fallback")
        XCTAssertEqual(restoredSnapshot.quotaWindows.count, 1)
        XCTAssertEqual(restoredSnapshot.quotaWindows.first?.title, "5h")
        XCTAssertEqual(restoredSnapshot.quotaWindows.first?.resetSource, .official)
        XCTAssertEqual(restoredSnapshot.quotaWindows.first?.confidence, .confirmed)
        XCTAssertEqual(restoredSnapshot.quotaWindows.first?.resetAt, Self.makeWindow(id: "w1").resetAt)
    }

    func testLoadReturnsEmptyWhenFileIsMissing() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        XCTAssertTrue(cache.loadAll().isEmpty)
        XCTAssertTrue(cache.loadLatestSnapshots().isEmpty)
    }

    // MARK: - Corrupt / incompatible files

    func testLoadSafelyIgnoresCorruptCacheFile() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        cache.save(providerID: "provider", snapshot: Self.makeSnapshot(source: "provider"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.fileLocation.path))

        try "not-json{{{ corruption".write(to: cache.fileLocation, atomically: true, encoding: .utf8)

        XCTAssertTrue(cache.loadAll().isEmpty, "Corrupt cache file must be ignored, not crash")
        XCTAssertTrue(cache.loadLatestSnapshots().isEmpty)

        // The cache stays usable: a later save recovers the file.
        cache.save(providerID: "provider", snapshot: Self.makeSnapshot(source: "provider", remaining: 7))
        XCTAssertEqual(cache.loadAll().first?.payload.remaining, 7)
    }

    func testLoadSafelyIgnoresIncompatibleSchemaVersion() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        cache.save(providerID: "provider", snapshot: Self.makeSnapshot(source: "provider"))

        let incompatible = try JSONSerialization.data(
            withJSONObject: ["schemaVersion": PersistedSnapshotCache.currentSchemaVersion + 1, "entries": []]
        )
        try incompatible.write(to: cache.fileLocation, options: .atomic)

        XCTAssertTrue(cache.loadAll().isEmpty, "Incompatible schema versions must be ignored, not crash")

        // The cache stays usable and rewrites with the current schema.
        cache.save(providerID: "provider", snapshot: Self.makeSnapshot(source: "provider", remaining: 9))
        XCTAssertEqual(cache.loadAll().first?.payload.remaining, 9)
        let probeDecoder = JSONDecoder()
        probeDecoder.dateDecodingStrategy = .iso8601
        let reloaded = try probeDecoder.decode(
            PersistedSnapshotCacheEnvelopeProbe.self,
            from: Data(contentsOf: cache.fileLocation)
        )
        XCTAssertEqual(reloaded.schemaVersion, PersistedSnapshotCache.currentSchemaVersion)
    }

    func testLoadSafelyIgnoresUndecodableEntryPayloads() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        let brokenPayload = """
        {"schemaVersion":\(PersistedSnapshotCache.currentSchemaVersion),"entries":[{"providerID":"p","accountFingerprint":"f","savedAt":"not-a-date","payload":{}}]}
        """
        try brokenPayload.write(to: cache.fileLocation, atomically: true, encoding: .utf8)
        XCTAssertTrue(cache.loadAll().isEmpty)
    }

    // MARK: - Credential safety

    func testCacheFileNeverContainsCredentialMaterial() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        let accessToken = "sk-ant-super-secret-access-token-1234567890"
        let refreshToken = "super-secret-refresh-token-abcdef"
        let cookieHeader = "sessionKey=do-not-persist-me; Path=/"
        let snapshot = Self.makeSnapshot(
            source: "codex-official",
            rawMeta: [
                "codex.identityKey": "identity-alpha",
                "access_token": accessToken,
                "refresh_token": refreshToken,
                "oauth": "{\"access_token\":\"\(accessToken)\"}"
            ],
            extras: ["Cookie": cookieHeader, "Authorization": "Bearer \(accessToken)"],
            note: "raw log line: sessionKey=leak-attempt access_token=leak-attempt"
        )

        cache.save(providerID: "codex-official", snapshot: snapshot)

        let rawFileContents = try String(contentsOf: cache.fileLocation, encoding: .utf8)
        XCTAssertFalse(rawFileContents.contains(accessToken), "Cache file must not contain access tokens")
        XCTAssertFalse(rawFileContents.contains(refreshToken), "Cache file must not contain refresh tokens")
        XCTAssertFalse(rawFileContents.contains(cookieHeader), "Cache file must not contain cookie headers")
        XCTAssertFalse(rawFileContents.contains("access_token"), "Cache file must not contain OAuth JSON field names")
        XCTAssertFalse(rawFileContents.contains("refresh_token"))
        XCTAssertFalse(rawFileContents.contains("sessionKey"))
        XCTAssertFalse(rawFileContents.contains("leak-attempt"), "Snapshot notes/raw logs must not be persisted")
        XCTAssertFalse(rawFileContents.contains("Bearer "), "Auth headers must not be persisted")
    }

    // MARK: - Cache keys and account identity

    func testCacheKeySeparatesAccountsForSameProvider() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        let accountA = Self.makeSnapshot(source: "codex-official", remaining: 10, rawMeta: ["codex.identityKey": "identity-a"])
        let accountB = Self.makeSnapshot(source: "codex-official", remaining: 90, rawMeta: ["codex.identityKey": "identity-b"])

        cache.save(providerID: "codex-official", snapshot: accountA, savedAt: Date(timeIntervalSince1970: 100))
        cache.save(providerID: "codex-official", snapshot: accountB, savedAt: Date(timeIntervalSince1970: 200))

        let entries = cache.loadAll()
        XCTAssertEqual(entries.count, 2, "Each provider/account keeps its own main snapshot")
        XCTAssertEqual(Set(entries.map(\.accountFingerprint)).count, 2, "Different accounts must not share a fingerprint")

        // Cold start cannot safely infer which account is current.
        let latest = cache.loadLatestSnapshots()
        XCTAssertNil(latest["codex-official"])
    }

    func testRemoveProviderClearsOnlyThatProvidersAccounts() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        cache.save(providerID: "first", snapshot: Self.makeSnapshot(source: "first", rawMeta: ["codex.identityKey": "a"]))
        cache.save(providerID: "first", snapshot: Self.makeSnapshot(source: "first", rawMeta: ["codex.identityKey": "b"]))
        cache.save(providerID: "second", snapshot: Self.makeSnapshot(source: "second"))

        cache.remove(providerID: "first")

        XCTAssertFalse(cache.loadAll().contains { $0.providerID == "first" })
        XCTAssertEqual(cache.loadAll().map(\.providerID), ["second"])
    }

    func testInvalidationGenerationRejectsQueuedStaleWrite() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        let staleGeneration = cache.currentGeneration(for: "provider")

        cache.remove(providerID: "provider")
        cache.save(
            providerID: "provider",
            snapshot: Self.makeSnapshot(source: "provider"),
            expectedGeneration: staleGeneration
        )

        XCTAssertTrue(cache.loadAll().isEmpty)
    }

    func testUpsertReplacesMainSnapshotForSameProviderAndAccount() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        let first = Self.makeSnapshot(source: "relay", remaining: 10, rawMeta: ["codex.identityKey": "identity-a"])
        let second = Self.makeSnapshot(source: "relay", remaining: 20, rawMeta: ["codex.identityKey": "identity-a"])

        cache.save(providerID: "relay", snapshot: first, savedAt: Date(timeIntervalSince1970: 100))
        cache.save(providerID: "relay", snapshot: second, savedAt: Date(timeIntervalSince1970: 200))

        let entries = cache.loadAll()
        XCTAssertEqual(entries.count, 1, "One main snapshot per provider/account")
        XCTAssertEqual(entries.first?.payload.remaining, 20)
    }

    func testAccountFingerprintIsStableIrreversibleAndDefaultsSafely() {
        let identifiable = Self.makeSnapshot(source: "claude-official", rawMeta: ["claude.accountId": "acct_1234567890"])
        let fingerprint = PersistedSnapshotCache.accountFingerprint(for: identifiable)

        XCTAssertEqual(fingerprint, PersistedSnapshotCache.accountFingerprint(for: identifiable), "Fingerprint must be stable")
        XCTAssertFalse(fingerprint.contains("acct_1234567890"), "Fingerprint must not contain the raw account id")
        XCTAssertEqual(fingerprint.count, 32, "SHA-256 prefix is 16 bytes, hex encoded")

        let differentAccount = Self.makeSnapshot(source: "claude-official", rawMeta: ["claude.accountId": "acct_0987654321"])
        XCTAssertNotEqual(fingerprint, PersistedSnapshotCache.accountFingerprint(for: differentAccount))

        let anonymous = Self.makeSnapshot(source: "relay", rawMeta: [:])
        XCTAssertEqual(
            PersistedSnapshotCache.accountFingerprint(for: anonymous),
            PersistedSnapshotCache.fingerprint(from: "default"),
            "Providers without identity metadata use the stable default fingerprint"
        )
    }

    // MARK: - Size limits

    func testEntryCountLimitDropsOldestEntries() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        let oldestProviderID = "provider-0"

        for index in 0..<PersistedSnapshotCache.maxEntryCount + 1 {
            let snapshot = Self.makeSnapshot(source: "provider-\(index)")
            cache.save(
                providerID: "provider-\(index)",
                snapshot: snapshot,
                savedAt: Date(timeIntervalSince1970: TimeInterval(1000 + index))
            )
        }

        let entries = cache.loadAll()
        XCTAssertEqual(entries.count, PersistedSnapshotCache.maxEntryCount)
        XCTAssertFalse(entries.contains { $0.providerID == oldestProviderID }, "Oldest entries are dropped first")
        XCTAssertTrue(entries.contains { $0.providerID == "provider-\(PersistedSnapshotCache.maxEntryCount)" })
    }

    func testFileSizeLimitTrimsOldestEntries() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        let oversizedTitle = String(repeating: "w", count: 220)

        for index in 0..<PersistedSnapshotCache.maxEntryCount {
            let window = Self.makeWindow(id: "window-\(index)", title: oversizedTitle)
            let snapshot = Self.makeSnapshot(
                source: "provider-\(index)",
                quotaWindows: Array(repeating: window, count: 30)
            )
            cache.save(
                providerID: "provider-\(index)",
                snapshot: snapshot,
                savedAt: Date(timeIntervalSince1970: TimeInterval(1000 + index))
            )
        }

        let fileSize = (try FileManager.default.attributesOfItem(atPath: cache.fileLocation.path)[.size] as? Int) ?? 0
        XCTAssertLessThanOrEqual(fileSize, PersistedSnapshotCache.maxEncodedFileBytes, "Cache file must stay size-bounded")
        let entries = cache.loadAll()
        XCTAssertLessThan(entries.count, PersistedSnapshotCache.maxEntryCount, "Oversized files trim down to fit")
        XCTAssertTrue(entries.contains { $0.providerID == "provider-\(PersistedSnapshotCache.maxEntryCount - 1)" }, "Newest entries survive trimming")
    }

    // MARK: - Directory and lifecycle

    func testSaveCreatesMissingDirectoryAtomically() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OhMyUsageSnapshotCacheTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = makeCache(directory: root)

        cache.save(providerID: "provider", snapshot: Self.makeSnapshot(source: "provider"))

        XCTAssertTrue(fileManager.fileExists(atPath: cache.fileLocation.path), "Missing cache directory must be created")
    }

    func testRemoveAllClearsPersistedEntries() throws {
        let directory = try makeTemporaryCacheDirectory()
        let cache = makeCache(directory: directory)
        cache.save(providerID: "provider", snapshot: Self.makeSnapshot(source: "provider"))
        XCTAssertEqual(cache.loadAll().count, 1)

        cache.removeAll()

        XCTAssertTrue(cache.loadAll().isEmpty)
    }
}

/// Test-only mirror of the on-disk envelope used to assert schema versioning.
private struct PersistedSnapshotCacheEnvelopeProbe: Codable {
    var schemaVersion: Int
    var entries: [PersistedSnapshotCacheEntry]
}

// MARK: - AppViewModel lifecycle integration (doc §8.2)

@MainActor
final class AppViewModelPersistedSnapshotCacheTests: XCTestCase {
    private func makeTemporaryCache() throws -> PersistedSnapshotCache {
        // Unique temp directories are intentionally left behind (existing repo
        // test practice); XCTest teardown blocks cannot capture self under
        // strict concurrency.
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OhMyUsageSnapshotCacheVMTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return PersistedSnapshotCache(
            fileManager: fileManager,
            fileURL: root.appendingPathComponent("provider_snapshots.json")
        )
    }

    private func makeRelayDescriptor(id: String) -> ProviderDescriptor {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Snapshot Cache Relay",
            baseURL: "https://snapshot-cache.test"
        )
        relay.id = id
        relay.enabled = true
        return relay
    }

    func testColdStartRestoresCachedSnapshotAsCachedFallback() async throws {
        let cache = try makeTemporaryCache()
        let descriptor = makeRelayDescriptor(id: "cold-start-relay")
        cache.save(
            providerID: descriptor.id,
            snapshot: UsageSnapshot(
                source: descriptor.id,
                status: .ok,
                remaining: 66,
                used: 34,
                limit: 100,
                unit: "%",
                updatedAt: Date(),
                note: "ok",
                sourceLabel: "Test"
            )
        )

        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [descriptor]),
            appUpdateService: SnapshotCacheNoopAppUpdateService(),
            providerFactory: SnapshotCacheProviderFactory(snapshotsByProviderID: [:])
        )
        viewModel.restorePersistedSnapshotsFromCache(cache)

        let restored = try XCTUnwrap(viewModel.snapshots[descriptor.id])
        XCTAssertEqual(restored.remaining, 66)
        XCTAssertEqual(restored.valueFreshness, .cachedFallback, "Restored values must be marked as cache fallback")
    }

    func testRestoreSkipsProvidersMissingFromCurrentConfig() async throws {
        let cache = try makeTemporaryCache()
        let descriptor = makeRelayDescriptor(id: "removed-relay")
        cache.save(
            providerID: descriptor.id,
            snapshot: UsageSnapshot(
                source: descriptor.id,
                status: .ok,
                remaining: 10,
                used: 90,
                limit: 100,
                unit: "%",
                updatedAt: Date(),
                note: "ok",
                sourceLabel: "Test"
            )
        )

        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: []),
            appUpdateService: SnapshotCacheNoopAppUpdateService(),
            providerFactory: SnapshotCacheProviderFactory(snapshotsByProviderID: [:])
        )
        viewModel.restorePersistedSnapshotsFromCache(cache)

        XCTAssertNil(viewModel.snapshots[descriptor.id], "Removed providers must not gain ghost snapshot state")
    }

    func testSuccessfulRefreshPersistsSnapshotAsynchronously() async throws {
        let cache = try makeTemporaryCache()
        let descriptor = makeRelayDescriptor(id: "persisting-relay")
        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [descriptor]),
            appUpdateService: SnapshotCacheNoopAppUpdateService(),
            providerFactory: SnapshotCacheProviderFactory(snapshotsByProviderID: [
                descriptor.id: UsageSnapshot(
                    source: descriptor.id,
                    status: .ok,
                    remaining: 81,
                    used: 19,
                    limit: 100,
                    unit: "%",
                    updatedAt: Date(),
                    note: "ok",
                    sourceLabel: "Test"
                )
            ]),
            persistedSnapshotCache: cache
        )

        await viewModel.refreshProvider(viewModel.config.providers[0], forceRefresh: true)

        let cacheFileURL = cache.fileLocation
        try await waitUntil(timeout: 3) {
            FileManager.default.fileExists(atPath: cacheFileURL.path)
                && cache.loadLatestSnapshots()[descriptor.id]?.payload.remaining == 81
        }
        let entry = try XCTUnwrap(cache.loadLatestSnapshots()[descriptor.id])
        XCTAssertEqual(entry.payload.valueFreshness, .live)
        XCTAssertEqual(viewModel.snapshots[descriptor.id]?.remaining, 81)
    }

    func testResetLocalAppDataClearsPersistedSnapshots() throws {
        let cache = try makeTemporaryCache()
        let descriptor = makeRelayDescriptor(id: "reset-relay")
        cache.save(
            providerID: descriptor.id,
            snapshot: UsageSnapshot(
                source: descriptor.id,
                status: .ok,
                remaining: 55,
                used: 45,
                limit: 100,
                unit: "%",
                updatedAt: Date(),
                note: "ok",
                sourceLabel: "Test"
            )
        )
        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [descriptor]),
            appUpdateService: SnapshotCacheNoopAppUpdateService(),
            providerFactory: SnapshotCacheProviderFactory(snapshotsByProviderID: [:]),
            persistedSnapshotCache: cache
        )
        defer { viewModel.providerRefreshModel.stopPolling() }
        XCTAssertEqual(cache.loadAll().count, 1)

        viewModel.resetLocalAppData()

        XCTAssertTrue(cache.loadAll().isEmpty)
    }

    private func waitUntil(
        timeout: TimeInterval,
        predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for persisted snapshot cache")
    }
}

private actor SnapshotCacheNoopAppUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw ProviderError.unavailable("unused")
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw ProviderError.unavailable("unused")
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {
    }
}

private struct SnapshotCacheProviderFactory: ProviderFactorying {
    let snapshotsByProviderID: [String: UsageSnapshot]

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        SnapshotCacheUsageProvider(
            descriptor: descriptor,
            snapshot: snapshotsByProviderID[descriptor.id]
        )
    }
}

private struct SnapshotCacheUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot?

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        guard let snapshot else {
            throw ProviderError.timeout("simulated timeout")
        }
        return snapshot
    }
}
