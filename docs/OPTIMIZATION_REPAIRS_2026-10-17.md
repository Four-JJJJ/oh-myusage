# 2026-10-17 第一批修缮与验证

## 范围与顺序

以当日审查报告和当前代码复核为依据，按以下顺序实施：

1. 凭证完整性：修复多实例整份 vault 覆盖、冷写覆盖、失败污染缓存及失败时删除旧项。
2. 配置恢复：确保不可解码原件经过多次启动和保存后仍可人工恢复。
3. 凭证文件保护：权限收紧和私有原子替换，不在本批迁移真实 OAuth 数据。
4. 确定性运行时修复：取消传播、移除历史轮询、复用枚举缓存。
5. 构建入口、源码警告门禁，以及统计页中英文本地化。

第一批修缮保留已有官方服务分类 UI 改动；未修改 AGENTS.md、长期知识库，未运行真实重置、读取真实钥匙串或调用付费接口。后续用户授权的版本整理与交付单独记录在文末。

## 已实施

### 凭证事务

- `AppViewModel` 的默认 Codex auth 由组合根共享 vault 注入，不再无条件创建独立存储。
- `KeychainService` 按存储身份使用同进程事务锁；保存前读取持久化权威快照，合并单项后同步写入，成功才更新缓存与版本。
- live 读取区分不存在、不可访问和损坏；后两者拒绝覆盖，不能把读取失败当作空 vault。
- `SecItemUpdate` 非 not-found 失败直接返回，不再先删旧项再新增。
- 删除写入空值 tombstone，阻止未能删除的旧单项凭证再次迁入；公开读取、凭证枚举过滤该标记。
- 历史默认 service 清理只限默认 service，不误删自定义 service 同账号之外的历史凭证。
- generation 使其他存储实例和 broker 缓存失效；broker 的进行中读取按版本隔离。throws 存储端口不再吞掉写入失败。

成功返回代表同步持久化已成功，不使用可重建缓存式的延迟写策略。同进程事务不是跨进程 CAS；旧版应用不理解 tombstone，不能保证降级后的防复活语义。

### 配置原件保留

- 不可解码字节在任何覆盖前进入 `OhMyUsage/config.corrupt-archive/`，SHA256 内容寻址、同名逐字节验证。
- 使用 0600 staging 文件完整写入并 fsync 后，通过 macOS `renamex_np(RENAME_EXCL)` 原子独占发布，避免双链接崩溃窗口；失败时不替换原始配置，目录权限 0700。
- 普通保存、bootstrap 和后续启动不删除归档；明确的应用 reset 才清理该目录。
- 保留原有 lossy、LKG 和 preserved candidate 恢复顺序。归档是人工恢复证据，不参与自动解码选择。
- 无法读取来源时抛错，不再伪造空坏档并覆盖默认配置。保存前仍读取既有快照保护原件，但已验证字节不重复解码。

### Profile 文件

- 现有 profile 文件在 store 初始化时尝试收紧到 0600，失败只记录不含内容的告警。
- 新写入从创建临时文件起就是 0600，完整写入及 fsync 后 rename，避免写完再 chmod 的暴露窗口。
- 默认应用专属父目录使用 0700；显式注入的既有父目录不批量 chmod。拒绝符号链接和硬链接目标。
- 测试中的默认 profile URL 隔离到临时目录，不收紧真实应用数据的权限。

profile 仍包含明文 OAuth 内容，0600 不能隔离同一用户下的其他进程。迁入按账号区分的 Keychain 引用需要另做兼容迁移和真实账号验收，本批没有声称完成。

### 运行时和界面

- 父刷新取消传递到 detached worker；合作式任务可终止，非合作式任务晚返回不发布旧结果。
- 删除全生命周期 0.75 秒窗口扫描 Timer；保留事件观察与打开设置后的有限扫描。
- Grok/Gemini 枚举缓存跨 service 实例复用，不改变 root/cutoff 键或时间窗口语义。
- 修复四处生产源码警告；统计页标题、选项、指标、空态、月份和固定来源说明跟随应用语言。
- 未知诊断保留原文，不通过翻译隐藏错误；未进行全仓本地化框架替换。

### 构建与发布入口

- `scripts/dev.sh build|test|run` 使用默认后端，将产物放在同步目录外，按 checkout 绝对路径区分缓存。
- 通过 `DEVELOPER_DIR` 临时选择完整 Xcode，脚本不会写全局 `xcode-select`；支持 `OMU_BUILD_PATH` 和显式后端覆盖。
- 打包使用同一入口及相同 Release/双架构参数的 `--show-bin-path`，不再按 mtime 猜产物。
- CI 的源码 build 使用 warnings-as-errors；release workflow 在打包前运行测试。修缮阶段未执行远端 workflow 或发布。

## 验证

- 新增凭证、配置、权限和取消测试均先确认原始实现失败，再修复。
- Debug：默认后端、完整 Xcode、独立 `/tmp` 目录，`build -Xswiftc -warnings-as-errors` 通过，生产源码零警告。
- 全量 XCTest：交叉复核补充 3 项边缘回归后最终 **1,378 项通过、0 失败，约 43.6 秒**；相对本轮开始的 1,339 项新增 39 项，包含已有未提交 UI 改动的测试。
- focused：凭证初批 58 项，隔离修复后所选凭证集 44 项；配置最终 36 项、profile/权限相关 45 项、运行时相关 30 项分别通过。
- Release：arm64 + x86_64 编译通过，产物确认为双架构，最低系统版本 14.0。Xcode-beta 构建系统另有 x86_64 弃用提示，不计作 Swift 源码警告。
- 中英文统计空态和带表格截图已查看。ImageRenderer fixture 复用生产模块，但绕过不支持的 ScrollView 渲染和真实数据加载；不替代真实窗口交互验收。
- `bash -n`、构建脚本三项参数/路径测试、`git diff --check` 通过。

日志：`/tmp/omu-integration-build-final.log`、`/tmp/omu-integration-tests.log`、`/tmp/omu-integration-release-final.log`。
截图：`/tmp/omu-analytics-localization/`；已有菜单与设置快照仍在 `/tmp/omu-visual/`。

以上修缮阶段没有运行 DMG 打包脚本，避免清理既有 dist 和触发其他打包副作用。SwiftPM 的原始通用二进制未签名；该阶段不代表最终 app bundle 的签名、公证、安装或启动验收。

## 本地交付与 2.6.0 发布准备

- 初次本地覆盖安装沿用当时的 2.5.4 版本号，已验证安装路径 `/Applications/oh-myusage.app`、固定 Bundle ID `com.oh-myusage.app`、arm64/x86_64 双架构、有效 ad-hoc 签名及正常启动；不是 Apple Developer ID 签名或已公证构建。
- 用户随后要求发布 2.6.0，已同步 `VERSION`、中英文 README 和 `docs/releases/v2.6.0.md`。原有官方服务设置 UI 与其回归测试纳入本版，没有重置或丢弃这些改动。
- 发布前重新执行 `./scripts/dev.sh build -Xswiftc -warnings-as-errors` 通过；`./scripts/dev.sh test` 再次通过 **1,378 项、0 失败，约 45.4 秒**。日志：`/tmp/omu-260-preflight-build.log`、`/tmp/omu-260-preflight-tests.log`。
- 本机工具链仍为 Swift 6.4；正式标签 `v2.6.0` 使用仓库固定的 Swift 6.2 GitHub 流水线进行测试、通用打包、校验清单生成和发布。远端结果及最终安装态需要发布后现场核验，不能从本地测试推断。
- `.review/` 保留为本地审查材料，不纳入发布提交；不发布临时测试日志、安装备份或真实用户数据。先前盘点的备份清单仍未删除。

## 保留的后续工作

- 真实钥匙串拒绝/锁定、真实 OAuth 轮换、账号切换和退出重启恢复验收。
- session SQLite/目录扫描下沉、profile/slot I/O 异步化、配置保存去重需要单独保序设计，不与本批事务止损混做。
- 官方 provider Retry-After、非合作式 Codex CLI 等待取消、剩余格式化/本地化问题。
- 启动、主线程耗时、CPU、RSS、能耗基线；不以删除 Timer 或测试数量推算性能百分比。
- 架构 target 接入或退役、Settings 类型拆分、护栏换代按独立方案决定，未批量删除现有分层。
- 本地使用 Swift 6.4；CI 固定 Swift 6.2 的修复后结果仍需远端核验。历史测试源码仍有警告，因此没有宣称 `swift test` 零警告。

## 2.6.0 发布计时测试修复

- 远端 `v2.6.0` 的 Release run `39040188401` 两次尝试均在 `testDuplicateSavedKeepsOriginalDeadline` 失败；Git 检出和 Swift 准备成功，打包与发布未执行。相同旧提交的 CI run `39040188510` 成功，不能据此忽略 Release 测试失败。
- 原测试依赖 150 毫秒截止时间、60 毫秒真实等待和 450 毫秒耗时上限。CI 调度延迟会使第二次保存发生在截止时间之后，不满足测试的时序假设；失败不等同于 Git 推送或保存功能失败。
- `AppSettingsPersistenceFeedbackCoordinator` 注入当前时间和等待截止时间的闭包；默认仍为系统时间与 `Task.sleep`，不修改应用默认时序、工作流门禁或版本号。
- 相关测试使用 MainActor 隔离的可控时钟手动推进时间，覆盖原截止时间、到期后重复保存、旧任务取消、新提示的独立截止时间、任务延迟启动和同步补偿；保留默认真实时钟的自动清除冒烟测试。
- 本地严格编译通过；全量 **1,382 项、0 失败**；相关 **12 项测试连续运行 20 轮全部通过**；`git diff --check` 通过。本机仍为 Swift 6.4，不能替代远端 Swift 6.2 验证。
- 该修复不读取真实凭证、不调用付费接口、不覆盖安装应用；`.review/` 不纳入提交。推送、标签和 Release 的最终状态以发布后的现场核验为准。
