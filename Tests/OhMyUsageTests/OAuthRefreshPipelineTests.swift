import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

/// P2-4 regression coverage for the shared Codex/Claude desktop OAuth refresh
/// pipeline: happy-path persistence per service configuration, plus
/// observability of credential-file / vault write-back failures (failures are
/// logged but never fail an otherwise successful refresh).
final class OAuthRefreshPipelineTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        OAuthRefreshMockURLProtocol.requestHandler = nil
    }

    // MARK: - Happy path per service configuration

    func testCodexServiceRefreshMergesTokensIntoAuthFilesAndVault() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-refresh-pipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let authPath = directory.appendingPathComponent("auth.json")
        let staleJSON = codexAuthJSON(
            accessToken: "access-old",
            refreshToken: "refresh-old",
            accountID: "team-old",
            idToken: codexIDToken(email: "old@example.com", subject: "sub-old")
        )
        try staleJSON.write(to: authPath, atomically: true, encoding: .utf8)

        let refreshedIDToken = codexIDToken(email: "refreshed@example.com", subject: "sub-refreshed")
        OAuthRefreshMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/oauth/token")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/x-www-form-urlencoded"
            )
            let body = String(data: requestBodyData(request) ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("grant_type=refresh_token"), "got \(body)")
            XCTAssertTrue(body.contains("client_id=app_EMoamEEZ73f0CkXaXp7hrann"), "got \(body)")
            XCTAssertTrue(body.contains("refresh_token=refresh-old"), "got \(body)")
            let responseBody: [String: Any] = [
                "access_token": "access-new",
                "refresh_token": "refresh-new",
                "id_token": refreshedIDToken,
                "account_id": "team-new"
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: responseBody)
            )
        }

        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        let service = CodexDesktopAuthService(
            homeDirectory: { directory.path },
            environment: { ["CODEX_HOME": directory.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true },
            oauthVault: vault
        )
        let logs = LogRecorder()

        let refreshed = try await service.refreshAuthJSON(
            session: makeSession(),
            rawAuthJSON: staleJSON,
            now: { fixedNow },
            log: { logs.append($0) }
        )

        let refreshedJSON = try XCTUnwrap(refreshed)
        let refreshedPayload = try CodexAccountProfileStore.parseAuthJSON(refreshedJSON)
        XCTAssertEqual(refreshedPayload.accessToken, "access-new")
        XCTAssertEqual(refreshedPayload.refreshToken, "refresh-new")
        XCTAssertEqual(refreshedPayload.accountId, "team-new")
        XCTAssertEqual(refreshedPayload.accountEmail, "refreshed@example.com")

        let onDisk = try JSONSerialization.jsonObject(
            with: Data(contentsOf: authPath)
        ) as? [String: Any]
        let tokens = try XCTUnwrap(onDisk?["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["access_token"] as? String, "access-new")
        XCTAssertEqual(tokens["refresh_token"] as? String, "refresh-new")
        XCTAssertEqual(tokens["account_id"] as? String, "team-new")
        XCTAssertEqual(
            onDisk?["last_refresh"] as? String,
            ISO8601DateFormatter().string(from: fixedNow)
        )

        XCTAssertEqual(
            vault.readOAuthJSON(provider: .codex),
            refreshedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertTrue(vault.isMigrationComplete(provider: .codex))
        XCTAssertTrue(logs.messages.isEmpty, "happy path must not log failures: \(logs.messages)")
    }

    func testClaudeServiceRefreshMergesOAuthIntoCredentialFilesAndVault() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-refresh-pipeline-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent("profiles/main", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let credentialPath = configDir.appendingPathComponent(".credentials.json")
        let staleJSON = claudeCredentialsJSON()
        try staleJSON.write(to: credentialPath, atomically: true, encoding: .utf8)

        OAuthRefreshMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://platform.claude.com/v1/oauth/token")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/json"
            )
            let body = try JSONSerialization.jsonObject(
                with: requestBodyData(request) ?? Data()
            ) as? [String: Any]
            XCTAssertEqual(body?["grant_type"] as? String, "refresh_token")
            XCTAssertEqual(body?["refresh_token"] as? String, "refresh-old")
            XCTAssertEqual(body?["client_id"] as? String, "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
            XCTAssertEqual(
                body?["scope"] as? String,
                "user:profile user:inference user:sessions:claude_code user:mcp_servers"
            )
            let responseBody: [String: Any] = [
                "access_token": "access-new",
                "refresh_token": "refresh-new",
                "expires_in": 3600
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: responseBody)
            )
        }

        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true },
            oauthVault: vault
        )
        let logs = LogRecorder()

        let refreshed = try await service.refreshCredentialsJSON(
            session: makeSession(),
            rawCredentialsJSON: staleJSON,
            now: { fixedNow },
            log: { logs.append($0) }
        )

        let refreshedJSON = try XCTUnwrap(refreshed)
        let refreshedPayload = try ClaudeAccountProfileStore.parseCredentialsJSON(refreshedJSON)
        XCTAssertEqual(refreshedPayload.accessToken, "access-new")
        XCTAssertEqual(refreshedPayload.refreshToken, "refresh-new")
        XCTAssertEqual(
            refreshedPayload.expiresAtMs ?? 0,
            fixedNow.timeIntervalSince1970 * 1000 + 3_600_000,
            accuracy: 1
        )
        XCTAssertEqual(refreshedPayload.subscriptionType, "pro")

        let onDisk = try JSONSerialization.jsonObject(
            with: Data(contentsOf: credentialPath)
        ) as? [String: Any]
        let oauth = try XCTUnwrap(onDisk?["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(oauth["accessToken"] as? String, "access-new")
        XCTAssertEqual(oauth["refreshToken"] as? String, "refresh-new")
        XCTAssertEqual(
            oauth["expiresAt"] as? Double,
            fixedNow.timeIntervalSince1970 * 1000 + 3_600_000
        )
        XCTAssertEqual(oauth["subscriptionType"] as? String, "pro")
        XCTAssertEqual(onDisk?["accountId"] as? String, "acc-1")

        XCTAssertEqual(
            vault.readOAuthJSON(provider: .claude),
            refreshedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertTrue(vault.isMigrationComplete(provider: .claude))
        XCTAssertTrue(logs.messages.isEmpty, "happy path must not log failures: \(logs.messages)")
    }

    // MARK: - Write-failure observability

    func testFileWriteFailureIsLoggedAndRefreshStillSucceeds() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-refresh-io-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let authPath = directory.appendingPathComponent("auth.json")
        let staleJSON = codexAuthJSON(
            accessToken: "access-old",
            refreshToken: "refresh-old",
            accountID: "team-old",
            idToken: codexIDToken(email: "old@example.com", subject: "sub-old")
        )
        try staleJSON.write(to: authPath, atomically: true, encoding: .utf8)

        OAuthRefreshMockURLProtocol.requestHandler = { request in
            let responseBody: [String: Any] = [
                "access_token": "access-new",
                "refresh_token": "refresh-new"
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: responseBody)
            )
        }

        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        let service = CodexDesktopAuthService(
            homeDirectory: { directory.path },
            environment: { ["CODEX_HOME": directory.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true },
            oauthVault: vault
        )
        let logs = LogRecorder()
        let failingWriteIO = OAuthRefreshPipeline.FileIO(
            read: { try Data(contentsOf: URL(fileURLWithPath: $0)) },
            write: { _, _ in throw CocoaError(.fileWriteUnknown) }
        )

        let refreshed = try await service.refreshAuthJSON(
            session: makeSession(),
            rawAuthJSON: staleJSON,
            fileIO: failingWriteIO,
            now: { fixedNow },
            log: { logs.append($0) }
        )

        // The refresh itself still counts as successful: the returned value
        // carries the freshly accepted tokens.
        let refreshedJSON = try XCTUnwrap(refreshed)
        let refreshedPayload = try CodexAccountProfileStore.parseAuthJSON(refreshedJSON)
        XCTAssertEqual(refreshedPayload.accessToken, "access-new")

        // The failed merge write is observable instead of silently swallowed.
        XCTAssertEqual(logs.messages.count, 1, "got \(logs.messages)")
        XCTAssertTrue(
            logs.messages[0].contains(authPath.path),
            "log should name the failed path: \(logs.messages[0])"
        )
        XCTAssertTrue(
            logs.messages[0].contains("failed to merge"),
            "log should describe the failure: \(logs.messages[0])"
        )

        // The on-disk file is left untouched and the vault write still runs.
        let onDisk = try JSONSerialization.jsonObject(with: Data(contentsOf: authPath)) as? [String: Any]
        let tokens = try XCTUnwrap(onDisk?["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["access_token"] as? String, "access-old")
        XCTAssertEqual(
            vault.readOAuthJSON(provider: .codex),
            refreshedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testCorruptCredentialFileMergeFailureIsLogged() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-refresh-decode-fail-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let credentialPath = configDir.appendingPathComponent(".credentials.json")
        let staleJSON = claudeCredentialsJSON()
        try Data("not a json object".utf8).write(to: credentialPath)

        OAuthRefreshMockURLProtocol.requestHandler = { request in
            let responseBody: [String: Any] = [
                "access_token": "access-new",
                "refresh_token": "refresh-new",
                "expires_in": 3600
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: responseBody)
            )
        }

        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true },
            oauthVault: vault
        )
        let logs = LogRecorder()

        let refreshed = try await service.refreshCredentialsJSON(
            session: makeSession(),
            rawCredentialsJSON: staleJSON,
            now: { fixedNow },
            log: { logs.append($0) }
        )

        let refreshedJSON = try XCTUnwrap(refreshed)
        let refreshedPayload = try ClaudeAccountProfileStore.parseCredentialsJSON(refreshedJSON)
        XCTAssertEqual(refreshedPayload.accessToken, "access-new")

        XCTAssertEqual(logs.messages.count, 1, "got \(logs.messages)")
        XCTAssertTrue(
            logs.messages[0].contains(credentialPath.path),
            "log should name the failed path: \(logs.messages[0])"
        )
        XCTAssertEqual(
            try String(contentsOf: credentialPath, encoding: .utf8),
            "not a json object",
            "a failed decode must not corrupt or rewrite the file"
        )
        XCTAssertEqual(
            vault.readOAuthJSON(provider: .claude),
            refreshedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testVaultWriteFailureIsLoggedAndRefreshStillSucceeds() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-refresh-vault-fail-\(UUID().uuidString)", isDirectory: true)
        let configDir = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let credentialPath = configDir.appendingPathComponent(".credentials.json")
        let staleJSON = claudeCredentialsJSON()
        try staleJSON.write(to: credentialPath, atomically: true, encoding: .utf8)

        OAuthRefreshMockURLProtocol.requestHandler = { request in
            let responseBody: [String: Any] = [
                "access_token": "access-new",
                "refresh_token": "refresh-new",
                "expires_in": 3600
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: responseBody)
            )
        }

        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: FailingTokenCredentialStore(), defaults: defaults)
        let service = ClaudeDesktopAuthService(
            homeDirectory: { home.path },
            environment: { ["CLAUDE_CONFIG_DIR": configDir.path] },
            keychainReader: { nil },
            keychainWriter: { _ in true },
            oauthVault: vault
        )
        let logs = LogRecorder()

        let refreshed = try await service.refreshCredentialsJSON(
            session: makeSession(),
            rawCredentialsJSON: staleJSON,
            now: { fixedNow },
            log: { logs.append($0) }
        )

        // The refresh still counts as successful and the file write-back ran.
        let refreshedJSON = try XCTUnwrap(refreshed)
        let refreshedPayload = try ClaudeAccountProfileStore.parseCredentialsJSON(refreshedJSON)
        XCTAssertEqual(refreshedPayload.accessToken, "access-new")
        let onDisk = try JSONSerialization.jsonObject(
            with: Data(contentsOf: credentialPath)
        ) as? [String: Any]
        let oauth = try XCTUnwrap(onDisk?["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(oauth["accessToken"] as? String, "access-new")

        // The vault failure is observable instead of silently swallowed.
        XCTAssertEqual(logs.messages.count, 1, "got \(logs.messages)")
        XCTAssertTrue(
            logs.messages[0].contains("app vault"),
            "log should name the failed vault write: \(logs.messages[0])"
        )
        XCTAssertNil(vault.readOAuthJSON(provider: .claude))
    }

    // MARK: - Semantics preservation

    func testRefreshReturnsNilWhenRefreshTokenIsMissing() async throws {
        OAuthRefreshMockURLProtocol.requestHandler = { _ in
            throw URLError(.badURL)
        }

        let codexService = CodexDesktopAuthService(
            homeDirectory: { NSTemporaryDirectory() },
            environment: { [:] },
            keychainReader: { nil },
            keychainWriter: { _ in true }
        )
        let codexWithoutRefreshToken = #"""
        {
          "tokens": {
            "access_token": "access-only"
          }
        }
        """#
        let codexRefreshed = try await codexService.refreshAuthJSON(
            session: makeSession(),
            rawAuthJSON: codexWithoutRefreshToken
        )
        XCTAssertNil(codexRefreshed)

        let claudeService = ClaudeDesktopAuthService(
            homeDirectory: { NSTemporaryDirectory() },
            environment: { [:] },
            keychainReader: { nil },
            keychainWriter: { _ in true }
        )
        let claudeWithoutRefreshToken = #"""
        {
          "claudeAiOauth": {
            "accessToken": "access-only",
            "expiresAt": 4102444800000
          }
        }
        """#
        let claudeRefreshed = try await claudeService.refreshCredentialsJSON(
            session: makeSession(),
            rawCredentialsJSON: claudeWithoutRefreshToken
        )
        XCTAssertNil(claudeRefreshed)
    }

    func testRefreshThrowsWhenTokenEndpointRejectsRefresh() async {
        OAuthRefreshMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let service = CodexDesktopAuthService(
            homeDirectory: { NSTemporaryDirectory() },
            environment: { [:] },
            keychainReader: { nil },
            keychainWriter: { _ in true }
        )
        let staleJSON = codexAuthJSON(
            accessToken: "access-old",
            refreshToken: "refresh-revoked",
            accountID: "team-old",
            idToken: codexIDToken(email: "old@example.com", subject: "sub-old")
        )

        do {
            _ = try await service.refreshAuthJSON(
                session: makeSession(),
                rawAuthJSON: staleJSON
            )
            XCTFail("a rejected refresh must throw")
        } catch let error as ProviderError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected provider error: \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthRefreshMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func codexAuthJSON(
        accessToken: String,
        refreshToken: String,
        accountID: String,
        idToken: String
    ) -> String {
        #"""
        {
          "tokens": {
            "access_token": "\#(accessToken)",
            "refresh_token": "\#(refreshToken)",
            "account_id": "\#(accountID)",
            "id_token": "\#(idToken)"
          }
        }
        """#
    }

    private func codexIDToken(email: String, subject: String) -> String {
        let payload = Data(#"{"email":"\#(email)","sub":"\#(subject)"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    private func claudeCredentialsJSON() -> String {
        let root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "access-old",
                "refreshToken": "refresh-old",
                "expiresAt": 1_000 as Double,
                "subscriptionType": "pro",
                "scopes": ["user:profile"]
            ],
            "accountId": "acc-1",
            "email": "claude@example.com"
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}

/// Lock-protected log capture safe to pass into `@Sendable` log closures.
/// Deterministic clock injected into refresh calls.
private let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)

private final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        items.append(message)
    }

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

private final class OAuthRefreshMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = OAuthRefreshMockURLProtocol.requestHandler else {
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

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let httpBody = request.httpBody {
        return httpBody
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: bufferSize)
        if count <= 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data.isEmpty ? nil : data
}
