# OhMyUsage 运行时性能 / 能效 / 并发审查（审查 B）

- 项目：`/Users/fourj/Desktop/Vibe Coding/oh-myusage`，VERSION 2.5.4，Swift 6.2 / strict concurrency，macOS 菜单栏常驻 app
- 审查方式：只读源码（grep + 定向阅读），**未** 运行 `swift build` / `swift test` / Instruments / `powermetrics`；所有“耗时/能耗/内存”结论均为代码推理 + 可验证测量方案，**不包含编造的百分比收益**
- 基线事实：`Sources/` 共 8 个 target、约 77,073 行 Swift；本报告聚焦常驻期（启动后 idle、菜单栏刷新、设置页）与刷新链路
- 关键前提（README/优化文档自述）：`README.md:24` 明确“尚未测量优化前后的启动耗时、CPU、内存或能耗”。因此“无实测基准”本身是一条发现（F5），本报告所有收益排序都是**代码证据强度 × 调用频率**的推断，不是实测排序
- 已核对历史优化（避免重复建议）：单 poll loop + per-provider in-flight、可见才 tick 的 VisibleClockController、StatusItemController 渲染去重、PersistedSnapshotCache（64 项 / 512 KiB / 原子写）、官方 provider 缓存（64 项 LRU / 24h stale）、analytics / history 缓存异步 IO 与上界、浏览器凭证路径 TTL、CCSwitch SQLite streaming、source fingerprint TTL、429 Retry-After、离线暂停、取消/单飞（多处 `withTaskCancellationHandler`）。这些在代码中均真实存在，见 §6

---

## 1. 结论摘要（按 收益/成本 排序，详见 §3）

| # | 发现 | 类别 | 频率 | 证据强度 | 修复成本 | 预期收益（方向，未实测） |
|---|---|---|---|---|---|---|
| F1 | **本地 session 完成信号监控（Codex SQLite + Claude 目录枚举/整文件 JSONL 解析）直接在 MainActor 上跑** | 主线程阻塞 / 能耗 | 每 10–30s（活跃）/30–120s（idle），仅当菜单栏展示 Codex/Claude official | 高 | M | 消除周期性主线程 FS/DB/解析停顿；随 Claude 会话文件增大而放大 |
| F2 | 每次 official provider 刷新，MainActor 上同步读/写 profile/slot JSON（含原子写、prettyPrinted 编码） | 主线程 I/O | 每个 displayed official provider 每 180–300s（后台 900s） | 高 | M | 消除每刷新周期的主线程小写盘；减少卡顿毛刺 |
| F3 | provider fetch 的 `Task.detached` 未接取消：scheduler stop/restart、reset、退出时父任务取消，但网络请求继续 | 并发/能耗 | 配置变更、reset、退出、重启轮询 | 高 | S | 少发重复/孤儿请求；取消语义变真实 |
| F4 | 配置持久化：MainActor 同步写 4 个文件 + 2 次 JSON 编解码（prettyPrinted+sortedKeys），且无“内容相同跳过” | 主线程 I/O | 每次设置变更（每个开关/保存） | 高 | S | 设置项点击更跟手；减少重复写盘 |
| F5 | 没有运行时可测量基线：无 signpost、无主线程卡顿检测、无 CPU/能耗/RSS/wakeups 采集；只有设置页一次性 RSS 探针 | 可观测性（使能项） | 常驻 | 高 | S | 让 F1–F12 的收益可证伪、可回归 |
| F6 | 启动路径在 main 上串行做：配置加载（最多 5 个候选文件/可能迁移写盘）、4 个 store JSON 读、launch-at-login 迁移、profile 同步、双份权限探测 | 启动耗时 | 每次冷启动 | 中高 | M | 缩短首帧/首次可交互延迟（需先测量） |
| F7 | 切换 Space（`activeSpaceDidChange`）触发 1+3 次状态栏外观刷新，每次都 `NSImage(contentsOf:)` 全量解码壁纸算亮度 | 主线程阻塞 / 能耗 | 每次切 Space、换壁纸 | 中 | S–M | 切 Space 时状态栏不再卡顿；减少重复解码 |
| F8 | 无任何低电量/热压力/锁屏/睡眠自适应：ResourceMode 纯手动，屏幕已锁仍按后台地板刷新 | 能效策略 | 常驻 | 高（缺失性证据） | M | 低电量/锁屏期间可明显降频；但改变数据新鲜度语义 |
| F9 | `GrokLocalUsageService` / `GeminiLocalUsageService` 每次调用**新建**枚举缓存实例，缓存必然 miss；Claude/Kimi 用 `static let` | 重复目录枚举 | 打开统计/趋势、刷新本地用量时 | 高 | S（2 行） | 恢复目录枚举缓存命中，减少重复 stat/enumerate |
| F10 | Codex CLI RPC 回退路径：一次刷新最多 spawn 3 个 `codex app-server` 子进程，并用 `Thread.sleep(3/10/18s)` 占用线程与刷新槽 | 能耗 / 刷新时延 | 仅 `sourceMode=cli/auto` 且 API 路径失败时 | 高（条件触发） | M | 消除最坏 ~40s/次 的刷新槽占用与 3 次进程启动 |
| F11 | 凭证保存把**整个 vault JSON** 同步写 Keychain（`SecItemUpdate`）在 MainActor 上 | 主线程 I/O | 每次保存/删除凭证 | 中 | S–M | 保存按钮响应更快（Keychain 写 5–50ms 级） |
| F12 | 统计原始记录内存上界按“条数 100k”而非字节；`UsageAnalyticsSnapshot` 16 项缓存无字节预算；`.all` 范围 bucket 数随历史线性增长 | 内存上界 | 打开统计页（用户显式操作） | 中 | M | 内存峰值可控、可诊断（需 RSS 测量） |

“疑似真 bug/竞态”单独见 §4（R1–R4）。其中 **R1 是 F3 的并发正确性表述**，若 Lead 只修一处，按 R1 处理即可。

---

## 2. 运行时快照（实测自源码）

### 2.1 常驻周期任务清单（全量 grep：`Timer|Task.sleep|DispatchSourceTimer|AsyncStream|asyncAfter|scheduleTimer`）

| 任务 | 位置 | 间隔 | 启停条件 | 菜单关闭/后台时是否运行 |
|---|---|---|---|---|
| Provider 刷新 poll loop（单 loop + nextDueAt） | `Sources/OhMyUsageApplication/ProviderRefreshScheduler.swift:269`，sleep at `:295-305` | 按 provider 到期时间：displayed = max(user, plan.activeTTL, 180s)；非 displayed = max(mode 地板, plan.backgroundTTL 900/1800s)（`:474-491`） | 有 enabled providers | 是（这正是设计目标）；离线时暂停（`:315-326`） |
| startup jitter | `ProviderRefreshScheduler.swift:168,216-219` | 0–20s 随机 | 每次 `restart(providers:)` | — |
| 本地 session 信号 loop | `ProviderRefreshScheduler.swift:419-451` | active 10–30s / idle 30–120s（`AppViewModel.swift:943-977`；`RuntimeDiagnostics.swift:16-17`） | 仅当菜单栏显示的 provider 中有 official Codex/Claude（`:453-462` + `AppProviderRefreshModel.swift:274-276`） | 是（只要菜单栏展示） |
| 菜单面板可见时钟 | `Sources/OhMyUsageApplication/VisibleClockController.swift:24-32`；`UI/MenuContentView.swift:463-484` | 5s（`RuntimeDiagnostics.swift:18`） | `viewModel.menuPanelVisible` | 否（隐藏即 cancel） |
| 状态栏可见刷新时钟 | `App/StatusBarController.swift:136-142` | 60s（`RuntimeDiagnostics.swift:19`） | 仅菜单面板打开 | 否 |
| 设置页时钟 | `UI/Settings/SettingsClockAndActions.swift:117-129`；默认 15s（`VisibleClockController.swift:10`） | 15s | `settingsWindowVisible` | 否 |
| 通知权限授权轮询 | `App/AppPermissionCoordinator.swift:48-74` | 20 × 0.5s | 仅在用户请求通知权限时 | 否 |
| 更新下载/安装等待 | `App/AppUpdateCoordinator.swift:325,356` | 秒级 sleep | 仅更新流程 | 否 |
| Codex Desktop 重启轮询 | `Services/CodexDesktopAppService.swift:130` | 0.25s × 超时（约 4s/2s） | 仅账号切换 | 否 |
| 临时反馈/设置保存状态清除 | `App/AppTransientFeedbackCoordinator.swift:28`；`App/AppSettingsPersistenceFeedbackCoordinator.swift:99` | 按注入延迟 | 用户操作后 | 否 |
| 壁纸外观跟随刷新 | `App/StatusBarAppearanceController.swift:161-183` | 0.12/0.35/0.8s 三次 + `NSWorkspace.activeSpaceDidChange`（`:44`）/分布式壁纸通知（`:94-107`） | 事件驱动（切 Space、换壁纸、屏幕参数变化） | 否（事件） |
| Cursor dashboard 总 deadline | `Services/CursorLocalUsageService.swift:200` | 60s 上限 | 仅 fetch 期间 | 否 |

结论：**没有“opened-file 型无界轮询”**；常驻周期任务只有 poll loop 与本地 session 信号 loop 两条，且都有明确的启停/可见性条件。真正值得优化的是后者在 MainActor 上做重 I/O（F1）与 poll loop 的取消语义（F3）。

### 2.2 MainActor 上的同步 I/O 盘点（grep 交叉验证）

- `App/` 目录整体干净：除 `AppViewModel.swift:383`（`#if DEBUG` 测试临时目录）外无直接 `FileManager/SQLite/SecItem/Process`。
- 以下调用链在 MainActor 上同步执行（本报告核心证据）：
  - 本地 session 监控：`ProviderRefreshScheduler.swift:419-451 → :113-122 → LocalSessionCompletionSignalMonitor.swift:68-137,163-288`（FS + SQLite + JSONL 解析）
  - official 刷新前后：`AppProviderRefreshModel.swift:193-213 → AppOfficialProfilesModel.swift:385-437 → AppOfficialProfileSyncCoordinator.swift:22-70 → CodexDesktopAuthService.swift:66-78 / CodexAccountProfileStore.swift:165,328,332,336 / CodexAccountSlotStore.swift:147-152,469-479 / ClaudeAccountSlotStore.swift:62,244-252`
  - 配置保存：`AppConfigurationModel.swift:805-830 → AppConfigurationMutationCoordinator.swift:91-103 → AppConfigurationRepository.swift:61-63 → ConfigStore.swift:112-130 → ConfigSnapshotWriter.swift:24-40`
  - 凭证保存：`AppConfigurationModel.swift:183-214 → CredentialAccessService.swift:56-64 → KeychainService.swift:160-181,569-581 → Security.framework`
  - 壁纸亮度：`StatusBarController.swift:136-142,230-273 → StatusBarAppearanceController.swift:36-41,161-183 → WallpaperAppearanceService.swift:81-88 → StatusBarAppearanceResolver.swift:32-80`
  - 启动：`RuntimeGuards.swift:79 → AppViewModel.swift:283-330,390-474 → AppCompositionFactory.swift:15-102 → ConfigStore.swift:26-110` + 各 store init `load()`
- 已正确 off-main 的重 I/O（无需再改）：provider fetch（`AppProviderRefreshCoordinator.swift:478-485` detached）、analytics fingerprint/snapshot（`App/UsageAnalyticsRefreshCoordinator.swift:95-103,145-151`）、本地趋势 loader/fingerprint（`LocalUsageHistoryRepository.swift:757-796`）、持久快照缓存 IO queue（`PersistedSnapshotCache.swift:176`）、analytics 缓存 IO queue（`UsageAnalyticsSnapshotCacheStore.swift:121`）、Keychain 读（`CredentialAccessService.swift:147-162`）、全盘权限探针（`AppPermissionCoordinator.swift:189-194`）。

### 2.3 缓存/内存上界核对（grep `maxEntries|capacity|prune|evict|LRU`）

| 缓存 | 上界 | TTL/淘汰 | 评价 |
|---|---|---|---|
| `PersistedSnapshotCache` | 64 条 / 512 KiB | 溢出按时间淘汰；原子写；IO queue | 合格（`PersistedSnapshotCache.swift:171-172`） |
| `FetchedAtOfficialSnapshotCache` / `SnapshotTimestamp...` | 64 条 / 24h stale | LRU + generation 失效 | 合格（`OhMyUsageProviders/OfficialProviderFetchRuntime.swift:121-156`） |
| `UsageAnalyticsSnapshotCacheStore` | 16 条 / 32 MiB 恢复预算 | 最旧淘汰 + 同内容跳过 | 合格（`UsageAnalyticsSnapshotCacheStore.swift:140-148,293-342`） |
| `LocalUsageHistoryRepository` | 24 条 / 16 MiB 读取预算 | TTL 15min + 最旧淘汰 | 合格（`RuntimeDiagnostics.swift:6,11`；`LocalUsageHistoryRepository.swift:1004`） |
| `ProviderValueCache` | 默认 32 条 | TTL + 溢出淘汰 | 合格（`Services/ProviderFetchCaches.swift:24-118`） |
| `LocalUsageParsedFileCache` | 512 项 / 32,768 values | LRU + 30min | 合格（`RuntimeDiagnostics.swift:7-8`；`LocalUsageHistoryRepository.swift:328-430`） |
| `LocalUsageFileEnumerationCache` | 8–32 项（每项保存全部 path snapshot） | 元数据校验命中 | 设计合理，但存在“实例化后丢弃”误用（F9） |
| `WallpaperAppearanceService` | 12 条 | FIFO + 显式 clear | 合格（`WallpaperAppearanceService.swift:10,76-79`） |
| `UsageAnalyticsRepository.rawEntry.records` | ≤100,000 条（**按条数，不按字节**） | 60s 复用 | 见 F12：字节上界缺失 |
| `UsageAnalyticsSnapshotCacheStore` 内 snapshot | 16 条（无字节预算） | 见上 | 见 F12：`.all` 范围快照可较大 |
| Keychain `tokenCache` / `missingCache` / `SecurityCredentialReader.credentialCache` | 按配置的 service/account 数量 | TTL（security reader 120s/8s）；missing 常驻 | 有界（配置规模决定），可接受 |

---

## 3. 发现详情（F1–F12，按 收益/成本 排序）

### F1. 本地 session 信号监控在 MainActor 上做同步 FS + SQLite + 整文件 JSONL 解析（P0，成本 M）

**现象**
常驻的 `localSessionSignalLoop` 是 `@MainActor` Task；每轮同步调用 `LocalSessionRefreshCoordinator.refreshCandidates`，后者同步调用 monitor 的两个方法。monitor 内部：
- Codex：对 `~/.codex/logs_2.sqlite`（+ `-wal`/`-shm`）做 3 次 stat，快照变化时 `sqlite3_open_v2` + `LIKE '%…%'` 查询（`ORDER BY ts DESC LIMIT 1`）；
- Claude：每 60s 对 `~/.claude/projects` 做**递归 directory enumeration + 每文件 stat**，最多跟踪 200 个最近 jsonl；对有变更的文件**从文件头整文件流式扫描**，对包含 `"type":"assistant"` 和 `"usage"` 的行做 `JSONSerialization` 解码。

**证据**
- `Sources/OhMyUsageApplication/ProviderRefreshScheduler.swift:424-451`（`private func localSessionSignalLoop()`，`:432` 同步 `refreshCandidates`），`:113-122`（`latestCodexCompletionAt()/latestClaudeCompletionAt()` 直接同步调用）
- `Sources/OhMyUsage/Services/LocalSessionCompletionSignalMonitor.swift:139-161`（stat/log snapshot）、`:99-118`（SQLite open/prepare/step）、`:163-216`（`FileManager.enumerator` + 逐文件 `resourceValues`）、`:224-238`（变更文件整文件解析）、`:268-288`（逐行整文件扫描 + JSON 解码）、`:303-361`（`scanJSONLLines`，只有 512 KiB/行上限，**没有整文件预算**；`jsonlMaxFileBytes` 只在 Kimi 扫描里用）
- 触发条件：`ProviderRefreshScheduler.swift:453-462`（只对菜单栏展示中的 official Codex/Claude）+ `App/AppProviderRefreshCoordinator.swift:155-168`（`localSessionWatchKind` 仅 codex/claude official）
- 间隔来源：`App/AppViewModel.swift:943-977` + `RuntimeDiagnostics.swift:16-17`

**根因**
`LocalSessionCompletionSignalSource` 协议是同步签名（`ProviderRefreshScheduler.swift:8-11`），被 @MainActor 类直接使用；monitor 是普通 class，没有自己的 actor/队列隔离。

**建议（不改协议语义的最小改法）**
1. 把 `LocalSessionCompletionSignalSource` 两个方法改成 `async`，`LocalSessionRefreshCoordinator.refreshCandidates` 改 `async`；在 monitor 上用私有 `actor`/`DispatchQueue` 串行隔离，主线程只拿 `Date?`；
2. 或者更小侵入：在 `localSessionSignalLoop` 里用 `Task.detached(priority: .utility)` 包住 `refreshCandidates` + `withTaskCancellationHandler`（与仓库里已有模式一致，见 `LocalUsageHistoryRepository.swift:757-762`），主 actor 只 await 结果；
3. Claude JSONL 改为**增量尾部读取**：记录上次读取的文件 offset + 尾行残留，只解析新增字节（当前每次从文件头读，会话越长越贵）；
4. Codex SQLite 查询前先看 `-wal` 尺寸变化（已有 snapshot），并把连接保持/查询下推到后台；可考虑 `PRAGMA busy_timeout` 与 `EXPLAIN QUERY PLAN` 验证索引使用。

**验证方式（可落地）**
- 在 monitor 外部加 `os_signpost` interval（category `session-monitor`，name `scan`），Instruments → Points of Interest 采样 10 分钟 idle，看 duration 与主线程重叠；
- 主线程卡顿心跳：主队列每 50ms 打点，记录 >100ms 的 gap（测试/DEBUG 构建启用），修复前后对比 gap 次数（这是计数，不是编造百分比）；
- 单元测试 seam：`LocalSessionCompletionSignalMonitorTests.swift` 已有计数断言（`diagnostics.codexSQLiteProbeCount/claudeEnumerationCount`）；新增“构造 1 个 20 MB jsonl fixture，断言首次 `latestClaudeCompletionAt()` 的**同步主线程占用**通过 `XCTMainActor` 心跳 < 阈值”，或注入 `currentThreadIsMain` 断言 I/O 不发生在 MainActor；
- 压力 fixture：`~/.claude/projects` 2,000 个 jsonl（本报告建议的 50k 压力扫描的一部分）。

**风险**
低。协议由 `ProviderRefreshSchedulerTests` 覆盖（`Tests/OhMyUsageTests/ProviderRefreshSchedulerTests.swift:580-614` 有 local session 触发/非活跃跳过用例），改 async 需要同步改测试；数据新鲜度语义不变。

---

### F2. 每次 official 刷新都在 MainActor 上同步读/写 profile & slot JSON（P1，成本 M）

**现象**
每次 Codex/Claude official 刷新（含自动轮询）在 `beforeRefresh` 里做 profile 同步，在 `transformFetchedSnapshot` 里把新快照写进 slot store；两者都在 MainActor 上同步读写 JSON 文件，其中 slot store 的 `save()` 是 `prettyPrinted + sortedKeys` 的**原子写**，且 `upsertActive` 每次都会更新 `lastSeenAt/isActive` → **每次成功刷新必写盘**。

**证据**
- `Sources/OhMyUsage/App/AppProviderRefreshModel.swift:193-213`（`beforeRefresh` + `transformFetchedSnapshot` 闭包）
- `Sources/OhMyUsage/App/AppProviderRefreshCoordinator.swift:304`（`beforeRefresh(descriptor)`）、`:312-313`（transform）
- `Sources/OhMyUsage/App/AppOfficialProfilesModel.swift:385-395`（`syncCodexProfilesCurrentState`）、`:415-437`（`syncClaudeProfilesCurrentState`）
- `Sources/OhMyUsage/App/AppOfficialProfileSyncCoordinator.swift:22-33`（`captureCurrentAuthIfNeeded`）、`:60-70`（`captureCurrentCredentialsIfNeeded`）
- `Sources/OhMyUsage/Services/CodexAccountProfileStore.swift:165-190`（每次 `load()` + `loadIgnoredFingerprints()` 两次读盘）、`:328-336`（`Data(contentsOf:)`）
- `Sources/OhMyUsage/Services/CodexAccountSlotStore.swift:147-152`（`upsertActive`）、`:469-479`（同步原子写）
- `Sources/OhMyUsage/Services/ClaudeAccountSlotStore.swift:62,244-252`（同样的写）
- `Sources/OhMyUsage/Services/ClaudeDesktopAuthService.swift:75-85`（vault miss 时 `fileExists`+`Data(contentsOf:)` 读 `~/.claude` 凭证文件，主 actor）
- `Sources/OhMyUsage/Services/CodexDesktopAuthService.swift:66-78`（同上，`~/.codex/auth.json`）

**根因**
“刷新动作前后需要最新账号状态”这个正确性需求，被实现成了主线程同步 store；store 本身没有异步/合并写机制（对比 `PersistedSnapshotCache` 的 IO queue + 合并写）。

**建议**
1. slot/profile store 改为内部串行 IO queue + 合并写（参考 `PersistedSnapshotCache.enqueueSave`），主 actor 只更新内存数组并投递写任务；
2. `save()` 加“内容未变则跳过”的指纹（slot 的 `lastSeenAt` 变动需要判断是否需要持久化，或把它从持久化字段拆出）；
3. profile 同步的磁盘读取放到 `Task.detached`，主 actor 只消费结果；如果 `captureCurrentAuthIfNeeded` 必须保持同步语义，至少把“读”缓存 30–60s（auth JSON 由 refresh 自身驱动变化，缓存失效点可挂在 credential 变更/刷新完成上）。

**验证方式**
- DEBUG 下给 store 包一层可注入 `FileManager` 记录器（或 `URLResourceValues` 计数），断言“一次 refresh 只产生 1 次写、内容不变时 0 次写”；
- `fs_usage -w -f filesys OhMyUsage` 观察 10 分钟 idle 中 `codex_slots.json`/`claude_profiles.json`/`provider_snapshots.json` 的写次数与大小（当前预期与刷新次数同阶）；
- signpost：`refresh.prepare` / `refresh.apply` 区间时长；Instruments Time Profiler 看主线程在该区间的栈。

**风险**
中低：store 是账号切换/恢复的正确性敏感路径，需保证写序（现有 `PersistedSnapshotCache` 有 revision/generation 机制可借鉴），并保留退出时 flush（`AppViewModel.swift:486-493`）。

---

### F3. provider fetch 的 detached Task 未接取消（P1，成本 S）

**现象**
`fetchProviderSnapshot` 用 `Task.detached { try await provider.fetch(...) }.value`。当父任务（runExclusiveRefresh 的 Task）被取消时，`await .value` 立即抛出 `CancellationError`，但 **detached task 不会被取消**：底层 `URLSession.data`/进程/DB 读取继续跑到请求超时（provider 普遍 15–20s，Cursor 60s，Codex CLI 回退最坏 ~40s），期间还可能开始第二次请求。

**证据**
- 缺失取消传播处：`Sources/OhMyUsage/App/AppProviderRefreshCoordinator.swift:478-485`
- 取消来源：`ProviderRefreshScheduler.swift:229-241`（`stop()` 取消 in-flight）、`:199-227`（每次 `restart` 先 stop；配置变更会触发 restart，`App/AppProviderRefreshModel.swift:95-100`）、`AppProviderRefreshCoordinator.swift:114-122`（reset/凭据变更 `invalidateRefreshes` 清 in-flight 并 cancel）、`AppViewModel.swift:486-493`（退出 stopPolling）
- 仓库内已有的正确模式（可照抄）：`LocalUsageHistoryRepository.swift:757-762,784-796`、`App/UsageAnalyticsRefreshCoordinator.swift:95-103,145-151`、`Services/CursorLocalUsageService.swift:404-410`

**根因**
没有对“可取消的 provider fetch”做统一封装；`Task.detached` 是刻意 off-main 的手段，但漏了 cancellation handler。

**建议**
```swift
private func fetchProviderSnapshot(using provider: any UsageProvider, forceRefresh: Bool) async throws -> UsageSnapshot {
    let worker = Task.detached(priority: .utility) { try await provider.fetch(forceRefresh: forceRefresh) }
    return try await withTaskCancellationHandler {
        try await worker.value
    } onCancel: {
        worker.cancel()
    }
}
```
并确认 provider 内部 `URLSession` 使用 async API 时会对 task cancellation 生效（`URLSession.data(for:)` 支持）；`Process`/SQLite 路径加 `Task.checkCancellation()`。

**验证方式**
- 新增 `ProviderFetchCancellationTests`：注入 `URLProtocol` stub（阻塞直到收到 cancel），调用 `coordinator.refreshProvider`，中途 `scheduler.stop()`/`invalidateRefreshes`，断言 stub 的 `stopLoading` 被调用 / 请求计数为 0 个“完成后仍开始”的孤儿请求（当前实现会失败 → 红测试先证明问题）；
- 运行时计数：`URLSessionTaskMetrics` 或 `URLProtocol` 计数“start 数 − finish 数”峰值，空闲/切配置 10 分钟观察。

**风险**
低。注意 join 语义：`runExclusiveRefresh` 中 joiner `await existing.value` 不应把 joiner 的取消传给共享请求（现有注释明确此语义，`AppProviderRefreshCoordinator.swift:110-113`），上述改法只影响“发起者取消”路径，与 joiner 语义兼容。

---

### F4. 配置持久化：主线程 4 文件同步写 + 双份编解码 + 无去重（P1，成本 S）

**现象**
任意设置变更（开关、保存 provider、状态栏显示偏好、账号档案变更）都会同步调用 config save：`JSONEncoder(prettyPrinted+sortedKeys)` 编码一次 → 写 `config.json`、`backup`、`recovery`（`options: .atomic` 各一次）→ 再 `AppConfig.decodeWithDiagnostics` 解码校验后写 `lastKnownGood`（第 4 次写）→ 删除 fallback candidate。全程在 MainActor。

**证据**
- `Sources/OhMyUsage/Services/ConfigSnapshotWriter.swift:24-40`（4 次写 + 校验解码）、`:57-65`（prettyPrinted/sortedKeys + 原子写）、`:67-79`（额外完整 decode）
- `Sources/OhMyUsage/Services/ConfigStore.swift:112-130`
- `Sources/OhMyUsage/Services/AppConfigurationRepository.swift:57-63`
- `Sources/OhMyUsage/App/AppConfigurationMutationCoordinator.swift:91-103`（`repository.saveResult(config)` 同步）
- `Sources/OhMyUsage/App/AppConfigurationModel.swift:805-830`（MainActor 调用点）
- 无“内容相同跳过”：`ConfigSnapshotWriter.save` 没有任何相等判断；`AppConfigurationMutationCoordinator` 的各 setter 有 `guard config.x != newValue`，但 profile/凭据/状态栏类路径会重复保存相等配置

**根因**
为崩溃恢复保留 primary/backup/recovery/lastKnownGood 四份；`saveResult` 的错误反馈需要同步返回 `ConfigurationMutationResult`。但“同步返回结果”不等于“4 次写都必须同步”。

**建议**
1. **先做去重**（零风险）：`ConfigStore` 保留上次成功写入的编码后 `Data`，相同则直接返回 `.success`（注意备份文件缺失时仍补齐）；
2. primary 保持同步写（保证错误反馈语义），backup/recovery/lastKnownGood 投递到串行 IO queue + 合并（参考 `PersistedSnapshotCache` 的 drain 模式）；退出时 flush（现有 `applicationShouldTerminate` 已有 2s best-effort 窗口，`RuntimeGuards.swift:89-109`）；
3. `lastKnownGood` 的 `decodeWithDiagnostics` 可改为“仅当内容变化时执行”。

**验证方式**
- 记录式 FileManager 单测：同一 config 连续 save 2 次，第二次写次数为 0（当前实现为 8 次写出）；
- signpost `config.save` 区间时长 + 主线程卡顿心跳；设置页连续开关 20 次的帧时间对比（Instruments Animation Hitches）。

**风险**
低（去重）；中低（异步化部分，需保证 reset/退出顺序与错误反馈）。

---

### F5. 缺少运行时可测量基线（P0 使能项，成本 S）

**现象**
代码库**没有任何 `os_signpost`/`OSSignposter`/`MetricKit` 打点**；`Logger` 只有 1 个文件使用；没有主线程卡顿/Wakeups/CPU 采集；唯一“诊断”是设置页渲染时的一次性 `RuntimeMemoryProbe.residentSizeBytes()`（`RuntimeDiagnostics.swift:76-98`，被 `AppViewModel.swift:763-777` 与 `SettingsGeneralAndMenuBarSections.swift:62-63` 在 SwiftUI body 里调用）。README 自述未测启动/CPU/内存/能耗。

**影响**
本报告 F1–F12 的收益无法被证实或回归；团队此前优化（2026-10-09 轮）也只能用“测试通过 + 样例耗时”自证。这本身是当前最大的流程性性能问题。

**建议（最小基线，1–2 天量级）**
1. 新建 `RuntimeSignposts`（`import os`）：`static let signposter = OSSignposter(subsystem: "com.oh-myusage.app", category: "refresh")`；至少在：启动各阶段、`performRefreshProvider` 的 prepare/fetch/apply/persist、`localSessionSignalLoop` 每轮、`refreshStatusDisplay`、`ConfigStore.save`、`WallpaperAppearanceService.wallpaperLuminance` 打 begin/end；
2. DEBUG/诊断开关下加主线程心跳（50ms 定时器，记录 >100ms gap 的调用栈摘要 + 计数），在设置页 diagnostics 中展示 `hangCount/maxGapMs`；
3. 采样脚本（不进入 CI）：`powermetrics -i 1000 --show-process-energy`、`vmmap -summary`、`log stream --predicate` 统计 wakeups、启动用`os_signpost`时间差；
4. 把 F1/F2/F3/F4 的计数 seam（见各自验证方式）落成 focused tests，作为回归护栏。

**验证方式**
自证：改动前后同一台机器同一场景（idle 10 分钟 / 打开菜单 60s / 切 10 次 Space / 冷启动 3 次）各采集 3 次，比较计数与 p95 区间时长。

**风险**
无（纯增量、默认轻量；signpost 在未 attach Instruments 时开销可忽略）。

---

### F6. 启动路径 main 上串行重活（P1，成本 M）

**现象**
`applicationDidFinishLaunching` 在 main 上同步 `AppViewModel()`：先 `loadProductionConfig()`（顺序读最多 5 个候选 JSON、可能触发 legacy import/迁移从而**写盘**），再构造 4 个 store（各自 `Data(contentsOf:)` 读 JSON）、`thirdPartyBalanceBaselineStore.load()`（UserDefaults）、`launchAtLoginService.migrateLegacyLaunchAgentsIfNeeded()`（文件系统操作）、`syncCodexProfilesCurrentState()`/`bootstrapClaudeProfileState()`（读 auth/credentials 文件 + 解析）、`restorePersistedOfficialProvidersIfNeeded()`、`refreshPermissionStatuses(force: true)`；`start()` 里再 force 一次权限刷新（同一帧内两次全盘探针/Keychain readiness 检查）。之后才开始 `app.run()`。

**证据**
- `Sources/OhMyUsage/App/RuntimeGuards.swift:62-83`（main 上创建 ViewModel）
- `Sources/OhMyUsage/App/AppViewModel.swift:283-330`（convenience init → 依赖图）、`:390-474`（private init 的启动副作用）、`:631-647`（`start()` 再 `refreshPermissionStatuses(force: true)`，与 init `:472` 重复）
- `Sources/OhMyUsage/App/AppCompositionFactory.swift:15-102`（keychain/network monitor/依赖图；`:87-102` 同步 config load）
- `Sources/OhMyUsage/Services/ConfigStore.swift:26-110`（最多 5 个候选、可能 `save(defaultConfig)`/`preserveFallbackCandidate` 写盘）
- `Sources/OhMyUsage/Services/CodexAccountSlotStore.swift:109-125`、`ClaudeAccountSlotStore.swift`、`CodexAccountProfileStore.swift:328-336`、`ClaudeAccountProfileStore.swift:945-965`（init 同步读）
- `Sources/OhMyUsage/App/AppPermissionModel.swift:209-219` + `AppPermissionCoordinator.swift:120-160`（权限刷新会取消上一个 task，导致 init 的探针可能白做）

**建议**
1. **先测量再动**：给启动各阶段加 signpost（F5），得到“launch→首帧/首次状态栏渲染/首次菜单可交互”三段数据；
2. 低风险子项：去掉 `start()` 里重复的 `refreshPermissionStatuses(force: true)`（保留 init 那次或反之），从源头避免同帧双探针；
3. 中风险：4 个 store 的 init 读取改为 `static async load` 或懒加载（首屏只需要 slots 的 `visibleSlots`，profiles 可稍后）；config 加载保持同步（正确性关键），但把“lastKnownGood/backup 校验读”移到后台；
4. `migrateLegacyLaunchAgentsIfNeeded` 移到启动后首个 runloop（`Task { @MainActor }`）并加一次性 marker。

**验证方式**
signpost 四段（process start→delegate、delegate→ViewModel init 完成、init 完成→首帧、首帧→首次菜单打开）+ `Instruments → App Launch`；冷启动 3 次取中位数，不要用单次数据。

**风险**
中：启动顺序与配置恢复语义耦合（`restorePersistedOfficialProvidersIfNeeded`、`normalizeStatusBarSelections` 依赖 config 已就绪），异步化 store 读取需保持“恢复不覆盖新状态”的既有约束（参见 `LocalUsageHistoryRepository` 的 tombstone 设计）。

---

### F7. 切 Space 触发壁纸全量解码 + 3 次重复刷新（P1，成本 S–M）

**现象**
`NSWorkspace.activeSpaceDidChangeNotification` / 分布式壁纸通知 → `clearCache()` + `refreshStatusDisplay()`，随后再排 3 个 follow-up work item（0.12/0.35/0.8s），每个都 `clearCache()` 再全量 `refreshStatusDisplay()`。`followWallpaper` 模式下每次 `refreshStatusDisplay` 都 `NSWorkspace.desktopImageURL` + `NSImage(contentsOf:)` + `CGImage`/TIFF 解码 + 亮度采样，全部在 main。

**证据**
- `Sources/OhMyUsage/App/StatusBarAppearanceController.swift:35-107`（Space/壁纸通知注册）、`:149-158`（`handleWallpaperContextDidChange` → clear + refresh）、`:161-183`（3 个 follow-up，各自 clearCache；延迟 `:183`）
- `Sources/OhMyUsage/App/StatusBarController.swift:230-273`（`resolvedForegroundStyle`/`wallpaperProbe` 每次渲染调用）
- `Sources/OhMyUsage/Services/WallpaperAppearanceService.swift:81-88`（缓存 miss 时 `imageLoader(probe.wallpaperURL)`，默认 `NSImage(contentsOf:)`）、`:76-79`（`clearCache`）
- `Sources/OhMyUsage/Services/StatusBarAppearanceResolver.swift:32-80`（全图 `cgImage`/TIFF 解码后采样）
- 缓存 key 含 path + 中心比例（`WallpaperAppearanceService.swift:82`），但每次 follow-up 都被 `clearCache()` 清空 → 缓存对本次事件无效

**建议**
1. 缓存 key 增加文件 `size+mtime`（或 `URLResourceValues` 指纹），Space 切换时**不清缓存**（壁纸未变则直接命中）；仅在“壁纸路径变化”时失效；
2. follow-up 只在“样式确实变化/壁纸文件变化”时执行，且 3 次可合并为 1 次（延迟 0.35s 一次 + 事件重复则 debounce）；
3. 亮度计算移到 `Task.detached`（`NSImage` 解码在后台，主线程只消费 Double），注意 `NSImage(contentsOf:)` 线程安全性：建议在后台用 `CGImageSource` 直接解码采样。

**验证方式**
- signpost `appearance.refresh` 的 duration + `WallpaperAppearanceService` 的 cache hit/miss 计数（新增诊断计数）；
- 在 6K 壁纸 fixture 上跑 `WallpaperAppearanceServiceTests` 风格的注入 `imageLoader`（现有 init 已支持注入），断言切 Space 模拟事件下 imageLoader 调用次数从 4 → ≤1；
- Instruments Time Profiler 手动切 10 次 Space，看主线程栈是否出现在 `StatusBarAppearanceResolver.wallpaperTopStripLuminance`。

**风险**
低（缓存指纹/去抖）；后台解码需注意 `NSImage` 非线程安全，建议换 ImageIO。

---

### F8. 无低电量/热压力/锁屏/睡眠自适应（P1，成本 M）

**现象**
全仓库 grep 无 `isLowPowerModeEnabled`、`thermalState`、`NSWorkspace.willSleepNotification/didWakeNotification`、`screensDidSleep`、`sessionDidResignActive`。唯一“环境自适应”是离线暂停（NWPathMonitor）。屏幕已锁/显示器睡眠时 poll loop 仍按原计划刷新（后台地板 900s / displayed 180s），local session 监控仍每 10–120s 扫盘。

**证据**
- 仅有网络状态注入：`Sources/OhMyUsage/App/AppCompositionFactory.swift:38-43`、`ProviderRefreshScheduler.swift:315-326`、`App/AppViewModel.swift:639-646`
- 配置只能手动选 `background3m/5m/10m/15m`：`Sources/OhMyUsage/Models/ProviderIdentityModels.swift:10-29`，`AppViewModel.swift:940-979`

**建议**
1. 监听 `NSWorkspace.shared.notificationCenter` 的 `willSleepNotification`/`didWakeNotification`（休眠前 stop poll loop，唤醒后按“启动刷新”语义只刷过期 displayed provider，`refreshDisplayedStatusBarProvidersForStartup` 已有该语义）；
2. 监听 `screenIsLocked`/`screensDidSleep`：锁屏/显示器睡眠时把 poll loop 切到“最低档”（如 background 1800s）并暂停 local session 监控；需要产品确认是否接受“解锁后数据稍旧”（可用缓存快照立即展示）；
3. `ProcessInfo.processInfo.isLowPowerModeEnabled` + `NSProcessInfo.thermalStateDidChangeNotification`：低电量/热压力时临时把 `backgroundProviderPollIntervalSeconds` 提升一档（复用现有 ResourceMode 配置即可，不新增 UI 配置项）。

**验证方式**
`powermetrics -i 1000 --show-process-energy` 在“锁屏 10 分钟”场景对比修复前后 process energy/CPU wakeups；日志/计数记录“lock→suspend monitor”事件次数；注意 macOS 休眠时进程本身被挂起，主要收益在“屏幕锁定但系统清醒”场景。

**风险**
中：改变数据新鲜度语义，需产品确认；实现上应默认开启但可配置（或用“至少保持缓存展示”保证 UI 不空）。

---

### F9. Grok/Gemini 本地用量枚举缓存实例化后即丢弃（P2，成本 S，2 行）

**现象**
`LocalUsageFileEnumerationCache` 设计为跨调用复用（校验文件元数据命中，避免重复 enumeration）；但 Grok/Gemini 每次 `fetchEvents` 都 `LocalUsageFileEnumerationCache().files(...)` 新建实例，调用返回后实例销毁，缓存永远为空；Claude/Kimi 则用 `static let`。

**证据**
- 误用：`Sources/OhMyUsage/Services/GrokLocalUsageService.swift:59`、`Sources/OhMyUsage/Services/GeminiLocalUsageService.swift:38`
- 正确用法：`Sources/OhMyUsage/Services/ClaudeLocalUsageService.swift:11`、`Sources/OhMyUsage/Services/KimiLocalUsageService.swift:11`、`Sources/OhMyUsage/Services/LocalUsageHistoryRepository.swift:433`（`static let cache = LocalUsageFileEnumerationCache(maxEntries: 8)`）
- 缓存实现：`Sources/OhMyUsage/Services/LocalUsageHistoryRepository.swift:68-190`

**建议**
改为 `private static let enumerationCache = LocalUsageFileEnumerationCache()`（注意同时保留 `Task.isCancelled` 检查；`isValid` 已是 O(files) stat，仍远优于递归 enumeration）。

**验证方式**
在 `GrokLocalUsageServiceTests`/`GeminiLocalUsageServiceTests` 里注入计数 `FileManager`（或利用 cache 的 `isValid` 行为），断言连续两次 `fetchEvents` 第二次不调用 `contentsOfDirectory`/`enumerator`（当前会失败）。

**风险**
很低（纯缓存实例化）。

---

### F10. Codex CLI RPC 回退：单次刷新最多 3 个子进程 + `Thread.sleep(3/10/18s)`（P2，成本 M，条件触发）

**现象**
`sourceMode=cli/auto` 且 API 路径失败/无 OAuth 时走 CLI RPC：依次 `keepAlive 3s → 10s → 18s` 尝试，每次 spawn `codex app-server`、写 JSON-RPC、`Thread.sleep(keepAlive)`、再 `terminated.wait(timeout: max(14, keepAlive+8))`。最坏情况单次刷新占用 ~3+10+18 秒 sleep + 3 次进程启动 + 最长 26s 等待；期间该 provider 的刷新槽（全局上限 2）被占用，其他 provider 的到期刷新被 defer（`ProviderRefreshScheduler.swift:328-355`）。`Thread.sleep` 还会阻塞协作线程池线程。

**证据**
- `Sources/OhMyUsage/Providers/CodexProvider.swift:661-668`（三次升级尝试）
- `Sources/OhMyUsage/Providers/CodexProvider.swift:754-800`（Process、`:787` `Thread.sleep`、`:791` 超时等待）
- 调用入口：`CodexProvider.swift:82-96`（auto: API → CLI → web）；`:152-167`（`loadFromCLI`）
- 全局并发上限：`AppProviderRefreshCoordinator.swift:66-107`；scheduler defer：`ProviderRefreshScheduler.swift:328-355`

**建议**
1. 进程不可用/输出无效时做“负缓存”（如 10 分钟），避免每个刷新周期重复尝试 3 次；
2. 用 terminationHandler + async awaited continuation 替代 `Thread.sleep`：写请求后等待目标响应帧（可用 readabilityHandler 收 stdout），总 deadline 建议 8–10s（而不是 keepAlive+8）；
3. 把 CLI RPC 限制为“用户显式触发/首次冷启动探测”，自动轮询不进入该回退（或仅在 `forceRefresh` 时允许一次）。

**验证方式**
注入 fake `codex` 可执行脚本（sleep/失败/正常三态）的 `CodexProviderTests`，计数“每次 fetch spawn 数 ≤1、总时长钳制”，当前实现会测出 3 次 spawn；运行时用 `log stream`/`ps` 观察子进程。

**风险**
中：`sourceMode=cli` 用户依赖此路径获取数据，需保留成功路径且不降低成功率；负缓存需区分“不存在/超时/协议错误”。

---

### F11. 凭证保存同步写整个 Keychain vault（P2，成本 S–M）

**现象**
设置页保存/删除凭证时，`KeychainService.saveToken` 会把**整个 tokenCache（含 official OAuth JSON 等大值）JSON 编码后一次性 `SecItemUpdate/Add` 到 Keychain**，且调用发生在 MainActor（通过 `AppConfigurationModel.saveCredential`）。Keychain 写涉及 securityd IPC，常见 5–50ms 级，冷/锁屏/认证上下文下可能更久。

**证据**
- `Sources/OhMyUsage/Services/KeychainService.swift:160-181`（`tokenCache[key] = token; persistSecureSnapshot(snapshot)`）
- `:569-581`（整 vault JSON encode）+ `:601-604`（`secureStore.saveData` → `SecItemUpdate/Add`）
- MainActor 调用链：`Sources/OhMyUsage/App/AppConfigurationModel.swift:183-214`（`@MainActor final class AppConfigurationModel` 于 `:10-11`）→ `CredentialAccessService.swift:56-64` → KeychainService
- 读取侧已 off-main（provider fetch detached），无需改

**建议**
把写 Keychain 移到 `Task.detached` + `withCheckedContinuation` 返回 Bool（`CredentialAccessService.saveCredential` 已是同步签名，可保留对外同步接口但内部 async 化需要改调用点；更小改法是 `AppConfigurationModel` 用 `Task` 包一层并由现有 feedback coordinator 显示结果）。同时评估“只写变化条目”的 schema（单条 entry 的 keychain item），避免整 vault 重写。

**验证方式**
signpost `keychain.save` duration + 主线程卡顿心跳；Instruments Time Profiler 点击保存时看 `SecItemUpdate` 栈位置；离线测试无法覆盖（Keychain 非可注入），建议保留 `SecureStoreAdapter` 注入（已有，`KeychainService.swift:8-42`）做“保存期间主线程不被占”的单元测试。

**风险**
低（异步化与现有 `settingsPersistenceFeedbackCoordinator` 兼容）。

---

### F12. 统计链路内存上界按条数而非字节 + 快照缓存无字节预算（P2，成本 M）

**现象**
- `UsageAnalyticsRepository` 的 raw cache 用 `records.count <= 100_000` 作为缓存上限，超过则不缓存但仍**构造整个数组**；每条 `UsageAnalyticsRecord` 含 4 个 String + totals，100k 条常驻 60s 可达几十 MB 量级（未实测）。
- 原始记录扫描无“分页/预算”概念，`.all` 范围时读取全部历史（`UsageAnalyticsAggregator.rangeInterval`）。
- `UsageAnalyticsSnapshotCacheStore` 16 项缓存无字节预算；`.all` 范围 trend buckets 数随历史天数线性增长（每 bucket 含 top5 provider/model 数组），16 项最坏可达数十 MB。
- `RuntimeMemoryDiagnostics.residentSizeBytes` 只在设置页 body 计算，没有任何 RSS 门槛/报警或淘汰联动。

**证据**
- `Sources/OhMyUsage/Services/UsageAnalyticsRepository.swift:157`（100k 条上限）、`:103-170`（整批构造 + 排序/聚合）
- `Sources/OhMyUsageApplication/UsageAnalyticsSnapshotCacheStore.swift:108-131`（16 entries 无字节预算）、`:183-200`（save 深拷贝 entries）
- `Sources/OhMyUsageApplication/UsageAnalyticsAggregator.swift:422-452,594`（bucket 数与 top-N）
- `Sources/OhMyUsageApplication/RuntimeDiagnostics.swift:27-74,76-98`（RSS 探针存在但未用于策略）

**建议**
1. 给 raw cache 增加字节预算（例如 32 MiB：估算 `records` 的 `MemoryLayout` + 字符串字节，超预算不缓存/降采样）；`rawEntry.records` 按来源（cc-switch proxy 是最大头）可先聚合再缓存；
2. `UsageAnalyticsSnapshotCacheStore` 增加 `maxTotalBytes`（编码后大小，调用点在 `persist` 已有 `encoder.encode` 结果，可直接量）；
3. 把 RSS 采样从“设置页 body”改成 diagnostics 定时采样（如菜单打开时 1 次 + 后台每 5 分钟一次），显示在设置页，作为 F5 基线的一部分。

**验证方式**
构造 30 天 / 多 provider 的合成 cc-switch DB（现有 `CCSwitchUsageLogReaderTests` 可生成 SQLite fixture），在 `.all` 范围下用 `RuntimeMemoryProbe.residentSizeBytes()` 记录峰值（当前无断言，先采集基线），再加预算断言。

**风险**
中：缓存预算会影响统计首屏速度（命中率下降），需同时记录“空缓存重算耗时”。

---

## 4. 疑似真 bug / 竞态清单（按严重度排序）

### R1. `fetchProviderSnapshot` 的取消不传播 —— 真实取消语义 bug（高置信，严重度 中）
见 F3。证据 `AppProviderRefreshCoordinator.swift:478-485`。后果：配置变更/重置/退出时，in-flight 刷新被标记取消但网络/子进程继续，最多再耗 15–60s 并占连接；由于 `invalidateRefreshes` 同时移除了 in-flight 记录，新刷新可与旧请求重叠（同一 provider 的 provider 端限流风险）。**不是数据竞争**（状态写入前有 revision/取消守卫，`:311,346-347,359`），是浪费与取消语义错误。

### R2. 本地 session 信号可能被“消费后丢弃” —— 数据新鲜度 bug（中置信，严重度 低）
`LocalSessionRefreshCoordinator.refreshCandidates` 在返回候选前就更新 `lastProcessedSignalAt`（`ProviderRefreshScheduler.swift:105-106`）。但候选刷新随后可能被 per-provider in-flight gate 合并/跳过（`AppProviderRefreshCoordinator.swift:129-132` 对已有刷新直接 join 并返回）或 provider 已被禁用；此时该完成信号永久丢失，只能等下一次 poll（最坏 900s）。**建议**：把 `lastProcessedSignalAt` 的更新移到 refresh 真正被接受（或完成）之后；`LocalSessionRefreshCoordinator` 需要注入“本次是否真的发起了刷新”的结果。验证：`ProviderRefreshSchedulerTests` 增加“in-flight 时到达完成信号，刷新结束后应补一次”的用例（当前实现会失败）。

### R3. 调度器 restart 与 in-flight 任务取消的时序 — 低风险，但会放大 R1（中置信）
`ProviderRefreshScheduler.restart` 先 `stop()`（取消 in-flight）再重建；`AppProviderRefreshModel.restartPolling` 在每次配置/凭据变更时被调用（`AppProviderRefreshModel.swift:95-100`；调用点 `AppConfigurationModel.swift:208,762,798,957`、`AppOfficialProfilesModel.swift:540`、`LocalProviderDiscoveryCoordinator.swift:48`）。旧刷新任务虽然被 cancel，但由于 R1 网络不 cancel，且 coordinator 的 map 条目在 `runExclusiveRefresh` defer 才移除，短时间内同 provider 可有两个请求在跑。**建议**与 R1 一起修（先修 R1 再观察）。

### R4. 启动期间权限探测重复执行（低置信/低严重度，属可清理项）
`AppViewModel` private init `:472` 与 `start()`（`:631-634`）都以 `force: true` 调 `refreshPermissionStatuses`，`AppPermissionModel.refreshPermissionStatuses` 会取消上一个 task（`AppPermissionModel.swift:217-219`），因此 init 触发的全盘探针/Keychain readiness 可能被立刻取消并重做；同时启动本来就慢（F6）。**建议**：start 中改成 `refreshPermissionStatusesIfNeeded()`（5s 节流已存在，`AppPermissionModel.swift:199-203`），或删除 init 那次。

### 非 bug 澄清（避免误报）
- `SecurityCredentialReader.credentialCache` 用 `nonisolated(unsafe) static var` 但所有读写都持 `cacheLock`（`SecurityCredentialReader.swift:23-26,126-158`）——**不是**竞态；
- `@unchecked Sendable` 的 27 个 provider 类只持有 `let` 不可变依赖（抽查 `CodexProvider.swift:12-31`、`ClaudeProvider.swift:11-33`）——**不是**竞态，属历史风格；
- 大量 `@unchecked Sendable` cache/store（`PersistedSnapshotCache`、`UsageAnalyticsSnapshotCacheStore`、`ProviderValueCache`、`LocalUsageHistoryCacheIO`、`KeychainService`、`CredentialBroker` 等）都实际用 `NSLock`/串行 queue 保护，抽查未发现“无锁可变状态”；
- `CursorLocalUsageService` 单飞 + `Waiter` 的 continuation 安装/完成竞态有缓冲结果设计（`CursorLocalUsageService.swift:61-83`），抽查未发现 continuation 泄漏；
- `Task.detached` 的其余 11 处均配 `withTaskCancellationHandler`（grep 核对），只有 R1 那处例外；
- `Timer` 未在任何业务代码中使用（仅 `DispatchQueue.main.asyncAfter` 的一次性延迟与 `Task.sleep`），**不存在**每 provider 一个 timer 的旧问题。

---

## 5. “只是风格/暂不构成性能问题”的观察

1. `UsageAnalyticsRepository.snapshot` 用 `while !rawLock.try() { Thread.sleep(0.01) }` 自旋等待（`:111-114`，reusableSnapshot `:176-178`）：目前在 `Task.detached` 里调用，不在主线程；但它是阻塞式等待，建议改 `await` 串行 actor 或 dispatcher（低优先）。
2. `MenuContentView` 5s tick 时 `refreshPermissionStatusesIfNeeded` 仅在权限引导展示时触发（`:477-483`），不是常驻开销。
3. `ConfigSnapshotWriter` 每次 save 都 `ensureDirectoryExists()`（一次 `fileExists`，`ConfigSnapshotWriter.swift:18-22`）——并入 F4 去重即可。
4. `ClaudeAccountProfileStore.loadFile()` 每次 load 都 `createDirectory`（`:953-957`）——同 F2 一起改。
5. `AppPermissionCoordinator.probeFullDiskAccess` 的候选路径 `fileExists/isReadableFile` 为轻量 syscall；5s 节流 + detached（`:170-194`），暂不构成问题。
6. `StatusBarController.image(for:)` 图标按 provider/style 缓存（`providerStatusImageCache`，`StatusBarController.swift:16`），有界，可接受。
7. `ResourceMode` 语义核对：`activeProviderPollIntervalSeconds`（180/300）与 fetch plan `activeTTL`（60–300）取 max，导致 displayed provider 默认按 180s 而非用户配置的 60s 刷新；3/5/10 分钟三档对非 displayed provider 都落到 plan `backgroundTTL=900s`（`ProviderFetchPlanRegistry.swift` 全表 + `AppViewModel.swift:940-979` + `ProviderRefreshScheduler.swift:474-491`）。这是**有测试确认的既定策略**（`ProviderRefreshSchedulerTests.swift:237-321`），但与“用户配置的刷新频率/资源模式”语义不一致，建议在 UI 文案或 README 里说明实际下限，避免用户误以为 3 分钟档就是 3 分钟（属产品语义问题，非本审查的性能 bug）。

---

## 6. 历史优化核对（本轮不应重复建议）

已在代码中确认存在并有效（抽查 + grep）：
- 单 poll loop + per-provider in-flight + startup jitter + 并发上限 + 离线暂停：`ProviderRefreshScheduler.swift:269-370`、`AppProviderRefreshCoordinator.swift:57-150`
- 可见才 tick 的时钟：`VisibleClockController.swift:13-33`（menu/settings/statusbar 三处均按可见性启停）
- 状态栏渲染去重：`StatusItemController.render` 返回是否重绘（`StatusBarController.swift:62-73`）
- 持久快照缓存（异步恢复 + 合并写 + 版本/代数守卫）：`PersistedSnapshotCache.swift:163-470`、`AppViewModel.swift:499-526`
- 官方 provider 缓存（64 项 LRU / 24h / generation 失效 / gate）：`OhMyUsageProviders/OfficialProviderFetchRuntime.swift:22-260`
- history/analytics 缓存异步 IO + 上界 + 旧 schema 兼容：`LocalUsageHistoryRepository.swift:654-1030`、`UsageAnalyticsSnapshotCacheStore.swift:108-374`
- 浏览器凭证路径 TTL、source fingerprint 60s TTL、CCSwitch streaming、429 Retry-After、source inventory 有界共享：分别在 `BrowserStorageCredentialReader`/`BrowserCookieDatabaseReader`/`UsageAnalyticsRepository.swift:207-231`/`CCSwitchUsageLogReader.swift:103-150`/`BackoffPolicy.swift`
- 多处 `withTaskCancellationHandler` + detached worker.cancel：`LocalUsageHistoryRepository.swift:757-796`、`UsageAnalyticsRefreshCoordinator.swift:95-151`、`CursorLocalUsageService.swift:404-410`
- 关闭时 best-effort flush（2s 上限）：`RuntimeGuards.swift:89-109`

---

## 7. 如果只做 3 件事

1. **F1：把本地 session 信号监控移出 MainActor**（含 Claude JSONL 增量尾部读取）。
   理由：这是当前唯一“周期性、无条件发生在主线程上的重 I/O（FS+SQLite+全文件解析）”，与菜单栏常驻模型直接冲突，且随 Claude 会话文件增长而恶化；改动局部（monitor + 一个协议 async 化），有现成测试 seam（`LocalSessionCompletionSignalMonitorTests` 的 probe/enumeration 计数）。
2. **F5：先补最小可观测性基线**（os_signpost + 主线程卡顿计数 + idle 能耗/RSS 采样脚本）。
   理由：README 已承认“未测量”；没有它，本报告任何“收益”都无法验收，团队后续优化也只能靠自证。成本最低、风险最低。
3. **F3：修 provider fetch 的取消传播**（R1）。
   理由：一行级封装（`withTaskCancellationHandler` + `worker.cancel()`）就能让“停止轮询/配置变更/退出”真正取消网络与子进程，减少孤儿请求与重复刷新，且可写成红-绿 focused test。

（若允许做第 4 件：F4 配置保存去重 —— 零风险、用户可感知的设置页跟手度改善。）

---

## 附：主要取证命令与限制

- 周期任务：`grep -rn "Timer\|Task.sleep\|DispatchSourceTimer\|AsyncStream\|asyncAfter\|scheduleTimer" Sources --include=*.swift`
- MainActor × 同步 I/O 交叉：先 `grep -rln "@MainActor"`，再对结果 grep `FileManager.default|Data(contentsOf|String(contentsOf|sqlite3_|SecItem|Process(`
- 并发原语：`grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|NSLock()\|os_unfair_lock\|withCheckedContinuation\|Task.detached" Sources`
- 缓存上界：`grep -rn "maxEntries\|maxBytes\|capacity\|prune\|evict\|LRU" Sources`
- 限制：未运行构建/测试、未运行 Instruments/powermetrics、未读取用户真实日志（不触碰 `~/.codex`/`~/.claude` 数据）；所有 file:line 以当前工作区为准（`VERSION=2.5.4`，工作区另有 UI 未提交改动，与运行时链路无关）。本报告只写入 `.review/02-performance.md`，未修改源码。
