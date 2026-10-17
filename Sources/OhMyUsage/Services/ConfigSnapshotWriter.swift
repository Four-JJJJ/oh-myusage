import CryptoKit
import Darwin
import Foundation

final class ConfigSnapshotWriter {
    private let paths: ConfigStorePaths
    private let fileManager: FileManager
    private let log: (String) -> Void
    private var knownUsableSnapshots: [URL: Data] = [:]

    init(
        paths: ConfigStorePaths,
        fileManager: FileManager,
        log: @escaping (String) -> Void
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.log = log
    }

    func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: paths.directoryURL.path) {
            try fileManager.createDirectory(at: paths.directoryURL, withIntermediateDirectories: true)
        }
    }

    func save(
        _ config: AppConfig,
        updateLastKnownGood: Bool,
        clearPreservedFallbackCandidate: Bool
    ) throws {
        try ensureDirectoryExists()
        let data = try encodedConfigData(config)
        // Preserve unreadable originals before any snapshot can be replaced or removed.
        for url in [paths.fileURL, paths.backupFileURL, paths.recoveryFileURL,
                    paths.lastKnownGoodFileURL, paths.preservedFallbackCandidateFileURL] {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let existing = try Data(contentsOf: url)
            if existing == data || knownUsableSnapshots[url] == existing { continue }
            if (try? AppConfig.decodeWithDiagnostics(from: existing)) == nil {
                try archiveCorruptSnapshot(existing)
            } else {
                knownUsableSnapshots[url] = existing
            }
        }
        try writeData(data, to: paths.fileURL)
        try writeData(data, to: paths.backupFileURL)
        try writeData(data, to: paths.recoveryFileURL)
        if updateLastKnownGood {
            try writeLastKnownGoodIfEligible(data, overwriteExisting: true)
        }
        if clearPreservedFallbackCandidate {
            try removePreservedFallbackCandidateIfPresent()
        }
        for url in [paths.fileURL, paths.backupFileURL, paths.recoveryFileURL] {
            knownUsableSnapshots[url] = data
        }
        if updateLastKnownGood { knownUsableSnapshots[paths.lastKnownGoodFileURL] = data }
    }

    func syncShadowCopiesIfNeeded(primaryData: Data) throws {
        if !fileManager.fileExists(atPath: paths.backupFileURL.path) {
            try writeData(primaryData, to: paths.backupFileURL)
        }
        if !fileManager.fileExists(atPath: paths.recoveryFileURL.path) {
            try writeData(primaryData, to: paths.recoveryFileURL)
        }
        try writeLastKnownGoodIfEligible(primaryData, overwriteExisting: false)
    }

    func preserveFallbackCandidateIfNeeded(_ data: Data?) throws {
        guard let data, !data.isEmpty else { return }
        try writeData(data, to: paths.preservedFallbackCandidateFileURL)
    }

    func archiveCorruptSnapshot(_ data: Data) throws {
        let directory = paths.corruptArchiveDirectoryURL
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Archives are not recovery candidates: only an explicit reset removes them.
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent("config-\(hash).json")
        if fileManager.fileExists(atPath: url.path) {
            try validateArchive(at: url, matches: data)
            return
        }
        let staging = directory.appendingPathComponent(".archive-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: staging) }
        try PrivateProfileFile(url: staging, fileManager: fileManager).write(data)
        // Exclusive atomic move also avoids a crash leaving two links to one archive.
        if Darwin.renamex_np(staging.path, url.path, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EEXIST else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            try validateArchive(at: url, matches: data)
        }
    }

    private func validateArchive(at url: URL, matches data: Data) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              try Data(contentsOf: url) == data else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func encodedConfigData(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private func writeLastKnownGoodIfEligible(_ data: Data, overwriteExisting: Bool) throws {
        if !overwriteExisting, fileManager.fileExists(atPath: paths.lastKnownGoodFileURL.path) {
            return
        }
        let decoded = try AppConfig.decodeWithDiagnostics(from: data)
        guard !decoded.diagnostics.hadLossyProviderDecoding else {
            log(
                "Skipped updating last-known-good snapshot because provider decoding dropped \(decoded.diagnostics.droppedProviderEntryCount) entries"
            )
            return
        }
        try writeData(data, to: paths.lastKnownGoodFileURL)
    }

    private func removePreservedFallbackCandidateIfPresent() throws {
        if fileManager.fileExists(atPath: paths.preservedFallbackCandidateFileURL.path) {
            try fileManager.removeItem(at: paths.preservedFallbackCandidateFileURL)
        }
    }
}
