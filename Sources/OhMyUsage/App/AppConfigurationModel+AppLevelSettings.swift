// 应用级偏好设置事务：语言、资源模式、开机启动与全局刷新间隔的变更与持久化。

import OhMyUsageProviders
import Foundation
import OhMyUsageApplication
import OhMyUsageDomain

@MainActor
extension AppConfigurationModel {
    // MARK: - App-level config mutation

    func setLanguage(_ language: AppLanguage) {
        let host = requireHost()
        guard let outcome = configurationMutationCoordinator.setLanguage(
            language,
            config: &host.config,
            repository: host.configurationRepository,
            showFeedback: true,
            successText: host.localizedText("已保存", "Saved"),
            failureText: host.localizedText("保存失败", "Save Failed")
        ) else { return }
        applyConfigurationPersistenceOutcome(outcome)
    }

    func setResourceMode(_ resourceMode: ResourceMode) {
        let host = requireHost()
        guard let outcome = configurationMutationCoordinator.setResourceMode(
            resourceMode,
            config: &host.config,
            repository: host.configurationRepository,
            showFeedback: true,
            successText: host.localizedText("已保存", "Saved"),
            failureText: host.localizedText("保存失败", "Save Failed")
        ) else { return }
        if applyConfigurationPersistenceOutcome(outcome) {
            host.providerRefreshModel.remakeRefreshScheduler()
            host.restartPolling()
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        let host = requireHost()
        guard let outcome = configurationMutationCoordinator.setLaunchAtLoginEnabled(
            enabled,
            config: &host.config,
            setLaunchAtLogin: { try host.launchAtLoginService.setEnabled($0) },
            repository: host.configurationRepository,
            showFeedback: true,
            successText: host.localizedText("已保存", "Saved"),
            failureText: host.localizedText("保存失败", "Save Failed")
        ) else { return }
        if let persistence = outcome.persistence {
            _ = applyConfigurationPersistenceOutcome(persistence)
        }
        if let errorMessage = outcome.errorMessage {
            host.providerRefreshModel.mutateProviderState { state in
                state.errors["launch-at-login"] = errorMessage
            }
        }
    }

    func setGlobalRefreshIntervalSeconds(_ seconds: Int) {
        let host = requireHost()
        let supported = [15, 30, 60, 300]
        let normalized = supported.contains(seconds) ? seconds : 60
        guard host.config.providers.contains(where: { $0.pollIntervalSec != normalized }) else { return }

        for index in host.config.providers.indices {
            host.config.providers[index].pollIntervalSec = normalized
        }

        if persistConfiguration(showFeedback: true) {
            host.restartPolling()
        }
    }
}
