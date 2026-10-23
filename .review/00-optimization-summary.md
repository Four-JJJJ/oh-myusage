# OhMyUsage 优化建议汇总（2026-10-17）

> 审查对象：`oh-myusage` @ `main` / `947d454` / VERSION 2.5.4（含工作树 9 个未提交改动）
> 方式：Lead 实测构建/测试 + 4 路只读并行审查（架构、运行时性能、Provider/凭证/配置、UI/测试/CI）
> 约束：**未修改任何源码、未改动 git 状态**；改动前请先提交或 stash 当前工作树
> 详细报告：`01-architecture.md`、`02-performance.md`、`03-providers-data.md`、`04-ui-tests-build.md`

---

## 1. 实测基线

| 项 | 结果 |
|---|---|
| 代码规模 | Sources 352 文件 / **77,073 行**；其中 executable `OhMyUsage` **291 文件 / 71,539 行（92.3%）**，7 个分层 target 合计 61 文件 / 5,534 行（7.7%） |
| 默认 `swift build` | **失败**：resource bundle codesign 报 `resource fork, Finder information, or similar detritus not allowed` |
| `/tmp` 全新 scratch 构建 | **通过，15.3s**（`swift build --build-system native --scratch-path /tmp/...`，同一工作树） |
| 全量测试 | **1,339 项通过，0 失败，40.7s**（同一 scratch path） |
| 编译警告 | 干净构建 **137 条警告日志 / 4 个真实位置**（见 P0-3），CI 无警告门禁 |
| 测试规模 | 163 文件 / 49,269 行 / 1,344 个 `func test` |
| 本地工具链 | Xcode-beta / Swift **6.4**；CI 固定 Swift **6.2.0**，仓库无 `.swift-version` |

构建失败根因已定位：仓库位于 Desktop（iCloud / file provider 同步域），`.build` 产物带
`com.apple.FinderInfo`、`com.apple.fileprovider.fpfs#P`，codesign 拒绝签名资源 bundle；
`.build` 还混有 Swift Build 与 Xcode 两套布局及 `.DS_Store`。**不是代码问题**，但本机默认开发体验是坏的。

---

## 2. 总体评价

这是一个成熟度较高的项目：正确性工程做得扎实（1339 测试、配置有损解码 + 4 快照恢复、缓存有界、
WAL 指纹、revision/epoch 防晚到、可见性驱动刷新、状态栏渲染去重），历史优化文档也真实落地了大部分。
本轮审查找到的优化空间集中在四类：

1. **少量真实正确性/安全风险**（凭证与会话数据、配置恢复）——优先级最高，因为会静默丢数据；
2. **常驻能耗/主线程 I/O 残留**（一个 0.75s 永久 Timer、session 监控在主线程扫 SQLite/JSONL）；
3. **架构投入产出比失衡**（92% 代码仍在单一 executable；两个分层 target 生产零引用；护栏测试靠字符串扫描）；
4. **工程化门禁缺失**（构建不可复现、137 警告、CI 只有 build+test、发布流程不跑测试）。

---

## 3. P0：建议本周做（低风险、直接止损）

### P0-1 【安全/丢数据】Keychain vault 双实例 + 锁外整份写回 → 可静默丢凭证

- 证据：生产 `AppViewModel()` 的默认参数 `codexDesktopAuthService: CodexDesktopAuthService = CodexDesktopAuthService()`（`Sources/OhMyUsage/App/AppViewModel.swift:289`）会构造**自带独立 KeychainService** 的实例（`Sources/OhMyUsage/Services/CodexDesktopAuthService.swift:51-53`）；`AppCompositionFactory.swift:44` 的 `?? CodexDesktopAuthService(oauthVault: oauthVaultStore)` 因而永不生效。`KeychainService.saveToken` 在锁外把**整份 tokenCache 快照**写回（`Sources/OhMyUsage/Services/KeychainService.swift:160-183`），两个实例谁后写谁覆盖。
- 影响：账号切换/同步（`AppOfficialProfilesModel.swift:264` 写 vault）与其它 provider 保存凭证交错时，可能丢掉刚写入的 key，用户表现为“保存过又要重新授权”。
- 改法（S）：组合根只持有一个 `KeychainService`/vault；`CodexDesktopAuthService` 默认参数去掉，改为必填注入；`saveToken` 串行化（单写入队列 + 合并写 + 失败回滚）。
- 验证：新增“两个入口交错保存不同 provider → 两份都在”的 focused test；`CredentialBrokerTests`/`AppOfficialAccountSwitchCoordinator` 回归。

### P0-2 【安全】OAuth token 明文落 Application Support

- 证据：`CodexAccountProfile.authJSON` / `ClaudeAccountProfile.credentialsJSON` 直接存 access/refresh token（`Sources/OhMyUsage/Models/OfficialAccountProfileModels.swift:26,74`），两个 store 用 `data.write(to:options:.atomic)` 落盘（`CodexAccountProfileStore.swift:362`、`ClaudeAccountProfileStore.swift:979`），未设 0600。
- 改法（S–M）：先补 `posixPermissions = 0o600` + 目录 0700（止血）；中期把 token 字段改为只存 Keychain 引用，profiles JSON 只留元数据。
- 验证：写盘后断言权限位；旧文件读取兼容测试。

### P0-3 【质量门禁】清 4 处编译警告并让 CI 对警告变红

- 真实位置：
  1. `Sources/OhMyUsage/App/AppViewModel.swift:567` — `DispatchQueue.global` 闭包里访问 MainActor 的 `self`（`#SendableClosureCaptures`），把 `keychain` 先取出为局部常量再进后台；
  2. `Sources/OhMyUsage/App/SettingsSceneWindowPolicy.swift:35-36` — `window.title`/`contentViewController` 在 nonisolated 上下文访问，函数标 `@MainActor`；
  3. `Sources/OhMyUsage/UI/MenuPermissionGuideView.swift:7` — 缺 `import OhMyUsagePresentation`。
- 改法（S）：修 4 点 + CI 加 `swift build -Xswiftc -warnings-as-errors`（或先用 `-warnings-as-errors` 仅构建主 target 过渡）。
- 验证：干净构建 0 警告；故意加回一处警告确认 CI 必红。

### P0-4 【能效】删掉生命周期常驻的 0.75s 窗口扫描 Timer

- 证据：`OhMyUsageApp` 已无 SwiftUI `Settings` scene（`Sources/OhMyUsage/App/OhMyUsageApp.swift:1-9` 注释自证），但 `RuntimeGuards.swift:78` 仍启动 `SettingsScenePhantomWindowGuard`；其内部 `pollInterval = 0.75`、`Timer(repeats: true)` 加入 RunLoop `.common`、全生命周期不 invalidate，每 750ms 在 MainActor 扫一遍 `NSApp.windows`（`Sources/OhMyUsage/App/SettingsScenePhantomWindowGuard.swift:20,56-71`）——**约 11.5 万次唤醒/天**，与项目“低能耗”目标直接矛盾。
- 改法（S）：删除 guard 与 `schedulePhantomSweeps` 的定时部分，仅保留 `didBecomeKey/didBecomeMain/didBecomeActive` 事件驱动 + 打开设置后一次性 sweep；若仍担心回归，把轮询改成“最多运行 10 分钟的自限时 timer”。
- 验证：`SettingsSceneWindowPolicyTests`/`SettingsScenePhantomWindowGuardTests` 改后绿；Instruments / `powermetrics` 观察 idle wakeups 下降（务必实测后再声称）。

### P0-5 【配置恢复】全量损坏路径“保留 fallback”刚写入就被删除

- 证据：`ConfigStore.swift:96-103` 先 `preserveFallbackCandidateIfNeeded(preservedFallbackData)`，紧接着 `save(defaultConfig)` → `ConfigSnapshotWriter.save(clearPreservedFallbackCandidate: true)`（`ConfigSnapshotWriter.swift:24-39`、`:81-85`）立刻删掉候选文件 → 用户损坏前的原始配置（唯一可手工恢复的数据）丢失；无测试覆盖。
- 改法（S）：该分支改为 `saveDuringBootstrap` 同款 `clearPreservedFallbackCandidate: false`，并加“全量损坏 → 重启 → candidate 仍存在”的测试。
- 验证：`swift test --filter ConfigStoreTests` + 新增用例。

### P0-6 【构建可复现】统一构建入口，修 xattr 问题

- 改法（S）：新增 `scripts/dev.sh`/`Makefile` 统一 `SCRATCH=$(mktemp -d)/build` 或 `~/Library/Caches/oh-myusage/build`，所有文档/CI 走同一入口；`package_dmg.sh` 用 `swift build --show-bin-path` 定位产物而不是按 mtime 猜路径；AGENTS.md/README 写入排查说明（或在非 iCloud 目录开发）。
- 验证：在 Desktop 路径下 `./scripts/dev.sh build/test` 一次通过；干净 clone + 脚本可复现。

---

## 4. P1：建议 1–2 周内做（收益明确）

| # | 项 | 证据/现状 | 改法 | 成本 |
|---|---|---|---|---|
| 1 | provider fetch 的 detached Task 不接取消 | `AppProviderRefreshCoordinator.swift:478-485` 裸 `Task.detached{...}.value`；stop/restart/reset/退出时父任务取消但网络/子进程继续跑到超时（provider 15–20s、Cursor 60s、Codex CLI 回退最坏 ~40s） | 照抄仓库已有模式：`withTaskCancellationHandler` + `worker.cancel()`；配置变更时去重 | S |
| 2 | 本地 session 监控在主线程做同步 FS + SQLite + 整文件 JSONL 解析 | `ProviderRefreshScheduler.swift:419-451` 是 `Task @MainActor`；`LocalSessionCompletionSignalMonitor.swift:99-118,163-288` 同步 stat/sqlite/枚举/逐行 JSON；每 10–30s（活跃）/30–120s（idle） | 监控内部串行 actor 或 `Task.detached(priority:.utility)`；协议 async 化；Claude JSONL 改增量尾部读 | M |
| 3 | 每次 official 刷新在 MainActor 同步读写 profile/slot JSON | `AppProviderRefreshModel.swift:193-213` → `CodexAccountProfileStore.swift:165,328-336`、`CodexAccountSlotStore.swift:147-152,469-479`（原子写 + prettyPrinted，每次刷新必写） | store 内串行 IO queue + 合并写 + 内容未变跳过（参考 `PersistedSnapshotCache`） | M |
| 4 | 配置保存主线程同步写 4 文件 + 2 次编解码，无去重 | `ConfigSnapshotWriter.swift:24-40,57-79` | 内容指纹相同跳过；写盘排队；只对变化的快照重写 | S |
| 5 | 官方 provider 429 不解析 Retry-After；20 个 provider 各内联 HTTP 状态校验（约 400–600 行）；relay token/balance 403 语义不一致 | `grep statusCode` Providers 41 处；Retry-After 只在 `OhMyUsageProviders/RelayHTTPClient.swift:50,90`；Claude/Codex 未复用 `requestWithExpiringCredentialRefresh` | 抽 `OhMyUsageProviders/HTTPResponseValidation`（429/408/5xx/cancel/HTML/可配 403）+ 统一错误分类，先迁 Claude/Codex/Gemini/RelayHTTPClient | M |
| 6 | 英文界面存在整页中文 | `UsageAnalyticsSettingsView.swift`（731 行，可从设置进入）0 处本地化调用、34 行硬编码中文；`"加油包"` 硬编码于 `SettingsQuotaDisplayHelpers.swift:351`、`MenuQuotaPresenter.swift:259` | 补 L10nKey/内联双语；CI 加“UI 新增 CJK 行”ratchet 门禁 | S–M |
| 7 | 本地化三套机制并行 | L10nKey 双 switch + 约 400 处内联 `localizedText(zh,en)` + 70+ 处 `language == .zhHans` 三元；Localization.swift 之外 88 文件含 8,646 个中文字符 | 定规则（新代码只允许一种写法）+ ratchet；按正在改的文件顺带迁移 | M |
| 8 | 数字/百分比格式化 ≥8 处重复且口径不一致 | `SettingsLocalUsageTrend.swift:507-536` 自成一套（w/tok）vs `UsageDisplayFormatter.swift:455-540`（万/K）；6 份 `NumberFormatter+%.2f` 副本 | 收敛到单一 Formatter API，统一单位口径（tok/tokens、次/req） | S |
| 9 | 架构“剧场”：92.3% 代码在 executable；Features/Bootstrap 生产零引用；`Domain.ProviderConfiguration` 生产引用为 0 | `Package.swift:17-67`；`OhMyUsageFeatures`/`Bootstrap` 只被架构测试 import；Domain 模型未被任何持久化路径使用（真正持久化是 `Models/ProviderDescriptor`） | 删 Features/Bootstrap + 7 个 marker + 死 Domain 模型，收窄 executable/test 依赖；更新过期 `.codex` 交接文档（其描述的分支/staged/804 tests 均已失真） | S |
| 10 | 架构护栏靠源码字符串/行数断言（重构税） | 5 文件 2,080 行/52 test；`MonolithRetirementBoundaryTests` 171 个断言含 132 `.contains`、27 `fileExists`；`ArchitectureTargetBoundaryTests.swift:708` 断言精确多行文本与缩进 | 保留 3 类真约束（target 依赖图/层间 import 禁令/executable 类型引用），其余改数据驱动 ratchet 或编译期边界；8 个测试文件依赖 `currentDirectoryPath` 需改为 `#filePath` | M |
| 11 | 无运行时性能/卡顿基线 | 全仓库无 signpost/MetricKit/主线程卡顿检测；README 自述未测启动/CPU/内存/能耗 | 加 DEBUG signpost（startup/refresh/session-scan）+ 主线程 50ms 心跳计数 + 一个 `scripts/measure.sh`（RSS/CPU/wakeups）；先有基线再谈收益 | S |
| 12 | 无低电量/热压力/锁屏/睡眠自适应 | 全仓库无 `isLowPowerModeEnabled`/`thermalState`；ResourceMode 纯手动，锁屏后仍按后台地板刷新 | 在 scheduler 加策略：低电量/热压力/锁屏时拉长间隔或暂停（可注入 `ProcessInfo` seam） | M |
| 13 | Grok/Gemini 本地用量每次调用新建枚举缓存 → 缓存必 miss | `GrokLocalUsageService.swift:59`、`GeminiLocalUsageService.swift:38` 每次 `LocalUsageFileEnumerationCache()`；Claude/Kimi 用 `static let` | 改 `static let`（2 行） | S |
| 14 | 设置窗口配套死代码 | `settingsUsesLightAppearance` 硬编码 `false`（`SettingsViewTheme.swift:219-221`），44 处浅色分支为死代码；`SettingsWindowAppearanceController` 仅被自身测试引用 | 接线或删除二选一 | S |

---

## 5. P2：中期（架构与工程化，按 PR 分批）

1. **SettingsView 类型级拆分（最大单项，L）**：`SettingsView` struct 144 行，但被 21 个文件 extension 成 **12,303 行 / 398 方法**；UI 通过 695 处访问 `AppViewModel` 的 115 个成员。按 pane 拆 `SettingsProviderSidebarPane`/`RelayConfigurationForm`/`OfficialSubscriptionPane` + 独立 `@Observable` draft model，先补设置页快照基线。
2. **中枢类拆分**：`AppConfigurationModel`（1,033 行、59 func、8 类配置变更 + 反向 `requireHost()`）按事务拆 4 个 coordinator；`RelayResponseInterpreter`（1,200 行、vendor 特例 690+ 行）按 vendor 拆文件 + `RelayPostprocessID -> handler` 注册表；`LocalUsageHistoryRepository`（1,093 行）纯移动拆 4 文件。
3. **Relay 扩展性数据化**：新增站点目前要改 8 文件约 45 处 `manifest.id` 分支；优先把 `valueScale`/`businessErrors`/`secondaryRequest` 变成 manifest 字段，并给内置 JSON 加 `validate()`。
4. **Codex/Claude OAuth refresh 统一**：两者仍手写同构的“刷新→字段更新→JSON 回写→vault 回写”，其余 5 家已复用 `requestWithExpiringCredentialRefresh`；抽 `OAuthRefreshPipeline<State>` 并让写盘失败可观测（当前 `updateJSONObjectFile` 全 `try?` 静默）。
5. **AppConfig 防御**：无 `schemaVersion`、枚举严格 decode，未知值/手改配置整份 invalid；建议 schemaVersion + 枚举字段级降级。
6. **CI/发布硬化（S–M）**：CI 仅 26 行（无缓存、无 concurrency、无 timeout、无警告/格式门禁、无覆盖率）；release workflow 不跑测试、无签名 secrets（GitHub 版永远 ad-hoc）、VERSION 只改不提交；`package_dmg.sh` 无 trap 清理、`--deep` 签名已不推荐、按 mtime 猜产物路径。建议：release 前跑全量测试 + 增加 release 构建 job + 用 `--show-bin-path` + 缓存 `.build` + pin actions 到 SHA + 提交 `.swift-version`。
7. **测试套件质量**：46 条源码扫描式架构断言、8 文件 48 处 `currentDirectoryPath`（Xcode cwd 下会直接失败）；`MenuVisualSnapshotRenderingTests` 占全量 40.7s 中约 9.6s（settle 循环、无像素断言、固定写 `/tmp` 不清理）→ 建议 env-gated（`RUN_VISUAL_SNAPSHOTS=1`）并清理输出；清理后可开 `swift test --parallel`。
8. **可访问性**：81 个 Button 仅 24 个有 label；菜单 3 个图标按钮无 label/help；设置页几乎无 Esc 关闭处理 → 批量补 `accessibilityLabel`/`.help`/`.keyboardShortcut(.cancelAction)`。
9. **Presentation 层空转**：`OhMyUsagePresentation` 仅 361 行，而 `UI/Presenters` 20 文件 3,333 行仍在 app target 且 `RelayStatusPresenter` 直接产出 SwiftUI `Color`；建议迁纯 presenter（Color→Tone）。
10. **产品向小建议**：无“导出诊断”入口（内部有大量 diagnostics 但无 `NSSavePanel`/复制按钮）；设置页无键盘关闭；浅色模式为死分支（若产品决定只做暗色，删代码；否则接线）——可按产品取舍。

---

## 6. 建议执行顺序

**批次 1（1–2 天，止损 + 体验）**：P0-1 凭证写入收敛 → P0-2 权限位 → P0-5 配置恢复 → P0-4 删 0.75s timer → P0-3 警告清零 + CI `-warnings-as-errors` → P0-6 构建入口。
**批次 2（3–5 天，运行时与一致性）**：P1-1 取消传播 → P1-4 配置保存去重 → P1-13 两行缓存修复 → P1-6/7/8 本地化与格式化收敛 → P1-9 死层/死模型清理 → P1-11 可观测性基线。
**批次 3（1–2 周，主线程与工程化）**：P1-2 session 监控下沉 → P1-3 store 异步化 → P1-5 HTTP 校验收敛 → P1-10 护栏换代 → CI/发布硬化 → 再评估 P2 的 Settings 拆分。

每批结束跑：`swift build`（0 警告）+ `swift test`（1339+ 全绿）+ 相关 focused tests；涉及 UI/凭证的改动补截图/权限位断言。

---

## 7. 不要回退的正向资产

- 1,339 测试全绿、测试/代码比高；`ConfigStore` 有损解码 + LKG/备份/恢复快照；`PersistedSnapshotCache` 有界 + 原子写 + IO queue；
- 缓存上界与 TTL 体系（官方快照 64/24h、analytics 16/32MiB、历史 24/16MiB、解析缓存 512/30min）；
- 可见性驱动时钟（菜单/设置/状态栏分开）、状态栏渲染去重、429 Retry-After（relay 通道）、离线暂停、revision/epoch 防晚到；
- `AppCompositionFactory`/`AppDependencyGraph` 收口、`ProviderStateStore` 单一写入口、6 家官方 provider 已复用 auth runtime。
