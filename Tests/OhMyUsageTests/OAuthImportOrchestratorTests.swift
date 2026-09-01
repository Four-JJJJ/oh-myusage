import Foundation
import XCTest
@testable import OhMyUsage

final class OAuthImportOrchestratorTests: XCTestCase {
    @MainActor
    func testCodexFallsBackToDeviceAuthWhenBrowserFlowFails() async {
        let recorder = CommandRecorder()
        let orchestrator = OAuthImportOrchestrator(
            commandRunner: { command, _ in
                await recorder.append(command)
                if command.provider == .codex, command.mode == .browserCallback {
                    return OAuthImportCommandResult(status: 1, timedOut: false, wasCancelled: false, stdout: "", stderr: "browser callback failed")
                }
                return OAuthImportCommandResult(status: 0, timedOut: false, wasCancelled: false, stdout: "ok", stderr: "")
            },
            credentialLoader: { provider in
                guard provider == .codex else { return nil }
                return OAuthImportCredential(
                    rawJSON: Self.sampleCodexAuthJSON(accountID: "acc-a", email: "a@example.com"),
                    fingerprint: "finger-a",
                    accountEmail: "a@example.com"
                )
            }
        )

        var phases: [OAuthImportPhase] = []
        let result = await orchestrator.importAccount(provider: .codex, slotID: .a) { state in
            phases.append(state.phase)
        }

        guard case .success(let imported) = result else {
            return XCTFail("expected success, got \(result)")
        }

        XCTAssertEqual(imported.provider, .codex)
        XCTAssertEqual(imported.mode, .deviceAuth)

        let commands = await recorder.commands()
        XCTAssertEqual(
            commands,
            [
                OAuthImportCLICommand(provider: .codex, mode: .browserCallback),
                OAuthImportCLICommand(provider: .codex, mode: .deviceAuth)
            ]
        )
        XCTAssertTrue(phases.contains(.waitingForDevice))
        XCTAssertEqual(phases.last, .succeeded)
    }

    func testClaudeFailsWhenCredentialIsMissingAfterLogin() async {
        let orchestrator = OAuthImportOrchestrator(
            commandRunner: { _, _ in
                OAuthImportCommandResult(status: 0, timedOut: false, wasCancelled: false, stdout: "ok", stderr: "")
            },
            credentialLoader: { _ in nil }
        )

        let result = await orchestrator.importAccount(provider: .claude, slotID: .a)

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertEqual(error, .missingCredential)
    }

    func testClaudeUsesAuthLoginByDefault() async {
        let recorder = CommandRecorder()
        let orchestrator = OAuthImportOrchestrator(
            commandRunner: { command, _ in
                await recorder.append(command)
                return OAuthImportCommandResult(status: 0, timedOut: false, wasCancelled: false, stdout: "ok", stderr: "")
            },
            credentialLoader: { provider in
                guard provider == .claude else { return nil }
                return OAuthImportCredential(
                    rawJSON: Self.sampleClaudeCredentialsJSON(email: "claude@example.com"),
                    fingerprint: "finger-claude",
                    accountEmail: "claude@example.com"
                )
            }
        )

        let result = await orchestrator.importAccount(provider: .claude, slotID: .a)

        guard case .success(let imported) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(imported.provider, .claude)
        XCTAssertEqual(imported.mode, .browserCallback)

        let commands = await recorder.commands()
        XCTAssertEqual(
            commands,
            [OAuthImportCLICommand(provider: .claude, mode: .browserCallback)]
        )
        XCTAssertEqual(commands.first?.prefersLegacyLogin, false)
    }

    func testClaudeFallsBackToLegacyLoginWhenAuthSubcommandIsUnsupported() async {
        let recorder = CommandRecorder()
        let orchestrator = OAuthImportOrchestrator(
            commandRunner: { command, _ in
                await recorder.append(command)
                if command.provider == .claude,
                   command.mode == .browserCallback,
                   !command.prefersLegacyLogin {
                    return OAuthImportCommandResult(
                        status: 1,
                        timedOut: false,
                        wasCancelled: false,
                        stdout: "",
                        stderr: "unknown command 'auth'"
                    )
                }
                return OAuthImportCommandResult(status: 0, timedOut: false, wasCancelled: false, stdout: "ok", stderr: "")
            },
            credentialLoader: { provider in
                guard provider == .claude else { return nil }
                return OAuthImportCredential(
                    rawJSON: Self.sampleClaudeCredentialsJSON(email: "claude@example.com"),
                    fingerprint: "finger-claude",
                    accountEmail: "claude@example.com"
                )
            }
        )

        let result = await orchestrator.importAccount(provider: .claude, slotID: .a)

        guard case .success(let imported) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(imported.provider, .claude)
        XCTAssertEqual(imported.mode, .browserCallback)

        let commands = await recorder.commands()
        XCTAssertEqual(
            commands,
            [
                OAuthImportCLICommand(provider: .claude, mode: .browserCallback),
                OAuthImportCLICommand(provider: .claude, mode: .browserCallback, prefersLegacyLogin: true)
            ]
        )
    }

    func testClaudeDoesNotFallbackForNonCompatibilityFailure() async {
        let recorder = CommandRecorder()
        let orchestrator = OAuthImportOrchestrator(
            commandRunner: { command, _ in
                await recorder.append(command)
                return OAuthImportCommandResult(
                    status: 1,
                    timedOut: false,
                    wasCancelled: false,
                    stdout: "",
                    stderr: "network unreachable"
                )
            },
            credentialLoader: { provider in
                guard provider == .claude else { return nil }
                return OAuthImportCredential(
                    rawJSON: Self.sampleClaudeCredentialsJSON(email: "claude@example.com"),
                    fingerprint: "finger-claude",
                    accountEmail: "claude@example.com"
                )
            }
        )

        let result = await orchestrator.importAccount(provider: .claude, slotID: .a)

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        guard case .commandFailed(let message) = error else {
            return XCTFail("expected commandFailed, got \(error)")
        }
        XCTAssertTrue(message.contains("network unreachable"))

        let commands = await recorder.commands()
        XCTAssertEqual(
            commands,
            [OAuthImportCLICommand(provider: .claude, mode: .browserCallback)]
        )
    }

    @MainActor
    func testCodexImportWritesVaultBeforeReportingSuccess() async {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: makeTestKeychain(), defaults: defaults)
        let rawJSON = Self.sampleCodexAuthJSON(accountID: "acc-a", email: "a@example.com")
        let orchestrator = OAuthImportOrchestrator(
            commandRunner: { _, _ in
                OAuthImportCommandResult(status: 0, timedOut: false, wasCancelled: false, stdout: "ok", stderr: "")
            },
            credentialLoader: { provider in
                guard provider == .codex else { return nil }
                return OAuthImportCredential(
                    rawJSON: rawJSON,
                    fingerprint: "finger-a",
                    accountEmail: "a@example.com"
                )
            },
            oauthVault: vault
        )

        var phases: [OAuthImportPhase] = []
        let result = await orchestrator.importAccount(provider: .codex, slotID: .a) { state in
            phases.append(state.phase)
        }

        guard case .success = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(phases.last, .succeeded)
        // The normalized OAuth JSON is in the app vault before the import completes.
        XCTAssertEqual(vault.readOAuthJSON(provider: .codex), rawJSON)
        XCTAssertTrue(vault.isMigrationComplete(provider: .codex))
    }

    @MainActor
    func testImportFailsWhenVaultWriteFails() async {
        let (defaults, suiteName) = makeTestDefaults()
        defer { removeTestDefaults(named: suiteName) }
        let vault = OfficialOAuthVaultStore(keychain: FailingTokenCredentialStore(), defaults: defaults)
        let orchestrator = OAuthImportOrchestrator(
            commandRunner: { _, _ in
                OAuthImportCommandResult(status: 0, timedOut: false, wasCancelled: false, stdout: "ok", stderr: "")
            },
            credentialLoader: { provider in
                guard provider == .claude else { return nil }
                return OAuthImportCredential(
                    rawJSON: Self.sampleClaudeCredentialsJSON(email: "claude@example.com"),
                    fingerprint: "finger-claude",
                    accountEmail: "claude@example.com"
                )
            },
            oauthVault: vault
        )

        var phases: [OAuthImportPhase] = []
        let result = await orchestrator.importAccount(provider: .claude, slotID: .a) { state in
            phases.append(state.phase)
        }

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertEqual(error, .vaultWriteFailed)
        XCTAssertEqual(phases.last, .failed)
        XCTAssertNil(vault.readOAuthJSON(provider: .claude))
    }

    private static func sampleCodexAuthJSON(accountID: String, email: String) -> String {
        let payload = Data(#"{"email":"\#(email)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return #"""
        {
          "tokens": {
            "access_token": "access-token-\#(accountID)",
            "refresh_token": "refresh-token-\#(accountID)",
            "account_id": "\#(accountID)",
            "id_token": "header.\#(payload).signature"
          }
        }
        """#
    }

    private static func sampleClaudeCredentialsJSON(email: String) -> String {
        #"""
        {
          "claudeAiOauth": {
            "accessToken": "claude-access-token",
            "refreshToken": "claude-refresh-token",
            "email": "\#(email)"
          }
        }
        """#
    }
}

private actor CommandRecorder {
    private var recordedCommands: [OAuthImportCLICommand] = []

    func append(_ command: OAuthImportCLICommand) {
        recordedCommands.append(command)
    }

    func commands() -> [OAuthImportCLICommand] {
        recordedCommands
    }
}
