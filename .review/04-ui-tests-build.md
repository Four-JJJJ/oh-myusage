# 审查报告 D：UI 层 / 测试套件 / 构建·CI·发布工程化

- 仓库：`/Users/fourj/Desktop/Vibe Coding/oh-myusage`（`main`，HEAD `947d454 release: 2.5.4 cache correctness and refresh reliability`）
- 版本：`VERSION=2.5.4`，最新 tag `v2.5.4`（当前无版本漂移）；Package tools 6.2，平台 macOS 14+
- 审查方式：只读静态分析 + 计数（未运行 `swift build` / `swift test`，由 Lead 统一执行；46s 全量耗时与 15.28s clean build 来自任务输入/Lead 实测）
- 工作树现状：7 个已修改 + 2 个未跟踪文件（official category 拆分 `OfficialSettingsCategory.swift`、`OfficialSettingsCategoryTests.swift`），按现状审查
- 报告路径：`.review/04-ui-tests-build.md`（本文件为本次唯一写入）

---

## 0. 摘要

一句话结论：**工程骨架（8 target、release manifest 校验、Keychain 注入式测试）不差，但"门禁"和"边界"两件事没做透**——构建不可复现（iCloud xattr）、CI 只有 build+test、UI 展示层没有真正的类型边界（`SettingsView` 被 21 个文件扩展）、架构约束靠扫描源码字符串维持。收益最高的是 F1（半天内可让所有开发机/CI 构建可重复）、F10（CI 门禁，避免 release 才发现 release 配置编译错误）、F2（Settings 上帝类型拆分，释放后续 UI 迭代速度）。

### 0.1 数字概览（本次实测）

| 指标 | 数值 |
|---|---|
| Swift target | 8 个（app `OhMyUsage` + 7 个库 target） |
| Sources 文件 / 行 | 352 / 77,073；其中 app target 71,539 行（**92.8%** 仍在一个 target） |
| UI 层 | UI 根 7 文件 1,482 行 + Support 4 文件 120 行 + Presenters 20 文件 3,333 行 + Settings 53 文件 15,729 行 = **84 文件 / 20,664 行**（占 app target 28.9%） |
| `OhMyUsagePresentation` target | 6 文件 361 行（与 UI/Presenters 3,333 行的职责漂移） |
| 测试 | 163 个 `.swift` 文件 / 49,269 行 / 1,344 个 test 方法 / 163 个 XCTestCase class / 0 个 swift-testing |
| 测试全局态 | 45 个文件 `@MainActor`、155/163 文件 `@testable import OhMyUsage`、26 处 setUp/tearDown |
| SettingsView 扩展 | **21 个文件** 对 `struct SettingsView` 做 extension；85 个 `-> some View` 构建函数 |
| 源码扫描式测试 | 46 个明确断言集中在 4 个文件（另有约 5 个混在其他文件），112 处引用 `Sources/` 路径 |
| 本地化 | `L10nKey` 223 个键 / `Localization.swift` 754 行；同时 368 处内联 `localizedText(zh,en)`、182 处 `.text(.key)`、103 处 `language == .zhHans` 三元 |
| CI | `.github/workflows/ci.yml` 仅 **26 行**（checkout/setup/build/test） |
| 发布 | `release.yml` 328 行、`package_dmg.sh` 545 行、`RELEASE_CHECKLIST.md` 手动清单 |

### 0.2 事实校正（相对任务描述）

- 测试文件数是 **163**（`find Tests -name '*.swift' | wc -l`），不是 192；1,344 个 test 方法与任务一致（`grep -rhoE 'func test[A-Za-z0-9_]+' Tests | wc -l` = 1344）。
- `Sources/OhMyUsage/UI` 根目录确为 7 文件 1,482 行（`wc -l Sources/OhMyUsage/UI/*.swift`），加 Support 4 文件 120 行。
- 工作树 refactor 不是"新增一个文件"：`git diff --stat` = 7 文件 +371/−154，另新增 2 文件；核心是把 official 分类逻辑抽成 `OfficialSettingsCategory` + 3 个纯 presenter 并补 10 个单测（见 §1-F2 的正面评价）。

### 0.3 已经做得好、不应回退的部分

1. **release manifest 流水线**：`latest.json` 生成后立即用 python 校验 version/url/sha256/size（`release.yml:125-169`），发布后还轮询两个 endpoint 验证（`release.yml:280-327`）——比多数同类项目扎实。
2. **凭证/Keychain 测试注入**：`KeychainService(storageURL:)` 注入临时文件（`TestKeychainHelpers.swift:6-12`），不碰真实钥匙串；网络测试 20 个文件使用 `URLProtocol` stub。
3. **AppKit 设置窗口方案本身**：`SettingsWindowController` 统一持有窗口（复用实例，`window`/`hostingController` 只创建一次），避免 SwiftUI `Settings` 场景空白窗口——方向正确（但残留守卫代码是死重，见 F3）。
4. **不伪造公证状态**：`package_dmg.sh:469-478, 540-544` 明确区分 developer-id / self-signed / ad-hoc，未公证时明确说 "NOT notarized"。
5. **工作树重构方向正确**：把分类判断、显示名、重排映射抽成 `OfficialSettingsCategory`/`OfficialSettingsCategory.providers(in:)`/`SettingsProviderSidebarPresenter`/`SettingsProviderReorderPresenter` 纯函数，并补了 10 个单测（`OfficialSettingsCategoryTests.swift`）——这正是 F2 建议的"抽 presenter/纯函数"路线的第一刀，应继续而不是推翻。
6. **菜单面板几何**：`MenuPanelGeometryResolver`（44 行纯函数）+ `MenuPanelGeometryResolverTests`，多屏/可见区域夹取逻辑清晰，无需重做。

---

## 1. 发现（按 收益/成本 排序，最多 12 条）

### F1（收益 高 / 成本 低）构建不可重复：iCloud file-provider xattr 污染 `.build`，codesign 报 detritus
**根因链**（证据来自本机产物，非猜测）：
1. 仓库位于 `~/Desktop/Vibe Coding/...`（macOS Desktop 属于 iCloud「桌面与文档」同步范围）。构建产物被 file provider 打上属性：
   ```
   $ xattr ".build/out/Products/Debug/OhMyUsage_OhMyUsage.bundle"
   com.apple.FinderInfo,com.apple.fileprovider.fpfs#P,com.apple.provenance
   $ xattr ".build/xcode/Build/Products/Release/OhMyUsage_OhMyUsage.bundle"
   com.apple.FinderInfo,com.apple.fileprovider.fpfs#P,com.apple.provenance
   $ find .build -name .DS_Store
   .build/.DS_Store  .build/out/.DS_Store  .build/out/Intermediates.noindex/.../.DS_Store
   ```
2. SwiftPM 在 `.build/out/Products/.../OhMyUsage_OhMyUsage.bundle` 上执行 codesign；`com.apple.FinderInfo` 会触发 codesign 的 "resource fork, Finder information, or similar detritus not allowed"。
3. 用 `/tmp/...` scratch path（不在 file provider 域内）全新构建通过（Lead 实测 15.28s），与本根因一致。
4. 恶化因素：同一个 `.build` 里同时存在 **Swift Build 布局**（`.build/out/`、`.build/.buildSystem_debug` 内容为 `swiftbuild`）与 **Xcode DerivedData**（`.build/xcode/Build/...`，来自 `-derivedDataPath .build/xcode`）；`Sources/OhMyUsage/Resources/*.svg` 只有 `com.apple.provenance`（无害，不是污染源）。
5. `package_dmg.sh` 也直接 `swift build`（`:393`）用仓库内 `.build`，只在构建前清理**源码**资源目录 xattr（`:388-390`），覆盖不到 `.build`，因此打包路径同样会踩。

**建议**（不要把"换机器/换目录"当唯一解）：
1. 新增 `scripts/build.sh`（或 Makefile）统一入口：
   ```bash
   SCRATCH="${OMU_SCRATCH_PATH:-$HOME/Library/Caches/oh-myusage/build}"
   swift build --scratch-path "$SCRATCH" "$@"
   ```
   `swift test` 同理；CI/本地文档统一改用它。
2. `package_dmg.sh` 增加 `--scratch-path` 并使用 `swift build --show-bin-path` 定位产物，替换 `resolve_binary_path` 的"4 个候选路径按 mtime 猜"（`:161-191`，可能选到 Xcode/旧布局产物）。
3. 一次性修复：`xattr -cr .build`（生成目录，安全）或直接删 `.build`；同时把 `.build` 与仓库加入 iCloud 排除（或不把仓库放同步目录）。
4. 文档化到 `AGENTS.md`/`README` 的 troubleshooting；CI 不受影响但顺带加 `swift build -c release`（见 F10）。

**验证**：`./scripts/build.sh` 成功后 `xattr -l "$(swift build --show-bin-path --scratch-path ...)/OhMyUsage_OhMyUsage.bundle"` 不含 FinderInfo；`codesign --verify --deep --strict` 通过；删除 `.build` 后重复两次构建均通过。

---

### F2（收益 高 / 成本 中高）`SettingsView` 是上帝类型：21 个文件扩展、85 个 view builder、同一文件里 3 套 sidebar
**证据**：
- `Sources/OhMyUsage/UI/SettingsView.swift:7-26`：一个 `struct SettingsView` 持有 10 个 `@State` + 4 个 `@FocusState`，并内嵌 3 个类型；本身只有 144 行，但**全部实现散在 21 个 `extension SettingsView` 文件**里（`grep -rln 'extension SettingsView' Sources — 21 个文件`，含 `UI/Presenters/RelayCredentialTemplatePresenter.swift`）。
- `SettingsProviderSidebar.swift` 1,675 行/90+ 成员/25 个 `-> some View`，且同时包含 **3 条并行 sidebar 实现**：`relayProvidersSidebar`（:8）、`officialSubscriptionsSidebar`（:648）、`sidebar()`（:1153）+ `thirdPartySidebarContent`（:1214）+ `officialSidebarContent`（:1253）+ `providerSidebarList`（:1261）——行渲染/选中/重排逻辑重复。
- 其它巨型文件：`SettingsRelayConfigurationForm` 1,305、`SettingsLocalUsageTrend` 1,260、`SettingsQuotaDisplayHelpers` 777、`SettingsOfficialProviderConfiguration` 748、`UsageAnalyticsSettingsView` 731。
- 状态爆炸半径大：`SettingsViewShell.swift:5-55` 的 body 挂了 8 个 `.onChange` + 1 个 `.onReceive`；其中 7 个 handler 都调用 `clearRelayTestResults()`。SettingsView 任一 `@State`（如 `relayEditorDraft` 每次键入）变化都会重算整个 settings 树（body + 全部 computed var），无法做到"改一个输入框只重绘一个 pane"。
- 工作树重构已抽出 `OfficialSettingsCategory`（44 行）+ 3 个纯 presenter（`SettingsProviderConfigurationPresentation.swift` +24 行），但仍把纯逻辑放在 UI target（`OhMyUsagePresentation` 才是现成的宿主），且 sidebar 文件本体仍 1,675 行（HEAD 1,613 → +82/−20）。

**建议（具体拆哪个 view / 抽哪个 presenter）**：
1. **Unify sidebar**：新建 `SettingsSidebarView`（独立 struct，输入 `@Bindable navigation` + `[ProviderDescriptor]` + `OfficialSettingsCategory`），替换 `relayProvidersSidebar`/`officialSubscriptionsSidebar`/`sidebar()` 三条路径；行视图抽 `ProviderSidebarRowView`（复用 official/relay 两种行内容）。目标：`SettingsProviderSidebar.swift` 1,675 → ~450 行（跨 3 文件）。
2. **每个 pane 独立 struct + 独立 `@Observable` 状态**：`RelayConfigurationPane`、`OfficialProviderPane`、`ProviderDetailPane`、`LocalUsageTrendPane`，把 draft 状态从 `SettingsView.@State` 上移/下沉到 `RelayConfigurationDraftModel`/`OfficialProviderDraftModel`（现有 `SettingsDraftModels` 已具备数据形态，只需加 Observable 容器）。收益：键入只重绘单 pane。
3. **抽 presenter**：`SettingsQuotaDisplayHelpers`（777 行）→ `SettingsQuotaPresenter` 纯函数（输入 quota window/snapshot/language → 输出展示值结构），放到 `UI/Settings/Presenters/` 或 `OhMyUsagePresentation`；`SettingsProviderSidebarPresenter`/`SettingsProviderReorderPresenter` 继续沿用到新 sidebar。
4. `SettingsView` 收敛为 ~100 行组装根：category → pane 的 switch。
5. 注意 `SettingsViewWindowController` 每次 `show()` 重建 rootView（`SettingsWindowController.swift:119-136`）会重置 pane 状态：拆 pane 时把"每次打开回到概览"作为明确行为写注释，避免误以为是 bug。

**验证**：临时加 `#if DEBUG` 的 `Self._printChanges()` 观察键入时 body 重算次数；VoiceOver 走查；`swift test --filter Settings`；视觉快照 zh/en 两套无回归。

---

### F3（收益 中高 / 成本 低）设置窗口生命周期与外观：一个常驻 0.75s Timer + 44 处死代码
**证据 1（幽灵窗口守卫已成死重）**：
- `OhMyUsageApp.swift:1-10` 明确写 "The app deliberately has NO SwiftUI `Settings` scene … that phantom cannot exist."
- 但 `RuntimeGuards.swift:78` 无条件 `SettingsScenePhantomWindowGuard.shared.start()`；该 guard 注册 3 个通知观察者并创建 **`Timer(timeInterval: 0.75, repeats: true)` 全生命周期轮询**（`SettingsScenePhantomWindowGuard.swift:20, 64-71`），每 tick 扫 `NSApp.windows`。
- `SettingsWindowController.show()` 另外安排 4 次 sweep（`SettingsWindowController.swift:100` → `SettingsSceneWindowPolicy.swift:9` = `[0, 0.3, 1.0, 2.5]`）。
- 结论：两条路径必有一条是错的——若 `OhMyUsageApp` 注释成立，guard 是纯耗电（菜单栏常驻 App 每 0.75s 唤醒一次）；若不成立，注释与架构不一致。**建议删除 phantom guard/policy 及其测试**（`SettingsScenePhantomWindowGuardTests.swift` 仅 1 个断言为 `XCTAssertTrue(true)`，见 F8），保留 `SettingsWindowController` 单窗口复用即可。
- **验证**：删除后在真机反复开关设置窗、切换激活策略，`NSApp.windows.count` 不增长；Activity Monitor/PowerLog 观察空闲唤醒下降。

**证据 2（浅色/跟随壁纸是未接线的死代码）**：
- `SettingsViewTheme.swift:219-221`：`var settingsUsesLightAppearance: Bool { false }` —— 硬编码；被 6 个文件共 **44 处**引用（`SettingsViewTheme` 28、`SettingsOfficialProfileManagement` 6、`SettingsProfileDialogs` 4、`SettingsGeneralAndMenuBarSections` 3、`SettingsProviderSidebar` 2、`SettingsLocalUsageTrend` 1）。
- `SettingsWindowAppearanceController`（58 行，壁纸亮度采样 + 浅色判定 + 应用）**只被自己的测试引用**：`grep -rn 'SettingsWindowAppearanceController' Sources` 仅命中定义文件；生产侧 `SettingsWindowController.swift:54,153` 两次硬编码 `usesLightAppearance: false`。
- 菜单面板则硬编码深色：`MenuPanelController.swift:84` `panel.appearance = NSAppearance(named: .vibrantDark)`。
- 结论：实际 App 是 dark-only，但设置页留了整套（可观的）浅色分支 + 一个未接线的外观控制器 + 其测试。**建议二选一**：(a) 接线：`SettingsWindowController` 注入 `SettingsWindowAppearanceController`，用 `statusBarAppearanceMode` + 壁纸亮度解析 `usesLightAppearance`，通过 `.environment(\.settingsUsesLightAppearance)` 传给视图（需对比度 QA）；(b) 删除死分支 + 控制器 + 对应测试，README 明示 dark-only。成本考虑建议先 (b)，(a) 作为独立特性排期。

**证据 3（窗口装饰脆弱点）**：
- 手工重排系统红绿灯按钮（`SettingsWindowController.swift:169-193`），仅 `windowDidResize` 时重排，且强制 `zoom.isEnabled = true`；`clearSettingsInputFocus`（:165-167）在打开时 `makeFirstResponder(nil)`（VoiceOver/Switch Control 焦点落空）。
- **建议**：如非设计硬需求，删除自定义红绿灯布局，用系统默认或 `titlebarAccessory`；保留 `isMovableByWindowBackground = false` 等已有正确设置。

---

### F4（收益 中高 / 成本 中）本地化：一个 731 行的设置页 100% 硬编码中文 + 三套并行的本地化写法
**证据 1（用户可见缺陷）**：`UsageAnalyticsSettingsView.swift`（731 行）全文件 **0 处** `localizedText`/`viewModel.text`/`language`（`grep -c` 均为 0），但它是可达页面：`SettingsViewShell.swift:256` 的 `usageAnalytics` tab 分支直接渲染它。英文用户会看到中文："总览"（:83）、"总使用趋势"（:93）、"供应商/模型/全部/近24小时"（:232-255）、"总请求/总Token/输入/输出/缓存命中/缓存写入/缓存率/成功率"（:265-275）、"暂无匹配的使用数据"（:611）、`dateFormat = "M月"`（:721）。同文件还有 5 处每次调用新建 `NumberFormatter`/`DateFormatter`（:663,669,677,685,713）。

**证据 2（漏网硬编码）**：
- `"加油包"` 作为 placeholder 指标标题：`SettingsQuotaDisplayHelpers.swift:351`、`MenuQuotaPresenter.swift:259`（英文界面也会出现）；`QwenProvider.swift:527` 的 quota window title 同样是中文常量。
- 其余抽查为双语（`MenuSubtitlePresenter.swift:49-53`、`SettingsRelayRuntimeStatus.swift` 等均为 zh/en 双分支），未发现更多硬编码句。

**证据 3（双轨/三轨制）**：
- `L10nKey` 223 cases + `Localization.text(_:language:)`（`Localization.swift:732` 起 754 行文件）；
- UI 层同时存在：`.text(.key)` 182 处/20 文件、内联 `localizedText("中文","English")` 368 处/23 文件、`language == .zhHans` 三元 103 处/22 文件。
- 风险：新增文案没有唯一入口；`L10nKey` 与内联双语会长期分叉；无法用一条 grep 保证"无中文漏网"。

**建议**：
1. 先修 `UsageAnalyticsSettingsView`：抽 `UsageAnalyticsPresenter`（把标题/列名/空态文案与格式化集中），沿用 `viewModel.localizedText(zh,en)`；该文件是自包含的，1 个 PR 可完成。
2. 修 `"加油包"` 两处 + `QwenProvider:527`（provider 侧需要 language 或返回 key 由 presenter 渲染）。
3. 冻结 `L10nKey`（不再新增），新文案统一 `localizedText(zh,en)`；为旧 key 逐步迁移。
4. CI 加一条 grep 门禁（成本 0.1 人日）：扫描 `Sources/OhMyUsage/UI/**/*.swift` 中含 CJK 的字符串字面量行，若前后 3 行内无 `localizedText(` / `zhHans` / `switch language` / `localized(` 则失败（本次用该启发式只命中 4 处真问题，误报可接受；脚本放 `scripts/check_localization.sh`）。
5. `dateFormat = "M月"` 改为按 language 选择 format。

**验证**：`.en` 下打开 Settings → 使用统计，全英文；grep 门禁为空；新增快照测试 zh/en 各 1 张。

---

### F5（收益 中 / 成本 中）展示层职责：`UI/Presenters`（3,333 行）留在 app target，`OhMyUsagePresentation`（361 行）空转；presenter 直接依赖 SwiftUI `Color`
**证据**：
- `OhMyUsagePresentation` 只有 6 文件/361 行（`MenuPermissionGuidePresentation.swift` 237 里最大），而 `UI/Presenters` 20 文件/3,333 行：`MenuQuotaPresenter` 706、`MenuDashboardStateBuilder` 482、`StatusBarDisplayPresenter` 274、`LocalUsageTrendPresenter` 244 等。
- `RelayStatusPresenter.swift:1-8`：`import SwiftUI` + `struct RelayDisplayStatus { var text: String; var color: Color }`——presenter 输出绑定 SwiftUI，无法在轻量测试 target 里测（必须编译 app 模块）。
- `SettingsQuotaDisplayHelpers`（777 行）本质是 settings 的 presenter，却放在 `UI/Settings/` 且以 `extension SettingsView` 形式组织，纯计算与视图 helper 混在一个 extension 里。
- 已有正向基础：presenter 单测已经存在且快（`SettingsViewQuotaDisplayTests` 14、`MenuQuotaPresenterTests`、`StatusBarDisplayPresenterTests` 等），说明拆分可测性已被验证。

**建议**：
1. 把纯展示计算迁到 `OhMyUsagePresentation`（已依赖 Domain）：`StatusBarDisplayPresenter`、`MenuQuotaPresenter`、`MenuDashboardStateBuilder`、`LocalUsageTrendPresenter`（要为其补充 Presentation 内部值类型，别把 UI 模型反向依赖）。
2. presenter 输出用语义枚举（如 `Tone { positive, warning, danger, neutral }`）替代 `Color`，UI 侧做 `Tone → Color` 映射；`RelayStatusPresenter` 是唯一违反者，先改它。
3. `SettingsQuotaDisplayHelpers` 拆成 `SettingsQuotaPresenter`（纯函数，进 Presentation）+ `SettingsQuotaViews`（UI）。
4. 建 `Tests/OhMyUsagePresentationTests`（新 test target，只依赖 Presentation）承接迁移后的 presenter 测试；这是 F6/F7 提速的前提之一。

**验证**：新 target 的测试在 5s 内跑完；`swift test --filter OhMyUsagePresentationTests` 不需要编译 71.5k 行 app target；app 行为不变（现有 presenter 测试全部保留通过）。

---

### F6（收益 中高 / 成本 中）源码扫描式架构测试：46+ 个测试读 `Sources/**` 字符串断言，依赖 cwd、按行数预算，脆弱且可规避
**证据**：
- 明确扫描源码的测试方法：`MonolithRetirementBoundaryTests` 30 个、`ArchitectureTargetBoundaryTests` 12 个、`UIFileDecompositionBoundaryTests` 3 个、`ArchitectureBoundaryTests` 1 个 = **46 个**；另有 ~5 个混在 `ProviderDefinitionRegistryTests`（3 处 `currentDirectoryPath`）、`AppConfigRelayCompatibilityTests`（1）、`OptimizationPresentationTests`（1）。
- 依赖工作目录：8 个文件、48 处 `URL(fileURLWithPath: FileManager.default.currentDirectoryPath)`（如 `ArchitectureTestSupport.swift:30`、`MonolithRetirementBoundaryTests.swift:15`）。`swift test` 从包根跑没问题，但 Xcode/IDE/derived-data cwd 下会直接 `try String(contentsOf:)` 抛错，整套 suite 失败且报错信息与真实原因无关；没有 `XCTSkip` 兜底。
- 典型脆弱断言：
  - `ArchitectureBoundaryTests.swift:15-18`：`XCTAssertFalse(source.contains("switch provider.type") || source.contains("switch type"))` —— 注释里出现该字符串即误报；改名/换写法合理重构也会误报。
  - `UIFileDecompositionBoundaryTests.swift:12-14`：`sharedHelpersLineCount <= 460`；`:97-99`：`menuContentLineCount <= 620` —— 行数预算把"拆文件"变成格式游戏，注释/空行都会触发。
  - `MonolithRetirementBoundaryTests.swift:34-40`：按类型名断言 `enum UpdateDisplayTone` 等不存在于 `AppViewModel.swift`；`:679`：`source.contains("RelayAdapterRegistry.shared")`。
  - `SettingsScenePhantomWindowGuardTests.swift:111-115`：断言 `sweepDelays == [0,...]` 这种实现常量（与行为无关）。
- 为什么该换：目标级依赖方向 Package.swift 已能表达且由编译器强制；这些测试实际在补"app target 太大、没有类型边界"的洞。它们占单元 suite 3.8%（51/1344），却制造 cwd 依赖与格式摩擦。

**建议（用编译期/target 结构替代字符串扫描）**：
1. **让编译器接管**：把 UI 拆成库 target（`OhMyUsageUI` 或按 feature 拆），Extension/type 的跨层引用就编译不过；`Package.swift` 的 target dependencies 已能表达 Domain ← Application ← Presentation ← Features ← Bootstrap/UI 的层次。先做最小步：`OhMyUsagePresentation` 承接 presenter（F5），`OhMyUsageFeatures` 承接组装逻辑；app target 只留 `OhMyUsageApp.swift`/`App/` 胶水。之后 `ArchitectureTargetBoundaryTests` 的 12 个测试大部分可删。
2. **保留的语义规则移到 CI 脚本**：`scripts/check_architecture.sh`（ripgrep）只断言少量稳定规则（如 Presenters 不得引用 `AppViewModel`、Providers 不得 import AppKit/SwiftUI），输出可读失败信息；不进 46s 的单元 suite（或只保留 1 个 entry test 调脚本）。
3. **根目录解析改造**（若短期保留测试）：统一用 `#filePath` 派生仓库根（现成范例：`ConfigStoreTests.swift:804` `fixtureData(_:filePath: #filePath)`），并对"repo root 不存在"`throw XCTSkip`。
4. 删除行数预算断言，换成 `swift-format` 的 line-length 配置（或 code review 习惯）；如需防回涨，用 `scripts/check_file_sizes.sh` 阈值 + `allowlist`。
5. 与 F7 协同：把边界测试从单元 suite 拆到单独的 `ArchitectureChecks` test target（或脚本），PR 快跑只跑单元。

**验证**：`cd /tmp && swift test --package-path <repo> --filter Architecture` 仍通过（cwd 无关）；删掉被替代的断言后 CI 仍能抓住一次人为违规（用临时分支验证）。

---

### F7（收益 中 / 成本 低）测试速度：46s 中约 10s 花在"只截图不断言"的可视化测试；并行化前置条件明确
**证据**：
- `MenuVisualSnapshotRenderingTests.swift`：9 个 test、11 次 `renderPNG`、5 次 `fitToNaturalSize`；`renderPNG` 内 `settle()` = `RunLoop.main.run(until:)` 循环 30 次 × 0.02s（`:670-677`），`fitToNaturalSize` 调 2 次 settle → 约 16 × 600ms ≈ **9.6s**（占 46s 的约 20%）。每张 PNG 写固定目录 `/tmp/omu-visual`（`:16`），**没有任何像素断言**（只断言 `bounds > 2` 和个别 state 字段），没有基线图、没有清理——它是"人工取证工具"，不是回归测试。
- 其它真实等待：`LocalUsageHistoryRepositoryTests.swift:124` `Task.sleep(nanoseconds: 1_100_000_000)` 等 mtime 粒度（1.1s）；`OfficialProviderTests.swift:970` 200ms；`ProviderRefreshSchedulerTests` 50–100ms 若干。全仓测试 42 处 `Task.sleep`（字面量合计 2.545s/33 次），8 处 `Thread.sleep`；`Task.sleep(for: .seconds(60))` 多处于已取消 task（不实际等待，勿直接求和）。
- 网络/时钟/Keychain 注入已较好：20 个测试文件用 `URLProtocol` stub；Keychain 全部走临时 `storageURL`；`Date()` 出现 45 个文件（多数显式传 `now`，少数依赖真实时钟）。
- 并行化：`swift test` 当前串行；`--parallel` 前需处理 3 类全局态：(a) 3 个文件创建 `NSWindow`（visual snapshot、phantom guard、appearance）；(b) `SettingsScenePhantomWindowGuardTests.swift:117-125` 在测试进程内启动**生产单例的 0.75s 轮询 Timer**（会扫/关窗口）；(c) 固定 `/tmp/omu-visual` 输出目录。

**建议**：
1. 可视化测试改为 opt-in：默认 `throw XCTSkip("set OMU_RENDER_SNAPSHOTS=1")`，CI 夜间/发版前跑；或保留 1 个冒烟场景常驻。
2. 若保留常驻，把 `settle()` 改成自适应（`layoutSubtreeIfNeeded` + 直至 `needsDisplay == false`，最多 ~5 次 runloop），并对 PNG 做最小断言（尺寸/非纯色/哈希入 Manifest）——否则不叫 snapshot test。
3. `LocalUsageHistoryRepositoryTests` 的 1.1s 改为显式设置 `FileManager.setAttributes(.modificationDate)` 到确定时间；`Thread.sleep` 换 `XCTestExpectation`/注入 sleeper。
4. 完成 F3/F8 清理后启用 `swift test --parallel`（先本地对比 3 次）；同时给 CI 提速（F10）。
5. test target 拆分（F5/F6）：库 target 的测试不需要编译 app target，PR 快车道可只跑库测试。

**验证**：`swift test 2>&1 | tail` 前后对比耗时；`swift test --parallel` 连续 5 次无 flake。

---

### F8（收益 中 / 成本 低）测试卫生：无意义断言、在单测里启动生产定时器、固定 /tmp 残留
**证据**：
- 3 处 `XCTAssertTrue(true)`（如 `SettingsScenePhantomWindowGuardTests.swift:125`；该测试唯一"断言"就是这句，永不可能失败）。
- `SettingsScenePhantomWindowGuardTests.swift:117-125` 在测试进程内调用生产 `shared.start()`（注册通知+启动 Timer），污染后续测试与并行执行。
- `SettingsScenePhantomWindowGuardTests.swift:111-115` 断言实现常量 `sweepDelays`，不测行为。
- `MenuVisualSnapshotRenderingTests` 固定写 `/tmp/omu-visual`，不清理；`renderPNG` 失败信息只带布局尺寸。
- 8 处 `Thread.sleep` 阻塞测试线程（如 `OfficialProviderTests.swift:1276`）。
- 正向：Keychain/UserDefaults/网络/临时目录注入到位；`makeTestDefaults()` 的 suite 创建失败会退回 `UserDefaults.standard`（`TestKeychainHelpers.swift:39`）——理论上会污染真实 defaults，建议直接 `fatalError` 或换 `XCTUnwrap`。
- 无 `XCTSkip`、无超时保护、无测试 tag/plan。

**建议**：删 `XCTAssertTrue(true)`/常量断言；phantom guard 只测纯函数（`SettingsSceneWindowPolicy`）且不启动生产单例；可视化测试改 opt-in（F7）；`Thread.sleep` 改异步等待；`makeTestDefaults` 失败即 `XCTFail`；`/tmp/omu-visual` 输出改 `FileManager.temporaryDirectory/UUID` 并在 `tearDown` 清理。

**验证**：`grep -rn 'XCTAssertTrue(true)\|Thread.sleep' Tests` 归零；`swift test --parallel` 无跨测试干扰。

---

### F9（收益 中 / 成本 低）可访问性/键盘：图标按钮无 label、无 Esc 关闭、无 ⌘ 快捷键
**证据**：
- 全 UI 层 `accessibilityLabel` 24 处、`accessibilityValue` 3 处、`accessibilityElement` 2 处，而 `Button(` 81 处；`keyboardShortcut` 全仓仅 2 处（`SettingsResetDialogView.swift:36,46` 的 cancel/default）；**0 处** `.onExitCommand`/`keyDown`。
- 菜单面板顶部 3 个图标按钮（刷新/设置/退出）直接 `headerIconButton(...)`（`MenuContentView.swift:149,154,161`），helper（:213-226）**既无 `.accessibilityLabel` 也无 `.help`** → VoiceOver 只读 "button"。
- `SettingsCheckbox`（`SettingsControlPrimitives.swift:151-173`）是自绘 checkbox Button，无 label/traits（全设置页复用）。
- 启发式扫描发现 9 处图标按钮缺 label（8 文件；抽检 2 处为真：上述 menu header、SettingsCheckbox；2 处为带文字假阳性）。`Image(systemName:)` 25 处仅 6 处 `.help(`。
- 焦点：打开设置窗即 `makeFirstResponder(nil)`（`SettingsWindowController.swift:165-167`）；`@FocusState` 仅覆盖阈值输入/relay 标题编辑（4 处），无完整键盘遍历设计；菜单面板 `.nonactivatingPanel`（`MenuPanelController.swift:73`）导致键盘交互受限（需 `canBecomeKey` 设计）。
- 正向：`RuntimeGuards.installGlobalKeyboardCommandMenu()` 修复了无主菜单 App 的 ⌘C/V/X 派发（`RuntimeGuards.swift:69-71` 注释）——有意识但只覆盖了编辑命令。

**建议（低成本优先）**：
1. 给 menu 顶部 3 个按钮 + `SettingsCheckbox` 补 `.accessibilityLabel`/`.help`；对 pill/segment 补 `.accessibilityAddTraits(.isSelected)`。
2. 菜单面板与设置窗加 `.onExitCommand { close() }`（若面板可成为 key window，实现 `NSPanel.canBecomeKey` override）。
3. 菜单面板加 `⌘R`（刷新可见）、`⌘,`（设置）、`⌘Q`（退出）等价键；设置页 tab 加 `⌘1..⌘7` 可选。
4. 建一份 release 前 VoiceOver 手工清单（或 `docs/ACCESSIBILITY.md` 5 行检查表）。

**验证**：VoiceOver 逐个元素朗读；Full Keyboard Access 下 Tab 顺序可达全部控件；Esc 关闭面板。

---

### F10（收益 高 / 成本 低-中）CI 门禁：26 行 workflow，release-only 编译错误要到打 tag 才发现
**证据**（`.github/workflows/ci.yml` 全文 26 行）：`actions/checkout@v4` + `swift-actions/setup-swift@v2`（`swift-version: "6.2.0"`）+ `swift build` + `swift test`。没有：缓存、`concurrency`、`timeout-minutes`、warning 门禁、format/lint、覆盖率、`-c release` 构建、focused tests、job 拆分、artifact。
- 工具链漂移：本机 `swift --version` = **Apple Swift 6.4**（`Target: arm64-apple-macosx27.2.0`），CI 固定 6.2.0；`macos-latest` 镜像会漂移。
- 仅 debug 配置被编译：release 配置（`-c release` / `--arch x86_64` 交叉）只在 `release.yml` 打 tag 时验证，一旦失败在发布时爆。
- 无 warning 门禁：126k 行 Swift 的 warning 只会累积；建议先跑基线再 turn on。

**建议（P0 先做，详见 §3）**：concurrency+timeout、`swift build -c release`、warnings 门禁、`swift format lint`（本机 `swift format --version` 可用，输出 `main`；CI 6.2 工具链若不含则 `brew install swift-format`）、`.build` 缓存、单元/架构 job 拆分 + `--parallel`（依赖 F7/F8）、覆盖率非阻塞上报、`macos-15` 固定镜像 + `.swift-version`。

---

### F11（收益 中高 / 成本 中）发布链路：CI 永不签名、测试不参与发布、VERSION 与 tag 可能漂移、DMG 脚本无 trap
**证据（release.yml 328 行）**：
1. **不跑测试、不做构建门禁**：tag push 直接进入 `Build release assets`（:81-85）；CI 的 `build-and-test` 是另一个 workflow，tag 可以指向红灯 commit。建议 release job 先 `swift build && swift test`（或复用 CI 的 `workflow_call`），失败即停止。
2. **签名/公证永远不生效**：`package_dmg.sh` 支持 `DEVELOPER_ID_APPLICATION` + 3 种公证凭据（`:95-138, 297-325`），但 `release.yml` **没有任何 secrets/env 传入** → 每个 GitHub Release 都是 ad-hoc；而 `RELEASE_CHECKLIST.md` §4 描述的是本地签名流程。二选一：加证书导入 + `DEVELOPER_ID_APPLICATION`/公证 secrets；或明确"CI 发布 = ad-hoc，签名版只能本地/自建 runner"，并删掉歧义。
3. **VERSION 漂移**：`release.yml:64-68` 只把版本写进 CI workspace 的 `VERSION`，不提交回仓库；同名 tag 与仓库 `VERSION` 无自动校验（当前 2.5.4 = v2.5.4 只是巧合对齐）。建议：打包前 `test "$(cat VERSION)" = "$version"` 强制，或发布后自动开 PR 更新 VERSION。
4. **legacy endpoint 强耦合**：`:280-327` 校验 `Four-JJJJ/AI-Plan-Monitor` 的 `latest.json` 版本等于新版本，但本 workflow 不更新它（依赖重定向/旧自动化）→ 外部状态可让发布失败。建议降级为 warning，或显式文档化前置条件。
5. **SHA256 双算不交叉校验**：`latest.json` 的 sha 来自 `shasum`（`:98-99`），`SHA256SUMS.txt` 由 `package_dmg.sh:531` 生成；两者独立计算，建议在 validate 步骤断言一致。
6. 无 `concurrency`（重复 tag 推送/手动 dispatch 可并发）、无 `timeout-minutes`；universal（arm64+x86_64）在 `macos-latest` 上构建，耗时不可控。

**证据（scripts/package_dmg.sh 545 行）**：
- **无 `trap` 清理**（`grep -n 'trap '` 无输出）：`hdiutil attach`（:511）与 `detach`（:513）之间失败会留下挂载卷 + `/tmp/aibm_pkg.*` 临时目录。
- `codesign --deep`（:248,254,258）已不推荐；该 bundle 只含资源包（`.build/.../OhMyUsage_OhMyUsage.bundle`），可去掉 `--deep` 并对 app 本体 `--options runtime` 签名后 `codesign --verify --deep --strict` 再确认。
- Finder AppleScript 定制 DMG 窗口（:348-379）：`delay 1/2/2` + `|| warn`，CI/无 GUI 会话下至少 +5s 且可能挂起；建议 `CUSTOMIZE_DMG_WINDOW=0` 默认在 CI 关闭。
- `swift build`（:393）用仓库 `.build` → 继承 F1 失败；且 `resolve_binary_path`（:161-191）按 mtime 在 `.build/apple`、`.build/arm64-...`、`.build/x86_64-...`、`.build/out/Products/Release` 四个布局里猜，可能打包到旧/Xcode 产物。改用 `swift build --show-bin-path`。
- `Info.plist` heredoc 未加引号（`:412` `<<PLIST`）——本意是展开 `$APP_VERSION`，属可接受，但 `$` 出现在其他变量时会破坏 plist（低风险，注释说明即可）。
- `CFBundleVersion` 直接用营销版本（`:449-450`），与自己的 updater 比较逻辑绑定，暂不算缺陷但版本比较需按数字分量（`AppVersionResolver` 已有，OK）。

---

### F12（收益 中 / 成本 低）文档一致性：AGENTS.md 落后于 target 结构，EXTENDING.md 有 4 个死链
**证据**：
- `AGENTS.md`（与 `CLAUDE.md` **内容完全相同**，`cmp` 一致）项目结构只列 `Sources/OhMyUsage` 下 App/UI/Providers/Services/Models/Utils（:3-10），完全没提 7 个库 target（`OhMyUsageDomain`/`Infrastructure`/`Providers`/`Application`/`Presentation`/`Features`/`Bootstrap`，合计约 5.5k 行）；命令段（:20-24）没有 iCloud/xattr 构建故障的说明与 `--scratch-path` 入口；"one primary type per file named after that type"（AGENTS.md:22）与实际（SettingsView 被 21 个文件扩展）冲突。
- `docs/EXTENDING.md` 4 个死链（均已迁到 `Sources/OhMyUsageProviders/`）：`:23 OfficialProviderFetchRuntime.swift`、`:24 OfficialProviderAuthRuntime.swift`、`:26 OfficialSnapshotFallback.swift`、`:63 RelayHTTPClient.swift`；`:48` "Prefer provider fixture tests beside the provider file" 与实际（全部测试集中在 `Tests/OhMyUsageTests`，`Fixtures` 被 `Package.swift:80-82` exclude）不符。
- `README.md` 工程结构树（:264-282）**正确列出 8 target**，但把 Providers/Presentation/Features 描述为"骨架"，而 `OhMyUsageApplication`（2,214 行）、`OhMyUsageProviders`（1,664 行）已有实质逻辑；本地打包示例 `APP_VERSION=2.0.0`（:301）是陈旧版本；无 iCloud 构建故障排查段。
- `docs/RELEASE_CHECKLIST.md` 内容扎实，但缺少：CI 绿灯前置、CI 是否签名的明确预期、VERSION↔tag 自动断言、SHA 交叉校验、`--scratch-path` 相关说明。

**建议**：更新 AGENTS.md（target 地图 + build wrapper + xattr 排查 + 测试布局 + SettingsView 例外说明）；修正 EXTENDING 4 个链接并补 `Sources/OhMyUsageProviders` 分工；README 更新骨架措辞与打包示例、加故障排查；CLAUDE.md 若只是副本，改成 `@AGENTS.md` 引用或删除避免双维护；RELEASE_CHECKLIST 加 §3 自动化前置与签名预期。

---

## 2. 测试套件问题清单

| # | 问题 | 证据/规模 | 建议 | 优先级 |
|---|---|---|---|---|
| T1 | 源码扫描式架构测试脆弱、依赖 cwd | 46 个方法/4 文件（+~5 个混在其他文件）；112 处 `Sources/` 引用；8 文件 48 处 `currentDirectoryPath` | 编译器 target 边界替代（F6）；保留规则进 CI 脚本；根路径改 `#filePath` | P0 |
| T2 | 行数预算/字符串 contains 断言可被规避 | `UIFileDecompositionBoundaryTests.swift:12-14`(≤460)、`:97-99`(≤620)、`ArchitectureBoundaryTests.swift:15-18`、`MonolithRetirementBoundaryTests.swift:34-40,679` | 删除或改语义规则 + swift-format | P1 |
| T3 | 可视化测试实为截图工具 | `MenuVisualSnapshotRenderingTests` 9 test/11 render/5 fit，settle 30×20ms×2 ≈ 9.6s；无像素断言；固定 `/tmp/omu-visual` 不清理 | opt-in（env/XCTSkip）+ 自适应 settle + 最小断言；避免常驻 CI | P0 |
| T4 | 真实等待让 suite 变慢且易 flake | `LocalUsageHistoryRepositoryTests.swift:124` 1.1s；42 处 `Task.sleep`；8 处 `Thread.sleep`（`OfficialProviderTests.swift:1276` 等） | 注入 Clock/Sleeper、`setAttributes` 改 mtime、expectation 替代 | P1 |
| T5 | 全局态测试污染 | `SettingsScenePhantomWindowGuardTests.swift:117-125` 启动生产单例 0.75s Timer 且 `XCTAssertTrue(true)`；3 文件创建 NSWindow | 删守卫/只测纯函数；AppKit 测试集中到独立 target | P0 |
| T6 | 无效断言/实现常量断言 | 3 处 `XCTAssertTrue(true)`；`sweepDelays` 常量断言 | 删除或改行为断言 | P0 |
| T7 | 单 test target 承载全部 163 文件、155 文件 `@testable import` app | `Package.swift:68-83`：1 个 testTarget 依赖 8 target | 按库 target 拆 test target；app 侧测试保留独立 target | P1 |
| T8 | 无法并行/无分层 | 无 `--parallel`；AppKit + 全局 timer + 固定 /tmp 阻碍 | 先清 T3/T5，再 `--parallel`；CI 拆 fast/full 两档 | P1 |
| T9 | 测试数据/时间依赖边界情况 | `makeTestDefaults` 在 suite 创建失败时退回 `UserDefaults.standard`（`TestKeychainHelpers.swift:39`） | 失败即 `XCTFail`，避免污染真实 defaults | P2 |
| T10 | 无超时/无 skip/无 tag | `grep XCTSkip` = 0；无 expectation timeout 保护 | 加测试 plan/tag；关键异步测试统一 2s 超时 | P2 |

---

## 3. CI/发布改进清单

| # | 改进 | 具体做法 | 收益 | 优先级 |
|---|---|---|---|---|
| C1 | 并发与超时 | `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`；`timeout-minutes: 30` | 省 runner/避免排队 | P0 |
| C2 | release 配置构建 | 加 `swift build -c release`（含 `--arch x86_64` 可选） | 打 tag 前暴露 release-only 编译错误 | P0 |
| C3 | warning 门禁 | 先基线 `swift build 2>&1 | grep -c warning`；再用 `-Xswiftc -warnings-as-errors` 或 `grep -q "warning:" && exit 1` | 防止 warning 累积 | P0 |
| C4 | format/lint | `swift format lint --recursive Sources Tests`（本机工具链已可用；CI 若无则 `brew install swift-format`），`swift-format` 配置 lineLength | 统一格式，替代行数预算类测试 | P1 |
| C5 | 构建缓存 | `actions/cache` 缓存 `.build`，key = `${{ runner.os }}-${{ hashFiles('Package.swift') }}-${{ env.SWIFT_VERSION }}`，restore-keys 前缀；无外部依赖，收益主要在跨 PR 复用对象文件 | 降 CI 时长 | P1 |
| C6 | 测试分层/focused | job A：库 target 测试（需先拆 test target）；job B：全量；PR 可按 paths 过滤（如仅 UI 改动跑 `--filter "Presenter|Settings"`，主分支全量）；完成后 `swift test --parallel` | PR 反馈从 46s+ 降到 <15s | P1 |
| C7 | 覆盖率 | `swift test --enable-code-coverage` + `xcrun llvm-cov report`，先非阻塞上传 artifact/PR comment | 可视化测试质量 | P2 |
| C8 | 工具链固定 | `.swift-version`（swiftly）或 `swift-actions/setup-swift@v2` 升到与开发机一致（本机 6.4）；runner 固定 `macos-15` | 消除 6.2/6.4 行为差 | P1 |
| C9 | 发布前置门禁 | release job 内先 `swift build && swift test`（或 `workflow_call` 复用 CI），失败不进打包 | 阻止红灯发版 | P0 |
| C10 | 签名/公证决策 | 若走 Developer ID：CI 导入证书（base64 p12 → keychain）+ 传 `DEVELOPER_ID_APPLICATION`/`NOTARYTOOL_PROFILE`；否则文档明确 CI=ad-hoc | 消除 checklist 与现实的歧义 | P1 |
| C11 | 版本一致性 | 打包前 `test "$(cat VERSION)" = "${{ steps.version.outputs.version }}"`；发布成功后自动 PR 更新 VERSION | 消除 VERSION/tag 漂移 | P1 |
| C12 | manifest 交叉校验 | validate 步骤断言 `latest.json` sha256 == `SHA256SUMS.txt` 对应值；legacy endpoint 校验降级 warning | 减少发布假失败 | P2 |
| C13 | DMG 脚本健壮性 | 加 `trap cleanup EXIT`（detach -force + 删 tmp）；去掉 `--deep`；CI 关闭 Finder 定制；`--scratch-path`/`--show-bin-path`；CI 加 `hdiutil verify` + 挂载后校验 app 存在 | 防挂载残留/打包错产物 | P1 |
| C14 | 本地构建入口 | `scripts/build.sh`（F1）+ README/AGENTS 更新；CI 也用同一 scratch 语义 | 开发机可重复构建 | P0 |

---

## 4. 如果只做 3 件事

1. **统一构建入口，修掉 iCloud/xattr 不可复现（F1/C14，约 0.5–1 人日）**
   新增 `scripts/build.sh`（`--scratch-path ~/Library/Caches/oh-myusage/build` + `xattr -cr` 兜底 + 参数透传），`package_dmg.sh` 改用 `--show-bin-path`，AGENTS/README 加排查段；验证：删除 `.build` 后连续两次 clean build + `codesign --verify` 通过。这是所有后续工作（CI、本地验证、发布）的前置。

2. **CI 门禁补齐到"发版前不可能漏"（F10/C1–C3、C9，1–2 人日）**
   `concurrency`+`timeout`、`swift build -c release`、warnings 门禁、`swift format lint`（可先非阻塞）、release workflow 打包前跑 build+test；`.swift-version` 对齐 6.4、runner 固定。验证：故意提交一个 release-only 编译错误/一个 warning，CI 必须红。

3. **Settings 上帝类型开始拆，并先把"截图测试"移出常驻 suite（F2 第 1–2 步 + F7/C6，3–5 人日）**
   新增 `SettingsSidebarView` + `SettingsQuotaPresenter`，把 `SettingsView` 收敛为组装根；可视化测试改 env-gated；之后启用 `swift test --parallel` 与库 target 拆分。收益是后续每次 UI 迭代的编译/重绘/测试反馈都会变快，同时为删除 F6 的源码扫描测试铺路。

> 如果只能做 1 件：做第 1 件——现在"默认 `swift build` 在主力开发机失败"，任何后续门禁和验证都建立在不可靠基础上。

---

## 5. 方法与限制

- 全部结论来自只读静态分析：文件/行数统计、`grep`/`ripgrep`、`git diff`、`xattr`/`find` 现有构建产物、workflow/脚本通读。**未运行** `swift build`/`swift test`（按任务约定由 Lead 执行），因此 46s/15.28s 与"默认 build 失败"均引用任务输入/Lead 实测，本报告负责给出根因证据与修复方案。
- 测试套件问题基于计数与样本抽查；"重复覆盖"未做语义级去重（如 RelayProviderTests 96 个 test/3,756 行内可能存在重复场景，需逐一 diff 才能确认，未计入结论）。
- 可访问性结论基于静态标签统计 + 2 处抽检；VoiceOver 实际朗读需真机验证。
- 本地化漏网扫描使用启发式（CJK 字面量行 ±3 行内无本地化调用即标记），已人工复核命中的 4 处；可能存在多行拼接的漏报。
- 未做网络/真实站点验证；release 的 legacy endpoint 行为需联网或查看旧仓库确认。
- 未审查 `docs/OPTIMIZATION_*` 的历史建议是否已被实现（任务要求勿盲信，本报告所有建议均基于当前代码独立取证）。

## 附录 A：关键命令与输出摘录

```
$ swift --version
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 ...)
Target: arm64-apple-macosx27.2.0

$ xattr ".build/out/Products/Debug/OhMyUsage_OhMyUsage.bundle"
com.apple.FinderInfo
com.apple.fileprovider.fpfs#P
com.apple.provenance

$ xattr ".build/xcode/Build/Products/Release/OhMyUsage_OhMyUsage.bundle"
com.apple.FinderInfo
com.apple.fileprovider.fpfs#P
com.apple.provenance

$ find .build -name '.DS_Store'
.build/.DS_Store
.build/out/.DS_Store
.build/out/Intermediates.noindex/.../.DS_Store

$ find Tests -name '*.swift' | wc -l
163
$ grep -rhoE 'func test[A-Za-z0-9_]+' Tests --include='*.swift' | wc -l
1344
$ grep -rln 'currentDirectoryPath' Tests --include='*.swift' | wc -l
8
$ grep -rln 'extension SettingsView' Sources/OhMyUsage/UI --include='*.swift' | wc -l
21
$ grep -c 'localizedText' Sources/OhMyUsage/UI/Settings/UsageAnalyticsSettingsView.swift
0
$ grep -rn 'SettingsWindowAppearanceController' Sources --include='*.swift'
# 仅命中定义文件自身 → 生产代码无引用
$ grep -rn 'trap ' scripts/package_dmg.sh
# 无输出 → 无清理 trap
```
