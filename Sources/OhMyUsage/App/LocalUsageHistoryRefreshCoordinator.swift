import OhMyUsageApplication
import OhMyUsageDomain
import Foundation

private enum LocalUsageHistoryRefreshCoordinatorError: LocalizedError {
    case unsupportedProvider(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Unsupported local trend provider: \(provider)"
        }
    }
}

@MainActor
final class LocalUsageHistoryRefreshCoordinator {
    func refreshLocalUsageHistoryIfNeeded(
        query: LocalUsageHistoryQuery,
        repository: LocalUsageHistoryRepository,
        codexIdentity: CodexTrendIdentityContext? = nil,
        claudeCurrentConfigDir: String? = nil,
        claudeAllConfigDirs: [String] = [],
        force: Bool = false,
        performRefresh: ((
            LocalUsageHistoryQuery,
            LocalUsageHistoryRepository,
            Bool,
            @escaping LocalUsageHistoryRepository.FingerprintProvider,
            @escaping LocalUsageHistoryRepository.Loader,
            @escaping @MainActor () -> Void
        ) -> Void)? = nil,
        onStateChange: @escaping @MainActor () -> Void
    ) {
        guard Self.supports(query.providerType) else { return }

        let providerType = query.providerType
        let scope = query.scope
        let codexIdentityForRequest = codexIdentity
        let claudeCurrentConfigDirForRequest = claudeCurrentConfigDir
        let claudeAllConfigDirsForRequest = claudeAllConfigDirs

        let fingerprintProvider: LocalUsageHistoryRepository.FingerprintProvider = {
            switch providerType {
            case .codex:
                return LocalUsageSourceFingerprintBuilder.codexFingerprint(scope: scope)
            case .claude:
                return LocalUsageSourceFingerprintBuilder.claudeFingerprint(
                    scope: scope,
                    currentConfigDir: claudeCurrentConfigDirForRequest,
                    allConfigDirs: claudeAllConfigDirsForRequest
                )
            case .kimi:
                return LocalUsageSourceFingerprintBuilder.kimiFingerprint()
            default:
                return LocalUsageSourceFingerprint(
                    roots: [],
                    fileCount: 0,
                    totalSize: 0,
                    latestModificationTime: nil
                )
            }
        }

        let loader: LocalUsageHistoryRepository.Loader = { sourceFingerprint in
            switch providerType {
            case .codex:
                let codexScope: CodexTrendScope = scope == .currentAccount
                    ? .currentAccount
                    : .allAccounts
                let codexSummary = try CodexLocalUsageService().fetchSummary(
                    scope: codexScope,
                    currentIdentity: codexIdentityForRequest
                )
                return LocalUsageHistoryLoadResult(
                    summary: LocalUsageSummary(codex: codexSummary),
                    sourceFingerprint: sourceFingerprint
                )
            case .claude:
                let summary = try ClaudeLocalUsageService().fetchSummary(
                    scope: scope,
                    currentConfigDir: claudeCurrentConfigDirForRequest,
                    allConfigDirs: claudeAllConfigDirsForRequest
                )
                return LocalUsageHistoryLoadResult(
                    summary: summary,
                    sourceFingerprint: sourceFingerprint
                )
            case .kimi:
                let summary = try KimiLocalUsageService().fetchSummary(scope: .allAccounts)
                return LocalUsageHistoryLoadResult(
                    summary: summary,
                    sourceFingerprint: sourceFingerprint
                )
            default:
                throw LocalUsageHistoryRefreshCoordinatorError.unsupportedProvider(providerType.rawValue)
            }
        }

        if let performRefresh {
            performRefresh(query, repository, force, fingerprintProvider, loader, onStateChange)
        } else {
            repository.refreshIfNeeded(
                query: query,
                force: force,
                fingerprintProvider: fingerprintProvider,
                loader: loader,
                onStateChange: onStateChange
            )
        }
    }

    static func supports(_ providerType: ProviderType) -> Bool {
        supportedProviderTypes.contains(providerType)
    }

    private static let supportedProviderTypes: Set<ProviderType> = [.codex, .claude, .kimi]
}
