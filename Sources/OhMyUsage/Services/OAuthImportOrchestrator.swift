import Foundation
import Darwin

enum OAuthImportProvider: String, Equatable {
    case codex
    case claude
}

enum OAuthImportMode: String, Equatable {
    case browserCallback
    case deviceAuth
}

enum OAuthImportPhase: String, Equatable {
    case launching
    case waitingForBrowser
    case waitingForDevice
    case verifying
    case succeeded
    case failed
    case cancelled

    var isRunning: Bool {
        switch self {
        case .launching, .waitingForBrowser, .waitingForDevice, .verifying:
            return true
        case .succeeded, .failed, .cancelled:
            return false
        }
    }
}

struct OAuthImportState: Equatable {
    var provider: OAuthImportProvider
    var slotID: CodexSlotID
    var mode: OAuthImportMode
    var phase: OAuthImportPhase
    var detail: String?
    var startedAt: Date
    var updatedAt: Date

    var isRunning: Bool { phase.isRunning }
    var isError: Bool { phase == .failed }
}

struct OAuthImportResult: Equatable {
    var provider: OAuthImportProvider
    var slotID: CodexSlotID
    var mode: OAuthImportMode
    var rawCredentialJSON: String
    var accountEmail: String?
}

enum OAuthImportError: LocalizedError, Equatable {
    case executableNotFound(String)
    case commandFailed(String)
    case timedOut
    case cancelled
    case missingCredential
    case invalidCredential
    case vaultWriteFailed

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let executable):
            return "Unable to locate \(executable) CLI"
        case .commandFailed(let message):
            return message
        case .timedOut:
            return "OAuth login timed out"
        case .cancelled:
            return "OAuth login cancelled"
        case .missingCredential:
            return "No local credential was detected after login"
        case .invalidCredential:
            return "The detected local credential is invalid"
        case .vaultWriteFailed:
            return "Failed to store the imported OAuth credential in the app vault"
        }
    }
}

struct OAuthImportCLICommand: Equatable {
    var provider: OAuthImportProvider
    var mode: OAuthImportMode
    var prefersLegacyLogin: Bool = false
}

struct OAuthImportCommandResult: Equatable {
    var status: Int32
    var timedOut: Bool
    var wasCancelled: Bool
    var stdout: String
    var stderr: String
}

struct OAuthImportCredential: Equatable {
    var rawJSON: String
    var fingerprint: String
    var accountEmail: String?
}

actor OAuthImportOrchestrator {
    typealias StateHandler = @MainActor @Sendable (OAuthImportState) -> Void

    private let commandRunner: (@Sendable (OAuthImportCLICommand, TimeInterval) async -> OAuthImportCommandResult)?
    private let credentialLoader: (@Sendable (OAuthImportProvider) -> OAuthImportCredential?)?
    private let oauthVault: OfficialOAuthVaultStore?

    private var runningProcesses: [OAuthImportProvider: Process] = [:]
    private var cancellationRequests: Set<OAuthImportProvider> = []

    private struct ClaudeBrowserCaptureContext {
        let helperDirectoryPath: String
    }

    private final class CommandOutputAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var stdout: String = ""
        private var stderr: String = ""

        func appendStdout(_ text: String) {
            append(text: text, isStdout: true)
        }

        func appendStderr(_ text: String) {
            append(text: text, isStdout: false)
        }

        func snapshot() -> (stdout: String, stderr: String) {
            lock.lock()
            defer { lock.unlock() }
            return (stdout, stderr)
        }

        private func append(text: String, isStdout: Bool) {
            lock.lock()
            defer { lock.unlock() }

            if isStdout {
                stdout += text
            } else {
                stderr += text
            }
        }
    }

    init(
        commandRunner: (@Sendable (OAuthImportCLICommand, TimeInterval) async -> OAuthImportCommandResult)? = nil,
        credentialLoader: (@Sendable (OAuthImportProvider) -> OAuthImportCredential?)? = nil,
        oauthVault: OfficialOAuthVaultStore? = nil
    ) {
        self.commandRunner = commandRunner
        self.credentialLoader = credentialLoader
        self.oauthVault = oauthVault
    }

    func importAccount(
        provider: OAuthImportProvider,
        slotID: CodexSlotID,
        stateHandler: StateHandler? = nil
    ) async -> Result<OAuthImportResult, OAuthImportError> {
        cancellationRequests.remove(provider)
        let startedAt = Date()

        switch provider {
        case .codex:
            return await importCodex(slotID: slotID, startedAt: startedAt, stateHandler: stateHandler)
        case .claude:
            return await importClaude(slotID: slotID, startedAt: startedAt, stateHandler: stateHandler)
        }
    }

    func cancelImport(provider: OAuthImportProvider) {
        cancellationRequests.insert(provider)
        if let process = runningProcesses[provider], process.isRunning {
            process.terminate()
        }
    }

    private func importCodex(
        slotID: CodexSlotID,
        startedAt: Date,
        stateHandler: StateHandler?
    ) async -> Result<OAuthImportResult, OAuthImportError> {
        let browserCommand = OAuthImportCLICommand(provider: .codex, mode: .browserCallback)

        await emitState(
            provider: .codex,
            slotID: slotID,
            mode: .browserCallback,
            phase: .launching,
            detail: nil,
            startedAt: startedAt,
            stateHandler: stateHandler
        )
        await emitState(
            provider: .codex,
            slotID: slotID,
            mode: .browserCallback,
            phase: .waitingForBrowser,
            detail: nil,
            startedAt: startedAt,
            stateHandler: stateHandler
        )

        let browserResult = await execute(command: browserCommand, timeout: 120)
        if let failure = commandFailure(from: browserResult) {
            if failure == .cancelled {
                await emitState(
                    provider: .codex,
                    slotID: slotID,
                    mode: .browserCallback,
                    phase: .cancelled,
                    detail: nil,
                    startedAt: startedAt,
                    stateHandler: stateHandler
                )
                return .failure(failure)
            }

            await emitState(
                provider: .codex,
                slotID: slotID,
                mode: .deviceAuth,
                phase: .waitingForDevice,
                detail: nil,
                startedAt: startedAt,
                stateHandler: stateHandler
            )

            let deviceResult = await executeCodexDeviceAuth(timeout: 360)
            if let deviceFailure = commandFailure(from: deviceResult) {
                let detail = mergedCommandOutput(deviceResult)
                await emitState(
                    provider: .codex,
                    slotID: slotID,
                    mode: .deviceAuth,
                    phase: deviceFailure == .cancelled ? .cancelled : .failed,
                    detail: detail,
                    startedAt: startedAt,
                    stateHandler: stateHandler
                )
                return .failure(deviceFailure)
            }

            return await finishImport(
                provider: .codex,
                slotID: slotID,
                mode: .deviceAuth,
                startedAt: startedAt,
                stateHandler: stateHandler
            )
        }

        return await finishImport(
            provider: .codex,
            slotID: slotID,
            mode: .browserCallback,
            startedAt: startedAt,
            stateHandler: stateHandler
        )
    }

    private func importClaude(
        slotID: CodexSlotID,
        startedAt: Date,
        stateHandler: StateHandler?
    ) async -> Result<OAuthImportResult, OAuthImportError> {
        let preferredCommand = OAuthImportCLICommand(provider: .claude, mode: .browserCallback)

        await emitState(
            provider: .claude,
            slotID: slotID,
            mode: .browserCallback,
            phase: .launching,
            detail: nil,
            startedAt: startedAt,
            stateHandler: stateHandler
        )
        await emitState(
            provider: .claude,
            slotID: slotID,
            mode: .browserCallback,
            phase: .waitingForBrowser,
            detail: nil,
            startedAt: startedAt,
            stateHandler: stateHandler
        )

        let preferredResult = await execute(command: preferredCommand, timeout: 240)
        let commandResult: OAuthImportCommandResult
        if shouldFallbackToClaudeLegacyLogin(preferredResult) {
            let legacyCommand = OAuthImportCLICommand(
                provider: .claude,
                mode: .browserCallback,
                prefersLegacyLogin: true
            )
            commandResult = await execute(command: legacyCommand, timeout: 240)
        } else {
            commandResult = preferredResult
        }

        if let failure = commandFailure(from: commandResult) {
            let detail = mergedCommandOutput(commandResult)
            await emitState(
                provider: .claude,
                slotID: slotID,
                mode: .browserCallback,
                phase: failure == .cancelled ? .cancelled : .failed,
                detail: detail,
                startedAt: startedAt,
                stateHandler: stateHandler
            )
            return .failure(failure)
        }

        return await finishImport(
            provider: .claude,
            slotID: slotID,
            mode: .browserCallback,
            startedAt: startedAt,
            stateHandler: stateHandler
        )
    }

    private func shouldFallbackToClaudeLegacyLogin(_ result: OAuthImportCommandResult) -> Bool {
        guard result.status != 0, !result.timedOut, !result.wasCancelled else { return false }
        let combined = mergedCommandOutput(result).lowercased()
        guard combined.contains("auth") else { return false }

        let compatibilityMarkers = [
            "unknown command",
            "unknown subcommand",
            "no such command",
            "invalid command",
            "unrecognized command",
            "did you mean"
        ]
        return compatibilityMarkers.contains { combined.contains($0) }
    }

    private func finishImport(
        provider: OAuthImportProvider,
        slotID: CodexSlotID,
        mode: OAuthImportMode,
        startedAt: Date,
        stateHandler: StateHandler?
    ) async -> Result<OAuthImportResult, OAuthImportError> {
        await emitState(
            provider: provider,
            slotID: slotID,
            mode: mode,
            phase: .verifying,
            detail: nil,
            startedAt: startedAt,
            stateHandler: stateHandler
        )

        guard !cancellationRequests.contains(provider) else {
            await emitState(
                provider: provider,
                slotID: slotID,
                mode: mode,
                phase: .cancelled,
                detail: nil,
                startedAt: startedAt,
                stateHandler: stateHandler
            )
            return .failure(.cancelled)
        }

        guard let credential = loadCredential(for: provider) else {
            await emitState(
                provider: provider,
                slotID: slotID,
                mode: mode,
                phase: .failed,
                detail: nil,
                startedAt: startedAt,
                stateHandler: stateHandler
            )
            return .failure(.missingCredential)
        }

        // Phase 1 §7.6: the import only completes after the normalized OAuth JSON
        // was parse-verified and written into the app vault (via the shared broker).
        // The `.succeeded` completion marker is emitted only after that write.
        if let oauthVault, !oauthVault.saveOAuthJSON(provider: provider, rawJSON: credential.rawJSON) {
            await emitState(
                provider: provider,
                slotID: slotID,
                mode: mode,
                phase: .failed,
                detail: nil,
                startedAt: startedAt,
                stateHandler: stateHandler
            )
            return .failure(.vaultWriteFailed)
        }

        await emitState(
            provider: provider,
            slotID: slotID,
            mode: mode,
            phase: .succeeded,
            detail: nil,
            startedAt: startedAt,
            stateHandler: stateHandler
        )

        return .success(
            OAuthImportResult(
                provider: provider,
                slotID: slotID,
                mode: mode,
                rawCredentialJSON: credential.rawJSON,
                accountEmail: credential.accountEmail
            )
        )
    }

    private func executeCodexDeviceAuth(timeout: TimeInterval) async -> OAuthImportCommandResult {
        let preferred = OAuthImportCLICommand(provider: .codex, mode: .deviceAuth)
        let first = await execute(command: preferred, timeout: timeout)
        if first.status == 0 && !first.timedOut && !first.wasCancelled {
            return first
        }

        let combined = (first.stdout + "\n" + first.stderr).lowercased()
        let needsFallback = combined.contains("unknown option") || combined.contains("unrecognized option")
        guard needsFallback else { return first }

        let alternate = OAuthImportCLICommand(provider: .codex, mode: .deviceAuth)
        return await execute(command: alternate, timeout: timeout, deviceAuthFallbackFlag: "--device-code")
    }

    private func execute(
        command: OAuthImportCLICommand,
        timeout: TimeInterval,
        deviceAuthFallbackFlag: String? = nil
    ) async -> OAuthImportCommandResult {
        if let commandRunner {
            return await commandRunner(command, timeout)
        }
        return await runLiveCommand(command: command, timeout: timeout, deviceAuthFallbackFlag: deviceAuthFallbackFlag)
    }

    private func commandFailure(from result: OAuthImportCommandResult) -> OAuthImportError? {
        if result.wasCancelled {
            return .cancelled
        }
        if result.timedOut {
            return .timedOut
        }
        guard result.status == 0 else {
            let detail = mergedCommandOutput(result)
            if detail.isEmpty {
                return .commandFailed("OAuth login command failed")
            }
            return .commandFailed(detail)
        }
        return nil
    }

    private func mergedCommandOutput(_ result: OAuthImportCommandResult) -> String {
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if stderr.isEmpty {
            return stdout
        }
        if stdout.isEmpty {
            return stderr
        }
        return "\(stderr)\n\(stdout)"
    }

    private func emitState(
        provider: OAuthImportProvider,
        slotID: CodexSlotID,
        mode: OAuthImportMode,
        phase: OAuthImportPhase,
        detail: String?,
        startedAt: Date,
        stateHandler: StateHandler?
    ) async {
        guard let stateHandler else { return }
        let state = OAuthImportState(
            provider: provider,
            slotID: slotID,
            mode: mode,
            phase: phase,
            detail: detail,
            startedAt: startedAt,
            updatedAt: Date()
        )
        await stateHandler(state)
    }

    private func loadCredential(for provider: OAuthImportProvider) -> OAuthImportCredential? {
        if let credentialLoader {
            return credentialLoader(provider)
        }
        switch provider {
        case .codex:
            return Self.loadCodexCredential()
        case .claude:
            return Self.loadClaudeCredential()
        }
    }

    private func runLiveCommand(
        command: OAuthImportCLICommand,
        timeout: TimeInterval,
        deviceAuthFallbackFlag: String?
    ) async -> OAuthImportCommandResult {
        guard let executablePath = resolveExecutablePath(for: command.provider) else {
            let executable = command.provider == .codex ? "codex" : "claude"
            return OAuthImportCommandResult(
                status: 127,
                timedOut: false,
                wasCancelled: false,
                stdout: "",
                stderr: OAuthImportError.executableNotFound(executable).localizedDescription
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments(for: command, deviceAuthFallbackFlag: deviceAuthFallbackFlag)

        var environment = ProcessInfo.processInfo.environment
        if command.provider == .claude {
            environment.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
        }
        let browserCapture = prepareClaudeBrowserCapture(
            command: command,
            baseEnvironment: &environment
        )
        defer {
            if let helperDirectoryPath = browserCapture?.helperDirectoryPath {
                try? FileManager.default.removeItem(atPath: helperDirectoryPath)
            }
        }
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputAccumulator = CommandOutputAccumulator()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            outputAccumulator.appendStdout(chunk)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            outputAccumulator.appendStderr(chunk)
        }

        let inputPipe = Pipe()
        process.standardInput = inputPipe
        try? inputPipe.fileHandleForWriting.close()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return OAuthImportCommandResult(
                status: 126,
                timedOut: false,
                wasCancelled: false,
                stdout: "",
                stderr: error.localizedDescription
            )
        }

        runningProcesses[command.provider] = process

        let waitResult: DispatchTimeoutResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = finished.wait(timeout: .now() + timeout)
                continuation.resume(returning: result)
            }
        }

        var timedOut = false
        if waitResult == .timedOut {
            timedOut = true
            if process.isRunning {
                process.terminate()
                if await waitOnSemaphore(finished, timeout: 1.0) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = await waitOnSemaphore(finished, timeout: 1.0)
                }
            }
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = await waitOnSemaphore(finished, timeout: 1.0)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        let remainingOutput = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        if !remainingOutput.isEmpty {
            outputAccumulator.appendStdout(remainingOutput)
        }
        let remainingError = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        if !remainingError.isEmpty {
            outputAccumulator.appendStderr(remainingError)
        }
        let (output, error) = outputAccumulator.snapshot()

        let cancelled = cancellationRequests.contains(command.provider)
        runningProcesses.removeValue(forKey: command.provider)

        return OAuthImportCommandResult(
            status: process.terminationStatus,
            timedOut: timedOut,
            wasCancelled: cancelled,
            stdout: output,
            stderr: error
        )
    }

    private func prepareClaudeBrowserCapture(
        command: OAuthImportCLICommand,
        baseEnvironment: inout [String: String]
    ) -> ClaudeBrowserCaptureContext? {
        guard command.provider == .claude, command.mode == .browserCallback else { return nil }

        let fileManager = FileManager.default
        let helperDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("aiplan-claude-open-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let helperScriptPath = helperDirectory.appendingPathComponent("open").path
        let openedFlagPath = helperDirectory.appendingPathComponent("opened.flag").path
        let helperScript = """
        #!/bin/sh
        opened_flag="\(openedFlagPath)"
        target=""
        for arg in "$@"; do
          case "$arg" in
            -*) ;;
            *) target="$arg"; break ;;
          esac
        done
        if [ -n "$target" ] && [ ! -e "$opened_flag" ]; then
          : > "$opened_flag"
          /usr/bin/open "$target" >/dev/null 2>&1 &
        fi
        exit 0
        """
        do {
            try helperScript.write(toFile: helperScriptPath, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperScriptPath)
        } catch {
            try? fileManager.removeItem(at: helperDirectory)
            return nil
        }

        let existingPath = baseEnvironment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        baseEnvironment["PATH"] = "\(helperDirectory.path):\(existingPath)"
        baseEnvironment["BROWSER"] = helperScriptPath
        return ClaudeBrowserCaptureContext(
            helperDirectoryPath: helperDirectory.path
        )
    }

    private func resolveExecutablePath(for provider: OAuthImportProvider) -> String? {
        switch provider {
        case .codex:
            return Self.resolveCodexExecutablePath()
        case .claude:
            return Self.resolveClaudeExecutablePath()
        }
    }

    private func arguments(for command: OAuthImportCLICommand, deviceAuthFallbackFlag: String?) -> [String] {
        switch command.provider {
        case .codex:
            switch command.mode {
            case .browserCallback:
                return ["login"]
            case .deviceAuth:
                return ["login", deviceAuthFallbackFlag ?? "--device-auth"]
            }
        case .claude:
            if command.prefersLegacyLogin {
                return ["login"]
            }
            return ["auth", "login"]
        }
    }

    private static func resolveCodexExecutablePath() -> String? {
        let manager = FileManager.default
        let explicit = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"]
        let staticCandidates: [String] = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]

        let envPath = ProcessInfo.processInfo.environment["PATH"]
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let pathCandidates = envPath
            .split(separator: ":")
            .map { "\($0)/codex" }

        let candidates = [explicit].compactMap { $0 } + staticCandidates + pathCandidates
        for path in candidates where manager.isExecutableFile(atPath: path) {
            if path.contains("/Applications/Codex.app/Contents/MacOS/codex") {
                continue
            }
            return path
        }
        return nil
    }

    private static func resolveClaudeExecutablePath() -> String? {
        let manager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["CLAUDE_CLI_PATH"],
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
            "/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude"
        ].compactMap { $0 }
        let envCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map { "\($0)/claude" }
        for path in candidates + envCandidates where manager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func loadCodexCredential() -> OAuthImportCredential? {
        let environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()

        for path in CodexAuthPathResolver.resolveAuthPaths(homeDirectory: home, environment: environment) {
            guard let raw = readTextFile(path) else { continue }
            guard let payload = try? CodexAccountProfileStore.parseAuthJSON(raw) else { continue }
            return OAuthImportCredential(
                rawJSON: raw,
                fingerprint: payload.credentialFingerprint,
                accountEmail: payload.accountEmail
            )
        }

        if let keychain = SecurityCredentialReader.readGenericPassword(service: "Codex Auth"),
           let payload = try? CodexAccountProfileStore.parseAuthJSON(keychain) {
            return OAuthImportCredential(
                rawJSON: keychain,
                fingerprint: payload.credentialFingerprint,
                accountEmail: payload.accountEmail
            )
        }

        return nil
    }

    private static func loadClaudeCredential() -> OAuthImportCredential? {
        let environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()

        let envConfigDir = ClaudeAccountProfileStore.normalizedConfigDirectory(environment["CLAUDE_CONFIG_DIR"])
        let defaultDir = ClaudeAccountProfileStore.normalizedConfigDirectory("\(home)/.claude")
        let configDirs = Array(NSOrderedSet(array: [envConfigDir, defaultDir].compactMap { $0 })) as? [String]
            ?? [envConfigDir, defaultDir].compactMap { $0 }

        for configDir in configDirs {
            let path = ClaudeAccountProfileStore.credentialsFilePath(configDirectory: configDir)
            guard let raw = readTextFile(path) else { continue }
            guard let payload = try? ClaudeAccountProfileStore.parseCredentialsJSON(raw) else { continue }
            return OAuthImportCredential(
                rawJSON: raw,
                fingerprint: payload.credentialFingerprint,
                accountEmail: payload.accountEmail
            )
        }

        if let keychain = SecurityCredentialReader.readGenericPassword(service: "Claude Code-credentials"),
           let payload = try? ClaudeAccountProfileStore.parseCredentialsJSON(keychain) {
            return OAuthImportCredential(
                rawJSON: keychain,
                fingerprint: payload.credentialFingerprint,
                accountEmail: payload.accountEmail
            )
        }

        return nil
    }

    private static func readTextFile(_ path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return text
    }

    private func waitOnSemaphore(_ semaphore: DispatchSemaphore, timeout: TimeInterval) async -> DispatchTimeoutResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = semaphore.wait(timeout: .now() + timeout)
                continuation.resume(returning: result)
            }
        }
    }
}
