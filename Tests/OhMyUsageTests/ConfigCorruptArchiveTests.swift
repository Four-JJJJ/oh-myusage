import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import OhMyUsage

final class ConfigCorruptArchiveTests: XCTestCase {
    func testInvalidOriginalSurvivesRepeatedLoadsBootstrapAndExplicitSave() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("OhMyUsage")
        let original = Data("{original: broken config".utf8)
        try original.write(to: directory.appendingPathComponent("config.json"))

        let store = ConfigStore(baseDirectoryURL: root)
        _ = try store.load()
        XCTAssertEqual(try archivedData(in: directory), [original])
        _ = try ConfigStore(baseDirectoryURL: root).load()
        try store.saveDuringBootstrap(.default)
        try store.save(.default)
        _ = try ConfigStore(baseDirectoryURL: root).load()
        XCTAssertEqual(try archivedData(in: directory), [original])
        try store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL(in: directory).path))
    }

    func testInvalidPrimaryIsArchivedBeforeRecoveryOverwritesIt() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("OhMyUsage")
        let store = ConfigStore(baseDirectoryURL: root)
        try store.save(.default)
        let original = Data("invalid primary".utf8)
        try original.write(to: directory.appendingPathComponent("config.json"))
        _ = try store.load()
        XCTAssertEqual(try archivedData(in: directory), [original])
    }

    func testDistinctCorruptSnapshotsAreNotOverwrittenAndDuplicatesAreDeduplicated() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("OhMyUsage")
        let first = Data("first corrupt snapshot".utf8)
        let second = Data("second corrupt snapshot".utf8)
        try first.write(to: directory.appendingPathComponent("config.json"))
        try second.write(to: directory.appendingPathComponent("config.backup.json"))
        try first.write(to: directory.appendingPathComponent("config.recovery.json"))
        _ = try ConfigStore(baseDirectoryURL: root).load()
        XCTAssertEqual(Set(try archivedData(in: directory)), Set([first, second]))
        XCTAssertEqual(try archivedData(in: directory).count, 2)
    }

    func testNormalFirstLaunchDoesNotCreateCorruptArchive() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try ConfigStore(baseDirectoryURL: root).load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL(in: root.appendingPathComponent("OhMyUsage")).path))
    }

    func testExplicitSaveBeforeLoadAlsoPreservesInvalidOriginal() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("OhMyUsage")
        let original = Data("invalid unsampled config".utf8)
        try original.write(to: directory.appendingPathComponent("config.json"))
        try ConfigStore(baseDirectoryURL: root).save(.default)
        XCTAssertEqual(try archivedData(in: directory), [original])
    }

    func testUsablePreservedCandidateCanRecoverWithoutDeletingCorruptArchive() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("OhMyUsage")
        let original = Data("invalid old snapshot".utf8)
        try original.write(to: directory.appendingPathComponent("config.json"))
        let store = ConfigStore(baseDirectoryURL: root)
        _ = try store.load()
        var candidate = AppConfig.default
        candidate.language = .en
        try JSONEncoder().encode(candidate).write(to: directory.appendingPathComponent("config.preserved-fallback-candidate.json"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("config.last-known-good.json"))

        XCTAssertEqual(try store.load().language, .en)
        XCTAssertEqual(try archivedData(in: directory), [original])
        let attributes = try FileManager.default.attributesOfItem(atPath: archiveURL(in: directory).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testArchiveWriteFailureDoesNotReplaceOriginal() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("OhMyUsage")
        let original = Data("irreplaceable invalid original".utf8)
        let primary = directory.appendingPathComponent("config.json")
        try original.write(to: primary)
        try Data("blocks archive directory".utf8).write(to: archiveURL(in: directory))
        XCTAssertThrowsError(try ConfigStore(baseDirectoryURL: root).load())
        XCTAssertEqual(try Data(contentsOf: primary), original)
        XCTAssertThrowsError(try ConfigStore(baseDirectoryURL: root).save(.default))
        XCTAssertEqual(try Data(contentsOf: primary), original)
    }

    func testDamagedArchiveCannotMasqueradeAsSuccessfullyPreservedOriginal() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("OhMyUsage")
        let primary = directory.appendingPathComponent("config.json")
        let original = Data("original to preserve".utf8)
        try original.write(to: primary)
        let store = ConfigStore(baseDirectoryURL: root)
        _ = try store.load()
        let archive = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: archiveURL(in: directory), includingPropertiesForKeys: nil).first)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data("partial or corrupted archive".utf8).write(to: archive)
        try original.write(to: primary)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: primary), original)
        XCTAssertEqual(try Data(contentsOf: archive), Data("partial or corrupted archive".utf8))
    }

    func testUnreadableSourceDoesNotBecomeEmptyArchiveOrDefaultConfig() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("OhMyUsage")
        let primary = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ConfigStore(baseDirectoryURL: root).load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: primary.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL(in: directory).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.backup.json").path))
    }

    func testArchiveSymlinkCannotRedirectPrivateEvidence() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("OhMyUsage")
        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: archiveURL(in: directory), withDestinationURL: other)
        let original = Data("original".utf8)
        try original.write(to: directory.appendingPathComponent("config.json"))
        XCTAssertThrowsError(try ConfigStore(baseDirectoryURL: root).load())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: other.path), [])
    }

    func testInterruptedStagingDoesNotBlockExclusiveSingleLinkPublication() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ConfigStorePaths(rootDirectoryURL: root)
        try FileManager.default.createDirectory(at: paths.corruptArchiveDirectoryURL, withIntermediateDirectories: true)
        let original = Data("original interrupted before publication".utf8)
        let leftover = paths.corruptArchiveDirectoryURL.appendingPathComponent(".archive-interrupted.tmp")
        try original.write(to: leftover)
        let writer = ConfigSnapshotWriter(paths: paths, fileManager: .default, log: { _ in })

        try writer.archiveCorruptSnapshot(original)
        let hash = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        let archive = paths.corruptArchiveDirectoryURL.appendingPathComponent("config-\(hash).json")
        var info = stat()
        XCTAssertEqual(lstat(archive.path, &info), 0)
        XCTAssertEqual(info.st_nlink, 1)
        XCTAssertEqual(try Data(contentsOf: archive), original)
        try writer.archiveCorruptSnapshot(original)
        XCTAssertEqual(try Data(contentsOf: leftover), original)
    }

    func testUnexpectedHardlinkedArchiveRemainsRejectedWithoutDestroyingEvidence() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ConfigStorePaths(rootDirectoryURL: root)
        let writer = ConfigSnapshotWriter(paths: paths, fileManager: .default, log: { _ in })
        let original = Data("existing multiply linked evidence".utf8)
        try writer.archiveCorruptSnapshot(original)
        let archive = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: paths.corruptArchiveDirectoryURL, includingPropertiesForKeys: nil).first)
        let leftover = paths.corruptArchiveDirectoryURL.appendingPathComponent(".archive-old-interrupted.tmp")
        XCTAssertEqual(Darwin.link(archive.path, leftover.path), 0)
        XCTAssertThrowsError(try writer.archiveCorruptSnapshot(original))
        XCTAssertEqual(try Data(contentsOf: archive), original)
        XCTAssertEqual(try Data(contentsOf: leftover), original)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("OhMyUsage"), withIntermediateDirectories: true)
        return root
    }

    private func archiveURL(in directory: URL) -> URL {
        directory.appendingPathComponent("config.corrupt-archive", isDirectory: true)
    }

    private func archivedData(in directory: URL) throws -> [Data] {
        try FileManager.default.contentsOfDirectory(at: archiveURL(in: directory), includingPropertiesForKeys: nil)
            .map { try Data(contentsOf: $0) }
    }
}
