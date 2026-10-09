# OhMyUsage 优化方案 v2：正确性优先，性能实测，渐进收口

日期：2026-10-09
核验基线：`main` / `a9259ca` / `VERSION=2.5.3`
性质：实施前方案，不代表已实施，也不授权安装、发布、真实凭据操作或生产变更。

## 1. 结论与范围

优先修复“统计可能漏数据、缓存可能误判未变化、异常缓存可能导致启动崩溃”等可验证问题，再优化主线程 I/O、后台取消和缓存容量，最后做局部消重与职责整理。

不沿用原报告的三个 P0 顺序：本地化不是失效；启动 jitter 与并发上限没有实测优化依据；主线程 I/O 存在，但需要有序持久化和状态隔离，不能直接把整个方法套进 `Task.detached`。

本方案整合以下材料，但以当前代码为准：

- 用户提供的《OhMyUsage-优化分析报告.md》（2026-10-09）。
- [OPTIMIZATION_NOTES.md](OPTIMIZATION_NOTES.md)：低能耗、可信度明确、先快后全的产品方向。
- [REFACTOR_PLAN.md](REFACTOR_PLAN.md)、[REFACTOR_BASELINE.md](REFACTOR_BASELINE.md)：历史设计背景，旧行数、测试数和“尚未实现”不能直接当成现状。
- [2026-08-11 架构收口记录](superpowers/plans/2026-08-11-architecture-debt-reduction.md)：已完成边界和仍未迁移的部分；再由当前边界测试核对。

本次只新增本文；不修改 Swift、Package、CI、版本、原方案或系统配置。

### 证据等级

- **已确认**：由当前源码、调用路径或隔离临时样例确认的行为。
- **条件性缺陷**：明确输入条件下代码会产生错误；实际用户发生率未测。
- **待测候选**：优化机制有依据，但实际耗时、能耗和收益尚未测量。
- 文件行数、调用层数、重复声明数不是性能或架构缺陷的证明。

## 2. 当前验证基线

- 源码：342 个 Swift 文件 / 75,753 行；测试：159 个 Swift 文件 / 48,096 行，原报告统计准确。
- 前一轮同基线全量 XCTest：1,277 项通过，0 失败。该结果证明现有测试通过，不证明未覆盖路径没有问题。
- 本轮复跑缓存、统计、Cursor、刷新调度、资源模式、架构边界及趋势 presenter 相关 XCTest：112 项通过，0 失败；未新增或修改测试。这些旧测试不覆盖本文所有新发现。
- 完整 Xcode 工具链 + 原生 SwiftPM 后端 + 独立 `/tmp` 构建目录可完成测试。
- 默认后端曾遇到资源 bundle 签名的扩展属性错误；CLT 和 Xcode 工具链不应混为一谈。
- `--build-system native` 已收到弃用警告，只作为本机临时验证路径，不建议固化为长期唯一构建方式。
- 本次没有运行已安装 App 的真实账号刷新、账号切换、权限弹窗、更新安装、发布或付费请求。
- 下列临时样例只使用生成的数据，不读取用户实际日志或数据库：SQLite WAL 变化、聚合指纹碰撞。
- 当前尚无本次采集的启动 p95、主线程阻塞、CPU、能耗或内存基准；本文不声明性能提升百分比。

## 3. 优先级与实施包

这里的 P0 表示第一批正确性工作，不表示已有生产事故。

| 编号 | 优先级 | 事项 | 证据 | 预期收益 | 风险/相对工作量 |
|---|---|---|---|---|---|
| C1 | P0 | 缓存恢复防重复 key、超大输入和损坏数据 | 重复 key 条件性崩溃已确认 | 启动与缓存恢复稳定性 | 低至中 / 小至中 |
| C2 | P0 | Cursor 按原始分页数量续页 | 代码路径已确认，需回归 fixture | 避免统计提前截断 | 中 / 小至中 |
| C3 | P0 | 指纹覆盖 WAL、逐文件变化与远端来源 | 临时样例 + 代码已确认 | 缓存不再误判数据未变化 | 中 / 中 |
| C4 | P1 | 失败重试与“最后成功时间”分离 | 当前状态流已确认 | 避免旧缓存错误恢复为健康 | 中 / 小至中 |
| P1 | P1 | 三类缓存 I/O 离开主线程，写入有序 | 同步调用已确认，耗时待测 | 页面/启动响应性 | 中至高 / 中 |
| P2 | P1 | 扫描 single-flight、取消传播与预算 | detached 取消缺口已确认 | 降低无效扫描与请求 | 中 / 中至大 |
| P3 | P1 | 官方快照缓存容量与旧值生命周期 | 无容量上限已确认，增长待测 | 长时运行内存可控 | 中 / 中 |
| P4 | P1 | 持久快照写入顺序、锁和重复 I/O | 顺序缺口由代码确认，需竞态 fixture | 避免旧快照覆盖新快照 | 中 / 中 |
| M1 | P2 | 同义工具消重、额度工厂保留语义 | 局部重复已确认 | 维护成本降低 | 低至中 / 中 |
| M2 | P2 | Settings/Relay 按职责渐进提取 | 大文件已确认，交互覆盖待补 | 修改范围更小、测试更直接 | 中 / 中至大 |
| M3 | P2 | 本地化统一、窄 UI 边界、别名清理 | 双轨和局部依赖已确认 | 工程一致性 | 低至中 / 中 |
| E1 | P2 | Retry-After 和错误分类增强 | 响应头丢失已确认 | 更可信的限流恢复 | 中 / 中 |
| E2 | 待测 | 刷新并发/jitter、增量扫描、SQL 下推 | 机制候选，无性能基准 | 有条件的性能收益 | 依实测决定 |

工作量是相对分级，不是工期承诺；先写回归测试后才能给更可靠的排期。

## 4. 第一批：正确性与恢复能力

### C1. 容错恢复，而不是可解码就信任

**证据**

- [LocalUsageHistoryRepository.swift](../Sources/OhMyUsage/Services/LocalUsageHistoryRepository.swift) `restoreFromDisk`，726-736 行。
- [UsageAnalyticsSnapshotCacheStore.swift](../Sources/OhMyUsageApplication/UsageAnalyticsSnapshotCacheStore.swift) `restoreFromDisk`，211-223 行。
- 两者在成功 JSON 解码后使用 `Dictionary(uniqueKeysWithValues:)`。合法 JSON 只要包含重复 query/filter，仍会触发运行时 precondition，而不是被 `try?` 捕获。
- 读入前没有文件字节数限制；条目裁剪发生在完整读入、解码之后。24/16 条内存上限不等于输入文件大小上限。

**实施**

1. 给恢复增加明确字节预算与 schema version；大小阈值先用生成的正常最大 fixture 校准，不照搬别的缓存的 512 KiB。
2. 使用容错 reduce：同 key 保留 `refreshedAt` 较新的合法条目；同时间使用确定规则。过滤非法条目，而不是崩溃。
3. 向后读取旧格式；未知版本安全忽略。只处理应用自有聚合缓存，不读写原始聊天日志、SQLite、钥匙串。
4. 记录脱敏错误类别和计数；不打印缓存内容、真实身份或凭据，不弹窗打扰普通缓存降级。

**验收**：重复 key、截断 JSON、未知版本、超大文件、非法条目都不崩溃；正常旧缓存 round-trip；异常恢复不自动删除用户原始数据。

### C2. Cursor 分页：过滤条数不等于服务器页长度

**证据**

- [CursorLocalUsageService.swift](../Sources/OhMyUsage/Services/CursorLocalUsageService.swift) 30-84 行。
- `fetchPage` 对原始 rows 做 `compactMap(Self.event)`，零 token 或缺少有效时间的行被丢弃。
- 上层用 `pageEvents.count < 200` 终止分页；原始满页若有一条被过滤，便可能漏掉后续页。
- 当前 `CursorLocalUsageServiceTests` 注入的是整体事件 fetcher，未直接覆盖真实分页解析；客户端还用 XCTest 环境变量跳过网络。

**实施**

1. 页响应返回 `events + rawRowCount + 可用的分页元数据`，续页根据原始数量或已验证的服务端 hasMore/cursor，不根据筛选后的数量。
2. 保留最多 30 页保护；达到上限时标记结果可能截断，不静默表现为完整结果。
3. 抽纯解析器和可注入请求 seam，使用本地 fixture/URLProtocol；不为了测试而读取真实 Cursor token。
4. 远端失败、空结果、本地 fallback 的来源与完整性要可区分，不能让 `try?` 一律表现为成功空结果。

**验收**：原始 200 行、其中 199 个有效事件，仍请求第二页；全部无效但原始满页仍正确续页；短页/空页停止；重复页不无限循环；后续页失败有明确降级结果。当前没有在线核验 Cursor 私有接口契约，实施时不得臆造分页字段。

### C3. 数据源指纹必须覆盖真实输入

**证据 A：WAL**

- [LocalUsageHistoryRepository.swift](../Sources/OhMyUsage/Services/LocalUsageHistoryRepository.swift) `codexFingerprint(.currentAccount)` 只包含 `logs_2.sqlite`，409-413 行。
- `cursorFingerprint` 只纳入 `state.vscdb` 和项目 JSONL，不纳入 `state.vscdb-wal`，456-465 行。
- Codex 当前账号通过 SQLite 扫描、Cursor 通过只读 SQLite 查询实际读取数据。
- 临时 SQLite WAL 样例确认：提交新记录后主文件大小/mtime 不变，只读连接已能读取新记录；主文件+WAL 指纹有变化。未断言用户当前数据库一定处于 WAL 模式。

**证据 B：聚合碰撞**

- 指纹仅含 roots、fileCount、totalSize、latestModificationTime，见同文件 24-29、536-556 行；统计模块同样使用此类聚合结构。
- 临时两个文件样例确认：非最新文件同长度更新，其 mtime 变化但仍小于另一个文件的最新时间，聚合指纹完全不变。
- `refreshIfNeeded` 指纹相同时直接更新 `refreshedAt` 并复用 summary，661-675 行。若一直相等，可反复复用至时间窗口重算；不能依赖 15 分钟 TTL 保证重新读取。

**证据 C：远端 Cursor**

- Cursor summary 优先使用 dashboard 数据，但是否重载主要由本地文件指纹判断。
- 本地文件不变不代表远端 dashboard 没有新事件。现有 hourly/daily/monthly 时间窗口重算提供部分兜底，不等于准确的远端失效策略。

**实施**

1. SQLite source descriptor 包含主文件和存在时的 `-wal`，处理创建、删除、checkpoint。`-shm` 不作为业务变化信号，除非后续证据表明必要；绝不删除/改写这些文件。
2. 对实际读取的每个文件形成规范化的 metadata tuple：路径、大小、高精度 mtime，必要时 inode；排序后生成稳定摘要。与枚举共享同一 source inventory，避免额外重复扫描。
3. 明确 metadata 摘要仍无法检测“内容被改且 metadata 被完全还原”；用有上限的真实重读周期兜底，不默认每轮 hash 所有原始日志内容。
4. 区分本地文件、SQLite、远端 dashboard 来源：远端具有独立验证时间/最大数据年龄；force 不得仍被静态 60 秒指纹缓存完全抵消。是否 bypass 应按请求意图实现，而不是删除全部缓存。
5. 指纹 schema 变化使旧缓存重新验证，不能直接沿用旧粗粒度字段并声称等价。

**验收**：WAL-only 更新可见；WAL checkpoint 与消失不报错；非最新文件等长更新可见；同数量同大小文件替换可见；远端变化即使本地不变也在明确预算内重新验证；跨小时/跨日无重复累计。

### C4. 失败时间不应成为“最新成功时间”

**证据**

- [LocalUsageHistoryRepository.swift](../Sources/OhMyUsage/Services/LocalUsageHistoryRepository.swift) 698-704 行，失败保留旧 summary，但把 `refreshedAt` 改为失败时刻。
- 后续 fingerprint 相等路径会清除 `lastError` 和 `isStaleFallback`，而不执行 loader，661-675 行。
- 对文件 metadata 不变但权限/解码/远端加载失败的情形，仅 fingerprint 验证不能证明恢复成功。

**实施**：拆分 `lastSuccessfulLoadAt`、`lastAttemptAt`、`lastFingerprintCheckedAt` 与 retryNotBefore；失败保留最后成功时间；只有真实成功载入或有明确有效性语义的验证才能清除失败状态；人工 force 绕过退避但遵守并发门控。

**验收**：原缓存→加载失败→fingerprint 相同，不会仅因 metadata 相同就显示健康；恢复后成功读取才清错；失败不丢旧图表；重试不形成循环刷盘和日志风暴。

## 5. 第二批：性能、资源与并发

### P1. 主线程 I/O 范围应扩大到三类缓存

**已确认调用**

- LocalUsageHistoryRepository：`@MainActor` 初始化 restore，刷新后 persist，726-759 行。
- UsageAnalyticsSnapshotCacheStore：save/markValidated 内持锁编码写盘，145-176、226-251 行；[UsageAnalyticsRefreshCoordinator.swift](../Sources/OhMyUsage/App/UsageAnalyticsRefreshCoordinator.swift) 在 MainActor 调用它，81、102 行。原报告漏掉了这一条。
- PersistedSnapshotCache：启动由 [AppViewModel.swift](../Sources/OhMyUsage/App/AppViewModel.swift) 473-488 行同步读取。正常刷新写入已是 detached，不能重复列为“尚未后台化”。
- LocalUsageHistory 的 fingerprint/loader 已后台执行，657、679 行；UsageAnalytics 的扫描也已后台执行，65、95 行。

**方案**

1. MainActor 只管理可观察状态；专用串行 actor/队列负责应用自有聚合缓存 I/O。编码器随 I/O owner 持有，不默认全局共享一个可变 encoder。
2. 异步恢复按 cache key 合并，禁止覆盖已经刷新的值；显式处理恢复与刷新/移除/重置竞态。
3. 状态快照带 generation/revision；写入有序并可合并，不创建无限 detached 写任务。先保证正确性，再评估 debounce 时长。
4. 校验时间更新不必每次立即持久化；保存业务值与验证 bookkeeping 可分别处理，但不牺牲重启后可解释性。
5. I/O 错误保留旧缓存并记录脱敏诊断；明确退出时 best-effort flush 和突然终止可损失的范围。
6. 先只处理可重建的展示缓存；配置、OAuth/凭据、账号切换事务不并入同一异步写入策略。

**验收**：慢磁盘 fake 不阻塞 UI 状态更新；连续写 A/B 不出现 A 最后覆盖 B；恢复不覆盖新数据；移除/重置后旧任务不能复活缓存；写入失败不显示错误的“持久化成功”。实际 UI 收益用相同 fixture 的主线程 trace 和打开时间比较。

### P2. 取消不只是“不展示旧结果”

**证据**

- UsageAnalyticsRefreshCoordinator 每次取消外层 refreshTask，但 fingerprint 与 snapshot 由独立 `Task.detached` 执行，55-100 行。generation 防止旧结果发布，不会自动停止旧扫描。
- [CodexLocalUsageScanners.swift](../Sources/OhMyUsage/Services/CodexLocalUsageScanners.swift) 的 scanLines 循环没有取消 seam，315-376 行。
- CursorDashboardUsageClient 使用 `dataTask + semaphore.wait()`，88-105 行；同步等待没有独立截止/取消传播，分页上限也不是总运行时间上限。通常运行在后台，不应误称主线程必定阻塞。
- UsageAnalyticsRepository 每个缺缓存的 filter snapshot 都读取来源后再聚合，78-115、149-243 行；模型筛选改变可能重复读取相同原始来源。

**方案**

1. 保留可取消 worker handle，显式传递取消；同步 scanner 在文件/批次边界检查共享 token，不能只在 UI task 末尾检查。
2. 按 source、时间范围、identity、source revision 建 single-flight；只针对等价加载共享结果，不把不同账号请求错误合并。
3. 原始事件层与展示筛选层分离。模型切换优先复用有界事件/聚合中间结果；先测内存再决定缓存粒度。
4. Cursor 请求改 async，支持取消和总 deadline；保留每页 timeout 和页数上限。先以 adapter 兼容同步调用点，分批迁移，而不是到处桥接 semaphore。
5. 区分主动取消、网络失败与权限失败；取消不累计 Provider 连续失败，不触发凭据重新发现或 fallback 请求链。

**验收**：快速切换十次筛选，只有最终结果发布且失效 worker 能在明确批次边界结束；等价请求只扫描一次；请求取消后不再发送下一页；各 source/账号隔离；离线和 timeout 可保留旧值并给出原因。

### P3. 官方快照缓存没有统一容量与 stale-age 边界

**证据**

- [OfficialProviderFetchRuntime.swift](../Sources/OhMyUsageProviders/OfficialProviderFetchRuntime.swift) 的 FetchedAtOfficialSnapshotCache、SnapshotTimestampOfficialSnapshotCache 使用字典，46-85 行；无容量裁剪，过 TTL 只停止 fresh 命中，不移除条目；snapshotAny 可返回任意旧值。
- Codex 等使用静态缓存，多账号/多配置切换会产生多个 key；这不是原报告列出的有界 ProviderValueCache，不能混为一谈。
- SerialOfficialFetchGate 的等待 continuation 无取消移除，88-117 行；排队中的取消请求取得 permit 后仍可能进入 operation。
- 这是代码层的资源边界缺失；实际增长量与卡顿未测，不能直接宣称内存泄漏或无限请求。

**方案**：注入 clock、容量上限和 stale fallback 最大年龄；LRU/时间裁剪；删除 Provider、身份改变时明确失效；gate waiter 可取消，operation 开始前检查取消。fresh TTL 与 stale 保留期独立，不能把可用离线缓存全部按 fresh TTL 删除。

**验收**：插入超过上限有确定淘汰；过期与 stale fallback 上限可测；账号隔离不回退；等待取消不执行网络；原有 offline fallback 和手工刷新语义保持。

### P4. 持久快照：串行锁不等于按刷新时间有序

**证据**

- [AppProviderRefreshModel.swift](../Sources/OhMyUsage/App/AppProviderRefreshModel.swift) 247-257 行，每次 snapshot 写入是独立 detached 任务。
- [PersistedSnapshotCache.swift](../Sources/OhMyUsage/Services/PersistedSnapshotCache.swift) 221-237、330-336 行，在锁内无条件移除同 key 再追加。
- 现有 generation 保护重置/凭据失效，不能区分同 generation 的先后刷新；如果较旧写任务后获得锁，会覆盖较新值。当前门控降低风险，不保证 detached 任务调度顺序。
- 每次 save 都读入、解码、编码、原子重写；currentGeneration 和删除路径也可能在 MainActor 等待持锁写入。这是应测的二次阻塞点。

**方案**：在 dispatch 前捕获每 provider 单调 revision，I/O owner 只接受较新 revision；保留 reset/identity generation。savedAt 记录请求侧明确时刻，不靠 worker 执行时刻推断新旧。按实测决定内存索引、批量合并和短锁，不先把安全锁删除。

**验收**：强制 A 旧快照晚于 B 新快照到达，最终保持 B；reset/remove 后旧写入无效；多账号 key 不合并；慢写不会导致 UI 长时间等待 currentGeneration；单次有效更新不引发重复全量读写风暴。

## 6. 第三批：维护成本和边界收口

### M1. 抽公共能力，但保持差异

- 可优先合并 Amp/Kiro 完全同义的 regexCaptures、同义 base64URL/数值钳位实现；配套现有 Provider 测试和边界输入测试。
- 百分比工厂必须保留 Double 精度、kind、resetSource、observedAt、clockSkew、confidence、windowIdentity，不直接复制 Cursor 固定 `.custom` 的四参数工厂覆盖所有场景。
- Kimi/OpenRouter/Trae token 归一化顺序、前缀、百分号解码不同；如要共享底层原语，显式传策略并先固定兼容 fixture。
- 阈值判断需区分金额、百分比、缺失值和耗尽状态；简单一行重复不等于规则散落，不以统一表达式掩盖业务差异。
- 不建立包罗所有行为的 ProviderUtilities 上帝工具类；不为省声明而合并隔离的 cache/gate。

**验收**：旧 fixture 输出逐项一致，额度精度和窗口语义不变；新公共能力职责清楚；不以减少 500-800 行作为交付指标。

### M2. 大文件按变更热点拆，不按固定行数拆

首选提取纯规则与展示模型，再调整视图组合：

1. SettingsProviderSidebar：拖拽排序状态机、导入导出命令和纯判断；不要同时改排序语义与布局。
2. SettingsRelayConfigurationForm：draft→配置映射、验证、凭据模板；沿用已有配置 facade、coordinator 和 presentation 测试。
3. SettingsLocalUsageTrend：账号上下文 resolver、格式化、summary 展示；小时图表已复用 LocalUsageTrendHourlyBarsView，不重复造一个通用图表。
4. RelayResponseInterpreter：先抽最常变化的平台解析策略，固定返回模型；不要一次把全部平台改为策略注册表。
5. Provider 凭据/OAuth 拆分按现有 port 与 runtime 推进，一次一个 Provider；不联动真实凭据写入/迁移。

**验收**：新增纯逻辑 XCTest；中英文、长账号名、空数据/旧缓存/失败、明暗外观、窄窗口/滚动、拖拽取消与提交均检查；视觉快照只是补充，不替代真实交互验收。没有对应文件名测试不等于无间接覆盖。

### M3. 本地化、UI 依赖和迁移别名

- 当前 UI 约 140 处 viewModel.text、234 处 viewModel.localizedText；后者也是双语，不以中文字面量总数当缺陷数量。
- 先做可见文案清单，区分品牌/单位/调试文本与需要翻译的用户文案；补关键文案双语测试。后续可选择统一 typed key 或 string catalog，但无需做“保留双语或删光体系”的假二选一。
- 无必要不一次全量迁移 xcstrings；如果选择 string catalog，明确动态参数、复数、fallback 和 Bundle.module 的 SwiftPM 资源行为，再单独验证。
- UI→Providers 的当前落点包括 MenuSubtitlePresenter、SettingsQuotaDisplayHelpers 的通用 OfficialValueParser。可将需要的纯语义转为 Presentation 输入，不能仅删 import。
- AppViewModel 作为可执行层的 Observation/UI facade 合理；“名字叫 ViewModel 就必须移入 Application”不是规则。保持配置与运行态写入口护栏，按职责调整协作对象，不按最多三层/至少600行强制合并。
- CodexQuotaDisplayNormalizer、UsageAnalyticsAggregator、UsageAnalyticsSnapshotCacheStore 等纯 typealias 可按引用图小批次移除；UsageAnalyticsTypes 有多个别名；MenuPermissionGuidePresenter 和 SettingsQuotaPresenter 有真实逻辑，不能当三行 shim 删除。
- Catalog facade 隔离默认配置政策，是否删除取决于 API 使用与变更热点，不以“透传无价值”直接判定。
- Provider 实现仍留 executable 有 ProviderDescriptor/配置政策边界原因。迁移需先处理实际依赖和现有 ArchitectureTargetBoundaryTests，而非先搬文件再放宽护栏。

**验收**：架构边界测试保留；UI 不再读取不必要的解析实现；配置编码兼容；中英文关键路径无回退；不引入 target 反向依赖。

### E1. Retry-After 与错误分类

[RelayHTTPClient.swift](../Sources/OhMyUsageProviders/RelayHTTPClient.swift) 对 429 只抛 ProviderError.rateLimited，响应头未进入后续调度；BackoffPolicy 无该输入。可增强，但不预设现有退避一定过长。

- 将受信任的 rate-limit retry deadline 通过 typed metadata 传到调度层；仅改 BackoffPolicy 不足以完成端到端闭环。
- 秒数/HTTP-date、无效/过去日期、合理上限和时钟偏差均需本地 fixture；不能为了“更快”早于服务端要求重试。
- 保留无 Retry-After 的旧默认；用户 force 有明确语义，后台不忽略 deadline。
- RelayHTTPClient.requestJSON 当前把各种 URLError 都转 timeout；区分 cancelled/offline/真正 timeout，避免取消被当成失败并继续 fallback。

**验收**：429 携带/缺少/非法头；旧缓存保留；取消不通知认证失败；调度等待时间可通过注入 clock 测试，不依赖真实网络或墙钟等待。

## 7. 原报告处理对照

| 原报告结论 | 新版处理 |
|---|---|
| 本地化形同虚设，UI 只使用两次 | 撤销；改为 M3 写法统一与真实文案审计 |
| 周一～周天不能英文化 | 撤销；当前代码明确有英文分支 |
| 主线程 I/O 小修即可 | 保留问题，扩大到统计/启动快照；采用 P1 有序异步设计 |
| 文件枚举本身导致主线程卡顿 | 不成立为主线程结论；现有后台执行，扫描成本进入 P2/基准 |
| jitter 60秒、并发3-4两行优化 | 暂不采纳；E2 实测后决策 |
| Provider 消重500-800行 | 保留局部消重方向；撤销未经推导的收益数字 |
| 两套小时图表几乎完全重复 | 撤销；共享组件已存在，M2 只提取剩余职责 |
| context 多层 switch、五层刷新调用链、11 coordinator | 不作为证据；实际源码不符合这些描述 |
| 六个三行 shim 可以删除 | 撤销批量删除；按 M3 引用与职责分别处理 |
| 无直接同名测试就是测试盲区 | 改为覆盖矩阵，已有 presenter/coordinator/smoke，不等于零覆盖 |
| Catalog/Coordinator 多就是过度工程化 | 改为变更耦合、职责、依赖与测试成本审查 |
| AppViewModel 必须归 Application | 不采纳概念搬迁；保持 UI facade，逐步缩小真实耦合 |
| Cache 从不保存任何原始认证材料 | 收紧表述；摘要用于 key，Qwen sec_token 是短期内存 cache value |
| Task.sleep 已解决低能耗 | 收紧表述；机制替换不等于能耗收益，周期/可见性/唤醒需测 |
| 字面量正则编译期可证明合法 | 修正；NSRegularExpression 在运行时编译。可保留常量不变量并测试，不盲目 try? 静默失败 |

## 8. 实施顺序、停点与回退

### 阶段 A：护栏与确定性复现

先补 C1/C2/C3/C4 和 P4 的失败 fixture；给 loader、request、clock、I/O 增加最小测试 seam；不要在本阶段改变刷新并发、账号切换或生产配置。新增测试应先复现缺陷再验证修复，不通过弱化断言“修好”测试。

交付：可复现测试、脱敏基准场景、原行为兼容清单。禁止把构建环境错误作为跳过测试的长期理由。

### 阶段 B：正确性修复

按 C1 → C2 → C3 → C4 实施。每项独立 diff；schema 变化可读旧数据；改动只涉及应用自有缓存和生成 fixture。涉及真实数据库/凭据写入的动作不在此授权范围。

交付：正确性测试通过，数据来源与降级状态可解释；原有显示与账号隔离不回退。

### 阶段 C：并发与 I/O

按 P4 顺序保护 → P1 异步持久化 → P2 取消/single-flight → P3 容量治理推进。顺序依赖可在实现时合成小包，但不得在没有 revision/reset 护栏时先大量异步化写盘。

交付：竞态/取消/慢 I/O 测试，前后 trace 对照；没有明显收益时保持较简单实现，不为“性能”增加未证明的复杂层。

### 阶段 D：维护性整理

按 M1 → M2 → M3 推进，每次一个职责/一个 Provider。E1 可独立排在 C 阶段后；E2 只有实测支持才进入实施。

交付：边界与回归全绿，页面截图和交互验收，真实账号/权限/更新安装等未验证项明确列出。

### 回退

- 各包独立提交候选，但只有用户要求才提交；git push、安装覆盖、发布另行确认。
- 不混入版本升级、全量格式化、目录批量迁移或历史文档重写。
- 新缓存格式兼容读取旧格式；回退允许聚合缓存失效重建，不要求改写或删除用户原始日志。
- 所有真实写入/付费/权限变更仍遵守项目单独审批。

## 9. 验收与基准设计

### 9.1 正确性矩阵

| 场景 | 必须检查 |
|---|---|
| 启动恢复 | 空/旧/损坏/重复/超大缓存；恢复与新刷新交错 |
| SQLite | WAL-only 更新、checkpoint、文件缺失/权限失败；只读读取 |
| JSONL | 等长修改、非最新文件更新、文件新增删除、超长行、跨日 |
| Cursor dashboard | 满页过滤、空页、部分失败、超页数、取消、远端数据变化 |
| 后台并发 | 相同请求合并、不同账号隔离、旧 worker 取消、等待 gate 取消 |
| 持久化 | A/B 乱序、reset/remove 与旧写入交错、写失败、退出/重启 |
| 展示 | 中英文、正常/旧缓存/失败/缺数据、长标签、明暗与窄窗口 |

### 9.2 性能指标

- 生成 1k/10k/50k 日志文件集，固定有效事件、日期、缓存状态；不复制实际聊天记录。50k 是压力档，不是对所有用户规模的断言。
- 生成 1/8/24 条本地趋势缓存、1/8/16 条统计缓存、1/32/64 条 Provider 快照；同时测接近合理字节预算的输入。
- fake Provider：1/10/28 个实例；快响应、慢响应、限流、离线。并发参数对比只在 fake 中进行。
- 记录冷启动到可见缓存、设置页打开/筛选响应、fingerprint/parse/aggregate/persist 分段耗时、请求数、文件扫描次数、主线程停顿、RSS、CPU/唤醒。
- 使用 signpost/本地计数，标签不含 token、cookie、聊天内容、真实账号或完整敏感路径；不新增遥测上传。
- p50/p95 应有足够重复样本；低样本先报告单次/范围，不制造看似精确的 p95。能耗使用固定观察窗口并注明噪声。
- 硬门槛：正确性不回退、并发/缓存有界、旧任务不覆盖新结果、正常降级可信。
- 性能门槛在基准建立后确定；不以“源码少了多少行”“测试多了多少项”或“Task.sleep 替代 Timer”作为性能验收。

### 9.3 验证命令与限制

正常工程入口仍是 `swift build` / `swift test`。本机临时替代路径如下，不修改 xcode-select：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --build-system native \
  --scratch-path /tmp/oh-myusage-report-review-build
```

实施每包先跑相关测试，发布候选再跑全量及 App 页面/交互验收。仓库 CI 配置已存在，但本次没有查询远端运行结果，不能宣称最新 CI 已通过。

## 10. 暂不做的事项

- 不直接把默认并发 2 改为 3-4，不扩大启动延迟作为“已证实省电”。
- 不删除双语系统，不把所有字符串一次迁移到 xcstrings。
- 不合并所有 coordinator/Catalog，不删除有行为的 presenter。
- 不强行将整个 ProviderDescriptor/AppViewModel 搬进另一个 target。
- 不全量改写原始日志为增量数据库；先验证文件轮转、截断、去重和身份规则，再评估追加 offset/index 的价值。
- Cursor SQLite 当前全取 bubble rows 再解析是成本候选；只有真实/生成规模基准显示热点后，才尝试流式行处理、JSON1 过滤或索引，且不为优化写入真实 Cursor 数据库。
- 不保证 short-lived 内存缓存完全不含认证材料；不把缓存 key 摘要等同于全部数据脱敏。
- 不凭测试全绿断言真实账号切换、权限、安装升级、线上 Provider 契约都已验证。

最终目标不是“文件更少”或“拆得更细”，而是：数据不漏、缓存可信、后台工作可取消、主线程安静、修改有明确边界且可回退。
