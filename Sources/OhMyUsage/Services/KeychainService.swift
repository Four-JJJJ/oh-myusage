import Foundation
import LocalAuthentication
import OhMyUsageDomain
import OhMyUsageInfrastructure
import Security

final class KeychainService: @unchecked Sendable {
    struct SecureStoreAdapter {
        var readData: @Sendable (_ service: String, _ account: String, _ interactive: Bool) -> Data?
        var readAll: @Sendable (_ service: String, _ interactive: Bool) -> [String: String]?
        var saveData: @Sendable (_ data: Data, _ service: String, _ account: String, _ interactive: Bool) -> Bool
        var deleteItem: @Sendable (_ service: String, _ account: String) -> Void
        var deleteAll: @Sendable (_ service: String) -> Void

        static let live = SecureStoreAdapter(
            readData: { service, account, interactive in
                KeychainService.liveReadData(service: service, account: account, interactive: interactive)
            },
            readAll: { service, interactive in
                KeychainService.liveReadAll(service: service, interactive: interactive)
            },
            saveData: { data, service, account, interactive in
                KeychainService.liveSaveData(data, service: service, account: account, interactive: interactive)
            },
            deleteItem: { service, account in
                KeychainService.liveDeleteItem(service: service, account: account)
            },
            deleteAll: { service in
                KeychainService.liveDeleteAll(service: service)
            }
        )
    }

    static let defaultServiceName = CredentialStoreServiceNames.defaultServiceName
    static let legacyServiceName = CredentialStoreServiceNames.legacyServiceName
    static let historicalLegacyServiceNames = CredentialStoreServiceNames.historicalLegacyServiceNames
    private static let vaultAccount = "__credential_vault__"
    private static let legacyMigrationDefaultsKey = "OhMyUsage.Keychain.LegacyMigrationComplete"
    private static let secureAccessPreparedDefaultsKey = "OhMyUsage.Keychain.SecureAccessPrepared"
    private static let credentialLengthDefaultsKey = "OhMyUsage.Keychain.CredentialLengths"

    private let lock = NSLock()
    private let fileManager: FileManager
    private let storageURL: URL?
    private let useFileStorage: Bool
    private let defaults: UserDefaults
    private let secureStore: SecureStoreAdapter
    private var tokenCache: [String: String] = [:]
    private var missingCache: Set<String> = []
    private var credentialLengthCache: [String: Int]?
    private var secureVaultLoaded = false

    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil,
        defaults: UserDefaults = .standard,
        forceSecureStore: Bool = false,
        secureStore: SecureStoreAdapter = .live
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.secureStore = secureStore
        let resolvedStorageURL = storageURL ?? Self.defaultTestingStorageURL(
            fileManager: fileManager,
            forceSecureStore: forceSecureStore
        )
        self.storageURL = resolvedStorageURL
        self.useFileStorage = !forceSecureStore && resolvedStorageURL != nil
        if useFileStorage {
            loadFromDisk()
        }
    }

    private static func defaultTestingStorageURL(
        fileManager: FileManager,
        forceSecureStore: Bool
    ) -> URL? {
        guard !forceSecureStore else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTest_SESSION_IDENTIFIER"] != nil ||
            ProcessInfo.processInfo.processName.lowercased().contains("xctest") ||
            Bundle.main.bundlePath.lowercased().contains(".xctest") else {
            return nil
        }
        return fileManager.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("keychain.json")
    }

    private func cacheKey(service: String, account: String) -> String {
        "\(normalizedServiceName(service))::\(account)"
    }

    func cachedToken(service: String, account: String) -> String? {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)
        lock.lock()
        defer { lock.unlock() }
        return tokenCache[key]
    }

    func cachedCredentialLength(service: String, account: String) -> Int? {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

        lock.lock()
        if let token = tokenCache[key], !token.isEmpty {
            lock.unlock()
            return token.count
        }
        lock.unlock()

        return credentialLengthSnapshot()[key]
    }

    func readToken(service: String, account: String) -> String? {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

        lock.lock()
        if let cached = tokenCache[key] {
            lock.unlock()
            return cached
        }
        if missingCache.contains(key) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let token: String?
        if useFileStorage {
            token = readFromDisk(service: normalizedService, account: account)
        } else {
            token = readFromVault(service: normalizedService, account: account)
                ?? readCurrentServiceAndMigrateIfPossible(service: normalizedService, account: account)
                ?? readLegacyServiceAndMigrateIfPossible(account: account)
            if token != nil {
                markSecureStorePrepared()
            }
        }

        lock.lock()
        if let token, !token.isEmpty {
            tokenCache[key] = token
            missingCache.remove(key)
        } else {
            missingCache.insert(key)
        }
        lock.unlock()
        if let token, !token.isEmpty, !useFileStorage {
            recordCredentialLengths([key: token.count])
        }
        return token
    }

    @discardableResult
    func saveToken(_ token: String, service: String, account: String) -> Bool {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

        lock.lock()
        tokenCache[key] = token
        missingCache.remove(key)
        let snapshot = tokenCache
        lock.unlock()

        let ok: Bool
        if useFileStorage {
            ok = persist(snapshot)
        } else {
            ok = persistSecureSnapshot(snapshot, interactive: false)
        }
        if ok {
            if !useFileStorage {
                recordCredentialLengths([key: token.count])
                markSecureStorePrepared()
            }
        }
        return ok
    }

    @discardableResult
    func deleteToken(service: String, account: String) -> Bool {
        let normalizedService = normalizedServiceName(service)
        let key = cacheKey(service: normalizedService, account: account)

        lock.lock()
        tokenCache.removeValue(forKey: key)
        missingCache.insert(key)
        let snapshot = tokenCache
        lock.unlock()

        removeCredentialLength(for: key)
        if useFileStorage {
            return persist(snapshot)
        }

        let ok = persistSecureSnapshot(snapshot, interactive: false)
        deleteSecureStoreItem(service: normalizedService, account: account)
        return ok
    }

    private var hasPreparedSecureStoreAccess: Bool {
        useFileStorage || defaults.bool(forKey: Self.secureAccessPreparedDefaultsKey)
    }

    private func markSecureStorePrepared() {
        defaults.set(true, forKey: Self.secureAccessPreparedDefaultsKey)
    }

    private func normalizedServiceName(_ service: String) -> String {
        let trimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || Self.isLegacyServiceName(trimmed) {
            return Self.defaultServiceName
        }
        return trimmed
    }

    static func isLegacyServiceName(_ service: String) -> Bool {
        CredentialStoreServiceNames.isLegacyServiceName(service)
    }

    private func readFromVault(service: String, account: String) -> String? {
        loadSecureVaultIfNeeded(interactive: false)

        let key = cacheKey(service: service, account: account)
        lock.lock()
        defer { lock.unlock() }
        return tokenCache[key]
    }

    private func readCurrentServiceAndMigrateIfPossible(service: String, account: String) -> String? {
        guard service != Self.defaultServiceName || account != Self.vaultAccount,
              let token = readFromSecureStore(service: service, account: account, interactive: false),
              !token.isEmpty else {
            return nil
        }

        _ = storeInVault(token: token, service: service, account: account)
        return token
    }

    private func readLegacyServiceAndMigrateIfPossible(account: String) -> String? {
        guard account != Self.vaultAccount else {
            return nil
        }

        for legacyService in Self.historicalLegacyServiceNames {
            guard let token = readFromSecureStore(service: legacyService, account: account, interactive: false),
                  !token.isEmpty else {
                continue
            }
            if storeInVault(token: token, service: Self.defaultServiceName, account: account) {
                deleteSecureStoreItem(service: legacyService, account: account)
            }
            return token
        }

        return nil
    }

    private func loadSecureVaultIfNeeded(interactive: Bool) {
        lock.lock()
        let shouldRetryInteractive = interactive && secureVaultLoaded && tokenCache.isEmpty
        if secureVaultLoaded && !shouldRetryInteractive {
            lock.unlock()
            return
        }
        lock.unlock()

        let snapshot = readVaultSnapshotFromSecureStore(interactive: interactive)
        if let snapshot, !snapshot.isEmpty {
            mergeIntoCache(snapshot)
        }

        let currentItems = snapshot == nil
            ? readCurrentServiceItemsForMigration(interactive: interactive) ?? [:]
            : [:]
        if !currentItems.isEmpty {
            if !mergeIntoVault(currentItems) {
                mergeIntoCache(currentItems)
            }
        }

        let didLoadAccessibleState = snapshot != nil || !currentItems.isEmpty
        lock.lock()
        secureVaultLoaded = didLoadAccessibleState
        lock.unlock()
        if didLoadAccessibleState {
            markSecureStorePrepared()
        }
    }

    func prepareSecureStoreAccess() -> Bool {
        let vaultSnapshot = readVaultSnapshotFromSecureStore(interactive: true)
        if let vaultSnapshot {
            mergeIntoCache(vaultSnapshot)
        }

        let currentItems = vaultSnapshot == nil
            ? readCurrentServiceItemsForMigration(interactive: false) ?? [:]
            : [:]
        if !currentItems.isEmpty {
            mergeIntoCache(currentItems)
        }

        let legacyMigration = readLegacyItemsForMigration(interactive: false)
        if let legacyMigration, !legacyMigration.items.isEmpty {
            mergeIntoCache(legacyMigration.items)
        }

        let hasVault = vaultSnapshot != nil
        let needsPersist = !hasVault || !currentItems.isEmpty || !(legacyMigration?.items.isEmpty ?? true)
        let didPersistSnapshot: Bool
        if needsPersist {
            didPersistSnapshot = persistSecureSnapshot(cachedSnapshot(), interactive: !hasVault)
        } else {
            didPersistSnapshot = true
        }

        guard hasVault || didPersistSnapshot else {
            return false
        }

        finishSecureStorePreparation()
        if didPersistSnapshot, let legacyMigration {
            completeLegacyMigration(accountsByService: legacyMigration.accountsByService)
        }
        return true
    }

    func isSecureStoreReady() -> Bool {
        guard !useFileStorage else {
            return true
        }
        lock.lock()
        let hasCachedCredentials = !tokenCache.isEmpty || secureVaultLoaded
        lock.unlock()
        return hasCachedCredentials || hasPreparedSecureStoreAccess
    }

    func resetAllStoredCredentials() {
        guard !useFileStorage else {
            lock.lock()
            tokenCache.removeAll()
            missingCache.removeAll()
            credentialLengthCache = nil
            secureVaultLoaded = false
            lock.unlock()
            defaults.removeObject(forKey: Self.credentialLengthDefaultsKey)
            if let storageURL {
                try? fileManager.removeItem(at: storageURL)
            }
            return
        }

        deleteAllSecureStoreItems(service: Self.defaultServiceName)
        for legacyService in Self.historicalLegacyServiceNames {
            deleteAllSecureStoreItems(service: legacyService)
        }
        defaults.removeObject(forKey: Self.legacyMigrationDefaultsKey)
        for legacyService in Self.historicalLegacyServiceNames {
            defaults.removeObject(forKey: Self.legacyMigrationDefaultsKey(for: legacyService))
        }
        defaults.removeObject(forKey: Self.secureAccessPreparedDefaultsKey)
        defaults.removeObject(forKey: Self.credentialLengthDefaultsKey)

        lock.lock()
        tokenCache.removeAll()
        missingCache.removeAll()
        credentialLengthCache = nil
        secureVaultLoaded = false
        lock.unlock()
    }

    private func readCurrentServiceItemsForMigration(interactive: Bool) -> [String: String]? {
        readAllFromSecureStore(service: Self.defaultServiceName, interactive: interactive)?
            .filter({ $0.key != Self.vaultAccount && !$0.key.isEmpty && !$0.value.isEmpty })
            .reduce(into: [String: String]()) { partialResult, entry in
                partialResult[cacheKey(service: Self.defaultServiceName, account: entry.key)] = entry.value
            }
    }

    private func readLegacyItemsForMigration(
        interactive: Bool
    ) -> (items: [String: String], accountsByService: [(service: String, accounts: [String])])? {
        var normalizedItems: [String: String] = [:]
        var accountsByService: [(service: String, accounts: [String])] = []

        for legacyService in Self.historicalLegacyServiceNames where !isLegacyMigrationComplete(for: legacyService) {
            guard let legacyItems = readAllFromSecureStore(service: legacyService, interactive: interactive)?
                .filter({ !$0.key.isEmpty && !$0.value.isEmpty }) else {
                continue
            }
            for entry in legacyItems {
                normalizedItems[cacheKey(service: Self.defaultServiceName, account: entry.key)] = entry.value
            }
            accountsByService.append((service: legacyService, accounts: Array(legacyItems.keys)))
        }

        guard !normalizedItems.isEmpty || !accountsByService.isEmpty else {
            return nil
        }

        return (normalizedItems, accountsByService)
    }

    private func completeLegacyMigration(accountsByService: [(service: String, accounts: [String])]) {
        for record in accountsByService {
            for account in record.accounts {
                deleteSecureStoreItem(service: record.service, account: account)
            }
            markLegacyMigrationComplete(for: record.service)
        }
    }

    private func isLegacyMigrationComplete(for service: String) -> Bool {
        if service == Self.legacyServiceName, defaults.bool(forKey: Self.legacyMigrationDefaultsKey) {
            return true
        }
        return defaults.bool(forKey: Self.legacyMigrationDefaultsKey(for: service))
    }

    private func markLegacyMigrationComplete(for service: String) {
        defaults.set(true, forKey: Self.legacyMigrationDefaultsKey(for: service))
        if service == Self.legacyServiceName {
            defaults.set(true, forKey: Self.legacyMigrationDefaultsKey)
        }
    }

    private static func legacyMigrationDefaultsKey(for service: String) -> String {
        let suffix = service
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        return "\(legacyMigrationDefaultsKey).\(suffix)"
    }

    private func mergeIntoVault(_ items: [String: String]) -> Bool {
        guard !items.isEmpty else { return true }

        lock.lock()
        var merged = tokenCache
        for (key, value) in items where !value.isEmpty {
            merged[key] = value
        }
        lock.unlock()

        guard persistSecureSnapshot(merged, interactive: false) else {
            return false
        }

        mergeIntoCache(items)
        return true
    }

    private func cachedSnapshot() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return tokenCache
    }

    private func finishSecureStorePreparation() {
        lock.lock()
        missingCache.removeAll()
        secureVaultLoaded = true
        lock.unlock()
        markSecureStorePrepared()
    }

    private func storeInVault(token: String, service: String, account: String) -> Bool {
        mergeIntoVault([cacheKey(service: service, account: account): token])
    }

    private func mergeIntoCache(_ items: [String: String]) {
        var lengths: [String: Int] = [:]
        lock.lock()
        for (key, value) in items where !value.isEmpty {
            tokenCache[key] = value
            missingCache.remove(key)
            lengths[key] = value.count
        }
        lock.unlock()
        if !lengths.isEmpty {
            recordCredentialLengths(lengths)
        }
    }

    private func credentialLengthSnapshot() -> [String: Int] {
        lock.lock()
        if let credentialLengthCache {
            lock.unlock()
            return credentialLengthCache
        }
        lock.unlock()

        let raw = defaults.dictionary(forKey: Self.credentialLengthDefaultsKey) ?? [:]
        let snapshot = raw.reduce(into: [String: Int]()) { partialResult, entry in
            if let length = entry.value as? Int {
                partialResult[entry.key] = length
            } else if let number = entry.value as? NSNumber {
                partialResult[entry.key] = number.intValue
            }
        }

        lock.lock()
        if let credentialLengthCache {
            lock.unlock()
            return credentialLengthCache
        }
        credentialLengthCache = snapshot
        lock.unlock()
        return snapshot
    }

    private func recordCredentialLengths(_ lengths: [String: Int]) {
        guard !lengths.isEmpty else { return }
        var snapshot = credentialLengthSnapshot()
        for (key, length) in lengths where length > 0 {
            snapshot[key] = length
        }
        lock.lock()
        credentialLengthCache = snapshot
        lock.unlock()
        defaults.set(snapshot, forKey: Self.credentialLengthDefaultsKey)
    }

    private func removeCredentialLength(for key: String) {
        var snapshot = credentialLengthSnapshot()
        snapshot.removeValue(forKey: key)
        lock.lock()
        credentialLengthCache = snapshot
        lock.unlock()
        defaults.set(snapshot, forKey: Self.credentialLengthDefaultsKey)
    }

    private func readVaultSnapshotFromSecureStore(interactive: Bool) -> [String: String]? {
        guard let data = readDataFromSecureStore(
            service: Self.defaultServiceName,
            account: Self.vaultAccount,
            interactive: interactive
        ) else {
            return nil
        }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private func persistSecureSnapshot(_ snapshot: [String: String], interactive: Bool) -> Bool {
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(snapshot)
        } catch {
            return false
        }
        return saveDataToSecureStore(
            encoded,
            service: Self.defaultServiceName,
            account: Self.vaultAccount,
            interactive: interactive
        )
    }

    private func readFromSecureStore(service: String, account: String, interactive: Bool) -> String? {
        guard let data = readDataFromSecureStore(service: service, account: account, interactive: interactive),
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private func readDataFromSecureStore(service: String, account: String, interactive: Bool) -> Data? {
        secureStore.readData(service, account, interactive)
    }

    private func readAllFromSecureStore(service: String, interactive: Bool) -> [String: String]? {
        secureStore.readAll(service, interactive)
    }

    private func saveDataToSecureStore(_ data: Data, service: String, account: String, interactive: Bool) -> Bool {
        secureStore.saveData(data, service, account, interactive)
    }

    private func deleteSecureStoreItem(service: String, account: String) {
        secureStore.deleteItem(service, account)
    }

    private func deleteAllSecureStoreItems(service: String) {
        secureStore.deleteAll(service)
    }

    private func readFromDisk(service: String, account: String) -> String? {
        tokenCache["\(service)::\(account)"]
    }

    private func loadFromDisk() {
        guard let storageURL,
              fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }

        lock.lock()
        tokenCache = decoded
        missingCache.removeAll()
        lock.unlock()
    }

    private func persist(_ snapshot: [String: String]) -> Bool {
        guard let storageURL else { return false }
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func liveReadData(service: String, account: String, interactive: Bool) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authenticationContext(interactive: interactive)
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              !data.isEmpty else {
            return nil
        }
        return data
    }

    private static func liveReadAll(service: String, interactive: Bool) -> [String: String]? {
        let context = authenticationContext(interactive: interactive)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }

        return tokensFromEnumeratedKeychainRows(item)
    }

    static func tokensFromEnumeratedKeychainRows(_ item: CFTypeRef?) -> [String: String]? {
        let rows: [[String: Any]]
        if let array = item as? [[String: Any]] {
            rows = array
        } else if let dict = item as? [String: Any] {
            rows = [dict]
        } else {
            return nil
        }

        var result: [String: String] = [:]
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String,
                  let data = row[kSecValueData as String] as? Data,
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty else {
                continue
            }
            result[account] = token
        }
        return result
    }

    private static func liveSaveData(_ data: Data, service: String, account: String, interactive: Bool) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: authenticationContext(interactive: interactive)
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            SecItemDelete(query as CFDictionary)
        }

        let addAttributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseAuthenticationContext as String: authenticationContext(interactive: interactive)
        ]
        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private static func liveDeleteItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func liveDeleteAll(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func authenticationContext(interactive: Bool) -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = !interactive
        return context
    }
}

extension KeychainService: CredentialStoring {}

extension KeychainService: UsageCredentialStore {
    func credential(for providerID: UsageProviderIdentity) async throws -> String? {
        readToken(service: Self.defaultServiceName, account: providerID.rawValue)
    }

    func saveCredential(_ credential: String, for providerID: UsageProviderIdentity) async throws {
        _ = saveToken(credential, service: Self.defaultServiceName, account: providerID.rawValue)
    }

    func removeCredential(for providerID: UsageProviderIdentity) async throws {
        _ = deleteToken(service: Self.defaultServiceName, account: providerID.rawValue)
    }
}
