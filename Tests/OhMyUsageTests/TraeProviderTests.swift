import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class TraeProviderTests: XCTestCase {
    func testParseSnapshotParsesDollarAndAutocompleteWindows() throws {
        let json = """
        {
          "code": 0,
          "msg": "success",
          "data": {
            "user_entitlement_pack_list": [
              {
                "display_desc": "Trae SOLO Pro",
                "usage": {
                  "basic_usage_amount": 12.5,
                  "auto_completion_usage": 8
                },
                "entitlement_base_info": {
                  "end_time": 1776787199,
                  "quota": {
                    "basic_usage_limit": 100,
                    "auto_completion_limit": 50
                  }
                }
              }
            ]
          }
        }
        """

        let snapshot = try TraeProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialTrae()
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.extras["planType"], "Trae SOLO Pro")
        XCTAssertTrue(snapshot.note.contains("Plan Trae SOLO Pro"))
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "美元余额" })?.remainingPercent ?? -1,
            87.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "自动补全" })?.remainingPercent ?? -1,
            84.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "美元余额" })?.resetAt,
            Date(timeIntervalSince1970: 1_776_787_199)
        )
    }

    func testParseSnapshotStripsPlanKeywordFromDisplayDesc() throws {
        let json = """
        {
          "code": 0,
          "msg": "success",
          "data": {
            "user_entitlement_pack_list": [
              {
                "display_desc": "Free plan",
                "usage": {
                  "basic_usage_amount": 1,
                  "auto_completion_usage": 10
                },
                "entitlement_base_info": {
                  "end_time": 1776787199,
                  "quota": {
                    "basic_usage_limit": 3,
                    "auto_completion_limit": 100
                  }
                }
              }
            ]
          }
        }
        """

        let snapshot = try TraeProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialTrae()
        )

        XCTAssertEqual(snapshot.extras["planType"], "Free")
        XCTAssertTrue(snapshot.note.contains("Plan Free"))
        XCTAssertTrue(snapshot.note.contains("美元余额"))
        XCTAssertTrue(snapshot.note.contains("自动补全"))
    }

    func testParseSnapshotKeepsDisplayDescWithoutPlanKeyword() throws {
        let json = """
        {
          "code": 0,
          "msg": "success",
          "data": {
            "user_entitlement_pack_list": [
              {
                "display_desc": "Ultra",
                "usage": {
                  "basic_usage_amount": 1,
                  "auto_completion_usage": 10
                },
                "entitlement_base_info": {
                  "end_time": 1776787199,
                  "quota": {
                    "basic_usage_limit": 3,
                    "auto_completion_limit": 100
                  }
                }
              }
            ]
          }
        }
        """

        let snapshot = try TraeProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialTrae()
        )

        XCTAssertEqual(snapshot.extras["planType"], "Ultra")
        XCTAssertTrue(snapshot.note.contains("Plan Ultra"))
    }

    func testFetchMaps401And403ToUnauthorized() async throws {
        try await assertFetchError(
            statusCode: 401,
            body: #"{"msg":"unauthorized"}"#,
            matcher: {
                if case .unauthorized = $0 {
                    return true
                }
                return false
            }
        )

        try await assertFetchError(
            statusCode: 403,
            body: #"{"msg":"forbidden"}"#,
            matcher: {
                if case .unauthorized = $0 {
                    return true
                }
                return false
            }
        )
    }

    func testFetchMaps429ToRateLimited() async throws {
        try await assertFetchError(
            statusCode: 429,
            body: #"{"msg":"too many requests"}"#,
            matcher: {
                if case .rateLimited = $0 {
                    return true
                }
                return false
            }
        )
    }

    func testFetchMapsMissingFieldsToInvalidResponse() async throws {
        try await assertFetchError(
            statusCode: 200,
            body: #"{"code":0,"data":{"user_entitlement_pack_list":[{"usage":{"basic_usage_amount":1}}]}}"#,
            matcher: {
                if case .invalidResponse = $0 {
                    return true
                }
                return false
            }
        )
    }

    func testFetchWithSavedTokenDoesNotReadBrowserCandidates() async throws {
        let keychain = makeTestKeychain()
        let service = "OhMyUsageTests-Trae-\(UUID().uuidString)"
        let account = "official/trae/cloud-ide-jwt-\(UUID().uuidString)"
        XCTAssertTrue(keychain.saveToken("saved.jwt.token", service: service, account: account))

        var descriptor = ProviderDescriptor.defaultOfficialTrae()
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: service, keychainAccount: account)
        descriptor.officialConfig?.sourceMode = .auto

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TraeMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        TraeMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Cloud-IDE-JWT saved.jwt.token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.successBody.utf8))
        }
        defer { TraeMockURLProtocol.requestHandler = nil }

        let spy = TraeBrowserCandidateSpy()
        let provider = TraeProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: spy.candidates(host:),
                cacheTTL: 0
            )
        )

        let snapshot = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testFetchRefreshesSavedTokenFromBrowserCandidateAfterUnauthorized() async throws {
        let keychain = makeTestKeychain()
        let service = "OhMyUsageTests-Trae-\(UUID().uuidString)"
        let account = "official/trae/cloud-ide-jwt-\(UUID().uuidString)"
        XCTAssertTrue(keychain.saveToken("expired.jwt.token", service: service, account: account))

        var descriptor = ProviderDescriptor.defaultOfficialTrae()
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: service, keychainAccount: account)
        descriptor.officialConfig?.sourceMode = .auto

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TraeMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var authorizations: [String] = []

        TraeMockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            authorizations.append(auth)
            if auth == "Cloud-IDE-JWT expired.jwt.token" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"msg":"unauthorized"}"#.utf8))
            }
            XCTAssertEqual(auth, "Cloud-IDE-JWT fresh.jwt.token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.successBody.utf8))
        }
        defer { TraeMockURLProtocol.requestHandler = nil }

        let spy = TraeBrowserCandidateSpy(
            candidatesByHost: [
                "trae.ai": [BrowserDetectedCredential(value: "fresh.jwt.token", source: "Chrome:localStorage")]
            ]
        )
        let provider = TraeProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: spy.candidates(host:),
                cacheTTL: 0
            )
        )

        let snapshot = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(authorizations, [
            "Cloud-IDE-JWT expired.jwt.token",
            "Cloud-IDE-JWT fresh.jwt.token"
        ])
        XCTAssertEqual(snapshot.authSourceLabel, "Chrome:localStorage:trae.ai")
        XCTAssertEqual(keychain.readToken(service: service, account: account), "fresh.jwt.token")
    }

    func testFetchUsesBrowserCandidateWhenSavedTokenMissing() async throws {
        let keychain = makeTestKeychain()
        let service = "OhMyUsageTests-Trae-\(UUID().uuidString)"
        let account = "official/trae/cloud-ide-jwt-\(UUID().uuidString)"

        var descriptor = ProviderDescriptor.defaultOfficialTrae()
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: service, keychainAccount: account)
        descriptor.officialConfig?.sourceMode = .auto

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TraeMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        TraeMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Cloud-IDE-JWT fresh.jwt.token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.successBody.utf8))
        }
        defer { TraeMockURLProtocol.requestHandler = nil }

        let spy = TraeBrowserCandidateSpy(
            candidatesByHost: [
                "trae.ai": [BrowserDetectedCredential(value: "Cloud-IDE-JWT fresh.jwt.token", source: "Arc:localStorage")]
            ]
        )
        let provider = TraeProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: spy.candidates(host:),
                cacheTTL: 0
            )
        )

        let snapshot = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(snapshot.authSourceLabel, "Arc:localStorage:trae.ai")
        XCTAssertEqual(keychain.readToken(service: service, account: account), "fresh.jwt.token")
    }

    func testFetchReturnsUnauthorizedDetailWhenSavedAndBrowserCandidatesFail() async throws {
        let keychain = makeTestKeychain()
        let service = "OhMyUsageTests-Trae-\(UUID().uuidString)"
        let account = "official/trae/cloud-ide-jwt-\(UUID().uuidString)"
        XCTAssertTrue(keychain.saveToken("expired.jwt.token", service: service, account: account))

        var descriptor = ProviderDescriptor.defaultOfficialTrae()
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: service, keychainAccount: account)
        descriptor.officialConfig?.sourceMode = .auto

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TraeMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        TraeMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"msg":"unauthorized"}"#.utf8))
        }
        defer { TraeMockURLProtocol.requestHandler = nil }

        let spy = TraeBrowserCandidateSpy(
            candidatesByHost: [
                "trae.ai": [BrowserDetectedCredential(value: "fresh.jwt.token", source: "Chrome:localStorage")]
            ]
        )
        let provider = TraeProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: spy.candidates(host:),
                cacheTTL: 0
            )
        )

        do {
            _ = try await provider.fetch(forceRefresh: false)
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertTrue(message.contains("Trae SOLO Authorization 已失效"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNormalizeTokenAcceptsCloudIDEAndBearerPrefix() {
        let jwt = "aaa.bbb.ccc"

        XCTAssertEqual(TraeProvider.normalizeToken(jwt), jwt)
        XCTAssertEqual(TraeProvider.normalizeToken("Cloud-IDE-JWT \(jwt)"), jwt)
        XCTAssertEqual(TraeProvider.normalizeToken("cloud-ide-jwt \(jwt)"), jwt)
        XCTAssertEqual(TraeProvider.normalizeToken("Bearer \(jwt)"), jwt)
    }

    private func assertFetchError(
        statusCode: Int,
        body: String,
        matcher: (ProviderError) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let keychain = makeTestKeychain()
        let service = "OhMyUsageTests-Trae-\(UUID().uuidString)"
        let account = "official/trae/cloud-ide-jwt-\(UUID().uuidString)"
        XCTAssertTrue(
            keychain.saveToken("Bearer aaa.bbb.ccc", service: service, account: account),
            file: file,
            line: line
        )

        var descriptor = ProviderDescriptor.defaultOfficialTrae()
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: service, keychainAccount: account)
        descriptor.baseURL = "https://api-sg-central.trae.ai"
        descriptor.officialConfig?.sourceMode = .api

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TraeMockURLProtocol.self]
        let session = URLSession(configuration: config)

        TraeMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/trae/api/v1/pay/ide_user_ent_usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Cloud-IDE-JWT aaa.bbb.ccc")
            let response = HTTPURLResponse(
                url: URL(string: "https://api-sg-central.trae.ai/trae/api/v1/pay/ide_user_ent_usage")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
        defer { TraeMockURLProtocol.requestHandler = nil }

        let provider = TraeProvider(descriptor: descriptor, session: session, keychain: keychain)
        do {
            _ = try await provider.fetch()
            XCTFail("Expected ProviderError", file: file, line: line)
        } catch let error as ProviderError {
            XCTAssertTrue(matcher(error), "Unexpected ProviderError: \(error)", file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private static let successBody = """
    {
      "code": 0,
      "msg": "success",
      "data": {
        "user_entitlement_pack_list": [
          {
            "display_desc": "Trae SOLO Pro",
            "usage": {
              "basic_usage_amount": 12.5,
              "auto_completion_usage": 8
            },
            "entitlement_base_info": {
              "end_time": 1776787199,
              "quota": {
                "basic_usage_limit": 100,
                "auto_completion_limit": 50
              }
            }
          }
        ]
      }
    }
    """
}

private final class TraeBrowserCandidateSpy {
    var calls: [String] = []
    var candidatesByHost: [String: [BrowserDetectedCredential]]

    init(candidatesByHost: [String: [BrowserDetectedCredential]] = [:]) {
        self.candidatesByHost = candidatesByHost
    }

    func candidates(host: String) -> [BrowserDetectedCredential] {
        calls.append(host)
        return candidatesByHost[host] ?? []
    }
}

private final class TraeMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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
