import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

final class AntigravityProvider: UsageProvider, @unchecked Sendable {
    private static let cache = SnapshotTimestampOfficialSnapshotCache()
    private static let gate = PassthroughOfficialFetchGate()

    private let cacheTTL: TimeInterval
    private let cache: any OfficialSnapshotCaching
    private let gate: any OfficialFetchGating
    private let homeDirectory: () -> String
    private let environment: () -> [String: String]
    private let shell: any ShellCommandRunning

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        cache: any OfficialSnapshotCaching = AntigravityProvider.cache,
        gate: any OfficialFetchGating = AntigravityProvider.gate,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        shell: any ShellCommandRunning = DefaultShellCommandRunner(),
        cacheTTL: TimeInterval = 30
    ) {
        self.descriptor = descriptor
        self.cache = cache
        self.gate = gate
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.shell = shell
        self.cacheTTL = cacheTTL
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await OfficialProviderFetchRuntime.fetch(
            forceRefresh: forceRefresh,
            cacheLookupKey: "\(descriptor.id)|\(effectiveSourceModeKey())",
            ttl: cacheTTL,
            cache: cache,
            gate: gate,
            load: { [self] in try await loadSnapshot(forceRefresh: forceRefresh) }
        )
    }

    private func effectiveSourceModeKey() -> String {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .antigravity)
        return official.sourceMode.rawValue
    }

    private func loadSnapshot(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .antigravity)
        switch official.sourceMode {
        case .cli, .auto:
            return try await loadFromCLI(forceRefresh: forceRefresh)
        case .api, .web:
            throw ProviderError.unavailable(Localizer.systemText(.antigravitySourceUnsupported))
        }
    }

    private func loadFromCLI(forceRefresh: Bool) async throws -> UsageSnapshot {
        let env = environment()
        let home = homeDirectory()
        guard let executablePath = AgyCLIUsageService.resolveExecutablePath(
            environment: env,
            homeDirectory: home,
            shell: shell
        ) else {
            throw ProviderError.missingCredential(
                Localizer.systemText(.antigravityCLINotFound)
            )
        }

        let report: AgyCLIUsageReport
        if cacheTTL > 0 {
            report = try await AgyCLIUsageCoordinator.shared.fetchReport(
                executablePath: executablePath,
                forceRefresh: forceRefresh,
                environment: env,
                homeDirectory: home,
                shell: shell
            )
        } else {
            report = try AgyCLIUsageService.executeUsageCommand(
                executablePath: executablePath,
                environment: env,
                homeDirectory: home,
                shell: shell
            )
        }

        return Self.makeSnapshot(from: report, descriptor: descriptor)
    }

    internal static func parseCLIUsageOutput(
        stdout: String,
        stderr: String = "",
        descriptor: ProviderDescriptor
    ) throws -> UsageSnapshot {
        let report = try AgyCLIUsageService.parseUsageOutput(
            stdout: stdout,
            stderr: stderr,
            executableSource: "CLI",
            fallbackAccountLabel: nil
        )
        return makeSnapshot(from: report, descriptor: descriptor)
    }

    internal static func makeSnapshot(
        from report: AgyCLIUsageReport,
        descriptor: ProviderDescriptor
    ) -> UsageSnapshot {
        let distinctFamilies = Set(report.buckets.map(\.family))
        let multiFamily = distinctFamilies.count > 1

        let windows: [UsageQuotaWindow] = report.buckets.map { bucket in
            let title: String
            let kind: UsageQuotaKind

            if !multiFamily && bucket.family == .gemini {
                switch bucket.cadence {
                case .fiveHour:
                    title = "5h"
                    kind = .session
                case .weekly:
                    title = "Weekly"
                    kind = .weekly
                case .other:
                    title = bucket.bucketName.isEmpty ? "Gemini" : bucket.bucketName
                    kind = .custom
                }
            } else {
                let familyLabel: String
                switch bucket.family {
                case .gemini:
                    familyLabel = "Gemini"
                case .claudeGPT:
                    familyLabel = "Claude/GPT"
                case .other:
                    familyLabel = bucket.groupName
                }

                let cadenceLabel: String
                switch bucket.cadence {
                case .fiveHour:
                    cadenceLabel = "5h"
                case .weekly:
                    cadenceLabel = "Weekly"
                case .other:
                    cadenceLabel = bucket.bucketName
                }

                title = cadenceLabel.isEmpty ? familyLabel : "\(familyLabel) \(cadenceLabel)"
                kind = .custom
            }

            return UsageQuotaWindow(
                id: "\(descriptor.id)-\(bucket.id)",
                title: title,
                remainingPercent: bucket.remainingPercent,
                usedPercent: bucket.usedPercent,
                resetAt: bucket.resetAt,
                kind: kind
            )
        }

        let geminiBuckets = report.buckets.filter { $0.family == .gemini }
        let primaryRemainingSource = geminiBuckets.isEmpty ? report.buckets : geminiBuckets
        let remaining = primaryRemainingSource.map(\.remainingPercent).min() ?? 0

        var extras: [String: String] = [:]
        if let plan = report.planType, !plan.isEmpty {
            extras["planType"] = plan
        }

        let noteParts = windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: max(0, 100 - remaining),
            limit: 100,
            unit: "%",
            updatedAt: report.fetchedAt,
            note: noteParts.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: report.executableSource,
            accountLabel: report.accountLabel,
            extras: extras,
            rawMeta: ["antigravity.source": report.outputFormat]
        )
    }
}
