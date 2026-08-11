import CommonCrypto
import Foundation

final class BrowserCookieDatabaseReader {
    private struct CookiePathCacheKey: Hashable {
        let browser: KimiBrowserKind
        let includeSafariBinaryCookies: Bool
    }

    private struct ExpiringPathCacheEntry {
        let paths: [String]
        let expiresAt: Date
    }

    private struct ExpiringSafeStoragePasswordCacheEntry {
        let password: String?
        let expiresAt: Date
    }

    private struct SafeStoragePasswordCacheKey: Hashable {
        let browser: KimiBrowserKind
        let allowsInteraction: Bool
    }

    private let fileManager: FileManager
    private let sqliteTimeout: TimeInterval?
    private let cookiePathCacheTTL: TimeInterval
    private let safeStoragePasswordCacheTTL: TimeInterval
    private let now: () -> Date
    private let cookiePathEnumerator: ((KimiBrowserKind, Bool) -> [String])?
    private let safeStoragePasswordReader: (String, String, Bool) -> String?
    private let cookiePathCacheLock = NSLock()
    private let safeStorageCacheLock = NSLock()
    private var cookiePathCache: [CookiePathCacheKey: ExpiringPathCacheEntry] = [:]
    private var safeStorageCache: [SafeStoragePasswordCacheKey: ExpiringSafeStoragePasswordCacheEntry] = [:]

    init(
        fileManager: FileManager = .default,
        sqliteTimeout: TimeInterval? = 5,
        cookiePathCacheTTL: TimeInterval = 60,
        safeStoragePasswordCacheTTL: TimeInterval = 60,
        now: @escaping () -> Date = Date.init,
        cookiePathEnumerator: ((KimiBrowserKind, Bool) -> [String])? = nil,
        safeStoragePasswordReader: @escaping (String, String, Bool) -> String? = { service, account, interactive in
            SecurityCredentialReader.readGenericPassword(
                service: service,
                account: account,
                interactive: interactive
            )
        }
    ) {
        self.fileManager = fileManager
        self.sqliteTimeout = sqliteTimeout
        self.cookiePathCacheTTL = max(0, cookiePathCacheTTL)
        self.safeStoragePasswordCacheTTL = max(0, safeStoragePasswordCacheTTL)
        self.now = now
        self.cookiePathEnumerator = cookiePathEnumerator
        self.safeStoragePasswordReader = safeStoragePasswordReader
    }

    func candidateCookiePaths(
        for browser: KimiBrowserKind,
        includeSafariBinaryCookies: Bool = false,
        bypassCache: Bool = false
    ) -> [String] {
        guard cookiePathCacheTTL > 0 else {
            return enumerateCandidateCookiePaths(
                for: browser,
                includeSafariBinaryCookies: includeSafariBinaryCookies
            )
        }

        let key = CookiePathCacheKey(
            browser: browser,
            includeSafariBinaryCookies: includeSafariBinaryCookies
        )
        let currentDate = now()
        if !bypassCache, let cached = cachedCookiePaths(for: key, now: currentDate) {
            return cached
        }

        let paths = enumerateCandidateCookiePaths(
            for: browser,
            includeSafariBinaryCookies: includeSafariBinaryCookies
        )
        cacheCookiePaths(paths, for: key, now: currentDate)
        return paths
    }

    private func enumerateCandidateCookiePaths(
        for browser: KimiBrowserKind,
        includeSafariBinaryCookies: Bool
    ) -> [String] {
        if let cookiePathEnumerator {
            return Array(Set(cookiePathEnumerator(browser, includeSafariBinaryCookies))).sorted()
        }

        let home = NSHomeDirectory()
        switch browser {
        case .arc:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Arc/User Data")
        case .chrome:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Google/Chrome")
        case .safari:
            var paths = [
                "\(home)/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/Default/Cookies/Cookies.sqlite",
                "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.sqlite",
            ]
            if includeSafariBinaryCookies {
                paths.append("\(home)/Library/Cookies/Cookies.binarycookies")
            }
            return paths
        case .edge:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Microsoft Edge")
        case .brave:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/BraveSoftware/Brave-Browser")
        case .chromium:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Chromium")
        case .firefox:
            return firefoxCookiePaths(base: "\(home)/Library/Application Support/Firefox")
        case .opera:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/com.operasoftware.Opera")
        case .operaGX:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/com.operasoftware.OperaGX")
        case .vivaldi:
            return chromiumCookiePaths(base: "\(home)/Library/Application Support/Vivaldi")
        }
    }

    private func cachedCookiePaths(for key: CookiePathCacheKey, now: Date) -> [String]? {
        cookiePathCacheLock.lock()
        defer { cookiePathCacheLock.unlock() }
        purgeExpiredCookiePathCacheLocked(now: now)
        return cookiePathCache[key]?.paths
    }

    private func cacheCookiePaths(_ paths: [String], for key: CookiePathCacheKey, now: Date) {
        cookiePathCacheLock.lock()
        cookiePathCache[key] = ExpiringPathCacheEntry(
            paths: paths,
            expiresAt: now.addingTimeInterval(cookiePathCacheTTL)
        )
        purgeExpiredCookiePathCacheLocked(now: now)
        cookiePathCacheLock.unlock()
    }

    private func purgeExpiredCookiePathCacheLocked(now: Date) {
        cookiePathCache = cookiePathCache.filter { _, entry in
            entry.expiresAt > now
        }
    }

    func namedCookieValue(
        fromDatabaseAt path: String,
        browser: KimiBrowserKind,
        cookieName: String,
        hostContains: String,
        accessIntent: BrowserCredentialAccessIntent = .interactiveImport
    ) -> String? {
        let queries = [
            "SELECT value, hex(encrypted_value) FROM cookies WHERE name='\(cookieName)' AND host_key LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, hex(encrypted_value) FROM cookies WHERE name='\(cookieName)' AND domain LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, hex(encrypted_value) FROM Cookies WHERE name='\(cookieName)' AND host LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, hex(encrypted_value) FROM Cookies WHERE name='\(cookieName)' AND domain LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC, LENGTH(encrypted_value) DESC;",
            "SELECT value, '' FROM moz_cookies WHERE name='\(cookieName)' AND host LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC;",
            "SELECT value, '' FROM cookies WHERE name='\(cookieName)' AND host LIKE '%\(hostContains)%' ORDER BY LENGTH(value) DESC;",
        ]

        return withTemporaryDatabaseCopy(path: path, prefix: "browser_cookie") { tempDB, sqlite in
            for query in queries {
                guard let raw = runSQLite(executable: sqlite, databasePath: tempDB, query: query) else {
                    continue
                }
                for lineSub in raw.split(separator: "\n") {
                    let line = String(lineSub)
                    guard !line.isEmpty else { continue }
                    let parts = line.components(separatedBy: "\t")
                    let plain = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let encryptedHex = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    let selected: String
                    if !plain.isEmpty {
                        selected = plain
                    } else if let decrypted = decryptChromiumCookieHex(
                        encryptedHex,
                        browser: browser,
                        accessIntent: accessIntent
                    ), !decrypted.isEmpty {
                        selected = decrypted
                    } else {
                        continue
                    }

                    let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let decoded = trimmed.removingPercentEncoding, !decoded.isEmpty {
                        return decoded
                    }
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
            return nil
        }
    }

    func cookieHeader(
        fromDatabaseAt path: String,
        browser: KimiBrowserKind,
        hostContains: String,
        accessIntent: BrowserCredentialAccessIntent = .interactiveImport
    ) -> String? {
        let queries = [
            "SELECT name, value, hex(encrypted_value) FROM cookies WHERE host_key LIKE '%\(hostContains)%' ORDER BY name;",
            "SELECT name, value, hex(encrypted_value) FROM cookies WHERE domain LIKE '%\(hostContains)%' ORDER BY name;",
            "SELECT name, value, hex(encrypted_value) FROM Cookies WHERE host LIKE '%\(hostContains)%' ORDER BY name;",
            "SELECT name, value, hex(encrypted_value) FROM Cookies WHERE domain LIKE '%\(hostContains)%' ORDER BY name;",
            "SELECT name, value, '' FROM moz_cookies WHERE host LIKE '%\(hostContains)%' ORDER BY name;",
            "SELECT name, value, '' FROM cookies WHERE host LIKE '%\(hostContains)%' ORDER BY name;",
        ]

        return withTemporaryDatabaseCopy(path: path, prefix: "browser_cookie_header") { tempDB, sqlite in
            for query in queries {
                guard let raw = runSQLite(executable: sqlite, databasePath: tempDB, query: query) else {
                    continue
                }
                var pairs: [String] = []
                for lineSub in raw.split(separator: "\n") {
                    let line = String(lineSub)
                    let parts = line.components(separatedBy: "\t")
                    guard parts.count >= 3 else { continue }
                    let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    let plain = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    let encryptedHex = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value: String
                    if !plain.isEmpty {
                        value = plain
                    } else if let decrypted = decryptChromiumCookieHex(
                        encryptedHex,
                        browser: browser,
                        accessIntent: accessIntent
                    ), !decrypted.isEmpty {
                        value = decrypted
                    } else {
                        continue
                    }
                    pairs.append("\(name)=\(value)")
                }
                if !pairs.isEmpty {
                    return pairs.joined(separator: "; ")
                }
            }

            return nil
        }
    }

    private func chromiumCookiePaths(base: String) -> [String] {
        guard fileManager.fileExists(atPath: base) else { return [] }
        var candidates: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                let path = url.path
                if path.hasSuffix("/Cookies") &&
                    (path.contains("/Network/") || path.contains("/Default/") || path.contains("/Profile ")) {
                    candidates.append(path)
                }
            }
        }
        return Array(Set(candidates)).sorted()
    }

    private func firefoxCookiePaths(base: String) -> [String] {
        guard fileManager.fileExists(atPath: base) else { return [] }
        var candidates: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator where url.lastPathComponent == "cookies.sqlite" {
                candidates.append(url.path)
            }
        }
        return Array(Set(candidates)).sorted()
    }

    private func withTemporaryDatabaseCopy<T>(
        path: String,
        prefix: String,
        read: (String, String) -> T?
    ) -> T? {
        guard fileManager.fileExists(atPath: path) else { return nil }
        guard let sqlite = resolvedSQLitePath() else { return nil }

        let tempDB = "\(NSTemporaryDirectory())/\(prefix)_\(UUID().uuidString).sqlite"
        defer { try? fileManager.removeItem(atPath: tempDB) }

        do {
            try fileManager.copyItem(atPath: path, toPath: tempDB)
        } catch {
            return nil
        }

        return read(tempDB, sqlite)
    }

    private func runSQLite(executable: String, databasePath: String, query: String) -> String? {
        let arguments = ["-separator", "\t", databasePath, query]
        if let sqliteTimeout {
            guard let result = ShellCommand.run(executable: executable, arguments: arguments, timeout: sqliteTimeout),
                  result.status == 0 else {
                return nil
            }
            return result.stdout
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func decryptChromiumCookieHex(
        _ hex: String,
        browser: KimiBrowserKind,
        accessIntent: BrowserCredentialAccessIntent
    ) -> String? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let encrypted = HexCookieDataParser.data(from: cleaned),
              encrypted.count > 3 else {
            return nil
        }

        let versionPrefix = encrypted.prefix(3)
        guard versionPrefix == Data([0x76, 0x31, 0x30]) || versionPrefix == Data([0x76, 0x31, 0x31]) else {
            return nil
        }

        guard let passphrase = safeStoragePassword(for: browser, accessIntent: accessIntent), !passphrase.isEmpty,
              let key = pbkdf2SHA1(password: passphrase, salt: "saltysalt", rounds: 1003, keyByteCount: 16) else {
            return nil
        }

        let cipher = Data(encrypted.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        guard let decrypted = aesCBCDecrypt(ciphertext: cipher, key: key, iv: iv) else {
            return nil
        }

        if let decoded = String(data: decrypted, encoding: .utf8), !decoded.isEmpty {
            return cleanCookieValue(decoded)
        }

        if decrypted.count > 32 {
            let trimmed = Data(decrypted.dropFirst(32))
            if let decoded = String(data: trimmed, encoding: .utf8), !decoded.isEmpty {
                return cleanCookieValue(decoded)
            }
        }

        return nil
    }

    private func safeStoragePassword(
        for browser: KimiBrowserKind,
        accessIntent: BrowserCredentialAccessIntent
    ) -> String? {
        let currentDate = now()
        let cacheKey = SafeStoragePasswordCacheKey(
            browser: browser,
            allowsInteraction: accessIntent.allowsKeychainInteraction
        )
        if safeStoragePasswordCacheTTL > 0,
           let cached = cachedSafeStoragePassword(for: cacheKey, now: currentDate) {
            return cached
        }

        let labels = safeStorageLabels(for: browser)
        for label in labels {
            if let password = safeStoragePasswordReader(
                label.service,
                label.account,
                accessIntent.allowsKeychainInteraction
            ),
               !password.isEmpty {
                cacheSafeStoragePassword(password, for: cacheKey, now: currentDate)
                if accessIntent.allowsKeychainInteraction {
                    cacheSafeStoragePassword(
                        password,
                        for: SafeStoragePasswordCacheKey(browser: browser, allowsInteraction: false),
                        now: currentDate
                    )
                }
                return password
            }
        }

        cacheSafeStoragePassword(nil, for: cacheKey, now: currentDate)
        return nil
    }

    private func cachedSafeStoragePassword(for key: SafeStoragePasswordCacheKey, now: Date) -> String?? {
        safeStorageCacheLock.lock()
        defer { safeStorageCacheLock.unlock() }
        purgeExpiredSafeStorageCacheLocked(now: now)
        guard let entry = safeStorageCache[key] else {
            return nil
        }
        return entry.password
    }

    private func cacheSafeStoragePassword(_ password: String?, for key: SafeStoragePasswordCacheKey, now: Date) {
        guard safeStoragePasswordCacheTTL > 0 else { return }
        safeStorageCacheLock.lock()
        safeStorageCache[key] = ExpiringSafeStoragePasswordCacheEntry(
            password: password,
            expiresAt: now.addingTimeInterval(safeStoragePasswordCacheTTL)
        )
        purgeExpiredSafeStorageCacheLocked(now: now)
        safeStorageCacheLock.unlock()
    }

    private func purgeExpiredSafeStorageCacheLocked(now: Date) {
        safeStorageCache = safeStorageCache.filter { _, entry in
            entry.expiresAt > now
        }
    }

    private func safeStorageLabels(for browser: KimiBrowserKind) -> [(service: String, account: String)] {
        switch browser {
        case .arc:
            return [
                ("Arc Safe Storage", "Arc"),
                ("Arc Safe Storage", "Arc Beta"),
                ("Arc Safe Storage", "Arc Canary"),
                ("Arc Safe Storage", "com.thebrowser.Browser"),
            ]
        case .chrome:
            return [("Chrome Safe Storage", "Chrome")]
        case .edge:
            return [("Microsoft Edge Safe Storage", "Microsoft Edge")]
        case .brave:
            return [("Brave Safe Storage", "Brave")]
        case .chromium:
            return [("Chromium Safe Storage", "Chromium")]
        case .opera:
            return [
                ("Opera Safe Storage", "Opera"),
                ("Opera Safe Storage", "Opera Stable"),
            ]
        case .operaGX:
            return [
                ("Opera Safe Storage", "Opera GX Stable"),
                ("Opera Safe Storage", "Opera GX"),
            ]
        case .vivaldi:
            return [("Vivaldi Safe Storage", "Vivaldi")]
        case .firefox:
            return []
        case .safari:
            return []
        }
    }

    private func pbkdf2SHA1(password: String, salt: String, rounds: Int, keyByteCount: Int) -> Data? {
        guard let saltData = salt.data(using: .utf8) else {
            return nil
        }

        var keyData = Data(repeating: 0, count: keyByteCount)
        let keyLength = keyData.count
        let result = keyData.withUnsafeMutableBytes { keyBytes in
            password.utf8CString.withUnsafeBytes { passBytes in
                saltData.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.bindMemory(to: Int8.self).baseAddress,
                        passBytes.count - 1,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(rounds),
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }

        return result == kCCSuccess ? keyData : nil
    }

    private func aesCBCDecrypt(ciphertext: Data, key: Data, iv: Data) -> Data? {
        var outLength = 0
        var outData = Data(repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let outCapacity = outData.count
        let status = outData.withUnsafeMutableBytes { outBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outBytes.baseAddress,
                            outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        outData.count = outLength
        return outData
    }

    private func cleanCookieValue(_ value: String) -> String {
        var index = value.startIndex
        while index < value.endIndex, value[index].unicodeScalars.allSatisfy({ $0.value < 0x20 }) {
            index = value.index(after: index)
        }
        return String(value[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedSQLitePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/sqlite3",
            "/usr/local/bin/sqlite3",
            "/usr/bin/sqlite3",
        ]
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }
}

private enum HexCookieDataParser {
    static func data(from hexString: String) -> Data? {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        for _ in 0..<(cleaned.count / 2) {
            let next = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
