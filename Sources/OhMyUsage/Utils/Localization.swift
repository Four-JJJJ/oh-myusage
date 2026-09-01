import Foundation

enum L10nKey {
    case appTitle
    case overview
    case settings
    case settingsTitle
    case settingsGeneralTab
    case settingsModelsTab
    case settingsAboutTab
    case done
    case general
    case launchAtLogin
    case launchAtLoginHint
    case providers
    case relaySimpleMode
    case relaySimpleModeHint
    case enabled
    case toggleOn
    case toggleOff
    case editingNow
    case noEnabledProviders
    case language
    case chinese
    case english
    case statusNormal
    case statusAlert
    case statusDisconnected
    case lastUpdate
    case lowThreshold
    case refreshNow
    case quit
    case error
    case pasteToken
    case save
    case tokenSaved
    case noToken
    case remaining
    case used
    case limit
    case resetsAt
    case unlimited
    case lowBalanceWarning
    case providerUnreachable
    case authError
    case tokenInvalidOrExpired
    case addRelayProvider
    case providerName
    case baseURL
    case addProvider
    case removeProvider
    case saveConfig
    case saveToken
    case enableTokenChannel
    case enableAccountChannel
    case pasteSystemToken
    case userID
    case userIDHeader
    case authHeader
    case authScheme
    case endpointPath
    case remainingPath
    case usedPath
    case limitPath
    case successPath
    case unit
    case relayRequiredFieldsHint
    case kimiAuthMode
    case kimiAuthManual
    case kimiAuthAuto
    case kimiManualToken
    case kimiAutoDetect
    case kimiAuthDetected
    case kimiAuthNotFound
    case kimiFdaHint
    case kimiOpenPrivacySettings
    case kimiBrowserOrder
    case kimiAutoCookie
    case kimiWeekly
    case kimiWindow5h
    case inSuffix
    case countdownTitle
    case quotaFiveHour
    case quotaWeekly
    case statusSufficient
    case statusQuotaTight
    case statusBalanceSufficient
    case statusBalanceTight
    case statusBalanceExhausted
    case statusTight
    case statusExhausted
    case statusActive
    case codexReadyToSwitch
    case updatedAgo
    case balanceLabel
    case thirdPartyRelay
    case officialProviders
    case thirdPartyProviders
    case officialTab
    case thirdPartyTab
    case selectProviderHint
    case sourceMode
    case webMode
    case webDisabled
    case webAutoImport
    case webManual
    case manualCookieHeader
    case officialAutoDiscoveryHint
    case matchedAdapter
    case relayTemplate
    case relayTemplatePresetHint
    case authSourceLabel
    case credentialMode
    case credentialModeManualPreferred
    case credentialModeBrowserPreferred
    case credentialModeBrowserOnly
    case credentialModeHint
    case testConnection
    case connectionSuccess
    case connectionFailed
    case advancedSettings
    case statusBarDisplayProvider
    case statusBarAppearanceMode
    case statusBarAppearanceFollowWallpaper
    case statusBarAppearanceDark
    case statusBarAppearanceLight
    case statusBarDisplayStyle
    case statusBarStyleIconPercent
    case statusBarStyleBarNamePercent
    case codexProfiles
    case codexProfileSlotA
    case codexProfileSlotB
    case codexAuthJSON
    case codexImportProfile
    case codexProfileImported
    case codexProfileImportFailed
    case codexProfileMissing
    case codexCurrentAccount
    case codexSwitchAction
    case codexSwitchSuccess
    case codexSwitchNeedsVerification
    case codexSwitchFailed
    case codexSwitchAppliedNeedsRestart
    case codexSwitchDesktopRestartIncomplete
    case codexImportedAt
    case codexProfileHint
    case codexProfileDetails
    case codexAuthJSONHowTo
    case codexProfileEmailUnknown
    case codexDeleteProfile
    case codexDeleteProfileTitle
    case codexDeleteProfileMessage
    case codexDeleteConfirm
    case codexImportNextProfile
    case quotaDisplayMode
    case quotaDisplayRemaining
    case quotaDisplayUsed
    case claudeQuotaDisplayHint
    case permissionsTitle
    case permissionsHint
    case permissionsPrivacyPromise
    case permissionNotificationsTitle
    case permissionNotificationsHint
    case permissionNotificationsAction
    case permissionNotificationsConfirm
    case permissionNotificationsRequested
    case permissionKeychainTitle
    case permissionKeychainHint
    case permissionKeychainAction
    case permissionKeychainConfirm
    case permissionKeychainReady
    case permissionKeychainFailed
    case permissionKeychainPrepareAction
    case permissionKeychainDeleteAction
    case permissionKeychainDeleteConfirm
    case permissionKeychainDeleted
    case permissionKeychainDeleteFailed
    case credentialStatusNotConfigured
    case credentialStatusReady
    case credentialStatusReloginRequired
    case credentialStatusSystemAccessRequired
    case credentialStatusSessionExpired
    case credentialStatusRefreshFailed
    case permissionFullDiskTitle
    case permissionFullDiskHint
    case permissionFullDiskAction
    case permissionFullDiskConfirm
    case permissionFullDiskRequested
    case permissionContinue
    case permissionCancel
    case permissionStatusAuthorized
    case permissionStatusPending
    case permissionStatusNeedsAction
    case resetLocalDataTitle
    case resetLocalDataHint
    case resetLocalDataAction
    case resetLocalDataConfirm
    case resetLocalDataDone
    case localDiscoveryTitle
    case localDiscoveryHint
    case localDiscoveryAction
    case localDiscoveryConfirm
    case localDiscoveryScanning
    case localDiscoveryNothingFound
    case aboutTitle
    case aboutVersion
    case aboutGitHub
    case aboutOpenGitHub
    case aboutCheckUpdates
    case aboutUpdateChecking
    case aboutUpdateUpToDate
    case aboutUpdateFailed
    case updateAvailableTitle
    case updateAvailableBody
    case updateDownloadAction
}

enum Localizer {
    static func text(_ key: L10nKey, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            switch key {
            case .appTitle: return "AI Plan 监控"
            case .overview: return "总览"
            case .settings: return "设置..."
            case .settingsTitle: return "设置"
            case .settingsGeneralTab: return "通用设置"
            case .settingsModelsTab: return "模型设置"
            case .settingsAboutTab: return "关于"
            case .done: return "完成"
            case .general: return "通用"
            case .launchAtLogin: return "开机启动"
            case .launchAtLoginHint: return "勾选后会把 oh-myusage 注册为登录项。建议安装到“应用程序”后再启用"
            case .providers: return "数据源"
            case .relaySimpleMode: return "API用量极简配置（推荐）"
            case .relaySimpleModeHint: return "开启后仅保留核心项，接口路径与字段解析自动使用站点模板。"
            case .enabled: return "启用"
            case .toggleOn: return "开启"
            case .toggleOff: return "关闭"
            case .editingNow: return "编辑中"
            case .noEnabledProviders: return "暂无启用的数据源，请在设置中开启"
            case .language: return "选择语言"
            case .chinese: return "简体中文"
            case .english: return "English"
            case .statusNormal: return "正常"
            case .statusAlert: return "告警"
            case .statusDisconnected: return "失联"
            case .lastUpdate: return "最近更新"
            case .lowThreshold: return "低余额阈值"
            case .refreshNow: return "立即刷新"
            case .quit: return "退出"
            case .error: return "错误"
            case .pasteToken: return "粘贴 Token"
            case .save: return "保存"
            case .tokenSaved: return "已保存"
            case .noToken: return "未配置"
            case .remaining: return "剩余"
            case .used: return "已用"
            case .limit: return "上限"
            case .resetsAt: return "重置于"
            case .unlimited: return "不限额"
            case .lowBalanceWarning: return "低余额告警"
            case .providerUnreachable: return "服务不可用"
            case .authError: return "认证错误"
            case .tokenInvalidOrExpired: return "Token 无效或已过期"
            case .addRelayProvider: return "新增 API用量"
            case .providerName: return "名称"
            case .baseURL: return "Base URL"
            case .addProvider: return "添加"
            case .removeProvider: return "移除"
            case .saveConfig: return "保存配置"
            case .saveToken: return "保存 Token"
            case .enableTokenChannel: return "启用 Token 配额通道"
            case .enableAccountChannel: return "启用账户余额通道"
            case .pasteSystemToken: return "粘贴系统访问令牌"
            case .userID: return "用户 ID"
            case .userIDHeader: return "用户 Header"
            case .authHeader: return "认证 Header"
            case .authScheme: return "认证前缀"
            case .endpointPath: return "余额接口路径"
            case .remainingPath: return "剩余字段路径"
            case .usedPath: return "已用字段路径"
            case .limitPath: return "上限字段路径"
            case .successPath: return "成功字段路径"
            case .unit: return "单位"
            case .relayRequiredFieldsHint: return "必填：名称、Base URL、Token。若需账户余额，再填系统令牌、用户ID和字段路径。"
            case .kimiAuthMode: return "认证模式"
            case .kimiAuthManual: return "手动"
            case .kimiAuthAuto: return "自动"
            case .kimiManualToken: return "粘贴 kimi-auth Token"
            case .kimiAutoDetect: return "自动检测 Token"
            case .kimiAuthDetected: return "已检测到"
            case .kimiAuthNotFound: return "未找到可用的 Kimi 登录 Cookie"
            case .kimiFdaHint: return "自动读取浏览器 Cookie 需要 Full Disk Access 权限。"
            case .kimiOpenPrivacySettings: return "打开隐私设置"
            case .kimiBrowserOrder: return "浏览器顺序"
            case .kimiAutoCookie: return "启用自动读取浏览器 Cookie"
            case .kimiWeekly: return "周配额"
            case .kimiWindow5h: return "5小时限额"
            case .inSuffix: return "后"
            case .countdownTitle: return "倒计时"
            case .quotaFiveHour: return "5h"
            case .quotaWeekly: return "周"
            case .statusSufficient: return "充足"
            case .statusQuotaTight: return "限额紧张"
            case .statusBalanceSufficient: return "余额充足"
            case .statusBalanceTight: return "余额紧张"
            case .statusBalanceExhausted: return "余额耗尽"
            case .statusTight: return "紧张"
            case .statusExhausted: return "耗尽"
            case .statusActive: return "激活中"
            case .codexReadyToSwitch: return "已重置，可切换"
            case .updatedAgo: return "更新于"
            case .balanceLabel: return "余额"
            case .thirdPartyRelay: return "API用量"
            case .officialProviders: return "官方订阅来源"
            case .thirdPartyProviders: return "API用量预置项"
            case .officialTab: return "官方订阅"
            case .thirdPartyTab: return "API余额"
            case .selectProviderHint: return "请先在左侧选择模型"
            case .sourceMode: return "来源模式"
            case .webMode: return "网页来源"
            case .webDisabled: return "关闭"
            case .webAutoImport: return "自动导入"
            case .webManual: return "手动"
            case .manualCookieHeader: return "手动 Cookie/Header"
            case .officialAutoDiscoveryHint: return "默认会自动发现本地 CLI 登录态；手动 Cookie 仅作为网页来源修复入口。"
            case .matchedAdapter: return "匹配模板"
            case .relayTemplate: return "站点模板"
            case .relayTemplatePresetHint: return "优先使用预置项；只有通用 NewAPI 场景或站点接口不一致时，再改 Base URL 或展开高级设置。"
            case .authSourceLabel: return "认证来源"
            case .credentialMode: return "凭证模式"
            case .credentialModeManualPreferred: return "手动优先"
            case .credentialModeBrowserPreferred: return "浏览器优先"
            case .credentialModeBrowserOnly: return "仅浏览器"
            case .credentialModeHint: return "浏览器优先会在手动凭证过期或失效时自动尝试读取浏览器登录态；仅浏览器模式不会使用你手动保存的 Cookie 或 Token。"
            case .testConnection: return "测试连接"
            case .connectionSuccess: return "连接成功"
            case .connectionFailed: return "连接失败"
            case .advancedSettings: return "高级设置"
            case .statusBarDisplayProvider: return "在状态栏展示该模型"
            case .statusBarAppearanceMode: return "菜单栏外观"
            case .statusBarAppearanceFollowWallpaper: return "跟随壁纸"
            case .statusBarAppearanceDark: return "深色"
            case .statusBarAppearanceLight: return "浅色"
            case .statusBarDisplayStyle: return "展示样式"
            case .statusBarStyleIconPercent: return "图标+百分比"
            case .statusBarStyleBarNamePercent: return "柱状图+文字"
            case .codexProfiles: return "Codex 账号档案"
            case .codexProfileSlotA: return "账号 A"
            case .codexProfileSlotB: return "账号 B"
            case .codexAuthJSON: return "auth.json 内容"
            case .codexImportProfile: return "导入账号"
            case .codexProfileImported: return "账号档案已导入"
            case .codexProfileImportFailed: return "导入失败"
            case .codexProfileMissing: return "该槽位还没有导入可切换的 Codex 账号"
            case .codexCurrentAccount: return "当前账号"
            case .codexSwitchAction: return "切换"
            case .codexSwitchSuccess: return "已切换，可直接使用"
            case .codexSwitchNeedsVerification: return "已切换到该账号，但需要重新验证"
            case .codexSwitchFailed: return "切换失败"
            case .codexSwitchAppliedNeedsRestart: return "已写入本机登录，请重开 Codex 桌面端"
            case .codexSwitchDesktopRestartIncomplete: return "已切换，但 Codex 桌面端重启未完成，请手动重开"
            case .codexImportedAt: return "最近导入"
            case .codexProfileHint: return "粘贴该账号完整 auth.json 内容。切换时会写回本机 Codex 当前登录，并立即做一次轻量校验。"
            case .codexProfileDetails: return "详情"
            case .codexAuthJSONHowTo: return "获取方法：先登录目标 Codex 账号，再复制 ~/.codex/auth.json 的完整内容。"
            case .codexProfileEmailUnknown: return "未识别邮箱"
            case .codexDeleteProfile: return "删除"
            case .codexDeleteProfileTitle: return "删除 Codex 账号"
            case .codexDeleteProfileMessage: return "删除后将移除该账号保存的 auth.json，本机当前已登录状态不会立刻受影响。"
            case .codexDeleteConfirm: return "确认删除"
            case .codexImportNextProfile: return "导入下一个账号"
            case .quotaDisplayMode: return "用量偏好"
            case .quotaDisplayRemaining: return "看剩余"
            case .quotaDisplayUsed: return "看已用"
            case .claudeQuotaDisplayHint: return "默认按“剩余”展示和提醒；如需按“已用”视角查看，可切到“看已用”。"
            case .permissionsTitle: return "权限与自动发现"
            case .permissionsHint: return "先说明用途，再由你确认是否发起系统授权。"
            case .permissionsPrivacyPromise: return "本地 Cookie、Token 和 CLI 登录态只会保存在你的 Mac 上，不会上传到开发者服务器；只有在你启用对应模型刷新时，应用才会直接请求该模型官方/ API 站点"
            case .permissionNotificationsTitle: return "系统通知"
            case .permissionNotificationsHint: return "用于低额度、鉴权失效和连接失败提醒"
            case .permissionNotificationsAction: return "授权通知"
            case .permissionNotificationsConfirm: return "确认后会弹出 macOS 通知授权窗口，用于发送低额度、鉴权失效和连接失败提醒。"
            case .permissionNotificationsRequested: return "已发起系统通知授权请求。"
            case .permissionKeychainTitle: return "钥匙串机密信息"
            case .permissionKeychainHint: return "用于把你手动保存的 Cookie、Token 和 API Key 安全地保存在 macOS 钥匙串里"
            case .permissionKeychainAction: return "启用钥匙串"
            case .permissionKeychainConfirm: return "确认后会初始化 oh-myusage 的钥匙串存储，用来安全保存你手动录入的 Cookie、Token 和 API Key。"
            case .permissionKeychainReady: return "钥匙串存储已就绪。"
            case .permissionKeychainFailed: return "钥匙串存储初始化失败，请稍后重试。"
            case .permissionKeychainPrepareAction: return "准备本机授权"
            case .permissionKeychainDeleteAction: return "删除本机凭证"
            case .permissionKeychainDeleteConfirm: return "确认后将删除 oh-myusage 钥匙串 vault 中保存的全部本机凭证（手动录入的 Cookie、Token、API Key 和已导入的登录态）。受影响的数据源需要重新录入凭证或重新导入后才能继续刷新；模型配置和其他本地数据不受影响。"
            case .permissionKeychainDeleted: return "本机凭证已删除。"
            case .permissionKeychainDeleteFailed: return "本机凭证删除失败，请稍后重试。"
            case .credentialStatusNotConfigured: return "未配置"
            case .credentialStatusReady: return "已准备，可后台读取"
            case .credentialStatusReloginRequired: return "需要重新登录"
            case .credentialStatusSystemAccessRequired: return "系统拒绝访问"
            case .credentialStatusSessionExpired: return "浏览器会话已过期"
            case .credentialStatusRefreshFailed: return "凭证刷新失败"
            case .permissionFullDiskTitle: return "全盘访问"
            case .permissionFullDiskHint: return "用于读取浏览器 Cookie 数据库和本地 CLI/ auth 文件，提升自动识别成功率"
            case .permissionFullDiskAction: return "打开全盘访问设置"
            case .permissionFullDiskConfirm: return "确认后会跳转到“隐私与安全性 -> 全盘访问”，方便你授权 oh-myusage 读取浏览器 Cookie 和本地 CLI 登录文件。"
            case .permissionFullDiskRequested: return "已打开系统的全盘访问设置页。"
            case .permissionContinue: return "继续"
            case .permissionCancel: return "取消"
            case .permissionStatusAuthorized: return "已授权"
            case .permissionStatusPending: return "待授权"
            case .permissionStatusNeedsAction: return "待设置"
            case .resetLocalDataTitle: return "重置本地数据"
            case .resetLocalDataHint: return "清理本地配置、账号槽位、首次安装引导和 oh-myusage 钥匙串内容，用于恢复到接近初装状态。系统通知、全盘访问等 macOS 授权仍需你在系统设置里手动关闭"
            case .resetLocalDataAction: return "重置所有数据"
            case .resetLocalDataConfirm: return "确认后会清理本地配置、Codex 账号槽位、启动项和 oh-myusage 的钥匙串内容。应用会恢复成接近首次安装状态；系统通知、全盘访问等 macOS 授权不会被自动撤销。"
            case .resetLocalDataDone: return "本地应用数据已清理，首次安装引导已重置。若要连系统通知或全盘访问一起关闭，请到 macOS 系统设置里手动撤销。"
            case .localDiscoveryTitle: return "扫描本地已登录模型"
            case .localDiscoveryHint: return "在授权完成后，自动尝试读取本机已有登录态并抓取可用模型的余额/额度"
            case .localDiscoveryAction: return "开始扫描"
            case .localDiscoveryConfirm: return "确认后会尝试读取本机已有的 CLI/浏览器登录态，并直接请求对应官方/API 站点来抓取余额或额度。"
            case .localDiscoveryScanning: return "正在扫描本机已登录模型..."
            case .localDiscoveryNothingFound: return "暂时没有发现可直接读取的本机模型登录态。"
            case .aboutTitle: return "关于 oh-myusage"
            case .aboutVersion: return "版本"
            case .aboutGitHub: return "项目主页"
            case .aboutOpenGitHub: return "打开 GitHub"
            case .aboutCheckUpdates: return "检查更新"
            case .aboutUpdateChecking: return "正在检查更新..."
            case .aboutUpdateUpToDate: return "已是最新版本（当前 %@，最新 %@）"
            case .aboutUpdateFailed: return "检查更新失败，请稍后重试。"
            case .updateAvailableTitle: return "发现新版本"
            case .updateAvailableBody: return "最新 %@（当前 %@）"
            case .updateDownloadAction: return "下载最新安装包"
            }
        case .en:
            switch key {
            case .appTitle: return "oh-myusage"
            case .overview: return "Overview"
            case .settings: return "Settings..."
            case .settingsTitle: return "Settings"
            case .settingsGeneralTab: return "General"
            case .settingsModelsTab: return "Models"
            case .settingsAboutTab: return "About"
            case .done: return "Done"
            case .general: return "General"
            case .launchAtLogin: return "Launch at login"
            case .launchAtLoginHint: return "When enabled, oh-myusage is registered as a login item. It's best to enable this after moving the app to Applications."
            case .providers: return "Providers"
            case .relaySimpleMode: return "Minimal API usage setup (Recommended)"
            case .relaySimpleModeHint: return "When enabled, only core fields are shown and endpoint/JSON paths follow site templates."
            case .enabled: return "Enabled"
            case .toggleOn: return "On"
            case .toggleOff: return "Off"
            case .editingNow: return "Editing"
            case .noEnabledProviders: return "No enabled providers. Enable them in Settings."
            case .language: return "Language"
            case .chinese: return "简体中文"
            case .english: return "English"
            case .statusNormal: return "Normal"
            case .statusAlert: return "Alert"
            case .statusDisconnected: return "Disconnected"
            case .lastUpdate: return "Last update"
            case .lowThreshold: return "Low threshold"
            case .refreshNow: return "Refresh Now"
            case .quit: return "Quit"
            case .error: return "Error"
            case .pasteToken: return "Paste token"
            case .save: return "Save"
            case .tokenSaved: return "Token saved"
            case .noToken: return "No token"
            case .remaining: return "Remaining"
            case .used: return "Used"
            case .limit: return "Limit"
            case .resetsAt: return "Resets"
            case .unlimited: return "Unlimited"
            case .lowBalanceWarning: return "Low Balance Warning"
            case .providerUnreachable: return "Provider Unreachable"
            case .authError: return "Auth Error"
            case .tokenInvalidOrExpired: return "Token invalid or expired"
            case .addRelayProvider: return "Add API Usage"
            case .providerName: return "Name"
            case .baseURL: return "Base URL"
            case .addProvider: return "Add"
            case .removeProvider: return "Remove"
            case .saveConfig: return "Save Config"
            case .saveToken: return "Save Token"
            case .enableTokenChannel: return "Enable token quota channel"
            case .enableAccountChannel: return "Enable account balance channel"
            case .pasteSystemToken: return "Paste system access token"
            case .userID: return "User ID"
            case .userIDHeader: return "User header"
            case .authHeader: return "Auth header"
            case .authScheme: return "Auth scheme"
            case .endpointPath: return "Balance endpoint path"
            case .remainingPath: return "Remaining JSON path"
            case .usedPath: return "Used JSON path"
            case .limitPath: return "Limit JSON path"
            case .successPath: return "Success JSON path"
            case .unit: return "Unit"
            case .relayRequiredFieldsHint: return "Required: Name, Base URL, token. For account balance also provide system token, user ID, and JSON paths."
            case .kimiAuthMode: return "Auth mode"
            case .kimiAuthManual: return "Manual"
            case .kimiAuthAuto: return "Auto"
            case .kimiManualToken: return "Paste kimi-auth token"
            case .kimiAutoDetect: return "Auto detect token"
            case .kimiAuthDetected: return "Detected"
            case .kimiAuthNotFound: return "No usable Kimi session cookie found"
            case .kimiFdaHint: return "Automatic browser cookie import requires Full Disk Access."
            case .kimiOpenPrivacySettings: return "Open Privacy Settings"
            case .kimiBrowserOrder: return "Browser order"
            case .kimiAutoCookie: return "Enable browser cookie auto import"
            case .kimiWeekly: return "Weekly quota"
            case .kimiWindow5h: return "5-hour window"
            case .inSuffix: return ""
            case .countdownTitle: return "Countdown"
            case .quotaFiveHour: return "5h"
            case .quotaWeekly: return "Weekly"
            case .statusSufficient: return "Healthy"
            case .statusQuotaTight: return "Quota tight"
            case .statusBalanceSufficient: return "Balance healthy"
            case .statusBalanceTight: return "Balance low"
            case .statusBalanceExhausted: return "Balance exhausted"
            case .statusTight: return "Tight"
            case .statusExhausted: return "Exhausted"
            case .statusActive: return "Active"
            case .codexReadyToSwitch: return "Reset, ready to switch"
            case .updatedAgo: return "Updated"
            case .balanceLabel: return "Balance"
            case .thirdPartyRelay: return "API Usage"
            case .officialProviders: return "Official Providers"
            case .thirdPartyProviders: return "API Usage Presets"
            case .officialTab: return "Official"
            case .thirdPartyTab: return "API Balance"
            case .selectProviderHint: return "Select a provider from the left"
            case .sourceMode: return "Source mode"
            case .webMode: return "Web mode"
            case .webDisabled: return "Disabled"
            case .webAutoImport: return "Auto Import"
            case .webManual: return "Manual"
            case .manualCookieHeader: return "Manual Cookie/Header"
            case .officialAutoDiscoveryHint: return "Local CLI credentials are auto-discovered by default; manual cookie input is only for web-source repair."
            case .matchedAdapter: return "Matched adapter"
            case .relayTemplate: return "Site template"
            case .relayTemplatePresetHint: return "Prefer a built-in preset first. Use the generic NewAPI template only when needed, and open Advanced settings only if the site behaves differently."
            case .authSourceLabel: return "Auth source"
            case .credentialMode: return "Credential mode"
            case .credentialModeManualPreferred: return "Manual First"
            case .credentialModeBrowserPreferred: return "Browser First"
            case .credentialModeBrowserOnly: return "Browser Only"
            case .credentialModeHint: return "Browser-first mode automatically retries with live browser credentials when saved tokens expire. Browser-only mode ignores manually saved cookies or tokens."
            case .testConnection: return "Test connection"
            case .connectionSuccess: return "Connection successful"
            case .connectionFailed: return "Connection failed"
            case .advancedSettings: return "Advanced settings"
            case .statusBarDisplayProvider: return "Show this provider in menu bar"
            case .statusBarAppearanceMode: return "Menubar Appearance"
            case .statusBarAppearanceFollowWallpaper: return "Wallpaper"
            case .statusBarAppearanceDark: return "Dark"
            case .statusBarAppearanceLight: return "Light"
            case .statusBarDisplayStyle: return "Display Style"
            case .statusBarStyleIconPercent: return "Icon + Percent"
            case .statusBarStyleBarNamePercent: return "Bar + Text"
            case .codexProfiles: return "Codex Profiles"
            case .codexProfileSlotA: return "Account A"
            case .codexProfileSlotB: return "Account B"
            case .codexAuthJSON: return "auth.json content"
            case .codexImportProfile: return "Import Account"
            case .codexProfileImported: return "Profile imported"
            case .codexProfileImportFailed: return "Import failed"
            case .codexProfileMissing: return "No imported Codex profile is available for this slot"
            case .codexCurrentAccount: return "Current"
            case .codexSwitchAction: return "Switch"
            case .codexSwitchSuccess: return "Switched successfully. Codex is ready to use."
            case .codexSwitchNeedsVerification: return "Switched to this account, but re-verification is required"
            case .codexSwitchFailed: return "Switch failed"
            case .codexSwitchAppliedNeedsRestart: return "Local Codex auth was updated. Reopen Codex desktop to apply it."
            case .codexSwitchDesktopRestartIncomplete: return "Switched successfully, but Codex Desktop did not finish restarting. Please reopen it manually."
            case .codexImportedAt: return "Imported"
            case .codexProfileHint: return "Paste the full auth.json content for this account. Switching writes it back to local Codex auth and runs a lightweight validation."
            case .codexProfileDetails: return "Details"
            case .codexAuthJSONHowTo: return "How to get it: sign in to the target Codex account first, then copy the full contents of ~/.codex/auth.json."
            case .codexProfileEmailUnknown: return "Email unavailable"
            case .codexDeleteProfile: return "Delete"
            case .codexDeleteProfileTitle: return "Delete Codex account"
            case .codexDeleteProfileMessage: return "This removes the saved auth.json for the account. It does not immediately sign the current local Codex session out."
            case .codexDeleteConfirm: return "Delete"
            case .codexImportNextProfile: return "Import another account"
            case .quotaDisplayMode: return "Usage preference"
            case .quotaDisplayRemaining: return "Remaining"
            case .quotaDisplayUsed: return "Used"
            case .claudeQuotaDisplayHint: return "Display and alerts default to Remaining. Switch to Used if you prefer usage-first monitoring."
            case .permissionsTitle: return "Permissions & auto-discovery"
            case .permissionsHint: return "oh-myusage explains each permission before triggering the macOS request."
            case .permissionsPrivacyPromise: return "Local cookies, tokens, and CLI sessions stay on your Mac and are never uploaded to a developer server. The app only calls the matching official/API endpoint when you enable that provider."
            case .permissionNotificationsTitle: return "Notifications"
            case .permissionNotificationsHint: return "Used for low quota, auth expired, and connection failure alerts."
            case .permissionNotificationsAction: return "Allow notifications"
            case .permissionNotificationsConfirm: return "Continue to request macOS notification permission for low quota, auth expired, and connection failure alerts."
            case .permissionNotificationsRequested: return "Notification permission request was sent."
            case .permissionKeychainTitle: return "Keychain secrets"
            case .permissionKeychainHint: return "Used to securely store the cookies, tokens, and API keys you save manually."
            case .permissionKeychainAction: return "Enable Keychain"
            case .permissionKeychainConfirm: return "Continue to initialize the oh-myusage Keychain vault for securely storing manually entered cookies, tokens, and API keys."
            case .permissionKeychainReady: return "Keychain storage is ready."
            case .permissionKeychainFailed: return "Keychain storage setup failed. Please try again."
            case .permissionKeychainPrepareAction: return "Prepare local access"
            case .permissionKeychainDeleteAction: return "Delete local credentials"
            case .permissionKeychainDeleteConfirm: return "Continue to delete every credential stored in the oh-myusage Keychain vault (manually entered cookies, tokens, API keys, and imported sessions). Affected providers must re-enter or re-import credentials before refreshing; provider configs and other local data are not touched."
            case .permissionKeychainDeleted: return "Local credentials were deleted."
            case .permissionKeychainDeleteFailed: return "Failed to delete local credentials. Please try again."
            case .credentialStatusNotConfigured: return "Not configured"
            case .credentialStatusReady: return "Ready for background reads"
            case .credentialStatusReloginRequired: return "Re-login required"
            case .credentialStatusSystemAccessRequired: return "System denied access"
            case .credentialStatusSessionExpired: return "Browser session expired"
            case .credentialStatusRefreshFailed: return "Credential refresh failed"
            case .permissionFullDiskTitle: return "Full Disk Access"
            case .permissionFullDiskHint: return "Used to read browser cookie databases and local CLI/auth files for better auto-discovery."
            case .permissionFullDiskAction: return "Open Full Disk Access"
            case .permissionFullDiskConfirm: return "Continue to open Privacy & Security > Full Disk Access so you can allow oh-myusage to read browser cookies and local CLI auth files."
            case .permissionFullDiskRequested: return "Opened the system Full Disk Access settings."
            case .permissionContinue: return "Continue"
            case .permissionCancel: return "Cancel"
            case .permissionStatusAuthorized: return "Allowed"
            case .permissionStatusPending: return "Pending"
            case .permissionStatusNeedsAction: return "Needs action"
            case .resetLocalDataTitle: return "Reset local app data"
            case .resetLocalDataHint: return "Clear local config, account slots, first-run onboarding state, and oh-myusage Keychain entries so the app returns close to a fresh install. macOS permissions like Notifications and Full Disk Access still have to be turned off in System Settings."
            case .resetLocalDataAction: return "Reset and clear"
            case .resetLocalDataConfirm: return "Continue to clear local config, Codex account slots, launch-at-login state, and oh-myusage Keychain data. The app will return close to first-run state, but macOS permissions are not automatically revoked."
            case .resetLocalDataDone: return "Local app data was cleared and first-run onboarding was reset. Revoke Notifications or Full Disk Access manually in System Settings if needed."
            case .localDiscoveryTitle: return "Scan local signed-in models"
            case .localDiscoveryHint: return "After permissions are granted, try local CLI/browser sessions and fetch balances or quota windows automatically."
            case .localDiscoveryAction: return "Scan now"
            case .localDiscoveryConfirm: return "Continue to inspect available local CLI/browser sessions and call the matching official/API endpoints to fetch balances or quota windows."
            case .localDiscoveryScanning: return "Scanning local signed-in models..."
            case .localDiscoveryNothingFound: return "No local signed-in model session could be used yet."
            case .aboutTitle: return "About oh-myusage"
            case .aboutVersion: return "Version"
            case .aboutGitHub: return "Repository"
            case .aboutOpenGitHub: return "Open GitHub"
            case .aboutCheckUpdates: return "Check for updates"
            case .aboutUpdateChecking: return "Checking for updates..."
            case .aboutUpdateUpToDate: return "You're up to date (current %@, latest %@)"
            case .aboutUpdateFailed: return "Failed to check updates. Please try again."
            case .updateAvailableTitle: return "Update Available"
            case .updateAvailableBody: return "Latest %@ (current %@)"
            case .updateDownloadAction: return "Download latest installer"
            }
        }
    }

    static func lowBalanceBody(
        providerName: String,
        remaining: String,
        unit: String,
        language: AppLanguage,
        displaysUsedQuota: Bool = false
    ) -> String {
        switch language {
        case .zhHans:
            return displaysUsedQuota
                ? "\(providerName) 已用 \(remaining) \(unit)"
                : "\(providerName) 剩余 \(remaining) \(unit)"
        case .en:
            return displaysUsedQuota
                ? "\(providerName) used \(remaining) \(unit)"
                : "\(providerName) remaining \(remaining) \(unit)"
        }
    }

    static func lowQuotaWindowBody(
        providerName: String,
        windowTitle: String,
        remaining: String,
        language: AppLanguage,
        displaysUsedQuota: Bool = false
    ) -> String {
        switch language {
        case .zhHans:
            return displaysUsedQuota
                ? "\(providerName) \(windowTitle) 已用 \(remaining)%"
                : "\(providerName) \(windowTitle) 剩余 \(remaining)%"
        case .en:
            return displaysUsedQuota
                ? "\(providerName) \(windowTitle) used \(remaining)%"
                : "\(providerName) \(windowTitle) remaining \(remaining)%"
        }
    }

    static func providerFailedBody(providerName: String, failures: Int, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return "\(providerName) 连续失败 \(failures) 次"
        case .en:
            return "\(providerName) failed \(failures) times"
        }
    }

    static func authErrorBody(providerName: String, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return "\(providerName) Token 无效或已过期"
        case .en:
            return "\(providerName) token invalid or expired"
        }
    }

    static func localDiscoveryFoundBody(providerNames: [String], language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return "扫描到 \(providerNames.joined(separator: " / ")) ，自动添加到监控"
        case .en:
            let joined = providerNames.joined(separator: ", ")
            return "Automatically discovered: \(joined)"
        }
    }
}
