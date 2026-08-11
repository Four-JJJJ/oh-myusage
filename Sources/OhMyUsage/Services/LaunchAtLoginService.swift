import Foundation
import OhMyUsageProviders

enum LaunchAtLoginError: LocalizedError {
    case missingBundlePath
    case unableToWrite

    var errorDescription: String? {
        switch self {
        case .missingBundlePath:
            return "Unable to locate the current app bundle."
        case .unableToWrite:
            return "Unable to update the launch-at-login agent."
        }
    }
}

final class LaunchAtLoginService {
    private struct LaunchAgentDefinition {
        var label: String
        var filename: String
    }

    private static let currentLaunchAgent = LaunchAgentDefinition(
        label: "com.oh-myusage.app.launchatlogin",
        filename: "com.oh-myusage.app.launchatlogin.plist"
    )
    private static let legacyLaunchAgents = [
        LaunchAgentDefinition(
            label: "com.aiplanmonitor.app.launchatlogin",
            filename: "com.aiplanmonitor.app.launchatlogin.plist"
        ),
        LaunchAgentDefinition(
            label: "com.aibalancemonitor.app.launchatlogin",
            filename: "com.aibalancemonitor.app.launchatlogin.plist"
        )
    ]

    private let fileManager: FileManager
    private let homeDirectory: () -> String
    private let bundlePathProvider: () -> String
    private let commandRunner: (String, [String]) -> Void

    init(
        fileManager: FileManager = .default,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        bundlePathProvider: @escaping () -> String = { Bundle.main.bundlePath },
        commandRunner: @escaping (String, [String]) -> Void = { executable, arguments in
            _ = ShellCommand.run(executable: executable, arguments: arguments, timeout: 5)
        }
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.bundlePathProvider = bundlePathProvider
        self.commandRunner = commandRunner
    }

    func isEnabled() -> Bool {
        fileManager.fileExists(atPath: plistURL.path)
            || Self.legacyLaunchAgents.contains { fileManager.fileExists(atPath: plistURL(for: $0).path) }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try writeLaunchAgent()
            loadLaunchAgent()
            removeLegacyLaunchAgents()
        } else {
            unloadLaunchAgent()
            unloadLegacyLaunchAgents()
            removeLaunchAgent()
            removeLegacyLaunchAgents()
        }
    }

    func reset() {
        unloadLaunchAgent()
        unloadLegacyLaunchAgents()
        removeLaunchAgent()
        removeLegacyLaunchAgents()
    }

    func migrateLegacyLaunchAgentsIfNeeded() {
        guard Self.legacyLaunchAgents.contains(where: { fileManager.fileExists(atPath: plistURL(for: $0).path) }) else {
            return
        }

        if !fileManager.fileExists(atPath: plistURL.path) {
            do {
                try writeLaunchAgent()
                loadLaunchAgent()
            } catch {
                return
            }
        }

        unloadLegacyLaunchAgents()
        removeLegacyLaunchAgents()
    }

    private var plistURL: URL {
        plistURL(for: Self.currentLaunchAgent)
    }

    private func plistURL(for agent: LaunchAgentDefinition) -> URL {
        launchAgentsDirectoryURL.appendingPathComponent(agent.filename)
    }

    private var launchAgentsDirectoryURL: URL {
        URL(fileURLWithPath: homeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var launchAgentLabel: String {
        Self.currentLaunchAgent.label
    }

    private func writeLaunchAgent() throws {
        let bundlePath = bundlePathProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundlePath.isEmpty else {
            throw LaunchAtLoginError.missingBundlePath
        }

        let directory = plistURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LaunchAtLoginError.unableToWrite
        }

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", bundlePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": ["Aqua"]
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            throw LaunchAtLoginError.unableToWrite
        }
    }

    private func removeLaunchAgent() {
        try? fileManager.removeItem(at: plistURL)
    }

    private func removeLegacyLaunchAgents() {
        for agent in Self.legacyLaunchAgents {
            try? fileManager.removeItem(at: plistURL(for: agent))
        }
    }

    private func loadLaunchAgent() {
        let domain = "gui/\(getuid())"
        commandRunner("/bin/launchctl", ["bootout", domain, plistURL.path])
        commandRunner("/bin/launchctl", ["bootstrap", domain, plistURL.path])
    }

    private func unloadLaunchAgent() {
        let domain = "gui/\(getuid())"
        commandRunner("/bin/launchctl", ["bootout", domain, plistURL.path])
    }

    private func unloadLegacyLaunchAgents() {
        let domain = "gui/\(getuid())"
        for agent in Self.legacyLaunchAgents {
            commandRunner("/bin/launchctl", ["bootout", domain, plistURL(for: agent).path])
        }
    }
}
