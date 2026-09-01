import Foundation
import XCTest
@testable import OhMyUsage

@MainActor
final class CredentialAccessServiceTests: XCTestCase {
    func testSaveCredentialMakesLengthAvailableFromCache() {
        let keychain = KeychainService(storageURL: makeCredentialURL())
        let service = CredentialAccessService(keychain: keychain)

        XCTAssertTrue(service.saveCredential("secret-token", service: "svc", account: "acct"))

        let length = service.savedCredentialLength(
            service: "svc",
            account: "acct",
            secureStorageReady: true,
            onLookupStateChanged: {}
        )
        XCTAssertEqual(length, "secret-token".count)
    }

    func testDisplayOnlyMissingCredentialDoesNotScheduleLookup() {
        let keychain = KeychainService(storageURL: makeCredentialURL())
        let service = CredentialAccessService(keychain: keychain)

        XCTAssertNil(
            service.savedCredentialLength(
                service: "svc",
                account: "missing",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )

        XCTAssertNil(
            service.savedCredentialLength(
                service: "svc",
                account: "missing",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )
        XCTAssertEqual(service.debugMissingKeyCount, 0)
        XCTAssertEqual(service.debugLookupInFlightCount, 0)
    }

    func testDisplayOnlyLookupDoesNotReadSecureStoreWhenCacheMiss() {
        let suite = "CredentialAccessServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let recorder = CredentialReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, _ in
                recorder.recordReadData(service: service, account: account)
                return Data("secret-token".utf8)
            },
            readAll: { service, _ in
                recorder.recordReadAll(service: service)
                return ["acct": "secret-token"]
            },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let keychain = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )
        let service = CredentialAccessService(keychain: keychain)

        XCTAssertNil(
            service.savedCredentialLength(
                service: "svc",
                account: "acct",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
        XCTAssertEqual(service.debugLookupInFlightCount, 0)
    }

    func testDisplayOnlyLengthUsesSavedMetadataWithoutReadingSecureStore() {
        let suite = "CredentialAccessServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let recorder = CredentialReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, _ in
                recorder.recordReadData(service: service, account: account)
                return nil
            },
            readAll: { service, _ in
                recorder.recordReadAll(service: service)
                return nil
            },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let savingKeychain = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )
        XCTAssertTrue(savingKeychain.saveToken("secret-token", service: "svc", account: "acct"))

        let displayOnlyKeychain = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )
        let service = CredentialAccessService(keychain: displayOnlyKeychain)

        XCTAssertEqual(
            service.savedCredentialLength(
                service: "svc",
                account: "acct",
                secureStorageReady: true,
                onLookupStateChanged: {}
            ),
            "secret-token".count
        )
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
    }

    // MARK: - Access state mapping (doc 7.5)

    func testCredentialAccessStateReflectsBrokerCaches() {
        let keychain = KeychainService(storageURL: makeCredentialURL())
        let service = CredentialAccessService(keychain: keychain)

        // Unknown slots report not configured without consulting the store.
        XCTAssertEqual(
            service.credentialAccessState(service: "svc", account: "never-saved"),
            .notConfigured
        )
        XCTAssertEqual(service.credentialAccessState(service: nil, account: nil), .notConfigured)

        XCTAssertTrue(service.saveCredential("secret-token", service: "svc", account: "acct"))
        XCTAssertEqual(
            service.credentialAccessState(service: "svc", account: "acct"),
            .ready
        )
    }

    // MARK: - Deletion goes through the shared broker

    func testDeleteCredentialRemovesVaultDataThroughBroker() {
        let storageURL = makeCredentialURL()
        let keychain = KeychainService(storageURL: storageURL)
        let service = CredentialAccessService(keychain: keychain)
        XCTAssertTrue(service.saveCredential("secret-token", service: "svc", account: "acct"))

        XCTAssertTrue(service.deleteCredential(service: "svc", account: "acct"))

        XCTAssertNil(
            service.savedCredentialLength(
                service: "svc",
                account: "acct",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )
        XCTAssertEqual(
            service.credentialAccessState(service: "svc", account: "acct"),
            .notConfigured
        )

        // Deletion persists: a fresh service over the same storage sees nothing.
        let fresh = CredentialAccessService(keychain: KeychainService(storageURL: storageURL))
        XCTAssertNil(
            fresh.savedCredentialLength(
                service: "svc",
                account: "acct",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )
        try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
    }

    func testDeleteAllCredentialsRemovesEveryKnownEntryPlusExtraTargets() {
        let storageURL = makeCredentialURL()
        let keychain = KeychainService(storageURL: storageURL)
        let service = CredentialAccessService(keychain: keychain)
        XCTAssertTrue(service.saveCredential("a-value", service: "svc", account: "acct-a"))
        XCTAssertTrue(service.saveCredential("b-value", service: "svc", account: "acct-b"))
        // Saved out-of-band (bypassing the broker) must still be enumerated.
        XCTAssertTrue(keychain.saveToken("c-value", service: "other-svc", account: "acct-c"))

        XCTAssertTrue(
            service.deleteAllCredentials(extraServiceAccounts: [("other-svc", "acct-c")])
        )

        for target in [("svc", "acct-a"), ("svc", "acct-b"), ("other-svc", "acct-c")] {
            XCTAssertNil(
                service.savedCredentialLength(
                    service: target.0,
                    account: target.1,
                    secureStorageReady: true,
                    onLookupStateChanged: {}
                ),
                "credential \(target.1) should have been deleted"
            )
        }

        // A fresh reader over the same storage sees no leftovers.
        let fresh = CredentialAccessService(keychain: KeychainService(storageURL: storageURL))
        for target in [("svc", "acct-a"), ("svc", "acct-b"), ("other-svc", "acct-c")] {
            XCTAssertNil(
                fresh.savedCredentialLength(
                    service: target.0,
                    account: target.1,
                    secureStorageReady: true,
                    onLookupStateChanged: {}
                ),
                "credential \(target.1) should be gone from persistent storage"
            )
        }
        try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
    }

    func testDeleteAllCredentialsOnSecureStoreStaysNonInteractive() {
        let suite = "CredentialAccessServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let recorder = CredentialReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                return nil
            },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let keychain = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )
        let service = CredentialAccessService(keychain: keychain)
        XCTAssertTrue(service.saveCredential("secret-token", service: "svc", account: "acct"))

        XCTAssertTrue(service.deleteAllCredentials())

        XCTAssertNil(
            service.savedCredentialLength(
                service: "svc",
                account: "acct",
                secureStorageReady: true,
                onLookupStateChanged: {}
            )
        )
        // Enumeration and deletion are metadata-level and non-interactive only.
        XCTAssertEqual(recorder.counts.interactiveReadData, 0)
        XCTAssertEqual(recorder.counts.interactiveReadAll, 0)
    }

    private func makeCredentialURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CredentialAccessServiceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }
}

private final class CredentialReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var readDataCount = 0
    private var readAllCount = 0
    private var interactiveReadDataCount = 0
    private var interactiveReadAllCount = 0

    struct Counts {
        var readData = 0
        var readAll = 0
        var interactiveReadData = 0
        var interactiveReadAll = 0
    }

    var counts: Counts {
        lock.lock()
        defer { lock.unlock() }
        return Counts(
            readData: readDataCount,
            readAll: readAllCount,
            interactiveReadData: interactiveReadDataCount,
            interactiveReadAll: interactiveReadAllCount
        )
    }

    func recordReadData(service: String, account: String) {
        _ = service
        _ = account
        lock.lock()
        readDataCount += 1
        lock.unlock()
    }

    func recordReadData(service: String, account: String, interactive: Bool) {
        lock.lock()
        readDataCount += 1
        if interactive {
            interactiveReadDataCount += 1
        }
        lock.unlock()
        _ = (service, account)
    }

    func recordReadAll(service: String) {
        _ = service
        lock.lock()
        readAllCount += 1
        lock.unlock()
    }

    func recordReadAll(service: String, interactive: Bool) {
        lock.lock()
        readAllCount += 1
        if interactive {
            interactiveReadAllCount += 1
        }
        lock.unlock()
        _ = service
    }
}
