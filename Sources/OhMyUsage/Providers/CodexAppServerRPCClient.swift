import Darwin
import Foundation
import OhMyUsageProviders

/// Talks JSON-RPC to `codex app-server --listen stdio://` and returns as soon
/// as `account/read` and `account/rateLimits/read` have both answered.
///
/// The previous implementation slept a fixed keep-alive before closing stdin,
/// so every read cost at least three seconds and blocked a thread for up to
/// ~19 seconds; a cancelled refresh also kept waiting. Here stdout is read as
/// it arrives, one overall deadline bounds the call, and task cancellation
/// returns immediately. The child process is reaped in the background.
struct CodexAppServerRPCClient: Sendable {
    static let accountRequestID = "2"
    static let rateLimitsRequestID = "3"

    var executablePath: String
    var clientVersion: String
    var deadline: TimeInterval = 20
    /// Time the server gets to exit on its own after stdin closes before it
    /// is terminated.
    var exitGrace: TimeInterval = 1.5

    /// Returns the raw JSON `result` object for each answered request ID.
    func readAccountAndRateLimits() async throws -> [String: Data] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let exchange = Exchange(
            requiredIDs: [Self.accountRequestID, Self.rateLimitsRequestID],
            process: process,
            input: inputPipe.fileHandleForWriting,
            exitGrace: exitGrace
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard exchange.start(continuation: continuation) else { return }

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                        return
                    }
                    exchange.receiveStdout(chunk)
                }
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                        return
                    }
                    exchange.receiveStderr(chunk)
                }
                process.terminationHandler = { finished in
                    // Drain whatever is still buffered before judging the exit.
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    exchange.receiveStdout(outputPipe.fileHandleForReading.readDataToEndOfFile())
                    exchange.receiveStderr(errorPipe.fileHandleForReading.readDataToEndOfFile())
                    exchange.processExited(status: finished.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    exchange.finish(.failure(error))
                    return
                }

                let payload = Self.requestLines(clientVersion: clientVersion)
                    .joined(separator: "\n") + "\n"
                try? inputPipe.fileHandleForWriting.write(contentsOf: Data(payload.utf8))

                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deadline) {
                    exchange.finish(.failure(ProviderError.timeout("codex app-server timeout")))
                }
            }
        } onCancel: {
            exchange.finish(.failure(CancellationError()))
        }
    }

    static func requestLines(clientVersion: String) -> [String] {
        let clientInfo = (try? JSONSerialization.data(
            withJSONObject: ["name": "OhMyUsage", "version": clientVersion],
            options: [.sortedKeys]
        )).flatMap { String(data: $0, encoding: .utf8) } ?? #"{"name":"OhMyUsage","version":"0.0.0"}"#
        return [
            #"{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":"#
                + clientInfo + "}}",
            #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
            #"{"jsonrpc":"2.0","id":"\#(accountRequestID)","method":"account/read","params":{}}"#,
            #"{"jsonrpc":"2.0","id":"\#(rateLimitsRequestID)","method":"account/rateLimits/read","params":{}}"#
        ]
    }

    /// Parses one stdout line. `nil` means the line is not a JSON-RPC reply.
    static func parseLine(_ line: Substring) -> LineResult? {
        guard line.first == "{",
              let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return .error(message)
        }
        let id: String?
        if let stringID = json["id"] as? String {
            id = stringID
        } else if let numericID = json["id"] as? NSNumber {
            id = numericID.stringValue
        } else {
            id = nil
        }
        guard let id,
              let result = json["result"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: result) else {
            return nil
        }
        return .result(id: id, data: data)
    }

    enum LineResult: Equatable {
        case result(id: String, data: Data)
        case error(String)
    }
}

private extension CodexAppServerRPCClient {
    /// Shared state between the pipe callbacks, the deadline, cancellation and
    /// the awaiting caller. Every transition goes through `lock`; the
    /// continuation is resumed exactly once.
    final class Exchange: @unchecked Sendable {
        private let lock = NSLock()
        private let requiredIDs: Set<String>
        private let process: Process
        private let input: FileHandle
        private let exitGrace: TimeInterval
        private var continuation: CheckedContinuation<[String: Data], any Error>?
        private var pendingOutcome: Result<[String: Data], any Error>?
        private var stdoutBuffer = Data()
        private var stderrBuffer = Data()
        private var results: [String: Data] = [:]
        private var finished = false

        init(requiredIDs: Set<String>, process: Process, input: FileHandle, exitGrace: TimeInterval) {
            self.requiredIDs = requiredIDs
            self.process = process
            self.input = input
            self.exitGrace = exitGrace
        }

        /// Returns `false` when the call was cancelled before it started, in
        /// which case the continuation has already been resumed.
        func start(continuation: CheckedContinuation<[String: Data], any Error>) -> Bool {
            lock.lock()
            if let pendingOutcome {
                lock.unlock()
                continuation.resume(with: pendingOutcome)
                return false
            }
            self.continuation = continuation
            lock.unlock()
            return true
        }

        func receiveStdout(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            stdoutBuffer.append(chunk)
            var outcome: Result<[String: Data], any Error>?
            while outcome == nil, let newline = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = stdoutBuffer[stdoutBuffer.startIndex..<newline]
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
                guard let text = String(data: lineData, encoding: .utf8) else { continue }
                switch CodexAppServerRPCClient.parseLine(Substring(text)) {
                case .error(let message):
                    outcome = .failure(ProviderError.invalidResponse(message))
                case .result(let id, let data):
                    results[id] = data
                    if requiredIDs.isSubset(of: results.keys) {
                        outcome = .success(results)
                    }
                case nil:
                    continue
                }
            }
            lock.unlock()
            if let outcome {
                finish(outcome)
            }
        }

        func receiveStderr(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            // Only the head matters for diagnostics; never grow without bound.
            if stderrBuffer.count < 64 * 1024 {
                stderrBuffer.append(chunk.prefix(64 * 1024 - stderrBuffer.count))
            }
            lock.unlock()
        }

        func processExited(status: Int32) {
            lock.lock()
            let collected = results
            let stderr = String(data: stderrBuffer, encoding: .utf8) ?? "unknown stderr"
            lock.unlock()
            if requiredIDs.isSubset(of: collected.keys) {
                finish(.success(collected))
            } else if status != 0 {
                finish(.failure(ProviderError.commandFailed(stderr)))
            } else {
                finish(.failure(ProviderError.invalidResponse(
                    "missing account/read or account/rateLimits/read response"
                )))
            }
        }

        func finish(_ outcome: Result<[String: Data], any Error>) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let continuation = self.continuation
            self.continuation = nil
            if continuation == nil {
                pendingOutcome = outcome
            }
            lock.unlock()

            continuation?.resume(with: outcome)
            reap()
        }

        /// Closes stdin so the server can exit on its own, then escalates.
        /// Runs off the caller so a slow exit never delays the result.
        private func reap() {
            try? input.close()
            let process = self.process
            let exitGrace = self.exitGrace
            DispatchQueue.global(qos: .utility).async {
                guard process.isRunning else { return }
                let deadline = Date().addingTimeInterval(exitGrace)
                while process.isRunning, Date() < deadline {
                    usleep(50_000)
                }
                guard process.isRunning else { return }
                process.terminate()
                let killDeadline = Date().addingTimeInterval(1.0)
                while process.isRunning, Date() < killDeadline {
                    usleep(50_000)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }
}
