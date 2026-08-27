import Foundation
import OhMyUsageDomain

struct AppCredentialMutationOutcome: Equatable {
    var didPersistCredential: Bool = false
    var shouldBumpLookupVersion: Bool = false

    static let none = AppCredentialMutationOutcome()
}

/// 凭证字段标识：唯一决定一次凭证写入的 keychain 目标与规范化方式。
/// keychain service/account 的推导逻辑从各旧调用点逐位抄来，行为不变。
enum AppCredentialField: Equatable {
    /// 官方/relay 额度 token → descriptor.auth 派生的 keychain 槽位
    case providerToken(ProviderDescriptor)
    /// relay 余额凭证 → 独立 AuthConfig 派生的 keychain 槽位
    case authToken(AuthConfig)
    /// 官方手动 Cookie → officialConfig.manualCookieAccount，固定 defaultServiceName
    case officialManualCookie(providerID: String)
}

/// 凭证保存成功后的轮询行为，从旧 wrapper（saveToken / saveTokenAndRestart 等）逐位抄来。
enum AppCredentialRestartPolicy: Equatable {
    case none
    case restartPolling
}

struct AppProviderCredentialCoordinator {
    /// 单一保存入口。所有旧写入 API 均为转发到这里的 wrapper。
    func saveCredential(
        field: AppCredentialField,
        value: String,
        providers: [ProviderDescriptor],
        normalize: (String, AuthKind) -> String,
        saveCredential: (String, String, String) -> Bool
    ) -> AppCredentialMutationOutcome {
        switch field {
        case .providerToken(let descriptor):
            return persistNormalized(
                value,
                kind: descriptor.auth.kind,
                service: descriptor.auth.keychainService,
                account: descriptor.auth.keychainAccount,
                normalize: normalize,
                saveCredential: saveCredential
            )
        case .authToken(let auth):
            return persistNormalized(
                value,
                kind: auth.kind,
                service: auth.keychainService,
                account: auth.keychainAccount,
                normalize: normalize,
                saveCredential: saveCredential
            )
        case .officialManualCookie(let providerID):
            guard let provider = providers.first(where: { $0.id == providerID }),
                  provider.family == .official,
                  let account = provider.officialConfig?.manualCookieAccount else {
                return .none
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .none }
            let ok = saveCredential(trimmed, KeychainService.defaultServiceName, account)
            return AppCredentialMutationOutcome(
                didPersistCredential: ok,
                shouldBumpLookupVersion: ok
            )
        }
    }

    func invalidateLookupCache(_ invalidate: () -> Void) -> AppCredentialMutationOutcome {
        invalidate()
        return AppCredentialMutationOutcome(
            didPersistCredential: false,
            shouldBumpLookupVersion: true
        )
    }

    // MARK: - Private

    private func persistNormalized(
        _ value: String,
        kind: AuthKind,
        service: String?,
        account: String?,
        normalize: (String, AuthKind) -> String,
        saveCredential: (String, String, String) -> Bool
    ) -> AppCredentialMutationOutcome {
        guard let service, let account else { return .none }

        let normalized = normalize(value, kind)
        guard !normalized.isEmpty else { return .none }
        let ok = saveCredential(normalized, service, account)
        return AppCredentialMutationOutcome(
            didPersistCredential: ok,
            shouldBumpLookupVersion: ok
        )
    }
}
