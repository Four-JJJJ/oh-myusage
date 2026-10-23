import Foundation
import XCTest
import OhMyUsageDomain
import OhMyUsageProviders
@testable import OhMyUsage

/// Regression tests for the 2.6.2 hardening pass: browser cookie SQL filters,
/// relay absolute-path policy, and official cookie rotation persistence.
final class SecurityHardeningTests: XCTestCase {
    // MARK: - Browser cookie query filters

    private func makeCookieDatabase() throws -> URL {
        // APFS is case-insensitive, so `Cookies` and `cookies` are one table;
        // the reader's first query (host_key) is the one that hits.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("omu-cookie-db-\(UUID().uuidString).sqlite")
        try runSQLite(url.path, sql: "CREATE TABLE cookies (name TEXT, host_key TEXT, value TEXT, encrypted_value BLOB);")
        try runSQLite(url.path, sql: "INSERT INTO cookies (name, host_key, value) VALUES ('session', 'app.goodhost.com', 'plain-value');")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testBrowserCookieQueryAcceptsLegitimateFilters() throws {
        let database = try makeCookieDatabase()
        let reader = BrowserCookieDatabaseReader()

        XCTAssertEqual(
            reader.namedCookieValue(
                fromDatabaseAt: database.path,
                browser: .chrome,
                cookieName: "session",
                hostContains: "goodhost.com"
            ),
            "plain-value"
        )
        XCTAssertEqual(
            reader.cookieHeader(
                fromDatabaseAt: database.path,
                browser: .chrome,
                hostContains: "goodhost.com"
            ),
            "session=plain-value"
        )
    }

    func testBrowserCookieQueryRejectsSQLInjectionInFilters() throws {
        let database = try makeCookieDatabase()
        let reader = BrowserCookieDatabaseReader()

        // Without sanitization each of these escapes the LIKE literal and
        // matches rows for unrelated hosts.
        XCTAssertNil(reader.namedCookieValue(
            fromDatabaseAt: database.path,
            browser: .chrome,
            cookieName: "session",
            hostContains: "evil.com' OR host_key LIKE '%goodhost"
        ))
        XCTAssertNil(reader.namedCookieValue(
            fromDatabaseAt: database.path,
            browser: .chrome,
            cookieName: "session' OR '1'='1",
            hostContains: "goodhost.com"
        ))
        XCTAssertNil(reader.cookieHeader(
            fromDatabaseAt: database.path,
            browser: .chrome,
            hostContains: "goodhost.com' OR '1'='1"
        ))
    }

    // MARK: - Relay absolute request paths

    func testRelayURLAllowsTrustedVendorAbsolutePaths() {
        let base = URL(string: "https://relay.example.com")!
        let minimax = RelayRequestResolver.relayURL(
            baseURL: base,
            rawPath: "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains"
        )
        XCTAssertEqual(minimax.host, "api.minimaxi.com")

        let deepseek = RelayRequestResolver.relayURL(
            baseURL: base,
            rawPath: "https://api.deepseek.com/user/balance"
        )
        XCTAssertEqual(deepseek.host, "api.deepseek.com")
    }

    func testRelayURLKeepsSameHostAbsolutePathOnlyWithSameScheme() {
        let base = URL(string: "https://relay.example.com")!

        let sameScheme = RelayRequestResolver.relayURL(
            baseURL: base,
            rawPath: "https://relay.example.com/api/balance"
        )
        XCTAssertEqual(sameScheme.absoluteString, "https://relay.example.com/api/balance")

        // An http override against an https relay is a downgrade, not a hop.
        let downgraded = RelayRequestResolver.relayURL(
            baseURL: base,
            rawPath: "http://relay.example.com/api/balance"
        )
        XCTAssertEqual(downgraded.host, "relay.example.com")
        XCTAssertEqual(downgraded.scheme, "https")
    }

    func testRelayURLSendsThirdPartyAbsolutePathsBackToConfiguredOrigin() {
        let base = URL(string: "https://relay.example.com")!

        let thirdParty = RelayRequestResolver.relayURL(
            baseURL: base,
            rawPath: "https://attacker.example.net/collect"
        )
        XCTAssertEqual(thirdParty.host, "relay.example.com")

        // A trusted vendor host over plaintext http is refused too.
        let plaintextTrusted = RelayRequestResolver.relayURL(
            baseURL: base,
            rawPath: "http://api.deepseek.com/user/balance"
        )
        XCTAssertEqual(plaintextTrusted.host, "relay.example.com")
    }

    // MARK: - Official cookie rotation persistence

    func testRotationDefersKeychainOverwriteUntilRequestSucceeds() async throws {
        let keychain = makeTestKeychain()
        let account = "official/hardening/cookie-\(UUID().uuidString)"
        XCTAssertTrue(keychain.saveToken("session=saved", service: KeychainService.defaultServiceName, account: account))
        let official = OfficialProviderConfig(
            sourceMode: .web,
            webMode: .autoImport,
            manualCookieAccount: account
        )
        let providerKey = "hardening-rotate-\(UUID().uuidString)"
        let spy = HardeningCookieDetectorSpy()
        spy.cookieHeaderResult = BrowserCookieHeader(header: "session=stale-browser", source: "Auto:Test")
        let strategy = OfficialBrowserCookieImportStrategy(
            providerKey: providerKey,
            hostContains: "example.com",
            namedCookie: nil,
            autoImportMissingCredential: "missing auto cookie",
            manualCredentialFallback: "manual cookie",
            normalizeManualHeader: { $0 },
            normalizeDetectedHeader: { $0 }
        )

        let rotated = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: official,
            descriptorID: "\(providerKey)-descriptor",
            keychain: keychain,
            browserCookieService: spy,
            forceRefresh: true,
            strategy: strategy
        )

        XCTAssertEqual(rotated.header, "session=stale-browser")
        XCTAssertTrue(rotated.readBrowserDuringResolution)
        XCTAssertEqual(rotated.pendingPersistHeader, "session=stale-browser")
        // A stale browser login must not destroy the cookie that still works.
        XCTAssertEqual(
            keychain.readToken(service: KeychainService.defaultServiceName, account: account),
            "session=saved"
        )

        await OfficialProviderWebOverlayRuntime.persistConfirmedCookie(rotated, official: official, keychain: keychain)
        XCTAssertEqual(
            keychain.readToken(service: KeychainService.defaultServiceName, account: account),
            "session=stale-browser"
        )
    }

    func testFirstBrowserImportPersistsImmediately() async throws {
        let keychain = makeTestKeychain()
        let account = "official/hardening/cookie-\(UUID().uuidString)"
        let official = OfficialProviderConfig(
            sourceMode: .web,
            webMode: .autoImport,
            manualCookieAccount: account
        )
        let providerKey = "hardening-first-\(UUID().uuidString)"
        let spy = HardeningCookieDetectorSpy()
        spy.cookieHeaderResult = BrowserCookieHeader(header: "session=fresh", source: "Auto:Test")
        let strategy = OfficialBrowserCookieImportStrategy(
            providerKey: providerKey,
            hostContains: "example.com",
            namedCookie: nil,
            autoImportMissingCredential: "missing auto cookie",
            manualCredentialFallback: "manual cookie",
            normalizeManualHeader: { $0 },
            normalizeDetectedHeader: { $0 }
        )

        let resolved = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: official,
            descriptorID: "\(providerKey)-descriptor",
            keychain: keychain,
            browserCookieService: spy,
            forceRefresh: false,
            strategy: strategy
        )

        XCTAssertEqual(resolved.header, "session=fresh")
        XCTAssertNil(resolved.pendingPersistHeader)
        // Nothing was stored, so the import can commit right away.
        XCTAssertEqual(
            keychain.readToken(service: KeychainService.defaultServiceName, account: account),
            "session=fresh"
        )
    }

    func testStoredCookieServedWithoutBrowserReadCarriesRetryFlag() async throws {
        let keychain = makeTestKeychain()
        let account = "official/hardening/cookie-\(UUID().uuidString)"
        XCTAssertTrue(keychain.saveToken("session=saved", service: KeychainService.defaultServiceName, account: account))
        let official = OfficialProviderConfig(
            sourceMode: .web,
            webMode: .autoImport,
            manualCookieAccount: account
        )
        let providerKey = "hardening-stored-\(UUID().uuidString)"
        let spy = HardeningCookieDetectorSpy()
        let strategy = OfficialBrowserCookieImportStrategy(
            providerKey: providerKey,
            hostContains: "example.com",
            namedCookie: nil,
            autoImportMissingCredential: "missing auto cookie",
            manualCredentialFallback: "manual cookie",
            normalizeManualHeader: { $0 },
            normalizeDetectedHeader: { $0 }
        )

        // Prime the rotation window: the forced read finds nothing and the
        // saved cookie is served.
        let primed = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: official,
            descriptorID: "\(providerKey)-descriptor",
            keychain: keychain,
            browserCookieService: spy,
            forceRefresh: true,
            strategy: strategy
        )
        XCTAssertEqual(primed.header, "session=saved")
        XCTAssertNil(primed.pendingPersistHeader)

        // Inside the rotation window the stored cookie is served without
        // touching the browser, so a rejected request may retry against it.
        let served = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: official,
            descriptorID: "\(providerKey)-descriptor",
            keychain: keychain,
            browserCookieService: spy,
            forceRefresh: false,
            strategy: strategy
        )
        XCTAssertEqual(served.header, "session=saved")
        XCTAssertFalse(served.readBrowserDuringResolution)
        XCTAssertNil(served.pendingPersistHeader)
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)
    }

    // MARK: - Update manifest checksum

    func testPrepareUpdateRejectsAssetWithoutChecksum() async throws {
        let zipURL = URL(string: "https://github.com/Four-JJJJ/oh-myusage/releases/download/v2.6.2/oh-myusage-macOS.zip")!
        let service = AppUpdateService(session: URLSession(configuration: .ephemeral))
        let update = AppUpdateInfo(
            latestVersion: "2.6.2",
            releaseURL: AppUpdateService.releasesURL,
            notesURL: nil,
            publishedAt: nil,
            zipAsset: AppUpdateAsset(url: zipURL, sha256: nil, size: nil),
            dmgAsset: nil
        )

        do {
            _ = try await service.prepareUpdate(update)
            XCTFail("Expected an update without a checksum to be rejected.")
        } catch AppUpdateError.missingChecksum {
        } catch {
            XCTFail("Expected missingChecksum, got \(error).")
        }
    }

    private func runSQLite(_ path: String, sql: String) throws {
        guard let result = ShellCommand.run(
            executable: "/usr/bin/sqlite3",
            arguments: [path, sql],
            timeout: 10
        ) else {
            throw XCTSkip("sqlite3 command failed to start")
        }
        XCTAssertEqual(result.status, 0, "sqlite3 failed: \(result.stderr)")
    }
}

private final class HardeningCookieDetectorSpy: BrowserCookieDetecting {
    var detectCookieHeaderCallCount = 0
    var cookieHeaderResult: BrowserCookieHeader?

    func detectCookieHeader(
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        detectCookieHeaderCallCount += 1
        return cookieHeaderResult
    }

    func detectNamedCookie(
        name: String,
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        nil
    }
}
