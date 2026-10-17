import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class OfficialProfileFileProtectionTests: XCTestCase {
    func testCodexProfileCreatesPrivateFileAndKeepsPermissionsAfterReplacement() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("profiles/codex_profiles.json")
        let store = CodexAccountProfileStore(fileURL: url)

        for token in ["fixture-one", "fixture-two"] {
            _ = try store.saveProfile(
                slotID: .a,
                displayName: "Fixture",
                note: nil,
                authJSON: "{\"tokens\":{\"access_token\":\"\(token)\"}}",
                currentFingerprint: nil
            )
            XCTAssertEqual(try mode(url), 0o600)
            XCTAssertEqual(try mode(url.deletingLastPathComponent()), 0o700)
            XCTAssertEqual(store.profiles().count, 1)
        }
    }

    func testClaudeProfileCreatesPrivateFileAndKeepsPermissionsAfterReplacement() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("profiles/claude_profiles.json")
        let store = ClaudeAccountProfileStore(fileURL: url)

        for token in ["fixture-one", "fixture-two"] {
            _ = try store.saveProfile(
                slotID: .a,
                displayName: "Fixture",
                note: nil,
                source: .manualCredentials,
                configDir: nil,
                credentialsJSON: "{\"accessToken\":\"\(token)\"}",
                currentFingerprint: nil
            )
            XCTAssertEqual(try mode(url), 0o600)
            XCTAssertEqual(try mode(url.deletingLastPathComponent()), 0o700)
            XCTAssertEqual(store.profiles().count, 1)
        }
    }

    func testExistingProfilesAreProtectedOnInitializationWithoutChangingBytes() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("{\"profiles\":[]}".utf8)
        let codex = root.appendingPathComponent("codex.json")
        let claude = root.appendingPathComponent("claude.json")
        for url in [codex, claude] {
            try bytes.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        _ = CodexAccountProfileStore(fileURL: codex)
        _ = ClaudeAccountProfileStore(fileURL: claude)

        for url in [codex, claude] {
            XCTAssertEqual(try mode(url), 0o600)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testInjectedExistingParentIsNotChmodded() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let url = root.appendingPathComponent("codex.json")
        let store = CodexAccountProfileStore(fileURL: url)
        _ = try store.saveProfile(
            slotID: .a, displayName: "Fixture", note: nil,
            authJSON: "{\"tokens\":{\"access_token\":\"fixture\"}}", currentFingerprint: nil
        )
        XCTAssertEqual(try mode(root), 0o755)
        XCTAssertEqual(try mode(url), 0o600)
    }

    func testProtectedWriteRejectsLinkedDestinationsWithoutChangingOriginal() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.json")
        let link = root.appendingPathComponent("profile.json")
        let bytes = Data("original fixture".utf8)
        try bytes.write(to: original)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let file = PrivateProfileFile(url: link, fileManager: .default)
        XCTAssertThrowsError(try file.write(Data("replacement".utf8)))
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.linkItem(at: original, to: link)
        XCTAssertThrowsError(try file.write(Data("replacement".utf8)))
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

    func testFailedProtectedWritePreservesOriginalAndLeavesNoTemporaryFile() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("profile.json")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let file = PrivateProfileFile(url: destination, fileManager: .default)
        XCTAssertThrowsError(try file.write(Data("fixture".utf8)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["profile.json"])
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func mode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)).intValue & 0o777
    }
}
