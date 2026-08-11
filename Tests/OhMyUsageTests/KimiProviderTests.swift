import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class KimiProviderTests: XCTestCase {
    func testParseSnapshotWithWeeklyAndFiveHourLimits() throws {
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": "1000", "used": "400", "remaining": "600", "resetTime": "2026-04-12T12:00:00Z" },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 100, "used": 20, "remaining": 80, "resetTime": "2026-04-10T15:00:00Z" }
                }
              ]
            }
          ]
        }
        """

        let snapshot = try KimiProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: makeDescriptor(threshold: 20),
            authSource: "manual",
            now: Date(timeIntervalSince1970: 1_710_000_000)
        )

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.remaining ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.used ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "%")
        XCTAssertEqual(snapshot.rawMeta["kimi.authSource"], "manual")
        XCTAssertEqual(snapshot.rawMeta["kimi.weekly.remaining"], "600.00")
        XCTAssertEqual(snapshot.rawMeta["kimi.window5h.remaining"], "80.00")
        XCTAssertNotNil(snapshot.rawMeta["kimi.weekly.resetAt"])
        XCTAssertNotNil(snapshot.rawMeta["kimi.window5h.resetAt"])
    }

    func testParseSnapshotFallsBackToFirstLimitWhenNoFiveHourWindow() throws {
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 95, "remaining": 5 },
              "limits": [
                {
                  "window": { "duration": 60, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "used": 9, "remaining": 1 }
                }
              ]
            }
          ]
        }
        """

        let snapshot = try KimiProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: makeDescriptor(threshold: 15),
            authSource: "auto:Chrome"
        )

        XCTAssertEqual(snapshot.status, .warning)
        XCTAssertEqual(snapshot.remaining ?? -1, 5, accuracy: 0.001)
    }

    func testFetchReturnsUnauthorizedOn401() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = KimiProvider(
            descriptor: makeDescriptor(),
            session: session,
            keychain: makeTestKeychain(),
            browserCookieService: KimiBrowserCookieService(),
            tokenResolverOverride: { ("fake.jwt.token", "manual") }
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorized error")
        } catch let error as ProviderError {
            if case .unauthorized = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchNormalizesBearerPrefixedTokenBeforeRequest() async throws {
        let pureToken = jwt(exp: Int(Date().timeIntervalSince1970) + 3600)
        let prefixed = "Bearer \(pureToken)"
        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 20, "remaining": 80 },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "used": 1, "remaining": 9 }
                }
              ]
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(pureToken)")
            let response = HTTPURLResponse(
                url: URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let provider = KimiProvider(
            descriptor: makeDescriptor(),
            session: session,
            keychain: makeTestKeychain(),
            browserCookieService: KimiBrowserCookieService(),
            tokenResolverOverride: { (prefixed, "manual") }
        )

        _ = try await provider.fetch()
    }

    func testManualTokenHasPriorityOverAutoToken() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let manualToken = jwt(exp: Int(Date().timeIntervalSince1970) + 3600)
        let autoToken = jwt(exp: Int(Date().timeIntervalSince1970) + 7200)
        var browserLookupCount = 0
        let keychainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("keychain.json")
        defer { try? FileManager.default.removeItem(at: keychainURL.deletingLastPathComponent()) }
        let keychain = KeychainService(storageURL: keychainURL)
        XCTAssertTrue(keychain.saveToken(manualToken, service: service, account: "kimi.com/kimi-auth-manual"))
        XCTAssertTrue(keychain.saveToken(autoToken, service: service, account: "kimi.com/kimi-auth-auto"))

        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 20, "remaining": 80 },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "remaining": 9 }
                }
              ]
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(manualToken)")
            let response = HTTPURLResponse(
                url: URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        var descriptor = makeDescriptor(threshold: 10)
        descriptor.auth.keychainService = service
        descriptor.kimiConfig?.authMode = .auto

        let provider = KimiProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: KimiBrowserCookieService(),
            browserTokenResolverOverride: { _, _ in
                browserLookupCount += 1
                return KimiDetectedToken(token: autoToken, source: "auto:test")
            }
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.rawMeta["kimi.authSource"], "manual")
        XCTAssertEqual(browserLookupCount, 0)
    }

    func testBackgroundFetchDoesNotScanBrowserWhenNoSavedToken() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let keychainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("keychain.json")
        defer { try? FileManager.default.removeItem(at: keychainURL.deletingLastPathComponent()) }

        var descriptor = makeDescriptor()
        descriptor.auth.keychainService = service
        descriptor.kimiConfig?.authMode = .auto
        descriptor.kimiConfig?.autoCookieEnabled = true

        var browserLookupCount = 0
        let provider = KimiProvider(
            descriptor: descriptor,
            session: URLSession(configuration: .ephemeral),
            keychain: KeychainService(storageURL: keychainURL),
            browserCookieService: KimiBrowserCookieService(),
            browserTokenResolverOverride: { _, _ in
                browserLookupCount += 1
                return KimiDetectedToken(
                    token: self.jwt(exp: Int(Date().timeIntervalSince1970) + 3600),
                    source: "auto:test"
                )
            }
        )

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: false)
        }
        XCTAssertEqual(browserLookupCount, 0)
    }

    func testForceRefreshCanUseBrowserFallbackWhenSavedAutoTokenMissing() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let browserToken = jwt(exp: Int(Date().timeIntervalSince1970) + 3600)
        let keychainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("keychain.json")
        defer { try? FileManager.default.removeItem(at: keychainURL.deletingLastPathComponent()) }

        let json = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 25, "remaining": 75 },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "remaining": 8 }
                }
              ]
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(browserToken)")
            let response = HTTPURLResponse(
                url: URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        var descriptor = makeDescriptor()
        descriptor.auth.keychainService = service
        descriptor.kimiConfig?.authMode = .auto
        descriptor.kimiConfig?.autoCookieEnabled = true

        var browserLookupCount = 0
        var refreshPathsValues: [Bool] = []
        let provider = KimiProvider(
            descriptor: descriptor,
            session: session,
            keychain: KeychainService(storageURL: keychainURL),
            browserCookieService: KimiBrowserCookieService(),
            browserTokenResolverOverride: { _, refreshPaths in
                browserLookupCount += 1
                refreshPathsValues.append(refreshPaths)
                return KimiDetectedToken(token: browserToken, source: "auto:test")
            }
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.rawMeta["kimi.authSource"], "auto:test")
        XCTAssertEqual(browserLookupCount, 1)
        XCTAssertEqual(refreshPathsValues, [true])
    }

    func testJWTExpiryValidation() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let futureToken = jwt(exp: Int(now.timeIntervalSince1970) + 3600)
        let pastToken = jwt(exp: Int(now.timeIntervalSince1970) - 10)

        XCTAssertFalse(KimiJWT.isExpired(futureToken, now: now))
        XCTAssertTrue(KimiJWT.isExpired(pastToken, now: now))
        XCTAssertTrue(KimiJWT.isExpired("invalid.jwt", now: now))
    }

    func testPreferredAccessTokenSkipsRefreshTokens() throws {
        let now = Date().timeIntervalSince1970
        let refresh = jwt(exp: Int(now) + 90 * 24 * 3600, typ: "refresh")
        let access = jwt(exp: Int(now) + 3600, typ: "access")
        let candidates = [
            BrowserDetectedCredential(value: refresh, source: "localStorage"),
            BrowserDetectedCredential(value: access, source: "localStorage"),
        ]

        XCTAssertEqual(
            KimiBrowserCookieService.preferredAccessToken(in: candidates)?.value,
            access,
            "Expiry-sorted candidates put the long-lived refresh token first; the access token must win."
        )
    }

    func testPreferredAccessTokenFallsBackToUnknownShape() throws {
        let now = Date().timeIntervalSince1970
        let refresh = jwt(exp: Int(now) + 90 * 24 * 3600, typ: "refresh")
        let unknown = jwt(exp: Int(now) + 3600)
        let candidates = [
            BrowserDetectedCredential(value: refresh, source: "localStorage"),
            BrowserDetectedCredential(value: unknown, source: "localStorage"),
        ]

        XCTAssertEqual(KimiBrowserCookieService.preferredAccessToken(in: candidates)?.value, unknown)
    }

    func testForceRefreshExchangesRefreshTokenWhenAccessTokenMissing() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let now = Date().timeIntervalSince1970
        let detectedRefreshToken = jwt(exp: Int(now) + 90 * 24 * 3600, typ: "refresh")
        let newAccessToken = jwt(exp: Int(now) + 3600, typ: "access")
        let rotatedRefreshToken = jwt(exp: Int(now) + 90 * 24 * 3600 + 60, typ: "refresh")
        let keychainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("keychain.json")
        defer { try? FileManager.default.removeItem(at: keychainURL.deletingLastPathComponent()) }
        let keychain = KeychainService(storageURL: keychainURL)

        let usageJSON = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 25, "remaining": 75 },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "remaining": 8 }
                }
              ]
            }
          ]
        }
        """

        var refreshCallCount = 0
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.absoluteString.contains("AuthService/RefreshToken") {
                refreshCallCount += 1
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {"accessToken": "\(newAccessToken)", "refreshToken": "\(rotatedRefreshToken)"}
                """
                return (response, Data(body.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(newAccessToken)")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(usageJSON.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        var descriptor = makeDescriptor()
        descriptor.auth.keychainService = service
        descriptor.kimiConfig?.authMode = .auto
        descriptor.kimiConfig?.autoCookieEnabled = true

        let provider = KimiProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: KimiBrowserCookieService(),
            browserTokenResolverOverride: { _, _ in nil },
            browserRefreshTokenResolverOverride: { _, _ in
                KimiDetectedToken(token: detectedRefreshToken, source: "auto:test")
            }
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(snapshot.rawMeta["kimi.authSource"], "auto:test+refresh")
        XCTAssertEqual(snapshot.rawMeta["kimi.weekly.remaining"], "75.00")
        // The rotated refresh token must replace the consumed one.
        XCTAssertEqual(
            keychain.readToken(service: service, account: "kimi.com/kimi-refresh-auto"),
            rotatedRefreshToken
        )
        // And the fresh access token is cached for background polls.
        XCTAssertEqual(
            keychain.readToken(service: service, account: "kimi.com/kimi-auth-auto"),
            newAccessToken
        )
    }

    func testBackgroundFetchRenewsExpiredAccessTokenWithCachedRefreshToken() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let now = Date().timeIntervalSince1970
        let expiredAccess = jwt(exp: Int(now) - 60, typ: "access")
        let cachedRefresh = jwt(exp: Int(now) + 90 * 24 * 3600, typ: "refresh")
        let newAccessToken = jwt(exp: Int(now) + 3600, typ: "access")
        let keychainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("keychain.json")
        defer { try? FileManager.default.removeItem(at: keychainURL.deletingLastPathComponent()) }
        let keychain = KeychainService(storageURL: keychainURL)
        XCTAssertTrue(keychain.saveToken(expiredAccess, service: service, account: "kimi.com/kimi-auth-auto"))
        XCTAssertTrue(keychain.saveToken(cachedRefresh, service: service, account: "kimi.com/kimi-refresh-auto"))

        let usageJSON = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 25, "remaining": 75 },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "remaining": 8 }
                }
              ]
            }
          ]
        }
        """

        var refreshCallCount = 0
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.absoluteString.contains("AuthService/RefreshToken") {
                refreshCallCount += 1
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {"accessToken": "\(newAccessToken)", "refreshToken": "\(cachedRefresh)"}
                """
                return (response, Data(body.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(newAccessToken)")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(usageJSON.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        var descriptor = makeDescriptor()
        descriptor.auth.keychainService = service
        descriptor.kimiConfig?.authMode = .auto
        descriptor.kimiConfig?.autoCookieEnabled = true

        var browserLookupCount = 0
        let provider = KimiProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: KimiBrowserCookieService(),
            browserTokenResolverOverride: { _, _ in
                browserLookupCount += 1
                return nil
            },
            browserRefreshTokenResolverOverride: { _, _ in
                browserLookupCount += 1
                return nil
            }
        )

        let snapshot = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(browserLookupCount, 0, "Background renewal must not scan browser storage")
        XCTAssertEqual(snapshot.rawMeta["kimi.authSource"], "auto:refresh-cache+refresh")
        XCTAssertEqual(snapshot.rawMeta["kimi.weekly.remaining"], "75.00")
    }

    func testStaleCachedRefreshTokenIsMigratedAndExchanged() async throws {
        // Versions that cached the long-lived refresh token in the access slot
        // must self-heal: move it to the refresh slot and exchange it.
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let now = Date().timeIntervalSince1970
        let staleRefresh = jwt(exp: Int(now) + 90 * 24 * 3600, typ: "refresh")
        let newAccessToken = jwt(exp: Int(now) + 3600, typ: "access")
        let rotatedRefreshToken = jwt(exp: Int(now) + 90 * 24 * 3600 + 60, typ: "refresh")
        let keychainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("keychain.json")
        defer { try? FileManager.default.removeItem(at: keychainURL.deletingLastPathComponent()) }
        let keychain = KeychainService(storageURL: keychainURL)
        XCTAssertTrue(keychain.saveToken(staleRefresh, service: service, account: "kimi.com/kimi-auth-auto"))

        let usageJSON = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 25, "remaining": 75 },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "remaining": 8 }
                }
              ]
            }
          ]
        }
        """

        var refreshCallCount = 0
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.absoluteString.contains("AuthService/RefreshToken") {
                refreshCallCount += 1
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {"accessToken": "\(newAccessToken)", "refreshToken": "\(rotatedRefreshToken)"}
                """
                return (response, Data(body.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(newAccessToken)")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(usageJSON.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]

        var descriptor = makeDescriptor()
        descriptor.auth.keychainService = service
        descriptor.kimiConfig?.authMode = .auto
        descriptor.kimiConfig?.autoCookieEnabled = true

        let provider = KimiProvider(
            descriptor: descriptor,
            session: URLSession(configuration: config),
            keychain: keychain,
            browserCookieService: KimiBrowserCookieService(),
            browserTokenResolverOverride: { _, _ in nil },
            browserRefreshTokenResolverOverride: { _, _ in nil }
        )

        let snapshot = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(snapshot.rawMeta["kimi.weekly.remaining"], "75.00")
        XCTAssertEqual(
            keychain.readToken(service: service, account: "kimi.com/kimi-auth-auto"),
            newAccessToken,
            "The stale refresh token must be replaced by the fresh access token"
        )
        XCTAssertEqual(
            keychain.readToken(service: service, account: "kimi.com/kimi-refresh-auto"),
            rotatedRefreshToken
        )
    }

    func testManualRefreshTokenIsExchangedForAccessToken() async throws {
        let service = "OhMyUsageTests-\(UUID().uuidString)"
        let now = Date().timeIntervalSince1970
        let manualRefresh = jwt(exp: Int(now) + 90 * 24 * 3600, typ: "refresh")
        let newAccessToken = jwt(exp: Int(now) + 3600, typ: "access")
        let keychainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("keychain.json")
        defer { try? FileManager.default.removeItem(at: keychainURL.deletingLastPathComponent()) }
        let keychain = KeychainService(storageURL: keychainURL)
        XCTAssertTrue(keychain.saveToken(manualRefresh, service: service, account: "kimi.com/kimi-auth-manual"))

        let usageJSON = """
        {
          "usages": [
            {
              "scope": "FEATURE_CODING",
              "detail": { "limit": 100, "used": 25, "remaining": 75 },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "limit": 10, "remaining": 8 }
                }
              ]
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.absoluteString.contains("AuthService/RefreshToken") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {"accessToken": "\(newAccessToken)", "refreshToken": "\(manualRefresh)"}
                """
                return (response, Data(body.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(newAccessToken)")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(usageJSON.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]

        var descriptor = makeDescriptor()
        descriptor.auth.keychainService = service
        descriptor.kimiConfig?.authMode = .manual

        let provider = KimiProvider(
            descriptor: descriptor,
            session: URLSession(configuration: config),
            keychain: keychain,
            browserCookieService: KimiBrowserCookieService()
        )

        let snapshot = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(snapshot.rawMeta["kimi.authSource"], "manual+refresh")
        XCTAssertEqual(snapshot.rawMeta["kimi.weekly.remaining"], "75.00")
    }


    private func makeDescriptor(threshold: Double = 10) -> ProviderDescriptor {
        ProviderDescriptor(
            id: "kimi-coding",
            name: "Kimi (For Coding)",
            type: .kimi,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: threshold, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: "OhMyUsage", keychainAccount: "kimi.com/kimi-auth-manual"),
            baseURL: "https://www.kimi.com",
            kimiConfig: KimiProviderConfig(
                authMode: .manual,
                manualTokenAccount: "kimi.com/kimi-auth-manual",
                autoCookieEnabled: true,
                browserOrder: [.arc, .chrome, .safari, .edge, .brave, .chromium]
            )
        )
    }

    private func jwt(exp: Int, typ: String? = nil) -> String {
        let header = #"{"alg":"HS256","typ":"JWT"}"#
        var payload = #"{"exp":\#(exp)"#
        if let typ {
            payload += #", "typ":"\#(typ)""#
        }
        payload += "}"
        return "\(b64url(header)).\(b64url(payload)).signature"
    }

    private func b64url(_ input: String) -> String {
        Data(input.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private func XCTAssertThrowsProviderError(
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected ProviderError", file: file, line: line)
    } catch is ProviderError {
        return
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
