import AppKit
import Foundation

@MainActor
final class AppUpdateCoordinator {
    typealias UpdateStateGetter = @MainActor () -> UpdateStore
    typealias UpdateStateSetter = @MainActor (UpdateStore) -> Void

    private let appUpdateService: any AppUpdateServicing
    private let postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring
    private let updateInstallBufferDelaySeconds: TimeInterval
    private let updateCheckStatusClearDelaySeconds: TimeInterval
    private let currentAppURLProvider: @MainActor () -> URL
    private let terminateApplication: @MainActor () -> Void
    private var updateInstallBufferTask: Task<Void, Never>?
    private var updateCheckStatusClearTask: Task<Void, Never>?

    init(
        appUpdateService: any AppUpdateServicing,
        postUpdateReleaseNotesStore: any PostUpdateReleaseNotesStoring,
        updateInstallBufferDelaySeconds: TimeInterval,
        updateCheckStatusClearDelaySeconds: TimeInterval,
        currentAppURLProvider: @escaping @MainActor () -> URL = { Bundle.main.bundleURL },
        terminateApplication: @escaping @MainActor () -> Void = {
            NSApplication.shared.terminate(nil)
        }
    ) {
        self.appUpdateService = appUpdateService
        self.postUpdateReleaseNotesStore = postUpdateReleaseNotesStore
        self.updateInstallBufferDelaySeconds = updateInstallBufferDelaySeconds
        self.updateCheckStatusClearDelaySeconds = updateCheckStatusClearDelaySeconds
        self.currentAppURLProvider = currentAppURLProvider
        self.terminateApplication = terminateApplication
    }

    func checkForAppUpdate(
        force: Bool,
        effectiveInstalledVersion: String,
        getState: @escaping UpdateStateGetter,
        setState: @escaping UpdateStateSetter
    ) {
        let state = getState()
        if state.updateCheckInFlight { return }
        if !force,
           let last = state.lastUpdateCheckAt,
           Date().timeIntervalSince(last) < 6 * 60 * 60 {
            return
        }

        cancelUpdateCheckStatusClear()
        mutateState(getState, setState) { state in
            state.updateCheckInFlight = true
            state.updateCheckErrorMessage = nil
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.mutateState(getState, setState) { state in
                    state.updateCheckInFlight = false
                    state.lastUpdateCheckAt = Date()
                }
            }

            do {
                let latest = try await appUpdateService.fetchLatestRelease()
                var state = getState()
                state.lastCheckedLatestVersion = latest.latestVersion
                state.updateCheckErrorMessage = nil

                if AppVersionResolver.isVersion(latest.latestVersion, newerThan: effectiveInstalledVersion) {
                    state.availableUpdate = latest
                    state.lastCheckedLatestVersion = nil
                    if state.updatePreparedVersion != latest.latestVersion {
                        clearPreparedUpdateState(state: &state)
                    }
                    setState(state)
                } else {
                    state.availableUpdate = nil
                    clearPreparedUpdateState(state: &state)
                    setState(state)
                    scheduleUpdateCheckStatusClear(getState: getState, setState: setState)
                }
            } catch {
                mutateState(getState, setState) { state in
                    state.updateCheckErrorMessage = error.localizedDescription
                    state.lastCheckedLatestVersion = nil
                }
                scheduleUpdateCheckStatusClear(getState: getState, setState: setState)
            }
        }
    }

    func performUpdateAction(
        allowCheckForUpdateFallback: Bool,
        getState: @escaping UpdateStateGetter,
        setState: @escaping UpdateStateSetter,
        checkForUpdateAction: @escaping @MainActor () -> Void
    ) {
        let state = getState()
        if state.updateDownloadInFlight || state.updateInstallBufferingInFlight || state.updateInstallationInFlight {
            return
        }

        if let preparedUpdate = state.preparedUpdate {
            beginUpdateInstallBuffering(
                for: preparedUpdate,
                getState: getState,
                setState: setState
            )
            return
        }

        if let availableUpdate = state.availableUpdate {
            beginUpdatePreparation(
                with: availableUpdate,
                getState: getState,
                setState: setState
            )
            return
        }

        guard allowCheckForUpdateFallback else { return }
        checkForUpdateAction()
    }

    func settingsDisplayState(
        for state: UpdateStore,
        localizedText: (String, String) -> String
    ) -> SettingsUpdateDisplayState {
        let canRetryUpdateAction = canRetryUpdateAction(for: state)
        if state.updateInstallErrorMessage != nil {
            return SettingsUpdateDisplayState(
                kind: .failed,
                statusText: localizedText("安装失败", "Install Failed"),
                tone: .negative,
                retryTitle: canRetryUpdateAction ? localizedText("重试", "Retry") : nil,
                isRetryEnabled: canRetryUpdateAction
            )
        }
        if state.updateCheckErrorMessage != nil {
            return SettingsUpdateDisplayState(
                kind: .checkFailed,
                statusText: localizedText("检查失败", "Check Failed"),
                tone: .negative,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if state.updateInstallBufferingInFlight || state.updateInstallationInFlight {
            return SettingsUpdateDisplayState(
                kind: .installBuffering,
                statusText: localizedText("即将安装重启...", "Installing and restarting..."),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if state.updateDownloadInFlight {
            return SettingsUpdateDisplayState(
                kind: .downloading,
                statusText: localizedText("正在下载...", "Downloading..."),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if let update = state.availableUpdate {
            return SettingsUpdateDisplayState(
                kind: .updateAvailable(version: update.latestVersion),
                statusText: localizedText("新版本 \(update.latestVersion)", "New \(update.latestVersion)"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: isActionEnabled(for: state)
            )
        }
        if state.lastCheckedLatestVersion != nil {
            return SettingsUpdateDisplayState(
                kind: .upToDate,
                statusText: localizedText("已经是最新版本", "Up to Date"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        return SettingsUpdateDisplayState(
            kind: .idle,
            statusText: nil,
            tone: .neutral,
            retryTitle: nil,
            isRetryEnabled: false
        )
    }

    func menuDisplayState(
        for state: UpdateStore,
        localizedText: (String, String) -> String
    ) -> MenuUpdateDisplayState {
        let canRetryUpdateAction = canRetryUpdateAction(for: state)
        if state.updateInstallErrorMessage != nil {
            return MenuUpdateDisplayState(
                kind: .failed,
                statusText: localizedText("安装失败", "Install Failed"),
                tone: .negative,
                retryTitle: canRetryUpdateAction ? localizedText("重试", "Retry") : nil,
                isRetryEnabled: canRetryUpdateAction
            )
        }
        if state.updateInstallBufferingInFlight || state.updateInstallationInFlight {
            return MenuUpdateDisplayState(
                kind: .installBuffering,
                statusText: localizedText("即将安装重启...", "Installing and restarting..."),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if state.updateDownloadInFlight {
            return MenuUpdateDisplayState(
                kind: .downloading,
                statusText: localizedText("正在下载...", "Downloading..."),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: false
            )
        }
        if let update = state.availableUpdate {
            return MenuUpdateDisplayState(
                kind: .updateAvailable(version: update.latestVersion),
                statusText: localizedText("新版本 \(update.latestVersion)", "New \(update.latestVersion)"),
                tone: .positive,
                retryTitle: nil,
                isRetryEnabled: isActionEnabled(for: state)
            )
        }
        return MenuUpdateDisplayState(
            kind: .idle,
            statusText: nil,
            tone: .neutral,
            retryTitle: nil,
            isRetryEnabled: false
        )
    }

    func updateActionTitle(
        for state: UpdateStore,
        localizedText: (String, String) -> String
    ) -> String {
        if state.updateInstallBufferingInFlight || state.updateInstallationInFlight {
            return localizedText("即将安装重启...", "Installing and restarting...")
        }
        if state.updateDownloadInFlight {
            return localizedText("正在下载...", "Downloading...")
        }
        if state.updatePreparedVersion != nil || state.availableUpdate != nil {
            return localizedText("更新版本", "Update App")
        }
        return localizedText("检查更新", "Check for Updates")
    }

    func updateStatusSummary(
        for state: UpdateStore,
        localizedText: (String, String) -> String
    ) -> String? {
        if let message = state.updateInstallErrorMessage, !message.isEmpty {
            return "\(localizedText("更新失败", "Update failed")): \(message)"
        }
        if state.updateDownloadInFlight {
            return localizedText("正在下载...", "Downloading...")
        }
        if state.updateInstallBufferingInFlight || state.updateInstallationInFlight {
            return localizedText("即将安装重启...", "Installing and restarting...")
        }
        if let version = state.updatePreparedVersion {
            return localizedText("新版本 \(version) 已准备完成。", "Version \(version) is ready.")
        }
        if let update = state.availableUpdate {
            return localizedText(
                "发现新版本 \(update.latestVersion)，点击“更新版本”开始更新。",
                "Version \(update.latestVersion) is available. Click Update App to continue."
            )
        }
        if let latest = state.lastCheckedLatestVersion {
            return localizedText("当前已是最新版本（最新 \(latest)）。", "You're up to date (latest \(latest)).")
        }
        return nil
    }

    func isActionEnabled(for state: UpdateStore) -> Bool {
        !(state.updateDownloadInFlight || state.updateInstallBufferingInFlight || state.updateInstallationInFlight)
    }

    private func canRetryUpdateAction(for state: UpdateStore) -> Bool {
        isActionEnabled(for: state) && (state.availableUpdate != nil || state.preparedUpdate != nil)
    }

    private func clearPreparedUpdateState(state: inout UpdateStore) {
        state.preparedUpdate = nil
        state.preparedUpdateInfo = nil
        state.updatePreparedVersion = nil
        state.updateFlowVersionInFlight = nil
        state.updateInstallBufferingInFlight = false
        cancelUpdateInstallBuffering()
    }

    private func cancelUpdateInstallBuffering() {
        updateInstallBufferTask?.cancel()
        updateInstallBufferTask = nil
    }

    private func cancelUpdateCheckStatusClear() {
        updateCheckStatusClearTask?.cancel()
        updateCheckStatusClearTask = nil
    }

    private func scheduleUpdateCheckStatusClear(
        getState: @escaping UpdateStateGetter,
        setState: @escaping UpdateStateSetter
    ) {
        cancelUpdateCheckStatusClear()
        let delaySeconds = max(0, updateCheckStatusClearDelaySeconds)
        updateCheckStatusClearTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.mutateState(getState, setState) { state in
                state.updateCheckErrorMessage = nil
                state.lastCheckedLatestVersion = nil
            }
            self.updateCheckStatusClearTask = nil
        }
    }

    private func beginUpdateInstallBuffering(
        for prepared: PreparedAppUpdate,
        getState: @escaping UpdateStateGetter,
        setState: @escaping UpdateStateSetter
    ) {
        let state = getState()
        guard !state.updateDownloadInFlight, !state.updateInstallationInFlight else { return }

        cancelUpdateInstallBuffering()
        mutateState(getState, setState) { state in
            state.updateInstallErrorMessage = nil
            state.updateInstallBufferingInFlight = true
        }

        let expectedVersion = prepared.version
        updateInstallBufferTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(updateInstallBufferDelaySeconds * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.startPreparedUpdateInstallationIfNeeded(
                expectedVersion: expectedVersion,
                getState: getState,
                setState: setState
            )
        }
    }

    private func startPreparedUpdateInstallationIfNeeded(
        expectedVersion: String,
        getState: @escaping UpdateStateGetter,
        setState: @escaping UpdateStateSetter
    ) {
        updateInstallBufferTask = nil
        let state = getState()
        guard state.updateInstallBufferingInFlight,
              !state.updateDownloadInFlight,
              !state.updateInstallationInFlight,
              let preparedUpdate = state.preparedUpdate,
              preparedUpdate.version == expectedVersion else {
            mutateState(getState, setState) { state in
                state.updateInstallBufferingInFlight = false
            }
            return
        }

        mutateState(getState, setState) { state in
            state.updateInstallBufferingInFlight = false
            state.updateInstallErrorMessage = nil
            state.updateInstallationInFlight = true
        }
        if let preparedUpdateInfo = state.preparedUpdateInfo,
           preparedUpdateInfo.latestVersion == preparedUpdate.version {
            postUpdateReleaseNotesStore.schedulePresentation(for: preparedUpdateInfo)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await appUpdateService.installPreparedUpdate(
                    preparedUpdate,
                    over: currentAppURLProvider()
                )
                terminateApplication()
            } catch {
                self.mutateState(getState, setState) { state in
                    state.updateInstallationInFlight = false
                    state.updateInstallErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func beginUpdatePreparation(
        with update: AppUpdateInfo,
        getState: @escaping UpdateStateGetter,
        setState: @escaping UpdateStateSetter
    ) {
        let state = getState()
        if state.updateDownloadInFlight || state.updateInstallBufferingInFlight || state.updateInstallationInFlight {
            return
        }
        if state.updatePreparedVersion == update.latestVersion {
            if let preparedUpdate = state.preparedUpdate, preparedUpdate.version == update.latestVersion {
                beginUpdateInstallBuffering(
                    for: preparedUpdate,
                    getState: getState,
                    setState: setState
                )
            }
            return
        }
        if state.updateFlowVersionInFlight == update.latestVersion {
            return
        }

        cancelUpdateInstallBuffering()
        mutateState(getState, setState) { state in
            state.updateFlowVersionInFlight = update.latestVersion
            state.updateDownloadInFlight = true
            state.updateInstallErrorMessage = nil
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let prepared = try await appUpdateService.prepareUpdate(update)
                self.mutateState(getState, setState) { state in
                    state.preparedUpdate = prepared
                    state.preparedUpdateInfo = update
                    state.updatePreparedVersion = prepared.version
                    state.updateDownloadInFlight = false
                    state.updateFlowVersionInFlight = nil
                }
                self.beginUpdateInstallBuffering(
                    for: prepared,
                    getState: getState,
                    setState: setState
                )
            } catch {
                self.mutateState(getState, setState) { state in
                    state.updateDownloadInFlight = false
                    state.updateFlowVersionInFlight = nil
                    state.updateInstallErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func mutateState(
        _ getState: UpdateStateGetter,
        _ setState: UpdateStateSetter,
        _ mutate: (inout UpdateStore) -> Void
    ) {
        var state = getState()
        mutate(&state)
        setState(state)
    }
}
