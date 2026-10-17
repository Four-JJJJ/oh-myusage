import Foundation

struct LegacyConfigSource {
    let displayName: String
    let directoryURL: URL
    let importMarkerFileURL: URL
    let backupDirectoryPrefix: String
}

struct ConfigStorePaths {
    let rootDirectoryURL: URL
    let directoryURL: URL
    let fileURL: URL
    let backupFileURL: URL
    let recoveryFileURL: URL
    let lastKnownGoodFileURL: URL
    let preservedFallbackCandidateFileURL: URL
    let corruptArchiveDirectoryURL: URL

    init(rootDirectoryURL: URL) {
        self.rootDirectoryURL = rootDirectoryURL
        let directory = rootDirectoryURL.appendingPathComponent("OhMyUsage", isDirectory: true)
        self.directoryURL = directory
        self.fileURL = directory.appendingPathComponent("config.json")
        self.backupFileURL = directory.appendingPathComponent("config.backup.json")
        self.recoveryFileURL = directory.appendingPathComponent("config.recovery.json")
        self.lastKnownGoodFileURL = directory.appendingPathComponent("config.last-known-good.json")
        self.preservedFallbackCandidateFileURL = directory.appendingPathComponent("config.preserved-fallback-candidate.json")
        self.corruptArchiveDirectoryURL = directory.appendingPathComponent("config.corrupt-archive", isDirectory: true)
    }

    var legacyConfigSources: [LegacyConfigSource] {
        [
            LegacyConfigSource(
                displayName: "AIPlanMonitor",
                directoryURL: rootDirectoryURL.appendingPathComponent("AIPlanMonitor", isDirectory: true),
                importMarkerFileURL: directoryURL.appendingPathComponent("legacy-import-aiplanmonitor.done"),
                backupDirectoryPrefix: "legacy-import-backup-aiplanmonitor-"
            ),
            LegacyConfigSource(
                displayName: "AIBalanceMonitor",
                directoryURL: rootDirectoryURL.appendingPathComponent("AIBalanceMonitor", isDirectory: true),
                importMarkerFileURL: directoryURL.appendingPathComponent("legacy-import-aibalancemonitor.done"),
                backupDirectoryPrefix: "legacy-import-backup-aibalancemonitor-"
            )
        ]
    }
}
