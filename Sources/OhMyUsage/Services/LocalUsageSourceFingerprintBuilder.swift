// Source fingerprint construction for local usage providers: enumerates each
// provider's on-disk roots and folds file metadata into a digest used to detect
// when a cached local usage summary must be refreshed.

import Foundation
import CryptoKit

enum LocalUsageSourceFingerprintBuilder {
    static func codexFingerprint(scope: LocalUsageTrendScope) -> LocalUsageSourceFingerprint {
        let codexRoot = "\(NSHomeDirectory())/.codex"
        switch scope {
        case .allAccounts:
            let roots = [
                    "\(codexRoot)/sessions",
                    "\(codexRoot)/archived_sessions"
                ]
            return fingerprint(roots: roots, inventory: LocalUsageSourceInventory.files(descriptor: .codexSessionJSONL, roots: roots))
        case .currentAccount:
            return fingerprint(
                roots: ["\(codexRoot)/logs_2.sqlite", "\(codexRoot)/logs_2.sqlite-wal"],
                includeFile: { _ in true }
            )
        }
    }

    static func claudeFingerprint(
        scope: LocalUsageTrendScope,
        currentConfigDir: String?,
        allConfigDirs: [String]
    ) -> LocalUsageSourceFingerprint {
        let defaultRoot = "\(NSHomeDirectory())/.claude/projects"
        let normalizedAllConfigDirs = allConfigDirs.compactMap(normalizedDirectoryPath)
        let allRoots = uniquePaths(
            [defaultRoot] + normalizedAllConfigDirs.map(projectsRoot(fromConfigDir:))
        )

        let roots: [String]
        switch scope {
        case .allAccounts:
            roots = allRoots
        case .currentAccount:
            if let currentConfigDir = normalizedDirectoryPath(currentConfigDir) {
                roots = [projectsRoot(fromConfigDir: currentConfigDir)]
            } else {
                roots = [defaultRoot]
            }
        }

        return fingerprint(
            roots: roots,
            includeFile: { $0.pathExtension.lowercased() == "jsonl" }
        )
    }

    static func kimiFingerprint() -> LocalUsageSourceFingerprint {
        fingerprint(
            roots: [
                "\(NSHomeDirectory())/.kimi/sessions",
                "\(NSHomeDirectory())/.kimi-code/sessions"
            ],
            includeFile: { $0.lastPathComponent == "wire.jsonl" }
        )
    }

    static func cursorFingerprint() -> LocalUsageSourceFingerprint {
        fingerprint(
            roots: [
                "\(NSHomeDirectory())/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
                "\(NSHomeDirectory())/Library/Application Support/Cursor/User/globalStorage/state.vscdb-wal",
                "\(NSHomeDirectory())/.cursor/projects"
            ],
            includeFile: { url in
                ["state.vscdb", "state.vscdb-wal"].contains(url.lastPathComponent) || url.pathExtension.lowercased() == "jsonl"
            }
        )
    }

    static func grokFingerprint() -> LocalUsageSourceFingerprint {
        fingerprint(
            roots: [GrokLocalUsageService.resolvedSessionsRoot(
                homeDirectory: NSHomeDirectory(),
                environment: ProcessInfo.processInfo.environment
            )],
            includeFile: { name in
                let filename = name.lastPathComponent
                return filename == "summary.json" || filename == "updates.jsonl" || filename == "signals.json"
            }
        )
    }

    static func geminiFingerprint() -> LocalUsageSourceFingerprint {
        fingerprint(
            roots: ["\(NSHomeDirectory())/.gemini/tmp"],
            includeFile: { url in
                let name = url.lastPathComponent.lowercased()
                return name.hasPrefix("session-") && (name.hasSuffix(".jsonl") || name.hasSuffix(".json"))
            }
        )
    }

    static func fingerprint(
        roots: [String],
        fileManager: FileManager = .default,
        includeFile: (URL) -> Bool
    ) -> LocalUsageSourceFingerprint {
        let normalizedRoots = roots
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }
            .sorted()
        var accumulator = FingerprintAccumulator()

        for root in normalizedRoots {
            if Task.isCancelled { break }
            let rootURL = URL(fileURLWithPath: root)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory) else {
                continue
            }

            if !isDirectory.boolValue {
                if includeFile(rootURL) {
                    accumulator.add(rootURL, fileManager: fileManager)
                }
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator where includeFile(fileURL) {
                if Task.isCancelled { break }
                accumulator.add(fileURL, fileManager: fileManager)
            }
        }

        return LocalUsageSourceFingerprint(
            roots: normalizedRoots,
            fileCount: accumulator.fileCount,
            totalSize: accumulator.totalSize,
            latestModificationTime: accumulator.latestModificationTime,
            metadataDigest: accumulator.digest
        )
    }

    static func fingerprint(roots: [String], inventory: [LocalUsageFileSnapshot]) -> LocalUsageSourceFingerprint {
        var accumulator = FingerprintAccumulator()
        for file in inventory {
            accumulator.add(path: file.path, size: file.fileSize, modifiedAt: file.modifiedAtRef.map(Date.init(timeIntervalSinceReferenceDate:)), inode: file.fileIdentity)
        }
        return LocalUsageSourceFingerprint(
            roots: roots.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }.sorted(),
            fileCount: accumulator.fileCount, totalSize: accumulator.totalSize,
            latestModificationTime: accumulator.latestModificationTime, metadataDigest: accumulator.digest)
    }

    private struct FingerprintAccumulator {
        var fileCount = 0
        var totalSize: UInt64 = 0
        var latestModificationTime: Date?
        var metadataTuples: [String] = []

        var digest: String {
            let data = Data(metadataTuples.sorted().joined(separator: "\n").utf8)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        mutating func add(_ fileURL: URL, fileManager: FileManager) {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            ), values.isRegularFile == true else {
                return
            }

            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
            add(path: fileURL.standardizedFileURL.path, size: UInt64(max(0, values.fileSize ?? 0)),
                modifiedAt: values.contentModificationDate, inode: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value)
        }

        mutating func add(path: String, size: UInt64, modifiedAt: Date?, inode: UInt64?) {
            let tuple = [path, String(size), String(modifiedAt?.timeIntervalSinceReferenceDate ?? 0), inode.map(String.init) ?? ""]
            // JSON framing avoids ambiguity for paths containing delimiters or newlines.
            if let data = try? JSONEncoder().encode(tuple), let text = String(data: data, encoding: .utf8) {
                metadataTuples.append(text)
            }
            fileCount += 1
            totalSize += size
            if let modifiedAt,
               latestModificationTime == nil || modifiedAt > (latestModificationTime ?? .distantPast) {
                latestModificationTime = modifiedAt
            }
        }
    }

    private static func projectsRoot(fromConfigDir configDir: String) -> String {
        URL(fileURLWithPath: configDir, isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .path
    }

    private static func normalizedDirectoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func uniquePaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for path in paths where seen.insert(path).inserted {
            output.append(path)
        }
        return output
    }
}
