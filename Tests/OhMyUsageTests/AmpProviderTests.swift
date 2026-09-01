import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class AmpProviderTests: XCTestCase {
    func testFetchMaps401And403ToUnauthorizedWithoutRetrying() async throws {
        for statusCode in [401, 403] {
            var requestCount = 0
            let provider = makeProvider(requestHandler: { request in
                requestCount += 1
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.host, "ampcode.com")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer amp-api-key")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data(#"{"ok":false}"#.utf8))
            })

            do {
                _ = try await provider.fetch()
                XCTFail("Expected unauthorized for status \(statusCode)")
            } catch let error as ProviderError {
                guard case .unauthorized = error else {
                    return XCTFail("Expected unauthorized for status \(statusCode), got \(error)")
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(requestCount, 1)
        }
    }

    func testFetchMaps429ToRateLimitedWithoutRetrying() async throws {
        var requestCount = 0
        let provider = makeProvider(requestHandler: { request in
            requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"ok":false}"#.utf8))
        })

        do {
            _ = try await provider.fetch()
            XCTFail("Expected rateLimited")
        } catch let error as ProviderError {
            guard case .rateLimited = error else {
                return XCTFail("Expected rateLimited, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testFetchMissingCredentialDoesNotTouchNetwork() async throws {
        let provider = AmpProvider(
            descriptor: ProviderDescriptor.defaultOfficialAmp(),
            session: makeMockSession(handler: { _ in
                XCTFail("network must not be reached without an API key")
                let response = HTTPURLResponse(url: URL(string: "https://ampcode.com/api/internal")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }),
            localJSONReader: StubLocalJSONReader(dictionary: [:])
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected missingCredential")
        } catch let error as ProviderError {
            guard case .missingCredential = error else {
                return XCTFail("Expected missingCredential, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeProvider(
        requestHandler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> AmpProvider {
        AmpProvider(
            descriptor: ProviderDescriptor.defaultOfficialAmp(),
            session: makeMockSession(handler: requestHandler),
            localJSONReader: StubLocalJSONReader(dictionary: [
                "apiKey@https://ampcode.com/": "amp-api-key"
            ])
        )
    }

    private func makeMockSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        AmpMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AmpMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class AmpMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
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

private struct StubLocalJSONReader: LocalJSONFileReading, @unchecked Sendable {
    let dictionary: [String: Any]

    func dictionary(atPath path: String) -> [String: Any]? {
        dictionary
    }

    func text(atPath path: String) -> String? {
        nil
    }
}
