import Foundation
import XCTest

final class DevelopmentScriptTests: XCTestCase {
    func testDefaultBuildUsesCheckoutSpecificCacheOutsideRepository() throws {
        let result = try runScript(arguments: [])
        XCTAssertEqual(result.status, 0)
        let lines = result.output.components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "build")
        XCTAssertEqual(lines[2], "--scratch-path")
        XCTAssertTrue(lines[3].contains("/Library/Caches/OhMyUsage/Builds/"))
        XCTAssertFalse(lines[3].contains(repository.path))
        XCTAssertEqual(lines[4], repository.resolvingSymlinksInPath().path)
    }

    func testBuildOverridesAndArgumentsArePassedWithoutSplittingSpaces() throws {
        let result = try runScript(
            arguments: ["test", "--filter", "One Test", "-Xswiftc", "-warnings-as-errors"],
            overrides: ["OMU_BUILD_PATH": "/tmp/omu fixture build", "SWIFT_BUILD_SYSTEM": "native"]
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(Array(result.output.components(separatedBy: "\n").prefix(10)), [
            "/explicit/Xcode", "test", "--scratch-path", "/tmp/omu fixture build",
            "--build-system", "native", "--filter", "One Test", "-Xswiftc", "-warnings-as-errors"
        ])
    }

    func testUnknownCommandDoesNotInvokeSwift() throws {
        let result = try runScript(arguments: ["invalid"])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("Usage:"))
        XCTAssertFalse(result.output.contains("/explicit/Xcode"))
    }

    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func runScript(arguments: [String], overrides: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let swift = root.appendingPathComponent("swift")
        let stub = "#!/bin/bash\nprintf '%s\\n' \"$DEVELOPER_DIR\" \"$@\" \"$PWD\"\n"
        try Data(stub.utf8).write(to: swift)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: swift.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repository.appendingPathComponent("scripts/dev.sh").path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OMU_BUILD_PATH")
        environment.removeValue(forKey: "SWIFT_BUILD_SYSTEM")
        environment["PATH"] = root.path + ":/usr/bin:/bin"
        environment["HOME"] = root.path
        environment["DEVELOPER_DIR"] = "/explicit/Xcode"
        environment.merge(overrides) { _, new in new }
        process.environment = environment
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }
}
