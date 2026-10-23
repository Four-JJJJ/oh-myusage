import AppKit
import CryptoKit
import Foundation

struct AppUpdateAsset: Equatable {
    var url: URL
    var sha256: String?
    var size: Int64?
}

struct AppUpdateInfo: Equatable {
    var latestVersion: String
    var releaseURL: URL
    var notesURL: URL?
    var publishedAt: Date?
    var zipAsset: AppUpdateAsset?
    var dmgAsset: AppUpdateAsset?

    var downloadURL: URL? {
        zipAsset?.url ?? dmgAsset?.url
    }
}

struct PreparedAppUpdate {
    var version: String
    var appBundleURL: URL
    var workingDirectoryURL: URL
}

protocol AppUpdateServicing: Actor {
    func fetchLatestRelease() async throws -> AppUpdateInfo
    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate
    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws
}

enum AppUpdateError: LocalizedError {
    case invalidMetadata
    case missingZipAsset
    case missingChecksum
    case checksumMismatch
    case signatureVerificationFailed(String)
    case extractedAppNotFound
    case unsupportedInstallLocation
    case installerLaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            return "Invalid update metadata"
        case .missingZipAsset:
            return "No macOS ZIP asset is available for automatic update"
        case .missingChecksum:
            return "Update manifest does not provide a download checksum"
        case .checksumMismatch:
            return "Downloaded update checksum mismatch"
        case .signatureVerificationFailed(let reason):
            return "Updated app failed signature verification: \(reason)"
        case .extractedAppNotFound:
            return "Updated app bundle was not found in the extracted archive"
        case .unsupportedInstallLocation:
            return "Automatic update requires running from an .app bundle"
        case .installerLaunchFailed:
            return "Update installer failed to start"
        }
    }
}

actor AppUpdateService {
    static let owner = "Four-JJJJ"
    static let repository = "oh-myusage"
    static let legacyRepository = "AI-Plan-Monitor"
    static let repositoryURL = URL(string: "https://github.com/\(owner)/\(repository)")!
    static let releasesURL = URL(string: "https://github.com/\(owner)/\(repository)/releases/latest")!
    static let metadataURL = URL(string: "https://github.com/\(owner)/\(repository)/releases/latest/download/latest.json")!
    static let legacyMetadataURL = URL(string: "https://github.com/\(owner)/\(legacyRepository)/releases/latest/download/latest.json")!
    static let apiBaseURL = URL(string: "https://api.github.com/repos/\(owner)/\(repository)")!
    static let defaultMetadataURLs = [metadataURL, legacyMetadataURL]

    private struct ReleaseManifest: Decodable {
        var version: String
        var pubDate: Date?
        var releaseURL: URL?
        var notesURL: URL?
        var assets: Assets

        struct Assets: Decodable {
            var macOSZip: Asset?
            var macOSDMG: Asset?

            private enum CodingKeys: String, CodingKey {
                case macOSZip = "macos_zip"
                case macOSDMG = "macos_dmg"
            }
        }

        struct Asset: Decodable {
            var url: URL
            var sha256: String?
            var size: Int64?
        }

        private enum CodingKeys: String, CodingKey {
            case version
            case pubDate = "pub_date"
            case releaseURL = "release_url"
            case notesURL = "notes_url"
            case assets
        }
    }

    private struct GitHubReleaseResponse: Decodable {
        var body: String?
    }

    private let session: URLSession
    private let latestMetadataURLs: [URL]
    private let fileManager: FileManager

    init(
        session: URLSession = .shared,
        latestMetadataURLs: [URL] = defaultMetadataURLs,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.latestMetadataURLs = latestMetadataURLs
        self.fileManager = fileManager
    }

    func fetchLatestRelease() async throws -> AppUpdateInfo {
        var lastFallbackError: Error?
        let candidates = latestMetadataURLs.isEmpty ? Self.defaultMetadataURLs : latestMetadataURLs

        for (index, metadataURL) in candidates.enumerated() {
            do {
                return try await fetchLatestRelease(from: metadataURL)
            } catch {
                let isLastCandidate = index == candidates.count - 1
                guard !isLastCandidate, Self.shouldTryNextMetadataURL(after: error) else {
                    throw error
                }
                lastFallbackError = error
            }
        }

        throw lastFallbackError ?? URLError(.badURL)
    }

    private func fetchLatestRelease(from metadataURL: URL) async throws -> AppUpdateInfo {
        var request = URLRequest(url: metadataURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ReleaseManifest.self, from: data)
        let normalizedVersion = Self.normalizeVersion(manifest.version)
        guard !normalizedVersion.isEmpty else {
            throw AppUpdateError.invalidMetadata
        }

        return AppUpdateInfo(
            latestVersion: normalizedVersion,
            releaseURL: manifest.releaseURL ?? Self.releasesURL,
            notesURL: manifest.notesURL,
            publishedAt: manifest.pubDate,
            zipAsset: manifest.assets.macOSZip.map { AppUpdateAsset(url: $0.url, sha256: $0.sha256, size: $0.size) },
            dmgAsset: manifest.assets.macOSDMG.map { AppUpdateAsset(url: $0.url, sha256: $0.sha256, size: $0.size) }
        )
    }

    private static func shouldTryNextMetadataURL(after error: Error) -> Bool {
        error is URLError || (error as NSError).domain == NSURLErrorDomain
    }

    func fetchReleaseNotesBody(forVersion version: String) async throws -> String {
        let candidates = Self.releaseTagCandidates(forVersion: version)

        for tag in candidates {
            let endpoint = Self.apiBaseURL
                .appendingPathComponent("releases", isDirectory: true)
                .appendingPathComponent("tags", isDirectory: true)
                .appendingPathComponent(tag)

            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if http.statusCode == 404 {
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
            return release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        throw URLError(.fileDoesNotExist)
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        guard let asset = update.zipAsset else {
            throw AppUpdateError.missingZipAsset
        }
        // The manifest and the download share an origin, so the published hash
        // is the only anchor the update chain has. Without it a substituted
        // asset would install unchallenged, so a manifest that omits it is
        // rejected rather than trusted — before any bytes are fetched.
        guard let expectedHash = asset.sha256?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expectedHash.isEmpty else {
            throw AppUpdateError.missingChecksum
        }

        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OhMyUsageUpdate-\(UUID().uuidString)", isDirectory: true)
        let downloadURL = root.appendingPathComponent("OhMyUsageUpdate.zip")
        let extractRoot = root.appendingPathComponent("Extracted", isDirectory: true)

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)

        var request = URLRequest(url: asset.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 300
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

        let (temporaryFileURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if fileManager.fileExists(atPath: downloadURL.path) {
            try fileManager.removeItem(at: downloadURL)
        }
        try fileManager.moveItem(at: temporaryFileURL, to: downloadURL)

        let actualHash = try Self.sha256Hex(for: downloadURL)
        if actualHash.caseInsensitiveCompare(expectedHash) != .orderedSame {
            throw AppUpdateError.checksumMismatch
        }

        try Self.runProcess(
            executablePath: "/usr/bin/ditto",
            arguments: ["-x", "-k", downloadURL.path, extractRoot.path]
        )

        guard let appBundleURL = Self.findAppBundle(in: extractRoot, fileManager: fileManager) else {
            throw AppUpdateError.extractedAppNotFound
        }

        try Self.verifyAppBundleSignature(at: appBundleURL)

        return PreparedAppUpdate(
            version: update.latestVersion,
            appBundleURL: appBundleURL,
            workingDirectoryURL: root
        )
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL = Bundle.main.bundleURL) throws {
        let standardizedCurrentAppURL = currentAppURL.standardizedFileURL
        guard standardizedCurrentAppURL.pathExtension == "app" else {
            throw AppUpdateError.unsupportedInstallLocation
        }

        let installerScriptURL = prepared.workingDirectoryURL.appendingPathComponent("install_update.sh")
        let sourceAppURL = prepared.appBundleURL.standardizedFileURL
        let targetAppURL = standardizedCurrentAppURL
        let backupAppURL = prepared.workingDirectoryURL
            .appendingPathComponent("\(targetAppURL.deletingPathExtension().lastPathComponent) Backup.app")
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = Self.installScript(
            sourceAppPath: sourceAppURL.path,
            targetAppPath: targetAppURL.path,
            backupAppPath: backupAppURL.path,
            workingDirectoryPath: prepared.workingDirectoryURL.path,
            pid: pid
        )
        try script.write(to: installerScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installerScriptURL.path)

        // Detach before `run`. `terminate` signals the app process group, so an
        // installer that stays in that group dies with the app and the UI stays
        // on "installing and restarting" until a later force-quit.
        try Self.launchDetachedInstaller(scriptURL: installerScriptURL)
    }

    /// Starts `install_update.sh` in its own session. The python process exits
    /// immediately; the installer keeps running after it and is not killed when
    /// the app process group receives SIGTERM.
    static func launchDetachedInstaller(scriptURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", detachedInstallerLauncher, scriptURL.path]
        try process.run()
        // The launcher exits right after forking. A non-zero exit means the
        // detached installer never started, and reporting success then would
        // quit the app into an update that never happens.
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.installerLaunchFailed
        }
    }

    static let detachedInstallerLauncher = """
    import os, sys
    script = sys.argv[1]
    if os.fork() > 0:
        raise SystemExit(0)
    os.setsid()
    devnull = os.open(os.devnull, os.O_RDWR)
    os.dup2(devnull, 0)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
    os.execv("/bin/sh", ["/bin/sh", script])
    """

    static func normalizeVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    static func releasePageURL(forVersion version: String) -> URL {
        let tag = releaseTagCandidates(forVersion: version).first ?? version
        return repositoryURL
            .appendingPathComponent("releases", isDirectory: true)
            .appendingPathComponent("tag", isDirectory: true)
            .appendingPathComponent(tag)
    }

    static func releaseTagCandidates(forVersion version: String) -> [String] {
        let normalized = normalizeVersion(version)
        guard !normalized.isEmpty else { return [] }

        let tags: [String] = ["v\(normalized)", normalized]
        var deduped: [String] = []
        var seen = Set<String>()
        for tag in tags {
            if seen.insert(tag).inserted {
                deduped.append(tag)
            }
        }
        return deduped
    }

    private static func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A matching checksum says the archive is what the manifest listed, but
    /// the manifest itself has no independent signature. The extracted bundle
    /// must still carry a structurally valid code signature, and when the
    /// running app is identity signed the update must come from the same team.
    static func verifyAppBundleSignature(at appBundleURL: URL) throws {
        try runProcess(
            executablePath: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appBundleURL.path]
        )

        guard let runningTeam = teamIdentifier(forAppBundleAt: Bundle.main.bundleURL) else {
            return
        }
        guard teamIdentifier(forAppBundleAt: appBundleURL) == runningTeam else {
            throw AppUpdateError.signatureVerificationFailed("signed by a different team than the installed app")
        }
    }

    /// Ad-hoc builds report no team; `nil` means "no identity to pin".
    private static func teamIdentifier(forAppBundleAt url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", url.path]
        let details = Pipe()
        process.standardError = details
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: details.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("TeamIdentifier=") else { continue }
            let value = trimmed.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
            return (value.isEmpty || value == "not set") ? nil : value
        }
        return nil
    }

    private static func findAppBundle(in root: URL, fileManager: FileManager) -> URL? {
        if root.pathExtension == "app" {
            return root
        }

        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let item = enumerator?.nextObject() as? URL {
            if item.pathExtension == "app" {
                return item
            }
        }
        return nil
    }

    private static func runProcess(executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "AppUpdateService.Process",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "Update helper process failed"]
            )
        }
    }

    private static func installScript(
        sourceAppPath: String,
        targetAppPath: String,
        backupAppPath: String,
        workingDirectoryPath: String,
        pid: Int32
    ) -> String {
        let source = shellSingleQuoted(sourceAppPath)
        let target = shellSingleQuoted(targetAppPath)
        let backup = shellSingleQuoted(backupAppPath)
        let workingDir = shellSingleQuoted(workingDirectoryPath)

        return """
        #!/bin/sh
        set -eu

        SOURCE_APP=\(source)
        TARGET_APP=\(target)
        BACKUP_APP=\(backup)
        WORKING_DIR=\(workingDir)
        TARGET_DIR="$(dirname "$TARGET_APP")"
        STAGING_APP="$TARGET_DIR/.oh-myusage.update.app"
        PID_TO_WAIT=\(pid)

        wait_for_exit() {
          waited=0
          while kill -0 "$PID_TO_WAIT" 2>/dev/null; do
            sleep 1
            waited=$((waited + 1))
            # A stuck terminate reply must not pin the UI forever. After the
            # grace period, ask the old process to exit so replacement can start.
            if [ "$waited" -eq 8 ]; then
              kill -TERM "$PID_TO_WAIT" 2>/dev/null || true
            fi
            if [ "$waited" -ge 20 ]; then
              kill -KILL "$PID_TO_WAIT" 2>/dev/null || true
              break
            fi
          done
          sleep 1
        }

        install_without_privileges() {
          rm -rf "$STAGING_APP" "$BACKUP_APP"
          /usr/bin/ditto "$SOURCE_APP" "$STAGING_APP"
          /usr/bin/xattr -dr com.apple.quarantine "$STAGING_APP" >/dev/null 2>&1 || true
          if [ -e "$TARGET_APP" ]; then
            mv "$TARGET_APP" "$BACKUP_APP"
          fi
          mv "$STAGING_APP" "$TARGET_APP"
        }

        install_with_privileges() {
          /usr/bin/osascript <<APPLESCRIPT
        do shell script "rm -rf " & quoted form of "$STAGING_APP" & " " & quoted form of "$BACKUP_APP" & "; " & ¬
          "/usr/bin/ditto " & quoted form of "$SOURCE_APP" & " " & quoted form of "$STAGING_APP" & "; " & ¬
          "/usr/bin/xattr -dr com.apple.quarantine " & quoted form of "$STAGING_APP" & " >/dev/null 2>&1 || true; " & ¬
          "if [ -e " & quoted form of "$TARGET_APP" & " ]; then mv " & quoted form of "$TARGET_APP" & " " & quoted form of "$BACKUP_APP" & "; fi; " & ¬
          "mv " & quoted form of "$STAGING_APP" & " " & quoted form of "$TARGET_APP" with administrator privileges
        APPLESCRIPT
        }

        wait_for_exit

        if [ -w "$TARGET_DIR" ] && { [ ! -e "$TARGET_APP" ] || [ -w "$TARGET_APP" ]; }; then
          install_without_privileges
        else
          install_with_privileges
        fi

        /usr/bin/open "$TARGET_APP"
        rm -rf "$BACKUP_APP"
        rm -rf "$WORKING_DIR"
        exit 0
        """
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}

extension AppUpdateService: AppUpdateServicing {}
