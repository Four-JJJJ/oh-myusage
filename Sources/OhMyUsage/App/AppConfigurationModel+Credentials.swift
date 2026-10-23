// 凭证查询与写入事务：token/手动 Cookie 的存在性与长度查询、统一保存入口、
// 缓存失效与全量删除，以及凭证变更后的快照失效 helper。

import OhMyUsageProviders
import Foundation
import OhMyUsageApplication
import OhMyUsageDomain

@MainActor
extension AppConfigurationModel {
    // MARK: - Credential lookup

    func hasToken(for descriptor: ProviderDescriptor) -> Bool {
        let host = requireHost()
        return credentialLookupCoordinator.credentialExists(
            for: descriptor,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func savedTokenLength(for descriptor: ProviderDescriptor) -> Int? {
        let host = requireHost()
        return credentialLookupCoordinator.savedCredentialLength(
            for: descriptor,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func hasToken(auth: AuthConfig) -> Bool {
        let host = requireHost()
        return credentialLookupCoordinator.credentialExists(
            auth: auth,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func savedTokenLength(auth: AuthConfig) -> Int? {
        let host = requireHost()
        return credentialLookupCoordinator.savedCredentialLength(
            auth: auth,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func hasOfficialManualCookie(for provider: ProviderDescriptor) -> Bool {
        let host = requireHost()
        return credentialLookupCoordinator.manualCookieExists(
            for: provider,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func savedOfficialManualCookieLength(for provider: ProviderDescriptor) -> Int? {
        let host = requireHost()
        return credentialLookupCoordinator.savedManualCookieLength(
            for: provider,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    // MARK: - Credential mutation

    /// 单一保存入口：field 决定 keychain 目标与规范化，restartPolicy 决定成功后
    /// 是否重启轮询（行为与旧 saveToken/saveTokenAndRestart 系列逐位一致）。
    @discardableResult
    func saveCredential(
        _ value: String,
        field: AppCredentialField,
        restartPolicy: AppCredentialRestartPolicy = .none
    ) -> Bool {
        let host = requireHost()
        let outcome = providerCredentialCoordinator.saveCredential(
            field: field,
            value: value,
            providers: host.config.providers,
            normalize: { token, kind in
                self.normalizedCredential(token, kind: kind)
            },
            saveCredential: { value, service, account in
                host.credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        if outcome.didPersistCredential {
            invalidateProviderSnapshotsAfterCredentialChange(
                providerIDs: field.affectedProviderIDs(in: host.config.providers)
            )
        }
        if Self.shouldRestartPolling(didPersist: outcome.didPersistCredential, policy: restartPolicy) {
            host.restartPolling()
        }
        return outcome.didPersistCredential
    }

    /// restart 判定：仅当凭证真正写入成功且调用方要求 restart 时才重启轮询。
    static func shouldRestartPolling(
        didPersist: Bool,
        policy: AppCredentialRestartPolicy
    ) -> Bool {
        didPersist && policy == .restartPolling
    }

    func invalidateCredentialLookupCache() {
        let host = requireHost()
        applyCredentialMutationOutcome(
            providerCredentialCoordinator.invalidateLookupCache {
                host.credentialAccessService.invalidateLookupCache()
            }
        )
    }

    /// 单一凭证状态查询：把共享 broker 的 `CredentialAccessState` 映射进
    /// 权限/状态展示（doc 7.5 固定文案），非交互、不弹窗。
    func credentialAccessState(for descriptor: ProviderDescriptor) -> CredentialAccessState {
        let host = requireHost()
        return host.credentialAccessService.credentialAccessState(
            service: descriptor.auth.keychainService,
            account: descriptor.auth.keychainAccount
        )
    }

    /// 删除本机凭证：枚举配置内所有 vault 凭证槽位 + 底层存储已知条目，
    /// 逐条经共享 broker 的 `deleteToken` 实删 vault 数据，并刷新凭证状态。
    /// 不修改模型配置和其他本地数据（与“重置所有数据”的边界）。
    @discardableResult
    func deleteAllLocalCredentials() -> Bool {
        let host = requireHost()
        let allDeleted = host.credentialAccessService.deleteAllCredentials(
            extraServiceAccounts: Self.credentialTargets(in: host.config.providers)
        )
        applyCredentialMutationOutcome(
            AppCredentialMutationOutcome(didPersistCredential: false, shouldBumpLookupVersion: true)
        )
        host.refreshPermissionStatusesNow()
        return allDeleted
    }

    /// 当前配置内全部已知 vault 凭证槽位（auth 授权槽位、官方手动 Cookie、
    /// relay 余额凭证），去重后返回。仅含槽位标识，不含任何凭证内容。
    static func credentialTargets(
        in providers: [ProviderDescriptor]
    ) -> [(service: String, account: String)] {
        var seen = Set<String>()
        var targets: [(service: String, account: String)] = []
        func append(_ service: String?, _ account: String?) {
            guard let service, let account else { return }
            let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedService.isEmpty, !trimmedAccount.isEmpty else { return }
            let key = "\(trimmedService)::\(trimmedAccount)"
            guard seen.insert(key).inserted else { return }
            targets.append((trimmedService, trimmedAccount))
        }
        for provider in providers {
            append(provider.auth.keychainService, provider.auth.keychainAccount)
            if let account = provider.officialConfig?.manualCookieAccount {
                append(KeychainService.defaultServiceName, account)
            }
            if let balanceAuth = provider.relayConfig?.balanceAuth {
                append(balanceAuth.keychainService, balanceAuth.keychainAccount)
            }
        }
        return targets
    }

    // MARK: - Private orchestration

    private func applyCredentialMutationOutcome(_ outcome: AppCredentialMutationOutcome) {
        guard outcome != .none else { return }
        let host = requireHost()
        if outcome.shouldBumpLookupVersion {
            host.credentialLookupVersion &+= 1
        }
    }

    private func invalidateProviderSnapshotsAfterCredentialChange(providerIDs: Set<String>) {
        guard !providerIDs.isEmpty else { return }
        let host = requireHost()
        host.providerRefreshModel.mutateProviderState { state in
            for providerID in providerIDs {
                state.snapshots.removeValue(forKey: providerID)
                state.errors.removeValue(forKey: providerID)
                state.consecutiveFailures.removeValue(forKey: providerID)
                state.retryNotBefore.removeValue(forKey: providerID)
                state.activeAlerts.remove("low:\(providerID)")
                state.activeAlerts.remove("fail:\(providerID)")
                state.activeAlerts.remove("auth:\(providerID)")
            }
        }
        for providerID in providerIDs {
            host.providerRefreshModel.invalidateRefreshes(providerID: providerID)
            OfficialProviderFetchRuntime.invalidateCaches()
            host.persistedSnapshotCache?.remove(providerID: providerID)
        }
    }

    private func normalizedCredential(_ token: String, kind: AuthKind) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .bearer:
            return TraeProvider.normalizeToken(trimmed)
        case .none, .localCodex:
            return trimmed
        }
    }
}
