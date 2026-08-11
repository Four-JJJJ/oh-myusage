import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class BrowserCredentialServiceTests: XCTestCase {
    func testBrowserCookieDatabaseReaderReadsNamedCookieFromPlainCookiesSchema() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, host TEXT);
            INSERT INTO cookies VALUES ('sessionKey', 'plain-token', '.claude.ai');
            INSERT INTO cookies VALUES ('other', 'ignored', '.example.com');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let reader = BrowserCookieDatabaseReader()
        let value = reader.namedCookieValue(
            fromDatabaseAt: databasePath,
            browser: .firefox,
            cookieName: "sessionKey",
            hostContains: "claude.ai"
        )

        XCTAssertEqual(value, "plain-token")
    }

    func testBrowserCookieDatabaseReaderBuildsCookieHeaderFromPlainCookiesSchema() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, host TEXT);
            INSERT INTO cookies VALUES ('a', '1', '.kimi.com');
            INSERT INTO cookies VALUES ('b', '2', '.www.kimi.com');
            INSERT INTO cookies VALUES ('ignored', 'x', '.example.com');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let reader = BrowserCookieDatabaseReader()
        let header = reader.cookieHeader(
            fromDatabaseAt: databasePath,
            browser: .firefox,
            hostContains: "kimi.com"
        )

        XCTAssertEqual(header, "a=1; b=2")
    }

    func testCookiePathEnumerationIsCachedWithinTTL() {
        var now = Date(timeIntervalSince1970: 2_000)
        var enumerationCount = 0
        let reader = BrowserCookieDatabaseReader(
            cookiePathCacheTTL: 30,
            now: { now },
            cookiePathEnumerator: { browser, includeSafariBinaryCookies in
                XCTAssertEqual(browser, .chrome)
                XCTAssertFalse(includeSafariBinaryCookies)
                enumerationCount += 1
                return ["/tmp/chrome/Profile 1/Network/Cookies"]
            }
        )

        XCTAssertEqual(
            reader.candidateCookiePaths(for: .chrome),
            ["/tmp/chrome/Profile 1/Network/Cookies"]
        )
        now = now.addingTimeInterval(10)
        XCTAssertEqual(
            reader.candidateCookiePaths(for: .chrome),
            ["/tmp/chrome/Profile 1/Network/Cookies"]
        )
        XCTAssertEqual(enumerationCount, 1)
    }

    func testCookiePathEnumerationRefreshesAfterTTL() {
        var now = Date(timeIntervalSince1970: 2_000)
        var enumerationCount = 0
        let reader = BrowserCookieDatabaseReader(
            cookiePathCacheTTL: 30,
            now: { now },
            cookiePathEnumerator: { _, _ in
                enumerationCount += 1
                return ["/tmp/chrome/Profile \(enumerationCount)/Network/Cookies"]
            }
        )

        XCTAssertEqual(
            reader.candidateCookiePaths(for: .chrome),
            ["/tmp/chrome/Profile 1/Network/Cookies"]
        )

        now = now.addingTimeInterval(31)

        XCTAssertEqual(
            reader.candidateCookiePaths(for: .chrome),
            ["/tmp/chrome/Profile 2/Network/Cookies"]
        )
        XCTAssertEqual(enumerationCount, 2)
    }

    func testCookiePathEnumerationCacheSeparatesSafariBinaryCookieDimension() {
        var enumerationKeys: [String] = []
        let reader = BrowserCookieDatabaseReader(
            cookiePathCacheTTL: 30,
            cookiePathEnumerator: { browser, includeSafariBinaryCookies in
                enumerationKeys.append("\(browser.rawValue):\(includeSafariBinaryCookies)")
                return includeSafariBinaryCookies
                    ? ["/tmp/safari/Cookies.sqlite", "/tmp/safari/Cookies.binarycookies"]
                    : ["/tmp/safari/Cookies.sqlite"]
            }
        )

        XCTAssertEqual(
            reader.candidateCookiePaths(for: .safari),
            ["/tmp/safari/Cookies.sqlite"]
        )
        XCTAssertEqual(
            reader.candidateCookiePaths(for: .safari, includeSafariBinaryCookies: true),
            ["/tmp/safari/Cookies.binarycookies", "/tmp/safari/Cookies.sqlite"]
        )
        XCTAssertEqual(
            reader.candidateCookiePaths(for: .safari),
            ["/tmp/safari/Cookies.sqlite"]
        )
        XCTAssertEqual(
            reader.candidateCookiePaths(for: .safari, includeSafariBinaryCookies: true),
            ["/tmp/safari/Cookies.binarycookies", "/tmp/safari/Cookies.sqlite"]
        )
        XCTAssertEqual(enumerationKeys, ["safari:false", "safari:true"])
    }

    func testDefaultCookiePathCacheSurvivesThirtySeconds() {
        var now = Date(timeIntervalSince1970: 2_000)
        var enumerationCount = 0
        let reader = BrowserCookieDatabaseReader(
            now: { now },
            cookiePathEnumerator: { _, _ in
                enumerationCount += 1
                return ["/tmp/chrome/Profile \(enumerationCount)/Network/Cookies"]
            }
        )

        XCTAssertEqual(
            reader.candidateCookiePaths(for: .chrome),
            ["/tmp/chrome/Profile 1/Network/Cookies"]
        )

        now = now.addingTimeInterval(30)

        XCTAssertEqual(
            reader.candidateCookiePaths(for: .chrome),
            ["/tmp/chrome/Profile 1/Network/Cookies"]
        )
        XCTAssertEqual(enumerationCount, 1)
    }

    func testMissingChromiumSafeStoragePasswordIsCachedWithinTTL() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, encrypted_value BLOB, host_key TEXT);
            INSERT INTO cookies VALUES ('sessionKey', '', X'76313001020304', '.secure.example.com');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        var now = Date(timeIntervalSince1970: 2_000)
        var passwordReadCount = 0
        let reader = BrowserCookieDatabaseReader(
            now: { now },
            safeStoragePasswordReader: { service, account, interactive in
                XCTAssertEqual(service, "Chrome Safe Storage")
                XCTAssertEqual(account, "Chrome")
                XCTAssertTrue(interactive)
                passwordReadCount += 1
                return nil
            }
        )

        XCTAssertNil(
            reader.namedCookieValue(
                fromDatabaseAt: databasePath,
                browser: .chrome,
                cookieName: "sessionKey",
                hostContains: "secure.example.com"
            )
        )
        XCTAssertEqual(passwordReadCount, 1)

        now = now.addingTimeInterval(30)

        XCTAssertNil(
            reader.namedCookieValue(
                fromDatabaseAt: databasePath,
                browser: .chrome,
                cookieName: "sessionKey",
                hostContains: "secure.example.com"
            )
        )
        XCTAssertEqual(passwordReadCount, 1)
    }

    func testInteractiveCookieHeaderLookupAllowsSafeStorageKeychainInteraction() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, encrypted_value BLOB, host_key TEXT);
            INSERT INTO cookies VALUES ('sessionKey', '', X'76313001020304', '.secure.example.com');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        var requestedInteractions: [Bool] = []
        let reader = BrowserCookieDatabaseReader(
            safeStoragePasswordReader: { _, _, interactive in
                requestedInteractions.append(interactive)
                return nil
            }
        )

        XCTAssertNil(
            reader.cookieHeader(
                fromDatabaseAt: databasePath,
                browser: .chrome,
                hostContains: "secure.example.com",
                accessIntent: .authRecovery
            )
        )
        XCTAssertEqual(requestedInteractions, [true])
    }

    func testBackgroundCookieHeaderLookupKeepsSafeStorageKeychainNonInteractive() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, encrypted_value BLOB, host_key TEXT);
            INSERT INTO cookies VALUES ('sessionKey', '', X'76313001020304', '.secure.example.com');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        var requestedInteractions: [Bool] = []
        let reader = BrowserCookieDatabaseReader(
            safeStoragePasswordReader: { _, _, interactive in
                requestedInteractions.append(interactive)
                return nil
            }
        )

        XCTAssertNil(
            reader.cookieHeader(
                fromDatabaseAt: databasePath,
                browser: .chrome,
                hostContains: "secure.example.com",
                accessIntent: .background
            )
        )
        XCTAssertEqual(requestedInteractions, [false])
    }

    func testBearerCandidatesUsesShortLivedCacheForSameHost() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            bearerCandidatesOverride: { host in
                lookupCount += 1
                return [BrowserDetectedCredential(value: "token-\(host)", source: "browser")]
            },
            cacheTTL: 30
        )

        let first = service.detectBearerTokenCandidates(host: "Platform.DeepSeek.com")
        let second = service.detectBearerTokenCandidates(
            host: "platform.deepseek.com",
            accessIntent: .background
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(lookupCount, 1)
    }

    func testInteractiveBearerLookupAlwaysReadsLiveStorage() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            bearerCandidatesOverride: { host in
                lookupCount += 1
                return [BrowserDetectedCredential(value: "token-\(lookupCount)-\(host)", source: "browser")]
            },
            cacheTTL: 30
        )

        let first = service.detectBearerTokenCandidates(host: "platform.deepseek.com")
        let second = service.detectBearerTokenCandidates(host: "platform.deepseek.com")

        XCTAssertEqual(first.map(\.value), ["token-1-platform.deepseek.com"])
        XCTAssertEqual(second.map(\.value), ["token-2-platform.deepseek.com"])
        XCTAssertEqual(lookupCount, 2)
    }

    func testInteractiveBearerLookupRescansAfterNegativeResult() {
        // Regression: a negative result cached by an earlier scan must not hide a
        // login the user completed right before hitting Test Connection.
        var lookupCount = 0
        let service = BrowserCredentialService(
            bearerCandidatesOverride: { host in
                lookupCount += 1
                guard lookupCount > 1 else { return [] }
                return [BrowserDetectedCredential(value: "fresh-token-\(host)", source: "browser")]
            },
            cacheTTL: 30
        )

        XCTAssertTrue(service.detectBearerTokenCandidates(host: "platform.deepseek.com").isEmpty)
        let retried = service.detectBearerTokenCandidates(host: "platform.deepseek.com")

        XCTAssertEqual(retried.map(\.value), ["fresh-token-platform.deepseek.com"])
        XCTAssertEqual(lookupCount, 2)
    }

    func testCookieHeaderCachesNegativeLookupResults() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            cookieHeaderOverride: { _ in
                lookupCount += 1
                return nil
            },
            cacheTTL: 30
        )

        XCTAssertNil(service.detectCookieHeader(host: "relay.example.com"))
        let firstPassCount = lookupCount
        XCTAssertGreaterThan(firstPassCount, 0)

        XCTAssertNil(service.detectCookieHeader(host: "relay.example.com", accessIntent: .background))
        XCTAssertEqual(lookupCount, firstPassCount)
    }

    func testInteractiveCookieHeaderLookupRescansAfterNegativeResult() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            cookieHeaderOverride: { host in
                guard host == "relay.example.com" else { return nil }
                lookupCount += 1
                guard lookupCount > 1 else { return nil }
                return BrowserDetectedCredential(value: "session=fresh-\(host)", source: "browser")
            },
            cacheTTL: 30
        )

        XCTAssertNil(service.detectCookieHeader(host: "relay.example.com"))
        let retried = service.detectCookieHeader(host: "relay.example.com")

        XCTAssertEqual(retried?.value, "session=fresh-relay.example.com")
        XCTAssertEqual(lookupCount, 2)
    }

    func testNamedCookieCachesNegativeLookupResults() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            namedCookieOverride: { _, _ in
                lookupCount += 1
                return nil
            },
            cacheTTL: 30
        )

        XCTAssertNil(service.detectNamedCookie(name: "sessionKey", host: "claude.ai"))
        let firstPassCount = lookupCount
        XCTAssertGreaterThan(firstPassCount, 0)

        XCTAssertNil(service.detectNamedCookie(name: "sessionKey", host: "claude.ai", accessIntent: .background))
        XCTAssertEqual(lookupCount, firstPassCount)
    }

    func testExpiredCredentialCacheEntriesAreInvalidatedByKeyBeforeDeferredSweep() {
        var now = Date(timeIntervalSince1970: 4_000)
        var bearerLookupCount = 0
        var cookieLookupCount = 0
        let service = BrowserCredentialService(
            bearerCandidatesOverride: { _ in
                bearerLookupCount += 1
                return [
                    BrowserDetectedCredential(
                        value: "bearer-\(bearerLookupCount)",
                        source: "browser"
                    )
                ]
            },
            cookieHeaderOverride: { _ in
                cookieLookupCount += 1
                return BrowserDetectedCredential(
                    value: "session=\(cookieLookupCount)",
                    source: "browser"
                )
            },
            cacheTTL: 10,
            now: { now }
        )

        XCTAssertEqual(
            service.detectBearerTokenCandidates(host: "stale.example.com").map(\.value),
            ["bearer-1"]
        )
        XCTAssertEqual(cacheEntryCount(named: "bearerCache", in: service), 1)

        now = now.addingTimeInterval(11)

        XCTAssertEqual(
            service.detectCookieHeader(host: "fresh.example.com")?.value,
            "session=1"
        )
        XCTAssertEqual(
            cacheEntryCount(named: "bearerCache", in: service),
            1,
            "Unrelated cache access should not rebuild and sweep every credential cache."
        )

        XCTAssertEqual(
            service.detectBearerTokenCandidates(host: "stale.example.com").map(\.value),
            ["bearer-2"]
        )
        XCTAssertEqual(bearerLookupCount, 2)
        XCTAssertEqual(cacheEntryCount(named: "bearerCache", in: service), 1)

        now = now.addingTimeInterval(61)

        XCTAssertEqual(
            service.detectCookieHeader(host: "another.example.com")?.value,
            "session=2"
        )
        XCTAssertEqual(cacheEntryCount(named: "bearerCache", in: service), 0)
    }

    func testDefaultBrowserCredentialCacheSurvivesThirtySecondsForNegativeLookups() {
        var now = Date(timeIntervalSince1970: 2_000)
        var lookupCount = 0
        let service = BrowserCredentialService(
            cookieHeaderOverride: { _ in
                lookupCount += 1
                return nil
            },
            now: { now }
        )

        XCTAssertNil(service.detectCookieHeader(host: "relay.example.com"))
        let firstPassCount = lookupCount
        XCTAssertGreaterThan(firstPassCount, 0)

        now = now.addingTimeInterval(30)

        XCTAssertNil(service.detectCookieHeader(host: "relay.example.com", accessIntent: .background))
        XCTAssertEqual(lookupCount, firstPassCount)
    }

    func testBackgroundIntentSkipsBearerLookupWhenCacheEmpty() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            bearerCandidatesOverride: { _ in
                lookupCount += 1
                return [BrowserDetectedCredential(value: "token", source: "browser")]
            },
            cacheTTL: 30
        )

        let candidates = service.detectBearerTokenCandidates(
            host: "platform.deepseek.com",
            accessIntent: .background
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(lookupCount, 0)
    }

    func testBackgroundIntentCanReuseCachedCookieHeader() {
        var lookupCount = 0
        let service = BrowserCredentialService(
            cookieHeaderOverride: { _ in
                lookupCount += 1
                return BrowserDetectedCredential(value: "session=ok", source: "browser")
            },
            cacheTTL: 30
        )

        XCTAssertEqual(
            service.detectCookieHeader(host: "relay.example.com")?.value,
            "session=ok"
        )
        XCTAssertEqual(lookupCount, 1)

        XCTAssertEqual(
            service.detectCookieHeader(
                host: "relay.example.com",
                accessIntent: .background
            )?.value,
            "session=ok"
        )
        XCTAssertEqual(lookupCount, 1)
    }

    func testBearerStoragePathEnumerationIsCachedWithinTTLAcrossLiveIntents() throws {
        let storageDirectory = try makeBearerStorageDirectory(
            host: "hongmacc.com",
            token: "sk-\(String(repeating: "b", count: 32))"
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory.deletingLastPathComponent()) }

        var enumerationCount = 0
        let storageReader = BrowserStorageCredentialReader(
            browserOrder: [.chrome],
            storagePathCacheTTL: 30,
            storagePathEnumerator: { browser in
                XCTAssertEqual(browser, .chrome)
                enumerationCount += 1
                return [storageDirectory.path]
            }
        )
        let service = BrowserCredentialService(
            storageReader: storageReader,
            cacheTTL: 0
        )

        XCTAssertEqual(
            service.detectBearerTokenCandidates(
                host: "hongmacc.com",
                accessIntent: .interactiveImport
            ),
            [BrowserDetectedCredential(value: "sk-\(String(repeating: "b", count: 32))", source: "auto:Chrome:localStorage")]
        )
        XCTAssertEqual(
            service.detectBearerTokenCandidates(
                host: "hongmacc.com",
                accessIntent: .authRecovery
            ),
            [BrowserDetectedCredential(value: "sk-\(String(repeating: "b", count: 32))", source: "auto:Chrome:localStorage")]
        )
        XCTAssertEqual(enumerationCount, 1)
    }

    func testDefaultBearerStoragePathCacheSurvivesThirtySeconds() throws {
        let firstDirectory = try makeBearerStorageDirectory(
            host: "hongmacc.com",
            token: "sk-\(String(repeating: "g", count: 32))"
        )
        let secondDirectory = try makeBearerStorageDirectory(
            host: "hongmacc.com",
            token: "sk-\(String(repeating: "h", count: 32))"
        )
        defer { try? FileManager.default.removeItem(at: firstDirectory.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: secondDirectory.deletingLastPathComponent()) }

        var now = Date(timeIntervalSince1970: 1_000)
        var enumerationCount = 0
        let storageReader = BrowserStorageCredentialReader(
            browserOrder: [.chrome],
            now: { now },
            storagePathEnumerator: { _ in
                enumerationCount += 1
                return enumerationCount == 1 ? [firstDirectory.path] : [secondDirectory.path]
            }
        )
        let service = BrowserCredentialService(
            storageReader: storageReader,
            cacheTTL: 0
        )

        XCTAssertEqual(
            service.detectBearerTokenCandidates(host: "hongmacc.com").map(\.value),
            ["sk-\(String(repeating: "g", count: 32))"]
        )

        now = now.addingTimeInterval(30)

        XCTAssertEqual(
            service.detectBearerTokenCandidates(host: "hongmacc.com").map(\.value),
            ["sk-\(String(repeating: "g", count: 32))"]
        )
        XCTAssertEqual(enumerationCount, 1)
    }

    func testBearerStoragePathEnumerationRefreshesAfterTTL() throws {
        let firstDirectory = try makeBearerStorageDirectory(
            host: "hongmacc.com",
            token: "sk-\(String(repeating: "c", count: 32))"
        )
        let secondDirectory = try makeBearerStorageDirectory(
            host: "hongmacc.com",
            token: "sk-\(String(repeating: "d", count: 32))"
        )
        defer { try? FileManager.default.removeItem(at: firstDirectory.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: secondDirectory.deletingLastPathComponent()) }

        var now = Date(timeIntervalSince1970: 1_000)
        var enumerationCount = 0
        let storageReader = BrowserStorageCredentialReader(
            browserOrder: [.chrome],
            storagePathCacheTTL: 30,
            now: { now },
            storagePathEnumerator: { _ in
                enumerationCount += 1
                return enumerationCount == 1 ? [firstDirectory.path] : [secondDirectory.path]
            }
        )
        let service = BrowserCredentialService(
            storageReader: storageReader,
            cacheTTL: 0
        )

        XCTAssertEqual(
            service.detectBearerTokenCandidates(host: "hongmacc.com").map(\.value),
            ["sk-\(String(repeating: "c", count: 32))"]
        )

        now = now.addingTimeInterval(31)

        XCTAssertEqual(
            service.detectBearerTokenCandidates(host: "hongmacc.com").map(\.value),
            ["sk-\(String(repeating: "d", count: 32))"]
        )
        XCTAssertEqual(enumerationCount, 2)
    }

    func testInteractiveBearerLookupRefreshesCachedEmptyStoragePaths() throws {
        let storageDirectory = try makeBearerStorageDirectory(
            host: "hongmacc.com",
            token: "sk-\(String(repeating: "e", count: 32))"
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory.deletingLastPathComponent()) }

        var enumerationCount = 0
        let storageReader = BrowserStorageCredentialReader(
            browserOrder: [.chrome],
            storagePathCacheTTL: 30,
            storagePathEnumerator: { _ in
                enumerationCount += 1
                return enumerationCount == 1 ? [] : [storageDirectory.path]
            }
        )

        XCTAssertTrue(storageReader.bearerTokenCandidates(host: "hongmacc.com").isEmpty)

        let service = BrowserCredentialService(
            storageReader: storageReader,
            cacheTTL: 0
        )

        XCTAssertEqual(
            service.detectBearerTokenCandidates(
                host: "hongmacc.com",
                accessIntent: .interactiveImport
            ).map(\.value),
            ["sk-\(String(repeating: "e", count: 32))"]
        )
        XCTAssertEqual(enumerationCount, 2)
    }

    func testBackgroundBearerLookupDoesNotRefreshCachedEmptyStoragePaths() throws {
        let storageDirectory = try makeBearerStorageDirectory(
            host: "hongmacc.com",
            token: "sk-\(String(repeating: "f", count: 32))"
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory.deletingLastPathComponent()) }

        var enumerationCount = 0
        let storageReader = BrowserStorageCredentialReader(
            browserOrder: [.chrome],
            storagePathCacheTTL: 30,
            storagePathEnumerator: { _ in
                enumerationCount += 1
                return enumerationCount == 1 ? [] : [storageDirectory.path]
            }
        )

        XCTAssertTrue(storageReader.bearerTokenCandidates(host: "hongmacc.com").isEmpty)

        let service = BrowserCredentialService(
            storageReader: storageReader,
            cacheTTL: 0
        )

        XCTAssertTrue(
            service.detectBearerTokenCandidates(
                host: "hongmacc.com",
                accessIntent: .background
            ).isEmpty
        )
        XCTAssertEqual(enumerationCount, 1)
    }

    func testInteractiveCookieHeaderLookupRefreshesCachedEmptyCookiePaths() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, host TEXT);
            INSERT INTO cookies VALUES ('session', 'ok', '.refresh.example.invalid');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        var enumerationCount = 0
        let cookieReader = BrowserCookieDatabaseReader(
            cookiePathCacheTTL: 30,
            cookiePathEnumerator: { browser, includeSafariBinaryCookies in
                XCTAssertEqual(browser, .chrome)
                XCTAssertTrue(includeSafariBinaryCookies)
                enumerationCount += 1
                return enumerationCount == 1 ? [] : [databasePath]
            }
        )

        XCTAssertTrue(
            cookieReader.candidateCookiePaths(
                for: .chrome,
                includeSafariBinaryCookies: true
            ).isEmpty
        )

        let cookieService = BrowserCookieService(cookieReader: cookieReader, browserOrder: [.chrome])
        let service = BrowserCredentialService(
            cookieService: cookieService,
            cacheTTL: 0
        )

        XCTAssertEqual(
            service.detectCookieHeader(
                host: "refresh.example.invalid",
                accessIntent: .interactiveImport
            )?.value,
            "session=ok"
        )
        XCTAssertEqual(enumerationCount, 2)
    }

    func testInteractiveNamedCookieLookupRefreshesCachedEmptyCookiePaths() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, host TEXT);
            INSERT INTO cookies VALUES ('sessionKey', 'plain-token', '.named-refresh.example.invalid');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        var enumerationCount = 0
        let cookieReader = BrowserCookieDatabaseReader(
            cookiePathCacheTTL: 30,
            cookiePathEnumerator: { browser, includeSafariBinaryCookies in
                XCTAssertEqual(browser, .chrome)
                XCTAssertTrue(includeSafariBinaryCookies)
                enumerationCount += 1
                return enumerationCount == 1 ? [] : [databasePath]
            }
        )

        XCTAssertTrue(
            cookieReader.candidateCookiePaths(
                for: .chrome,
                includeSafariBinaryCookies: true
            ).isEmpty
        )

        let cookieService = BrowserCookieService(cookieReader: cookieReader, browserOrder: [.chrome])
        let service = BrowserCredentialService(
            cookieService: cookieService,
            cacheTTL: 0
        )

        XCTAssertEqual(
            service.detectNamedCookie(
                name: "sessionKey",
                host: "named-refresh.example.invalid",
                accessIntent: .authRecovery
            )?.value,
            "sessionKey=plain-token"
        )
        XCTAssertEqual(enumerationCount, 2)
    }

    func testBackgroundCookieHeaderLookupDoesNotRefreshCachedEmptyCookiePaths() throws {
        let databasePath = try makeCookieDatabase(
            sql: """
            CREATE TABLE cookies (name TEXT, value TEXT, host TEXT);
            INSERT INTO cookies VALUES ('session', 'ok', '.background-refresh.example.invalid');
            """
        )
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        var enumerationCount = 0
        let cookieReader = BrowserCookieDatabaseReader(
            cookiePathCacheTTL: 30,
            cookiePathEnumerator: { _, _ in
                enumerationCount += 1
                return enumerationCount == 1 ? [] : [databasePath]
            }
        )

        XCTAssertTrue(
            cookieReader.candidateCookiePaths(
                for: .chrome,
                includeSafariBinaryCookies: true
            ).isEmpty
        )

        let cookieService = BrowserCookieService(cookieReader: cookieReader, browserOrder: [.chrome])
        let service = BrowserCredentialService(
            cookieService: cookieService,
            cacheTTL: 0
        )

        XCTAssertNil(
            service.detectCookieHeader(
                host: "background-refresh.example.invalid",
                accessIntent: .background
            )
        )
        XCTAssertEqual(enumerationCount, 1)
    }

    func testBrowserStorageCredentialReaderFindsBearerCandidatesInHostStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("leveldb", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        let token = "sk-\(String(repeating: "a", count: 32))"
        let text = "_https://hongmacc.com auth_token Bearer \(token)"
        try text.write(
            to: directory.appendingPathComponent("000003.log"),
            atomically: true,
            encoding: .isoLatin1
        )

        let reader = BrowserStorageCredentialReader()
        let candidates = reader.bearerTokenCandidates(
            storagePaths: [directory.path],
            host: "hongmacc.com",
            source: "test:localStorage"
        )

        XCTAssertEqual(candidates, [BrowserDetectedCredential(value: token, source: "test:localStorage")])
    }

    func testBrowserStorageCredentialReaderDoesNotImportTokenFromAnotherOriginInSharedStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("leveldb", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        let unrelatedToken = [
            String(repeating: "a", count: 24),
            String(repeating: "b", count: 24),
            String(repeating: "c", count: 24),
        ].joined(separator: ".")
        let padding = String(repeating: "x", count: 600)
        let text = "_https://platform.deepseek.com \(padding) _https://www.kimi.com refresh_token \(unrelatedToken)"
        try text.write(
            to: directory.appendingPathComponent("000003.log"),
            atomically: true,
            encoding: .isoLatin1
        )

        let reader = BrowserStorageCredentialReader()
        XCTAssertTrue(
            reader.bearerTokenCandidates(
                storagePaths: [directory.path],
                host: "platform.deepseek.com",
                source: "test:localStorage"
            ).isEmpty
        )
    }

    private func makeBearerStorageDirectory(host: String, token: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("leveldb", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = "_https://\(host) auth_token Bearer \(token)"
        try text.write(
            to: directory.appendingPathComponent("000003.log"),
            atomically: true,
            encoding: .isoLatin1
        )
        return directory
    }

    private func cacheEntryCount(named cacheName: String, in service: BrowserCredentialService) -> Int {
        let serviceMirror = Mirror(reflecting: service)
        guard let child = serviceMirror.children.first(where: { $0.label == cacheName }) else {
            XCTFail("Missing cache storage named \(cacheName)")
            return 0
        }
        return Mirror(reflecting: child.value).children.count
    }

    private func makeCookieDatabase(sql: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("cookies.sqlite").path
        guard let result = ShellCommand.run(executable: "/usr/bin/sqlite3", arguments: [path, sql], timeout: 5) else {
            throw NSError(domain: "BrowserCredentialServiceTests", code: 1)
        }
        XCTAssertEqual(result.status, 0, result.stderr)
        return path
    }
}
