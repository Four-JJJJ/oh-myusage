# oh-myusage

<img width="2140" height="1470" alt="image" src="https://github.com/user-attachments/assets/a1804d4f-1c91-41d3-9c64-fab73a83cf44" />


面向 macOS 菜单栏的 AI 订阅、额度与账号状态控制台。

oh-myusage 把官方订阅额度、模型使用窗口、第三方中转余额、本地桌面端账号状态和异常诊断统一放到菜单栏里。它不是单一网页余额的封装，而是一个常驻运行、低打扰、可扩展的 AI 用量工作台。

[下载最新版本](https://github.com/Four-JJJJ/oh-myusage/releases/latest) · [安装说明](docs/DOWNLOAD.md) · [支持的服务](docs/PROVIDERS.md) · [扩展指南](docs/EXTENDING.md) · [发布清单](docs/RELEASE_CHECKLIST.md) · [English](docs/README.en.md)

## V2.6.3 更新

V2.6.3 是一版全量性能与工程优化：主线程 IO 清零到后台、HTTP 行为统一、死代码出清。

| 方向 | 改进 |
| --- | --- |
| 主线程 IO | 本地 session 监控（stat/SQLite/JSONL）移入 actor；官方 profile/slot 四个 store 读写下沉串行 IO 队列，内容未变跳过写盘，退出时统一落盘 |
| HTTP 统一 | 公共校验层统一 401/403/429/5xx/HTML 分类，迁移 Relay、官方认证/抓取与 Copilot/Cursor/Codex/Claude/Gemini/Grok Bot/Kimi/OpenRouter 共 10 处 |
| 429 处理 | 官方 API 与中转通道解析 Retry-After（封顶 1 小时）推迟轮询，不再只靠固定退避 |
| 一致性 | 统计页术语对齐、「加油包」双语；11 处重复数字格式化收敛为共享实现，显示输出不变 |
| 加固 | 单实例锁 O_NOFOLLOW；Kimi 缓存 key 改 SHA-256 指纹 |
| 架构 | 删除零引用的 Features/Bootstrap 占位 target 与死模型；8 个测试文件不再依赖运行目录；含测试全仓零警告 |

全量 1,426 项测试 0 失败。详见[本版发布说明](docs/releases/v2.6.3.md)。

## V2.6.2 更新

V2.6.2 是一版安全与稳定性修缮：堵住两条本地凭证读取链路上的安全缺口，并修复 2.6.1 轮换机制引入的 Cookie 覆盖回归。

| 方向 | 改进 |
| --- | --- |
| 浏览器 Cookie 查询 | Cookie 名与域名过滤条件改为严格白名单，仅接受标准字符，消除把 SQL 注入进浏览器 Cookie 库、读取任意站点登录态的通道 |
| 中转请求地址 | 适配器里的绝对地址只允许你配置的中转域名（同协议）或内置官方探测域名（强制 https），其余一律回落到所配置站点，凭证不外发 |
| Cookie 轮换 | 浏览器读到的 Cookie 改为「请求成功后才写入钥匙串」，陈旧浏览器登录态不再覆盖仍有效的已保存 Cookie；被拒后的立即重试不再受来源标签限制 |
| 应用内更新 | 清单缺 SHA-256 直接拒绝；解压后的 .app 先过 codesign 校验（签名团队一致时要求同团队）；安装器启动失败如实报错 |
| 凭证与文件 | 移除把明文密码暴露在命令行参数的钥匙串回退；配置、槽位、基线文件统一 0600 私有权限 |
| 运行时 | 第三方基线不再每轮主线程写盘（去重 + 后台 IO）；浏览器读取退避期间继续使用可用已存 Cookie；有损配置候选不再被启动保存删除 |
| 工程化 | CI 超时与并发取消、actions 固定 commit SHA、`.swift-version`；打包脚本退出清理临时目录与挂载 DMG |

本地全量 1,394 项测试通过（含 9 项新增安全回归测试），生产源码零警告。详见[本版发布说明](docs/releases/v2.6.2.md)。

## V2.6.1 更新

V2.6.1 把靠浏览器登录态的站点统一成同一套自动续期，不再每个站点各自处理。

| 方向 | 改进 |
| --- | --- |
| 自动续期 | 浏览器优先或自动导入模式下，每 30 分钟从浏览器重新导入一次登录态，在 Cookie 过期前换上新的；浏览器没有更新时继续用旧的 |
| 覆盖范围 | 小米 MIMO、MiniMax、爱琳语等中转站，以及千问、Ollama、OpenCode Go，还有 Codex 与 Claude 的网页模式 |
| 失效恢复 | 服务器拒绝旧凭证后立刻再读一次浏览器；读不到登录时的等待从 10 到 15 分钟统一收成 1 分钟，Trae 也是 1 分钟 |
| 手动模式 | 手动优先与手动粘贴保持不变，只用你保存的那份；过期报错统一说明如何切到浏览器优先或重新粘贴 |
| 应用内更新 | 点击更新后不再停在「即将安装重启」；安装完成直接回到菜单栏，不再弹出更新说明窗口 |

自动续期需要浏览器里该站点保持登录，且使用 Chrome、Arc、Edge 等 Chromium 系浏览器；Safari 与 Firefox 的登录读不出来。API 密钥被吊销、以及登录态锁在 App 自己数据里的站点（Windsurf、Amp、JetBrains、Kiro）仍需手动处理。详见[本版发布说明](docs/releases/v2.6.1.md)。

## V2.6.0 更新

V2.6.0 聚焦凭证与配置的数据安全、后台任务取消和统计页双语体验，保留既有刷新频率与界面风格。

| 方向 | 改进 |
| --- | --- |
| 凭证完整性 | 同进程多实例按最新持久化状态合并写入，避免冷写覆盖；写入失败不删旧凭证，不污染成功缓存；删除标记防止旧单项凭证重新迁入 |
| 配置恢复 | 损坏配置原始字节在覆盖前独立归档，连续启动和普通保存不会清除，保留人工恢复依据 |
| Profile 保护 | 新文件从创建起使用 0600 权限并私有原子替换；收紧现有 profile 文件，拒绝符号链接和硬链接目标 |
| 运行时治理 | 父刷新取消传递到后台 worker，阻止旧结果晚写；移除常驻窗口扫描 Timer，复用 Grok/Gemini 文件枚举缓存 |
| 官方服务 | 统一管理订阅与 API 来源，在服务名后标注 API 类型；按来源展示账号、套餐额度或账户余额 |
| 双语与构建 | 统计页标题、指标、选项、空态和月份跟随应用语言；新增隔离构建入口和源码警告门禁，发布前运行测试 |
| 发布稳定性 | 保存提示的计时测试使用可控时钟，消除 CI 调度延迟导致的偶发失败；覆盖重复保存、旧任务取消和延迟补偿，应用默认计时行为不变 |

本地全量 1,382 项测试通过，保存提示相关 12 项测试连续运行 20 轮全部通过，生产源码严格编译通过；本版双架构 Release 编译此前已通过。最终 DMG、签名、公证和覆盖安装的验证状态以实际 Release 与验收记录为准；真实账号流程另行验收。Profile 仍是同用户可访问的明文，凭证事务尚不保证跨进程并发；不宣称未经测量的性能或能耗收益。详见[本版发布说明](docs/releases/v2.6.0.md)与[修缮验证记录](docs/OPTIMIZATION_REPAIRS_2026-10-17.md)。

## V2.5.4 更新

V2.5.4 聚焦用量统计正确性、缓存可信度和后台任务治理，保留现有界面与默认刷新频率。

| 方向 | 改进 |
| --- | --- |
| Cursor 与统计 | 修复满页中无效记录导致提前停止分页的问题；部分结果与本地回退明确提示完整性；cc-switch 读取失败不再当作完整空数据 |
| 缓存正确性 | 数据指纹覆盖 SQLite WAL 与逐文件变化；刷新失败保留最后成功时间和旧图表；损坏、重复及超大缓存安全降级 |
| 响应与后台工作 | 展示缓存采用有序后台 I/O；取消过时扫描与请求，短期复用统计原始记录，限制缓存容量与旧值年龄 |
| 账号与持久化 | 凭据变化、删除或重置后拒绝旧请求晚到结果；避免异步写入乱序和系统时钟回拨覆盖新数据 |
| 限流恢复 | 服务端 `Retry-After` 传入后台调度，多渠道保留最晚期限；主动取消不再误判为网络失败 |

本轮全量 1,326 项测试通过。尚未测量优化前后的启动耗时、CPU、内存或能耗，不宣称提升百分比，也未提高默认刷新并发。详见[实施与验收记录](docs/OPTIMIZATION_IMPLEMENTATION_2026-10-09.md)。

## V2.5.3 更新

- 第三方中转套餐有效期显示为倒计时，不再直接展示绝对到期日期。

## V2.5.2 更新

V2.5.2 让套餐名更可读，并补上 Sub2API 中转模板和本地用量的 24 小时趋势。

| 方向 | 改进 |
| --- | --- |
| 套餐名 | Kimi 降级后也能从 `/me` 识别 Andante 等档位；Codex、Claude、Cursor、Copilot、Gemini、Grok、Windsurf、Trae、Qwen、Z.ai 等会把 `PLAN_` / `LEVEL_` 这类内部码显示成 Plus、Pro、SuperGrok；读不到就不显示，不再出现 `unknown` |
| Sub2API | 新增通用 Sub2API 站点模板：填根地址和分组 API Key，读取额度、订阅或速率窗口 |
| 本地用量 | 设置页本地历史用量新增 24 小时趋势图 |

## V2.5.1 更新

V2.5.1 新增 Grok Bot 官方来源，并让菜单栏排序、订阅档位展示与设置保持一致。

| 方向 | 改进 |
| --- | --- |
| Grok Bot | 新增独立官方卡：读取 Grok Bot 桌面端或 Cursor 登录态，显示每周 Bot 额度与可选按量窗口 |
| 菜单栏排序 | 设置里拖拽官方 / API 服务商顺序后，菜单栏立即按同一顺序刷新 |
| 订阅档位 | Cursor、Copilot、Gemini、Z.ai、Amp、Windsurf、Grok、Grok Bot、Qwen、Ollama Cloud 以及带套餐名的官方中转，会在卡片标题旁显示 Pro / Ultra / SuperGrok 等档位 |

## V2.5.0 更新

V2.5.0 聚焦官方账号授权、低功耗刷新与菜单栏状态可信度，让常驻查询更少打扰、更容易判断。

| 方向 | 改进 |
| --- | --- |
| 凭证与授权 | 统一 Keychain / OAuth 凭证路径，减少重复授权；官方账号凭证保存、导入和切换行为更一致 |
| 刷新与缓存 | 支持缓存优先展示、持久快照、按可见性调度刷新和网络可达性判断，降低后台无效请求并保留可用的历史状态 |
| 状态可信度 | 菜单卡片更明确地区分实时、缓存、估算与鉴权异常等状态，额度与账户信息更易判断 |
| 菜单栏展示 | 恢复额度进度条绿 / 橙 / 红的健康语义；移除菜单卡片中冗余的「官方实时 / Live」文字，保留必要的状态提示 |
| 发布与安装 | 强化无 Apple Developer ID 的 GitHub DMG / ZIP 发布校验、更新清单与未公证安装说明 |

## V2.4.6 更新

V2.4.6 新增千问AI平台官方来源（Qwen Coding Plan 限额卡与 Qwen (API) 余额卡），并统一所有 API 余额卡的设置页展示。

| 方向 | 改进 |
| --- | --- |
| Qwen | 新增千问 Token Plan 个人版额度卡：7 天滚动限额、加油包 Credits、套餐档位与重置时间；浏览器登录 platform.qianwenai.com 后手动刷新即可自动导入登录态，也可手动粘贴 Cookie |
| Qwen (API) | 新增千问按量付费余额卡，显示 CNY 可用额度，与 Qwen 卡共用同一份 Cookie |
| 余额卡展示 | 设置页账号卡的 API 余额统一显示真实金额（两位小数），不再显示误导性百分比；状态按余额阈值映射（充足/紧张/耗尽），Z.ai / Kimi / Qwen 三家一致 |
| 渠道图标 | 渠道图标切换为 lobehub 单色图标，深浅双主题自动适配 |

## V2.4.5 更新

V2.4.5 新增 Kimi (API) 余额卡，统一 Z.ai / Kimi 卡片命名，并为官方服务补上凭证获取指引。

| 方向 | 改进 |
| --- | --- |
| Kimi (API) | 新增 Moonshot 开放平台按量付费余额卡：自动识别 `MOONSHOT_API_KEY` 环境变量，也可在设置页粘贴开放平台 API Key，显示 CNY 余额 |
| 卡片命名 | 「智谱 API 余额」更名为「Z.ai (API)」，「Kimi Coding」更名为「Kimi」，订阅卡与 API 余额卡成对展示 |
| 凭证获取 | Z.ai、Kimi、OpenRouter、Trae 等官方服务的凭证框下方新增「获取说明」，直接写明去哪里拿 key |
| 一键导入 | Z.ai / Z.ai (API) 支持「从 Claude Code 导入」，一键读取本机 Claude Code 接入配置里的智谱密钥，无需跑开放平台控制台 |
| Moonshot 预设 | 默认添加列表移除 Moonshot 中转预设（由 Kimi (API) 官方卡替代）；已添加的站点与手动新建不受影响 |

## V2.4.4 更新

V2.4.4 为 Xiaomi MIMO 新增按量付费余额查询，在 Token Plan 不可用时自动切换，无需另行配置。

| 方向 | 改进 |
| --- | --- |
| MIMO 按量付费 | Token Plan 无订阅、套餐为空或接口返回 404 时，自动查询 `/api/v1/userProfile` 与 `/api/v1/balance`，显示 CNY 余额、已用额度和总额度 |

## V2.4.3 更新

V2.4.3 修复 Xiaomi MIMO 凭证读取与设置窗口显示问题，并优化 MIMO Token Plan 的鉴权诊断。

本次更新集中在这些事：

| 方向 | 改进 |
| --- | --- |
| MIMO 认证 | 粘贴凭证支持三种格式：完整 Cookie、带 `Cookie:` 前缀的整行、或只粘贴 `api-platform_serviceToken` 的值；不再误报 "cookie looks incomplete" |
| 设置窗口 | 根治打开设置时偶发的空白设置窗口——移除 SwiftUI `Settings` 场景，设置界面改由 AppKit 窗口承载，始终只出现一个设置窗口 |
| MIMO Token Plan | Cookie 过期或未订阅 Token Plan 时给出明确的重新登录 / 订阅提示，而不是模糊的响应错误 |
| 错误提示 | 设置页凭证提示同步覆盖三种粘贴方式，测试连接报错更可读 |

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

- 支持读取 Codex、Claude、Kimi、Grok、Gemini 的本地使用记录；Cursor 优先使用 dashboard 用量事件，并支持本地回退
- 使用统计结合官方本地日志与可用的 Cursor dashboard；cc-switch 作为中转请求的可选补充
- 本机没有 cc-switch 时，仍可汇总可用来源；部分结果会标记完整性，不等同于官方账单或剩余额度
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
| 官方 / 本地桌面端 | Codex、Claude、Gemini、GitHub Copilot、Cursor、Grok Bot、Windsurf、Grok |
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

GitHub 分发的构建未使用 Apple Developer ID 签名、未经公证（notarization），首次打开会被 Gatekeeper 拦截，升级后可能需要重新确认 Keychain 访问：详见[未签名构建安装说明](docs/INSTALL_UNSIGNED.md)。

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
./scripts/dev.sh build
```

运行：

```bash
./scripts/dev.sh run
```

测试：

```bash
./scripts/dev.sh test
```

打包：

```bash
./scripts/package_dmg.sh
```

`dev.sh` 使用默认 SwiftPM 构建后端，并将产物放在同步目录外的
`~/Library/Caches/OhMyUsage/Builds/<工作区路径摘要>`，不同 checkout 不共用产物。
如果当前选择的是 Command Line Tools，会仅为该命令优先选择已安装的完整 Xcode，
不会修改全局 `xcode-select`。可用 `DEVELOPER_DIR` 指定工具链，或用 `OMU_BUILD_PATH`
指定独立构建目录；原生 `swift build/test/run` 仍可使用。

遇到 SwiftUI 宏插件缺失时先检查完整 Xcode 选择；遇到 resource fork / FinderInfo
签名错误时使用同步目录外的全新构建目录。无需清空已有 `.build`、移动源码或递归清理仓库属性。
CI 的源码构建使用 `-Xswiftc -warnings-as-errors`；测试仍单独运行，避免把历史测试警告混同为生产源码警告。

打包产物默认输出到：

- `dist/oh-myusage.dmg`
- `dist/oh-myusage-macOS.zip`

## 工程结构

```text
Sources/
├── OhMyUsage              # 当前可执行应用主体，包含 App、UI、Services、Providers、Resources
├── OhMyUsageDomain        # 领域模型与稳定契约
├── OhMyUsageInfrastructure # 基础设施（凭证存储）
├── OhMyUsageProviders     # Provider 运行时（HTTP 校验、Cookie 检测等）
├── OhMyUsageApplication   # 应用层调度、退避、诊断等已抽出的逻辑
└── OhMyUsagePresentation  # 展示层逻辑

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
