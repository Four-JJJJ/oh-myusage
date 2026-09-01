import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class OfficialProviderTests: XCTestCase {
    func testConfigMigrationInjectsOfficialProviders() {
        let legacy = AppConfig(language: .zhHans, providers: [])
        let migrated = legacy.migratedWithSiteDefaults()

        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "codex-official" && $0.family == .official }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "claude-official" && $0.family == .official }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "gemini-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "copilot-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "microsoft-copilot-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "zai-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "amp-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "cursor-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "jetbrains-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "kiro-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "windsurf-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "kimi-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "trae-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "openrouter-credits-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "openrouter-api-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "ollama-cloud-official" && $0.family == .official && !$0.enabled }))
        XCTAssertTrue(migrated.providers.contains(where: { $0.id == "opencode-go-official" && $0.family == .official && !$0.enabled }))
    }

    func testLegacyCodexDescriptorNormalizesToOfficialFamily() {
        let legacy = ProviderDescriptor(
            id: "codex-official",
            name: "Official Codex",
            type: .codex,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .localCodex)
        )

        let normalized = legacy.normalized()
        XCTAssertEqual(normalized.family, .official)
        XCTAssertEqual(normalized.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(normalized.officialConfig?.webMode, .autoImport)
    }

    func testCodexAPIResponseParsesQuotaWindows() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": { "used_percent": 25, "reset_at": 1760000000, "limit_window_seconds": 18000 },
            "secondary_window": { "used_percent": 60, "reset_at": 1760500000, "limit_window_seconds": 604800 }
          },
          "code_review_rate_limit": {
            "primary_window": { "used_percent": 10, "reset_at": 1760600000, "limit_window_seconds": 604800 }
          },
          "credits": { "balance": 42.5 }
        }
        """

        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["x-codex-primary-used-percent": "25", "x-codex-secondary-used-percent": "60"]
        )!

        let snapshot = try CodexProvider.parseUsageSnapshot(
            data: Data(json.utf8),
            response: response,
            descriptor: ProviderDescriptor.defaultOfficialCodex(),
            sourceLabel: "API",
            accountLabel: "test@example.com"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "test@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 75, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.remainingPercent ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt,
            Date(timeIntervalSince1970: 1_760_000_000)
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.resetAt,
            Date(timeIntervalSince1970: 1_760_500_000)
        )
        XCTAssertEqual(snapshot.extras["creditsBalance"], "42.50")
    }

    func testCodexAPIResponseAllowsMissingResetAt() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": { "used_percent": 25 },
            "secondary_window": { "used_percent": 60 }
          }
        }
        """

        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let snapshot = try CodexProvider.parseUsageSnapshot(
            data: Data(json.utf8),
            response: response,
            descriptor: ProviderDescriptor.defaultOfficialCodex(),
            sourceLabel: "API",
            accountLabel: nil
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertNil(snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        XCTAssertNil(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.resetAt)
    }

    func testCodexAPIResponseCalibratesResetAtFromServerDateHeader() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": { "used_percent": 25, "reset_at": 1760000000 },
            "secondary_window": { "used_percent": 60, "reset_at": 1760500000 }
          }
        }
        """
        let serverNow = Date(timeIntervalSince1970: 1_750_000_000)
        let localReceiveAt = serverNow.addingTimeInterval(90)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Date": formatter.string(from: serverNow)]
        )!

        let snapshot = try CodexProvider.parseUsageSnapshot(
            data: Data(json.utf8),
            response: response,
            descriptor: ProviderDescriptor.defaultOfficialCodex(),
            sourceLabel: "API",
            accountLabel: nil,
            receivedAt: localReceiveAt
        )
        let sessionReset = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        let weeklyReset = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.resetAt)

        XCTAssertEqual(
            sessionReset.timeIntervalSince1970,
            Date(timeIntervalSince1970: 1_760_000_000).addingTimeInterval(90).timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            weeklyReset.timeIntervalSince1970,
            Date(timeIntervalSince1970: 1_760_500_000).addingTimeInterval(90).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testCodexAPIResponseWithoutServerDateHeaderKeepsResetAt() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": { "used_percent": 25, "reset_at": 1760000000 },
            "secondary_window": { "used_percent": 60, "reset_at": 1760500000 }
          }
        }
        """
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let snapshot = try CodexProvider.parseUsageSnapshot(
            data: Data(json.utf8),
            response: response,
            descriptor: ProviderDescriptor.defaultOfficialCodex(),
            sourceLabel: "API",
            accountLabel: nil,
            receivedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt,
            Date(timeIntervalSince1970: 1_760_000_000)
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.resetAt,
            Date(timeIntervalSince1970: 1_760_500_000)
        )
    }

    func testCodexForceRefreshDoesNotReturnStaleCachedSnapshot() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "codex-provider-tests")
        let authDirectory = homeDirectory.appendingPathComponent(".config/codex", isDirectory: true)
        try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)

        let idTokenPayload = Data(#"{"email":"codex@example.com"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let authJSON = #"""
        {
          "last_refresh": "\#(ISO8601DateFormatter().string(from: Date()))",
          "tokens": {
            "access_token": "codex-access-token",
            "refresh_token": "codex-refresh-token",
            "account_id": "codex-account",
            "id_token": "header.\#(idTokenPayload).signature"
          }
        }
        """#
        try authJSON.write(to: authDirectory.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        var usageRequestCount = 0
        var refreshRequestCount = 0
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            if url.absoluteString == "https://auth.openai.com/oauth/token" {
                refreshRequestCount += 1
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            usageRequestCount += 1
            if usageRequestCount == 1 {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "plan_type": "plus",
                  "rate_limit": {
                    "primary_window": { "used_percent": 25, "reset_at": 1760000000 },
                    "secondary_window": { "used_percent": 60, "reset_at": 1760500000 }
                  }
                }
                """
                return (response, Data(body.utf8))
            }
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.id = "codex-force-refresh-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api
        descriptor.officialConfig?.webMode = .disabled

        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: makeTestKeychain(),
            browserCookieService: BrowserCookieService(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path },
            environment: { [:] }
        )

        let initial = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(initial.remaining ?? -1, 40, accuracy: 0.001)

        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("forceRefresh should not fall back to a stale cached snapshot")
        } catch let error as ProviderError {
            if case .unauthorized = error {
                XCTAssertEqual(usageRequestCount, 2)
                XCTAssertEqual(refreshRequestCount, 1)
            } else {
                XCTFail("unexpected provider error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCodexAPIRefreshesAndRetriesWhenUsageRejectsStaleAccessToken() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "codex-provider-refresh-tests")
        let authDirectory = homeDirectory.appendingPathComponent(".config/codex", isDirectory: true)
        try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)
        let authPath = authDirectory.appendingPathComponent("auth.json")
        let idToken = makeJWT(email: "codex@example.com")
        let initialAuthJSON = #"""
        {
          "last_refresh": "2099-06-08T14:00:00Z",
          "tokens": {
            "access_token": "stale-access-token",
            "refresh_token": "codex-refresh-token",
            "account_id": "codex-account",
            "id_token": "\#(idToken)"
          }
        }
        """#
        try writeText(initialAuthJSON, to: authPath)

        var usageRequestCount = 0
        var didRefresh = false
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            if url.absoluteString == "https://auth.openai.com/oauth/token" {
                didRefresh = true
                XCTAssertEqual(request.httpMethod, "POST")
                let body = String(data: try XCTUnwrap(requestBodyData(request)), encoding: .utf8) ?? ""
                XCTAssertTrue(body.contains("grant_type=refresh_token"))
                XCTAssertTrue(body.contains("refresh_token=codex-refresh-token"))
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let bodyJSON = #"""
                {
                  "access_token": "fresh-access-token",
                  "refresh_token": "fresh-refresh-token",
                  "id_token": "\#(idToken)"
                }
                """#
                return (response, Data(bodyJSON.utf8))
            }

            XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            usageRequestCount += 1
            if usageRequestCount == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer stale-access-token")
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-access-token")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": { "used_percent": 25, "reset_at": 1760000000 },
                "secondary_window": { "used_percent": 60, "reset_at": 1760500000 }
              }
            }
            """
            return (response, Data(body.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.id = "codex-usage-401-refresh-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api
        descriptor.officialConfig?.webMode = .disabled

        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: makeTestKeychain(),
            browserCookieService: BrowserCookieService(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path },
            environment: { [:] }
        )

        let snapshot = try await provider.fetch(forceRefresh: true)

        XCTAssertEqual(snapshot.remaining ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(usageRequestCount, 2)
        XCTAssertTrue(didRefresh)
        let persisted = try String(contentsOf: authPath, encoding: .utf8)
        XCTAssertTrue(persisted.contains("fresh-access-token"))
        XCTAssertTrue(persisted.contains("fresh-refresh-token"))
    }

    func testCodexLoadCredentialsPrefersVaultOverLocalFilesAndSkipsExternalKeychain() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "codex-vault-priority")
        let authDirectory = homeDirectory.appendingPathComponent(".config/codex", isDirectory: true)
        try writeText(
            codexAuthJSON(accessToken: "file-codex-access"),
            to: authDirectory.appendingPathComponent("auth.json")
        )
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let vault = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)
        XCTAssertTrue(
            vault.saveOAuthJSON(provider: .codex, rawJSON: codexAuthJSON(accessToken: "vault-codex-access"))
        )

        var authorizationHeaders: [String] = []
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": { "used_percent": 25, "reset_at": 1760000000 },
                "secondary_window": { "used_percent": 60, "reset_at": 1760500000 }
              }
            }
            """
            return (response, Data(body.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.id = "codex-vault-priority-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api
        descriptor.officialConfig?.webMode = .disabled

        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: BrowserCookieService(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path },
            environment: { [:] }
        )

        _ = try await provider.fetch(forceRefresh: true)

        XCTAssertEqual(authorizationHeaders, ["Bearer vault-codex-access"])
    }

    func testCodexRefreshUpdatesVaultWhenCredentialComesFromVault() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "codex-vault-refresh")
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let vault = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)
        let idToken = makeJWT(email: "vault-refresh@example.com")
        XCTAssertTrue(
            vault.saveOAuthJSON(
                provider: .codex,
                rawJSON: #"""
                {
                  "last_refresh": "2020-01-01T00:00:00Z",
                  "tokens": {
                    "access_token": "stale-vault-codex-access",
                    "refresh_token": "vault-codex-refresh-token",
                    "account_id": "vault-codex-account",
                    "id_token": "\#(idToken)"
                  }
                }
                """#
            )
        )

        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            if url.absoluteString == "https://auth.openai.com/oauth/token" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let bodyJSON = #"""
                {
                  "access_token": "fresh-vault-codex-access",
                  "refresh_token": "fresh-vault-codex-refresh",
                  "id_token": "\#(idToken)"
                }
                """#
                return (response, Data(bodyJSON.utf8))
            }

            XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-vault-codex-access")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": { "used_percent": 10, "reset_at": 1760000000 },
                "secondary_window": { "used_percent": 20, "reset_at": 1760500000 }
              }
            }
            """
            return (response, Data(body.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.id = "codex-vault-refresh-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api
        descriptor.officialConfig?.webMode = .disabled

        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: BrowserCookieService(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path },
            environment: { [:] }
        )

        let snapshot = try await provider.fetch(forceRefresh: false)

        XCTAssertEqual(snapshot.remaining ?? -1, 80, accuracy: 0.001)
        let vaultJSON = try XCTUnwrap(vault.readOAuthJSON(provider: .codex))
        XCTAssertTrue(vaultJSON.contains("fresh-vault-codex-access"))
        XCTAssertTrue(vaultJSON.contains("fresh-vault-codex-refresh"))
        XCTAssertFalse(vaultJSON.contains("stale-vault-codex-access"))
    }

    func testCodexMissingCredentialWhenVaultAndFilesAbsent() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "codex-vault-missing")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.id = "codex-vault-missing-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api
        descriptor.officialConfig?.webMode = .disabled

        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: makeTestKeychain(),
            browserCookieService: BrowserCookieService(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path },
            environment: { [:] }
        )

        do {
            _ = try await provider.fetch(forceRefresh: false)
            XCTFail("expected missing credential failure")
        } catch let error as ProviderError {
            guard case .missingCredential = error else {
                return XCTFail("unexpected provider error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testClaudeLoadCredentialsPrefersVaultOverLocalFiles() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "claude-vault-priority")
        try writeText(
            claudeCredentialsJSON(accessToken: "file-claude-access"),
            to: homeDirectory.appendingPathComponent(".claude/.credentials.json")
        )
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let vault = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)
        XCTAssertTrue(
            vault.saveOAuthJSON(provider: .claude, rawJSON: claudeCredentialsJSON(accessToken: "vault-claude-access"))
        )

        var authorizationHeaders: [String] = []
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://api.anthropic.com/api/oauth/usage")
            authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "five_hour": { "utilization": 30, "resets_at": "2026-04-11T10:00:00Z" },
              "seven_day": { "utilization": 55, "resets_at": "2026-04-17T00:00:00Z" }
            }
            """
            return (response, Data(body.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialClaude()
        descriptor.id = "claude-vault-priority-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api
        descriptor.officialConfig?.webMode = .disabled

        let provider = ClaudeProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: BrowserCookieService(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path }
        )

        _ = try await provider.fetch(forceRefresh: true)

        XCTAssertEqual(authorizationHeaders, ["Bearer vault-claude-access"])
    }

    func testClaudeRefreshUpdatesVaultWhenCredentialComesFromVault() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "claude-vault-refresh")
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let keychain = makeTestKeychain()
        let vault = OfficialOAuthVaultStore(keychain: keychain, defaults: defaults)
        let soonExpiryMs = Date().timeIntervalSince1970 * 1000 + 1_000
        XCTAssertTrue(
            vault.saveOAuthJSON(
                provider: .claude,
                rawJSON: #"""
                {
                  "claudeAiOauth": {
                    "accessToken": "stale-vault-claude-access",
                    "refreshToken": "vault-claude-refresh-token",
                    "expiresAt": \#(soonExpiryMs),
                    "subscriptionType": "pro",
                    "scopes": ["user:profile"]
                  }
                }
                """#
            )
        )

        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            if url.absoluteString == "https://platform.claude.com/v1/oauth/token" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let bodyJSON = """
                {
                  "access_token": "fresh-vault-claude-access",
                  "refresh_token": "fresh-vault-claude-refresh",
                  "expires_in": 3600
                }
                """
                return (response, Data(bodyJSON.utf8))
            }

            XCTAssertEqual(url.absoluteString, "https://api.anthropic.com/api/oauth/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-vault-claude-access")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "five_hour": { "utilization": 20, "resets_at": "2026-04-11T10:00:00Z" },
              "seven_day": { "utilization": 40, "resets_at": "2026-04-17T00:00:00Z" }
            }
            """
            return (response, Data(body.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialClaude()
        descriptor.id = "claude-vault-refresh-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api
        descriptor.officialConfig?.webMode = .disabled

        let provider = ClaudeProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: BrowserCookieService(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path }
        )

        _ = try await provider.fetch(forceRefresh: false)

        let vaultJSON = try XCTUnwrap(vault.readOAuthJSON(provider: .claude))
        XCTAssertTrue(vaultJSON.contains("fresh-vault-claude-access"))
        XCTAssertTrue(vaultJSON.contains("fresh-vault-claude-refresh"))
        XCTAssertFalse(vaultJSON.contains("stale-vault-claude-access"))
    }

    private func codexAuthJSON(accessToken: String) -> String {
        let idToken = makeJWT(email: "vault-priority@example.com")
        return #"""
        {
          "last_refresh": "\#(ISO8601DateFormatter().string(from: Date()))",
          "tokens": {
            "access_token": "\#(accessToken)",
            "refresh_token": "vault-codex-refresh",
            "account_id": "vault-codex-account",
            "id_token": "\#(idToken)"
          }
        }
        """#
    }

    private func claudeCredentialsJSON(accessToken: String) -> String {
        #"""
        {
          "claudeAiOauth": {
            "accessToken": "\#(accessToken)",
            "refreshToken": "vault-claude-refresh",
            "expiresAt": 4102444800000,
            "subscriptionType": "pro",
            "scopes": ["user:profile"]
          }
        }
        """#
    }

    func testClaudeForceRefreshDoesNotReturnStaleCachedSnapshot() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "claude-provider-tests")
        let credentialsPath = homeDirectory.appendingPathComponent(".claude/.credentials.json")
        let credentialsJSON = #"""
        {
          "claudeAiOauth": {
            "accessToken": "claude-access-token",
            "expiresAt": 4102444800000,
            "subscriptionType": "pro",
            "scopes": ["user:profile"]
          }
        }
        """#
        try writeText(credentialsJSON, to: credentialsPath)

        var requestCount = 0
        OfficialMockURLProtocol.requestHandler = { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://api.anthropic.com/api/oauth/usage")
            if requestCount == 1 {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "five_hour": { "utilization": 30, "resets_at": "2026-04-11T10:00:00Z" },
                  "seven_day": { "utilization": 55, "resets_at": "2026-04-17T00:00:00Z" }
                }
                """
                return (response, Data(body.utf8))
            }
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialClaude()
        descriptor.id = "claude-force-refresh-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api
        descriptor.officialConfig?.webMode = .disabled

        let provider = ClaudeProvider(
            descriptor: descriptor,
            session: session,
            keychain: makeTestKeychain(),
            browserCookieService: BrowserCookieService(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path }
        )

        let initial = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(initial.remaining ?? -1, 45, accuracy: 0.001)

        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("forceRefresh should not fall back to a stale cached snapshot")
        } catch let error as ProviderError {
            if case .unauthorized = error {
                XCTAssertEqual(requestCount, 2)
            } else {
                XCTFail("unexpected provider error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testGeminiForceRefreshDoesNotReturnStaleCachedSnapshot() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "gemini-provider-tests")
        let geminiDirectory = homeDirectory.appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: geminiDirectory, withIntermediateDirectories: true)
        try writeText(#"{"selectedAuthType":"oauth-personal"}"#, to: geminiDirectory.appendingPathComponent("settings.json"))
        let idToken = makeJWT(email: "gemini@example.com")
        let oauthJSON = #"""
        {
          "access_token": "gemini-access-token",
          "id_token": "\#(idToken)",
          "expiry_date": 4102444800000
        }
        """#
        try writeText(oauthJSON, to: geminiDirectory.appendingPathComponent("oauth_creds.json"))

        var requestCount = 0
        OfficialMockURLProtocol.requestHandler = { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)
            switch requestCount {
            case 1:
                XCTAssertEqual(url.absoluteString, "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{}"#.utf8))
            case 2:
                XCTAssertEqual(url.absoluteString, "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "quotas": [
                    {
                      "quotaId": "gemini-2.5-pro",
                      "usage": { "utilization": 0.40, "resetAt": "2026-04-11T08:00:00Z" }
                    },
                    {
                      "quotaId": "gemini-2.5-flash",
                      "usage": { "utilization": 20, "resetAt": "2026-04-11T02:00:00Z" }
                    }
                  ]
                }
                """
                return (response, Data(body.utf8))
            default:
                XCTAssertEqual(url.absoluteString, "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialGemini()
        descriptor.id = "gemini-force-refresh-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api

        let provider = GeminiProvider(
            descriptor: descriptor,
            session: session,
            cache: SnapshotTimestampOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path }
        )

        let initial = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(initial.remaining ?? -1, 60, accuracy: 0.001)

        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("forceRefresh should not fall back to a stale cached snapshot")
        } catch let error as ProviderError {
            if case .unauthorized = error {
                XCTAssertEqual(requestCount, 3)
            } else {
                XCTFail("unexpected provider error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testKimiForceRefreshDoesNotReturnStaleCachedSnapshot() async throws {
        let homeDirectory = try makeTemporaryHomeDirectory(prefix: "kimi-provider-tests")
        let credentialsPath = homeDirectory.appendingPathComponent(".kimi/credentials/kimi-code.json")
        let credentialsJSON = #"""
        {
          "access_token": "kimi-access-token",
          "expires_at": 4102444800
        }
        """#
        try writeText(credentialsJSON, to: credentialsPath)

        var requestCount = 0
        OfficialMockURLProtocol.requestHandler = { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://api.kimi.com/coding/v1/usages")
            if requestCount == 1 {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "user": {
                    "email": "kimi@example.com",
                    "membership": { "level": "premium" }
                  },
                  "usage": {
                    "remaining_amount": 700,
                    "quota_amount": 1000
                  },
                  "limits": [
                    {
                      "name": "5-hour",
                      "window": { "duration": 300, "time_unit": "TIME_UNIT_MINUTE", "resets_at": "2026-04-10T12:00:00Z" },
                      "usage": { "remaining_amount": 30, "quota_amount": 50 }
                    }
                  ]
                }
                """
                return (response, Data(body.utf8))
            }
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var descriptor = ProviderDescriptor.defaultOfficialKimi()
        descriptor.id = "kimi-force-refresh-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api

        let provider = KimiOfficialProvider(
            descriptor: descriptor,
            session: session,
            keychain: makeTestKeychain(),
            cache: SnapshotTimestampOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { homeDirectory.path }
        )

        let initial = try await provider.fetch(forceRefresh: false)
        XCTAssertEqual(initial.remaining ?? -1, 60, accuracy: 0.001)

        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("forceRefresh should not fall back to a stale cached snapshot")
        } catch let error as ProviderError {
            if case .unauthorized = error {
                XCTAssertEqual(requestCount, 2)
            } else {
                XCTFail("unexpected provider error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCodexWebWithManualCookieSkipsBrowserDetection() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "manual-cookie=ok")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "plan_type": "plus",
              "rate_limit": {
                "primary_window": { "used_percent": 20, "reset_at": 1760000000 },
                "secondary_window": { "used_percent": 40, "reset_at": 1760500000 }
              }
            }
            """
            return (response, Data(body.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let keychain = makeTestKeychain()
        let account = "official/codex/cookie-header-\(UUID().uuidString)"
        XCTAssertTrue(keychain.saveToken("manual-cookie=ok", service: KeychainService.defaultServiceName, account: account))

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.id = "codex-web-manual-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .autoImport
        descriptor.officialConfig?.manualCookieAccount = account

        let spy = SpyBrowserCookieDetector()
        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain,
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate()
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.sourceLabel, "Web")
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 0)
    }

    func testOfficialKimiPrefersSavedCodingAPIKey() async throws {
        let keychain = makeTestKeychain()
        var descriptor = ProviderDescriptor.defaultOfficialKimi()
        descriptor.id = "kimi-api-key-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .api
        let service = try XCTUnwrap(descriptor.auth.keychainService)
        let account = try XCTUnwrap(descriptor.auth.keychainAccount)
        XCTAssertTrue(keychain.saveToken("kimi-coding-api-key", service: service, account: account))

        OfficialMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.kimi.com/coding/v1/usages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer kimi-coding-api-key")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "usage": { "used": "40", "limit": "100" },
              "limits": [
                {
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": { "used": "10", "limit": "50" }
                }
              ]
            }
            """
            return (response, Data(body.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let provider = KimiOfficialProvider(
            descriptor: descriptor,
            session: URLSession(configuration: configuration),
            keychain: keychain,
            cache: SnapshotTimestampOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { "/path/that/does/not/exist" }
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.remaining ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.sourceLabel, "API")
    }

    func testCodexWebBackoffSkipsRepeatedBrowserReadAndForceRefreshBypasses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        OfficialMockURLProtocol.requestHandler = { request in
            XCTFail("browser cookie missing should fail before network request, got \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url ?? URL(string: "https://chatgpt.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        var descriptor = ProviderDescriptor.defaultOfficialCodex()
        descriptor.id = "codex-web-backoff-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .autoImport
        descriptor.officialConfig?.manualCookieAccount = "official/codex/cookie-header-\(UUID().uuidString)"

        let spy = SpyBrowserCookieDetector()
        let provider = CodexProvider(
            descriptor: descriptor,
            session: session,
            keychain: makeTestKeychain(),
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate()
        )

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: false)
        }
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: false)
        }
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: true)
        }
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 2)
    }

    func testWebOverlayReusesDetectedCookieForBackgroundRefreshUntilForced() async throws {
        let providerKey = "test-overlay-cache-\(UUID().uuidString)"
        let host = "\(providerKey).example.com"
        let spy = SpyBrowserCookieDetector()
        spy.cookieHeaderResult = BrowserCookieHeader(header: "session=first", source: "Auto:Test")
        let strategy = OfficialBrowserCookieImportStrategy(
            providerKey: providerKey,
            hostContains: host,
            namedCookie: nil,
            autoImportMissingCredential: "missing auto cookie",
            manualCredentialFallback: "manual cookie",
            normalizeManualHeader: { $0 },
            normalizeDetectedHeader: { $0 }
        )

        let first = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: OfficialProviderConfig(sourceMode: .web, webMode: .autoImport),
            descriptorID: "\(providerKey)-descriptor",
            keychain: makeTestKeychain(),
            browserCookieService: spy,
            forceRefresh: true,
            strategy: strategy
        )
        XCTAssertEqual(first.header, "session=first")
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        spy.cookieHeaderResult = BrowserCookieHeader(header: "session=second", source: "Auto:Test")
        let cached = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: OfficialProviderConfig(sourceMode: .web, webMode: .autoImport),
            descriptorID: "\(providerKey)-descriptor",
            keychain: makeTestKeychain(),
            browserCookieService: spy,
            forceRefresh: false,
            strategy: strategy
        )
        XCTAssertEqual(cached.header, "session=first")
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        let refreshed = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: OfficialProviderConfig(sourceMode: .web, webMode: .autoImport),
            descriptorID: "\(providerKey)-descriptor",
            keychain: makeTestKeychain(),
            browserCookieService: spy,
            forceRefresh: true,
            strategy: strategy
        )
        XCTAssertEqual(refreshed.header, "session=second")
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 2)
    }

    func testWebOverlayCachesMissingCookieUntilForced() async throws {
        let providerKey = "test-overlay-missing-cache-\(UUID().uuidString)"
        let host = "\(providerKey).example.com"
        let spy = SpyBrowserCookieDetector()
        let strategy = OfficialBrowserCookieImportStrategy(
            providerKey: providerKey,
            hostContains: host,
            namedCookie: nil,
            autoImportMissingCredential: "missing auto cookie",
            manualCredentialFallback: "manual cookie",
            normalizeManualHeader: { $0 },
            normalizeDetectedHeader: { $0 }
        )

        await XCTAssertThrowsProviderError {
            _ = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
                official: OfficialProviderConfig(sourceMode: .web, webMode: .autoImport),
                descriptorID: "\(providerKey)-descriptor",
                keychain: makeTestKeychain(),
                browserCookieService: spy,
                forceRefresh: false,
                strategy: strategy
            )
        }
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        await XCTAssertThrowsProviderError {
            _ = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
                official: OfficialProviderConfig(sourceMode: .web, webMode: .autoImport),
                descriptorID: "\(providerKey)-descriptor",
                keychain: makeTestKeychain(),
                browserCookieService: spy,
                forceRefresh: false,
                strategy: strategy
            )
        }
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        spy.cookieHeaderResult = BrowserCookieHeader(header: "session=forced", source: "Auto:Test")
        let refreshed = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: OfficialProviderConfig(sourceMode: .web, webMode: .autoImport),
            descriptorID: "\(providerKey)-descriptor",
            keychain: makeTestKeychain(),
            browserCookieService: spy,
            forceRefresh: true,
            strategy: strategy
        )
        XCTAssertEqual(refreshed.header, "session=forced")
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 2)
    }

    func testWebOverlayBackgroundRefreshUsesBackgroundIntentAndNeverAuthRecovery() async throws {
        let providerKey = "test-overlay-intent-\(UUID().uuidString)"
        let host = "\(providerKey).example.com"
        let spy = SpyBrowserCookieDetector()
        let strategy = OfficialBrowserCookieImportStrategy(
            providerKey: providerKey,
            hostContains: host,
            namedCookie: nil,
            autoImportMissingCredential: "missing auto cookie",
            manualCredentialFallback: "manual cookie",
            normalizeManualHeader: { $0 },
            normalizeDetectedHeader: { $0 }
        )

        // Background refresh resolves with the .background intent only; the
        // browser service itself refuses live lookups for that intent.
        await XCTAssertThrowsProviderError {
            _ = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
                official: OfficialProviderConfig(sourceMode: .web, webMode: .autoImport),
                descriptorID: "\(providerKey)-descriptor",
                keychain: makeTestKeychain(),
                browserCookieService: spy,
                forceRefresh: false,
                strategy: strategy
            )
        }
        XCTAssertEqual(spy.recordedIntents, [.background])

        // The user-initiated force refresh is the interactive import path.
        spy.cookieHeaderResult = BrowserCookieHeader(header: "session=forced", source: "Auto:Test")
        let refreshed = try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: OfficialProviderConfig(sourceMode: .web, webMode: .autoImport),
            descriptorID: "\(providerKey)-descriptor",
            keychain: makeTestKeychain(),
            browserCookieService: spy,
            forceRefresh: true,
            strategy: strategy
        )
        XCTAssertEqual(refreshed.header, "session=forced")
        XCTAssertEqual(spy.recordedIntents, [.background, .interactiveImport])
        XCTAssertFalse(spy.recordedIntents.contains(.authRecovery), "Web overlay never triggers browser recovery on its own")
    }

    func testClaudeWebBackoffSkipsRepeatedBrowserRead() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        OfficialMockURLProtocol.requestHandler = { request in
            XCTFail("browser cookie missing should fail before network request, got \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url ?? URL(string: "https://claude.ai")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        var descriptor = ProviderDescriptor.defaultOfficialClaude()
        descriptor.id = "claude-web-backoff-\(UUID().uuidString)"
        descriptor.officialConfig?.sourceMode = .web
        descriptor.officialConfig?.webMode = .autoImport
        descriptor.officialConfig?.manualCookieAccount = "official/claude/cookie-header-\(UUID().uuidString)"

        let spy = SpyBrowserCookieDetector()
        let provider = ClaudeProvider(
            descriptor: descriptor,
            session: session,
            keychain: makeTestKeychain(),
            browserCookieService: spy,
            webReadBackoff: WebOverlayRetryBackoff(),
            cache: FetchedAtOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate()
        )

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: false)
        }
        XCTAssertEqual(spy.detectNamedCookieCallCount, 1)
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)

        await XCTAssertThrowsProviderError {
            _ = try await provider.fetch(forceRefresh: false)
        }
        XCTAssertEqual(spy.detectNamedCookieCallCount, 1)
        XCTAssertEqual(spy.detectCookieHeaderCallCount, 1)
    }

    func testClaudeOAuthResponseParsesWindowsAndExtraUsage() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 30, "resets_at": "2026-04-11T10:00:00Z"],
            "seven_day": ["utilization": 55, "resets_at": "2026-04-17T00:00:00Z"],
            "seven_day_opus": ["utilization": 80, "resets_at": "2026-04-17T00:00:00Z"],
            "extra_usage": ["used_credits": 1200, "monthly_limit": 5000]
        ]

        let snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialClaude(),
            sourceLabel: "API",
            accountLabel: "claude@example.com",
            planHint: "pro"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "claude@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 70, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.remainingPercent ?? -1, 45, accuracy: 0.001)
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt,
            ISO8601DateFormatter().date(from: "2026-04-11T10:00:00Z")
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.resetAt,
            ISO8601DateFormatter().date(from: "2026-04-17T00:00:00Z")
        )
        XCTAssertEqual(snapshot.extras["extraUsageCost"], "1200.00")
        XCTAssertEqual(snapshot.extras["extraUsageLimit"], "5000.00")
    }

    func testClaudeOAuthResponseNormalizesKnownModelWindowTitles() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 10, "resets_at": "2026-04-11T10:00:00Z"],
            "seven_day": ["utilization": 20, "resets_at": "2026-04-17T00:00:00Z"],
            "seven_day_sonnet_only": ["utilization": 12, "resets_at": "2026-04-17T12:00:00Z"],
            "seven_day_claude_design": ["utilization": 34, "resets_at": "2026-04-19T23:00:00Z"]
        ]

        let snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialClaude(),
            sourceLabel: "API",
            accountLabel: nil,
            planHint: "max"
        )

        XCTAssertNotNil(snapshot.quotaWindows.first(where: { $0.title == "Sonnet only" }))
        XCTAssertNotNil(snapshot.quotaWindows.first(where: { $0.title == "Claude Design" }))
        XCTAssertEqual(
            snapshot.rawMeta["claude.parsedSevenDayKeys"],
            "seven_day_claude_design,seven_day_sonnet_only"
        )
        XCTAssertEqual(snapshot.rawMeta["claude.window.sonnetOnly"], "present")
        XCTAssertEqual(snapshot.rawMeta["claude.window.claudeDesign"], "present")
    }

    func testClaudeOAuthResponseParsesFractionalSecondResetDate() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 30, "resets_at": "2026-04-11T10:00:00.123Z"],
            "seven_day": ["utilization": 55, "resets_at": "2026-04-17T00:00:00Z"]
        ]

        let snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialClaude(),
            sourceLabel: "API",
            accountLabel: nil,
            planHint: "pro"
        )

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = try XCTUnwrap(fractionalFormatter.date(from: "2026-04-11T10:00:00.123Z"))
        let actual = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        XCTAssertEqual(actual.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testClaudeOAuthResponseAllowsMissingResetDate() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 30],
            "seven_day": ["utilization": 55]
        ]

        let snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialClaude(),
            sourceLabel: "API",
            accountLabel: nil,
            planHint: "pro"
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertNil(snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        XCTAssertNil(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.resetAt)
    }

    func testClaudeOAuthResponseCalibratesResetAtFromServerDateHeader() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 30, "resets_at": "2026-04-11T10:00:00Z"],
            "seven_day": ["utilization": 55, "resets_at": "2026-04-17T00:00:00Z"]
        ]
        let serverNow = Date(timeIntervalSince1970: 1_750_000_000)
        let localReceiveAt = serverNow.addingTimeInterval(120)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Date": formatter.string(from: serverNow)]
        )!

        let snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            response: response,
            descriptor: ProviderDescriptor.defaultOfficialClaude(),
            sourceLabel: "API",
            accountLabel: nil,
            planHint: "pro",
            receivedAt: localReceiveAt
        )
        let sessionReset = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        let weeklyReset = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.resetAt)
        let expectedSession = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-04-11T10:00:00Z")
        ).addingTimeInterval(120)
        let expectedWeekly = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-04-17T00:00:00Z")
        ).addingTimeInterval(120)

        XCTAssertEqual(
            sessionReset.timeIntervalSince1970,
            expectedSession.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            weeklyReset.timeIntervalSince1970,
            expectedWeekly.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testClaudeOAuthResponseWithoutServerDateHeaderKeepsResetAt() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 30, "resets_at": "2026-04-11T10:00:00Z"],
            "seven_day": ["utilization": 55, "resets_at": "2026-04-17T00:00:00Z"]
        ]
        let snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            response: nil,
            descriptor: ProviderDescriptor.defaultOfficialClaude(),
            sourceLabel: "API",
            accountLabel: nil,
            planHint: "pro",
            receivedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )

        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt,
            ISO8601DateFormatter().date(from: "2026-04-11T10:00:00Z")
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.resetAt,
            ISO8601DateFormatter().date(from: "2026-04-17T00:00:00Z")
        )
    }

    func testClaudeOAuthResponseWithoutPlanAndWithAllZeroUsageIsRejected() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 0],
            "seven_day": ["utilization": 0]
        ]

        XCTAssertThrowsError(
            try ClaudeProvider.parseClaudeSnapshot(
                root: root,
                descriptor: ProviderDescriptor.defaultOfficialClaude(),
                sourceLabel: "API",
                accountLabel: nil,
                planHint: nil
            )
        ) { error in
            guard case let ProviderError.unavailable(message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("subscription"))
        }
    }

    func testGeminiQuotaResponseParsesProAndFlashWindows() throws {
        let quotaRoot: [String: Any] = [
            "quotaInfos": [
                [
                    "quotaId": "gemini-2.5-pro",
                    "usage": ["utilization": 0.40, "resetAt": "2026-04-11T08:00:00Z"],
                ],
                [
                    "quotaId": "gemini-2.5-flash",
                    "usage": ["utilization": 20, "resetAt": "2026-04-11T02:00:00Z"],
                ],
            ]
        ]
        let codeAssistRoot: [String: Any] = ["tierId": "legacy-pro"]

        let snapshot = try GeminiProvider.parseQuotaSnapshot(
            root: quotaRoot,
            codeAssistRoot: codeAssistRoot,
            descriptor: ProviderDescriptor.defaultOfficialGemini(),
            sourceLabel: "API",
            accountLabel: "gemini@example.com",
            projectLabel: "demo-project"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "gemini@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Pro" })?.remainingPercent ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Flash" })?.remainingPercent ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "pro")
        XCTAssertEqual(snapshot.extras["project"], "demo-project")
        XCTAssertEqual(snapshot.rawMeta["gemini.rawModel.count"], "2")
        let rawModelIDs = snapshot.rawMeta
            .filter { $0.key.hasSuffix(".id") }
            .map(\.value)
        XCTAssertTrue(rawModelIDs.contains("gemini-2.5-pro"))
        XCTAssertTrue(rawModelIDs.contains("gemini-2.5-flash"))
    }

    func testGeminiQuotaResponseParsesBucketsShapeFromGeminiCLI() throws {
        let quotaRoot: [String: Any] = [
            "buckets": [
                [
                    "modelId": "gemini-2.5-pro",
                    "remainingAmount": "400",
                    "remainingFraction": 0.40,
                    "resetTime": "2026-04-11T08:00:00Z",
                ],
                [
                    "modelId": "gemini-2.5-flash",
                    "remainingAmount": "900",
                    "remainingFraction": 0.90,
                    "resetTime": "2026-04-11T02:00:00Z",
                ],
            ]
        ]
        let codeAssistRoot: [String: Any] = [
            "currentTier": ["id": "legacy-pro"],
            "cloudaicompanionProject": "demo-project",
        ]

        let snapshot = try GeminiProvider.parseQuotaSnapshot(
            root: quotaRoot,
            codeAssistRoot: codeAssistRoot,
            descriptor: ProviderDescriptor.defaultOfficialGemini(),
            sourceLabel: "API",
            accountLabel: "gemini@example.com",
            projectLabel: "demo-project"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "gemini@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Pro" })?.remainingPercent ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Flash" })?.remainingPercent ?? -1, 90, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "pro")
        XCTAssertEqual(snapshot.extras["project"], "demo-project")
        XCTAssertEqual(snapshot.rawMeta["gemini.rawModel.count"], "2")
        let rawModelIDs = snapshot.rawMeta
            .filter { $0.key.hasSuffix(".id") }
            .map(\.value)
        XCTAssertTrue(rawModelIDs.contains("gemini-2.5-pro"))
        XCTAssertTrue(rawModelIDs.contains("gemini-2.5-flash"))
    }

    func testGeminiClientSecretParserSupportsNewBundleConstants() {
        let source = #"""
        var OAUTH_CLIENT_ID = "demo-client.apps.googleusercontent.com";
        var OAUTH_CLIENT_SECRET = "demo-secret";
        """#

        let parsed = GeminiProvider.parseClientSecrets(in: source)
        XCTAssertEqual(parsed?.id, "demo-client.apps.googleusercontent.com")
        XCTAssertEqual(parsed?.secret, "demo-secret")
    }

    func testGeminiClientSecretParserSupportsLegacyOAuthFilePattern() {
        let source = #"""
        export const oauthConfig = {
          client_id: "legacy-client.apps.googleusercontent.com",
          client_secret: "legacy-secret"
        };
        """#

        let parsed = GeminiProvider.parseClientSecrets(in: source)
        XCTAssertEqual(parsed?.id, "legacy-client.apps.googleusercontent.com")
        XCTAssertEqual(parsed?.secret, "legacy-secret")
    }

    func testOfficialKimiResponseParsesSessionAndOverallUsage() throws {
        let root: [String: Any] = [
            "user": [
                "email": "kimi@example.com",
                "membership": ["level": "premium"],
            ],
            "usage": [
                "remaining_amount": 700,
                "quota_amount": 1000,
            ],
            "limits": [
                [
                    "name": "5-hour",
                    "window": ["duration": 300, "time_unit": "TIME_UNIT_MINUTE", "resets_at": "2026-04-10T12:00:00Z"],
                    "usage": ["remaining_amount": 30, "quota_amount": 50],
                ]
            ],
        ]

        let snapshot = try KimiOfficialProvider.parseUsageSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialKimi(),
            sourceLabel: "API"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "kimi@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Overall" })?.remainingPercent ?? -1, 70, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "premium")
        XCTAssertEqual(snapshot.rawMeta["kimi.rawModel.count"], "2")
        let rawModelIDs = snapshot.rawMeta
            .filter { $0.key.hasSuffix(".id") }
            .map(\.value)
        XCTAssertTrue(rawModelIDs.contains("5-hour"))
    }

    func testOfficialKimiResponseParsesResetTimeFromCamelCaseAndEpochMillis() throws {
        let root: [String: Any] = [
            "user": [
                "email": "kimi@example.com",
                "membership": ["level": "premium"],
            ],
            "usage": [
                "remaining_amount": 620,
                "quota_amount": 1000,
                "nextCycleAt": 1_776_000_000_000 as Double,
            ],
            "limits": [
                [
                    "name": "5-hour",
                    "window": ["duration": 300, "timeUnit": "TIME_UNIT_MINUTE"],
                    "usage": [
                        "remaining_amount": 35,
                        "quota_amount": 50,
                        "resetTime": "2026-04-11T12:30:00Z",
                    ],
                ]
            ],
        ]

        let snapshot = try KimiOfficialProvider.parseUsageSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialKimi(),
            sourceLabel: "API"
        )

        XCTAssertNotNil(snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt)
        XCTAssertNotNil(snapshot.quotaWindows.first(where: { $0.title == "Overall" })?.resetAt)
    }

    func testOfficialKimiResponseParsesCurrentUsedLimitWireShape() throws {
        // Current /coding/v1/usages payload (kimi-code 0.18+ era): decimal-string
        // `used`/`limit` under `usage` summary and per-window `detail`, with no
        // remaining/quota fields at all.
        let root: [String: Any] = [
            "usage": ["used": "40", "limit": "1000", "resetTime": "2030-01-08T00:00:00.000Z"],
            "limits": [
                [
                    "window": ["duration": 300, "timeUnit": "TIME_UNIT_MINUTE"],
                    "detail": ["used": "10", "limit": "100", "resetTime": "2030-01-01T05:00:00.000Z"],
                ],
                [
                    "window": ["duration": 7, "timeUnit": "TIME_UNIT_DAY"],
                    "detail": ["used": "30", "limit": "200", "resetTime": "2030-01-08T00:00:00.000Z"],
                ],
            ],
        ]

        let snapshot = try KimiOfficialProvider.parseUsageSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialKimi(),
            sourceLabel: "API"
        )

        let session = snapshot.quotaWindows.first(where: { $0.kind == .session })
        XCTAssertEqual(session?.remainingPercent ?? -1, 90, accuracy: 0.001)
        XCTAssertNotNil(session?.resetAt)

        let weekly = snapshot.quotaWindows.first(where: { $0.kind == .weekly })
        XCTAssertEqual(weekly?.remainingPercent ?? -1, 85, accuracy: 0.001)

        XCTAssertFalse(snapshot.quotaWindows.isEmpty)
    }

    func testOfficialKimiResponseParsesHourAndWeekTimeUnits() throws {
        let root: [String: Any] = [
            "limits": [
                [
                    "window": ["duration": 5, "timeUnit": "TIME_UNIT_HOUR"],
                    "detail": ["used": "25", "limit": "100"],
                ],
                [
                    "window": ["duration": 1, "timeUnit": "TIME_UNIT_WEEK"],
                    "detail": ["used": "10", "limit": "50"],
                ],
            ],
        ]

        let snapshot = try KimiOfficialProvider.parseUsageSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialKimi(),
            sourceLabel: "API"
        )

        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 75, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.remainingPercent ?? -1, 80, accuracy: 0.001)
    }

    func testCopilotResponseParsesPremiumAndChat() throws {
        let json = """
        {
          "copilot_plan": "pro",
          "quota_reset_date": "2026-04-30T00:00:00Z",
          "quota_snapshots": {
            "premium_interactions": { "percent_remaining": 80, "entitlement": 300, "remaining": 240 },
            "chat": { "percent_remaining": 95, "entitlement": 1000, "remaining": 950 }
          }
        }
        """

        let snapshot = try CopilotProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialCopilot()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Premium" })?.remainingPercent ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "pro")
        XCTAssertEqual(snapshot.sourceLabel, "GitHub API")
    }

    func testCopilotResponseDerivesPercentAndFiltersPlaceholderAndUndefinedPlan() throws {
        let json = """
        {
          "copilot_plan": " undefined ",
          "login": "octocat",
          "quota_snapshots": {
            "placeholder_window": { "percent_remaining": "0", "entitlement": "0", "remaining": "0" },
            "premium_interactions": { "entitlement": "300", "remaining": "240" },
            "chat_messages": { "entitlement": "200", "remaining": "180" }
          }
        }
        """

        let snapshot = try CopilotProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialCopilot()
        )

        XCTAssertEqual(snapshot.accountLabel, "octocat")
        XCTAssertNil(snapshot.extras["planType"])
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "Premium" })?.remainingPercent ?? -1,
            80,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "Chat" })?.remainingPercent ?? -1,
            90,
            accuracy: 0.001
        )
    }

    func testCopilotResponseFallsBackToLimitedAndMonthlyWhenSnapshotsMissingPercent() throws {
        let json = """
        {
          "quota_snapshots": {
            "chat_v2": { "remaining": "0", "entitlement": "0" }
          },
          "limited_user_reset_date": "2026-05-01",
          "limited_user_quotas": {
            "chat": "475",
            "completions": "90"
          },
          "monthly_quotas": {
            "chat": "500",
            "completions": "100"
          }
        }
        """

        let snapshot = try CopilotProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialCopilot()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "Chat" })?.remainingPercent ?? -1,
            95,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.title == "Completions" })?.remainingPercent ?? -1,
            90,
            accuracy: 0.001
        )
    }

    func testMicrosoftCopilotResponseParsesD7AndD30Summaries() throws {
        let d7Root: [String: Any] = [
            "value": [
                ["reportPeriod": 7, "anyAppActiveUsers": 12, "anyAppEnabledUsers": 20]
            ]
        ]
        let d30Root: [String: Any] = [
            "value": [
                ["reportPeriod": 30, "anyAppActiveUsers": 30, "anyAppEnabledUsers": 40]
            ]
        ]

        let snapshot = try MicrosoftCopilotProvider.parseSnapshot(
            d7Root: d7Root,
            d30Root: d30Root,
            descriptor: ProviderDescriptor.defaultOfficialMicrosoftCopilot()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "D7" })?.remainingPercent ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "D30" })?.remainingPercent ?? -1, 75, accuracy: 0.001)
        XCTAssertEqual(snapshot.sourceLabel, "Graph API")
        XCTAssertEqual(snapshot.extras["planType"], "M365")
    }

    func testMicrosoftCopilotResponseThrowsWhenEnabledUsersMissingOrZero() {
        let d7Root: [String: Any] = [
            "value": [
                ["reportPeriod": 7, "anyAppActiveUsers": 12, "anyAppEnabledUsers": 0]
            ]
        ]
        let d30Root: [String: Any] = [
            "value": [
                ["reportPeriod": 30, "anyAppActiveUsers": 30, "anyAppEnabledUsers": 40]
            ]
        ]

        XCTAssertThrowsError(
            try MicrosoftCopilotProvider.parseSnapshot(
                d7Root: d7Root,
                d30Root: d30Root,
                descriptor: ProviderDescriptor.defaultOfficialMicrosoftCopilot()
            )
        )
    }

    func testZaiResponseParsesSessionWeeklyAndWeb() throws {
        let subscriptionRoot: [String: Any] = [
            "data": [[
                "productName": "GLM Coding Max",
                "inCurrentPeriod": true,
                "nextRenewTime": "2026-05-12",
            ]]
        ]
        let quotaRoot: [String: Any] = [
            "data": [
                "limits": [
                    ["type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 15, "nextResetTime": 1770648402389 as Double],
                    ["type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 45, "nextResetTime": 1771200000000 as Double],
                    ["type": "TIME_LIMIT", "remaining": 2172, "usage": 4000],
                ]
            ]
        ]

        let snapshot = try ZaiProvider.parseSnapshot(
            subscriptionRoot: subscriptionRoot,
            quotaRoot: quotaRoot,
            descriptor: ProviderDescriptor.defaultOfficialZai()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 85, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "GLM Coding Max")
    }

    func testZaiResponseParsesCreditLimitWindows() throws {
        // 新账号（GLM Coding Plan 体验卡 / lite）返回 CREDIT_LIMIT 而非 TOKENS_LIMIT。
        let subscriptionRoot: [String: Any] = [
            "data": [[
                "productName": "GLM Coding Plan 体验卡",
                "inCurrentPeriod": true,
                "nextRenewTime": "2026-09-02",
            ]]
        ]
        let quotaRoot: [String: Any] = [
            "data": [
                "limits": [
                    ["type": "CREDIT_LIMIT", "unit": 3, "number": 5, "usage": 2000, "currentValue": 924, "remaining": 1075, "percentage": 46, "nextResetTime": 1787823303158 as Double],
                    ["type": "CREDIT_LIMIT", "unit": 6, "number": 1, "usage": 2000, "currentValue": 2004, "remaining": 0, "percentage": 100, "nextResetTime": 1788361121998 as Double],
                ]
            ]
        ]

        let snapshot = try ZaiProvider.parseSnapshot(
            subscriptionRoot: subscriptionRoot,
            quotaRoot: quotaRoot,
            descriptor: ProviderDescriptor.defaultOfficialZai()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 54, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.remainingPercent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "GLM Coding Plan 体验卡")
    }

    func testZaiQuotaAuthorizationDoesNotAddBearerPrefix() {
        XCTAssertEqual(
            ZaiProvider.authorizationHeaderValue(apiKey: "  glm-api-key  "),
            "glm-api-key"
        )
    }

    func testZaiBalanceDataWrapperParsesAmount() throws {
        let root: [String: Any] = [
            "success": true,
            "data": ["balance": 42.75]
        ]

        let snapshot = try ZaiProvider.parseBalanceSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialZaiBalance()
        )

        XCTAssertEqual(snapshot.remaining ?? -1, 42.75, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
    }

    func testZaiBalanceAccountReportShapeParsesAvailableBalance() throws {
        // GET /api/biz/account/query-customer-account-report 的真实返回形态。
        let root: [String: Any] = [
            "code": 200,
            "msg": "操作成功",
            "success": true,
            "data": [
                "balance": 20.0,
                "rechargeAmount": 20.0,
                "giveAmount": 0.0,
                "totalSpendAmount": 0.0,
                "availableBalance": 18.5,
                "frozenBalance": 0.0,
            ]
        ]

        let snapshot = try ZaiProvider.parseBalanceSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialZaiBalance()
        )

        XCTAssertEqual(snapshot.remaining ?? -1, 18.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.status, .ok)
    }

    func testZaiBalanceTopLevelAndUnderscoreFieldsParse() throws {
        let topLevel: [String: Any] = ["total_balance": 12.5, "currency": "CNY"]
        let snapshot = try ZaiProvider.parseBalanceSnapshot(
            root: topLevel,
            descriptor: ProviderDescriptor.defaultOfficialZaiBalance()
        )
        XCTAssertEqual(snapshot.remaining ?? -1, 12.5, accuracy: 0.001)

        let deepseekStyle: [String: Any] = [
            "data": ["balance_infos": [["total_balance": "88.10"]]]
        ]
        let parsed = try ZaiProvider.parseBalanceSnapshot(
            root: deepseekStyle,
            descriptor: ProviderDescriptor.defaultOfficialZaiBalance()
        )
        XCTAssertEqual(parsed.remaining ?? -1, 88.1, accuracy: 0.001)
    }

    func testZaiBalanceEmptyResponseThrows() {
        XCTAssertThrowsError(
            try ZaiProvider.parseBalanceSnapshot(
                root: ["success": true, "data": [:]],
                descriptor: ProviderDescriptor.defaultOfficialZaiBalance()
            )
        ) { error in
            guard case ProviderError.invalidResponse(let message) = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
            XCTAssertTrue(message.contains("missing Zhipu balance"))
        }
    }

    func testZaiBalanceConsoleErrorPropagatesMessage() {
        XCTAssertThrowsError(
            try ZaiProvider.parseBalanceSnapshot(
                root: ["success": false, "code": 401, "msg": "令牌已过期或验证不正确"],
                descriptor: ProviderDescriptor.defaultOfficialZaiBalance()
            )
        ) { error in
            guard case ProviderError.invalidResponse(let message) = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
            XCTAssertTrue(message.contains("令牌已过期或验证不正确"))
        }
    }

    func testZaiBalanceDefaultCatalogTargetsBigModelHost() {
        let descriptor = ProviderDescriptor.defaultOfficialZaiBalance()
        XCTAssertEqual(descriptor.id, "zai-balance-official")
        XCTAssertEqual(descriptor.baseURL, "https://open.bigmodel.cn")
        XCTAssertEqual(descriptor.auth.keychainAccount, ZaiProvider.balanceKeychainAccount)
    }

    func testMoonshotBalanceResponseParsesAvailableBalance() throws {
        // GET /v1/users/me/balance 的真实返回形态。
        let root: [String: Any] = [
            "code": 0,
            "status": true,
            "data": [
                "available_balance": 49.9,
                "voucher_balance": 49.9,
                "cash_balance": 0.0,
            ]
        ]

        let snapshot = try MoonshotBalanceProvider.parseBalanceSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialKimiBalance()
        )

        XCTAssertEqual(snapshot.remaining ?? -1, 49.9, accuracy: 0.001)
        XCTAssertEqual(snapshot.unit, "CNY")
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
    }

    func testMoonshotBalanceZeroBalanceWarns() throws {
        let root: [String: Any] = [
            "code": 0,
            "data": ["available_balance": 0.0]
        ]

        let snapshot = try MoonshotBalanceProvider.parseBalanceSnapshot(
            root: root,
            descriptor: ProviderDescriptor.defaultOfficialKimiBalance()
        )

        XCTAssertEqual(snapshot.remaining ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.status, .warning)
    }

    func testMoonshotBalanceMissingFieldsThrows() {
        XCTAssertThrowsError(
            try MoonshotBalanceProvider.parseBalanceSnapshot(
                root: ["code": 0, "data": [:]],
                descriptor: ProviderDescriptor.defaultOfficialKimiBalance()
            )
        ) { error in
            guard case ProviderError.invalidResponse(let message) = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
            XCTAssertTrue(message.contains("missing Moonshot balance"))
        }
    }

    func testMoonshotBalanceErrorCodePropagatesMessage() {
        XCTAssertThrowsError(
            try MoonshotBalanceProvider.parseBalanceSnapshot(
                root: ["code": 401, "message": "Invalid Authentication"],
                descriptor: ProviderDescriptor.defaultOfficialKimiBalance()
            )
        ) { error in
            guard case ProviderError.invalidResponse(let message) = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid Authentication"))
        }
    }

    func testMoonshotBalanceDefaultCatalogTargetsMoonshotHost() {
        let descriptor = ProviderDescriptor.defaultOfficialKimiBalance()
        XCTAssertEqual(descriptor.id, "kimi-balance-official")
        XCTAssertEqual(descriptor.baseURL, "https://api.moonshot.cn")
        XCTAssertEqual(descriptor.auth.kind, .bearer)
        XCTAssertEqual(descriptor.auth.keychainAccount, MoonshotBalanceProvider.balanceKeychainAccount)
    }

    func testZaiCodingPlanCatalogStoresManualAPIKeyInKeychain() {
        let descriptor = ProviderDescriptor.defaultOfficialZai()
        XCTAssertEqual(descriptor.baseURL, "https://api.z.ai")
        XCTAssertEqual(descriptor.auth.kind, .bearer)
        XCTAssertEqual(descriptor.auth.keychainAccount, ZaiProvider.codingPlanKeychainAccount)
    }

    func testZaiCodingPlanHostMirrorFallsBackAcrossRegions() {
        XCTAssertEqual(
            ZaiProvider.codingPlanHosts(primary: "https://api.z.ai"),
            ["https://api.z.ai", "https://open.bigmodel.cn"]
        )
        XCTAssertEqual(
            ZaiProvider.codingPlanHosts(primary: "https://open.bigmodel.cn"),
            ["https://open.bigmodel.cn", "https://api.z.ai"]
        )
    }

    func testZaiStatusFailureDetailIncludesUpstreamMessage() {
        let data = Data(#"{"error":{"code":"1000","message":"身份验证失败。"}}"#.utf8)
        XCTAssertTrue(ZaiProvider.statusFailureDetail(status: 404, data: data).contains("身份验证失败"))
        XCTAssertTrue(ZaiProvider.statusFailureDetail(status: 401, data: Data("not json".utf8)).contains("http 401"))
    }

    func testAmpResponseParsesFreeAndCredits() throws {
        let json = """
        {
          "ok": true,
          "result": {
            "displayText": "Signed in as test\\nAmp Free: $12.50/$20.00 remaining (replenishes +$1.50/hour)\\nIndividual credits: $8.25 remaining"
          }
        }
        """

        let snapshot = try AmpProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialAmp()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Free" })?.remainingPercent ?? -1, 62.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["creditsBalance"], "8.25")
    }

    func testCursorResponseParsesCursorModelsAndOtherModels() throws {
        let json = """
        {
          "membershipType": "pro",
          "billingCycleEnd": "2026-05-01T00:00:00Z",
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 2000,
              "limit": 2000,
              "remaining": 0,
              "autoPercentUsed": 80,
              "apiPercentUsed": 100,
              "totalPercentUsed": 100
            },
            "onDemand": { "enabled": true, "used": 10, "limit": 100, "remaining": 90 }
          }
        }
        """

        let snapshot = try CursorProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialCursor(),
            accountLabel: "cursor@example.com"
        )

        XCTAssertEqual(snapshot.accountLabel, "cursor@example.com")
        XCTAssertEqual(snapshot.extras["planType"], "pro")
        XCTAssertEqual(snapshot.quotaWindows.count, 3)

        let cursorModels = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.title == "Cursor Models" }))
        XCTAssertEqual(cursorModels.usedPercent, 80, accuracy: 0.001)
        XCTAssertEqual(cursorModels.remainingPercent, 20, accuracy: 0.001)

        let otherModels = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.title == "Other Models" }))
        XCTAssertEqual(otherModels.usedPercent, 100, accuracy: 0.001)
        XCTAssertEqual(otherModels.remainingPercent, 0, accuracy: 0.001)

        let onDemand = try XCTUnwrap(snapshot.quotaWindows.first(where: { $0.title == "On-Demand" }))
        XCTAssertEqual(onDemand.remainingPercent, 90, accuracy: 0.001)
    }

    func testCursorResponseFallsBackToMonthlyWithoutPoolPercents() throws {
        let json = """
        {
          "membershipType": "ultra",
          "billingCycleEnd": "2026-05-01T00:00:00Z",
          "individualUsage": {
            "plan": { "enabled": true, "used": 326, "limit": 40000, "remaining": 39674 },
            "onDemand": { "enabled": true, "used": 10, "limit": 100, "remaining": 90 }
          }
        }
        """

        let snapshot = try CursorProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialCursor(),
            accountLabel: "cursor@example.com"
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first?.title, "Monthly")
        XCTAssertEqual(snapshot.extras["planType"], "ultra")
    }

    func testJetBrainsXMLParsesQuota() throws {
        let xml = """
        <application>
          <component name="AIAssistantQuotaManager2">
            <option name="nextRefill" value="{&quot;type&quot;:&quot;Known&quot;,&quot;next&quot;:&quot;2099-01-01T00:00:00Z&quot;,&quot;tariff&quot;:{&quot;amount&quot;:&quot;100&quot;,&quot;duration&quot;:&quot;PT720H&quot;}}" />
            <option name="quotaInfo" value="{&quot;type&quot;:&quot;Available&quot;,&quot;current&quot;:&quot;75&quot;,&quot;maximum&quot;:&quot;100&quot;,&quot;available&quot;:&quot;25&quot;,&quot;until&quot;:&quot;2099-01-31T00:00:00Z&quot;}" />
          </component>
        </application>
        """

        let snapshot = try JetBrainsProvider.parseSnapshot(
            xml: xml,
            descriptor: ProviderDescriptor.defaultOfficialJetBrains()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.remainingPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.sourceLabel, "Local")
    }

    func testKiroCLIOutputParsesCreditsAndBonus() throws {
        let text = """
        Estimated Usage | resets on 03/01 | KIRO FREE

        Bonus credits: 122.54/500 credits used, expires in 29 days

        Credits (0.00 of 50 covered in plan)
        """

        let snapshot = try KiroProvider.parseSnapshot(
            text: text,
            descriptor: ProviderDescriptor.defaultOfficialKiro()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.sourceLabel, "CLI")
    }

    func testKiroCLIOutputParsesUsedCoveredInPlanFormat() throws {
        let text = """
        Estimated Usage resets on 05/01
        Credits 50 used / 50 covered in plan
        """

        let snapshot = try KiroProvider.parseSnapshot(
            text: text,
            descriptor: ProviderDescriptor.defaultOfficialKiro()
        )

        XCTAssertEqual(snapshot.sourceLabel, "CLI")
        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.title, "Credits")
        XCTAssertEqual(snapshot.quotaWindows.first?.remainingPercent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.remaining ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.used ?? -1, 100, accuracy: 0.001)
    }

    func testKiroIDEStateParsesCreditsAndBonus() throws {
        let stateJSON = """
        {
          "kiro.resourceNotifications.usageState": {
            "usageBreakdowns": [
              {
                "resourceType": "CREDIT",
                "currentUsage": 10,
                "usageLimit": 50,
                "nextDateReset": "2026-05-01T00:00:00Z",
                "displayName": "Credits",
                "freeTrialInfo": {
                  "currentUsage": 100,
                  "usageLimit": 500,
                  "freeTrialStatus": "ACTIVE",
                  "freeTrialExpiry": "2026-05-03T00:00:00Z"
                }
              }
            ],
            "timestamp": 1777770000000
          }
        }
        """

        let snapshot = try KiroProvider.parseIDESnapshot(
            stateJSON: stateJSON,
            descriptor: ProviderDescriptor.defaultOfficialKiro(),
            accountLabel: "kiro@example.com"
        )

        XCTAssertEqual(snapshot.sourceLabel, "IDE")
        XCTAssertEqual(snapshot.accountLabel, "kiro@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Credits" })?.remainingPercent ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Bonus" })?.remainingPercent ?? -1, 80, accuracy: 0.001)
    }

    func testKiroIDEAccountLabelExtractsFromJWTAndProfileFallback() throws {
        let jwtPayload = try JSONSerialization.data(withJSONObject: ["email": "kiro@example.com"])
        let tokenPayload = jwtPayload
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let idToken = "header.\(tokenPayload).signature"

        XCTAssertEqual(
            KiroProvider.extractIDEAccountLabel(
                token: ["idToken": idToken],
                profile: ["name": "Kiro IDE User"]
            ),
            "kiro@example.com"
        )
        XCTAssertEqual(
            KiroProvider.extractIDEAccountLabel(
                token: nil,
                profile: ["name": "Kiro IDE User"]
            ),
            "Kiro IDE User"
        )
    }

    func testKiroIDEStateDatabasePathsIncludeVariantDirectories() {
        let paths = KiroProvider.ideStateDatabasePaths(
            homeDirectory: "/Users/demo",
            appSupportEntries: [
                "Kiro",
                "Kiro - Insiders",
                "Kiro Preview",
                "kiro-next",
                "NotKiro"
            ]
        )

        XCTAssertTrue(paths.contains("/Users/demo/Library/Application Support/Kiro/User/globalStorage/state.vscdb"))
        XCTAssertTrue(paths.contains("/Users/demo/Library/Application Support/Kiro - Insiders/User/globalStorage/state.vscdb"))
        XCTAssertTrue(paths.contains("/Users/demo/Library/Application Support/Kiro Preview/User/globalStorage/state.vscdb"))
        XCTAssertTrue(paths.contains("/Users/demo/Library/Application Support/kiro-next/User/globalStorage/state.vscdb"))
        XCTAssertFalse(paths.contains("/Users/demo/Library/Application Support/NotKiro/User/globalStorage/state.vscdb"))
        XCTAssertEqual(paths.count, Set(paths).count)
    }

    func testWindsurfResponseParsesDailyAndWeekly() throws {
        let json = """
        {
          "userStatus": {
            "planStatus": {
              "planInfo": { "planName": "Pro" },
              "dailyQuotaRemainingPercent": 72,
              "weeklyQuotaRemainingPercent": 55,
              "dailyQuotaResetAtUnix": 1770648402,
              "weeklyQuotaResetAtUnix": 1771200000,
              "overageBalanceMicros": 2500000
            }
          }
        }
        """

        let snapshot = try WindsurfProvider.parseSnapshot(
            data: Data(json.utf8),
            descriptor: ProviderDescriptor.defaultOfficialWindsurf()
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 72, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "Pro")
    }

    func testSQLiteShellSnapshotQueryReadsSingleValueFromTemporaryDatabase() throws {
        let root = try makeTemporaryHomeDirectory(prefix: "sqlite-shell")
        let databaseURL = root.appendingPathComponent("state.vscdb")
        try createSQLiteItemTableDatabase(
            at: databaseURL,
            rows: [("windsurfAuthStatus", #"{"apiKey":"snapshot-key"}"#)]
        )

        let result = SQLiteShell.snapshotQuery(
            databasePath: databaseURL.path,
            query: "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus' LIMIT 1"
        )

        XCTAssertEqual(result.mode, .readOnlySnapshot)
        XCTAssertTrue(result.succeeded, result.errorMessage)
        XCTAssertEqual(result.singleValue, #"{"apiKey":"snapshot-key"}"#)
    }

    func testSQLiteShellSnapshotQueryReadsDatabaseWhenWALSidecarsExist() throws {
        let root = try makeTemporaryHomeDirectory(prefix: "sqlite-shell-wal")
        let databaseURL = root.appendingPathComponent("state.vscdb")
        try createSQLiteItemTableDatabase(
            at: databaseURL,
            rows: [("windsurfAuthStatus", #"{"apiKey":"wal-key"}"#)],
            useWAL: true
        )

        let walPath = databaseURL.path + "-wal"
        let shmPath = databaseURL.path + "-shm"
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: walPath) || FileManager.default.fileExists(atPath: shmPath),
            "expected WAL sidecars to exist for snapshot read regression coverage"
        )

        let result = SQLiteShell.snapshotQuery(
            databasePath: databaseURL.path,
            query: "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus' LIMIT 1"
        )

        XCTAssertTrue(result.succeeded, result.errorMessage)
        XCTAssertEqual(result.singleValue, #"{"apiKey":"wal-key"}"#)
    }

    func testSQLiteShellSnapshotQueryReturnsClearErrorForSQLiteFailure() throws {
        let root = try makeTemporaryHomeDirectory(prefix: "sqlite-shell-error")
        let databaseURL = root.appendingPathComponent("state.vscdb")
        try createSQLiteItemTableDatabase(
            at: databaseURL,
            rows: [("windsurfAuthStatus", #"{"apiKey":"broken"}"#)]
        )

        let result = SQLiteShell.snapshotQuery(
            databasePath: databaseURL.path,
            query: "SELECT value FROM MissingTable LIMIT 1"
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.errorMessage.localizedCaseInsensitiveContains("no such table"), result.errorMessage)
    }

    func testWindsurfFetchFallsBackToNextStateDatabase() async throws {
        let root = try makeTemporaryHomeDirectory(prefix: "windsurf-provider")
        let stableURL = root.appendingPathComponent("Library/Application Support/Windsurf/User/globalStorage/state.vscdb")
        let nextURL = root.appendingPathComponent("Library/Application Support/Windsurf - Next/User/globalStorage/state.vscdb")
        try createSQLiteItemTableDatabase(at: stableURL, rows: [("otherKey", "other-value")])
        try createSQLiteItemTableDatabase(
            at: nextURL,
            rows: [("windsurfAuthStatus", #"{"apiKey":"windsurf-next-key"}"#)]
        )

        OfficialMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            let metadata = try XCTUnwrap(json["metadata"] as? [String: Any])
            XCTAssertEqual(metadata["apiKey"] as? String, "windsurf-next-key")
            XCTAssertEqual(metadata["ideName"] as? String, "windsurf-next")
            let body = """
            {
              "userStatus": {
                "planStatus": {
                  "planInfo": { "planName": "Pro" },
                  "dailyQuotaRemainingPercent": 80,
                  "weeklyQuotaRemainingPercent": 60
                }
              }
            }
            """
            return (response, Data(body.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let provider = WindsurfProvider(
            descriptor: ProviderDescriptor.defaultOfficialWindsurf(),
            session: session,
            stateVariants: [
                .init(ideName: "windsurf", dbPath: stableURL.path),
                .init(ideName: "windsurf-next", dbPath: nextURL.path),
            ]
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.sourceLabel, "API")
    }

    func testWindsurfFetchSurfacesStateDatabaseReadFailure() async throws {
        let root = try makeTemporaryHomeDirectory(prefix: "windsurf-provider-failure")
        let databaseURL = root.appendingPathComponent("Library/Application Support/Windsurf - Next/User/globalStorage/state.vscdb")
        try writeText("not-a-sqlite-database", to: databaseURL)

        let provider = WindsurfProvider(
            descriptor: ProviderDescriptor.defaultOfficialWindsurf(),
            stateVariants: [
                .init(ideName: "windsurf-next", dbPath: databaseURL.path)
            ]
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected state database read failure")
        } catch let error as ProviderError {
            guard case .commandFailed(let detail) = error else {
                return XCTFail("Expected commandFailed, got \(error)")
            }
            XCTAssertTrue(detail.contains("Failed to read Windsurf state database"), detail)
            XCTAssertTrue(
                detail.localizedCaseInsensitiveContains("database")
                    || detail.localizedCaseInsensitiveContains("malformed")
                    || detail.localizedCaseInsensitiveContains("sqlite"),
                detail
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class OfficialMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = OfficialMockURLProtocol.requestHandler else {
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

private final class SpyBrowserCookieDetector: BrowserCookieDetecting {
    var detectCookieHeaderCallCount = 0
    var detectNamedCookieCallCount = 0
    var cookieHeaderResult: BrowserCookieHeader?
    var namedCookieResult: BrowserCookieHeader?
    private(set) var recordedIntents: [BrowserCredentialAccessIntent] = []

    func detectCookieHeader(
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        detectCookieHeaderCallCount += 1
        recordedIntents.append(accessIntent)
        return cookieHeaderResult
    }

    func detectNamedCookie(
        name: String,
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        detectNamedCookieCallCount += 1
        recordedIntents.append(accessIntent)
        return namedCookieResult
    }
}

private func makeTemporaryHomeDirectory(prefix: String) throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func createSQLiteItemTableDatabase(
    at url: URL,
    rows: [(String, String)],
    useWAL: Bool = false
) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if useWAL {
        try runSQLite(databasePath: url.path, sql: "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
    }
    try runSQLite(databasePath: url.path, sql: "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT, value TEXT);")
    for (key, value) in rows {
        let escapedKey = key.replacingOccurrences(of: "'", with: "''")
        let escapedValue = value.replacingOccurrences(of: "'", with: "''")
        try runSQLite(
            databasePath: url.path,
            sql: "INSERT INTO ItemTable (key, value) VALUES ('\(escapedKey)', '\(escapedValue)');"
        )
    }
}

private func runSQLite(databasePath: String, sql: String) throws {
    guard let result = ShellCommand.run(
        executable: "/usr/bin/sqlite3",
        arguments: [databasePath, sql],
        timeout: 10
    ) else {
        XCTFail("sqlite3 command failed to start")
        return
    }
    if result.status != 0 {
        XCTFail("sqlite3 command failed: \(result.stderr)")
    }
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

private func writeText(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

private func makeJWT(email: String) -> String {
    let payload = Data(#"{"email":"\#(email)"}"#.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(payload).signature"
}
