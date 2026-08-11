import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class CopilotProviderTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        CopilotMockURLProtocol.requestHandler = nil
    }

    func testFetchPrefersCopilotGitHubTokenAndSetsAuthSourceLabel() async throws {
        let provider = makeProvider(
            environment: {
                [
                    "COPILOT_GITHUB_TOKEN": "copilot-env-token",
                    "GH_TOKEN": "gh-env-token",
                    "GITHUB_TOKEN": "github-env-token"
                ]
            },
            requestHandler: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token copilot-env-token")
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(Self.successBody.utf8))
            }
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.authSourceLabel, "COPILOT_GITHUB_TOKEN")
        XCTAssertEqual(snapshot.accountLabel, "octocat")
        XCTAssertEqual(snapshot.sourceLabel, "GitHub API")
    }

    func testFetchFallsBackToCopilotCLIKeychain() async throws {
        var keychainReads: [String] = []
        let provider = makeProvider(
            keychainReader: { service, _ in
                keychainReads.append(service)
                return service == "copilot-cli" ? "copilot-keychain-token" : nil
            },
            shell: StubShellCommandRunner { _, _, _ in
                XCTFail("shell fallback should not run when copilot-cli keychain token exists")
                return nil
            },
            requestHandler: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token copilot-keychain-token")
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(Self.successBody.utf8))
            }
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.authSourceLabel, "Copilot CLI")
        XCTAssertEqual(keychainReads, ["copilot-cli"])
    }

    func testFetchFallsBackToGitHubCLIKeychainBeforeShell() async throws {
        var keychainReads: [String] = []
        let provider = makeProvider(
            keychainReader: { service, _ in
                keychainReads.append(service)
                return service == "gh:github.com" ? "gh-keychain-token" : nil
            },
            shell: StubShellCommandRunner { _, _, _ in
                XCTFail("shell fallback should not run when gh keychain token exists")
                return nil
            },
            requestHandler: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token gh-keychain-token")
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(Self.successBody.utf8))
            }
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.authSourceLabel, "GitHub CLI")
        XCTAssertEqual(keychainReads, ["copilot-cli", "gh:github.com"])
    }

    func testFetchFallsBackToGitHubCLIShellToken() async throws {
        var shellCalls: [(String, [String], TimeInterval)] = []
        let provider = makeProvider(
            shell: StubShellCommandRunner { executable, arguments, timeout in
                shellCalls.append((executable, arguments, timeout))
                return (0, "gh-shell-token\n", "")
            },
            requestHandler: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token gh-shell-token")
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(Self.successBody.utf8))
            }
        )

        let snapshot = try await provider.fetch()
        let firstCall = try XCTUnwrap(shellCalls.first)
        XCTAssertEqual(snapshot.authSourceLabel, "GitHub CLI")
        XCTAssertEqual(shellCalls.count, 1)
        XCTAssertEqual(firstCall.0, "/usr/bin/env")
        XCTAssertEqual(firstCall.1, ["gh", "auth", "token"])
        XCTAssertEqual(firstCall.2, 8, accuracy: 0.001)
    }

    func testFetchThrowsHelpfulMissingCredentialWhenAllSourcesMissing() async {
        let provider = makeProvider()

        do {
            _ = try await provider.fetch()
            XCTFail("Expected missingCredential")
        } catch let error as ProviderError {
            guard case .missingCredential(let account) = error else {
                return XCTFail("Expected missingCredential, got \(error)")
            }
            XCTAssertTrue(account.contains("COPILOT_GITHUB_TOKEN"))
            XCTAssertTrue(account.contains("Copilot CLI"))
            XCTAssertTrue(account.contains("GitHub CLI"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchMaps401ToUnauthorizedDetailWithSourceLabel() async {
        let provider = makeProvider(
            environment: { ["GH_TOKEN": "gh-env-token"] },
            requestHandler: { request in
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"message":"token expired"}"#.utf8))
            }
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertTrue(message.contains("GH_TOKEN"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("refresh"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("token expired"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchMaps403ToUnauthorizedDetailWithEntitlementGuidance() async {
        let provider = makeProvider(
            environment: { ["GITHUB_TOKEN": "github-env-token"] },
            requestHandler: { request in
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 403, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"message":"Resource not accessible by integration"}"#.utf8))
            }
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertTrue(message.contains("GITHUB_TOKEN"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("entitlement"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("scope"))
            XCTAssertTrue(message.localizedCaseInsensitiveContains("resource not accessible"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeProvider(
        environment: @escaping () -> [String: String] = { [:] },
        keychainReader: @escaping (String, String?) -> String? = { _, _ in nil },
        shell: any ShellCommandRunning = StubShellCommandRunner { _, _, _ in nil },
        requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? = nil
    ) -> CopilotProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CopilotMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        CopilotMockURLProtocol.requestHandler = requestHandler

        var descriptor = ProviderDescriptor.defaultOfficialCopilot()
        descriptor.officialConfig?.sourceMode = .auto

        return CopilotProvider(
            descriptor: descriptor,
            session: session,
            environment: environment,
            keychainReader: keychainReader,
            shell: shell
        )
    }

    private static let successBody = """
    {
      "copilot_plan": "pro",
      "login": "octocat",
      "quota_reset_date": "2026-04-30T00:00:00Z",
      "quota_snapshots": {
        "premium_interactions": { "percent_remaining": 80, "entitlement": 300, "remaining": 240 },
        "chat": { "percent_remaining": 95, "entitlement": 1000, "remaining": 950 }
      }
    }
    """
}

private final class StubShellCommandRunner: ShellCommandRunning, @unchecked Sendable {
    let handler: (String, [String], TimeInterval) -> (status: Int32, stdout: String, stderr: String)?

    init(handler: @escaping (String, [String], TimeInterval) -> (status: Int32, stdout: String, stderr: String)?) {
        self.handler = handler
    }

    func run(
        executable: String,
        arguments: [String],
        input: String?,
        timeout: TimeInterval,
        environment: [String: String]?,
        currentDirectory: String?
    ) -> (status: Int32, stdout: String, stderr: String)? {
        handler(executable, arguments, timeout)
    }
}

private final class CopilotMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = CopilotMockURLProtocol.requestHandler else {
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
