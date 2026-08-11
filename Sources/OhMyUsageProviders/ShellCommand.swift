import Darwin
import Foundation

public struct ShellCommand: Sendable {
    public init() {}

    public static func run(
        executable: String,
        arguments: [String],
        input: String? = nil,
        timeout: TimeInterval = 20,
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) -> (status: Int32, stdout: String, stderr: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        let inputPipe = Pipe()
        if input != nil {
            process.standardInput = inputPipe
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if let input {
            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
        }

        var didTimeout = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            didTimeout = true
            if process.isRunning {
                process.terminate()
                if finished.wait(timeout: .now() + 1.0) == .timedOut, process.isRunning {
                    // SIGTERM 无效时强制杀进程，避免 Process 仍在运行导致崩溃。
                    kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 1.0)
                }
            }
        }

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.isRunning {
            // 极端情况下仍未退出，返回超时状态并避免触发 terminationStatus 异常。
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1.0)
            return (didTimeout ? 124 : -1, stdout, stderr)
        }

        return (process.terminationStatus, stdout, stderr)
    }
}
