// Source discovery for local usage parsing: the file snapshot value type, the
// shared filesystem enumeration cache that avoids re-scanning unchanged roots,
// and the provider-specific source inventory descriptors layered on that cache.

import Foundation

struct LocalUsageFileSnapshot: Equatable, Hashable, Sendable {
    var path: String
    var fileSize: UInt64
    var modifiedAtRef: TimeInterval?
    var fileIdentity: UInt64? = nil
}

final class LocalUsageFileEnumerationCache: @unchecked Sendable {
    private struct CacheKey: Hashable {
        var identifier: String
        var roots: [String]
        var cutoffRef: TimeInterval
    }

    private struct PathSnapshot: Equatable {
        var path: String
        var exists: Bool
        var isDirectory: Bool
        var fileSize: UInt64?
        var modifiedAtRef: TimeInterval?
        var fileIdentity: UInt64? = nil
    }

    private struct Entry {
        var pathSnapshots: [PathSnapshot]
        var files: [LocalUsageFileSnapshot]
    }

    private let lock = NSLock()
    private let maxEntries: Int
    private var entries: [CacheKey: Entry] = [:]

    init(maxEntries: Int = 32) {
        self.maxEntries = max(1, maxEntries)
    }

    func files(
        identifier: String,
        roots: [String],
        cutoff: Date,
        fileManager: FileManager,
        includeFile: (URL) -> Bool
    ) -> [LocalUsageFileSnapshot] {
        let normalizedRoots = roots
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }
            .sorted()
        let key = CacheKey(
            identifier: identifier,
            roots: normalizedRoots,
            cutoffRef: cutoff.timeIntervalSinceReferenceDate
        )

        // Validate filesystem metadata outside the lock. Holding the lock during
        // pathSnapshot I/O can stall other callers (including tests) for a long time
        // when a prior enumeration cached a large directory tree.
        lock.lock()
        let cached = entries[key]
        lock.unlock()

        if let entry = cached, isValid(entry: entry, fileManager: fileManager) {
            return entry.files
        }

        let entry = buildEntry(
            roots: normalizedRoots,
            cutoff: cutoff,
            fileManager: fileManager,
            includeFile: includeFile
        )
        guard !Task.isCancelled else { return entry.files }

        lock.lock()
        entries[key] = entry
        pruneIfNeeded()
        lock.unlock()

        return entry.files
    }

    func removeAllEntries() {
        lock.lock()
        entries.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private func isValid(entry: Entry, fileManager: FileManager) -> Bool {
        for snapshot in entry.pathSnapshots {
            if Task.isCancelled { return false }
            if Self.pathSnapshot(atPath: snapshot.path, fileManager: fileManager) != snapshot {
                return false
            }
        }
        return true
    }

    private func buildEntry(
        roots: [String],
        cutoff: Date,
        fileManager: FileManager,
        includeFile: (URL) -> Bool
    ) -> Entry {
        var pathSnapshots: [PathSnapshot] = []
        var files: [LocalUsageFileSnapshot] = []

        for root in roots {
            if Task.isCancelled { break }
            let rootURL = URL(fileURLWithPath: root)
            let rootSnapshot = Self.pathSnapshot(atPath: root, fileManager: fileManager)
            pathSnapshots.append(rootSnapshot)
            guard rootSnapshot.exists else {
                continue
            }

            if !rootSnapshot.isDirectory {
                guard includeFile(rootURL),
                      let file = Self.fileSnapshot(atPath: root, fileManager: fileManager) else {
                    continue
                }
                if Self.modifiedAtRef(file.modifiedAtRef, isAtOrAfter: cutoff) {
                    files.append(file)
                }
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                if Task.isCancelled { break }
                guard let values = try? fileURL.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey,
                        .contentModificationDateKey
                    ]
                ) else {
                    continue
                }

                // Avoid symlink cycles / accidental traversal into huge external trees.
                if values.isSymbolicLink == true {
                    if values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                if values.isDirectory == true {
                    pathSnapshots.append(Self.pathSnapshot(from: fileURL, values: values))
                    continue
                }

                guard includeFile(fileURL),
                      values.isRegularFile == true else {
                    continue
                }

                let size = UInt64(max(0, values.fileSize ?? 0))
                let snapshot = LocalUsageFileSnapshot(
                    path: fileURL.path,
                    fileSize: size,
                    modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate,
                    fileIdentity: Self.fileIdentity(atPath: fileURL.path)
                )
                pathSnapshots.append(Self.pathSnapshot(from: fileURL, values: values))
                if Self.modifiedAtRef(snapshot.modifiedAtRef, isAtOrAfter: cutoff) {
                    files.append(snapshot)
                }
            }
        }

        return Entry(
            pathSnapshots: pathSnapshots,
            files: files.sorted { $0.path < $1.path }
        )
    }

    private static func modifiedAtRef(_ modifiedAtRef: TimeInterval?, isAtOrAfter cutoff: Date) -> Bool {
        guard let modifiedAtRef else { return true }
        return modifiedAtRef >= cutoff.timeIntervalSinceReferenceDate
    }

    private static func fileSnapshot(
        atPath path: String,
        fileManager: FileManager
    ) -> LocalUsageFileSnapshot? {
        let snapshot = pathSnapshot(atPath: path, fileManager: fileManager)
        guard snapshot.exists,
              !snapshot.isDirectory else {
            return nil
        }
        return LocalUsageFileSnapshot(
            path: path,
            fileSize: snapshot.fileSize ?? 0,
            modifiedAtRef: snapshot.modifiedAtRef,
            fileIdentity: snapshot.fileIdentity
        )
    }

    private static func pathSnapshot(
        atPath path: String,
        fileManager: FileManager
    ) -> PathSnapshot {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return PathSnapshot(
                path: path,
                exists: false,
                isDirectory: false,
                fileSize: nil,
                modifiedAtRef: nil
            )
        }

        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let modifiedAt = attributes?[.modificationDate] as? Date
        let size = attributes?[.size] as? NSNumber
        return PathSnapshot(
            path: path,
            exists: true,
            isDirectory: isDirectory.boolValue,
            fileSize: isDirectory.boolValue ? nil : size.map { UInt64(truncating: $0) },
            modifiedAtRef: modifiedAt?.timeIntervalSinceReferenceDate,
            fileIdentity: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }

    private static func pathSnapshot(
        from url: URL,
        values: URLResourceValues
    ) -> PathSnapshot {
        PathSnapshot(
            path: url.path,
            exists: true,
            isDirectory: values.isDirectory == true,
            fileSize: values.isDirectory == true ? nil : UInt64(max(0, values.fileSize ?? 0)),
            modifiedAtRef: values.contentModificationDate?.timeIntervalSinceReferenceDate,
            fileIdentity: fileIdentity(atPath: url.path)
        )
    }

    private static func fileIdentity(atPath path: String) -> UInt64? {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    private func pruneIfNeeded() {
        guard entries.count > maxEntries else { return }
        let overflow = entries.count - maxEntries
        for key in entries.keys.prefix(overflow) {
            entries.removeValue(forKey: key)
        }
    }
}

/// Explicit filter identities prevent different parsers sharing an incompatible inventory.
enum LocalUsageSourceInventory {
    enum Descriptor: String {
        case codexSessionJSONL
        case kimiWireJSONL

        func includes(_ url: URL) -> Bool {
            switch self {
            case .codexSessionJSONL: return url.pathExtension.lowercased() == "jsonl"
            case .kimiWireJSONL: return url.lastPathComponent == "wire.jsonl"
            }
        }
    }

    private static let cache = LocalUsageFileEnumerationCache(maxEntries: 8)

    static func files(descriptor: Descriptor, roots: [String], fileManager: FileManager = .default) -> [LocalUsageFileSnapshot] {
        cache.files(identifier: descriptor.rawValue, roots: roots, cutoff: .distantPast,
                    fileManager: fileManager, includeFile: descriptor.includes)
    }
}
