import Foundation

enum ConfigSnapshotSource: String {
    case primary = "primary"
    case backup = "backup"
    case recovery = "recovery"
    case lastKnownGood = "last-known-good"
    case preservedFallbackCandidate = "preserved-fallback-candidate"
}

enum ConfigSnapshotLoadResult {
    case missing
    case unreadable(Error)
    case invalid(Data, Error)
    case lossy(ConfigSnapshot, AppConfigDecodeDiagnostics)
    case usable(ConfigSnapshot)
}

struct ConfigSnapshot {
    let source: ConfigSnapshotSource
    let rawData: Data
    let config: AppConfig
    let wasMigrated: Bool
}

final class ConfigSnapshotLoader {
    private let paths: ConfigStorePaths
    private let fileManager: FileManager

    init(paths: ConfigStorePaths, fileManager: FileManager) {
        self.paths = paths
        self.fileManager = fileManager
    }

    var currentSnapshotCandidates: [(ConfigSnapshotSource, URL)] {
        [
            (.primary, paths.fileURL),
            (.backup, paths.backupFileURL),
            (.recovery, paths.recoveryFileURL)
        ]
    }

    var recoveryLoadOrder: [(ConfigSnapshotSource, URL)] {
        if fileManager.fileExists(atPath: paths.preservedFallbackCandidateFileURL.path) {
            return [
                (.lastKnownGood, paths.lastKnownGoodFileURL),
                (.preservedFallbackCandidate, paths.preservedFallbackCandidateFileURL),
                (.primary, paths.fileURL),
                (.backup, paths.backupFileURL),
                (.recovery, paths.recoveryFileURL)
            ]
        }

        return [
            (.primary, paths.fileURL),
            (.backup, paths.backupFileURL),
            (.recovery, paths.recoveryFileURL),
            (.lastKnownGood, paths.lastKnownGoodFileURL)
        ]
    }

    var hasPreservedFallbackCandidate: Bool {
        fileManager.fileExists(atPath: paths.preservedFallbackCandidateFileURL.path)
    }

    func loadStoredConfig(at url: URL, source: ConfigSnapshotSource) -> ConfigSnapshotLoadResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unreadable(error)
        }
        do {
            let decoded = try AppConfig.decodeWithDiagnostics(from: data)
            let migrated = decoded.config.migratedWithSiteDefaults()
            let snapshot = ConfigSnapshot(
                source: source,
                rawData: data,
                config: migrated,
                wasMigrated: migrated != decoded.config
            )

            if decoded.diagnostics.hadLossyProviderDecoding {
                return .lossy(snapshot, decoded.diagnostics)
            }

            return .usable(snapshot)
        } catch {
            return .invalid(data, error)
        }
    }
}
