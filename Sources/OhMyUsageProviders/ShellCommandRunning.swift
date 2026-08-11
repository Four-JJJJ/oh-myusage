import Foundation

/// Provider-side port for running local shell commands.
public protocol ShellCommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        input: String?,
        timeout: TimeInterval,
        environment: [String: String]?,
        currentDirectory: String?
    ) -> (status: Int32, stdout: String, stderr: String)?
}

public extension ShellCommandRunning {
    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 20
    ) -> (status: Int32, stdout: String, stderr: String)? {
        run(
            executable: executable,
            arguments: arguments,
            input: nil,
            timeout: timeout,
            environment: nil,
            currentDirectory: nil
        )
    }
}
