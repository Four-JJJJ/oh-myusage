# 应用界面文案汇总与优化表

生成日期：2026-05-19

> **存档说明**：本文档是 2026-05-19 的界面文案快照存档，仅供历史参考。2.5.0 之后的界面文案以代码内 `localizedText` 双语实现为准，本表不再维护更新。

## 使用说明

- 范围：只包含 App 内用户可见或可能透出的界面文案，包括菜单栏、设置页、弹窗、状态、错误提示、空状态、权限引导和中转模板展示文案。
- 不包含：README/docs、测试、调试日志、内部字段名、真实凭证或用户私密数据。
- “优化表达”只作为产品文案建议，本文件不会直接替换代码里的现有文案。
- 优化原则：简洁、专业、适合 macOS 工具类产品；品牌名、Provider 名、Token/API Key、auth.json、路径和必要技术名默认保留。

## 覆盖概览

- 扫描源码/资源文件：299 个
- 汇总去重文案：595 条
- 覆盖模块：菜单栏 17 条；设置页 261 条；应用界面 72 条；全局本地化 203 条；更新与发布说明 17 条；使用统计 30 条；Provider 状态 26 条；运行状态 22 条；中转模板 13 条

## 原始表

| 模块/页面 | 位置 | 文案类型 | 原始文案 | 优化表达 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 菜单栏 / 设置页 | Sources/OhMyUsage/UI/Presenters/MenuQuotaPresenter.swift:540<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:579 | 标签/标题 | \(baseTitle)已用 | \(baseTitle)已用 | 可保留，保留动态变量 |
| 菜单栏 / 应用界面 | Sources/OhMyUsage/UI/Presenters/MenuDashboardPresenter.swift:64<br>Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:141 | 标签/标题 | \(seconds / 3600) 小时前 | \(seconds / 3600) 小时前 | 可保留，保留动态变量 |
| 菜单栏 / 应用界面 | Sources/OhMyUsage/UI/Presenters/MenuDashboardPresenter.swift:63<br>Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:140 | 标签/标题 | \(seconds / 60) 分钟前 | \(seconds / 60) 分钟前 | 可保留，保留动态变量 |
| 菜单栏 / 应用界面 | Sources/OhMyUsage/UI/Presenters/MenuDashboardPresenter.swift:65<br>Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:142 | 标签/标题 | \(seconds / 86_400) 天前 | \(seconds / 86_400) 天前 | 可保留，保留动态变量 |
| 菜单栏 / 应用界面 | Sources/OhMyUsage/UI/Presenters/MenuDashboardPresenter.swift:62<br>Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:139 | 标签/标题 | \(seconds) 秒前 | \(seconds) 秒前 | 可保留，保留动态变量 |
| 菜单栏 | Sources/OhMyUsage/UI/Presenters/MenuPermissionGuidePresenter.swift:73 | 标签/标题 | 待确认 | 待确认 | 可保留 |
| 菜单栏 / 全局本地化 | Sources/OhMyUsage/UI/Presenters/MenuPermissionGuidePresenter.swift:69<br>Sources/OhMyUsage/Utils/Localization.swift:389 | 按钮/操作 | 待授权 | 待授权 | 可保留 |
| 菜单栏 | Sources/OhMyUsage/UI/Presenters/MenuDashboardPresenter.swift:51 | 标签/标题 | 更新于 - | 更新于 - | 可保留 |
| 菜单栏 | Sources/OhMyUsage/UI/Presenters/MenuCardStatusPresenter.swift:135 | 标签/标题 | 故障 | 故障 | 可保留 |
| 菜单栏 | Sources/OhMyUsage/UI/Presenters/MenuPermissionGuidePresenter.swift:59 | 标签/标题 | 可开始 | 可开始 | 可保留 |
| 菜单栏 | Sources/OhMyUsage/UI/Presenters/MenuSubtitlePresenter.swift:48 | 说明/提示 | 请求次数 \(requestCount) | 请求次数 \(requestCount) | 可保留，保留动态变量 |
| 菜单栏 / 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Presenters/MenuPermissionGuidePresenter.swift:65<br>Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:288<br>Sources/OhMyUsage/Utils/Localization.swift:388 | 成功反馈 | 已授权 | 已授权 | 可保留 |
| 菜单栏 | Sources/OhMyUsage/UI/Presenters/MenuPermissionGuidePresenter.swift:60 | 标签/标题 | 已完成 | 已完成 | 可保留 |
| 菜单栏 | Sources/OhMyUsage/UI/Presenters/MenuDashboardPresenter.swift:90 | 标签/标题 | 应用更新状态：\(title) | 应用更新状态：\(title) | 可保留，保留动态变量 |
| 菜单栏 | Sources/OhMyUsage/UI/Presenters/MenuSubtitlePresenter.swift:64 | 标签/标题 | 有效期至 \(raw) (UTC) | 有效期至 \(raw)（UTC） | 建议替换，保留动态变量 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:135<br>Sources/OhMyUsage/App/AppUpdateCoordinator.swift:203 | 错误/异常 | 安装失败 | 安装失败 | 可保留 |
| 更新与发布说明 | Sources/OhMyUsage/App/ReleaseNotesWindowController.swift:221 | 按钮/操作 | 打开 Release 页面 | 打开 Release 页面 | 可保留 |
| 更新与发布说明 | Sources/OhMyUsage/App/ReleaseNotesWindowController.swift:235 | 空状态 | 当前版本没有填写更新说明。 | 当前版本没有填写更新说明。 | 可保留 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:284 | 标签/标题 | 当前已是最新版本（最新 \(latest)）。 | 当前已是最新版本（最新 \(latest)）。 | 可保留，保留动态变量 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:279 | 标签/标题 | 发现新版本 \(update.latestVersion)，点击“更新版本”开始更新。 | 发现新版本 \(update.latestVersion)，点击“更新版本”开始更新。 | 可保留，保留动态变量 |
| 更新与发布说明 / 设置页 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:256<br>Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:130 | 标签/标题 | 更新版本 | 更新版本 | 可保留 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:153<br>Sources/OhMyUsage/App/AppUpdateCoordinator.swift:212<br>Sources/OhMyUsage/App/AppUpdateCoordinator.swift:250<br>Sources/OhMyUsage/App/AppUpdateCoordinator.swift:272 | 标签/标题 | 即将安装重启... | 即将安装并重启… | 建议替换 |
| 更新与发布说明 | Sources/OhMyUsage/App/ReleaseNotesWindowController.swift:242 | 错误/异常 | 加载更新说明失败。你仍然可以点击下方按钮打开 Release 页面查看。 | 加载更新说明失败。你仍然可以点击下方按钮打开 Release 页面查看。 | 可保留 |
| 更新与发布说明 / 设置页 / 全局本地化 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:258<br>Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:129<br>Sources/OhMyUsage/Utils/Localization.swift:406 | 加载状态 | 检查更新 | 检查更新 | 可保留 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:144 | 错误/异常 | 检查失败 | 检查失败 | 可保留 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:171<br>Sources/OhMyUsage/App/AppUpdateCoordinator.swift:230 | 标签/标题 | 新版本 \(update.latestVersion) | 新版本 \(update.latestVersion) | 可保留，保留动态变量 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:275 | 标签/标题 | 新版本 \(version) 已准备完成。 | 新版本 \(version) 已准备完成。 | 可保留，保留动态变量 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:180 | 标签/标题 | 已经是最新版本 | 已是最新版本 | 建议替换 |
| 更新与发布说明 | Sources/OhMyUsage/App/ReleaseNotesWindowController.swift:228 | 加载状态 | 正在加载当前版本的更新说明… | 正在加载当前版本的更新说明… | 可保留 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:162<br>Sources/OhMyUsage/App/AppUpdateCoordinator.swift:221<br>Sources/OhMyUsage/App/AppUpdateCoordinator.swift:253<br>Sources/OhMyUsage/App/AppUpdateCoordinator.swift:269 | 加载状态 | 正在下载... | 正在下载… | 建议替换 |
| 更新与发布说明 | Sources/OhMyUsage/App/AppUpdateCoordinator.swift:137<br>Sources/OhMyUsage/App/AppUpdateCoordinator.swift:205 | 按钮/操作 | 重试 | 重试 | 可保留 |
| 更新与发布说明 | Sources/OhMyUsage/App/ReleaseNotesWindowController.swift:214 | 说明/提示 | oh-myusage \(version) 更新说明 | oh-myusage \(version) 更新说明 | 可保留，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:651 | 标签/标题 | \(providerName) \(windowTitle) 剩余 \(remaining)% | \(providerName) \(windowTitle) 剩余 \(remaining)% | 可保留，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:650 | 标签/标题 | \(providerName) \(windowTitle) 已用 \(remaining)% | \(providerName) \(windowTitle) 已用 \(remaining)% | 可保留，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:662 | 错误/异常 | \(providerName) 连续失败 \(failures) 次 | \(providerName) 连续失败 \(failures) 次 | 可保留，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:632 | 标签/标题 | \(providerName) 剩余 \(remaining) \(unit) | \(providerName) 剩余 \(remaining) \(unit) | 可保留，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:631 | 标签/标题 | \(providerName) 已用 \(remaining) \(unit) | \(providerName) 已用 \(remaining) \(unit) | 可保留，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:671 | 错误/异常 | \(providerName) Token 无效或已过期 | \(providerName) Token 无效或已过期 | 可保留，保留必要技术名，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:288 | 标签/标题 | 5小时限额 | 5 小时限额 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:261 | 按钮/操作 | 保存 Token | 保存 Token | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:260 | 按钮/操作 | 保存配置 | 保存配置 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:369 | 按钮/操作 | 本地 Cookie、Token 和 CLI 登录态只会保存在你的 Mac 上，不会上传到开发者服务器；只有在你启用对应模型刷新时，应用才会直接请求该模型官方/ API 站点 | 本地 Cookie、Token 和 CLI 登录态只保存在你的 Mac 上，不会上传到开发者服务器；只有启用对应模型刷新时，应用才会请求该模型官方或 API 站点。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:395 | 成功反馈 | 本地应用数据已清理，首次安装引导已重置。若要连系统通知或全盘访问一起关闭，请到 macOS 系统设置里手动撤销。 | 本地应用数据已清理，首次安装引导已重置。如需关闭系统通知或全盘访问，请到 macOS 系统设置手动撤销。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:275 | 标签/标题 | 必填：名称、Base URL、Token。若需账户余额，再填系统令牌、用户ID和字段路径。 | 必填：名称、Base URL、Token。若需账户余额，请补充系统令牌、用户 ID 和字段路径。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:229 | 标签/标题 | 编辑中 | 编辑中 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:250 | 标签/标题 | 不限额 | 无限额 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:331 | 标签/标题 | 菜单栏外观 | 菜单栏外观 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:326 | 按钮/操作 | 测试连接 | 测试连接 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:273 | 成功反馈 | 成功字段路径 | 成功字段路径 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:293 | 标签/标题 | 充足 | 充足 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:241 | 错误/异常 | 错误 | 错误 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:405 | 按钮/操作 | 打开 GitHub | 打开 GitHub | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:383 | 按钮/操作 | 打开全盘访问设置 | 打开全盘访问设置 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:284 | 按钮/操作 | 打开隐私设置 | 打开隐私设置 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:390 | 标签/标题 | 待设置 | 待设置 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:274 | 标签/标题 | 单位 | 单位 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:344 | 错误/异常 | 导入失败 | 导入失败 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:362 | 按钮/操作 | 导入下一个账号 | 导入下一个账号 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:342 | 按钮/操作 | 导入账号 | 导入账号 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:290 | 标签/标题 | 倒计时 | 倒计时 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:251 | 标签/标题 | 低余额告警 | 低额度提醒 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:238 | 标签/标题 | 低余额阈值 | 低额度阈值 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:410 | 标签/标题 | 发现新版本 | 发现新版本 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:252 | 错误/异常 | 服务不可用 | 服务暂不可用 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:345 | 空状态 | 该槽位还没有导入可切换的 Codex 账号 | 该槽位还没有导入可切换的 Codex 账号 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:329 | 标签/标题 | 高级设置 | 高级设置 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:235 | 标签/标题 | 告警 | 提醒 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:302 | 标签/标题 | 更新于 | 更新于 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:222 | 说明/提示 | 勾选后会把 oh-myusage 注册为登录项。建议安装到“应用程序”后再启用 | 开启后将 oh-myusage 注册为登录项。建议移入“应用程序”后再启用。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:218 | 标签/标题 | 关于 | 关于 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:402 | 标签/标题 | 关于 oh-myusage | 关于 oh-myusage | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:305 | 标签/标题 | 官方订阅来源 | 官方订阅来源 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:299 | 标签/标题 | 耗尽 | 已耗尽 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:289 | 标签/标题 | 后 | 后 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:356 | 说明/提示 | 获取方法：先登录目标 Codex 账号，再复制 ~/.codex/auth.json 的完整内容。 | 获取方法：先登录目标 Codex 账号，再复制 ~/.codex/auth.json 的完整内容。 | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:300 | 标签/标题 | 激活中 | 激活中 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:386 | 按钮/操作 | 继续 | 继续 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:409 | 错误/异常 | 检查更新失败，请稍后重试。 | 检查更新失败，请稍后重试。 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:232<br>Sources/OhMyUsage/Utils/Localization.swift:436 | 标签/标题 | 简体中文 | 简体中文 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:324 | 标签/标题 | 仅浏览器 | 仅浏览器 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:298 | 标签/标题 | 紧张 | 紧张 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:227 | 标签/标题 | 开启 | 开启 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:225 | 说明/提示 | 开启后仅保留核心项，接口路径与字段解析自动使用站点模板。 | 开启后仅保留核心项，接口路径与字段解析自动使用站点模板。 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:398 | 加载状态 | 开始扫描 | 开始扫描 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:364 | 标签/标题 | 看剩余 | 看剩余 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:365 | 标签/标题 | 看已用 | 看已用 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:310 | 标签/标题 | 来源模式 | 来源模式 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:239 | 按钮/操作 | 立即刷新 | 立即刷新 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:327 | 成功反馈 | 连接成功 | 连接成功 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:285 | 标签/标题 | 浏览器顺序 | 浏览器顺序 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:323 | 标签/标题 | 浏览器优先 | 浏览器优先 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:325 | 错误/异常 | 浏览器优先会在手动凭证过期或失效时自动尝试读取浏览器登录态；仅浏览器模式不会使用你手动保存的 Cookie 或 Token。 | 浏览器优先会在手动凭证失效时读取浏览器登录态；仅浏览器模式不会使用手动保存的 Cookie 或 Token。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:217 | 标签/标题 | 模型设置 | 模型设置 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:366 | 说明/提示 | 默认按“剩余”展示和提醒；如需按“已用”视角查看，可切到“看已用”。 | 默认按“剩余”展示和提醒；如需查看消耗进度，可切换为“看已用”。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:316 | 说明/提示 | 默认会自动发现本地 CLI 登录态；手动 Cookie 仅作为网页来源修复入口。 | 默认自动发现本地 CLI 登录态；手动 Cookie 仅用于修复网页来源。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:317 | 说明/提示 | 匹配模板 | 匹配模板 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:226 | 标签/标题 | 启用 | 启用 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:262 | 标签/标题 | 启用 Token 配额通道 | 启用 Token 配额通道 | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:263 | 标签/标题 | 启用账户余额通道 | 启用账户余额通道 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:286 | 加载状态 | 启用自动读取浏览器 Cookie | 启用自动读取浏览器 Cookie | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:350 | 错误/异常 | 切换失败 | 切换失败 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:392 | 按钮/操作 | 清理本地配置、账号槽位、首次安装引导和 oh-myusage 钥匙串内容，用于恢复到接近初装状态。系统通知、全盘访问等 macOS 授权仍需你在系统设置里手动关闭 | 清理本地配置、账号槽位、首次安装引导和 oh-myusage 钥匙串内容，恢复到接近初装状态。系统通知、全盘访问等 macOS 授权仍需手动关闭。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:309 | 说明/提示 | 请先在左侧选择模型 | 请先从左侧选择模型。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:387 | 按钮/操作 | 取消 | 取消 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:381 | 标签/标题 | 全盘访问 | 全盘访问 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:367 | 标签/标题 | 权限与自动发现 | 权限与自动发现 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:399 | 加载状态 | 确认后会尝试读取本机已有的 CLI/浏览器登录态，并直接请求对应官方/API 站点来抓取余额或额度。 | 确认后会尝试读取本机已有的 CLI/浏览器登录态，并直接请求对应官方/API 站点来抓取余额或额度。 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:378 | 按钮/操作 | 确认后会初始化 oh-myusage 的钥匙串存储，用来安全保存你手动录入的 Cookie、Token 和 API Key。 | 确认后会初始化 oh-myusage 的钥匙串存储，用来安全保存你手动录入的 Cookie、Token 和 API Key。 | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:373 | 错误/异常 | 确认后会弹出 macOS 通知授权窗口，用于发送低额度、鉴权失效和连接失败提醒。 | 确认后会弹出 macOS 通知授权窗口，用于发送低额度、鉴权失效和连接失败提醒。 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:394 | 按钮/操作 | 确认后会清理本地配置、Codex 账号槽位、启动项和 oh-myusage 的钥匙串内容。应用会恢复成接近首次安装状态；系统通知、全盘访问等 macOS 授权不会被自动撤销。 | 确认后会清理本地配置、Codex 账号槽位、启动项和 oh-myusage 的钥匙串内容。应用会恢复成接近首次安装状态；系统通知、全盘访问等 macOS 授权不会被自动撤销。 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:384 | 加载状态 | 确认后会跳转到“隐私与安全性 -> 全盘访问”，方便你授权 oh-myusage 读取浏览器 Cookie 和本地 CLI 登录文件。 | 确认后会跳转到“隐私与安全性 > 全盘访问”，方便你授权 oh-myusage 读取浏览器 Cookie 和本地 CLI 登录文件。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:267 | 标签/标题 | 认证 Header | 认证 Header | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:253 | 错误/异常 | 认证错误 | 认证失败 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:320 | 标签/标题 | 认证来源 | 认证来源 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:276 | 标签/标题 | 认证模式 | 认证模式 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:268 | 标签/标题 | 认证前缀 | 认证前缀 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:684 | 加载状态 | 扫描到 \(joined) ，自动添加到监控 | 扫描到 \(joined) ，自动添加到监控 | 可保留，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:358 | 按钮/操作 | 删除 | 删除 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:359 | 按钮/操作 | 删除 Codex 账号 | 删除 Codex 账号 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:360 | 按钮/操作 | 删除后将移除该账号保存的 auth.json，本机当前已登录状态不会立刻受影响。 | 删除后会移除该账号保存的 auth.json，不会立即退出本机当前登录。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:248 | 标签/标题 | 上限 | 上限 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:272 | 标签/标题 | 上限字段路径 | 上限字段路径 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:215 | 标签/标题 | 设置 | 设置 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:214 | 标签/标题 | 设置... | 设置… | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:246 | 标签/标题 | 剩余 | 剩余 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:270 | 标签/标题 | 剩余字段路径 | 剩余字段路径 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:236 | 标签/标题 | 失联 | 连接异常 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:315 | 标签/标题 | 手动 Cookie/Header | 手动 Cookie/Header | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:322 | 标签/标题 | 手动优先 | 手动优先 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:372 | 按钮/操作 | 授权通知 | 授权通知 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:223 | 标签/标题 | 数据源 | 数据源 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:220 | 标签/标题 | 通用 | 通用 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:216 | 标签/标题 | 通用设置 | 通用设置 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:240 | 按钮/操作 | 退出 | 退出 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:219 | 标签/标题 | 完成 | 完成 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:311 | 标签/标题 | 网页来源 | 网页来源 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:245 | 空状态 | 未配置 | 未配置 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:357 | 空状态 | 未识别邮箱 | 未识别邮箱 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:282 | 空状态 | 未找到可用的 Kimi 登录 Cookie | 未找到可用的 Kimi 登录 Cookie | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:370 | 标签/标题 | 系统通知 | 系统通知 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:412 | 加载状态 | 下载最新安装包 | 下载最新安装包 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:368 | 按钮/操作 | 先说明用途，再由你确认是否发起系统授权。 | 每项授权都会先说明用途，再由你确认是否发起。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:294 | 标签/标题 | 限额紧张 | 额度偏低 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:355 | 标签/标题 | 详情 | 详情 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:404 | 标签/标题 | 项目主页 | 项目主页 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:255 | 标签/标题 | 新增 API用量 | 新增 API 用量 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:380 | 错误/异常 | 钥匙串存储初始化失败，请稍后重试。 | 钥匙串存储初始化失败，请稍后重试。 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:379 | 成功反馈 | 钥匙串存储已就绪。 | 钥匙串存储已就绪。 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:375 | 标签/标题 | 钥匙串机密信息 | 钥匙串机密信息 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:259 | 标签/标题 | 移除 | 移除 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:385 | 按钮/操作 | 已打开系统的全盘访问设置页。 | 已打开系统的全盘访问设置页。 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:374 | 按钮/操作 | 已发起系统通知授权请求。 | 已发起系统通知授权请求。 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:281 | 标签/标题 | 已检测到 | 已检测到 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:352 | 成功反馈 | 已切换，但 Codex 桌面端重启未完成，请手动重开 | 已切换，但 Codex 桌面端重启未完成，请手动重开 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:348 | 成功反馈 | 已切换，可直接使用 | 已切换，可直接使用 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:349 | 成功反馈 | 已切换到该账号，但需要重新验证 | 已切换到该账号，但需要重新验证 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:408 | 标签/标题 | 已是最新版本（当前 %@，最新 %@） | 已是最新版本（当前 %@，最新 %@） | 可保留，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:351 | 说明/提示 | 已写入本机登录，请重开 Codex 桌面端 | 已写入本机登录，请重开 Codex 桌面端 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:271 | 标签/标题 | 已用字段路径 | 已用字段路径 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:301 | 按钮/操作 | 已重置，可切换 | 已重置，可切换账号 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:266 | 标签/标题 | 用户 Header | 用户 Header | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:376 | 按钮/操作 | 用于把你手动保存的 Cookie、Token 和 API Key 安全地保存在 macOS 钥匙串里 | 用于将手动保存的 Cookie、Token 和 API Key 安全存入 macOS 钥匙串。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:371 | 错误/异常 | 用于低额度、鉴权失效和连接失败提醒 | 用于低额度、鉴权失效和连接失败提醒。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:382 | 加载状态 | 用于读取浏览器 Cookie 数据库和本地 CLI/ auth 文件，提升自动识别成功率 | 用于读取浏览器 Cookie 数据库和本地 CLI/auth 文件，提高自动识别成功率。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:319 | 标签/标题 | 优先使用预置项；只有通用 NewAPI 场景或站点接口不一致时，再改 Base URL 或展开高级设置。 | 优先使用预置模板；仅当站点接口不一致时，再修改 Base URL 或展开高级设置。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:295 | 标签/标题 | 余额充足 | 余额充足 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:297 | 标签/标题 | 余额耗尽 | 余额已耗尽 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:269 | 标签/标题 | 余额接口路径 | 余额接口路径 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:296 | 标签/标题 | 余额紧张 | 余额偏低 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:397 | 加载状态 | 在授权完成后，自动尝试读取本机已有登录态并抓取可用模型的余额/额度 | 授权完成后，自动读取本机已有登录态，并抓取可用模型的余额或额度。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:330 | 标签/标题 | 在状态栏展示该模型 | 在菜单栏展示该模型 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:401 | 空状态 | 暂时没有发现可直接读取的本机模型登录态。 | 暂未发现可读取的本机模型登录态。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:230 | 空状态 | 暂无启用的数据源，请在设置中开启 | 暂无启用的数据源，请前往设置开启。 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:279 | 说明/提示 | 粘贴 kimi-auth Token | 粘贴 kimi-auth Token | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:242 | 说明/提示 | 粘贴 Token | 粘贴 Token | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:354 | 按钮/操作 | 粘贴该账号完整 auth.json 内容。切换时会写回本机 Codex 当前登录，并立即做一次轻量校验。 | 粘贴该账号完整 auth.json。切换时会写回本机 Codex 登录，并执行轻量校验。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:264 | 说明/提示 | 粘贴系统访问令牌 | 粘贴系统访问令牌 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:335 | 标签/标题 | 展示样式 | 展示样式 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:318 | 说明/提示 | 站点模板 | 站点模板 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:339 | 标签/标题 | 账号 A | 账号 A | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:340 | 标签/标题 | 账号 B | 账号 B | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:343 | 成功反馈 | 账号档案已导入 | 账号档案已导入 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:234 | 标签/标题 | 正常 | 正常 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:407 | 加载状态 | 正在检查更新... | 正在检查更新… | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:400 | 加载状态 | 正在扫描本机已登录模型... | 正在扫描本机已登录模型… | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:249 | 按钮/操作 | 重置于 | 重置于 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:287 | 标签/标题 | 周配额 | 周额度 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:337 | 标签/标题 | 柱状图+文字 | 柱状图 + 文字 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:313 | 按钮/操作 | 自动导入 | 自动导入 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:283 | 加载状态 | 自动读取浏览器 Cookie 需要 Full Disk Access 权限。 | 自动读取浏览器 Cookie 需要全盘访问权限。 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:280 | 标签/标题 | 自动检测 Token | 自动检测 Token | 可保留，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:353 | 按钮/操作 | 最近导入 | 最近导入 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:237 | 标签/标题 | 最近更新 | 最近更新 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:411 | 标签/标题 | 最新 %@（当前 %@） | 最新 %@（当前 %@） | 可保留，保留动态变量 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:212 | 标签/标题 | AI Plan 监控 | oh-myusage | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:304 | 标签/标题 | API用量 | API 用量 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:224 | 标签/标题 | API用量极简配置（推荐） | API 用量极简配置（推荐） | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:306 | 标签/标题 | API用量预置项 | API 用量预置项 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:308 | 标签/标题 | API余额 | API 余额 | 建议替换 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:341 | 标签/标题 | auth.json 内容 | auth.JSON 内容 | 建议替换，保留必要技术名 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:338 | 标签/标题 | Codex 账号档案 | Codex 账号档案 | 可保留 |
| 全局本地化 | Sources/OhMyUsage/Utils/Localization.swift:254 | 错误/异常 | Token 无效或已过期 | Token 无效或已过期 | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:998 | 标签/标题 | \(compact) 次 | \(compact) 次 | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:937 | 标签/标题 | \(header) 值 | \(header) 值 | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:996 | 标签/标题 | \(number) \(last)次 | \(number) \(last)次 | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:227 | 标签/标题 | 10分钟 | 10 分钟 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:228 | 标签/标题 | 15分钟 | 15 分钟 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:271 | 标签/标题 | 15秒 | 15 秒 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:273 | 标签/标题 | 1分钟 | 1 分钟 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:402<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:688 | 标签/标题 | 24小时趋势 | 24 小时趋势 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:272 | 标签/标题 | 30秒 | 30 秒 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:225 | 标签/标题 | 3分钟 | 3 分钟 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:226<br>Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:274 | 标签/标题 | 5分钟 | 5 分钟 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:473<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:779 | 标签/标题 | 7天趋势 | 7 天趋势 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:628 | 标签/标题 | 按账号 | 按账号 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:60 | 加载状态 | 把监控、权限和服务配置收拢成一个可快速扫描的工作台。 | 把监控、权限和服务配置收拢成一个可快速扫描的工作台。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:90<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:413 | 标签/标题 | 百分比 | 百分比 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:128<br>Sources/OhMyUsage/Utils/Localization.swift:403 | 标签/标题 | 版本 | 版本 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:397<br>Sources/OhMyUsage/Utils/Localization.swift:243 | 按钮/操作 | 保存 | 保存 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:963 | 按钮/操作 | 保存 \(header) | 保存 \(header) | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:961 | 按钮/操作 | 保存 Access Token | 保存 Access Token | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:959 | 按钮/操作 | 保存 Cookie | 保存 Cookie | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:382 | 按钮/操作 | 保存名称 | 保存名称 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:347 | 按钮/操作 | 保存站点 | 保存站点 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:106 | 说明/提示 | 备注会显示在菜单栏模型卡片上，建议使用简短易辨识的名称 | 备注会显示在菜单栏模型卡片上，建议使用简短、易识别的名称。 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:98 | 标签/标题 | 备注名称 | 备注名称 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:88 | 标签/标题 | 本地数据 | 本地数据 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:234 | 标签/标题 | 本机 Claude 账号 | 本机 Claude 账号 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:319 | 标签/标题 | 本机\(displayName)账号 | 本机\(displayName)账号 | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:209 | 标签/标题 | 本机Codex账号 | 本机 Codex 账号 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:670 | 标签/标题 | 编辑 | 编辑 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:258 | 标签/标题 | 编辑 \(editor.title) 凭证 | 编辑 \(editor.title) 凭证 | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:402 | 标签/标题 | 编辑 \(editor.title) auth.json | 编辑 \(editor.title) auth.JSON | 建议替换，保留必要技术名，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:213<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:276 | 标签/标题 | 编辑名称 | 编辑名称 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:70<br>Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:152 | 标签/标题 | 菜单栏 | 菜单栏 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:437 | 按钮/操作 | 菜单栏当前展示的服务按此频率刷新。 | 菜单栏当前展示的服务按此频率刷新。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:945 | 标签/标题 | 菜单栏显示 | 菜单栏显示 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:244<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:343 | 按钮/操作 | 测试链接 | 测试连接 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:655 | 按钮/操作 | 从浏览器导入 | 从浏览器导入 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:1091 | 标签/标题 | 从左侧选择一个来源后，这里会显示完整配置。 | 从左侧选择一个来源后，这里会显示完整配置。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:311 | 按钮/操作 | 打开设置 | 打开设置 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:566 | 标签/标题 | 单位 = \(unit) | 单位 = \(unit) | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:160 | 标签/标题 | 当前菜单栏展示：\(title) | 当前菜单栏展示：\(title) | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:388 | 标签/标题 | 当前连接状态 | 当前连接状态 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:537 | 说明/提示 | 当前模板 \`\(manifest.displayName)\` 的核心必填项：\(joined)。名称可自定义。 | 当前模板 \`\(manifest.displayName)\` 的核心必填项：\(joined)。可自定义名称。 | 建议替换，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:535 | 说明/提示 | 当前模板 \`\(manifest.displayName)\` 的接口配置已固定，名称可自定义。 | 当前模板 \`\(manifest.displayName)\` 的接口配置已固定，可自定义名称。 | 建议替换，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1368<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1370 | 标签/标题 | 当前目录 | 当前目录 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1444<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1453<br>Sources/OhMyUsage/Utils/Localization.swift:346 | 标签/标题 | 当前账号 | 当前账号 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:321 | 按钮/操作 | 导入另一个 Claude | 导入另一个 Claude | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:217 | 按钮/操作 | 导入另一个Codex | 导入另一个 Codex | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:72 | 标签/标题 | 调整菜单栏里显示哪些模型、如何显示以及跟随哪种外观。 | 调整菜单栏里显示哪些模型、如何显示以及跟随哪种外观。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:175 | 加载状态 | 读取趋势中... | 正在读取趋势… | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:454 | 标签/标题 | 多模展示 | 多模展示 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:90 | 标签/标题 | 发现本地 CLI 账号配置，或在需要时清理本地应用数据。 | 发现本地 CLI 账号配置，或在需要时清理本地应用数据。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:1010 | 标签/标题 | 访问令牌 | 访问令牌 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:15 | 标签/标题 | 刚刚 | 刚刚 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:329 | 标签/标题 | 个人设置中的User ID | 个人设置中的 User ID | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:482 | 标签/标题 | 根据壁纸自动选择清晰易读的显示外观 | 根据壁纸自动选择清晰易读的显示外观 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:102 | 标签/标题 | 更新于 -- | 更新于 -- | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:551 | 标签/标题 | 固定地址 = \(suggestedBaseURL) | 固定地址 = \(suggestedBaseURL) | 可保留，保留动态变量 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:663<br>Sources/OhMyUsage/Utils/Localization.swift:228<br>Sources/OhMyUsage/Utils/Localization.swift:312 | 标签/标题 | 关闭 | 关闭 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:101 | 标签/标题 | 关键信息 | 关键信息 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:157<br>Sources/OhMyUsage/Utils/Localization.swift:307 | 标签/标题 | 官方订阅 | 官方订阅 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:359<br>Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:94 | 标签/标题 | 官方服务 | 官方服务 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:381 | 标签/标题 | 官方服务使用趋势 | 官方服务使用趋势 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:96 | 标签/标题 | 管理 Codex、Claude、Gemini、Cursor 等官方来源和账号。 | 管理 Codex、Claude、Gemini、Cursor 等官方来源和账号。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:66 | 标签/标题 | 管理应用语言、启动行为和基础偏好。 | 管理应用语言、启动行为和基础偏好。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:1010 | 标签/标题 | 后台 | 后台 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:443 | 按钮/操作 | 后台刷新 | 后台刷新 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:78 | 说明/提示 | 汇总本地服务、模型和供应商的请求与 Token 使用趋势。 | 汇总本地服务、模型和供应商的请求与 Token 使用趋势。 | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:400 | 按钮/操作 | 获取说明：登录 trae.ai 后打开开发者工具 Network，刷新页面，复制 /trae/api/v1/pay/ide_user_ent_usage 请求头 Authorization（Cloud-IDE-JWT ...）粘贴到上方。 | 获取说明：登录 trae.ai 后打开开发者工具 Network，刷新页面，复制 /trae/api/v1/pay/ide_user_ent_usage 请求头 Authorization（Cloud-IDE-JWT …）粘贴到上方。 | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:189 | 标签/标题 | 基础状态 | 基础状态 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:127 | 标签/标题 | 监控与设置工作台 | 监控与设置工作台 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:84 | 加载状态 | 检查授权状态，确保通知、钥匙串和本地读取能力可用。 | 检查授权状态，确保通知、钥匙串和本地读取能力可用。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:336<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:931 | 标签/标题 | 今日 | 今日 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:386 | 标签/标题 | 仅汇总已启用的官方服务，本地趋势不等同于官方剩余额度。 | 仅汇总已启用的官方服务，本地趋势不等同于官方剩余额度。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:350<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:943 | 标签/标题 | 近30日 | 近 30 日 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1167 | 标签/标题 | 近似 | 近似 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:422<br>Sources/OhMyUsage/Utils/Localization.swift:221 | 标签/标题 | 开机启动 | 登录时启动 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:459 | 空状态 | 开启后菜单栏展示多个模型监控，过多的展示可能挤压菜单栏空间 | 开启后菜单栏展示多个模型监控，过多的展示可能挤压菜单栏空间 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:427 | 说明/提示 | 开启后会把 oh-myusage 注册为登录项。建议安装到“应用程序”后再启用 | 开启后会把 oh-myusage 注册为登录项。建议安装到“应用程序”后再启用 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:979 | 按钮/操作 | 可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制 \(header) 的值。 | 可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制 \(header) 的值。 | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:975 | 按钮/操作 | 可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制 Authorization 的 Bearer 值。 | 可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制 Authorization 的 Bearer 值。 | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:971 | 按钮/操作 | 可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制完整 Cookie。 | 可在浏览器开发者工具的 Network 中打开对应请求，在 Request Headers 里复制完整 Cookie。 | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:115 | 按钮/操作 | 快来添加你的第一个代理中转站点吧～ | 快来添加你的第一个代理中转站点吧～ | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:220<br>Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:245<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:961 | 按钮/操作 | 快来添加你的第一个账号吧～ | 添加第一个账号后即可开始监控。 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:71 | 标签/标题 | 来源 | 来源 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:106 | 标签/标题 | 来源：\(sourceValue)｜\(freshnessText) | 来源：\(sourceValue)｜\(freshnessText) | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:117 | 按钮/操作 | 立即刷新所有已启用服务 | 立即刷新所有已启用服务 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:119 | 标签/标题 | 例如公司账号/工作/个人 | 例如：公司账号 / 工作 / 个人 | 建议替换 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:422<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:178<br>Sources/OhMyUsage/Utils/Localization.swift:328 | 错误/异常 | 连接失败 | 连接失败 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:683 | 标签/标题 | 连接状态 | 连接状态 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:534<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:352<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:1118 | 成功反馈 | 链接成功接口正常 | 连接成功，接口正常 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:323 | 错误/异常 | 浏览器回调失败，已自动回退到 Device Code 登录。 | 浏览器回调失败，已切换为 Device Code 登录。 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:173<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:308 | 错误/异常 | 浏览器优先会在手动凭证失效时自动读取浏览器登录态；仅浏览器模式只使用浏览器登录态，不使用手动保存的 Cookie 或 Token。 | 浏览器优先会在手动凭证失效时自动读取浏览器登录态；仅浏览器模式只使用浏览器登录态，不使用手动保存的 Cookie 或 Token。 | 可保留，保留必要技术名 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:520<br>Sources/OhMyUsage/Utils/Localization.swift:256 | 标签/标题 | 名称 | 名称 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:699 | 加载状态 | 默认按顺序自动读取 COPILOT_GITHUB_TOKEN、GH_TOKEN、GITHUB_TOKEN、Copilot CLI 钥匙串与 GitHub CLI 登录态；当前仅支持 API 检测。 | 默认按顺序自动读取 COPILOT_GITHUB_TOKEN、GH_TOKEN、GITHUB_TOKEN、Copilot CLI 钥匙串与 GitHub CLI 登录态；当前仅支持 API 检测。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:723 | 按钮/操作 | 默认从浏览器自动导入 ollama.com 的 __Secure-session Cookie，也可切到手动模式粘贴。 | 默认从浏览器自动导入 ollama.com 的 __Secure-session Cookie，也可切到手动模式粘贴。 | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:693 | 错误/异常 | 默认会自动发现本地 CLI 或 Kiro IDE 登录态；当 CLI 不可用时会回退读取 IDE 缓存。 | 默认会自动发现本地 CLI 或 Kiro IDE 登录态；当 CLI 不可用时会回退读取 IDE 缓存。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1385<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1438 | 说明/提示 | 默认目录 | 默认目录 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1382 | 说明/提示 | 默认目录 (~/.claude/projects) | 默认目录 (~/.claude/projects) | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:231 | 标签/标题 | 目录 | 目录 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:366 | 标签/标题 | 目录绑定 | 目录绑定 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:950 | 标签/标题 | 配额 \(fieldName) | 配额 \(fieldName) | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:521<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:997<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:268 | 标签/标题 | 配置 | 配置 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:102 | 标签/标题 | 配置 Relay、New API 和第三方余额接口。 | 配置 Relay、New API 和第三方余额接口。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1157 | 标签/标题 | 匹配事件 \(formattedSettingsInteger(diagnostics.matchedRows)) 条 · 可归属 \(formattedSettingsInteger(diagnostics.attributableEvents)) 条 · 会话回填 \(recoveredResponses) 条/\(recoveredTokens) Token · 未归属 \(unattributedResponses) 条/\(unattributedTokens) Token · 最近事件 \(latestText) · 口径 \(modeText) | 匹配事件 \(formattedSettingsInteger(diagnostics.matchedRows)) 条 · 可归属 \(formattedSettingsInteger(diagnostics.attributableEvents)) 条 · 会话回填 \(recoveredResponses) 条/\(recoveredTokens) Token · 未归属 \(unattributedResponses) 条/\(unattributedTokens) Token · 最近事件 \(latestText) · 口径 \(modeText) | 可保留，保留必要技术名，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:721<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:179<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:314 | 标签/标题 | 凭证 | 凭证 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:157<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:296<br>Sources/OhMyUsage/Utils/Localization.swift:321 | 标签/标题 | 凭证模式 | 凭证模式 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:362<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:429<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:932<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:934 | 标签/标题 | 凭证信息 | 凭证信息 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:304<br>Sources/OhMyUsage/Utils/Localization.swift:377 | 标签/标题 | 启用钥匙串 | 启用钥匙串 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:432 | 按钮/操作 | 前台刷新 | 前台刷新 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:106<br>Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:168 | 说明/提示 | 请我喝咖啡 | 请我喝咖啡 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:289<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1033 | 说明/提示 | 请选择账号 | 请选择账号 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:321 | 按钮/操作 | 请在浏览器完成授权，完成后将自动导入本地账号 | 请在浏览器完成授权，完成后将自动导入本地账号。 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:304<br>Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:311 | 按钮/操作 | 取消授权 | 取消授权 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:265<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:627 | 标签/标题 | 全量 | 全量 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:82 | 标签/标题 | 权限 | 权限 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOverlayPresenter.swift:35 | 按钮/操作 | 确认后会清理本地配置、Codex 账号槽位、启动项和 oh-myusage 的钥匙串内容。应用会恢复成接近首次安装状态；系统通知、全盘访问等 macOS 授权不会被自动撤销 | 确认后会清理本地配置、Codex 账号槽位、启动项和 oh-myusage 的钥匙串内容。应用会恢复成接近首次安装状态；系统通知、全盘访问等 macOS 授权不会被自动撤销 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:89<br>Sources/OhMyUsage/Utils/Localization.swift:361 | 按钮/操作 | 确认删除 | 确认删除 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:416<br>Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:381<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:172 | 标签/标题 | 认证故障 | 认证故障 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:268 | 按钮/操作 | 如果 oh-myusage 帮到了你，可以请我喝杯咖啡，或者随手赞赏支持一下继续维护 | 如果 oh-myusage 帮到了你，可以请我喝杯咖啡，或者随手赞赏支持一下继续维护 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:108 | 按钮/操作 | 如果 oh-myusage 帮到了你，可以请我喝杯咖啡，或者随手赞赏支持一下继续维护。 | 如果 oh-myusage 帮到了你，可以请我喝杯咖啡，或者随手赞赏支持一下继续维护。 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:284<br>Sources/OhMyUsage/Utils/Localization.swift:396 | 加载状态 | 扫描本地已登录模型 | 扫描本地已登录模型 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:278 | 加载状态 | 扫描中··· | 扫描中··· | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:78 | 按钮/操作 | 删除 Claude 账号 | 删除 Claude 账号 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:99 | 按钮/操作 | 删除后将移除该账号保存的凭证与目录配置，本机当前 Claude 登录态不会立刻受影响。 | 删除后会移除该账号保存的凭证与目录配置，不会立即退出本机当前 Claude 登录。 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:553<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:620 | 按钮/操作 | 删除站点 | 删除站点 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:674 | 按钮/操作 | 删除账号 | 删除账号 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:563 | 标签/标题 | 上限 = \(limit) | 上限 = \(limit) | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:58 | 标签/标题 | 设置概览 | 设置概览 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:299 | 按钮/操作 | 申请授权 | 申请授权 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:556 | 标签/标题 | 剩余 = \(manifest.extract.remaining) | 剩余 = \(manifest.extract.remaining) | 可保留，保留动态变量 |
| 设置页 / 使用统计 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:117<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:89 | 标签/标题 | 使用趋势 | 使用趋势 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:76<br>Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:142 | 标签/标题 | 使用统计 | 使用统计 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:667<br>Sources/OhMyUsage/Utils/Localization.swift:277<br>Sources/OhMyUsage/Utils/Localization.swift:314 | 标签/标题 | 手动 | 手动 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:368 | 说明/提示 | 手动粘贴 | 手动粘贴 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1204 | 标签/标题 | 数据来源：本地 ~/.claude/projects + 已绑定 CLAUDE_CONFIG_DIR/projects（仅本地 Token，不等价于官方剩余额度） | 数据来源：本地 ~/.claude/projects + 已绑定 CLAUDE_CONFIG_DIR/projects（仅本地 Token，不等价于官方剩余额度） | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1198 | 标签/标题 | 数据来源：本地 ~/.codex/logs_2.sqlite（当前账号可归属事件；缺失身份会按会话回填，仍无法归属会单独提示，仅本地 Token，不等价于官方剩余额度） | 数据来源：本地 ~/.codex/logs_2.sqlite（当前账号可归属事件；缺失身份会按会话回填，仍无法归属会单独提示，仅本地 Token，不等价于官方剩余额度） | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1193 | 标签/标题 | 数据来源：本地 ~/.codex/sessions（仅本地 Token，不等价于官方剩余额度） | 数据来源：本地 ~/.codex/sessions（仅本地 Token，不等价于官方剩余额度） | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1219 | 标签/标题 | 数据来源：本地 ~/.gemini（当前未发现稳定 token 事件流，后续补齐） | 数据来源：本地 ~/.gemini（当前未发现稳定 token 事件流，后续补齐） | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1214 | 标签/标题 | 数据来源：本地 ~/.kimi/sessions/**/wire.jsonl（仅本地 Token，不等价于官方剩余额度） | 数据来源：本地 ~/.kimi/sessions/**/wire.JSONl（仅本地 Token，不等价于官方剩余额度） | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1224 | 标签/标题 | 数据来源：本地日志（仅本地 Token） | 数据来源：本地日志（仅本地 Token） | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1209 | 错误/异常 | 数据来源：当前账号 CLAUDE_CONFIG_DIR/projects（目录不可用时回退 ~/.claude/projects，仅本地 Token） | 数据来源：当前账号 CLAUDE_CONFIG_DIR/projects（目录不可用时回退 ~/.claude/projects，仅本地 Token） | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:406 | 标签/标题 | 数据状态 | 数据状态 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:91<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:415 | 标签/标题 | 数字 | 数字 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:116 | 按钮/操作 | 刷新全部 | 刷新全部 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:941 | 标签/标题 | 套餐信息 | 套餐信息 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:678<br>Sources/OhMyUsage/Utils/Localization.swift:258 | 按钮/操作 | 添加 | 添加 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:258 | 按钮/操作 | 添加 \(editor.title) 凭证 | 添加 \(editor.title) 凭证 | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:402 | 按钮/操作 | 添加 \(editor.title) auth.json | 添加 \(editor.title) auth.JSON | 建议替换，保留必要技术名，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:1227<br>Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:120 | 按钮/操作 | 添加 NewAPI 站点 | 添加 NewAPI 站点 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:147<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:284 | 说明/提示 | 填写站点访问地址 | 填写站点访问地址 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:137<br>Sources/OhMyUsage/Utils/Localization.swift:336 | 标签/标题 | 图标+百分比 | 图标 + 百分比 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:1332<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:1333 | 标签/标题 | 拖拽排序 | 拖拽排序 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:994 | 标签/标题 | 万 | 万 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:105 | 标签/标题 | 网页 | 网页 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:272 | 标签/标题 | 微信赞赏二维码 | 微信赞赏二维码 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:290<br>Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:186 | 空状态 | 未识别账号 | 未识别账号 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:292 | 按钮/操作 | 未授权 | 未授权 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:448 | 按钮/操作 | 未显示在菜单栏的服务按此频率刷新。 | 未显示在菜单栏的服务按此频率刷新。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:414<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:170<br>Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:103 | 标签/标题 | 未知 | 未知 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOverlayPresenter.swift:37 | 标签/标题 | 我再想想 | 我再想想 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1175 | 标签/标题 | 无 | 无 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:87 | 标签/标题 | 显示 | 显示 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:937 | 标签/标题 | 显示邮箱 | 显示邮箱 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:420<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:176 | 标签/标题 | 限流 | 限流 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:39 | 标签/标题 | 详细数据 | 详细数据 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:418<br>Sources/OhMyUsage/Utils/Localization.swift:231 | 标签/标题 | 选择语言 | 界面语言 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1165 | 标签/标题 | 严格 | 严格 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:470 | 标签/标题 | 已消耗 | 已消耗 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:545<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:612<br>Sources/OhMyUsage/Utils/Localization.swift:247 | 标签/标题 | 已用 | 已用 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:560 | 标签/标题 | 已用 = \(used) | 已用 = \(used) | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:571 | 说明/提示 | 以下内容由模板固定：\(joined)。如需改接口或字段映射，再展开高级设置。 | 以下内容由模板固定：\(joined)。如需修改接口或字段映射，请展开高级设置。 | 建议替换，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:994 | 标签/标题 | 亿 | 亿 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsRelayTemplateSupport.swift:528<br>Sources/OhMyUsage/Utils/Localization.swift:265 | 标签/标题 | 用户 ID | 用户 ID | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:122<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:228<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:460<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:877 | 标签/标题 | 用量 | 用量 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:596<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:846<br>Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:109<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:130<br>另 2 处 | 标签/标题 | 用量偏好 | 用量偏好 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:406 | 标签/标题 | 用量显示 | 用量显示 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:335 | 标签/标题 | 有效期至 \(trimmed) (UTC) | 有效期至 \(trimmed)（UTC） | 建议替换，保留动态变量 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:463<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:539<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:606<br>Sources/OhMyUsage/Utils/Localization.swift:303 | 标签/标题 | 余额 | 余额 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:950 | 标签/标题 | 余额 \(fieldName) | 余额 \(fieldName) | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:953<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:364 | 标签/标题 | 余额阈值 | 余额阈值 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:418 | 标签/标题 | 预览: 剩余 \(remaining)\(unit) / 已用 \(used)\(unit) / 上限 \(limit)\(unit) | 预览：剩余 \(remaining)\(unit) / 已用 \(used)\(unit) / 上限 \(limit)\(unit) | 建议替换，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:261 | 空状态 | 暂无可识别的模型，请手动添加或再次尝试 | 暂无可识别的模型，请手动添加或再次尝试 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:314<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:338 | 空状态 | 暂无快照 | 暂无快照 | 可保留 |
| 设置页 / 使用统计 | Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:178<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:308 | 空状态 | 暂无趋势数据 | 暂无趋势数据 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:230<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:885 | 空状态 | 暂无用量信息 | 暂无用量信息 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:409 | 标签/标题 | 粘帖Access Token | 粘贴 Access Token | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:913 | 说明/提示 | 粘贴 \(normalizedHeader) 的值：\(normalizedScheme.isEmpty ? | 粘贴 \(normalizedHeader) 的值：\(normalizedScheme.isEmpty ? | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:438<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:695 | 说明/提示 | 粘贴 API Key | 粘贴 API Key | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:896 | 说明/提示 | 粘贴 Bearer Token，例如 Bearer eyJ... 或 eyJ... | 粘贴 Bearer Token，例如 Bearer eyJ… 或 eyJ… | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:371<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:700 | 说明/提示 | 粘贴 Cloud-IDE-JWT / JWT | 粘贴 Cloud-IDE-JWT / JWT | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:288<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:690 | 说明/提示 | 粘贴 wrk_... (必填) | 粘贴 wrk_… (必填) | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:879 | 说明/提示 | 粘贴完整 Cookie Header，例如 session=...; token=... | 粘贴完整 Cookie Header，例如 session=…; token=… | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:949 | 标签/标题 | 展示账号 | 展示账号 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:527<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:590 | 标签/标题 | 站点 | 站点 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:145<br>Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:282 | 标签/标题 | 站点地址 | 站点地址 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:897 | 说明/提示 | 这里填写 Authorization Bearer 值，带或不带 Bearer 前缀都可以。 | 填写 Authorization Bearer 值，可带 Bearer 前缀，也可只填 Token。 | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:880 | 说明/提示 | 这里填写完整 Cookie Header，不是单个字段。 | 填写完整 Cookie Header，不是单个字段。 | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:914 | 说明/提示 | 这里填写站点要求的自定义请求头值。 | 填写站点要求的自定义请求头值。 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:420 | 说明/提示 | 这里填写Access Token通过个人设置-安全设置-系统访问令牌, 生成令牌 | 在个人设置 > 安全设置 > 系统访问令牌中生成 Access Token，并粘贴到这里。 | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:325 | 加载状态 | 正在读取并校验本地凭据… | 正在读取并校验本地凭据… | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:319 | 加载状态 | 正在启动官方 CLI 登录流程… | 正在启动官方 CLI 登录流程… | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:469<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:501 | 加载状态 | 正在使用 | 正在使用 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:332 | 说明/提示 | 支持绑定 CLAUDE_CONFIG_DIR 目录，或手动粘贴完整 .credentials.json。 | 支持绑定 CLAUDE_CONFIG_DIR 目录，或手动粘贴完整 .credentials.json。 | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:216 | 加载状态 | 支持两种导入方式：绑定一个 CLAUDE_CONFIG_DIR 目录，或粘贴完整 .credentials.json。如果手动粘贴缺少 email，建议同时绑定目录读取 claude.json。切换时会同步写回系统默认 Claude 登录。 | 支持绑定 CLAUDE_CONFIG_DIR 目录，或粘贴完整 .credentials.json。若凭证缺少 email，建议同时绑定目录读取 claude.json；切换时会同步写回系统默认 Claude 登录。 | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:271 | 标签/标题 | 支付宝赞赏二维码 | 支付宝赞赏二维码 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:430<br>Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:445 | 标签/标题 | 指纹 \(fingerprint) | 指纹 \(fingerprint) | 可保留，保留动态变量 |
| 设置页 / 使用统计 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:162<br>Sources/OhMyUsageApplication/UsageAnalyticsAggregator.swift:63<br>Sources/OhMyUsageApplication/UsageAnalyticsAggregator.swift:72 | 标签/标题 | 中转代理 | 中转代理 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:387 | 说明/提示 | 重新粘贴json | 重新粘贴 JSON | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:143<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:389 | 标签/标题 | 重新OAuth | 重新 OAuth | 建议替换 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:211<br>Sources/OhMyUsage/Utils/Localization.swift:391 | 按钮/操作 | 重置本地数据 | 重置本地数据 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOverlayPresenter.swift:33 | 按钮/操作 | 重置本地应用数据 | 重置本地应用数据 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOverlayPresenter.swift:38 | 按钮/操作 | 重置数据 | 重置数据 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsPermissionAndLocalData.swift:215<br>Sources/OhMyUsage/Utils/Localization.swift:393 | 按钮/操作 | 重置所有数据 | 重置所有数据 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:899 | 标签/标题 | 周二 | 周二 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:903 | 标签/标题 | 周六 | 周六 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:900 | 标签/标题 | 周三 | 周三 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:901 | 标签/标题 | 周四 | 周四 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:904 | 标签/标题 | 周天 | 周天 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:902 | 标签/标题 | 周五 | 周五 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:898 | 标签/标题 | 周一 | 周一 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:194 | 标签/标题 | 主额度 | 主额度 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:146 | 标签/标题 | 柱状图+名称 | 柱状图 + 名称 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:397 | 标签/标题 | 抓取状态 | 抓取状态 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsViewShell.swift:360<br>Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:100 | 标签/标题 | 自定义接口 | 自定义接口 | 可保留 |
| 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:650<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:665<br>Sources/OhMyUsage/UI/Settings/SettingsProviderDetailSections.swift:166<br>Sources/OhMyUsage/Utils/Localization.swift:278 | 标签/标题 | 自动 | 自动 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:477 | 标签/标题 | 总额 | 总额 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift:131 | 按钮/操作 | 最近刷新 | 最近刷新 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayRuntimeStatus.swift:19 | 标签/标题 | 最近自动恢复：\(recovery.source)｜\(timeSuffix) | 最近自动恢复：\(recovery.source)｜\(timeSuffix) | 可保留，保留动态变量 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:343<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:935 | 标签/标题 | 昨日 | 昨日 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:327<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProviderConfiguration.swift:710 | 空状态 | auth=... (可选，自动导入可留空) | auth=… (可选，自动导入可留空) | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsRelayConfigurationForm.swift:316 | 标签/标题 | Authorization Bearer或者cookies | Authorization Bearer 或 Cookie | 建议替换，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:303 | 按钮/操作 | Claude OAuth 添加 | Claude OAuth 添加 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:301 | 按钮/操作 | Codex OAuth 添加 | Codex OAuth 添加 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:930 | 按钮/操作 | json添加 | JSON 添加 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:151<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:178 | 标签/标题 | NewAPI站点 | NewAPI 站点 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:327 | 成功反馈 | OAuth 导入成功。 | OAuth 导入成功。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:329 | 错误/异常 | OAuth 导入失败。 | OAuth 导入失败。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProfileDialogs.swift:331 | 按钮/操作 | OAuth 导入已取消。 | OAuth 导入已取消。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:236<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:340 | 按钮/操作 | OAuth 添加 | OAuth 添加 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:940 | 按钮/操作 | OAuth添加 | OAuth 添加 | 建议替换 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:717 | 加载状态 | OpenRouter API 使用普通 API Key，读取 /key 的 limit 与 remaining。 | OpenRouter API 使用普通 API Key，读取 /key 的 limit 与 remaining。 | 可保留，保留必要技术名 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:705 | 加载状态 | OpenRouter Credits 需要管理密钥（Management Key），用于读取 /credits 的总额度数据。 | OpenRouter Credits 需要管理密钥（Management Key），用于读取 /credits 的总额度数据。 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:202 | 标签/标题 | quotaWindows 明细 | quotaWindows 明细 | 可保留 |
| 设置页 | Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:711 | 按钮/操作 | Workspace ID 请从 opencode.ai 的 workspace URL 中复制 wrk_...；Cookie 可开启浏览器自动导入 auth，或手动粘贴。若远端接口 hash 变更，可用环境变量 OPENCODE_USAGE_ENDPOINT_ID 覆盖。 | Workspace ID 请从 opencode.ai 的 workspace URL 中复制 wrk_…；Cookie 可开启浏览器自动导入 auth，或手动粘贴。若远端接口 hash 变更，可用环境变量 OPENCODE_USAGE_ENDPOINT_ID 覆盖。 | 建议替换，保留必要技术名 |
| 使用统计 | Sources/OhMyUsageApplication/UsageAnalyticsTypes.swift:71 | 标签/标题 | 30天 | 30 天 | 建议替换 |
| 使用统计 | Sources/OhMyUsageApplication/UsageAnalyticsTypes.swift:70 | 标签/标题 | 7天 | 7 天 | 建议替换 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:271<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:630 | 成功反馈 | 成功率 | 成功率 | 可保留 |
| 使用统计 | Sources/OhMyUsageApplication/UsageAnalyticsAggregator.swift:220 | 标签/标题 | 多个来源 | 多个来源 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:228 | 标签/标题 | 供应商 | 供应商 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:270<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:365<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:629 | 标签/标题 | 缓存率 | 缓存率 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:268<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:363<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:627 | 标签/标题 | 缓存命中 | 缓存命中 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:269<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:364<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:628 | 标签/标题 | 缓存写入 | 缓存写入 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:249 | 标签/标题 | 近24小时 | 近 24 小时 | 建议替换 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:251 | 标签/标题 | 近30天 | 近30 天 | 建议替换 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:250 | 标签/标题 | 近7天 | 近7 天 | 建议替换 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:229 | 标签/标题 | 模型 | 模型 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:248<br>Sources/OhMyUsageApplication/UsageAnalyticsTypes.swift:72 | 标签/标题 | 全部 | 全部 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:264<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:362<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:626 | 标签/标题 | 输出 | 输出 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:263<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:361<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:625 | 标签/标题 | 输入 | 输入 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:74 | 按钮/操作 | 刷新使用统计 | 刷新使用统计 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:111 | 标签/标题 | 统计 | 统计 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:607 | 空状态 | 暂无匹配的使用数据 | 暂无匹配的使用数据 | 可保留 |
| 使用统计 / 全局本地化 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:83<br>Sources/OhMyUsage/Utils/Localization.swift:213 | 标签/标题 | 总览 | 总览 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:261 | 说明/提示 | 总请求 | 总请求 | 可保留 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:262<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:360<br>Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:624 | 标签/标题 | 总Token | 总 Token | 建议替换，保留必要技术名 |
| 使用统计 | Sources/OhMyUsageApplication/UsageAnalyticsTypes.swift:69 | 标签/标题 | 最近24小时 | 最近 24 小时 | 建议替换 |
| 使用统计 | Sources/OhMyUsage/Services/UsageAnalyticsRepository.swift:164 | 错误/异常 | Claude 本地日志读取失败：\(error.localizedDescription) | Claude 本地日志读取失败：\(error.localizedDescription) | 可保留，保留动态变量 |
| 使用统计 | Sources/OhMyUsage/Services/UsageAnalyticsRepository.swift:149 | 错误/异常 | Codex 本地日志读取失败：\(error.localizedDescription) | Codex 本地日志读取失败：\(error.localizedDescription) | 可保留，保留动态变量 |
| 使用统计 | Sources/OhMyUsageApplication/UsageAnalyticsAggregator.swift:70 | 标签/标题 | GPT 官方 | GPT 官方 | 可保留 |
| 使用统计 | Sources/OhMyUsage/Services/UsageAnalyticsRepository.swift:179 | 错误/异常 | Kimi 本地日志读取失败：\(error.localizedDescription) | Kimi 本地日志读取失败：\(error.localizedDescription) | 可保留，保留动态变量 |
| 使用统计 | Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift:717 | 标签/标题 | M月 | M月 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:114 | 标签/标题 | \(displayName) 使用趋势 | \(displayName) 使用趋势 | 可保留，保留动态变量 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:58 | 标签/标题 | \(officialProviderCount) 个官方来源，\(thirdPartyProviderCount) 个自定义来源 | \(officialProviderCount) 个官方来源，\(thirdPartyProviderCount) 个自定义来源 | 可保留，保留动态变量 |
| 应用界面 | Sources/OhMyUsage/App/AppViewModel+ProviderConfiguration.swift:566<br>Sources/OhMyUsage/App/AppViewModel.swift:530<br>Sources/OhMyUsage/App/AppViewModel.swift:542<br>Sources/OhMyUsage/App/AppViewModel.swift:558 | 错误/异常 | 保存失败 | 保存失败 | 可保留 |
| 应用界面 / 设置页 | Sources/OhMyUsage/UI/Presenters/LocalUsageTrendPresenter.swift:118<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:134 | 错误/异常 | 本地趋势数据源暂不可用 | 本地趋势数据源暂不可用 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:92 | 标签/标题 | 菜单栏外观 \(statusBarAppearanceModeSummary(statusBarAppearanceMode, localizedText: localizedText)) · 样式 \(statusBarDisplayStyleSummary(statusBarDisplayStyle, localizedText: localizedText)) | 菜单栏外观 \(statusBarAppearanceModeSummary(statusBarAppearanceMode, localizedText: localizedText)) · 样式 \(statusBarDisplayStyleSummary(statusBarDisplayStyle, localizedText: localizedText)) | 可保留，保留动态变量 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:90 | 标签/标题 | 单模型 | 单模型 | 可保留 |
| 应用界面 / 设置页 | Sources/OhMyUsage/App/AppViewModel.swift:616<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:570 | 标签/标题 | 当前套餐 | 当前套餐 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/LocalUsageTrendPresenter.swift:112 | 空状态 | 当前账号暂无可归属事件 | 当前账号暂无可归属事件 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/LocalUsageTrendPresenter.swift:106 | 空状态 | 当前账号暂无可归属事件（未归属 \(unattributedResponses) 条/\(unattributedTokens) Token） | 当前账号暂无可归属事件（未归属 \(unattributedResponses) 条/\(unattributedTokens) Token） | 可保留，保留必要技术名，保留动态变量 |
| 应用界面 | Sources/OhMyUsage/Models/ProviderMetadataCatalog.swift:120<br>Sources/OhMyUsage/Models/ProviderTypeMetadataCatalog.swift:36 | 标签/标题 | 第三方中转站 | 第三方中转站 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:89 | 标签/标题 | 多模型 | 多模型 | 可保留 |
| 应用界面 | Sources/OhMyUsage/App/AppViewModel+OfficialProfiles.swift:307 | 空状态 | 该槽位还没有导入可切换的 Claude 账号 | 该槽位还没有导入可切换的 Claude 账号 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:27 | 标签/标题 | 概览 | 概览 | 可保留 |
| 应用界面 / 设置页 / 全局本地化 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:188<br>Sources/OhMyUsage/UI/Settings/SettingsGeneralAndMenuBarSections.swift:473<br>Sources/OhMyUsage/Utils/Localization.swift:332 | 标签/标题 | 跟随壁纸 | 跟随壁纸 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:69 | 标签/标题 | 还有 \(disabledProviders) 个已停用 | 还有 \(disabledProviders) 个已停用 | 可保留，保留动态变量 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:60<br>Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:119 | 标签/标题 | 缓存回退 | 缓存回退 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/LocalUsageTrendPresenter.swift:163 | 标签/标题 | 缓存生成 \(refreshedText) · 图表生成 \(generatedText) | 缓存生成 \(refreshedText) · 图表生成 \(generatedText) | 可保留，保留动态变量 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/LocalUsageTrendPresenter.swift:155 | 标签/标题 | 缓存已校验 \(checkedText) · 图表生成 \(generatedText) | 缓存已校验 \(checkedText) · 图表生成 \(generatedText) | 可保留，保留动态变量 |
| 应用界面 / 设置页 | Sources/OhMyUsage/App/AppViewModel.swift:614<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:1169<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:320<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:553 | 标签/标题 | 会话 | 会话 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:66 | 标签/标题 | 活跃监控 | 活跃监控 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:39 | 标签/标题 | 活跃轮询任务 | 活跃轮询任务 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/LocalUsageTrendPresenter.swift:89 | 加载状态 | 加载中... | 加载中… | 建议替换 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:43 | 标签/标题 | 健康 | 健康 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:87 | 错误/异常 | 接口配置异常 | 接口配置异常 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:26<br>Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:85 | 标签/标题 | 接口限流 | 接口限流 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:81 | 标签/标题 | 接口正常 | 接口正常 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:87 | 标签/标题 | 界面与菜单栏 | 界面与菜单栏 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:64 | 标签/标题 | 进行中 · 已尝试 \(diagnostics.codexPrefetchAttemptedIdentityCount + diagnostics.claudePrefetchAttemptedIdentityCount) | 进行中 · 已尝试 \(diagnostics.codexPrefetchAttemptedIdentityCount + diagnostics.claudePrefetchAttemptedIdentityCount) | 可保留，保留动态变量 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:31 | 标签/标题 | 快照 | 快照 | 可保留 |
| 应用界面 / Provider 状态 / 设置页 | Sources/OhMyUsage/App/AppViewModel.swift:618<br>Sources/OhMyUsage/Providers/TraeProvider.swift:183<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:640 | 标签/标题 | 美元余额 | 美元余额 | 可保留 |
| 应用界面 / 设置页 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:24<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialProfileManagement.swift:418<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:174 | 错误/异常 | 配置异常 | 配置异常 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:56 | 错误/异常 | 配置异常(缓存) | 配置异常(缓存) | 可保留 |
| 应用界面 / 全局本地化 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:192<br>Sources/OhMyUsage/Utils/Localization.swift:334 | 标签/标题 | 浅色 | 浅色 | 可保留 |
| 应用界面 / 全局本地化 | Sources/OhMyUsage/App/AppViewModel.swift:627<br>Sources/OhMyUsage/Utils/Localization.swift:347 | 按钮/操作 | 切换 | 切换 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:70 | 标签/标题 | 全部服务都已启用 | 全部服务都已启用 | 可保留 |
| 应用界面 / 设置页 | Sources/OhMyUsage/App/AppViewModel.swift:611<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:398<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:454 | 标签/标题 | 全部模型 | 全部模型 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:76 | 标签/标题 | 权限状态 | 权限状态 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:22<br>Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:83 | 错误/异常 | 认证失效 | 认证失效 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:54 | 错误/异常 | 认证失效(缓存) | 认证失效(缓存) | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:126 | 按钮/操作 | 尚未刷新 | 尚未刷新 | 可保留 |
| 应用界面 / 全局本地化 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:190<br>Sources/OhMyUsage/Utils/Localization.swift:333 | 标签/标题 | 深色 | 深色 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:117 | 标签/标题 | 实时值 | 实时值 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:37 | 按钮/操作 | 刷新 | 刷新 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/LocalUsageTrendPresenter.swift:138 | 错误/异常 | 刷新失败，显示旧缓存：\(error) | 刷新失败，显示旧缓存：\(error) | 可保留，保留动态变量 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:79 | 标签/标题 | 通知、钥匙串与全盘访问统一收纳 | 通知、钥匙串与全盘访问统一收纳 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:202 | 标签/标题 | 图标 + 百分比 | 图标 + 百分比 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:58 | 标签/标题 | 限流回退 | 限流回退 | 可保留 |
| 应用界面 / 全局本地化 | Sources/OhMyUsage/App/AppViewModel+ProviderConfiguration.swift:565<br>Sources/OhMyUsage/App/AppViewModel.swift:529<br>Sources/OhMyUsage/App/AppViewModel.swift:541<br>Sources/OhMyUsage/App/AppViewModel.swift:557<br>另 1 处 | 成功反馈 | 已保存 | 已保存 | 可保留 |
| 应用界面 | Sources/OhMyUsage/App/AppViewModel+OfficialProfiles.swift:338 | 成功反馈 | 已切换 Claude 账号 | 已切换 Claude 账号 | 可保留 |
| 应用界面 | Sources/OhMyUsage/App/AppViewModel+OfficialProfiles.swift:339 | 标签/标题 | 已写入本机 Claude 登录 | 已写入本机 Claude 登录 | 可保留 |
| 应用界面 | Sources/OhMyUsage/App/AppViewModel+ProviderConfiguration.swift:577 | 按钮/操作 | 已重置 | 已重置 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:55 | 标签/标题 | 已追踪服务 | 已追踪服务 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:61 | 标签/标题 | 预取 | 预取 | 可保留 |
| 应用界面 | Sources/OhMyUsage/App/AppViewModel.swift:615 | 标签/标题 | 月度 | 月度 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:121 | 空状态 | 暂无可用值 | 暂无可用值 | 可保留 |
| 应用界面 / 设置页 | Sources/OhMyUsage/UI/Presenters/LocalUsageTrendPresenter.swift:119<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:372<br>Sources/OhMyUsage/UI/Settings/SettingsOfficialDetailedData.swift:401 | 空状态 | 暂无数据 | 暂无数据 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/RelayStatusPresenter.swift:89 | 标签/标题 | 站点不可达 | 站点不可达 | 可保留 |
| 应用界面 / 设置页 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:52<br>Sources/OhMyUsage/UI/Settings/SettingsLocalUsageTrend.swift:266<br>Sources/OhMyUsage/UI/Settings/SettingsProviderSidebar.swift:921 | 标签/标题 | 账号 | 账号 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:46 | 错误/异常 | 正常 Provider · 异常 \(diagnostics.providerErrorCount) | 正常 Provider · 异常 \(diagnostics.providerErrorCount) | 可保留，保留动态变量 |
| 应用界面 | Sources/OhMyUsage/App/AppViewModel+ProviderConfiguration.swift:578 | 错误/异常 | 重置失败 | 重置失败 | 可保留 |
| 应用界面 / Provider 状态 / 全局本地化 | Sources/OhMyUsage/App/AppViewModel.swift:610<br>Sources/OhMyUsage/Providers/KimiOfficialProvider.swift:408<br>Sources/OhMyUsage/Providers/KimiOfficialProvider.swift:653<br>Sources/OhMyUsage/Utils/Localization.swift:292 | 标签/标题 | 周 | 周 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift:204 | 标签/标题 | 柱状 + 名称 | 柱状图 + 名称 | 建议替换 |
| 应用界面 / Provider 状态 / 运行状态 / 菜单栏 / 设置页 | Sources/OhMyUsage/App/AppViewModel.swift:617<br>Sources/OhMyUsage/Providers/TraeProvider.swift:191<br>Sources/OhMyUsage/Services/UsageDisplayFormatter.swift:17<br>Sources/OhMyUsage/UI/Presenters/MenuQuotaPresenter.swift:487<br>另 3 处 | 标签/标题 | 自动补全 | 自动补全 | 可保留 |
| 应用界面 | Sources/OhMyUsage/App/AppViewModel+OfficialProfiles.swift:195 | 标签/标题 | Claude 账号备注已更新 | Claude 账号备注已更新 | 可保留 |
| 应用界面 | Sources/OhMyUsage/App/AppViewModel+OfficialProfiles.swift:208 | 成功反馈 | Claude 账号档案已导入 | Claude 账号档案已导入 | 可保留 |
| 应用界面 | Sources/OhMyUsage/UI/Presenters/SettingsResourceDiagnosticsPresenter.swift:33 | 标签/标题 | Provider 快照 | Provider 快照 | 可保留 |
| 应用界面 / 设置页 | Sources/OhMyUsage/App/AppViewModel.swift:612<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:410<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:461 | 标签/标题 | Sonnet 专用 | Sonnet 专用 | 可保留 |
| 运行状态 | Sources/OhMyUsage/Services/UsageDisplayFormatter.swift:345 | 标签/标题 | \(compactDecimal(Double(safeValue) / 10_000))万 | \(compactDecimal(Double(safeValue) / 10_000))万 | 可保留，保留动态变量 |
| 运行状态 | Sources/OhMyUsage/Services/UsageDisplayFormatter.swift:342 | 标签/标题 | \(compactDecimal(Double(safeValue) / 100_000_000))亿 | \(compactDecimal(Double(safeValue) / 100_000_000))亿 | 可保留，保留动态变量 |
| 运行状态 | Sources/OhMyUsage/Services/UsageDisplayFormatter.swift:333 | 标签/标题 | \(compactValue)次 | \(compactValue)次 | 可保留，保留动态变量 |
| 运行状态 | Sources/OhMyUsage/Services/CountdownFormatter.swift:61 | 标签/标题 | \(days)天\(hours)时 | \(days)天\(hours)时 | 可保留，保留动态变量 |
| 运行状态 | Sources/OhMyUsage/Services/CountdownFormatter.swift:70 | 标签/标题 | \(hours)时\(minutes)分 | \(hours)时\(minutes)分 | 可保留，保留动态变量 |
| 运行状态 | Sources/OhMyUsage/Services/CountdownFormatter.swift:36<br>Sources/OhMyUsage/Services/CountdownFormatter.swift:40 | 标签/标题 | 本地估算 | 本地估算 | 可保留 |
| 运行状态 | Sources/OhMyUsage/Services/RelayAdapterRegistry.swift:125 | 按钮/操作 | 测试连接时会优先使用当前模板的默认余额接口；若站点返回结构不同，再展开高级设置覆盖路径。 | 测试连接会优先使用当前模板的默认余额接口；若站点返回结构不同，再展开高级设置覆盖路径。 | 建议替换 |
| 运行状态 | Sources/OhMyUsage/Services/CountdownFormatter.swift:25<br>Sources/OhMyUsage/Services/CountdownFormatter.swift:38<br>Sources/OhMyUsage/Services/CountdownFormatter.swift:42 | 按钮/操作 | 待刷新 | 待刷新 | 可保留 |
| 运行状态 | Sources/OhMyUsage/Services/RelayAdapterRegistry.swift:120 | 错误/异常 | 该模板读取 Token Plan 套餐详情与用量接口，展示套餐名称、到期时间和当前套餐用量；如果测试连接失败，优先确认浏览器里 platform.xiaomimimo.com 仍处于登录状态。 | 该模板会读取 Token Plan 套餐详情和用量接口，展示套餐名称、到期时间和当前套餐用量。若测试失败，请先确认浏览器中 platform.xiaomimimo.com 仍处于登录状态。 | 建议替换，保留必要技术名 |
| 运行状态 | Sources/OhMyUsage/Services/CountdownFormatter.swift:30<br>Sources/OhMyUsage/Services/CountdownFormatter.swift:44 | 标签/标题 | 官方确认 | 官方确认 | 可保留 |
| 运行状态 / 菜单栏 / 应用界面 / 设置页 | Sources/OhMyUsage/Services/UsageDisplayFormatter.swift:20<br>Sources/OhMyUsage/UI/Presenters/MenuQuotaPresenter.swift:490<br>Sources/OhMyUsage/UI/Presenters/StatusBarDisplayPresenter.swift:225<br>Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift:621<br>另 1 处 | 标签/标题 | 美元 | 美元 | 可保留 |
| 运行状态 | Sources/OhMyUsage/Services/CountdownFormatter.swift:34 | 标签/标题 | 网页观测 | 网页观测 | 可保留 |
| 运行状态 | Sources/OhMyUsage/Services/CCSwitchUsageLogReader.swift:105 | 说明/提示 | 未检测到 cc-switch 请求日志：\(databasePath) | 未检测到 cc-switch 请求日志：\(databasePath) | 可保留，保留动态变量 |
| 运行状态 | Sources/OhMyUsage/Services/CCSwitchUsageLogReader.swift:114 | 按钮/操作 | 无法只读打开 cc-switch 请求日志：\(databasePath) | 无法只读打开 cc-switch 请求日志：\(databasePath) | 可保留，保留动态变量 |
| 运行状态 | Sources/OhMyUsage/Services/RelayAdapterRegistry.swift:130 | 标签/标题 | 先尝试标准 New API 配置；只有当站点接口路径或字段不兼容时再改高级设置。 | 先尝试标准 New API 配置；只有当站点接口路径或字段不兼容时再改高级设置。 | 可保留 |
| 运行状态 | Sources/OhMyUsage/Services/CountdownFormatter.swift:32 | 标签/标题 | 用户校准 | 用户校准 | 可保留 |
| 运行状态 | Sources/OhMyUsage/Services/RelayAdapterRegistry.swift:115 | 说明/提示 | 优先确认 API Key 与后台访问令牌分别填写正确；该站点可同时展示 token 配额和账户余额。 | 优先确认 API Key 与后台访问令牌分别填写正确；该站点可同时展示 token 配额和账户余额。 | 可保留，保留必要技术名 |
| 运行状态 | Sources/OhMyUsage/Services/CCSwitchUsageLogReader.swift:125 | 标签/标题 | cc-switch 数据库缺少 proxy_request_logs 表 | cc-switch 数据库缺少 proxy_request_logs 表 | 可保留 |
| 中转模板 / 运行状态 | Sources/OhMyUsage/Resources/RelayAdapters/generic-newapi.json:13<br>Sources/OhMyUsage/Services/RelayAdapterRegistry.swift:353 | 模板说明 / 说明/提示 | 填写后台 Access Token，支持直接粘贴 \`Bearer ...\` 或纯 token。 | 填写后台 Access Token，支持直接粘贴 \`Bearer …\` 或纯 token。 | 建议替换，保留必要技术名 |
| 中转模板 / 运行状态 | Sources/OhMyUsage/Resources/RelayAdapters/generic-newapi.json:17<br>Sources/OhMyUsage/Services/RelayAdapterRegistry.swift:357 | 模板说明 / 说明/提示 | 填写请求头 \`New-Api-User\` 对应的 userId。 | 填写请求头 \`New-Api-User\` 对应的 userId。 | 可保留 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/moonshot.json:14 | 模板说明 | 优先填写请求头里的 Authorization Bearer Token，直接粘贴 \`Bearer ...\` 或只粘贴 Token 本体都可以。像 INGRESSCOOKIE、_ga 这类 Cookie 不能用于登录鉴权。 | 优先填写请求头里的 Authorization Bearer Token，直接粘贴 \`Bearer …\` 或只粘贴 Token 本体都可以。像 INGRESSCOOKIE、_ga 这类 Cookie 不能用于登录鉴权。 | 建议替换，保留必要技术名 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/xiaomimimo-token-plan.json:15 | 模板说明 | 粘贴浏览器请求里的完整 Cookie，通常至少包含 \`api-platform_serviceToken\`、\`userId\`、\`api-platform_slh\`、\`api-platform_ph\`。模板会自动读取 \`/api/v1/tokenPlan/detail\` 与 \`/api/v1/tokenPlan/usage\` 展示套餐用量。 | 粘贴浏览器请求里的完整 Cookie，通常至少包含 \`api-platform_serviceToken\`、\`userId\`、\`api-platform_slh\`、\`api-platform_ph\`。模板会自动读取 \`/api/v1/tokenPlan/detail\` 与 \`/api/v1/tokenPlan/usage\` 展示套餐用量。 | 可保留，保留必要技术名 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/xiaomimimo.json:14 | 模板说明 | 粘贴浏览器请求里的完整 Cookie，通常至少包含 \`api-platform_serviceToken\`、\`userId\`、\`api-platform_slh\`、\`api-platform_ph\`。模板会自动先访问 \`/api/v1/userProfile\`，再探测 \`/api/v1/balance\` 获取余额。 | 粘贴浏览器请求里的完整 Cookie，通常至少包含 \`api-platform_serviceToken\`、\`userId\`、\`api-platform_slh\`、\`api-platform_ph\`。模板会自动先访问 \`/api/v1/userProfile\`，再探测 \`/api/v1/balance\` 获取余额。 | 可保留，保留必要技术名 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/minimax.json:14 | 模板说明 | 粘贴浏览器请求里的完整 Cookie。模板会自动带上 \`Origin\` 和 \`Referer\` 等固定请求头。 | 粘贴浏览器请求中的完整 Cookie。模板会自动带上 Origin、Referer 等固定请求头。 | 建议替换，保留必要技术名 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/ailinyu.json:14 | 模板说明 | 粘贴浏览器请求头里的完整 Cookie。 | 粘贴浏览器请求头中的完整 Cookie。 | 建议替换，保留必要技术名 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/dragoncode.json:14 | 模板说明 | 粘贴请求头中的 Authorization 值（支持 Bearer 前缀或原始 Token）。 | 粘贴请求头中的 Authorization 值，支持 Bearer 前缀或原始 Token。 | 建议替换，保留必要技术名 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/deepseek.json:14 | 模板说明 | 粘贴请求头中的 Authorization 值（Bearer Token 或登录态令牌）。 | 粘贴请求头中的 Authorization 值（Bearer Token 或登录态令牌）。 | 可保留，保留必要技术名 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/hongmacc.json:14 | 模板说明 | 粘贴请求头中的 Authorization Bearer 值。 | 粘贴请求头中的 Authorization Bearer 值。 | 可保留，保留必要技术名 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/minimax.json:18 | 模板说明 | 这里填写请求 URL 里的 \`GroupId\`，例如 \`/backend/account?GroupId=2026...\` 里的那一串数字。 | 填写请求 URL 里的 GroupId，例如 /backend/account?GroupId=2026... 中的数字。 | 建议替换 |
| 中转模板 | Sources/OhMyUsage/Resources/RelayAdapters/ailinyu.json:18 | 模板说明 | 这里需要填写你自己账号对应的用户 ID。请从站点请求头里的 \`New-Api-User\` 或相关账户请求中复制，不会再使用模板预填值。 | 填写你自己账号对应的用户 ID。可从站点请求头 New-Api-User 或账户请求中复制。 | 建议替换 |
| 中转模板 / 运行状态 | Sources/OhMyUsage/Resources/RelayAdapters/generic-newapi.json:45<br>Sources/OhMyUsage/Services/RelayAdapterRegistry.swift:384 | 模板说明 / 说明/提示 | coalesce(data.group,"默认套餐") | coalesce(data.group,"默认套餐") | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/TraeProvider.swift:201 | 标签/标题 | 美元余额 \(Int(dollar.remainingPercent.rounded()))% \| 自动补全 \(Int(autocomplete.remainingPercent.rounded()))% | 美元余额 \(Int(dollar.remainingPercent.rounded()))% \| 自动补全 \(Int(autocomplete.remainingPercent.rounded()))% | 可保留，保留动态变量 |
| Provider 状态 | Sources/OhMyUsage/Providers/KiroProvider.swift:31 | 标签/标题 | 未检测到 kiro-cli | 未检测到 kiro-cli | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/GeminiProvider.swift:246 | 空状态 | 未找到 Gemini CLI OAuth client 配置，无法刷新令牌 | 未找到 Gemini CLI OAuth client 配置，无法刷新令牌 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/AmpProvider.swift:16 | 说明/提示 | Amp 官方来源当前仅支持 API 检测 | Amp 官方来源当前仅支持 API 检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/CursorProvider.swift:27 | 说明/提示 | Cursor 官方来源当前仅支持 API 检测 | Cursor 官方来源当前仅支持 API 检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/GeminiProvider.swift:54 | 说明/提示 | Gemini 官方来源当前不支持网页 Cookie 检测 | Gemini 官方来源当前不支持网页 Cookie 检测 | 可保留，保留必要技术名 |
| Provider 状态 | Sources/OhMyUsage/Providers/GeminiProvider.swift:52 | 说明/提示 | Gemini 官方来源当前仅支持 API 凭证发现 | Gemini 官方来源当前仅支持 API 凭证发现 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/GeminiProvider.swift:62 | 标签/标题 | Gemini API key 模式无法稳定获取官方订阅配额 | Gemini API key 模式无法稳定获取官方订阅配额 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/GeminiProvider.swift:64 | 标签/标题 | Gemini Vertex AI 模式不属于个人官方订阅配额 | Gemini Vertex AI 模式不属于个人官方订阅配额 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/CopilotProvider.swift:40 | 说明/提示 | GitHub Copilot 官方来源当前仅支持 API 检测 | GitHub Copilot 官方来源当前仅支持 API 检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/JetBrainsProvider.swift:14 | 说明/提示 | JetBrains 官方来源当前仅支持本地配额缓存检测 | JetBrains 官方来源当前仅支持本地配额缓存检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/KimiOfficialProvider.swift:54 | 说明/提示 | Kimi 官方来源当前不支持网页 Cookie 检测 | Kimi 官方来源当前不支持网页 Cookie 检测 | 可保留，保留必要技术名 |
| Provider 状态 | Sources/OhMyUsage/Providers/KimiOfficialProvider.swift:52 | 说明/提示 | Kimi 官方来源当前仅支持 API 凭证发现 | Kimi 官方来源当前仅支持 API 凭证发现 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/KiroProvider.swift:15 | 说明/提示 | Kiro 官方来源当前仅支持 CLI 或 IDE 本地检测 | Kiro 官方来源当前仅支持 CLI 或 IDE 本地检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/KiroProvider.swift:39 | 错误/异常 | kiro-cli /usage 执行失败 | kiro-cli /usage 执行失败 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/MicrosoftCopilotProvider.swift:16 | 说明/提示 | Microsoft Copilot 官方来源当前仅支持 API 检测 | Microsoft Copilot 官方来源当前仅支持 API 检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/OllamaCloudProvider.swift:36 | 说明/提示 | Ollama Cloud 官方来源当前仅支持 Web 检测 | Ollama Cloud 官方来源当前仅支持 Web 检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/OpenCodeGoProvider.swift:129 | 说明/提示 | OpenCode Go 官方来源当前仅支持 Web 检测 | OpenCode Go 官方来源当前仅支持 Web 检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/OpenRouterProvider.swift:28 | 说明/提示 | OpenRouter 官方来源当前仅支持 API 检测 | OpenRouter 官方来源当前仅支持 API 检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/TraeProvider.swift:30 | 说明/提示 | Trae SOLO 官方来源当前仅支持 API 检测 | Trae SOLO 官方来源当前仅支持 API 检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/TraeProvider.swift:61 | 错误/异常 | Trae SOLO Authorization 已失效，且未在浏览器中找到可用登录态。请登录 trae.ai 后重试，或重新粘贴最新 Cloud-IDE-JWT。 | Trae SOLO Authorization 已失效，且未在浏览器中找到可用登录态。请登录 trae.ai 后重试，或重新粘贴最新 Cloud-IDE-JWT。 | 可保留，保留必要技术名 |
| Provider 状态 | Sources/OhMyUsage/Providers/WindsurfProvider.swift:36 | 说明/提示 | Windsurf 官方来源当前仅支持 API 检测 | Windsurf 官方来源当前仅支持 API 检测 | 可保留 |
| Provider 状态 | Sources/OhMyUsage/Providers/ZaiProvider.swift:16 | 说明/提示 | Z.ai 官方来源当前仅支持 API 检测 | Z.ai 官方来源当前仅支持 API 检测 | 可保留 |
