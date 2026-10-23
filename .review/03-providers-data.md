# 审查 C：Provider / Relay / 凭证 / 配置持久化层

- 审查对象：OhMyUsage v2.5.4（macOS 菜单栏 SwiftPM App）
- 方式：**只读静态审查**。未运行 `swift build` / `swift test` / 未改源码 / 未动 git；本文所有结论均可通过 `file:line` 复核。
- 覆盖：`Sources/OhMyUsage/Providers`（35 文件 16.3k 行）、`Sources/OhMyUsageProviders`（23 文件 1.66k 行）、`Sources/OhMyUsage/Services` 中凭证/配置/持久化相关（KeychainService 777、OAuthImportOrchestrator 844、ClaudeAccountProfileStore 981、CodexAccountProfileStore 526、RelayAdapterRegistry 506、ConfigStore 系列、CredentialBroker 279…）、`App/AppConfigurationModel`(1033) 与 `App/AppCompositionFactory`、`Resources/RelayAdapters/*.json`（10 个）、以及对应测试（164 个测试文件里与本范围相关的 ~39 个）。
- 未覆盖：UI 渲染细节、更新服务下载逻辑（AppUpdateService 仅做接口级浏览）。

## 摘要

Provider 层现状总体不错：官方 auth/fetch runtime 已抽取并覆盖 7 个 OAuth provider，`CredentialBroker`/`OfficialOAuthVaultStore`/`RelayHTTPClient` 已把大部分"一条龙"逻辑收口，Relay 有 ~90 个行为测试。**真正需要动手的不是再抽一层架构，而是 3 类"会丢数据/丢凭证"的具体缺陷 + 1 类重复分叉**：

1. **凭证 vault 是"整快照 JSON + 多写入方"**：Keychain 里所有秘密存在一个 JSON blob 中，`saveToken` 把内存全量快照写回、且写操作不串行；生产环境里 `CodexDesktopAuthService` 又自带一份**独立 KeychainService 实例**（`AppViewModel()` 默认参数链），两个实例各持旧快照互相覆盖 → 可丢凭证/账户串扰（见 F1）。
2. **OAuth token 明文落盘**：`claude_profiles.json` / `codex_profiles.json` 直接保存完整 access/refresh token 的 JSON（`credentialsJSON`/`authJSON`），与应用里"秘密只进 Keychain"的总体设计不一致（F2）。
3. **配置损坏路径会删掉唯一可恢复数据**：全量不可解码时先 `preserveFallbackCandidateIfNeeded` 保存原始坏数据，紧接着 `save(defaultConfig)` 又把它删掉（F3）。
4. 20 个 provider 文件各自内联一份 HTTP 状态校验（约 400–600 行重复），且行为分叉：官方 provider 的 429 **丢失 Retry-After**，Relay token/balance 两个通道对 403 的处理不同；Claude/Codex 还手写了一套 `requestWithExpiringCredentialRefresh` 已有实现（F4/F5）。

详细见下。每条给出"证据 / 影响 / 渐进建议 / 如何验证"，并区分**已修复/已有测试**与**仍缺**。末尾有"只做 3 件事"。

---

## 一、已完成的收敛与已有测试（不要重复建议）

| 已完成 | 证据 |
|---|---|
| OAuth 预刷新 + 401 单次重试 runtime | `OhMyUsageProviders/OfficialProviderAuthRuntime.swift:38-97`；Gemini `GeminiProvider.swift:113-129`、Grok `GrokProvider.swift:47`、GrokBot `GrokBotProvider.swift:48`、KimiOfficial `KimiOfficialProvider.swift:71`、Cursor `CursorProvider.swift:31` 已复用 |
| 官方快照缓存 / 串行 gate / stale fallback / generation 失效 | `OhMyUsageProviders/OfficialProviderFetchRuntime.swift:29-73,121-218`；Claude `ClaudeProvider.swift:68-76`、Codex `CodexProvider.swift:59-70`、Gemini `GeminiProvider.swift:64-73`、KimiOfficial `KimiOfficialProvider.swift:48`、Zai `ZaiProvider.swift:66-76` |
| 统一 CredentialBroker（in-flight 合并、正/负缓存、非交互读） | `Services/CredentialBroker.swift:95-208`；测试 `Tests/OhMyUsageTests/CredentialBrokerTests.swift` |
| OAuth vault：先验证后写、vault→文件→外部 Keychain 优先级、外部 Keychain 只在显式导入路径 | `Services/OfficialOAuthVaultStore.swift:80-118,125-156`；`Tests/OhMyUsageTests/OfficialOAuthVaultStoreTests.swift` |
| Relay 双通道独立缓存 + 按凭证指纹做 key（不落明文） | `Providers/RelayProvider.swift:22-27,292-328`；`Services/ProviderFetchCaches.swift:10-15`；测试 `RelayProviderTests.swift:3442,3617,3661` |
| Relay adapter JSON 可向后兼容解码、本地目录热加载（60s TTL + 指纹） | `Domain/RelayModels.swift:355-384`；`Services/RelayAdapterRegistry.swift:174-208`；测试 `RelayAdapterRegistryTests.swift` |
| 配置四快照恢复 + lossy provider 诊断 + 保留 fallback candidate + 官方 profile 状态兜底 | `Services/ConfigStore.swift:26-110`；`ConfigSnapshotLoader.swift`、`ConfigSnapshotWriter.swift`；测试 `ConfigStoreTests.swift`（27 个 test） |
| Keychain 历史 service 迁移（OhMyUsage / AI Plan Monitor 等） | `Services/KeychainService.swift:235-263,398-458`；`KeychainServiceTests.swift` |
| 输出侧已做脱敏：无 `print`、无 token 进 rawMeta/note/诊断 | 全仓 `NSLog` 仅 3 处（`ConfigStore.swift:196`、`PersistedSnapshotCache.swift:397,438`），均不含值；`RelayDiagnosticSnapshotPreview` 只有数值（`Models/UsageSnapshotModels.swift:3-17`） |

**仍缺**（下文展开）：统一 HTTP 校验 runtime、写盘/持久化失败的可观测性、多写方 vault 串行化、配置 schema 版本。

---

## 二、按风险排序的发现（12 条）

### F1【高｜正确性/凭证】Keychain vault 是"整快照 JSON"，生产环境存在两个 KeychainService 实例并发写 → 可丢凭证

- 证据：
  - 所有秘密存进同一个 vault item：`KeychainService.swift:34-37`（service=`oh-myusage`, account=`__credential_vault__`），`readVaultSnapshotFromSecureStore` 整个 `[String:String]` 解码（`:558-567`）。
  - 写路径：`saveToken` 先在锁内更新内存快照、**出锁后才** `persistSecureSnapshot`（`:160-183`）；`deleteToken` 同样（`:185-204`）；`mergeIntoVault` 先读缓存、再持久化、再合并（`:460-476`）。多个写入方之间没有任何"读最新磁盘状态 + 合并"的串行化。
  - 生产组合里出现**第二个实例**：`AppViewModel.swift:289` 默认参数 `codexDesktopAuthService: CodexDesktopAuthService = CodexDesktopAuthService()`；`CodexDesktopAuthService.swift:51-53` 默认 `OfficialOAuthVaultStore(keychain: CredentialBroker(keychain: KeychainService()))`；`AppCompositionFactory.swift:44` 的 `codexDesktopAuthService ?? CodexDesktopAuthService(oauthVault: oauthVaultStore)` 因为实参非 nil 而**永远走不到共享 vault**。而 `AppOfficialProfilesModel.swift:243-264` 的账户切换/sync 正是通过这个私有实例 `saveVaultOAuthJSON` 写 vault；`AppViewModel.swift:408` 的 `OAuthImportOrchestrator` 用的却是共享 `oauthVaultStore`。
- 影响：vault 里不只有 OAuth JSON，而是**所有 provider 的 keychain 凭证**。实例 B 在 t0 读到旧快照，t1 其它路径（共享实例）新增了 relay/API key，t2 B 为写 Codex OAuth JSON 把旧快照整份写回 → 该 key 从 Keychain 消失（内存里可能还在，直到退出）。同类竞态也存在于同一实例的并发 `saveToken`（两个后台刷新同时更新各自 token）。这是"偶发丢凭证/换号后另一站点失效"一类难排查问题的根。
- 渐进建议（不重写）：
  1. `KeychainService` 改为进程级单例（`static let shared`），或把 vault 持久化放到一个私有串行队列/actor：`saveToken/deleteToken` 在串行区内做"重读磁盘 vault → 合并本条变更 → 原子写回"，避免整份旧快照覆盖；保留现有内存缓存只作加速。
  2. 修组合根：`AppViewModel`/`makeDependencyGraph` 中 `codexDesktopAuthService` 默认值改为 `nil`（与 `claudeDesktopAuthService` 一致，后者已经是 nil 并因此拿到共享 vault），或强制注入同一 `OfficialOAuthVaultStore`。
  3. 中期可把 vault 由"单 JSON blob"改为"每 account 一个 Keychain item"（迁移一次性完成），从结构上消除 lost update。
- 验证：新增 `KeychainServiceTests` 并发/多实例用例（见测试清单 T1/T2）；另加一个组合根断言（T3）。

### F2【高｜安全/持久化】官方账户档案把完整 OAuth token 明文写进 Application Support JSON

- 证据：`Models/OfficialAccountProfileModels.swift:26`（`CodexAccountProfile.authJSON: String`）、`:74`（`ClaudeAccountProfile.credentialsJSON: String?`）；`CodexAccountProfileStore.swift:350-362` 与 `ClaudeAccountProfileStore.swift:967-979` 用 `JSONEncoder` + `Data.write(.atomic)` 写入 `codex_profiles.json` / `claude_profiles.json`（路径 `CodexAccountProfileStore.swift:53-60`、`ClaudeAccountProfileStore.swift:55-61`）。写入内容确实包含 token：`ClaudeAccountProfileStore.swift:112-145`（`credentialsJSON: resolvedCredentialsJSON`）、`CodexAccountProfileStore.swift:87-112`。
- 影响：应用刻意把单凭证放进 Keychain vault（且 Gemini 明确注释"刷新后的 token 绝不写回明文文件"，`GeminiProvider.swift:403-406`），但多账号档案把 `access_token + refresh_token`（有时还有 id_token）以明文 JSON 存在 `~/Library/Application Support/OhMyUsage/`，且代码里没有收紧 `0600` 权限。对"同用户其它进程/备份/同步盘"暴露面明显大于 Keychain 项。这不是新需求，而是与既有安全模型的直接矛盾。
- 渐进建议：
  1. 保留 profile 元数据（slotID/displayName/email/configDir/fingerprint）在 JSON，把 `credentialsJSON`/`authJSON` 移到 vault（account 形如 `official/claude/profile/<slotID>`），读取时按 slotID 取；首次加载做一次性迁移（vault 写成功才从 JSON 删除，失败保留兼容读）。
  2. 迁移完成前至少对两个 profile JSON 设置 `0600`（`FileManager.setAttributes([.posixPermissions: 0o600])`），并在保存路径保持权限。
- 验证：T13（迁移后 JSON 不含 token、权限 0600）。

### F3【高｜数据丢失】全量不可解码配置：preserved-fallback 刚写入就被默认配置保存删掉

- 证据：`ConfigStore.swift:101-103`：`preservedFallbackData` 先 `preserveFallbackCandidateIfNeeded(...)`，下一行 `try save(defaultConfig)`；而 `save` 默认 `clearPreservedFallbackCandidate: true`（`:112-114,120-130`）→ `ConfigSnapshotWriter.swift:37-39` → `removePreservedFallbackCandidateIfPresent`（`:81-85`）。`ConfigStoreTests` 覆盖了 lossy 路径保留（`:261-331`）和恢复路径，但**没有**覆盖"所有快照 invalid 且无 last-known-good → 落默认配置"这一分支保留坏数据。
- 影响：用户 config.json 全量损坏（例如降级/枚举漂移/手改坏了）且无 last-known-good 时，唯一可人工恢复的原始 JSON 被删；`lastLoadWasLossy` 路径的"保留待新版恢复"设计在这里失效。
- 渐进建议：把 `save(defaultConfig)` 改为 `save(defaultConfig, updateLastKnownGood: true, clearPreservedFallbackCandidate: false)`，或把 preserve 调用移到 save 之后；若认为"落默认即完成恢复、无需保留"是刻意行为，请补一条 test 固定该语义并注释原因。
- 验证：T4。

### F4【中高｜重复+分叉】20 个 provider 各写一份 HTTP 状态校验；官方 429 丢 Retry-After，403 语义与 relay 双通道不一致

- 证据：
  - 重复：`grep -l "guard let http = response as? HTTPURLResponse" Providers/*.swift` = **20 个文件**（Amp/Claude/Codex/Copilot/Cursor/CursorSessionAuth/Gemini/GrokBot/Grok/KimiOfficial/Kimi/MicrosoftCopilot/MoonshotBalance/OllamaCloud/OpenCodeGo/OpenRouter/Qwen/Trae/Windsurf/Zai）。典型 15 行样板：`CodexProvider.swift:443-456`、`GeminiProvider.swift:589-605`、`ClaudeProvider.swift:330-343`、`CopilotProvider.swift:50-64`、`OpenRouterProvider.swift:48-68`。
  - 分叉 1（429）：全部 provider 只抛 `.rateLimited`，**没有任何一处解析 Retry-After**；而共享 `ProviderRateLimitError.parseRetryAfter`（`OhMyUsageProviders/ProviderError.swift:36-56`）只有 relay 在用（`RelayHTTPClient.swift:50-54,90-93`）。于是 `ProviderFetchPlanRegistry`/`AppProviderRefreshCoordinator` 对官方 provider 的限流只能按本地退避走，忽略服务端明确 deadline。
  - 分叉 2（403）：`RelayHTTPClient.requestJSON` 把 401/403 都当 unauthorized（`:40-48`），而 `RelayHTTPClient.request<T:Decodable>`（token 通道用）只处理 401，403 会落到 `invalidResponse("http 403")`（`:72-104`）→ token 通道因此不会触发浏览器恢复，balance 通道会；OpenRouter 又刻意把 403 当 management-key 提示（`OpenRouterProvider.swift:56-58`）。
  - 分叉 3（第四份实现）：`Services/OfficialProfileSnapshotRuntime.swift:11-57` 是"401/403→unauthorized、429→rateLimited、非 2xx→invalidResponse"的另一份拷贝；`OfficialProviderAuthRuntime.swift:38-64` 又是第三份（400/401、无 429 分类）。
- 影响：每新增一个 provider 都要复制 15 行并容易分叉；同一 token 通道/余额通道对同一站点错误分类不同，直接改变"是否尝试浏览器恢复"与 UI 文案；官方 429 的 `Retry-After` 被浪费。
- 渐进建议：在 `OhMyUsageProviders` 增加一个纯函数 `HTTPResponseValidation.validate(_:unauthorizedStatusCodes:rateLimitStatusCodes:errorMessageExtractor:) -> (Data, HTTPURLResponse)`，内部用 `ProviderRateLimitError.parseRetryAfter`；默认 `unauthorized=[401,403]`、`rateLimit=[429]`、`408/5xx→timeout`、可选 HTML 登录页识别（从 `RelayHTTPClient.looksLikeAuthenticationHTMLResponse` 移入）。先迁 Claude/Codex/Gemini/Relay 两个 executor（有测试网可回归），其余 provider 逐步替换；`OfficialProfileSnapshotRuntime` 直接委托它（两目标都在依赖链上）。
- 验证：T8（表驱动：401/403/429 秒数与 HTTP-date/408/500/HTML/JSON decode）。

### F5【中｜正确性/可观测】刷新的 refresh token 写回失败被静默吞掉；Claude/Codex 还手写了一份已有 runtime

- 证据：`OfficialProviderAuthRuntime.updateJSONObjectFile`（`:99-114`）全程 `try?`、返回 `Void`；调用方 `ClaudeProvider.swift:309-318`、`CodexProvider.swift:410-420` 也只"尽力而为"。`Data.write(options: .atomic)`（`:113`）失败时无任何日志（对比 `ConfigStore` 至少有 NSLog）。同时 vault 侧写入 `updateVaultAfterRefresh` 失败也是静默 early-return（`ClaudeProvider.swift:289-307`、`CodexProvider.swift:389-408`）。
- 影响：OAuth refresh token 可能轮换（服务端作废旧 refresh token）。若本次刷新成功、但新 token 因磁盘只读/配额/权限写盘失败，旧 token 已被服务端作废 → 下次启动 provider 永久 401，直到用户重新登录；用户/日志都拿不到线索。另外 `.atomic` 写 tmp 再 rename，**可能重置文件权限**（取决于 Foundation/APFS 行为，需实测；若 provider 凭据文件原本 0600，会变成默认 umask 权限）。
- 建议：`updateJSONObjectFile` 返回 `Bool`/`Result`，失败按"不含值"日志上报并在错误里给出 `re-auth required` 提示；写后校验可读；补文件权限保持测试。Claude/Codex 的预刷新+401 单次重试逻辑与 `OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh` 等价（见 `ClaudeProvider.swift:106-127`、`CodexProvider.swift:97-130`），可分两步迁移（先 Codex 后 Claude）以减少删除重复。
- 验证：T7。

### F6【中｜配置健壮性】AppConfig 没有 schemaVersion；枚举为严格 decode；无字段级降级

- 证据：`Models/AppConfigModels.swift:18-31`（字段里没有版本）、`:79-92`（CodingKeys 无 version）、`:168-182`（`decodeIfPresent(AppLanguage/ResourceMode/StatusBarAppearanceMode/StatusBarDisplayStyle)`——键存在但 rawValue 未知时 `decodeIfPresent` 会抛 `dataCorrupted` 而不是返回 nil）；`ProviderModels.swift:4`（`ProviderDescriptor` synthesized Codable，`family`/`type` 未知 raw 值也会失败，仅靠 `LossyProviderDescriptorArray` 丢单个 provider：`AppConfigModels.swift:94-120`）。
- 影响：新版加了枚举 case 后用户降级/回滚、或手改配置写错一个词，整份 config 判 invalid，逐级回退 backup/recovery（内容相同仍 invalid）→ last-known-good（可能很旧）→ 默认值。Provider 级别的 lossy 有诊断记录（good），但顶层 5 个枚举没有；且没有版本号就无法写"从 vN 到 vM"的有序迁移，只能靠 `AppConfigSiteDefaultsMigrator` 每次 load 全量猜。
- 建议：加 `"schemaVersion": Int?`（缺失=1）并对枚举做 `decodeIfPresentLenient`（`try?` 失败返回 nil 用默认值，同时把 `droppedTopLevelFields: [String]` 计入 diagnostics 与日志）；版本号只用于记录/前进迁移，不阻塞旧读。这是一次约 30 行的小改动，可单独 PR。
- 验证：T5。

### F7【中｜Relay 扩展性】新增中转站不是"只加 JSON"：8 个文件 ~45 处 adapter id 硬编码分支

- 证据（全为 `manifest.id ==/case` 分支）：
  - `Providers/RelayResponseInterpreter.swift:47-89`（deepseek 业务码、moonshot 二次探测、xiaomimimo 递归回退、minimax coding plan、sub2api postprocess）、`:268`、`:304`、`:430-443`、`:466-536`、`:611-618`；
  - `Providers/RelayBalanceChannelExecutor.swift:27-35,213-220,268-276,304-307,354-365,372-381,461-473`；
  - `Providers/RelayRequestResolver.swift:60-76`（5 个探针路径表，含 moonshot/xiaomimimo 超长 coalesce 表达式）；
  - `Providers/RelayCredentialResolver.swift:123-126,206-227,302-359`（moonshot cookie 判定、deepseek bearer+cookie 组合、xiaomimimo 补 userId）；
  - `Providers/RelayRecoveryPolicy.swift:143-188,199-241`（各站点登录过期文案）；
  - `Services/RelayAdapterRegistry.swift:115-172`（displayMode/诊断提示 switch）、`:420-505`（generic 兜底两份 Swift 副本）；
  - `Services/RelayProviderDescriptorResolver.swift:112-125`（站点 → 默认 keychain account 映射）；
  - `UI/Settings/SettingsRelayTemplateSupport.swift`（图标映射）。
- 边界：**纯 JSON 能覆盖**——单一 GET/JSON、标准 2xx/401/403/429 语义、表达式只用 `div/sum/add/coalesce/字面量`、`postprocessID` 命中现有两种。**必须改代码**——(a) 业务错误是 HTTP 200 + envelope code（deepseek/xiaomimimo）；(b) 一个站点要 ≥2 个请求联合计算（moonshot org、xiaomimimo token plan、minimax coding plan+balance 回退）；(c) 非 1:1 单位换算（moonshot `/100000` 形状嗅探、New API 的 quota→currency 需要额外 `/api/status` 请求）；(d) 认证需要拼 Cookie/特殊 header。
- 渐进建议（数据驱动化，先做收益最高的 3 个 manifest 字段）：
  1. `extract.valueScale: Double?`（moonshot 的 100000、未来 CNY/USD 缩放）→ 替换 `RelayResponseInterpreter.swift:491-499,585-593` 的硬编码；
  2. `probe.businessErrors: [{path, codes, messagePaths, classify}]`（deepseek 40002/40003、xiaomimimo envelope）→ 替换 `:289-310,430-443`；
  3. `balanceRequest.secondaryRequest`（path + mergeExpressions）→ 为 moonshot/xiaomimimo token plan 提供通用"两段式"模板；
  4. `postprocessID` 由 `String` enum 扩为"注册表 + 内置 id"（保留现 enum 兼容），降低再加一个站点就要改 enum 的成本。
- 验证：T10。

### F8【中｜正确性】Gemini 配额解析 clamp 不对称：负 utilization 会产生 remaining > 100、used < 0

- 证据：`GeminiProvider.swift:824-833`：
  `usedPercent: min(100, max(0, usedPercent))`（clamp 后存储）但 `remainingPercent: max(0, 100 - usedPercent)`（用的是**未 clamp** 的局部变量）。若 API/形状误判产生 `utilization = -0.5` → `parseUsedPercent` 返回 -50（`:836-841`）→ 存储 used=0、remaining=150；随后 `parseQuotaSnapshot` 用 `remaining = min(...)` 推导 `used: 100 - remaining`（`:686-702`）→ used=-50 进入 snapshot。
- 影响：菜单栏/详情出现 >100% 剩余或负 used；`status` 计算（`:698`）与告警阈值随之错。触发条件依赖异常 payload（防御性缺失），不是高频 bug。
- 建议：两处都用同一 clamp，或直接改用 domain 里已有的正确工厂 `UsageQuotaWindow.percent(...)`（`Domain/UsageQuotaWindow+Percent.swift:8-20`，它内部 `used = min(100,max(0,usedPercent))`），删掉手写窗口构造；顺手把 `parseUsedPercent` 的 `value <= 1 ? value*100 : value` 换成显式 `< 1` 并对 0 做说明（当前 `0` 走 `<=1` 仍是 0，无碍）。
- 验证：T6（utilization=-0.5、remainingFraction=-0.2、used/limit 溢出）。

### F9【中低｜确定性】`firstNestedValue` 依赖 Dictionary 遍历顺序：同一响应跨启动可能取到不同字段

- 证据：`OhMyUsageProviders/RelayJSONExpressionEvaluator.swift:158-180`：先查直接 key，再 `for value in dict.values { ... firstNestedValue ... }`。Swift `Dictionary` 的遍历顺序每个进程的 hash seed 不同，因此当 JSON 里有**多个嵌套分支含同名 key**（例如 `data.wallet.balance` 与 `data.bonus.balance`）时，命中哪个值不稳定。使用点：`RelayResponseInterpreter.swift:132-156`（firstNestedNumericValue）、`:626-650`；测试 `RelayJSONExpressionEvaluatorTests.swift:68-99` 只测单分支。
- 影响：同一站点余额在不同重启后可能显示不同数字（到底取钱包还是赠送金），且难复现；也会影响"哪个分支被当成账号名"。
- 建议：遍历 `dict.keys.sorted()`（或按表达式给定的 candidate 列表顺序递归）；顺序本身不是语义，但**确定性**对排障和 snapshot 对比很重要。改动 <10 行。
- 验证：T9（构造两个分支都含 `balance`，跑两次/多个表达式断言一致）。

### F10【低中｜Relay 语义】token 通道对空路径仍发请求；Relay 快照恒标 live/ok；改模板后缓存键不变

- 证据：
  - `RelayTokenChannelExecutor.swift:76-85`：`subscriptionPath ?? ""`、`billingUsagePath ?? ""` 直接传给 `relayURL`；`RelayRequestResolver.relayURL` 对空串返回 `baseURL.appending("/")`（`:89-93`）→ 每次 token 刷新都会额外打两次站点根路径（可能返回 HTML→`invalidResponse` 被 `try?` 吞掉），浪费请求且增加风控症状。
  - `RelayProvider.swift:229-247`：返回的 `UsageSnapshot` 恒定 `fetchHealth: .ok`、`valueFreshness: .live`，即便数据来自 120s 的 channel cache（`ProviderFetchPlanRegistry.swift:241-250` activeTTL=120）或浏览器恢复导入的旧 Cookie。
  - 缓存 key 只含 descriptor/baseURL/adapter/keychain 身份/凭证指纹（`RelayProvider.swift:292-328`），不含 `manualOverrides`/模板版本：用户在高级设置里改路径/表达式并保存后，最多 120s 内仍可能显示旧值（`persistAndRestart` → `restartPolling` 不是强制刷新）；force refresh 可绕过。
- 建议：`tokenRequest.subscriptionPath/billingUsagePath` 为 nil 时不发请求；`fetchHealth`/`valueFreshness` 从 channel 来源推导（缓存命中→`.cachedFallback`/`.ok`+`valueFreshness=.cached`，恢复成功可在 extras 标注）；在 `AppConfigurationModel.applyGenericProviderSettingsMutation`/`persistAndRestart` 中清 `RelayProvider` 两个 channel cache（加按 descriptorID 前缀失效接口即可）。
- 验证：T11。

### F11【低｜可维护】若干可收敛的小重复（本次不建议大改，只列清单）

- `Providers/WebOverlayRetryBackoff.swift:3-25`（public actor）与 `Providers/RelayRecoveryPolicy.swift:10-30`（private actor `BrowserRecoveryBackoff`）是同一逻辑两份；后者可直接复用前者（同 target 外可用 public 版本）。
- `RelayResponseInterpreter` 中 5 处几乎相同的 rawMeta 模板（`:102-109`、`:483-490`、`:576-584`、`:652-659`、`:871-878`）→ 抽 `makeRequestMeta(...)`。
- `RelayBalanceChannelExecutor` 三处 candidate 循环 + 同一错误分类 switch（`:279-346`、`:392-459`、`:481-524`）→ 抽 `firstCandidateSuccess` 泛型；`RelayTokenChannelExecutor.swift:63-144` 可共用。
- 两套 JSON 文件改写：`OfficialProviderAuthRuntime.updateJSONObjectFile`（原地读改写、`try?`）vs `OfficialProfileSnapshotRuntime.mutateJSONObjectString`（返回字符串、throws）——后者更可测，前者建议收敛为"mutate→返回值→调用方决定持久化"。
- `RelayAdapterRegistry.invalidateLocalManifestCache`（`:98-102`）在 Sources 中**无调用方**（死 API）；本地 manifest 只被 `availableManifests()` 用于 host 匹配，模板选择器只用 `builtInManifests()`（`UI/Settings/SettingsRelayTemplateSupport.swift:229-236`），所以"热加载自定义模板"实际只对自动 host 匹配生效，UI 里选不到、也没有 JSON 语法/字段校验与错误提示（`RelayAdapterRegistry.swift:196-204,317-323` 全是 `try?` 静默跳过）。
- 验证：无（纯结构），建议随 F4/F7 一起顺手做。

### F12【低｜配置迁移】无版本的增量 migrator + override 静默剥离：默认值漂移的风险面

- 证据：`Models/AppConfigSiteDefaultsMigrator.swift:5-62` 每次 load 全量跑迁移（删 legacy Kimi、删示例 relay、给缺失的默认 provider 补回、改默认顺序、改默认轮询 60→120）；`ProviderDescriptorNormalizer.swift:118-136` 在归一化时若 `looksLikeTemplateDefaultOverride`（`ProviderDescriptor+RelayOverrideMigration.swift:94-161`）就把用户保存的 `manualOverrides` 置 nil。
- 影响：a) 迁移不可版本化/不可回滚，默认值随版本变化会持续改写用户配置，出问题时无法判断"哪一版迁移干的"；b) 剥离逻辑把"用户显式保存、恰好等于当前模板默认值"的设置视为默认而丢弃——当前行为等价所以无害，但一旦模板默认值后续变动，用户原来显式钉住的值会被静默改变。c) `AppConfig.default.providers` 是隐式 schema，新增默认 provider 会自动出现（好在默认 `enabled:false`，如 `OfficialProviderDefaultCatalog.swift:6-18`），语义可接受但值得注释固定。
- 建议：给 `AppConfig` 加 schemaVersion（同 F6）后，把 migrator 拆成按版本递增的小迁移（`migrateV1toV2`…）并只对 `< current` 的配置执行；override 剥离逻辑保留，但只在"键缺失/为空"时补默认，不做"等于默认就删"——或记录 diagnostics 便于用户看到"高级设置被模板默认覆盖"。属于长期项，可与 F6 一起做最小版（仅版本字段 + 迁移函数签名）。
- 验证：T5 同一组用例可覆盖迁移幂等性（连续 load 两次配置不变）。

---

## 三、疑似 bug / 安全清单（按置信度）

| # | 位置 | 现象 | 置信度 | 关联 |
|---|---|---|---|---|
| B1 | `CodexDesktopAuthService.swift:51-53` + `AppViewModel.swift:289` + `AppCompositionFactory.swift:44` | 生产环境 Codex 档案写入使用独立 KeychainService，与共享 vault 并存 → 整快照覆盖丢凭证 | **高**（默认参数链可 100% 静态确认；是否真丢取决于写入交错） | F1 |
| B2 | `KeychainService.swift:160-183,185-204,460-476` | 并发 `saveToken/deleteToken` 用内存旧快照整份写回，非串行；删除可被并发保存"复活" | **高**（代码结构确定），触发需并发写 | F1 |
| B3 | `OfficialAccountProfileModels.swift:26,74` + 两个 profile store 的 `save` | access/refresh token 明文落 App Support JSON，无 0600 | **高** | F2 |
| B4 | `ConfigStore.swift:101-103` + `ConfigSnapshotWriter.swift:24-39,81-85` | 全量 invalid 场景 preserved-fallback 写后即删 | **高**（行为确定；是否有意需产品确认） | F3 |
| B5 | `GeminiProvider.swift:829-830,700` | 负 utilization → remaining 150%、used -50 | **高**（代码确定；输入是否出现取决于上游） | F8 |
| B6 | `RelayJSONExpressionEvaluator.swift:164-167` | 递归取值依赖 Dictionary 遍历顺序，跨进程不确定 | **高**（Swift 语义确定），影响低 | F9 |
| B7 | `OhMyUsageProviders/OfficialProviderAuthRuntime.swift:99-114` | 刷新 token 写盘失败静默；`.atomic` 可能改权限 | **中**（失败路径确定；权限行为需实测） | F5 |
| B8 | `RelayResponseInterpreter.swift:323-334` | `xiaomimimoBusinessCode` 回退把任意 `status` 当业务码：若 token-plan 响应只有 `status: 200`（无 `code`）而实际成功，会被判 `unauthorizedDetail`（登录过期） | **中**（取决于真实响应是否带 status 字段；建议只认 code，或 status 需配 `code==0` 语义白名单） | F7 |
| B9 | `RelayHTTPClient.swift:44-46` | 传输层硬编码 `xiaomimimo.com` 的登录过期文案（分层泄漏，新增站点无法只加 JSON） | **高**（设计问题），风险低 | F4/F7 |
| B10 | `RelayTokenChannelExecutor.swift:76-85` | 空 subscription/billing path 仍请求站点根；`try?` 静默 | **高**（浪费/症状增强），风险低 | F10 |

---

## 四、Relay 扩展性专节（"只加 JSON"能做到哪一步）

**新增一个"普通 New API 形态"站点：可以只加 1 个 JSON**（放 `Sources/OhMyUsage/Resources/RelayAdapters/`，`RelayAdapterRegistry.loadBundledManifests` 自动加载；host 匹配 + 模板选择器 + 默认 keychain account 走通用路径）。已内置的 `generic-newapi`/`generic-sub2api` 就是证据。

**其余情况需要改代码，最少 3 处、最多 8 个文件**（清单见 F7）。判断口诀：
- 响应是标准 HTTP 状态 + 单请求 + 表达式可表达 → JSON；
- 出现"HTTP 200 但 code≠0"、"两个接口拼一个值"、"需要额外换算/请求汇率"、"认证要拼 Cookie"任一 → 改代码，优先把该差异做成 manifest 字段（F7 建议），而不是再加一个 `if manifest.id ==`。

**表达式引擎边界**（`RelayJSONExpressionEvaluator.swift`）：
- 能力：`div/sum/add/coalesce`、路径 `a.b.0.c`、`*` 通配（仅 `values/sum`）、数字/字符串/布尔字面量、`coalesce` 字符串嵌套。**没有**乘/减/比较/条件/取整/单位字符串模板。
- 安全：纯内存 O(payload)，无网络/无超时概念；`JSONSerialization` 本身有嵌套上限，深递归风险低；但**无深度/长度限制**（本地用户提供的 adapter JSON 可构造超深表达式，最坏是栈；建议加 `maxExpressionLength`/`maxDepth` 常量，成本几行）。
- 错误定位：缺失时错误为 `missing remaining path <expr>`（`RelayResponseInterpreter.swift:91-93`），可定位到表达式原文，尚可；但表达式**语法错误**（如 `div(a,b`、`sum(`）不会在加载期报错，只在抓取时报"missing remaining path div(a,b"——建议 manifest 加载时做一次静态校验：括号配平、已知函数名、路径非空，把错误推到"站点设置"保存时。
- 模板校验（仍缺）：`RelayAdapterRegistry.loadLocalManifests/loadBundledManifests` 对 decode 失败一律 `try? continue`（`:196-204,317-323`），坏 JSON 无提示；bundle 里的模板没有测试覆盖"每个内置 JSON 都满足 requiredInputs/authStrategies/表达式非空"的一致性约束。建议加一个 `RelayAdapterManifest.validate() -> [String]`，在 registry 里记录/汇总，设置页 Test Connection 前可展示。

---

## 五、配置专节（schema/版本/迁移/降级/默认值）

- **现状**：无 schema version（F6）；损坏降级链路完整且测试好（F3 有一个顺序 bug）；迁移是无版本、幂等目标的全量 normalizer（F12）；`ConfigStore.save` 同步写 4 个文件（primary/backup/recovery/last-known-good，`ConfigSnapshotWriter.swift:24-40`），每次写前 `encode`、写 LKG 前再 `decode` 校验 lossy（`:67-79`），没有 fsync（.atomic rename 已经够用，崩溃最多丢最后一次保存，可接受）。
- **损坏降级行为**（默认路径）：primary invalid → backup → recovery → last-known-good，任一可用即 `save` 回写主快照；全 invalid → 官方 profile/slot 推断恢复 → 默认配置（F3 的保留 bug）。`ConfigRecoveryPolicy.swift:21-71` 只恢复 codex/claude 两个官方 provider 的 enabled 状态，其余信息确实无从恢复，可接受。
- **并发写**：`AppConfigurationMutationCoordinator` 是 `@MainActor`，`persistConfiguration` 同步调用，配置写不存在 out-of-order；provider snapshot 缓存是 actor/Bounded LRU，OK（不在本报告展开）。
- **默认值漂移**：`AppConfig.default` 是隐式 schema，`migratedSiteDefaults` 有意只补"站点默认"、不覆盖用户阈值（`AppConfigSiteDefaultsMigrator.swift:17-24,181-262`）；新增默认 provider 默认 `enabled:false`（`OfficialProviderDefaultCatalog.swift:6-18`）不会替用户打开。需要注释/测试固定"用户显式值优先"的规则（已有部分测试：`AppConfigTests.swift:696` 自定义 interval 不被改）。
- 建议优先做：schemaVersion（F6）→ F3 顺序修复 → 迁移函数按版本切分（F12 可选）。三者都不影响功能面，可以单 PR 完成。

---

## 六、建议补的 focused tests 清单

按"能抓住已发现 bug/回归"排序（现有 39 个相关测试文件已覆盖大量解析/缓存/恢复，以下为缺口）：

1. **T1 KeychainService 并发保存**：两个不同 account 并发 `saveToken` 100 轮 → 磁盘/vault 二者都在；`deleteToken` 与 `saveToken` 交错 → 删除项不被复活。用现有 `SecureStoreAdapter` 注入内存实现即可（`KeychainServiceTests.swift` 已有测试设施）。
2. **T2 双 KeychainService 实例**：共用同一 storageURL/adapter 构造两个实例，A 写 key1，B（先读过旧 vault）写 key2 → 断言 key1 仍在（当前预期会失败，作为 F1 回归锚点）。
3. **T3 组合根不变量**：`AppCompositionFactory.makeDependencyGraph` 后断言 `graph.codexDesktopAuthService` 与 `graph.credentialBroker` 使用同一 KeychainService/vault（需暴露 identity 或注入 spy broker）；生产 `AppViewModel()` 也覆盖。
4. **T4 配置全量损坏**：primary/backup/recovery 都非 JSON、无 LKG、无 profile 状态 → `load()` 后 `config.preserved-fallback-candidate.json` 必须存在且内容等于损坏原始数据（当前会失败）。
5. **T5 配置 schema 防御**：手写 JSON 把 `statusBarDisplayStyle`/`resourceMode`/某 provider `family` 改成未知字符串 → 期望：顶层字段回落默认且其余 provider 保留（当前整份 invalid）。做 F6 前先写"现状文档测试"亦可。
6. **T6 Gemini 越界百分比**：`utilization=-0.5`、`remainingFraction=-0.2`、`utilization=150` → 断言窗口 0…100、`snapshot.used` 0…100（当前 -0.5 会产出 used=-50/remaining=150）。
7. **T7 刷新 token 写盘失败**：`updateJSONObjectFile` 指向只读路径/只读文件 → 返回失败、保留旧文件不损坏；成功路径断言文件权限保持 0600（若 F5 落地返回 Result）。
8. **T8 统一 HTTP 校验表驱动**：401/403/429(秒/HTTP-date/非法)/408/500/HTML/非法 JSON × 各 provider 的 unauthorized 集合差异（OpenRouter 403 特例）→ 断言错误分类与 Retry-After deadline。
9. **T9 Relay 表达式确定性/边界**：同一响应含两个同名嵌套 key 连续求值结果一致；`div(`/`sum(` 未闭合、超长表达式、1000 层嵌套 → 不崩溃、返回 nil 或明确错误。
10. **T10 manifest 数据驱动**：任意 `valueScale`/`businessErrors`/`secondaryRequest` JSON（不写 Swift）→ 断言解释器产生与 deepseek/moonshot 特判一致的结果；再断言"内置 10 个 JSON 全部通过 `validate()`"。
11. **T11 token 通道请求预算**：`subscriptionPath/billingUsagePath == nil` → 只允许 1 次 usage 请求；非 nil → 3 次；断言 URL 不落在站点根。
12. **T12 Relay 恢复/缓存退化**：balance 通道返回 403 → 触发一次浏览器恢复（与 token 通道对齐）；改 `manualOverrides` 后第二次 fetch 不再命中旧缓存；缓存命中时 `valueFreshness != .live`（F10 落地后）。
13. **T13 Profile 凭证明文迁移**：迁移后 `claude_profiles.json`/`codex_profiles.json` 不含 token、文件权限 0600；vault 中有对应 slot 的凭证；迁移失败时旧文件保持可读（F2 落地后）。
14. **T14 xiaomimimo token plan `status` 语义**：只有 `status:200` 无 `code` 的成功响应不应被当登录过期（B8）。

---

## 七、如果只做 3 件事

1. **把"凭证写入"收敛成单写者、串行化、可迁移**（F1+F2）：`KeychainService` 进程单例 + vault 持久化串行合并；修组合根让 Codex 档案服务复用共享 vault；把两个 profile JSON 里的 token 迁入 vault 并收紧权限。这是唯一会**静默丢用户凭证**的一类问题，优先级最高，且改动集中（~2 个文件 + 1 个组合根 + 1 个迁移函数）。
2. **抽官方 HTTP 响应校验 runtime 并统一错误分类**（F4+F5 的传输部分）：一个 20 行的 `HTTPResponseValidation`（含 `Retry-After`、408/5xx→timeout、取消映射、可选 HTML 登录页识别、可配 403 策略），先迁 Claude/Codex/Gemini 与 `RelayHTTPClient.request`，让 Relay token/balance 通道对 401/403 行为一致；再逐 provider 替换样板。既删 ~400–600 行重复，又补上官方 provider 现在完全丢失的限流 deadline。
3. **配置/模板防御性小修 + 回归测试**（F3+F6，可选 F7 的 `valueScale/businessError` 两个数据字段）：修 preserved-fallback 写后即删；加 `schemaVersion` + 枚举字段级降级；为内置 relay JSON 加 `validate()` 与两个数据化字段，让下一次"加站点"尽量少写 `if manifest.id ==`。全部无 UI/行为回归风险，适合作为下一个独立 PR。

---

## 附：审查方法说明与限制

- 所有结论基于静态阅读 2026-10-17 工作区中的源码；未执行构建/测试，因此"行为确定"指控制流可静态确认，涉及 Foundation/Keychain 系统行为（如 `.atomic` 是否保留权限、`URL(string:)` 对非法字符的处理）的条目已在文中标注需实测。
- 未修改源码、未执行 git 操作、未运行 `swift build/test`；唯一写入为本文件。
- 相关但不属本次重点、建议由其他审查线确认：`OAuthImportOrchestrator` 的登录检测轮询（844 行，本次仅检查了凭证落点）、`AppUpdateService` 下载/重试、以及 `ClaudeAccountProfileStore` 981 行里的账户匹配/压缩启发式（本报告只覆盖其凭证持久化面）。
