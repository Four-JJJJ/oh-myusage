import Foundation
import XCTest
import OhMyUsageInfrastructure
import OhMyUsageProviders
@testable import OhMyUsage

final class CredentialBrokerTests: XCTestCase {
    // MARK: - Interactive preparation

    func testConcurrentPrepareExecutesInteractivePreparationOnce() throws {
        let clock = MutableClock()
        let recorder = SecureStoreRecorder()
        let vaultSnapshot = try JSONEncoder().encode([
            "\(KeychainService.defaultServiceName)::prep-account": "prep-token"
        ])
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                if interactive, account == "__credential_vault__" {
                    recorder.signalLeaderEntered()
                    _ = recorder.releaseGate.wait(timeout: .now() + 10)
                    return vaultSnapshot
                }
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let broker = CredentialBroker(
            keychain: makeSecureStoreKeychain(adapter: adapter),
            now: { clock.now }
        )

        let joinSemaphore = DispatchSemaphore(value: 0)
        let results = ResultCollector<CredentialPreparationResult>()
        for index in 0..<4 {
            Thread.detachNewThread { [broker] in
                if index > 0 {
                    Thread.sleep(forTimeInterval: 0.05 * Double(index))
                }
                results.append(broker.prepareSecureStoreAccess())
                joinSemaphore.signal()
            }
        }
        // Wait until the leader is inside the interactive vault read, then give the
        // remaining threads time to reach it too if in-flight merging were broken.
        XCTAssertEqual(recorder.waitLeaderEntered(timeout: 10), .success)
        Thread.sleep(forTimeInterval: 0.4)

        XCTAssertEqual(recorder.counts.interactiveReadData, 1)
        recorder.releaseGate.signal()
        for _ in 0..<4 {
            XCTAssertEqual(joinSemaphore.wait(timeout: .now() + 10), .success)
        }

        XCTAssertEqual(recorder.counts.interactiveReadData, 1)
        let allResults = results.all
        XCTAssertEqual(allResults.count, 4)
        XCTAssertTrue(allResults.allSatisfy(\.succeeded))
        XCTAssertTrue(allResults.allSatisfy { $0.state == .ready })
        XCTAssertEqual(
            broker.readToken(service: KeychainService.defaultServiceName, account: "prep-account"),
            "prep-token"
        )
    }

    func testFailedPrepareReportsSystemAccessRequiredState() {
        let clock = MutableClock()
        let recorder = SecureStoreRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                // Interactive vault creation fails → preparation cannot complete.
                return !interactive
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let broker = CredentialBroker(
            keychain: makeSecureStoreKeychain(adapter: adapter),
            now: { clock.now }
        )

        XCTAssertEqual(broker.accessState(service: "svc", account: "acct"), .notConfigured)

        let result = broker.prepareSecureStoreAccess()

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.state, .systemAccessRequired)
        XCTAssertEqual(broker.accessState(service: "svc", account: "acct"), .systemAccessRequired)
    }

    func testSuccessfulPrepareClearsNegativeCacheAndReportsReady() {
        let clock = MutableClock()
        let recorder = SecureStoreRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                if !interactive, account == "late-account", recorder.lateAccountEnabled {
                    return Data("late-token".utf8)
                }
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                if interactive {
                    // The credential becomes reachable once preparation ran.
                    recorder.lateAccountEnabled = true
                }
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let broker = CredentialBroker(
            keychain: makeSecureStoreKeychain(adapter: adapter),
            now: { clock.now }
        )

        // Missing credential is negative-cached before preparation.
        XCTAssertNil(broker.readToken(service: "svc", account: "late-account"))
        let accountReadsBeforePrepare = recorder.readDataCount(service: "svc", account: "late-account")

        let result = broker.prepareSecureStoreAccess()

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(broker.accessState(service: "svc", account: "late-account"), .ready)
        // Negative cache cleared by preparation: the key is readable again and the
        // underlying non-interactive read is re-consulted exactly once.
        XCTAssertEqual(broker.readToken(service: "svc", account: "late-account"), "late-token")
        XCTAssertEqual(recorder.readDataCount(service: "svc", account: "late-account"), accountReadsBeforePrepare + 1)
    }

    // MARK: - Background reads are always non-interactive

    func testBackgroundReadsNeverTouchInteractiveKeychainAccess() {
        let clock = MutableClock()
        let recorder = SecureStoreRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                if !interactive, account == "present" {
                    return Data("present-token".utf8)
                }
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let broker = CredentialBroker(
            keychain: makeSecureStoreKeychain(adapter: adapter),
            now: { clock.now }
        )

        func readOnce() {
            XCTAssertEqual(broker.readToken(service: "svc", account: "present"), "present-token")
            XCTAssertNil(broker.readToken(service: "svc", account: "missing"))
            XCTAssertEqual(broker.accessState(service: "svc", account: "present"), .ready)
        }

        readOnce()
        let countsAfterFirstPass = recorder.counts
        readOnce()
        readOnce()

        // Repeat reads are served from the broker caches: no additional keychain work.
        XCTAssertEqual(recorder.counts, countsAfterFirstPass)
        XCTAssertEqual(recorder.counts.interactiveReadData, 0)
        XCTAssertEqual(recorder.counts.interactiveReadAll, 0)
        XCTAssertEqual(recorder.counts.interactiveSaveData, 0)
    }

    // MARK: - In-flight read merge

    func testConcurrentReadsOfSameKeyHitUnderlyingStoreOnce() {
        let clock = MutableClock()
        let recorder = SecureStoreRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                if !interactive, account == "shared-account" {
                    recorder.signalLeaderEntered()
                    _ = recorder.releaseGate.wait(timeout: .now() + 10)
                }
                return Data("shared-token".utf8)
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let broker = CredentialBroker(
            keychain: makeSecureStoreKeychain(adapter: adapter),
            now: { clock.now }
        )

        let joinSemaphore = DispatchSemaphore(value: 0)
        let results = ResultCollector<String?>()
        for index in 0..<3 {
            Thread.detachNewThread { [broker] in
                if index > 0 {
                    Thread.sleep(forTimeInterval: 0.05 * Double(index))
                }
                results.append(broker.readToken(service: "svc", account: "shared-account"))
                joinSemaphore.signal()
            }
        }
        // Once the leader blocks inside the underlying read, the joiners must wait on
        // the in-flight entry instead of issuing their own underlying reads.
        XCTAssertEqual(recorder.waitLeaderEntered(timeout: 10), .success)
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(recorder.readDataCount(service: "svc", account: "shared-account"), 1)

        recorder.releaseGate.signal()
        for _ in 0..<3 {
            XCTAssertEqual(joinSemaphore.wait(timeout: .now() + 10), .success)
        }

        XCTAssertEqual(recorder.readDataCount(service: "svc", account: "shared-account"), 1)
        let allResults = results.all
        XCTAssertEqual(allResults.count, 3)
        XCTAssertTrue(allResults.allSatisfy { $0 == "shared-token" })
    }

    // MARK: - TTL caches

    func testSuccessCacheExpiresAfterTTL() {
        let clock = MutableClock()
        let recorder = SecureStoreRecorder()
        let keychain = makeSecureStoreKeychain(adapter: KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                if !interactive, account == "ttl-account" {
                    return Data("ttl-token".utf8)
                }
                return nil
            },
            readAll: { _, _ in nil },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        ))
        let broker = CredentialBroker(
            keychain: keychain,
            successCacheTTL: 60,
            negativeCacheTTL: 10,
            now: { clock.now }
        )

        XCTAssertEqual(broker.readToken(service: "svc", account: "ttl-account"), "ttl-token")
        let initialAccountReads = recorder.readDataCount(service: "svc", account: "ttl-account")
        XCTAssertEqual(initialAccountReads, 1)

        // Within the TTL the broker shield even a cold keychain from re-reads.
        clock.advance(30)
        keychain.resetAllStoredCredentials()
        XCTAssertEqual(broker.readToken(service: "svc", account: "ttl-account"), "ttl-token")
        XCTAssertEqual(recorder.readDataCount(service: "svc", account: "ttl-account"), initialAccountReads)

        // Past the TTL the broker re-consults the underlying store exactly once.
        clock.advance(40)
        keychain.resetAllStoredCredentials()
        XCTAssertEqual(broker.readToken(service: "svc", account: "ttl-account"), "ttl-token")
        XCTAssertEqual(recorder.readDataCount(service: "svc", account: "ttl-account"), initialAccountReads + 1)
    }

    func testNegativeCacheExpiresAfterTTL() {
        let clock = MutableClock()
        let recorder = SecureStoreRecorder()
        let keychain = makeSecureStoreKeychain(adapter: KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { _, _ in nil },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        ))
        let broker = CredentialBroker(
            keychain: keychain,
            successCacheTTL: 60,
            negativeCacheTTL: 10,
            now: { clock.now }
        )

        XCTAssertNil(broker.readToken(service: "svc", account: "missing-account"))
        let initialAccountReads = recorder.readDataCount(service: "svc", account: "missing-account")
        XCTAssertEqual(initialAccountReads, 1)

        // Within the negative TTL the broker shields even a cold keychain.
        clock.advance(5)
        keychain.resetAllStoredCredentials()
        XCTAssertNil(broker.readToken(service: "svc", account: "missing-account"))
        XCTAssertEqual(recorder.readDataCount(service: "svc", account: "missing-account"), initialAccountReads)

        // Past the negative TTL the miss is re-consulted against the store.
        clock.advance(6)
        keychain.resetAllStoredCredentials()
        XCTAssertNil(broker.readToken(service: "svc", account: "missing-account"))
        XCTAssertEqual(recorder.readDataCount(service: "svc", account: "missing-account"), initialAccountReads + 1)
    }

    // MARK: - Save / delete cache updates

    func testSaveTokenRefreshesCachesImmediately() {
        let clock = MutableClock()
        let broker = CredentialBroker(
            keychain: makeFileKeychain(),
            successCacheTTL: 60,
            negativeCacheTTL: 10,
            now: { clock.now }
        )

        // Missing key is negative-cached first.
        XCTAssertNil(broker.readToken(service: "svc", account: "save-account"))

        XCTAssertTrue(broker.saveToken("saved-token", service: "svc", account: "save-account"))

        // Save must clear the negative cache: the value is immediately visible and
        // survives the success TTL via the underlying persistence.
        XCTAssertEqual(broker.readToken(service: "svc", account: "save-account"), "saved-token")
        clock.advance(120)
        XCTAssertEqual(broker.readToken(service: "svc", account: "save-account"), "saved-token")
        XCTAssertEqual(broker.accessState(service: "svc", account: "save-account"), .ready)
    }

    func testDeleteTokenInvalidatesCachedValue() {
        let clock = MutableClock()
        let broker = CredentialBroker(
            keychain: makeFileKeychain(),
            successCacheTTL: 60,
            negativeCacheTTL: 10,
            now: { clock.now }
        )

        XCTAssertTrue(broker.saveToken("doomed-token", service: "svc", account: "delete-account"))
        XCTAssertEqual(broker.readToken(service: "svc", account: "delete-account"), "doomed-token")

        XCTAssertTrue(broker.deleteToken(service: "svc", account: "delete-account"))

        XCTAssertNil(broker.readToken(service: "svc", account: "delete-account"))
        XCTAssertEqual(broker.accessState(service: "svc", account: "delete-account"), .notConfigured)
        // Deletion survives the negative-cache TTL (not just the in-memory view).
        clock.advance(30)
        XCTAssertNil(broker.readToken(service: "svc", account: "delete-account"))
    }

    // MARK: - Cache invalidation

    func testInvalidateCacheForcesFreshUnderlyingReads() {
        let clock = MutableClock()
        let keychain = makeFileKeychain()
        let broker = CredentialBroker(
            keychain: keychain,
            successCacheTTL: 60,
            negativeCacheTTL: 10,
            now: { clock.now }
        )

        XCTAssertTrue(broker.saveToken("fresh-token", service: "svc", account: "fresh-account"))
        XCTAssertEqual(broker.readToken(service: "svc", account: "fresh-account"), "fresh-token")
        // Underlying store changes out of band (simulating another writer).
        XCTAssertTrue(keychain.saveToken("out-of-band-token", service: "svc", account: "fresh-account"))
        XCTAssertEqual(broker.readToken(service: "svc", account: "fresh-account"), "fresh-token")

        broker.invalidateCache(service: "svc", account: "fresh-account")
        XCTAssertEqual(broker.readToken(service: "svc", account: "fresh-account"), "out-of-band-token")

        broker.invalidateCache(service: nil, account: nil)
        XCTAssertNil(broker.readToken(service: "svc", account: "never-saved"))
    }

    // MARK: - Legacy service name migration

    func testLegacyServiceNamesNormalizeToDefaultServiceLosslessly() {
        let storageURL = makeCredentialURL()
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }

        let writer = CredentialBroker(keychain: KeychainService(storageURL: storageURL, defaults: makeDefaults()))
        XCTAssertTrue(writer.saveToken("legacy-a", service: "OhMyUsage", account: "demo-a"))
        XCTAssertTrue(writer.saveToken("legacy-b", service: "AI Plan Monitor", account: "demo-b"))
        XCTAssertTrue(writer.saveToken("legacy-c", service: "AIPlanMonitor", account: "demo-c"))

        // A fresh broker over the same storage must read every historical name back
        // through the canonical default service name.
        let reader = CredentialBroker(keychain: KeychainService(storageURL: storageURL, defaults: makeDefaults()))
        XCTAssertEqual(reader.readToken(service: KeychainService.defaultServiceName, account: "demo-a"), "legacy-a")
        XCTAssertEqual(reader.readToken(service: KeychainService.defaultServiceName, account: "demo-b"), "legacy-b")
        XCTAssertEqual(reader.readToken(service: KeychainService.defaultServiceName, account: "demo-c"), "legacy-c")
        XCTAssertEqual(reader.readToken(service: "OhMyUsage", account: "demo-a"), "legacy-a")
        XCTAssertEqual(reader.readToken(service: "AI Plan Monitor", account: "demo-b"), "legacy-b")
    }

    func testPrepareMigratesHistoricalServiceItemsThroughBroker() throws {
        let clock = MutableClock()
        let recorder = SecureStoreRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                guard !interactive else { return nil }
                if service == "AI Plan Monitor" {
                    return ["ai-plan-account": "ai-plan-token"]
                }
                if service == "AIPlanMonitor" {
                    return ["aiplan-account": "aiplan-token"]
                }
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let broker = CredentialBroker(
            keychain: makeSecureStoreKeychain(adapter: adapter),
            now: { clock.now }
        )

        let result = broker.prepareSecureStoreAccess()

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(
            broker.readToken(service: KeychainService.defaultServiceName, account: "ai-plan-account"),
            "ai-plan-token"
        )
        XCTAssertEqual(
            broker.readToken(service: KeychainService.defaultServiceName, account: "aiplan-account"),
            "aiplan-token"
        )
        let vaultSnapshot = try XCTUnwrap(recorder.latestSavedVaultSnapshot)
        XCTAssertEqual(vaultSnapshot["\(KeychainService.defaultServiceName)::ai-plan-account"], "ai-plan-token")
        XCTAssertEqual(vaultSnapshot["\(KeychainService.defaultServiceName)::aiplan-account"], "aiplan-token")
        XCTAssertEqual(recorder.counts.interactiveReadData, 1)
    }

    // MARK: - Port conformances

    func testBrokerSatisfiesTokenCredentialStoringPort() {
        let broker: any TokenCredentialStoring = CredentialBroker(keychain: makeFileKeychain())

        XCTAssertTrue(broker.saveToken("port-token", service: "svc", account: "port-account"))
        XCTAssertEqual(broker.readToken(service: "svc", account: "port-account"), "port-token")
        XCTAssertTrue(broker.deleteToken(service: "svc", account: "port-account"))
        XCTAssertNil(broker.readToken(service: "svc", account: "port-account"))
    }

    func testBrokerSatisfiesInfrastructureCredentialStoringPort() {
        let broker: any CredentialStoring = CredentialBroker(keychain: makeFileKeychain())

        XCTAssertTrue(broker.saveToken("infra-token", service: "svc", account: "infra-account"))
        XCTAssertEqual(broker.readToken(service: "svc", account: "infra-account"), "infra-token")
        XCTAssertTrue(broker.deleteToken(service: "svc", account: "infra-account"))
        XCTAssertNil(broker.readToken(service: "svc", account: "infra-account"))
    }

    // MARK: - Helpers

    private func makeSecureStoreKeychain(adapter: KeychainService.SecureStoreAdapter) -> KeychainService {
        KeychainService(
            defaults: makeDefaults(),
            forceSecureStore: true,
            secureStore: adapter
        )
    }

    private func makeFileKeychain() -> KeychainService {
        KeychainService(
            storageURL: makeCredentialURL(),
            defaults: makeDefaults(),
            forceSecureStore: false
        )
    }

    private func makeCredentialURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CredentialBrokerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "CredentialBrokerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

/// Thread-safe collector for values produced on detached threads.
private final class ResultCollector<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [T] = []

    func append(_ value: T) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var all: [T] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

/// Injectable wall clock for TTL assertions.
private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.current = date
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}

/// Thread-safe recorder over the `KeychainService.SecureStoreAdapter` seams.
/// Only aggregate call counts, account names and decoded vault snapshot keys are
/// retained — never credential values.
private final class SecureStoreRecorder: @unchecked Sendable {
    let releaseGate = DispatchSemaphore(value: 0)
    private let leaderEntered = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var readDataCountsByServiceAccount: [String: Int] = [:]
    private var readDataCount = 0
    private var readAllCount = 0
    private var saveDataCount = 0
    private var interactiveReadDataCount = 0
    private var interactiveReadAllCount = 0
    private var interactiveSaveDataCount = 0
    private var savedVaultSnapshots: [[String: String]] = []
    private var lateAccountEnabledValue = false

    var lateAccountEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return lateAccountEnabledValue
        }
        set {
            lock.lock()
            lateAccountEnabledValue = newValue
            lock.unlock()
        }
    }

    struct Counters: Equatable {
        var readData = 0
        var readAll = 0
        var saveData = 0
        var interactiveReadData = 0
        var interactiveReadAll = 0
        var interactiveSaveData = 0
    }

    var counts: Counters {
        lock.lock()
        defer { lock.unlock() }
        return Counters(
            readData: readDataCount,
            readAll: readAllCount,
            saveData: saveDataCount,
            interactiveReadData: interactiveReadDataCount,
            interactiveReadAll: interactiveReadAllCount,
            interactiveSaveData: interactiveSaveDataCount
        )
    }

    func readDataCount(service: String, account: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return readDataCountsByServiceAccount["\(service)::\(account)", default: 0]
    }

    var latestSavedVaultSnapshot: [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return savedVaultSnapshots.last
    }

    func signalLeaderEntered() {
        leaderEntered.signal()
    }

    func waitLeaderEntered(timeout: TimeInterval) -> DispatchTimeoutResult {
        leaderEntered.wait(timeout: .now() + timeout)
    }

    func recordReadData(service: String, account: String, interactive: Bool) {
        lock.lock()
        readDataCount += 1
        readDataCountsByServiceAccount["\(service)::\(account)", default: 0] += 1
        if interactive {
            interactiveReadDataCount += 1
        }
        lock.unlock()
    }

    func recordReadAll(service: String, interactive: Bool) {
        lock.lock()
        readAllCount += 1
        if interactive {
            interactiveReadAllCount += 1
        }
        lock.unlock()
    }

    func recordSaveData(data: Data, service: String, account: String, interactive: Bool) {
        lock.lock()
        saveDataCount += 1
        if interactive {
            interactiveSaveDataCount += 1
        }
        if service == KeychainService.defaultServiceName,
           account == "__credential_vault__",
           let snapshot = try? JSONDecoder().decode([String: String].self, from: data) {
            savedVaultSnapshots.append(snapshot)
        }
        lock.unlock()
    }
}
