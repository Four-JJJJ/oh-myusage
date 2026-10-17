import XCTest
import OhMyUsageDomain
@testable import OhMyUsage

final class CredentialIntegrityTests: XCTestCase {
    func testColdAndStaleInstancesPreserveOtherCredentials() {
        let memory = CredentialMemoryStore()
        let adapter = memory.adapter
        let first = makeStore(adapter)
        let second = makeStore(adapter)
        XCTAssertTrue(first.saveToken("one", service: "test", account: "a"))
        XCTAssertEqual(second.readToken(service: "test", account: "a"), "one")
        XCTAssertTrue(first.saveToken("two", service: "test", account: "b"))
        XCTAssertTrue(second.saveToken("three", service: "test", account: "c"))
        XCTAssertEqual(memory.snapshot.count, 3)
        XCTAssertTrue(first.deleteToken(service: "test", account: "a"))
        XCTAssertTrue(second.saveToken("four", service: "test", account: "d"))
        XCTAssertNil(second.readToken(service: "test", account: "a"))
        XCTAssertEqual(memory.snapshot.filter { !$0.value.isEmpty }.count, 3)
    }

    func testFailedSaveAndDeleteKeepPersistedAndCachedValue() {
        let memory = CredentialMemoryStore()
        let store = makeStore(memory.adapter)
        XCTAssertTrue(store.saveToken("old", service: "test", account: "a"))
        memory.allowWrites = false
        XCTAssertFalse(store.saveToken("new", service: "test", account: "a"))
        XCTAssertEqual(store.readToken(service: "test", account: "a"), "old")
        XCTAssertFalse(store.deleteToken(service: "test", account: "a"))
        XCTAssertEqual(store.readToken(service: "test", account: "a"), "old")
    }

    func testConcurrentInstancesDoNotLoseWrites() {
        let memory = CredentialMemoryStore()
        let adapter = memory.adapter
        let stores = (0..<24).map { _ in makeStore(adapter) }
        DispatchQueue.concurrentPerform(iterations: stores.count) { index in
            XCTAssertTrue(stores[index].saveToken("value", service: "test", account: "\(index)"))
        }
        XCTAssertEqual(memory.snapshot.count, stores.count)
    }

    func testUnavailableVaultFailsClosedWithoutWrites() {
        let memory = CredentialMemoryStore()
        var adapter = memory.adapter
        adapter.readVault = { _ in .unavailable }
        let store = makeStore(adapter)
        XCTAssertFalse(store.saveToken("new", service: "test", account: "a"))
        XCTAssertFalse(store.deleteToken(service: "test", account: "a"))
        XCTAssertFalse(store.prepareSecureStoreAccess())
        XCTAssertTrue(memory.snapshot.isEmpty)
        XCTAssertNil(store.cachedToken(service: "test", account: "a"))
    }

    func testDeletionDoesNotResurrectUndeletableLegacyItemDuringPreparation() {
        let memory = CredentialMemoryStore()
        var adapter = memory.adapter
        adapter.readAll = { service, _ in
            service == KeychainService.legacyServiceName ? ["a": "legacy"] : [:]
        }
        let store = makeStore(adapter)
        XCTAssertTrue(store.saveToken("current", service: KeychainService.defaultServiceName, account: "a"))
        XCTAssertTrue(store.deleteToken(service: KeychainService.defaultServiceName, account: "a"))
        XCTAssertTrue(store.prepareSecureStoreAccess())
        let reloaded = makeStore(adapter)
        XCTAssertNil(reloaded.readToken(service: KeychainService.defaultServiceName, account: "a"))
        XCTAssertFalse(reloaded.storedCredentialIdentifiers().contains("\(KeychainService.defaultServiceName)::a"))
    }

    func testBrokerInvalidatesCachesAfterAnotherStoreWritesOrDeletes() {
        let memory = CredentialMemoryStore()
        let adapter = memory.adapter
        let first = makeStore(adapter)
        let broker = CredentialBroker(keychain: makeStore(adapter))
        XCTAssertTrue(first.saveToken("old", service: "test", account: "a"))
        XCTAssertEqual(broker.readToken(service: "test", account: "a"), "old")
        XCTAssertTrue(first.saveToken("new", service: "test", account: "a"))
        XCTAssertEqual(broker.readToken(service: "test", account: "a"), "new")
        XCTAssertTrue(first.deleteToken(service: "test", account: "a"))
        XCTAssertNil(broker.readToken(service: "test", account: "a"))
    }

    func testFileInstancesPreserveWritesAndFailClosedOnCorruptStorage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = KeychainService(storageURL: url)
        let second = KeychainService(storageURL: url)
        XCTAssertTrue(first.saveToken("one", service: "test", account: "a"))
        XCTAssertTrue(second.saveToken("two", service: "test", account: "b"))
        XCTAssertEqual(first.readToken(service: "test", account: "b"), "two")
        try Data("invalid".utf8).write(to: url)
        XCTAssertFalse(first.saveToken("three", service: "test", account: "c"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "invalid")
    }

    func testPreparationWaitsForInFlightWriteAndPreservesItsSnapshot() {
        let memory = CredentialMemoryStore()
        var adapter = memory.adapter
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let completed = DispatchGroup()
        let baseSave = adapter.saveData
        adapter.saveData = { data, service, account, interactive in
            if !interactive {
                entered.signal()
                _ = release.wait(timeout: .now() + 10)
            }
            return baseSave(data, service, account, interactive)
        }
        let writer = makeStore(adapter)
        let preparer = makeStore(adapter)
        completed.enter()
        DispatchQueue.global().async {
            XCTAssertTrue(writer.saveToken("value", service: "test", account: "a"))
            completed.leave()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 10), .success)
        completed.enter()
        DispatchQueue.global().async {
            XCTAssertTrue(preparer.prepareSecureStoreAccess())
            completed.leave()
        }
        release.signal()
        XCTAssertEqual(completed.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(preparer.readToken(service: "test", account: "a"), "value")
        XCTAssertEqual(memory.snapshot["test::a"], "value")
    }

    func testThrowingCredentialPortReportsPersistenceFailure() async {
        let memory = CredentialMemoryStore()
        let store = makeStore(memory.adapter)
        memory.allowWrites = false
        do {
            try await store.saveCredential("value", for: UsageProviderIdentity("test")!)
            XCTFail("Failed persistence must throw")
        } catch { }
        do {
            try await store.removeCredential(for: UsageProviderIdentity("test")!)
            XCTFail("Failed persistence must throw")
        } catch { }
    }

    @MainActor
    func testAppViewModelDefaultCodexAuthUsesInjectedCredentialStore() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let keychain = KeychainService(storageURL: url,
            defaults: UserDefaults(suiteName: "CredentialIntegrityTests.\(UUID().uuidString)")!)
        let viewModel = AppViewModel(testingConfig: AppConfig(providers: []),
                                    appUpdateService: AppUpdateService(), keychain: keychain)
        let authJSON = #"{"tokens":{"access_token":"fake-access","refresh_token":"fake-refresh","account_id":"fake-account"}}"#
        XCTAssertTrue(keychain.saveToken(authJSON, service: KeychainService.defaultServiceName,
                                        account: OfficialOAuthVaultAccounts.codexOAuthJSON))
        XCTAssertEqual(viewModel.codexDesktopAuthService.currentAuthJSON(), authJSON)
    }

    func testDeletingCustomServiceDoesNotDeleteUnmigratedDefaultLegacyAccount() {
        let memory = CredentialMemoryStore()
        let legacy = LegacyCredentialFixture()
        var adapter = memory.adapter
        adapter.readData = { service, account, _ in
            legacy.read(service: service, account: account)
        }
        adapter.deleteItem = { service, account in
            legacy.delete(service: service, account: account)
        }
        let store = makeStore(adapter)
        XCTAssertTrue(store.deleteToken(service: "custom-service", account: "shared-account"))
        XCTAssertEqual(legacy.read(service: KeychainService.legacyServiceName, account: "shared-account"),
                       Data("legacy-value".utf8))
    }

    private func makeStore(_ adapter: KeychainService.SecureStoreAdapter) -> KeychainService {
        KeychainService(defaults: UserDefaults(suiteName: "CredentialIntegrityTests.\(UUID().uuidString)")!,
                        forceSecureStore: true, secureStore: adapter)
    }
}

private final class CredentialMemoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    var allowWrites = true
    var snapshot: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }
    var adapter: KeychainService.SecureStoreAdapter {
        KeychainService.SecureStoreAdapter(
            readData: { [self] _, account, _ in
                lock.lock()
                defer { lock.unlock() }
                return account == "__credential_vault__" ? data : nil
            },
            readAll: { _, _ in [:] },
            saveData: { [self] value, _, _, _ in
                lock.lock()
                defer { lock.unlock() }
                guard allowWrites else { return false }
                data = value
                return true
            },
            deleteItem: { _, _ in }, deleteAll: { _ in }
        )
    }
}

private final class LegacyCredentialFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var token: Data? = Data("legacy-value".utf8)

    func read(service: String, account: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return service == KeychainService.legacyServiceName && account == "shared-account" ? token : nil
    }

    func delete(service: String, account: String) {
        lock.lock()
        defer { lock.unlock() }
        if service == KeychainService.legacyServiceName && account == "shared-account" { token = nil }
    }
}
