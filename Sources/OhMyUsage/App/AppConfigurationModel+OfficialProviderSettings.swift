// Official Provider 的设置事务：source/web 模式与展示偏好的更新、草稿保存，
// 以及“凭证 + 设置”一次性保存入口。

import OhMyUsageProviders
import Foundation
import OhMyUsageApplication
import OhMyUsageDomain

@MainActor
extension AppConfigurationModel {
    // MARK: - Official provider settings

    func updateOfficialProviderSettings(
        providerID: String,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) {
        let host = requireHost()
        let outcome = officialProviderSettingsCoordinator.updateOfficialProviderSettings(
            providerID: providerID,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode,
            providers: &host.config.providers
        )
        guard outcome != .none else { return }
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            host.notifyStatusBarDisplayConfigChanged()
        }
    }

    func saveOfficialDraft(_ draft: OfficialSettingsDraft) {
        updateOfficialProviderSettings(
            providerID: draft.providerID,
            sourceMode: draft.sourceMode,
            webMode: draft.webMode,
            quotaDisplayMode: draft.quotaDisplayMode,
            traeValueDisplayMode: draft.traeValueDisplayMode
        )
    }

    @discardableResult
    func saveOfficialCredentialAndSettings(
        providerID: String,
        credentialInput: String?,
        manualCookieInput: String?,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) -> Bool {
        let host = requireHost()
        var savedCredential = false
        if let provider = host.config.providers.first(where: { $0.id == providerID }),
           let credentialInput {
            savedCredential = saveCredential(credentialInput, field: .providerToken(provider), restartPolicy: .none) || savedCredential
        }
        if let manualCookieInput {
            savedCredential = saveCredential(manualCookieInput, field: .officialManualCookie(providerID: providerID), restartPolicy: .none) || savedCredential
        }
        updateOfficialProviderSettings(
            providerID: providerID,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode
        )
        return savedCredential
    }
}
