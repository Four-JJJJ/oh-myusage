import Foundation
import XCTest
import OhMyUsageApplication
@testable import OhMyUsage

@MainActor
final class LocalUsageHistoryRepositoryTests: XCTestCase {
    func testPersistAndRestoreKeepsCachedSummary() async throws {
        let root = try makeTemporaryRoot()
        let now = LockedDate(Date(timeIntervalSince1970: 5_000))
        let query = makeQuery(identityKey: "persisted")
        let fingerprint = LocalUsageSourceFingerprint(
            roots: ["/tmp/source"],
            fileCount: 1,
            totalSize: 12,
            latestModificationTime: Date(timeIntervalSince1970: 100)
        )
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: root,
            nowProvider: { now.value },
            asynchronousIO: false
        )

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 1),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )

        try await waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 101 && !$0.isLoading
        }

        let restored = LocalUsageHistoryRepository(
            baseDirectoryURL: root,
            nowProvider: { now.value },
            asynchronousIO: false
        )
        let state = restored.snapshot(for: query)
        XCTAssertEqual(state.summary?.today.totalTokens, 101)
        XCTAssertEqual(state.sourceFingerprint, fingerprint)
        XCTAssertEqual(state.lastFingerprintCheckedAt, now.value)
        XCTAssertFalse(state.isStaleFallback)
    }

    func testPersistWritesCompactJSONPayload() async throws {
        let root = try makeTemporaryRoot()
        let now = LockedDate(Date(timeIntervalSince1970: 5_100))
        let query = makeQuery(identityKey: "compact")
        let fingerprint = LocalUsageSourceFingerprint(
            roots: ["/tmp/source"],
            fileCount: 1,
            totalSize: 12,
            latestModificationTime: Date(timeIntervalSince1970: 100)
        )
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: root,
            nowProvider: { now.value },
            asynchronousIO: false
        )

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 11, generatedAt: now.value),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 111 && !$0.isLoading
        }

        let payload = try String(contentsOf: localUsageCacheURL(root: root), encoding: .utf8)
        XCTAssertFalse(payload.contains("\n"), "local usage cache should be compact JSON without pretty-print newlines")
        XCTAssertFalse(payload.contains("  "), "local usage cache should avoid pretty-print indentation")
    }

    func testPersistSkipsUnchangedPayloadWrite() async throws {
        let root = try makeTemporaryRoot()
        let now = LockedDate(Date(timeIntervalSince1970: 5_200))
        let query = makeQuery(identityKey: "unchanged-persist")
        let fingerprint = LocalUsageSourceFingerprint(
            roots: ["/tmp/source"],
            fileCount: 1,
            totalSize: 12,
            latestModificationTime: Date(timeIntervalSince1970: 100)
        )
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: root,
            nowProvider: { now.value },
            asynchronousIO: false
        )

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 12, generatedAt: now.value),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 112 && !$0.isLoading
        }

        let cacheURL = localUsageCacheURL(root: root)
        let firstModifiedAt = try modificationDate(at: cacheURL)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        repository.persist()
        let secondModifiedAt = try modificationDate(at: cacheURL)

        XCTAssertEqual(firstModifiedAt, secondModifiedAt)
    }

    func testUnchangedFingerprintReusesCacheWithoutCallingLoader() async throws {
        let root = try makeTemporaryRoot()
        let now = LockedDate(Date(timeIntervalSince1970: 1_000))
        let query = makeQuery(identityKey: "fingerprint")
        let fingerprint = LocalUsageSourceFingerprint(
            roots: ["/tmp/source"],
            fileCount: 1,
            totalSize: 20,
            latestModificationTime: Date(timeIntervalSince1970: 100)
        )
        let loaderCalls = LockedCounter()
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: root,
            nowProvider: { now.value },
            asynchronousIO: false
        )

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                loaderCalls.increment()
                return LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 2, generatedAt: now.value),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 102 && !$0.isLoading
        }

        now.value = Date(timeIntervalSince1970: 1_000 + RuntimeDiagnosticsLimits.localUsageTrendCacheEntryTTL + 5)
        repository.refreshIfNeeded(
            query: query,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                loaderCalls.increment()
                return LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 99),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            !$0.isLoading
        }

        let state = repository.snapshot(for: query)
        XCTAssertEqual(loaderCalls.value, 1)
        XCTAssertEqual(state.summary?.today.totalTokens, 102)
        XCTAssertFalse(state.isStaleFallback)
    }

    func testFreshCacheProbesFingerprintAfterProbeIntervalWithoutLoaderWhenUnchanged() async throws {
        let root = try makeTemporaryRoot()
        let now = LockedDate(Date(timeIntervalSince1970: 10_000))
        let query = makeQuery(identityKey: "probe")
        let fingerprint = LocalUsageSourceFingerprint(
            roots: ["/tmp/source"],
            fileCount: 1,
            totalSize: 20,
            latestModificationTime: Date(timeIntervalSince1970: 100)
        )
        let fingerprintCalls = LockedCounter()
        let loaderCalls = LockedCounter()
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: root,
            nowProvider: { now.value },
            asynchronousIO: false
        )

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: {
                fingerprintCalls.increment()
                return fingerprint
            },
            loader: { _ in
                loaderCalls.increment()
                return LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 5, generatedAt: now.value),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 105 && !$0.isLoading
        }

        now.value = now.value.addingTimeInterval(RuntimeDiagnosticsLimits.localUsageTrendFingerprintProbeInterval + 1)
        repository.refreshIfNeeded(
            query: query,
            fingerprintProvider: {
                fingerprintCalls.increment()
                return fingerprint
            },
            loader: { _ in
                loaderCalls.increment()
                return LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 50, generatedAt: now.value),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            $0.lastFingerprintCheckedAt == now.value && !$0.isLoading
        }

        let state = repository.snapshot(for: query)
        XCTAssertEqual(fingerprintCalls.value, 2)
        XCTAssertEqual(loaderCalls.value, 1)
        XCTAssertEqual(state.summary?.today.totalTokens, 105)
        XCTAssertEqual(state.lastFingerprintCheckedAt, now.value)
    }

    func testTemporalBoundaryForcesReloadEvenWhenFingerprintUnchanged() async throws {
        let root = try makeTemporaryRoot()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let initialNow = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 6,
            hour: 10,
            minute: 58
        )))
        let nextHourNow = try XCTUnwrap(calendar.date(byAdding: .minute, value: 3, to: initialNow))
        let now = LockedDate(initialNow)
        let query = makeQuery(identityKey: "hour-boundary")
        let fingerprint = LocalUsageSourceFingerprint(
            roots: ["/tmp/source"],
            fileCount: 1,
            totalSize: 20,
            latestModificationTime: Date(timeIntervalSince1970: 100)
        )
        let loaderCalls = LockedCounter()
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: root,
            nowProvider: { now.value },
            asynchronousIO: false
        )

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                loaderCalls.increment()
                return LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 6, generatedAt: now.value),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 106 && !$0.isLoading
        }

        now.value = nextHourNow
        repository.refreshIfNeeded(
            query: query,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                loaderCalls.increment()
                return LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 60, generatedAt: now.value),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 160 && !$0.isLoading
        }

        XCTAssertEqual(loaderCalls.value, 2)
    }

    func testFailureKeepsOldCacheAsStaleFallback() async throws {
        let root = try makeTemporaryRoot()
        let query = makeQuery(identityKey: "fallback")
        let fingerprint = LocalUsageSourceFingerprint(
            roots: ["/tmp/source"],
            fileCount: 1,
            totalSize: 20,
            latestModificationTime: Date(timeIntervalSince1970: 100)
        )
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root, asynchronousIO: false)

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 3),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 103 && !$0.isLoading
        }

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                throw SampleError.refreshFailed
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) {
            $0.isStaleFallback && !$0.isLoading
        }

        let state = repository.snapshot(for: query)
        XCTAssertEqual(state.summary?.today.totalTokens, 103)
        XCTAssertEqual(state.error, SampleError.refreshFailed.localizedDescription)
        XCTAssertTrue(state.isStaleFallback)
    }

    func testPruneLimitsCacheCapacityByFreshness() async throws {
        let root = try makeTemporaryRoot()
        let now = LockedDate(Date(timeIntervalSince1970: 2_000))
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: root,
            nowProvider: { now.value },
            asynchronousIO: false
        )
        let fingerprint = LocalUsageSourceFingerprint(
            roots: ["/tmp/source"],
            fileCount: 1,
            totalSize: 20,
            latestModificationTime: Date(timeIntervalSince1970: 100)
        )
        var queries: [LocalUsageHistoryQuery] = []

        for index in 0..<(RuntimeDiagnosticsLimits.localUsageTrendCacheMaxEntries + 2) {
            now.value = Date(timeIntervalSince1970: 2_000 + TimeInterval(index))
            let query = makeQuery(identityKey: "capacity-\(index)")
            queries.append(query)
            repository.refreshIfNeeded(
                query: query,
                force: true,
                fingerprintProvider: { fingerprint },
                loader: { _ in
                    LocalUsageHistoryLoadResult(
                        summary: Self.sampleSummary(seed: index),
                        sourceFingerprint: fingerprint
                    )
                },
                onStateChange: {}
            )
            try await waitUntil(repository: repository, query: query) {
                $0.summary?.today.totalTokens == 100 + index && !$0.isLoading
            }
        }

        XCTAssertNil(repository.snapshot(for: queries[0]).lastRefreshedAt)
        XCTAssertNil(repository.snapshot(for: queries[1]).lastRefreshedAt)
        XCTAssertEqual(repository.snapshot(for: queries[2]).summary?.today.totalTokens, 102)
        XCTAssertEqual(repository.snapshot(for: queries.last!).summary?.today.totalTokens, 125)
    }

    func testRefreshDeduplicatesConcurrentSameQueryWork() async throws {
        let root = try makeTemporaryRoot()
        let query = makeQuery(identityKey: "dedupe")
        let fingerprint = LocalUsageSourceFingerprint(
            roots: ["/tmp/source"],
            fileCount: 1,
            totalSize: 20,
            latestModificationTime: Date(timeIntervalSince1970: 100)
        )
        let loaderCalls = LockedCounter()
        let release = DispatchSemaphore(value: 0)
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root, asynchronousIO: false)

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                loaderCalls.increment()
                _ = release.wait(timeout: .now() + 2)
                return LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 4),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await waitUntil(repository: repository, query: query) { state in
            state.isLoading && loaderCalls.value == 1
        }
        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                loaderCalls.increment()
                return LocalUsageHistoryLoadResult(
                    summary: Self.sampleSummary(seed: 40),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )

        release.signal()
        try await waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 104 && !$0.isLoading
        }
        XCTAssertEqual(loaderCalls.value, 1)
    }

    func testDuplicateLegacyEntriesRestoreNewestWithoutTrapping() throws {
        let root = try makeTemporaryRoot()
        let query = makeQuery(identityKey: "duplicate")
        let older = LocalUsageHistoryEntry(query: query, summary: Self.sampleSummary(seed: 1),
            refreshedAt: Date(timeIntervalSince1970: 100), sourceFingerprint: nil,
            lastFingerprintCheckedAt: nil, lastError: nil, isStaleFallback: false)
        var newer = older
        newer.refreshedAt = Date(timeIntervalSince1970: 200)
        newer.summary = Self.sampleSummary(seed: 2)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([older, newer, older])
        try writeCache(Data("{\"entries\":".utf8) + data + Data("}".utf8), root: root)
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root, asynchronousIO: false)
        XCTAssertEqual(repository.snapshot(for: query).summary?.today.totalTokens, 102)
    }

    func testUnknownSchemaCorruptAndOversizeCachesAreIgnored() throws {
        let root = try makeTemporaryRoot()
        let query = makeQuery(identityKey: "invalid")
        for data in [Data("{\"schemaVersion\":999,\"entries\":[]}".utf8),
                     Data("{\"entries\":".utf8), Data(repeating: 32, count: 16 * 1024 * 1024 + 1)] {
            try writeCache(data, root: root)
            let repository = LocalUsageHistoryRepository(baseDirectoryURL: root, asynchronousIO: false)
            XCTAssertNil(repository.snapshot(for: query).summary)
        }
    }

    func testFailureDoesNotAdvanceSuccessfulLoadOrValidateItHealthy() async throws {
        let root = try makeTemporaryRoot()
        let now = LockedDate(Date(timeIntervalSince1970: 10_000))
        let query = makeQuery(identityKey: "failure-time")
        let fingerprint = LocalUsageSourceFingerprint(roots: [], fileCount: 0, totalSize: 0, latestModificationTime: nil)
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root, nowProvider: { now.value }, asynchronousIO: false)
        repository.refreshIfNeeded(query: query, force: true, fingerprintProvider: { fingerprint }, loader: { _ in
            LocalUsageHistoryLoadResult(summary: Self.sampleSummary(seed: 1, generatedAt: now.value), sourceFingerprint: fingerprint)
        }, onStateChange: {})
        try await waitUntil(repository: repository, query: query) { $0.summary != nil && !$0.isLoading }
        let successAt = repository.snapshot(for: query).lastRefreshedAt
        now.value = now.value.addingTimeInterval(10)
        repository.refreshIfNeeded(query: query, force: true, fingerprintProvider: { fingerprint }, loader: { _ in
            throw SampleError.refreshFailed
        }, onStateChange: {})
        try await waitUntil(repository: repository, query: query) { $0.isStaleFallback && !$0.isLoading }
        XCTAssertEqual(repository.snapshot(for: query).lastRefreshedAt, successAt)
        now.value = now.value.addingTimeInterval(31)
        let calls = LockedCounter()
        repository.refreshIfNeeded(query: query, fingerprintProvider: { fingerprint }, loader: { _ in
            calls.increment()
            throw SampleError.refreshFailed
        }, onStateChange: {})
        try await waitUntil(repository: repository, query: query) { !$0.isLoading }
        XCTAssertEqual(calls.value, 1)
        XCTAssertTrue(repository.snapshot(for: query).isStaleFallback)
    }

    func testAsyncRestoreNeverOverwritesFreshResultAndOrderedWritesRoundTrip() async throws {
        let root = try makeTemporaryRoot()
        let query = makeQuery(identityKey: "async-race")
        let fingerprint = LocalUsageSourceFingerprint(roots: [], fileCount: 0, totalSize: 0, latestModificationTime: nil)
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root)
        for seed in [1, 2] {
            repository.refreshIfNeeded(query: query, force: true, fingerprintProvider: { fingerprint }, loader: { _ in
                LocalUsageHistoryLoadResult(summary: Self.sampleSummary(seed: seed), sourceFingerprint: fingerprint)
            }, onStateChange: {})
            try await waitUntil(repository: repository, query: query) { $0.summary?.today.totalTokens == 100 + seed && !$0.isLoading }
        }
        await repository.flushPersistence()
        repository.restoreFromDisk()
        await repository.flushPersistence()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(repository.snapshot(for: query).summary?.today.totalTokens, 102)
        let restored = LocalUsageHistoryRepository(baseDirectoryURL: root, asynchronousIO: false)
        XCTAssertEqual(restored.snapshot(for: query).summary?.today.totalTokens, 102)
    }

    func testDigestDetectsNonLatestEqualSizeModificationAndWALChanges() throws {
        let root = try makeTemporaryRoot()
        let first = root.appendingPathComponent("state.vscdb")
        let wal = root.appendingPathComponent("state.vscdb-wal")
        try Data("abcd".utf8).write(to: first)
        try Data("1234".utf8).write(to: wal)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: first.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 500)], ofItemAtPath: wal.path)
        let before = LocalUsageSourceFingerprintBuilder.fingerprint(roots: [root.path], includeFile: { _ in true })
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: first.path)
        let changed = LocalUsageSourceFingerprintBuilder.fingerprint(roots: [root.path], includeFile: { _ in true })
        XCTAssertEqual(before.totalSize, changed.totalSize)
        XCTAssertEqual(before.latestModificationTime, changed.latestModificationTime)
        XCTAssertNotEqual(before.metadataDigest, changed.metadataDigest)
        try FileManager.default.removeItem(at: wal)
        let checkpointed = LocalUsageSourceFingerprintBuilder.fingerprint(roots: [first.path, wal.path], includeFile: { _ in true })
        XCTAssertEqual(checkpointed.fileCount, 1)
    }

    func testSlowAsyncRestoreDoesNotBlockMainActorAndCancellationDoesNotPublish() async throws {
        let root = try makeTemporaryRoot()
        let releaseRead = DispatchSemaphore(value: 0)
        let startedRead = LockedCounter()
        let query = makeQuery(identityKey: "slow-restore")
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root, beforeCacheRead: {
            startedRead.increment()
            _ = releaseRead.wait(timeout: .now() + 2)
        })
        // Reaching this assertion while the read is blocked proves initialization did not wait on disk.
        XCTAssertNil(repository.snapshot(for: query).summary)
        let fingerprint = LocalUsageSourceFingerprint(roots: [], fileCount: 0, totalSize: 0, latestModificationTime: nil)
        let calls = LockedCounter()
        repository.refreshIfNeeded(query: query, force: true, fingerprintProvider: { fingerprint }, loader: { _ in
            calls.increment()
            return LocalUsageHistoryLoadResult(summary: Self.sampleSummary(seed: 9), sourceFingerprint: fingerprint)
        }, onStateChange: {})
        repository.cancelRefresh(for: query)
        releaseRead.signal()
        try await waitUntil(repository: repository, query: query) { !$0.isLoading }
        XCTAssertEqual(calls.value, 0)
        XCTAssertNil(repository.snapshot(for: query).summary)
    }

    func testResetAndRemovePreventLateWorkersResurrectingEntries() async throws {
        let root = try makeTemporaryRoot()
        let query = makeQuery(identityKey: "reset-race")
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root)
        let fingerprint = LocalUsageSourceFingerprint(roots: [], fileCount: 0, totalSize: 0, latestModificationTime: nil)
        let started = LockedCounter()
        let release = DispatchSemaphore(value: 0)
        repository.refreshIfNeeded(query: query, force: true, fingerprintProvider: { fingerprint }, loader: { _ in
            started.increment()
            _ = release.wait(timeout: .now() + 2)
            return LocalUsageHistoryLoadResult(summary: Self.sampleSummary(seed: 42), sourceFingerprint: fingerprint)
        }, onStateChange: {})
        try await waitUntil(repository: repository, query: query) { _ in started.value == 1 }
        repository.reset()
        release.signal()
        await repository.flushPersistence()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(repository.snapshot(for: query).summary)
        repository.refreshIfNeeded(query: query, force: true, fingerprintProvider: { fingerprint }, loader: { _ in
            LocalUsageHistoryLoadResult(summary: Self.sampleSummary(seed: 2), sourceFingerprint: fingerprint)
        }, onStateChange: {})
        try await waitUntil(repository: repository, query: query) { $0.summary != nil && !$0.isLoading }
        repository.removeEntries(providerID: query.providerID)
        await repository.shutdown()
        let restored = LocalUsageHistoryRepository(baseDirectoryURL: root, asynchronousIO: false)
        XCTAssertNil(restored.snapshot(for: query).summary)
    }

    func testAsyncLoaderIsUsedInsteadOfBlockingLoader() async throws {
        let root = try makeTemporaryRoot()
        let query = makeQuery(identityKey: "async-loader")
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root)
        let fingerprint = LocalUsageSourceFingerprint(roots: [], fileCount: 0, totalSize: 0, latestModificationTime: nil)
        repository.refreshIfNeeded(query: query, force: true, fingerprintProvider: { fingerprint }, loader: { _ in
            throw SampleError.refreshFailed
        }, asyncLoader: { _ in
            await Task.yield()
            return LocalUsageHistoryLoadResult(summary: Self.sampleSummary(seed: 5), sourceFingerprint: fingerprint)
        }, onStateChange: {})
        try await waitUntil(repository: repository, query: query) { $0.summary?.today.totalTokens == 105 && !$0.isLoading }
        XCTAssertNil(repository.snapshot(for: query).error)
    }

    func testGeneratedFingerprintInventoryBenchmarks() throws {
        // Generated metadata only. Single samples are timings, not p95 or energy claims.
        for count in [1_000, 10_000] {
            let root = try makeTemporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            for index in 0..<count {
                try Data("{}\n".utf8).write(to: root.appendingPathComponent("\(index).jsonl"))
            }
            let start = Date()
            let fingerprint = LocalUsageSourceFingerprintBuilder.fingerprint(roots: [root.path], includeFile: { $0.pathExtension == "jsonl" })
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertEqual(fingerprint.fileCount, count)
            XCTAssertNotNil(fingerprint.metadataDigest)
            print("Generated fingerprint fixture files=\(count) elapsedSeconds=\(elapsed)")
        }
    }

    func testSourceInventoryDescriptorSeparatesFiltersAndUpdatesMetadata() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let wire = root.appendingPathComponent("wire.jsonl")
        let session = root.appendingPathComponent("session.jsonl")
        try Data("wire".utf8).write(to: wire)
        try Data("session".utf8).write(to: session)
        let all = LocalUsageSourceInventory.files(descriptor: .codexSessionJSONL, roots: [root.path])
        let narrow = LocalUsageSourceInventory.files(descriptor: .kimiWireJSONL, roots: [root.path])
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(narrow.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path },
                       [wire.resolvingSymlinksInPath().path])
        let before = LocalUsageSourceFingerprintBuilder.fingerprint(roots: [root.path], inventory: all)
        try Data("longer-session".utf8).write(to: session)
        let updated = LocalUsageSourceInventory.files(descriptor: .codexSessionJSONL, roots: [root.path])
        XCTAssertNotEqual(before, LocalUsageSourceFingerprintBuilder.fingerprint(roots: [root.path], inventory: updated))
        XCTAssertEqual(LocalUsageSourceInventory.files(descriptor: .kimiWireJSONL, roots: [root.path]).count, 1)
    }

    func testResetWhileRestoreReadIsBlockedDoesNotResurrectCache() async throws {
        let root = try makeTemporaryRoot()
        let query = makeQuery(identityKey: "restore-reset")
        let entry = LocalUsageHistoryEntry(query: query, summary: Self.sampleSummary(seed: 1), refreshedAt: Date(),
            sourceFingerprint: nil, lastFingerprintCheckedAt: nil, lastError: nil, isStaleFallback: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try writeCache(Data("{\"entries\":".utf8) + encoder.encode([entry]) + Data("}".utf8), root: root)
        let release = DispatchSemaphore(value: 0)
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root, beforeCacheRead: {
            _ = release.wait(timeout: .now() + 2)
        })
        repository.reset()
        release.signal()
        await repository.flushPersistence()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(repository.snapshot(for: query).summary)
        let restored = LocalUsageHistoryRepository(baseDirectoryURL: root, asynchronousIO: false)
        XCTAssertNil(restored.snapshot(for: query).summary)
    }

    func testRemoveDuringRestoreRetainsOtherProviderCacheOnDisk() async throws {
        let root = try makeTemporaryRoot()
        let queryA = makeQuery(identityKey: "remove-A")
        var queryB = makeQuery(identityKey: "retain-B")
        queryB.providerID = "other-provider"
        func entry(_ query: LocalUsageHistoryQuery) -> LocalUsageHistoryEntry {
            LocalUsageHistoryEntry(query: query, summary: Self.sampleSummary(seed: 1), refreshedAt: Date(),
                sourceFingerprint: nil, lastFingerprintCheckedAt: nil, lastError: nil, isStaleFallback: false)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try writeCache(Data("{\"entries\":".utf8) + encoder.encode([entry(queryA), entry(queryB)]) + Data("}".utf8), root: root)
        let release = DispatchSemaphore(value: 0)
        let repository = LocalUsageHistoryRepository(baseDirectoryURL: root, beforeCacheRead: {
            _ = release.wait(timeout: .now() + 2)
        })
        repository.removeEntries(providerID: queryA.providerID)
        release.signal()
        await repository.flushPersistence()
        XCTAssertNil(repository.snapshot(for: queryA).summary)
        XCTAssertNotNil(repository.snapshot(for: queryB).summary)
        let restored = LocalUsageHistoryRepository(baseDirectoryURL: root, asynchronousIO: false)
        XCTAssertNil(restored.snapshot(for: queryA).summary)
        XCTAssertNotNil(restored.snapshot(for: queryB).summary)
    }

    private func writeCache(_ data: Data, root: URL) throws {
        let url = localUsageCacheURL(root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func testFingerprintChangesWhenFileSetChanges() throws {
        let root = try makeTemporaryRoot().appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("one.jsonl")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)],
            ofItemAtPath: fileURL.path
        )

        let first = LocalUsageSourceFingerprintBuilder.fingerprint(
            roots: [root.path],
            includeFile: { $0.pathExtension == "jsonl" }
        )

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 20)],
            ofItemAtPath: fileURL.path
        )
        let mtimeOnlyChange = LocalUsageSourceFingerprintBuilder.fingerprint(
            roots: [root.path],
            includeFile: { $0.pathExtension == "jsonl" }
        )

        try "abcdef".write(to: fileURL, atomically: true, encoding: .utf8)
        let second = LocalUsageSourceFingerprintBuilder.fingerprint(
            roots: [root.path],
            includeFile: { $0.pathExtension == "jsonl" }
        )

        let secondFileURL = root.appendingPathComponent("two.jsonl")
        try "z".write(to: secondFileURL, atomically: true, encoding: .utf8)
        let third = LocalUsageSourceFingerprintBuilder.fingerprint(
            roots: [root.path],
            includeFile: { $0.pathExtension == "jsonl" }
        )

        try FileManager.default.removeItem(at: secondFileURL)
        let fourth = LocalUsageSourceFingerprintBuilder.fingerprint(
            roots: [root.path],
            includeFile: { $0.pathExtension == "jsonl" }
        )

        XCTAssertEqual(first.fileCount, 1)
        XCTAssertNotEqual(first.latestModificationTime, mtimeOnlyChange.latestModificationTime)
        XCTAssertNotEqual(first, mtimeOnlyChange)
        XCTAssertNotEqual(first.totalSize, second.totalSize)
        XCTAssertEqual(third.fileCount, 2)
        XCTAssertGreaterThan(third.totalSize, second.totalSize)
        XCTAssertEqual(fourth.fileCount, 1)
        XCTAssertNotEqual(third, fourth)
    }

    func testParsedFileCachePrunesLeastRecentlyUsedEntry() {
        let cache = LocalUsageParsedFileCache<Int>(maxEntries: 2)
        let first = LocalUsageFileSnapshot(path: "/tmp/first.jsonl", fileSize: 1, modifiedAtRef: 1)
        let second = LocalUsageFileSnapshot(path: "/tmp/second.jsonl", fileSize: 1, modifiedAtRef: 1)
        let third = LocalUsageFileSnapshot(path: "/tmp/third.jsonl", fileSize: 1, modifiedAtRef: 1)
        var firstParseCount = 0
        var secondParseCount = 0
        var thirdParseCount = 0

        XCTAssertEqual(cache.values(for: first) {
            firstParseCount += 1
            return [1]
        }, [1])
        XCTAssertEqual(cache.values(for: second) {
            secondParseCount += 1
            return [2]
        }, [2])
        XCTAssertEqual(cache.values(for: first) {
            firstParseCount += 1
            return [10]
        }, [1])
        XCTAssertEqual(cache.values(for: third) {
            thirdParseCount += 1
            return [3]
        }, [3])

        XCTAssertEqual(cache.values(for: first) {
            firstParseCount += 1
            return [10]
        }, [1])
        XCTAssertEqual(cache.values(for: second) {
            secondParseCount += 1
            return [20]
        }, [20])
        XCTAssertEqual(firstParseCount, 1)
        XCTAssertEqual(secondParseCount, 2)
        XCTAssertEqual(thirdParseCount, 1)
    }

    func testParsedFileCachePrunesByCachedValueCount() {
        let cache = LocalUsageParsedFileCache<Int>(maxEntries: 3, maxCachedValues: 3)
        let first = LocalUsageFileSnapshot(path: "/tmp/value-count-first.jsonl", fileSize: 1, modifiedAtRef: 1)
        let second = LocalUsageFileSnapshot(path: "/tmp/value-count-second.jsonl", fileSize: 1, modifiedAtRef: 1)
        var firstParseCount = 0
        var secondParseCount = 0

        XCTAssertEqual(cache.values(for: first) {
            firstParseCount += 1
            return [1, 2]
        }, [1, 2])
        XCTAssertEqual(cache.values(for: second) {
            secondParseCount += 1
            return [3, 4]
        }, [3, 4])

        // The oldest entry is evicted because the aggregate value count is 4.
        XCTAssertEqual(cache.values(for: first) {
            firstParseCount += 1
            return [10, 20]
        }, [10, 20])
        XCTAssertEqual(firstParseCount, 2)
        XCTAssertEqual(secondParseCount, 1)
    }

    func testParsedFileCacheDoesNotRetainSingleOversizedEntry() {
        let cache = LocalUsageParsedFileCache<Int>(maxEntries: 3, maxCachedValues: 2)
        let snapshot = LocalUsageFileSnapshot(path: "/tmp/oversized.jsonl", fileSize: 1, modifiedAtRef: 1)
        var parseCount = 0

        XCTAssertEqual(cache.values(for: snapshot) {
            parseCount += 1
            return [1, 2, 3]
        }, [1, 2, 3])
        XCTAssertEqual(cache.values(for: snapshot) {
            parseCount += 1
            return [4, 5, 6]
        }, [4, 5, 6])
        XCTAssertEqual(parseCount, 2)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func localUsageCacheURL(root: URL) -> URL {
        root
            .appendingPathComponent("OhMyUsage", isDirectory: true)
            .appendingPathComponent("local_usage_history_cache.json")
    }

    private func modificationDate(at url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.modificationDate] as? Date)
    }

    private func makeQuery(identityKey: String) -> LocalUsageHistoryQuery {
        LocalUsageHistoryQuery(
            providerType: .codex,
            providerID: "codex-official",
            scope: .allAccounts,
            identityKey: identityKey
        )
    }

    private func waitUntil(
        repository: LocalUsageHistoryRepository,
        query: LocalUsageHistoryQuery,
        timeout: TimeInterval = 2,
        predicate: (LocalUsageHistoryState) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(repository.snapshot(for: query)) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for local usage history repository state")
    }

    nonisolated private static func sampleSummary(
        seed: Int,
        generatedAt: Date? = nil
    ) -> LocalUsageSummary {
        let now = generatedAt ?? Date(timeIntervalSince1970: TimeInterval(1_800_000_000 + seed))
        let period = LocalUsagePeriodSummary(
            totalTokens: 100 + seed,
            responses: 2,
            byModel: [
                LocalUsageModelBreakdown(
                    modelID: "gpt-test",
                    totalTokens: 100 + seed,
                    responses: 2
                )
            ]
        )
        return LocalUsageSummary(
            today: period,
            yesterday: .empty,
            last30Days: period,
            hourly24: [
                LocalUsageTrendPoint(
                    id: "h-\(seed)",
                    startAt: now,
                    totalTokens: 100 + seed,
                    responses: 2
                )
            ],
            daily7: [
                LocalUsageTrendPoint(
                    id: "d-\(seed)",
                    startAt: now,
                    totalTokens: 100 + seed,
                    responses: 2
                )
            ],
            sourcePath: "/tmp/source-\(seed)",
            generatedAt: now,
            diagnostics: nil,
            isApproximateFallback: false
        )
    }

    private enum SampleError: LocalizedError {
        case refreshFailed

        var errorDescription: String? {
            "refresh failed"
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class LockedDate: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Date

    init(_ value: Date) {
        self.storage = value
    }

    var value: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
