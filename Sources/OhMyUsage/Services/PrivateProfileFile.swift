import Darwin
import Foundation

struct PrivateProfileFile {
    let url: URL
    let fileManager: FileManager
    var ownsParentDirectory = false

    static func defaultURL(name: String, fileManager: FileManager) -> URL {
        let environment = ProcessInfo.processInfo.environment
        let isTesting = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTest_SESSION_IDENTIFIER"] != nil
            || ProcessInfo.processInfo.processName.lowercased().contains("xctest")
            || Bundle.main.bundlePath.lowercased().contains(".xctest")
        let root = isTesting
            ? fileManager.temporaryDirectory.appendingPathComponent("OhMyUsageTests/\(UUID().uuidString)")
            : fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("OhMyUsage/\(name)")
    }

    func protectExistingFile() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try requireRegularFile()
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if ownsParentDirectory {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        }
    }

    func write(_ data: Data) throws {
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        if ownsParentDirectory {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        }
        if fileManager.fileExists(atPath: url.path) { try requireRegularFile() }

        // Set permissions before writing secrets; chmod after Data.atomic leaves an exposure window.
        let temporaryURL = parent.appendingPathComponent(".profile-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer {
            Darwin.close(descriptor)
            try? fileManager.removeItem(at: temporaryURL)
        }
        guard Darwin.fchmod(descriptor, 0o600) == 0 else { throw posixError() }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw posixError() }
                offset += written
            }
        }
        guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
        guard Darwin.rename(temporaryURL.path, url.path) == 0 else { throw posixError() }
    }

    private func requireRegularFile() throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw posixError() }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
