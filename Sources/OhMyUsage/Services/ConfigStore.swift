import Foundation

final class ConfigStore {
    private let paths: ConfigStorePaths
    private let fileManager: FileManager
    private lazy var snapshotWriter = ConfigSnapshotWriter(
        paths: paths, fileManager: fileManager, log: { [weak self] in self?.log($0) }
    )
    private(set) var lastLoadWasLossy = false
    private var directoryURL: URL { paths.directoryURL }
    private var fileURL: URL { paths.fileURL }
    private var backupFileURL: URL { paths.backupFileURL }
    private var recoveryFileURL: URL { paths.recoveryFileURL }
    private var lastKnownGoodFileURL: URL { paths.lastKnownGoodFileURL }
    private var preservedFallbackCandidateFileURL: URL { paths.preservedFallbackCandidateFileURL }

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        let rootDirectory: URL
        if let baseDirectoryURL {
            rootDirectory = baseDirectoryURL
        } else {
            rootDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }
        let paths = ConfigStorePaths(rootDirectoryURL: rootDirectory)
        self.paths = paths
    }

    func load() throws -> AppConfig {
        let snapshotLoader = makeSnapshotLoader()
        let snapshotWriter = makeSnapshotWriter()
        try snapshotWriter.ensureDirectoryExists()
        lastLoadWasLossy = false
        var sawPersistedConfigSource = false
        var preservedFallbackData: Data?
        var lossySnapshot: (snapshot: ConfigSnapshot, diagnostics: AppConfigDecodeDiagnostics)?

        if !snapshotLoader.hasPreservedFallbackCandidate {
            for (source, url) in snapshotLoader.currentSnapshotCandidates {
                let result = snapshotLoader.loadStoredConfig(at: url, source: source)
                switch result {
                case .missing:
                    continue
                case .unreadable(let error):
                    throw error
                case .invalid(let data, let error):
                    try snapshotWriter.archiveCorruptSnapshot(data)
                    sawPersistedConfigSource = true
                    if preservedFallbackData == nil {
                        preservedFallbackData = data
                    }
                    log("Ignoring \(source.rawValue) config because it could not be decoded: \(error.localizedDescription)")
                case .lossy(let snapshot, let diagnostics):
                    sawPersistedConfigSource = true
                    if preservedFallbackData == nil {
                        preservedFallbackData = snapshot.rawData
                    }
                    if lossySnapshot == nil {
                        lossySnapshot = (snapshot, diagnostics)
                    }
                    log(
                        "Found lossy \(source.rawValue) config; keeping it as a fallback because provider decoding dropped \(diagnostics.droppedProviderEntryCount) entries"
                    )
                case .usable(let snapshot):
                    let loaded = try acceptLoadedSnapshot(snapshot)
                    return applyLegacyImportIfNeeded(to: loaded)
                }
            }

            if let lossySnapshot {
                let loaded = try acceptLossySnapshot(lossySnapshot.snapshot, diagnostics: lossySnapshot.diagnostics)
                return applyLegacyImportIfNeeded(to: loaded)
            }
        }

        for (source, url) in snapshotLoader.recoveryLoadOrder {
            let result = snapshotLoader.loadStoredConfig(at: url, source: source)
            switch result {
            case .missing:
                continue
            case .unreadable(let error):
                throw error
            case .invalid(let data, let error):
                try snapshotWriter.archiveCorruptSnapshot(data)
                sawPersistedConfigSource = true
                if preservedFallbackData == nil, source != .preservedFallbackCandidate {
                    preservedFallbackData = data
                }
                log("Ignoring \(source.rawValue) config because it could not be decoded: \(error.localizedDescription)")
            case .lossy(let snapshot, let diagnostics):
                sawPersistedConfigSource = true
                if preservedFallbackData == nil, source != .preservedFallbackCandidate {
                    preservedFallbackData = snapshot.rawData
                }
                log(
                    "Ignoring \(source.rawValue) config because provider decoding dropped \(diagnostics.droppedProviderEntryCount) entries"
                )
            case .usable(let snapshot):
                let loaded = try acceptLoadedSnapshot(snapshot)
                return applyLegacyImportIfNeeded(to: loaded)
            }
        }

        if let recovered = try recoverFromPersistedOfficialStateAndRestoreIfNeeded() {
            try snapshotWriter.preserveFallbackCandidateIfNeeded(preservedFallbackData)
            log("Recovered official monitoring state from persisted profiles/slots")
            return applyLegacyImportIfNeeded(to: recovered)
        }

        let defaultConfig = AppConfig.default
        try snapshotWriter.preserveFallbackCandidateIfNeeded(preservedFallbackData)
        try save(defaultConfig)
        if sawPersistedConfigSource {
            log("Fell back to default config after all persisted config sources were invalid or lossy")
        } else {
            log("No persisted config found; wrote default config")
        }
        return applyLegacyImportIfNeeded(to: defaultConfig)
    }

    func save(_ config: AppConfig) throws {
        try save(config, updateLastKnownGood: true, clearPreservedFallbackCandidate: true)
    }

    func saveDuringBootstrap(_ config: AppConfig) throws {
        try save(config, updateLastKnownGood: false, clearPreservedFallbackCandidate: false)
    }

    private func save(
        _ config: AppConfig,
        updateLastKnownGood: Bool,
        clearPreservedFallbackCandidate: Bool
    ) throws {
        try makeSnapshotWriter().save(
            config,
            updateLastKnownGood: updateLastKnownGood,
            clearPreservedFallbackCandidate: clearPreservedFallbackCandidate
        )
    }

    func reset() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        if fileManager.fileExists(atPath: backupFileURL.path) {
            try fileManager.removeItem(at: backupFileURL)
        }
        if fileManager.fileExists(atPath: recoveryFileURL.path) {
            try fileManager.removeItem(at: recoveryFileURL)
        }
        if fileManager.fileExists(atPath: lastKnownGoodFileURL.path) {
            try fileManager.removeItem(at: lastKnownGoodFileURL)
        }
        if fileManager.fileExists(atPath: preservedFallbackCandidateFileURL.path) {
            try fileManager.removeItem(at: preservedFallbackCandidateFileURL)
        }
        if fileManager.fileExists(atPath: paths.corruptArchiveDirectoryURL.path) {
            try fileManager.removeItem(at: paths.corruptArchiveDirectoryURL)
        }
        for source in paths.legacyConfigSources where fileManager.fileExists(atPath: source.importMarkerFileURL.path) {
            try fileManager.removeItem(at: source.importMarkerFileURL)
        }
        for url in legacyImporter().backupDirectories() {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func acceptLoadedSnapshot(_ snapshot: ConfigSnapshot) throws -> AppConfig {
        if snapshot.source == .primary {
            if snapshot.wasMigrated {
                log("Loaded primary config and migrated site defaults before rewriting persisted snapshots")
                try save(snapshot.config)
                return snapshot.config
            }
            try makeSnapshotWriter().syncShadowCopiesIfNeeded(primaryData: snapshot.rawData)
            return snapshot.config
        }

        log("Recovered config from \(snapshot.source.rawValue) snapshot")
        try save(snapshot.config)
        return snapshot.config
    }

    private func acceptLossySnapshot(
        _ snapshot: ConfigSnapshot,
        diagnostics: AppConfigDecodeDiagnostics
    ) throws -> AppConfig {
        lastLoadWasLossy = true
        try makeSnapshotWriter().preserveFallbackCandidateIfNeeded(snapshot.rawData)
        log(
            "Loaded lossy \(snapshot.source.rawValue) config in-place; provider decoding dropped \(diagnostics.droppedProviderEntryCount) entries"
        )
        return snapshot.config
    }

    private func recoverFromPersistedOfficialStateAndRestoreIfNeeded() throws -> AppConfig? {
        let recoveryPolicy = ConfigRecoveryPolicy(directoryURL: directoryURL, fileManager: fileManager)
        guard let recovered = recoveryPolicy.recoveredConfigFromPersistedOfficialState() else {
            return nil
        }
        try save(recovered, updateLastKnownGood: false, clearPreservedFallbackCandidate: false)
        return recovered
    }

    private func log(_ message: String) {
        NSLog("[ConfigStore] %@", message)
    }

    private func applyLegacyImportIfNeeded(to currentConfig: AppConfig) -> AppConfig {
        legacyImporter().applyIfNeeded(to: currentConfig)
    }

    private func makeSnapshotLoader() -> ConfigSnapshotLoader {
        ConfigSnapshotLoader(paths: paths, fileManager: fileManager)
    }

    private func makeSnapshotWriter() -> ConfigSnapshotWriter {
        snapshotWriter
    }

    private func legacyImporter() -> LegacyConfigImporter {
        LegacyConfigImporter(
            paths: paths,
            fileManager: fileManager,
            saveConfig: { config in
                try self.save(config)
            },
            log: { message in
                self.log(message)
            }
        )
    }
}
