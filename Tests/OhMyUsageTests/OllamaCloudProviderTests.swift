import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class OllamaCloudProviderTests: XCTestCase {
    func testParseSnapshotParsesSessionWeeklyAndPlan() throws {
        let html = #"""
        <html>
          <body>
            <h2 class="text-xl font-medium flex items-center space-x-2">
              <span>Cloud Usage</span>
              <span class="text-xs font-normal px-2 py-0.5 rounded-full bg-neutral-100 text-neutral-600 capitalize">free</span>
            </h2>
            <div>
              <div class="flex justify-between mb-2">
                <span class="text-sm">Session usage</span>
                <span class="text-sm">5.8% used</span>
              </div>
              <div class="text-xs text-neutral-500 mt-1 local-time" data-time="2026-04-17T05:00:00Z">Resets in 49 minutes</div>
            </div>
            <div>
              <div class="flex justify-between mb-2">
                <span class="text-sm">Weekly usage</span>
                <span class="text-sm">1.9% used</span>
              </div>
              <div class="text-xs text-neutral-500 mt-1 local-time" data-time="2026-04-20T00:00:00Z">Resets in 2 days</div>
            </div>
          </body>
        </html>
        """#

        let snapshot = try OllamaCloudProvider.parseSnapshot(
            html: html,
            descriptor: ProviderDescriptor.defaultOfficialOllamaCloud()
        )
        let isoFormatter = ISO8601DateFormatter()

        XCTAssertEqual(snapshot.sourceLabel, "Web")
        XCTAssertEqual(snapshot.extras["planType"], "free")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)

        let session = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.kind == .session }))
        XCTAssertEqual(session.remainingPercent, 94.2, accuracy: 0.001)
        XCTAssertEqual(session.resetAt, isoFormatter.date(from: "2026-04-17T05:00:00Z"))

        let weekly = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.kind == .weekly }))
        XCTAssertEqual(weekly.remainingPercent, 98.1, accuracy: 0.001)
        XCTAssertEqual(weekly.resetAt, isoFormatter.date(from: "2026-04-20T00:00:00Z"))
    }

    func testFetchPrefersManualCookieOverBrowserImport() async throws {
        let service = KeychainService.defaultServiceName
        let account = "official/ollama/manual-cookie-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("manual-token", service: service, account: account))

        var descriptor = ProviderDescriptor.defaultOfficialOllamaCloud()
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .autoImport
        descriptor.officialConfig?.manualCookieAccount = account

        let browser = OllamaMockBrowserCookieService()
        browser.namedResult = BrowserCookieHeader(header: "__Secure-session=auto-token", source: "Chrome")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaMockURLProtocol.self]
        let session = URLSession(configuration: config)

        OllamaMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Secure-session=manual-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.sampleHTML.utf8))
        }
        defer { OllamaMockURLProtocol.requestHandler = nil }

        let provider = OllamaCloudProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: browser
        )
        let snapshot = try await provider.fetch(forceRefresh: true)

        XCTAssertEqual(snapshot.extras["webCookieSource"], "Manual")
        XCTAssertEqual(browser.namedLookupCount, 0)
        XCTAssertEqual(browser.headerLookupCount, 0)
    }

    func testFetchUsesBrowserCookieWhenManualMissing() async throws {
        var descriptor = ProviderDescriptor.defaultOfficialOllamaCloud()
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .autoImport
        descriptor.officialConfig?.manualCookieAccount = "official/ollama/auto-cookie-\(UUID().uuidString)"

        let browser = OllamaMockBrowserCookieService()
        browser.namedResult = BrowserCookieHeader(header: "__Secure-session=auto-token", source: "Chrome")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaMockURLProtocol.self]
        let session = URLSession(configuration: config)

        OllamaMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Secure-session=auto-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.sampleHTML.utf8))
        }
        defer { OllamaMockURLProtocol.requestHandler = nil }

        let provider = OllamaCloudProvider(
            descriptor: descriptor,
            session: session,
            keychain: makeTestKeychain(),
            browserCookieService: browser
        )
        let snapshot = try await provider.fetch(forceRefresh: true)

        XCTAssertEqual(snapshot.extras["webCookieSource"], "Chrome")
        XCTAssertEqual(browser.namedLookupCount, 1)
    }

    func testFetchMapsSigninRedirectToUnauthorized() async throws {
        let service = KeychainService.defaultServiceName
        let account = "official/ollama/manual-cookie-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("manual-token", service: service, account: account))

        var descriptor = ProviderDescriptor.defaultOfficialOllamaCloud()
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .manual
        descriptor.officialConfig?.manualCookieAccount = account

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaMockURLProtocol.self]
        let session = URLSession(configuration: config)

        OllamaMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 303,
                httpVersion: nil,
                headerFields: ["Location": "/signin"]
            )!
            return (response, Data())
        }
        defer { OllamaMockURLProtocol.requestHandler = nil }

        let provider = OllamaCloudProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: OllamaMockBrowserCookieService()
        )

        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("Expected ProviderError.unauthorized")
        } catch let error as ProviderError {
            if case .unauthorized = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected unauthorized, got \(error)")
            }
        }
    }

    private static let sampleHTML = #"""
    <html>
      <body>
        <h2><span>Cloud Usage</span><span>free</span></h2>
        <div>
          <span>Session usage</span>
          <span>5.0% used</span>
          <div class="local-time" data-time="2026-04-22T00:00:00Z">Reset</div>
        </div>
        <div>
          <span>Weekly usage</span>
          <span>20.0% used</span>
          <div class="local-time" data-time="2026-04-25T00:00:00Z">Reset</div>
        </div>
      </body>
    </html>
    """#
}

private final class OllamaMockBrowserCookieService: BrowserCookieDetecting {
    var namedResult: BrowserCookieHeader?
    var headerResult: BrowserCookieHeader?
    private(set) var namedLookupCount: Int = 0
    private(set) var headerLookupCount: Int = 0

    func detectCookieHeader(
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        _ = hostContains
        _ = order
        _ = accessIntent
        headerLookupCount += 1
        return headerResult
    }

    func detectNamedCookie(
        name: String,
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        _ = name
        _ = hostContains
        _ = order
        _ = accessIntent
        namedLookupCount += 1
        return namedResult
    }
}

private final class OllamaMockURLProtocol: URLProtocol {
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
