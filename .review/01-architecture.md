# OhMyUsage 架构审查（审查 A：模块边界 / 单体债务 / 死代码）

- 版本：VERSION 2.5.4，HEAD `947d454`（2026-10-09 release），分支 `main`
- 审查时间：2026-10-17；**只读审查**，未改源码、未动 git 状态、未运行 `swift build/test`
- 工作树现状：`git status` 有 7 个已跟踪改动 + 2 个未跟踪文件，全部集中在 UI/Settings 的 official category 拆分（`git diff --numstat`：+371/−154；新增 `OfficialSettingsCategory.swift` 44 行、`OfficialSettingsCategoryTests.swift` 160 行）。本报告按此现状审查，未做任何修改。
- 证据约定：`文件:行号` 均为当前工作树实测；统计数字来自 `wc/grep/python` 脚本（见文末命令）。标 **待验证** 的条目需要 Lead 跑 `swift build/test` 或产品确认，本报告不臆断。

---

## 0. 项目现状快照（实测）

| 项 | 数字 |
|---|---|
| Swift 文件 / 代码行（Sources） | 352 文件 / 77,073 行；其中 executable target `Sources/OhMyUsage` **291 文件 / 71,539 行** |
| 7 个非 executable target 合计 | **61 文件 / 5,534 行（占 7.7%）**：Domain 1,112、Infrastructure 38、Providers 1,664、Application 2,214、Presentation 361、Features 77、Bootstrap 68 |
| 分层 public API 面 | Domain 225 / Providers 162 / Application 143 / Presentation 53 / Features 13 / Bootstrap 9 / Infrastructure 8 条 `public` 声明 |
| 主 target 子目录 | App 57/12,448、Services 75/19,168、UI 84/20,664（Settings 53/15,729 + Presenters 20/3,308）、Providers 35/14,596、Models 39/3,909、Utils 1/754 |
| 大文件 | ≥500 行 39 个（合计 30,892 行，占主 target 43%）；≥800 行 13 个；≥1000 行 8 个 |
| 测试 | 163 文件 / 49,269 行 / 1,344 个 `func test`（7.7 万行源码对 4.9 万行测试） |
| 架构护栏测试 | 5 文件 / 2,080 行 / 52 个 test；全仓库 17 个测试文件读源码、92 处 `String(contentsOf` |

---

## 1. 结论摘要表（按“收益/成本”排序）

| # | 发现 | 严重度 | 收益 | 成本 | 建议批次 |
|---|---|---|---|---|---|
| F1 | “名义分层”：95% 代码留在 executable，Features/Bootstrap 两 target 生产零引用 | 高 | 中高 | S | P0 |
| F2 | `Domain.ProviderConfiguration` 与 executable `ProviderDescriptor` 双模型并存，前者生产未使用 | 高 | 中 | S | P0 |
| F3 | 架构护栏以源码字符串/行数为断言，重构即红且挡迁移（重构税） | 高 | 高 | M | P0/P2 |
| F4 | `SettingsView` 单类型 god view：21 个 extension 文件/12,303 行/398 方法 | 高 | 高 | L | P1（增量） |
| F5 | 本地化双轨：8,646 个中文硬编码字符散布 88 文件，两套 API 并存 | 中高 | 中高 | M | P1 |
| F6 | 数字/百分比格式化 ≥8 处重复，阈值与后缀不一致（tok/tokens、w/K、calls/req） | 中 | 中 | S | P1 |
| F7 | Presentation 健康状态枚举在 UI 有 3 层同名副本 + 2 处重复映射 switch | 中低 | 中 | S | P1 |
| F8 | 迁移残留：4 个纯 typealias 转发文件 + 1 个零声明注释文件 + 死协议 | 低 | 中 | S | P1 |
| F9 | `LocalUsageHistoryRepository` 1093 行混装 2 个缓存 + 指纹构建 + 仓库 | 中低 | 中 | S | P1 |
| F10 | `RelayResponseInterpreter` 1200 行单 enum，vendor 特例 690+ 行，与 JSON adapter 机制脱节 | 中 | 中 | M | P2 |
| F11 | `AppConfigurationModel` 1033 行/59 个 func 吞并 8 类配置变更，且反向 `requireHost()` | 中 | 中 | L | P2 |
| F12 | Codex/Claude OAuth refresh 仍手写两份（vault 回写同构） | 中 | 中 | M | P2 |
| F13 | `Infrastructure` target 名义化：38 行协议，5k+ 行真实实现仍在 Services | 中低 | 中 | M | P2 |
| F14 | `.codex` 交接文档描述的工作区状态与当前仓库不符（误导研发） | 低 | 中 | S | P0（顺手） |

现状中值得**保留**的正向资产（不要回退）：`AppCompositionFactory`/`AppDependencyGraph` 收口（App/AppCompositionFactory.swift:1，MonolithRetirementBoundaryTests.swift:685-745 有真护栏）、ProviderStateStore 单一写入口、官方 auth runtime 已被 6 个 provider 复用（见 F12 证据）、`AppConfigDecodeResult` 的 lossy provider 解码（Models/AppConfigModels.swift:94-199）。

---

## 2. 发现详情

### F1. “名义分层”：95% 代码留在 executable，Features/Bootstrap 生产零引用（P0，成本 S）

- **评级**：严重度 高；收益 中高；成本 S；优先级 P0

- **证据**
  - `Package.swift:17-52` 声明 7 个非 executable target，`:53-67` executable 宽依赖全部 7 层；主 target 291 文件/71,539 行 vs 7 层 61 文件/5,534 行 = **7.7%**（`wc` 实测）。
  - **Features/Bootstrap 生产零引用**：全仓库 `import OhMyUsageFeatures` 只出现在 `Sources/OhMyUsageBootstrap/OhMyUsageCompositionRoot.swift:3` 与 `Tests/OhMyUsageTests/ArchitectureTargetBoundaryTests.swift:5`；`import OhMyUsageBootstrap` 只在同测试 `:3`。主 target 0 处引用（grep）。
  - `OhMyUsageCompositionRoot`/`UsageFeatureAssembly` 唯一实例化位置是测试：`ArchitectureTargetBoundaryTests.swift:198,377`；`MonolithRetirementBoundaryTests.swift:690` 只做字符串断言。
  - 7 个 `OhMyUsage*Module.swift` marker 全部零引用（如 `Sources/OhMyUsageDomain/OhMyUsageDomainModule.swift:1` 只有一行空 enum）。
  - 文档承诺 vs 现实：`docs/REFACTOR_PLAN.md:171-172` 规划 Bootstrap=app lifecycle、Features=menu bar/settings 入口；`docs/superpowers/plans/2026-08-11-architecture-debt-reduction.md:26` 把 Bootstrap 标为“DONE（策略 A）”，但两个 target 从未被生产代码引用。
- **问题**：空壳 target 的存在意义只能由“字符串护栏”自我证明（`ArchitectureTargetBoundaryTests.swift:177-249` 断言这两个文件不含 `NSApplication`/`AppViewModel` 等字符串）。它们不隔离任何真实代码、不降低编译耦合，却持续要求 Package 依赖、public 化和测试接线；对外呈现的 8 层架构图与实际 92.3%/7.7% 的代码分布严重不符。
- **建议**：二选一，不要再维持第三种状态。
  - 方案 A（推荐，成本 S）：删除 `OhMyUsageFeatures`、`OhMyUsageBootstrap` 及 7 个 marker；`Package.swift` executable/test 依赖同步收窄（顺带完成 `.codex/remaining-optimization-handoff.md:56` 的“allowlist 收窄”一项）；保留 Domain/Providers/Application/Presentation/Infrastructure 5 层并明确“只保留编译器真正隔离的层”。
  - 方案 B（若坚持分层，成本 L）：先做 F4（解 SettingsView/AppViewModel 耦合）与 F2/F13，再把 App/ 的生命周期/窗口控制器迁入 Bootstrap、菜单与设置入口迁入 Features；否则迁进去也只是把 god view 换个 target。
- **成本与风险**：删除约 10 文件/约 270 行（含测试断言约 150 行）；无运行时行为，风险低；唯一代价是放弃“未来分层”占位，需要文档同步（配合 F14）。
- **验证方式**：`swift build && swift test`；`grep -rn "OhMyUsageFeatures\|OhMyUsageBootstrap" Sources/ Tests/ Package.swift` 应无命中；`swift test --filter ArchitectureTargetBoundaryTests` 更新后仍绿。

### F2. `Domain.ProviderConfiguration` 与 executable `ProviderDescriptor` 双模型并存，前者生产未使用（P0，成本 S）

- **评级**：严重度 高；收益 中；成本 S；优先级 P0

- **证据**
  - `Sources/OhMyUsageDomain/ProviderConfiguration.swift:3-108` 新增了 `ProviderConfiguration` + `ProviderSettings`（109 行），字段与实际持久化模型几乎一致。
  - **生产引用 0**：grep 全仓库，除自身定义外只有测试引用 —— `Tests/OhMyUsageTests/ProviderConfigurationPersistenceTests.swift:11,30,62`、`ArchitectureTargetBoundaryTests.swift:420-576`；生产代码无任何 decode/encode 使用。
  - 实际持久化仍走 executable 的 `ProviderDescriptor`：`Sources/OhMyUsage/Models/AppConfigModels.swift:30`（`var providers: [ProviderDescriptor]`，Codable 直接用），`Models/ProviderModels.swift:4-19` 定义该类型。
  - 两模型不等价：`ProviderDescriptor` 有 `kimiConfig`（ProviderModels.swift:19），Domain 版本没有；测试自己承认缺口：`ProviderConfigurationPersistenceTests.swift:81` 名为 `...NotCoveredByDomainProviderConfigurationYet`。
  - `.codex/remaining-optimization-handoff.md:160-188` 正把“ProviderDescriptor / Config Domain 第一阶段”推荐为下一分支任务——但它其实已经半成品地做了，且没人接线。
- **问题**：两个 Codable 模型描述同一份 JSON schema，Domain 版没有任何运行时角色。后果：①按文档理解会以为迁移已完成；②未来任何配置字段变更要么改两处、要么用 Domain 版覆盖生产格式（高风险）；③新增 109 行 + 约 90 行测试只产出“架构正确”的假象。
- **建议**：二选一，禁止第三种状态。
  - (a) 删除 `OhMyUsageDomain/ProviderConfiguration.swift` 与对应测试（推荐，1 小时内）；等真正要迁 `ProviderDescriptor` 时再一起做，避免死模型。
  - (b) 完成迁移：`AppConfig.providers` 改用 `ProviderConfiguration` 持久化，`ProviderDescriptor` 降级为运行时视图（补齐 `kimiConfig`），补旧配置兼容测试。只有在要做 F1 方案 B / F13 时才值得。
- **成本与风险**：(a) 极低；(b) 中高（配置文件格式是用户数据，需要双向兼容测试 + 降级路径）。
- **验证方式**：(a) 删后 `swift test --filter ProviderConfigurationPersistenceTests|ConfigStoreTests|AppConfigTests`；(b) 增加“2.5.4 配置 → 新模型 → 再编码”黄金样本测试。

### F3. 架构护栏以源码字符串/行数为断言，重构即红且挡迁移（P0 策略 + P2 迁移，成本 M）

- **评级**：严重度 高；收益 高；成本 M；优先级 P0（策略）+ P2（迁移）

- **证据**
  - 规模：5 个护栏文件 2,080 行/52 test；`MonolithRetirementBoundaryTests.swift` 全文 171 个 XCTAssert、**132 处 `.contains(`、27 处 `fileExists`**；全仓库 17 个测试文件读源码、92 处 `String(contentsOf`、8 个文件依赖 `FileManager.currentDirectoryPath`。
  - 脆弱样例（改名/改缩进即红）：`ArchitectureTargetBoundaryTests.swift:708` 断言精确多行文本 `"func applyProviderStateStorage(_ state: ProviderStateStore) {\n        sessionStore.providerState = state\n    }"`；`MonolithRetirementBoundaryTests.swift:717` 断言 `"private init(\n        dependencyGraph: AppDependencyGraph,"`；`UIFileDecompositionBoundaryTests.swift:12-16,97-101` 断言行数预算 460/620。
  - 空断言样例：`MonolithRetirementBoundaryTests.swift:756` `XCTAssertTrue(appViewModel.contains("AppUsageAnalyticsModel"))`——只要类名出现即过，不能证明转发。
  - 只查“某文件不含 X”，无法发现“X 被复制到另一个文件”：例如 `ArchitectureTargetBoundaryTests.swift:669-672` 只禁止 `appViewModel` 内 `set { sessionStore.providerState`。
  - 有效断言（应保留）：`ArchitectureTargetBoundaryTests.swift:11-58`（分层 import 禁令）、`:60-91`（Package.swift target 依赖集相等）、`:614-640`（非 executable 不得引用 AppCompositionFactory/AppDependencyGraph）。
  - 护栏反噬实例：`docs/superpowers/plans/2026-08-11-architecture-debt-reduction.md:39-40` 记录“ProviderDescriptor 整文件迁入 Providers 被边界测试阻塞”；`ArchitectureTargetBoundaryTests.swift:578-612` 直接把 `ProviderDescriptor`、`SettingsDraft` 等字符串列为 Domain 红线。
- **问题**：这类测试把“文件位置/命名/缩进”冻结成契约：①任何重构先付测试修改成本（本次未提交改动也改了 `MenuVisualSnapshotRenderingTests` +92 行来配合）；②无法阻止复制粘贴式违规；③用测试维护架构事实，而不是让编译器维护——成本高、信号弱。
- **建议**：
  1. 保留并强化 3 类真护栏：target 依赖图相等、层间 import 禁令、executable 类型不得被层引用（现有 3 个 test 已覆盖，可再加“层 target 不得 import AppKit/SwiftUI”统一表）。
  2. “X 必须住在文件 Y / Y 不得含 X”优先改为编译期边界（把类型移到 target 或拆类型）；不能移动的，合并成**数据驱动 ratchet 表**（一张 `[路径: 行数上限]` + 一个通用遍历 test），而不是逐个手写字符串断言。
  3. 删除只复述行为测试的 `contains` 断言；`fileExists` 只保留在“文件本身就是边界”的场景。
  4. 每个遗留字符串护栏加退役条件注释（例：Descriptor 迁入 Providers 后删除对应断言），避免永久累积。
- **成本与风险**：中（需逐条分类 52 个 test）；风险是误删真实信号——先落地 3 类真护栏，再删字符串断言；`ProviderConfigurationDomainBoundaryTests.swift:6-215` 这类行为/契约测试应保留。
- **验证方式**：迁移后 `swift test --filter 'Architecture|MonolithRetirement|UIFileDecomposition'` 绿；人为在 `Sources/OhMyUsageDomain` 加一个 `import SwiftUI`，确认新护栏会红。

### F4. `SettingsView` 单类型 god view：21 个 extension 文件 / 12,303 行 / 398 方法（P1，成本 L）

- **评级**：严重度 高；收益 高；成本 L；优先级 P1（按 pane 增量）

- **证据**
  - `Sources/OhMyUsage/UI/SettingsView.swift:7-30`：一个 `View` 持有 `relayEditorDraft`、`officialEditorDraft`、`profileDraftState`、`dialogState`、`runtimeState`、`navigationState`、`newRelaySiteDraft` 及 3 个 `@FocusState`。
  - **21 个文件**以 `extension SettingsView` 组织，合计 **12,303 行 / 398 个 func**（脚本统计）；`UI/` 共 84 文件/20,664 行。
  - UI 通过 `viewModel.` 访问 **695 处、115 个不同成员**（`grep -rho` 统计），即 UI 依赖 `AppViewModel` 的宽接口。
  - 三个最大文件职责混杂：`UI/Settings/SettingsProviderSidebar.swift:7`（1675 行：relay row、official row、拖拽重排、图标加载塞在同一 extension）、`UI/Settings/SettingsRelayConfigurationForm.swift:24,517`（1305 行：condensed 配置、open 配置、大量纯 helper）、`UI/Settings/SettingsLocalUsageTrend.swift:66,203,539`（1260 行：official/subscription/普通三套趋势 UI，格式化逻辑重复见 F6）。
  - 现有“文件拆分护栏”只锁文件名/行数：`UIFileDecompositionBoundaryTests.swift:12-16,97-101`，不约束类型边界。
- **问题**：文件拆到 53 个已到边际收益；真正瓶颈是**一个类型承载 12k 行状态与行为**：任何设置改动都落在同一类型，SwiftUI 预览/快照只能整体构建，无法按 pane 注入依赖，评审时无法按职责分片。
- **建议**（按收益/成本排序，逐 pane 独立 PR）：
  1. 先把三个最大文件中的 pane 抽成独立 `struct`：`RelayProviderSidebarPane`、`RelayConfigurationForm`（输入 `RelaySettingsDraft` value + 回调闭包）、`OfficialSubscriptionPane`；把 `@Bindable AppViewModel` 收窄为“只读 view-state + 明确 action”。
  2. 每个 pane 的 draft/焦点/弹窗状态用独立 `@Observable` model（如 `OfficialSettingsDraftModel`）替代 SettingsView 顶层 6 个大 state 对象。
  3. 最后 SettingsView 只留导航/布局/共享状态。依赖方向：View → Presenter（纯函数）→ Model；pane 不直接读 `viewModel.config` 做派生。
- **成本与风险**：L（12.3k 行、UI 回归面大）；建议先补设置页的 1-2 张快照基线（当前 `MenuVisualSnapshotRenderingTests.swift` 只覆盖菜单），再按 pane 迁移；`SettingsViewQuotaDisplayTests`、`SettingsWorkspacePresenterTests` 可做回归网。
- **验证方式**：每 pane 抽出后 `swift test --filter 'SettingsViewQuotaDisplayTests|SettingsWorkspacePresenterTests|MenuVisualSnapshotRenderingTests'`；pane 纯函数单测；人工截图对比。
- **对当前未提交改动的评价**：方向正确（新增 `OfficialSettingsCategory` 纯逻辑 + `SettingsProviderConfigurationPresentation` 3 个小 presenter + 160 行测试，含快照 +92 行），但没有缩小 SettingsView 类型面（仍是 extension），且新文件继续使用内联双语（见 F5）。

### F5. 本地化双轨：8,646 个中文硬编码字符散布 88 文件，两套 API 并存（P1，成本 M）

- **评级**：严重度 中高；收益 中高；成本 M；优先级 P1

- **证据**
  - `Sources/OhMyUsage/Utils/Localization.swift:1-754`：`L10nKey` 枚举 + `text(_:language:)` 两个大 switch（`:232`、`:461`）+ 通知文案（`:689-754`）。
  - 主线之外：**88 个文件含硬编码中文，共 8,646 字符**（脚本统计；Localization.swift 自身 1,749 字符不计）；`language == .zhHans` 内联三元 **103 处**；`localizedText(` 368 处、`viewModel.text(.` 172 处——三套写法并存。
  - 同一函数混用两套：`UI/Settings/SettingsQuotaDisplayHelpers.swift:174-195`（6 个 case 用内联中文，2 个 case 用 `viewModel.text(.statusX)`）。
  - 最新未提交文件继续内联：`UI/Settings/OfficialSettingsCategory.swift:11-13`（`language == .zhHans ? "管理订阅账号…" : "Manage…"`），说明没有规则约束新代码。
  - 人工 copy 审计表已达 `docs/copy-audit.md` 616 行，靠文档而非代码维护文案一致性。
- **问题**：没有单一字符串清单 → 无法做完整 i18n、无法审计未翻译文本、同文案多处复制易漂移；新代码随作者习惯分叉。
- **建议**：不做一次性大迁移（成本高、收益滞后），分两步：
  1. 定规则 + 增量约束：新代码只允许 `text(.key)` 或 `localizedText(zh, en)` 之一；加一个 grep 型 CI ratchet（记录当前内联计数，只准降不准升）。顺手把 copy-audit 从人工表变成脚本生成的检查项。
  2. 按“正在改的文件”顺带迁移：优先 UI/Settings 的 103 处 `language ==` 三元；providers 里的中文 note（`Providers/ZaiProvider.swift` 496 字符、`QwenProvider.swift` 355 字符）先确认是否用户可见，不可见就改英文常量。
  - 长期 String Catalog 已在 `docs/OPTIMIZATION_IMPLEMENTATION_2026-10-09.md:82` 明确不列入本轮，保持该结论。
- **成本与风险**：M（按文件增量）；风险是文案变化影响 UI 快照与用户预期，需要快照/评审配合。
- **验证方式**：ratchet 计数不增长；改动文件的 zh/en 截图；新增 `SettingsCopyTests` 覆盖迁移后的 key→文案。

### F6. 数字/百分比格式化 ≥8 处重复，阈值与后缀不一致（P1，成本 S）

- **评级**：严重度 中；收益 中；成本 S；优先级 P1

- **证据**
  - 唯一较完整实现：`Services/UsageDisplayFormatter.swift:455-540`（`LocalTrendValueFormatter.compactNumber`：万/亿、K/M/B）。
  - 副本：
    - `UI/Settings/SettingsLocalUsageTrend.swift:507-536`：自成一套（`1_000_000_000 → "B"`、`10_000 → "w"`、后缀 `"tok"`/`"w calls"`），阈值与 suffix 都和主实现不同；
    - `UI/Settings/UsageAnalyticsSettingsView.swift:662-681`：文件级 `tokenText`/`percentText`/`percentTextFixed`；
    - 同一段 `NumberFormatter + "%.2f" fallback` 复制 6 份：`SettingsThresholdControls.swift:22-28`、`SettingsQuotaDisplayHelpers.swift:695-700`、`SettingsProviderSidebar.swift:519-526`、`SettingsRelayRuntimeStatus.swift:24-30`、`StatusBarDisplayPresenter.swift:266-274`、`MenuCardStatePresenter.swift:151-156`；
    - `UI/Settings/OfficialSettingsCategory.swift:38-43` 又一套 amount 格式。
  - 用户可见口径不一致：`次` / `req` / `calls` / `w calls`（`SettingsLocalUsageTrend.swift:511-516` vs `UsageDisplayFormatter.swift:476-484`）属同一指标。
- **问题**：同一 App 内同一数值出现不同单位/精度；四舍五入与本地化规则分散，新增面板继续复制；`%.2f` fallback 意味着 locale 行为不确定。
- **建议**：收敛到单一 Formatter API（建议放 `OhMyUsageApplication` 或 `Services/UsageDisplayFormatter`）：`compactToken(_:language:)`、`decimal(_:fractionDigits:locale:)`、`percent(_:fractionDigits:)`；删除 6 处本地 `%.2f` helper 与 Settings 副本；单位后缀做一次产品口径决定（token/tokens、次/req 统一）。约 0.5–1 天机械替换。
- **成本与风险**：S；风险是用户可见文案变化（这是目的），需更新 UI 快照。
- **验证方式**：新增 formatter 单测（0/999/1k/1万/1亿/负数/NaN，zh/en）；`swift test --filter 'CountdownFormatterTests|LocalUsageTrendPresenterTests|SettingsViewQuotaDisplayTests'`；截图前后对比。

### F7. Presentation 健康状态枚举在 UI 有 3 层同名副本 + 2 处重复映射 switch（P1，成本 S）

- **评级**：严重度 中低；收益 中；成本 S；优先级 P1

- **证据**
  - 权威定义：`Sources/OhMyUsagePresentation/OfficialMonitoringHealthPresenter.swift:4-10`（8 个 case）。
  - 副本 1：`UI/SettingsView.swift:73-82` 同构嵌套枚举 + `:98-123` 逐 case 映射函数（把 Presentation 结果转成嵌套枚举）。
  - 副本 2：`UI/Presenters/SettingsQuotaPresenter.swift:5` typealias + `:39-47` 纯转发包装。
  - 重复映射 switch 两处：`UI/Settings/SettingsQuotaDisplayHelpers.swift:174-195`、`UI/Settings/SettingsOfficialProfileManagement.swift:402-430`（同样 8 case、同样中文串，颜色值不同：`SettingsVisualTokens.Status.*` vs `Color(hex:)`）。
  - 注意名字解析陷阱：在 `extension SettingsView` 内，**嵌套类型优先于文件级 typealias**，所以 Settings 文件里的 `OfficialMonitoringHealthStatus` 实际指向 `SettingsView` 的嵌套枚举，而 `SettingsQuotaPresenter` 的 typealias 指向 Presentation 类型——同名两类型共存（推断自 Swift 名字查找规则，**最终以 Lead 编译确认**）。
- **问题**：一次“抽取到 Presentation”的重构（docs M3）在 UI 留下 3 层副本和 2 个重复 switch；同名类型共存使后续读者/迁移者极易改错；文案与颜色已出现分叉。
- **建议**：删除 `SettingsView.swift:73-123` 与 `SettingsQuotaPresenter.swift:5,39-47`；UI 直接使用 `OhMyUsagePresentation.OfficialMonitoringHealthStatus`；把两处 `(text, color)` 映射合并为 `OfficialMonitoringHealthStatusPresentation.presentation(for:language:)` 放 Presentation 或 UI/Presenters，并补 8 个 case 的单测。
- **成本与风险**：S；风险是两处颜色不同需产品确认（大概率是历史漂移）。
- **验证方式**：`swift test --filter 'SettingsViewQuotaDisplayTests'`（该文件 248/279 行已直接测 `SettingsQuotaPresenter`）；新增枚举映射测试；菜单/设置截图。

### F8. 迁移残留：4 个纯 typealias 转发文件 + 1 个零声明注释文件 + 死协议（P1，成本 S）

- **评级**：严重度 低；收益 中；成本 S；优先级 P1

- **证据**
  - `Services/UsageAnalyticsTypes.swift:4-19`：16 个 `typealias X = OhMyUsageApplication.X`；
  - `Services/UsageAnalyticsSnapshotCacheStore.swift:3`、`Services/UsageAnalyticsAggregator.swift:3`、`Services/CodexQuotaDisplayNormalizer.swift:3`：各只有 1 个 typealias；
  - `Services/UsageAnalyticsModels.swift:1-5`：**只有注释、零声明**的文件（仍参与编译）；
  - `OhMyUsageApplication/RefreshUseCaseContracts.swift:14-16`：`UsageRefreshUseCase` 协议全仓库无 conformer、无引用（grep 命中仅定义处）。
  - 说明：`docs/OPTIMIZATION_IMPLEMENTATION_2026-10-09.md:30` 明确“保留迁移 typealias … 不为删除几行引入广泛引用改动”——这是有意决策，本发现不要求一次全删。
- **问题**：alias 层让“类型属于哪个 target”变得模糊，读者无法从类型名判断 import；零声明文件与死协议是纯噪声。
- **建议**：立即删 `UsageAnalyticsModels.swift` 与 `UsageRefreshUseCase`（零引用、零风险）；alias 保留但加可追踪的退役标记（当前仓库 `TODO/FIXME/HACK` 统计为 **0**，可引入 `ARCHIVE:` 标记并在 CI 统计），等 import 清理成本可接受时删除。
- **成本与风险**：S，风险极低。
- **验证方式**：`swift test`；`grep -rn "UsageRefreshUseCase\|UsageAnalyticsModels"` 无命中。

### F9. `LocalUsageHistoryRepository` 1093 行混装 2 个缓存 + 指纹构建 + 仓库（P1，成本 S）

- **评级**：严重度 中低；收益 中；成本 S；优先级 P1

- **证据**（均在该文件内）
  - 数据结构 7-66；`LocalUsageFileEnumerationCache` 68-327（含文件枚举缓存 + 校验 + 剪枝）；`LocalUsageParsedFileCache` 328-419（解析结果 LRU）；`LocalUsageSourceInventory` 420-440 + `LocalUsageSourceFingerprintBuilder` 441-654（6 个 provider 各自的 fingerprint 分支）；`LocalUsageHistoryRepository` 655-1093（刷新/恢复/持久化/取消）。
- **问题**：一个文件 4 类职责、2 个 `@unchecked Sendable` 缓存与仓库共享锁边界；单测只能整文件加载，缓存逻辑难独立测。
- **建议**：按既有命名惯例拆 4 个文件（纯移动，不改逻辑）；后续把 `441-533` 的 provider 分支改成 descriptor 驱动（与 F10 同风格）。已有 `LocalUsageHistoryRepositoryTests.swift`（973 行）覆盖，风险低。
- **成本与风险**：S（约 2 小时机械拆分）；注意 `@unchecked Sendable` 锁不跨类拆分，避免语义变化。
- **验证方式**：拆后 `swift test --filter 'LocalUsageHistoryRepositoryTests|LocalUsageHistoryRefreshCoordinatorTests|UsageAnalyticsRepositoryTests'`；`git diff` 确认仅移动。

### F10. `RelayResponseInterpreter` 1200 行单 enum，vendor 特例 690+ 行，与 JSON adapter 机制脱节（P2，成本 M）

- **评级**：严重度 中；收益 中；成本 M；优先级 P2

- **证据**
  - `Providers/RelayResponseInterpreter.swift:28` 单 enum；`:31-162` `extractAccountValues`；`:163-170` MiniMax；`:171-444` xiaomimimo token plan；`:445-858` xiaomimimo plan type；`:859-1200` sub2api。
  - 分发靠散落 if：`:83` `manifest.postprocessID == .sub2apiUsage`、`:121` `== .quotaDisplayStatus`；重复 note 构造 `:145/:510/:604/:666/:1143`。
  - 已有数据驱动机制：`Resources/RelayAdapters/*.json`（10 个 manifest，含 `xiaomimimo*.json`）+ `Services/RelayAdapterRegistry.swift:3`（加载/缓存/装饰）；`Domain/RelayModels.swift:302` 已有 `RelayPostprocessID`。
- **问题**：manifest 已能描述 endpoint/path/extract，但 vendor 特有后处理仍写死在 1200 行解释器里，且以 if 链分发；新增 relay 站点继续加长同一文件。
- **建议**：第一步先按文件拆 4 个（Account / MiniMax / Xiaomimimo / Sub2API）+ 抽公共 note 构造，纯静态拆分零行为变化；第二步把 if 链改成 `RelayPostprocessID -> handler` 注册表（类型放 OhMyUsageProviders，解释器只调度）。若某 vendor 可纯 JSON 表达，优先迁到 adapter manifest。
- **成本与风险**：M；解析语义有回归风险，但 `Tests/OhMyUsageTests/RelayProviderTests.swift`（3,756 行）覆盖充分。
- **验证方式**：`swift test --filter 'RelayProviderTests|MiniMaxCodingPlanParser'`；拆后对比每 vendor fixture 输出。

### F11. `AppConfigurationModel` 1033 行/59 个 func 吞并 8 类配置变更，且反向 `requireHost()`（P2，成本 L）

- **评级**：严重度 中；收益 中；成本 L；优先级 P2

- **证据**：`App/AppConfigurationModel.swift:11,31`（`bind(host:)`）、`:1027` `func requireHost() -> AppViewModel`；职责分区：provider list 35、credential lookup 105、credential mutation 179、relay/open 284、official 669、app-level 735、persist/reset 802、provider lookups 862、私有编排 921。
- **问题**：一个类型同时是 8 类变更入口 + 反向依赖宿主 `AppViewModel`；任何配置面板改动都进入同一文件，单测必须构造完整 `AppViewModel`；`requireHost()` 让这个中央枢纽与其宿主形成双向环。
- **建议**：按“变更事务”拆 4 个协调器（部分类型已存在，把入口挪进去即可）：`ProviderListMutationCoordinator`（已有，收 setEnabled/reorder/remove）、`CredentialMutationCoordinator`（save/delete/invalidate）、`RelayDraftCoordinator`（addRelaySiteDraft/test*/saveRelayDraft）、`AppPreferencesCoordinator`（language/resourceMode/launchAtLogin/persist/reset）；用闭包/协议注入替代 `requireHost()`。
- **成本与风险**：L（配置持久化路径，回归面大）；建议先移纯函数/静态方法，再移可变入口，逐块跑 focused tests。
- **验证方式**：`swift test --filter 'ConfigStoreTests|AppConfigTests|ProviderConfigurationPersistenceTests|SettingsWorkspacePresenterTests|AppRelayProviderSettingsCoordinator'`；每块迁移单独 PR。
- 说明：该类的存在本身是历史优化的产物（“AppViewModel facades”），本条不是否定它，而是指它已成为新的单点。

### F12. Codex/Claude OAuth refresh 仍手写两份（vault 回写同构）（P2，成本 M）

- **评级**：严重度 中；收益 中；成本 M；优先级 P2

- **证据**
  - `Providers/CodexProvider.swift:349-416`：`refresh(credentials:)` + `updateVaultAfterRefresh` + `persist`；
  - `Providers/ClaudeProvider.swift:249-316`：同构骨架（构造 token 请求 → `OfficialProviderAuthRuntime.requestOAuthRefresh` → 更新字段 → `persist` → `saveOAuthJSON`），差异仅在 token 字段映射与 JSON 键名。
  - 已复用 runtime 的 provider：`CursorProvider.swift:31`、`KimiOfficialProvider.swift:71`、`GrokProvider.swift:47`、`GeminiProvider.swift:113`、`GrokBotProvider.swift:48` 使用 `requestWithExpiringCredentialRefresh`；`Codex/Claude` 仍是各自实现。
  - `.codex/remaining-optimization-handoff.md:189-205`“后续分支 2：官方 Auth Runtime 继续抽取”仍未完成。
- **问题**：同一套“刷新→字段更新→文件回写→vault 回写”逻辑两份；新增此类 provider 会复制第三份；vault 回写是账号态关键路径，重复实现放大不一致风险。
- **建议**：在 `OhMyUsageProviders` 增加泛型 `OAuthRefreshPipeline<State>`（3 个闭包：makeRequest / applyResponse / persist，加 vault 写入钩子）；先接 Codex（测试夹具最全）再接 Claude；Gemini/Kimi 的 refresh 一并统一。
- **成本与风险**：M（认证敏感）；风险是 token 回写格式错误损坏登录态——保留现有 fixture 测试，并新增“刷新后保留 JSON 其他字段”的压缩测试；**真实刷新验证需用户手工做（标注待验证）**。
- **验证方式**：`swift test --filter 'OfficialProviderTests|CodexDesktopAuthServiceTests|ClaudeDesktopAuthServiceTests|OfficialProviderAuthRuntimeTests'`；人工验证一次真实 token 刷新。

### F13. `Infrastructure` target 名义化：38 行协议，5k+ 行真实实现仍在 Services（P2，成本 M）

- **评级**：严重度 中低；收益 中；成本 M；优先级 P2

- **证据**：`Sources/OhMyUsageInfrastructure` 仅 3 文件 38 行（`CredentialStoring.swift:5-13` 协议、`UsageCredentialStore.swift:5-9`、marker）；真实实现仍在 executable：`Services/KeychainService.swift` 777、`BrowserStorageCredentialReader.swift` 439、`BrowserCookieDatabaseReader.swift` 496、`BrowserCredentialService.swift` 363、`SecurityCredentialReader.swift` 175、`OAuthImportOrchestrator.swift` 844 等；主 target 仅 2 处 import Infrastructure（`KeychainService.swift:4`、`ProviderPortAdapters.swift:2`）。
- **问题**：基础设施层“协议在这、实现在那”，和 F1 同构：分层图上有 Infrastructure，实际只是端口声明。它是 Provider 实现无法迁入 `OhMyUsageProviders` 的前置阻塞之一（provider 依赖 keychain/browser 服务）。
- **建议**：(a) 若按 F1 方案 B 继续分层：把上述凭证/浏览器实现迁入 Infrastructure（这些文件不依赖 SwiftUI；全仓库 32 文件 import AppKit，需先筛掉平台耦合），并把 public 化 + 注入点补齐；这是让 14.6k 行 Providers 实现迁入 Providers target 的前置步骤。(b) 若按 F1 方案 A 收敛：把这两个协议并回 Providers 或 executable，避免“协议在此、实现在彼”的假象。
- **成本与风险**：M；Keychain/浏览器属敏感路径，现有 `BrowserCredentialServiceTests.swift`（971 行）、`CredentialBrokerTests` 可作回归网。
- **验证方式**：迁移后 `swift test --filter 'BrowserCredentialServiceTests|CredentialBrokerTests|Keychain'`；Package.swift 依赖图同步更新。

### F14. `.codex` 交接文档描述的工作区状态与当前仓库不符（P0 顺手，成本 S）

- **评级**：严重度 低；收益 中；成本 S；优先级 P0（顺手）

- **证据**
  - `.codex/remaining-optimization-handoff.md:9` 声称“代码变更已 staged，未 commit、未 push”“在 `codex/整体优化` 分支上”；实测 `git diff --cached` 为空、当前分支 `main`、HEAD `947d454`（2026-10-09 release 2.5.4）。
  - `:22` 记录“`swift test`：804 tests”；当前 `func test` 计数 **1,344**（2026-10-09 文档记录 1,326 项）。
  - 文档更新时间 `:3` 为 2026-05-19，而 repo 已有 `docs/OPTIMIZATION_IMPLEMENTATION_2026-10-09.md` 的 10-09 记录与 2.5.4 发布说明。
  - `:160` 推荐的“ProviderDescriptor 第一阶段”已有半成品（见 F2），照做会重复劳动。
- **问题**：这是新会话/新 agent 的第一入口，错误的状态描述会导致重复实现、错误分支操作，或误判“已完成/未完成”。
- **建议**：把 `.codex/remaining-optimization-handoff.md` 头部加 `ARCHIVED` 并指向 `docs/OPTIMIZATION_IMPLEMENTATION_2026-10-09.md`；新建一页“当前架构事实”（target 清单、已迁/未迁、护栏清单、测试基线数字），或直接在 AGENTS.md 增加“architecture source of truth”指针。
- **成本与风险**：S，零风险。
- **验证方式**：文档校对 + 下次会话按新文档能复现统计数字。

---

## 3. 对历史优化文档的核对（不重复已完成项）

| 文档主张 | 实测结论 |
|---|---|
| `UsageSnapshot`/`UsageQuotaWindow`/`ProviderType`/`ProviderFamily` 已迁 Domain（remaining-optimization-list 第 11/13/15 项） | **属实**：Domain 有对应文件；主 target 130 文件 `import OhMyUsageDomain`；`ArchitectureTargetBoundaryTests.swift:342-418` 可跨 target 构造 |
| Provider auth runtime 已抽取并复用（第 9/14 项） | **大部分属实**：6 个 provider 复用；但 Codex/Claude 自带 refresh 仍在（F12） |
| CC Switch streaming、指纹/WAL、缓存容量、取消/复用等 C1-C4/P1-P4/E1 项（10-09 文档） | 未逐项复核运行时行为（超出架构范围）；从代码结构看对应类型/测试存在（如 `CCSwitchUsageLogReaderStreamEvent`、`LocalUsageSourceFingerprint`）——**建议 Lead 的构建/测试/性能审查覆盖** |
| ProviderDescriptor / config Domain 迁移第一阶段（handoff 推荐下一分支） | **半成品且未接线**：Domain 已有 `ProviderConfiguration`，但生产不用（F2） |
| executable/test target broad allowlist 收窄（handoff 剩余项 4） | **未做**：`Package.swift:53-83` 仍是全部 7 层 + 全栈测试依赖；且被 `ArchitectureTargetBoundaryTests.swift:103-126` 用 TODO 注释锁定 |
| 通用 OAuth/凭据拆分、全量 string catalog、migration alias 删除（10-09 文档明确保留） | 与 F5/F8/F12 一致；**文档遗漏的是**：死 target（F1）、死 Domain 模型（F2）、字符串护栏重构税（F3）、SettingsView 类型级 god view（F4）、格式化重复（F6）、三层枚举副本（F7） |

**文档遗漏总结**：历史文档把注意力放在“运行时正确性 + 局部抽取”，但没有再评估“分层投入产出比”，也没有把“空壳 target / 未接线 Domain 模型 / 字符串护栏”登记为债务；这三类恰恰是当前最便宜可清、且最影响后续判断的部分。

---

## 4. 建议落地顺序（按 PR 切片）

1. **PR-1 清理死层与死模型（0.5–1 天，F1+F2a+F8 部分+F14）**：删 Features/Bootstrap/marker、删 `Domain.ProviderConfiguration` 与其测试、删零声明文件与死协议、归档 `.codex` 交接文档、同步 Package.swift 与架构测试 allowlist。收益：架构图与实际一致；测试/依赖面立即缩小。
2. **PR-2 护栏换代（1–2 天，F3）**：先补 3 类真护栏（依赖图/import 禁令/executable 类型引用），再删除复述行为的 `contains`/精确文本断言；把文件行数预算合并成一张 ratchet 表。收益：后续所有重构不再付测试修改税。
3. **PR-3 UI 一致性包（2–3 天，F6+F7）**：格式化收敛 + 删除 3 层健康状态副本 + 合并 2 个映射 switch。收益：用户可见不一致消失，代码显著变短，风险低。
4. **PR-4 本地化规则（2–3 天，F5）**：加 ratchet、统一新代码规则、迁移 Settings 的 103 处内联三元。
5. **PR-5 Settings pane 拆分（按 pane 分批，2–3 周，F4）**：每 pane 独立 PR，先补快照。
6. **PR-6 大文件/中枢拆分（F9 → F10 → F11）**：LocalUsageHistoryRepository 先做（纯移动），再 RelayResponseInterpreter（按 vendor 拆文件 + 注册表），最后 AppConfigurationModel（事务拆分）。
7. **PR-7（可选，仅在确认要做真分层时）**：F13 Infrastructure 实心化 → 再迁 Providers 实现 → 最后才可能收窄 executable/test 依赖（handoff 剩余项 4）。

---

## 5. 如果只做 3 件事

1. **拆掉“架构剧场”**：删除 Features/Bootstrap/7 个 marker（F1）+ 删除未接线的 `Domain.ProviderConfiguration`（F2）+ 归档 `.codex` 过期交接文档（F14）。半天到一天，让 8 层架构图变成 5 层真边界，后续所有判断不再被误导。
2. **给护栏换代**：保留 3 类真依赖约束，把“某文件必须包含某字符串/行数预算”的断言换成数据驱动 ratchet 或编译期边界（F3）。否则每次重构都先改测试，任何后续优化都会被护栏征税。
3. **把 Settings 从“一个类型 12k 行”拆成 pane 级 View + `@Observable` model（F4），第一步先做 `SettingsProviderSidebar`/`SettingsRelayConfigurationForm`/`SettingsLocalUsageTrend` 三个文件内的 pane 抽取**；顺手把格式化重复（F6）与三层健康状态副本（F7）一起清掉。用户诉求的“真实可落地优化”里，这一项对日常开发速度的回报最高。

---

## 附：本次统计使用的主要命令

```sh
# target/文件规模
for d in Sources/*/; do find "$d" -name '*.swift' ...; done
find Sources/OhMyUsage -name '*.swift' -exec wc -l {} + | sort -rn
# 引用/import
grep -rn "^import OhMyUsage" Sources/OhMyUsage/ | awk -F'import ' '{print $2}' | sort | uniq -c
grep -rn "import OhMyUsageFeatures\|import OhMyUsageBootstrap" Sources/ Tests/
grep -rho "viewModel\.[a-zA-Z]*" Sources/OhMyUsage/UI | sort -u | wc -l
# 中文硬编码 / 本地化
python3：遍历 Sources/OhMyUsage，正则 [\u4e00-\u9fff] 计数（排除 Utils/Localization.swift）
grep -rn "language == \.zhHans" Sources/OhMyUsage --include='*.swift' | wc -l
# 护栏
grep -c "func test" Tests/OhMyUsageTests/{Architecture*,Monolith*,UIFile*,ProviderConfigurationDomain*}
grep -rn "String(contentsOf" Tests/OhMyUsageTests | wc -l
# 死代码
grep -rn "ProviderConfiguration" Sources/ Tests/ | grep -v 视图/presenter 名
grep -rn "UsageRefreshUseCase" Sources/ Tests/
```
