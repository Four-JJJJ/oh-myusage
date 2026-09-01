import SwiftUI

extension SettingsView {
    var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            permissionAccessSection
            dividerLine
            localDataManagementSection
        }
    }

    var permissionAccessSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                permissionStatusTile(
                    title: viewModel.text(.permissionNotificationsTitle),
                    hint: viewModel.text(.permissionNotificationsHint),
                    statusText: notificationPermissionStatusText,
                    statusColor: notificationPermissionStatusColor,
                    buttonTitle: notificationActionTitle,
                    buttonMutedStyle: viewModel.hasNotificationPermission
                ) {
                    handlePermissionAction(.notifications)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 154, alignment: .topLeading)

                permissionStatusTile(
                    title: viewModel.text(.permissionKeychainTitle),
                    hint: viewModel.text(.permissionKeychainHint),
                    statusText: keychainPermissionStatusText,
                    statusColor: keychainPermissionStatusColor,
                    buttonTitle: keychainActionTitle,
                    buttonMutedStyle: false,
                    buttonDestructive: viewModel.secureStorageReady
                ) {
                    handlePermissionAction(.keychain)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 154, alignment: .topLeading)

                permissionStatusTile(
                    title: viewModel.text(.permissionFullDiskTitle),
                    hint: viewModel.text(.permissionFullDiskHint),
                    statusText: fullDiskPermissionStatusText,
                    statusColor: fullDiskPermissionStatusColor,
                    buttonTitle: fullDiskActionTitle,
                    buttonMutedStyle: viewModel.fullDiskAccessGranted
                ) {
                    handlePermissionAction(.fullDisk)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 154, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .onPreferenceChange(PermissionTileHeightPreferenceKey.self) { newHeight in
                if abs(runtimeState.permissionTileHeight - newHeight) > 0.5 {
                    runtimeState.permissionTileHeight = newHeight
                }
            }
        }
    }

    var localDataManagementSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            localDiscoverySection
            dividerLine
            resetDataActionRow
        }
    }

    var localDiscoverySection: some View {
        VStack(alignment: .leading, spacing: localDiscoveryItemSpacing) {
            localDiscoveryHeaderRow

            if let autoDiscoveryResultText {
                localDiscoveryResultRow(autoDiscoveryResultText)
            }

            localDiscoveryPrivacyBanner
        }
    }

    var localDiscoveryHeaderRow: some View {
        HStack(alignment: .center, spacing: 98) {
            VStack(alignment: .leading, spacing: 8) {
                Text(localDiscoveryTitleText)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsTitleColor)
                    .lineSpacing(0)
                Text(viewModel.text(.localDiscoveryHint))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsGeneralOutlineButton(
                autoDiscoveryActionTitle,
                disabled: runtimeState.autoDiscoveryScanning,
                borderOpacity: 0.80
            ) {
                startAutoDiscoveryScan()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    func localDiscoveryResultRow(_ text: String) -> some View {
        Text(text)
            .font(settingsHintFont)
            .foregroundStyle(autoDiscoveryResultColor)
            .lineSpacing(0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var localDiscoveryPrivacyBanner: some View {
        Text(viewModel.text(.permissionsPrivacyPromise))
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(Color(hex: 0xD87E3E))
            .lineSpacing(settingsHintMultilineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .overlay(
                SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: 0xD87E3E), lineWidth: 0.5)
            )
    }

    var resetDataActionRow: some View {
        HStack(alignment: .center, spacing: 98) {
            VStack(alignment: .leading, spacing: 8) {
                Text(resetSectionTitle)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsTitleColor)
                    .lineSpacing(0)
                    .frame(height: 12, alignment: .leading)
                Text(viewModel.text(.resetLocalDataHint))
                    .font(settingsHintFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(settingsHintMultilineSpacing)
                    .frame(height: 30, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsGeneralOutlineButton(resetActionTitle, destructive: true, borderOpacity: 1) {
                dialogState.permissionPrompt = .resetLocalData
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
    }

    func permissionStatusTile(
        title: String,
        hint: String,
        statusText: String,
        statusColor: Color,
        buttonTitle: String,
        buttonMutedStyle: Bool = false,
        buttonDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(settingsLabelFont)
                    .foregroundStyle(settingsTitleColor)
                Text(hint)
                    .font(settingsBodyFont)
                    .foregroundStyle(settingsHintColor)
                    .lineSpacing(settingsBodyMultilineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(statusText)
                    .font(settingsLabelFont)
                    .foregroundStyle(statusColor)
                Spacer(minLength: 8)
                settingsGeneralOutlineButton(
                    buttonTitle,
                    destructive: buttonDestructive,
                    textOpacity: buttonMutedStyle ? 0.55 : 0.80,
                    borderOpacity: buttonMutedStyle ? 0.55 : 0.80,
                    action: action
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 154, maxHeight: 154, alignment: .topLeading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PermissionTileHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    var resetSectionTitle: String {
        viewModel.language == .zhHans ? "重置本地数据" : viewModel.text(.resetLocalDataTitle)
    }

    var resetActionTitle: String {
        viewModel.language == .zhHans ? "重置所有数据" : viewModel.text(.resetLocalDataAction)
    }

    func settingsGeneralOutlineButton(
        _ title: String,
        destructive: Bool = false,
        disabled: Bool = false,
        textOpacity: Double = 0.80,
        borderOpacity: Double = 0.80,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(
                    destructive
                        ? Color(hex: 0xD05858).opacity(disabled ? 0.38 : 1)
                        : Color.white.opacity(disabled ? 0.38 : textOpacity)
                )
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color.clear)
                .overlay(
                    SettingsSmoothedRoundedRectangle(cornerRadius: 8)
                        .stroke(
                            destructive
                                ? Color(hex: 0xD05858).opacity(disabled ? 0.24 : borderOpacity)
                                : Color.white.opacity(disabled ? 0.24 : borderOpacity),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    var autoDiscoveryResultText: String? {
        let key = PermissionPrompt.autoDiscovery.id
        guard let rawResult = dialogState.permissionResultMessage[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawResult.isEmpty else {
            return nil
        }

        if rawResult == viewModel.text(.localDiscoveryNothingFound) {
            return viewModel.language == .zhHans
                ? "暂无可识别的模型，请手动添加或再次尝试"
                : "No recognizable models found. Please add one manually or try again."
        }
        return rawResult
    }

    var autoDiscoveryResultColor: Color {
        let key = PermissionPrompt.autoDiscovery.id
        let rawResult = dialogState.permissionResultMessage[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawResult == viewModel.text(.localDiscoveryNothingFound) {
            return Color(hex: 0xD87E3E)
        }
        return Color(hex: 0x69BD64)
    }

    var autoDiscoveryActionTitle: String {
        if runtimeState.autoDiscoveryScanning {
            return viewModel.language == .zhHans ? "扫描中···" : "Scanning..."
        }
        return viewModel.text(.localDiscoveryAction)
    }

    var localDiscoveryTitleText: String {
        viewModel.language == .zhHans ? "扫描本地已登录模型" : viewModel.text(.localDiscoveryTitle)
    }

    var statusAuthorizedText: String {
        viewModel.language == .zhHans ? "已授权" : "Authorized"
    }

    var statusUnauthorizedText: String {
        viewModel.language == .zhHans ? "未授权" : "Not authorized"
    }

    var notificationActionTitle: String {
        if viewModel.hasNotificationPermission {
            return statusAuthorizedText
        }
        return viewModel.language == .zhHans ? "申请授权" : viewModel.text(.permissionNotificationsAction)
    }

    var keychainActionTitle: String {
        // 已就绪时按钮语义是“删除本机凭证”（实删 vault 数据），不是取消授权；
        // 未就绪时点击触发一次交互式准备。
        viewModel.secureStorageReady
            ? viewModel.text(.permissionKeychainDeleteAction)
            : viewModel.text(.permissionKeychainPrepareAction)
    }

    var fullDiskActionTitle: String {
        if viewModel.language == .zhHans {
            return viewModel.fullDiskAccessGranted ? "取消授权" : "打开设置"
        }
        return viewModel.text(.permissionFullDiskAction)
    }

    var notificationPermissionStatusText: String {
        viewModel.hasNotificationPermission ? statusAuthorizedText : statusUnauthorizedText
    }

    var notificationPermissionStatusColor: Color {
        viewModel.hasNotificationPermission ? Color(hex: 0x69BD64) : Color(hex: 0xD05757)
    }

    /// 钥匙串 tile 的固定状态文案（doc 7.5）：把凭证访问状态映射成
    /// 未配置 / 已准备，可后台读取 / 需要重新登录 / 系统拒绝访问 /
    /// 浏览器会话已过期 / 凭证刷新失败。
    var keychainPermissionStatusText: String {
        viewModel.text(viewModel.credentialAccessDisplayState.localizationKey)
    }

    var keychainPermissionStatusColor: Color {
        Color(hex: viewModel.credentialAccessDisplayState.statusColorHex)
    }

    var fullDiskPermissionStatusText: String {
        viewModel.fullDiskAccessGranted ? statusAuthorizedText : statusUnauthorizedText
    }

    var fullDiskPermissionStatusColor: Color {
        viewModel.fullDiskAccessGranted ? Color(hex: 0x69BD64) : Color(hex: 0xD05757)
    }

    var permissionAlertTitle: String {
        switch dialogState.permissionPrompt {
        case .notifications:
            return viewModel.text(.permissionNotificationsTitle)
        case .keychain:
            return viewModel.text(.permissionKeychainTitle)
        case .fullDisk:
            return viewModel.text(.permissionFullDiskTitle)
        case .resetLocalData:
            return viewModel.text(.resetLocalDataTitle)
        case .autoDiscovery:
            return viewModel.text(.localDiscoveryTitle)
        case .deleteLocalCredentials:
            return viewModel.text(.permissionKeychainDeleteAction)
        case .none:
            return ""
        }
    }

    var permissionAlertMessage: String {
        switch dialogState.permissionPrompt {
        case .notifications:
            return viewModel.text(.permissionNotificationsConfirm)
        case .keychain:
            return viewModel.text(.permissionKeychainConfirm)
        case .fullDisk:
            return viewModel.text(.permissionFullDiskConfirm)
        case .autoDiscovery:
            return viewModel.text(.localDiscoveryConfirm)
        case .resetLocalData:
            return viewModel.text(.resetLocalDataConfirm)
        case .deleteLocalCredentials:
            return viewModel.text(.permissionKeychainDeleteConfirm)
        case .none:
            return ""
        }
    }

    func handlePermissionPrompt() {
        let prompt = dialogState.permissionPrompt
        dialogState.permissionPrompt = nil
        handlePermissionAction(prompt)
    }

    func handlePermissionAction(_ prompt: PermissionPrompt?) {
        switch prompt {
        case .notifications:
            if !viewModel.hasNotificationPermission {
                viewModel.requestNotificationPermission()
            }
            dialogState.permissionResultMessage[PermissionPrompt.notifications.id] = viewModel.hasNotificationPermission
                ? statusAuthorizedText
                : viewModel.text(.permissionNotificationsRequested)
            dialogState.permissionResultIsError[PermissionPrompt.notifications.id] = false
        case .keychain:
            if !viewModel.secureStorageReady {
                let ok = viewModel.prepareSecureStorageAccess()
                dialogState.permissionResultMessage[PermissionPrompt.keychain.id] = ok
                    ? viewModel.text(.permissionKeychainReady)
                    : viewModel.text(.permissionKeychainFailed)
                dialogState.permissionResultIsError[PermissionPrompt.keychain.id] = !ok
            } else {
                // 已就绪：按钮语义是“删除本机凭证”，确认后实删 vault 数据。
                dialogState.permissionPrompt = .deleteLocalCredentials
            }
        case .fullDisk:
            viewModel.openFullDiskAccessSettings()
            dialogState.permissionResultMessage[PermissionPrompt.fullDisk.id] = viewModel.text(.permissionFullDiskRequested)
            dialogState.permissionResultIsError[PermissionPrompt.fullDisk.id] = false
        case .autoDiscovery:
            startAutoDiscoveryScan()
        case .resetLocalData:
            viewModel.resetLocalAppData()
            seedInputsFromConfig()
            syncSelection()
            navigationState.selectedSettingsTab = .general
            dialogState.permissionResultMessage[PermissionPrompt.resetLocalData.id] = viewModel.text(.resetLocalDataDone)
            dialogState.permissionResultIsError[PermissionPrompt.resetLocalData.id] = false
        case .deleteLocalCredentials:
            let ok = viewModel.deleteLocalCredentials()
            dialogState.permissionResultMessage[PermissionPrompt.deleteLocalCredentials.id] = ok
                ? viewModel.text(.permissionKeychainDeleted)
                : viewModel.text(.permissionKeychainDeleteFailed)
            dialogState.permissionResultIsError[PermissionPrompt.deleteLocalCredentials.id] = !ok
        case .none:
            break
        }
        viewModel.refreshPermissionStatusesNow()
    }

    func startAutoDiscoveryScan() {
        guard !runtimeState.autoDiscoveryScanning else { return }
        runtimeState.autoDiscoveryScanning = true
        dialogState.permissionResultMessage[PermissionPrompt.autoDiscovery.id] = nil
        dialogState.permissionResultIsError[PermissionPrompt.autoDiscovery.id] = false

        Task { @MainActor in
            let result = await viewModel.discoverLocalProviders()
            dialogState.permissionResultMessage[PermissionPrompt.autoDiscovery.id] = result
            dialogState.permissionResultIsError[PermissionPrompt.autoDiscovery.id] = false
            runtimeState.autoDiscoveryScanning = false
        }
    }
}
