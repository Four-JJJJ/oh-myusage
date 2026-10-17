import XCTest
import Security
@testable import OhMyUsage

final class KeychainServiceTests: XCTestCase {
    func testEnumeratedKeychainRowsReuseReturnedData() {
        let rows: [[String: Any]] = [
            [
                kSecAttrAccount as String: "account-a",
                kSecValueData as String: Data("token-a".utf8)
            ],
            [
                kSecAttrAccount as String: "account-b",
                kSecValueData as String: Data("token-b".utf8)
            ],
            [
                kSecAttrAccount as String: "missing-data"
            ]
        ]

        let result = KeychainService.tokensFromEnumeratedKeychainRows(rows as CFTypeRef)

        XCTAssertEqual(result, [
            "account-a": "token-a",
            "account-b": "token-b"
        ])
    }

    func testLegacyServiceNameIsNormalizedToOhMyUsage() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = KeychainService(storageURL: tempURL)
        XCTAssertTrue(store.saveToken("secret", service: KeychainService.legacyServiceName, account: "demo"))

        let reloaded = KeychainService(storageURL: tempURL)
        XCTAssertEqual(reloaded.readToken(service: KeychainService.defaultServiceName, account: "demo"), "secret")
        XCTAssertEqual(reloaded.readToken(service: KeychainService.legacyServiceName, account: "demo"), "secret")
    }

    func testHistoricalAIPlanMonitorServiceNamesNormalizeToOhMyUsage() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("credentials.json")
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = KeychainService(storageURL: tempURL)
        XCTAssertTrue(store.saveToken("secret-a", service: "AI Plan Monitor", account: "demo-a"))
        XCTAssertTrue(store.saveToken("secret-b", service: "AIPlanMonitor", account: "demo-b"))

        let reloaded = KeychainService(storageURL: tempURL)
        XCTAssertEqual(reloaded.readToken(service: KeychainService.defaultServiceName, account: "demo-a"), "secret-a")
        XCTAssertEqual(reloaded.readToken(service: KeychainService.defaultServiceName, account: "demo-b"), "secret-b")
    }

    func testPrepareSecureStoreAccessMigratesHistoricalAIPlanMonitorServices() throws {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let aiPlanKey = "\(KeychainService.defaultServiceName)::ai-plan-account"
        let aiPlanNoSpaceKey = "\(KeychainService.defaultServiceName)::aiplan-account"
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

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertEqual(recorder.latestSavedVaultSnapshot?[aiPlanKey], "ai-plan-token")
        XCTAssertEqual(recorder.latestSavedVaultSnapshot?[aiPlanNoSpaceKey], "aiplan-token")
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "ai-plan-account"), "ai-plan-token")
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "aiplan-account"), "aiplan-token")
    }

    func testReadTokenMigratesHistoricalServiceItemByAccount() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let savedKey = "\(KeychainService.defaultServiceName)::legacy-account"
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                if service == "AI Plan Monitor", account == "legacy-account" {
                    return Data("legacy-token".utf8)
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

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "legacy-account"), "legacy-token")
        XCTAssertEqual(recorder.latestSavedVaultSnapshot?[savedKey], "legacy-token")
    }

    func testPrepareSecureStoreAccessReloadsVaultAfterNonInteractiveMiss() throws {
        let defaults = makeDefaults()
        let snapshot = [
            "\(KeychainService.defaultServiceName)::open.ailinyu.de/session-cookie": "cookie-value"
        ]
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                guard service == KeychainService.defaultServiceName,
                      account == "__credential_vault__",
                      interactive else {
                    return nil
                }
                return encodedSnapshot
            },
            readAll: { _, _ in nil },
            saveData: { _, _, _, _ in true },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertNil(
            store.readToken(
                service: KeychainService.defaultServiceName,
                account: "open.ailinyu.de/session-cookie"
            )
        )

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertEqual(
            store.readToken(
                service: KeychainService.defaultServiceName,
                account: "open.ailinyu.de/session-cookie"
            ),
            "cookie-value"
        )
    }

    func testPrepareSecureStoreAccessKeepsMigrationNonInteractive() throws {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let looseKey = "\(KeychainService.defaultServiceName)::loose-account"
        let legacyKey = "\(KeychainService.defaultServiceName)::legacy-account"
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, interactive in
                recorder.recordReadData(service: service, account: account, interactive: interactive)
                return nil
            },
            readAll: { service, interactive in
                recorder.recordReadAll(service: service, interactive: interactive)
                guard !interactive else { return nil }
                if service == KeychainService.defaultServiceName {
                    return [
                        "__credential_vault__": "ignored",
                        "loose-account": "loose-token"
                    ]
                }
                if service == KeychainService.legacyServiceName {
                    return ["legacy-account": "legacy-token"]
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

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertTrue(store.prepareSecureStoreAccess())
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "loose-account"), "loose-token")
        XCTAssertEqual(store.readToken(service: KeychainService.defaultServiceName, account: "legacy-account"), "legacy-token")
        XCTAssertEqual(recorder.counts.interactiveReadData, 1)
        XCTAssertEqual(recorder.counts.interactiveReadAll, 0)
        XCTAssertEqual(recorder.counts.interactiveSaveData, 1)
        XCTAssertEqual(recorder.latestSavedVaultSnapshot?[looseKey], "loose-token")
        XCTAssertEqual(recorder.latestSavedVaultSnapshot?[legacyKey], "legacy-token")
    }

    func testIsSecureStoreReadyDoesNotReadKeychainWithoutPreparedDefaults() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
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

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertFalse(defaults.bool(forKey: "OhMyUsage.Keychain.SecureAccessPrepared"))
        XCTAssertFalse(store.isSecureStoreReady())
        XCTAssertFalse(defaults.bool(forKey: "OhMyUsage.Keychain.SecureAccessPrepared"))
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
    }

    func testIsSecureStoreReadyUsesPreparedFlagWithoutReadingKeychain() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "OhMyUsage.Keychain.SecureAccessPrepared")
        let recorder = KeychainReadRecorder()
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

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertTrue(store.isSecureStoreReady())
        XCTAssertEqual(recorder.counts.readData, 0)
        XCTAssertEqual(recorder.counts.readAll, 0)
    }

    func testCachedCredentialLengthMemoizesDefaultsSnapshotUntilLocalWrite() {
        let defaults = makeDefaults()
        let recorder = KeychainReadRecorder()
        let adapter = KeychainService.SecureStoreAdapter(
            readData: { service, account, _ in
                recorder.recordReadData(service: service, account: account)
                return nil
            },
            readAll: { service, _ in
                recorder.recordReadAll(service: service)
                return nil
            },
            saveData: { data, service, account, interactive in
                recorder.recordSaveData(data: data, service: service, account: account, interactive: interactive)
                return true
            },
            deleteItem: { _, _ in },
            deleteAll: { _ in }
        )
        let account = "display-account"
        let key = "\(KeychainService.defaultServiceName)::\(account)"
        defaults.set([key: 12], forKey: "OhMyUsage.Keychain.CredentialLengths")

        let store = KeychainService(
            defaults: defaults,
            forceSecureStore: true,
            secureStore: adapter
        )

        XCTAssertEqual(
            store.cachedCredentialLength(service: KeychainService.defaultServiceName, account: account),
            12
        )

        defaults.set([key: 99], forKey: "OhMyUsage.Keychain.CredentialLengths")

        XCTAssertEqual(
            store.cachedCredentialLength(service: KeychainService.defaultServiceName, account: account),
            12
        )
        XCTAssertTrue(store.saveToken("updated-secret", service: KeychainService.defaultServiceName, account: account))
        XCTAssertEqual(
            store.cachedCredentialLength(service: KeychainService.defaultServiceName, account: account),
            "updated-secret".count
        )
        XCTAssertEqual(recorder.counts.readData, 1)
        XCTAssertEqual(recorder.counts.readAll, 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "KeychainServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class KeychainReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var readDataCount = 0
    private var readAllCount = 0
    private var saveDataCount = 0
    private var interactiveReadDataCount = 0
    private var interactiveReadAllCount = 0
    private var interactiveSaveDataCount = 0
    private var savedVaultSnapshots: [[String: String]] = []

    var counts: (
        readData: Int,
        readAll: Int,
        saveData: Int,
        interactiveReadData: Int,
        interactiveReadAll: Int,
        interactiveSaveData: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (
            readDataCount,
            readAllCount,
            saveDataCount,
            interactiveReadDataCount,
            interactiveReadAllCount,
            interactiveSaveDataCount
        )
    }

    var latestSavedVaultSnapshot: [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return savedVaultSnapshots.last
    }

    func recordReadData(service: String, account: String, interactive: Bool = false) {
        _ = service
        _ = account
        lock.lock()
        readDataCount += 1
        if interactive {
            interactiveReadDataCount += 1
        }
        lock.unlock()
    }

    func recordReadAll(service: String, interactive: Bool = false) {
        _ = service
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
