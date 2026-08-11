# oh-myusage

<img width="2140" height="1470" alt="image" src="https://github.com/user-attachments/assets/a1804d4f-1c91-41d3-9c64-fab73a83cf44" />


面向 macOS 菜单栏的 AI 订阅、额度与账号状态控制台。

oh-myusage 把官方订阅额度、模型使用窗口、第三方中转余额、本地桌面端账号状态和异常诊断统一放到菜单栏里。它不是单一网页余额的封装，而是一个常驻运行、低打扰、可扩展的 AI 用量工作台。

[下载最新版本](https://github.com/Four-JJJJ/oh-myusage/releases/latest) · [安装说明](docs/DOWNLOAD.md) · [支持的服务](docs/PROVIDERS.md) · [扩展指南](docs/EXTENDING.md) · [发布清单](docs/RELEASE_CHECKLIST.md) · [English](docs/README.en.md)

## V2.2.4 更新

V2.2.4 的重点是提高官方模型余额与额度查询的稳定性，并修复多余额菜单栏展示。

本次更新集中在五件事：

| 方向 | 改进 |
| --- | --- |
| 官方余额 | DeepSeek 支持使用已保存的 API key 查询账户余额，并区分余额与订阅限额展示 |
| 凭证恢复 | 优化 Kimi、MiniMax、Xiaomi MiMo 等服务的浏览器凭证、Cookie 合并和失效凭证回退 |
| 额度解析 | 增强 Kimi Coding、MiniMax Coding Plan、Moonshot 及多种官方余额响应结构的解析兼容性 |
| 账号刷新 | Codex 鉴权失败时自动刷新一次凭证，并改进账号切换后的状态同步 |
| 菜单栏 | 恢复同时展示多个余额，金额统一保留两位小数并支持千分位 |

## 适合谁

- 同时使用多个 AI 官方产品，希望在菜单栏快速判断额度状态的人
- 依赖多个第三方中转站，希望统一查看余额、Token 用量和异常原因的人
- 经常在多个 Codex 或 Claude 本地账号之间切换的人
- 希望区分“官方确认”“本地估算”“缓存回退”“鉴权失效”等数据可信度的人
- 想要一个长期常驻、低能耗、可诊断的 AI 用量监控工具的人

## 它解决什么问题

AI 用量信息通常分散在很多地方：

- 官方产品各自有不同的额度页、重置周期和显示方式
- 第三方中转站需要处理 Cookie、Bearer、用户 ID、GroupId、组织上下文或自定义 JSON 字段
- 本地桌面端工具的账号状态和历史用量不一定存在公开网页里
- 登录态过期、接口变更、限流和网络失败经常只表现为“刷新失败”

oh-myusage 的目标是让这些信息变得可扫读、可诊断、可维护：

- 在菜单栏快速看到当前服务还能不能用
- 明确看到会话、5 小时、天、周、月等窗口何时重置
- 同时管理官方来源、本地来源和第三方中转来源
- 发现低额度、鉴权失效、连续失败、缓存回退和接口变化
- 在需要时直接管理或切换本地账号，而不是手动翻配置文件

## 核心能力

### 菜单栏状态驾驶舱

- 直接显示额度、百分比、余额、倒计时、刷新状态和异常状态
- 支持固定单模型显示、多模型轮换和多用量展示
- 支持低额度、鉴权失效、连续失败等提醒
- 状态栏外观支持跟随壁纸、强制深色和强制浅色

### 官方订阅与本地账号

- 统一管理官方 Provider、本地桌面端会话和账号资料
- 支持 Codex / Claude OAuth 导入和账号槽位管理
- 支持 Codex 本地多账号识别、保存与切换
- 非当前账号的额度窗口和倒计时也可以保留展示

### 第三方中转账本

- 内置常见站点模板，减少手工填写接口路径和字段解析
- 支持余额通道、Token 通道、账号信息、有效期和额外上下文字段
- 支持 `Manual Preferred`、`Browser Preferred`、`Browser Only` 三种凭证策略
- 对认证失败、限流、端点配置错误、网络不可达等状态做用户可读诊断

### 本地历史用量

- 支持读取 Codex、Claude、Kimi 等本地使用记录
- 缓存聚合结果，避免每次打开设置页都重新扫描
- 刷新失败时保留旧数据，并明确标记缓存回退
- 不保存原始聊天内容，重点保存用量聚合结果

### 更新与发布

- 支持 GitHub Release 驱动的应用内更新检测
- 支持更新说明展示
- 打包脚本支持 DMG / ZIP 输出
- 可接入 Developer ID 签名和 notarization

## 支持的服务

完整说明见 [docs/PROVIDERS.md](docs/PROVIDERS.md)。

### 官方与本地来源

| 类型 | 服务 |
| --- | --- |
| 官方 / 本地桌面端 | Codex、Claude、Gemini、GitHub Copilot、Cursor、Windsurf |
| 官方 / API 或网页来源 | Kimi / Moonshot、DeepSeek、MiniMax、Xiaomi MiMo、Amp、Z.ai、OpenCode Go |
| 官方 / 本地数据来源 | JetBrains AI、Kiro |

### 第三方中转模板

| 模板 | 凭证方式 |
| --- | --- |
| Generic New API | Bearer 或 Cookie |

支持通用的NewAPI站点模板获取信息

## 快速开始

### 下载安装

1. 打开 [Latest Release](https://github.com/Four-JJJJ/oh-myusage/releases/latest)
2. 下载 `oh-myusage.dmg`
3. 打开 DMG，将 `oh-myusage.app` 拖入 `Applications`
4. 第一次启动时如被 macOS 拦截，右键应用并选择“打开”
5. 如果仍被拦截，到“系统设置 -> 隐私与安全性”里选择“仍要打开”

更完整的安装和排障步骤见 [docs/DOWNLOAD.md](docs/DOWNLOAD.md)。

### 系统要求

- macOS 14 或更高版本
- 当前通过 GitHub Releases 分发，非 App Store 安装包

### 初次配置建议

1. 先在设置页启用你真正需要监控的 Provider
2. 官方服务优先使用本地登录态或 OAuth 导入
3. 第三方中转优先选择内置模板，再补充必要的 Token、Cookie 或 GroupId
4. 如果站点登录态更稳定，可把凭证策略切换为 `Browser Preferred`
5. 对高频使用的服务设置低额度提醒和菜单栏显示策略

## 数据与安全

- 手动保存的 Token、Cookie 等凭证默认存放在 macOS Keychain
- 历史 `OhMyUsage` 钥匙串条目会迁移到新的 `oh-myusage`
- 应用配置保存在 `~/Library/Application Support/OhMyUsage`
- 本地历史用量保存聚合缓存，不保存原始聊天内容
- 浏览器凭证读取只用于支持的站点和对应凭证策略
- 第三方站点接入能力会受到目标站点认证方式、权限策略和返回结构变化影响

## 从源码运行

### 环境要求

- macOS 14+
- Xcode / Swift 6.2 工具链

### 常用命令

构建：

```bash
swift build
```

运行：

```bash
swift run
```

测试：

```bash
swift test
```

打包：

```bash
./scripts/package_dmg.sh
```

打包产物默认输出到：

- `dist/oh-myusage.dmg`
- `dist/oh-myusage-macOS.zip`

## 工程结构

```text
Sources/
├── OhMyUsage              # 当前可执行应用主体，包含 App、UI、Services、Providers、Resources
├── OhMyUsageDomain        # 领域模型与稳定契约骨架
├── OhMyUsageInfrastructure # 基础设施骨架
├── OhMyUsageProviders     # Provider 运行时拆分目标骨架
├── OhMyUsageApplication   # 应用层调度、退避、诊断等已抽出的逻辑
├── OhMyUsagePresentation  # 展示层拆分目标骨架
├── OhMyUsageFeatures      # 功能模块拆分目标骨架
└── OhMyUsageBootstrap     # 启动组装拆分目标骨架

Tests/OhMyUsageTests       # XCTest 测试
docs/                      # 安装、支持服务、扩展、发布与重构说明
scripts/                   # 打包与发布脚本
```

当前代码仍保留兼容迁移路径：主应用逻辑主要位于 `Sources/OhMyUsage`，新的 target 用于承接 V2 之后的持续模块化拆分。

## 扩展开发

新增官方 Provider、第三方中转模板或设置项前，优先阅读 [docs/EXTENDING.md](docs/EXTENDING.md)。

推荐原则：

- Provider 接入代码放在 `Sources/OhMyUsage/Providers`
- 共享模型放在 `Sources/OhMyUsage/Models`
- 刷新、账号、配置、通知和更新能力放在 `Sources/OhMyUsage/Services` 或已抽出的应用层模块
- 菜单栏和设置页展示逻辑优先放到 Presenter 或 Settings 子模块
- 新增行为需要补 focused tests，并至少运行 `swift build` 和 `swift test`

## 发布

本地打包：

```bash
APP_VERSION=2.0.0 ./scripts/package_dmg.sh
```

发布前检查：

- 确认 `VERSION` 与目标版本一致
- 运行 `swift build`
- 运行 `swift test`
- 运行本地打包冒烟测试
- 确认 `dist/oh-myusage.dmg` 和 `dist/oh-myusage-macOS.zip` 存在
- 确认 GitHub Release 产物包含 `latest.json`

完整流程见 [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md)。

## 常见问题

### 应用无法打开

GitHub 分发的构建可能未完成正式公证。可先右键 `oh-myusage.app` 选择“打开”，或按 [安装说明](docs/DOWNLOAD.md) 处理 Gatekeeper 拦截。

### Provider 显示鉴权失效

重新登录对应官方应用或网站。对于手动凭证模式，重新保存 Token 或 Cookie；对于支持的中转站，可以尝试切换到浏览器优先模式。

### 第三方中转突然刷新失败

优先查看错误类型。如果是认证失败，通常需要重新登录或更新凭证；如果是端点或解析失败，可能是目标站点改版，需要更新模板或字段规则。

### Codex 切换后仍提示验证

本地账号配置可能已经切换成功，但 Codex 桌面端仍需要完成一次官方验证。按 Codex 桌面端提示完成验证后，再回到 oh-myusage 刷新状态。

## 致谢

感谢以下项目带来的启发：

- [openusage](https://github.com/robinebers/openusage)
- [cc-switch](https://github.com/farion1231/cc-switch)
- [codexbar](https://github.com/rajasimon/codexbar)

## 许可证

MIT，详见 [LICENSE](LICENSE)。
