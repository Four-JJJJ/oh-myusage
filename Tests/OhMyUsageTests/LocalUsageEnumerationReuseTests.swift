import Foundation
import XCTest
@testable import OhMyUsage

final class LocalUsageEnumerationReuseTests: XCTestCase {
    func testServicesRetainSharedEnumerationCacheRatherThanRecreatingPerFetch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Grok", "Gemini"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/OhMyUsage/Services/\(name)LocalUsageService.swift"), encoding: .utf8)
            XCTAssertTrue(source.contains("static let enumerationCache = LocalUsageFileEnumerationCache()"))
            XCTAssertTrue(source.contains("Self.enumerationCache.files("))
            XCTAssertFalse(source.contains("let files = LocalUsageFileEnumerationCache().files("))
        }
    }

    func testCacheInvalidatesForAddedDeletedFilesAndSeparatesRootsAndCutoffs() throws {
        try withRoot { root, manager in
            let cache = LocalUsageFileEnumerationCache()
            let cutoff = Date(timeIntervalSince1970: 0)
            var enumerations = 0
            func files(_ path: URL, since: Date = cutoff) -> [String] {
                cache.files(identifier: "test", roots: [path.path], cutoff: since, fileManager: manager,
                            includeFile: { url in
                                if url.lastPathComponent == "second.json" || url.lastPathComponent == "first.json" { enumerations += 1 }
                                return url.pathExtension == "json"
                            }).map { URL(fileURLWithPath: $0.path).lastPathComponent }
            }
            let first = root.appendingPathComponent("first.json")
            try Data("{}".utf8).write(to: first)
            XCTAssertEqual(files(root), ["first.json"])
            XCTAssertEqual(files(root), ["first.json"])
            XCTAssertEqual(enumerations, 1)
            try Data("{\"changed\":true}".utf8).write(to: first)
            XCTAssertEqual(files(root), ["first.json"])
            XCTAssertEqual(enumerations, 2)
            enumerations = 1
            let nested = root.appendingPathComponent("nested")
            try manager.createDirectory(at: nested, withIntermediateDirectories: true)
            let second = nested.appendingPathComponent("second.json")
            try Data("{}".utf8).write(to: second)
            XCTAssertEqual(Set(files(root)), Set(["first.json", "second.json"]))
            XCTAssertEqual(enumerations, 3)
            try manager.removeItem(at: first)
            XCTAssertEqual(files(root), ["second.json"])
            XCTAssertEqual(enumerations, 4)
            XCTAssertEqual(files(root, since: Date.distantFuture), [])
            XCTAssertEqual(enumerations, 5)
            XCTAssertEqual(files(nested), ["second.json"])
            XCTAssertEqual(enumerations, 6)
            XCTAssertEqual(files(root), ["second.json"])
            XCTAssertEqual(enumerations, 6)
        }
    }

    private func withRoot(_ body: (URL, FileManager) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omu-enumeration-\(UUID().uuidString)").resolvingSymlinksInPath()
        let manager = FileManager()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        try body(root.resolvingSymlinksInPath(), manager)
    }
}
