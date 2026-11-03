# 2026-11-03 优化实施记录

基线：`main` / `40b6100` / `VERSION=2.6.7`，全量 1,500 项测试通过。
分支：`optimize/2026-11-priority-pass`（未推送、未发布、未改版本号）。

## 已实施

| 优先级 | 事项 | 结果 |
|---|---|---|
| P1 | Codex CLI RPC | 新增 `CodexAppServerRPCClient`：流式读 stdout，`id=2/3` 都到就返回；单一 20s 期限；任务取消立即返回；子进程在后台回收。去掉固定 3s sleep 和实际不生效的 10s/18s 重试。`clientInfo.version` 改为真实版本。 |
| P1 | 统计扫描锁 | `UsageAnalyticsRepository` 去掉 `NSLock.try()` + 10ms sleep 轮询；扫描排队改用 `SerialOfficialFetchGate`（挂起、可取消），短锁只保护缓存条目。 |
| P1 | 更新 manifest 签名 | 应用校验 `latest.json.sig`（Ed25519，对原始字节签名）；公钥在 `Resources/update_signing_public_key.txt`，为空时不校验。`scripts/update_signing.swift` 提供 generate/sign/verify；release workflow 在公钥存在时强制签名并上传 `.sig`。启用步骤见 `RELEASE_CHECKLIST.md` §5。 |
| P2 | ProviderModule | 每个 provider 的元数据、默认配置、fetch plan、构造方式收进 `Providers/Modules/ProviderModule+X.swift`，由 `ProviderModuleRegistry.allModules` 统一查表。`.ollamaCloud` 引用文件 16 → 6，`.windsurf` 15 → 5。新增覆盖护栏测试，`EXTENDING.md` 已更新。 |
| P2 | 本地化 | 新增 CJK 字面量总量护栏（只降不升）；约 150 个新 `L10nKey`，中英文逐字保持。Sources 内 CJK 字面量 651 → 469。 |
| P2 | 大文件拆分 | `SettingsProviderSidebar` 1,697 → 139 行，`SettingsRelayConfigurationForm` 1,307 → 64 行，`SettingsLocalUsageTrend` 1,256 → 352 行，均为纯移动。 |
| P3 | 模块 shim | 删除 22 个跨模块 `typealias` 转发，调用方直接 import 对应 target。 |
| P3 | 性能基线工具 | `os_signpost`：ProcessStart、LaunchFinished、ProviderFetch、AnalyticsScan（`OhMyUsage/Performance`）。`scripts/perf.sh sample` 采样 CPU/RSS/线程数，`trace` 用 Instruments 录制。 |
| P3 | 包体 | `app_icon_source.png`（739KB）移出 app bundle，放到 `scripts/assets/`，打包仍用它生成 icns。 |

## 验证

- `./scripts/dev.sh build -Xswiftc -warnings-as-errors`：零警告。
- `./scripts/dev.sh test`：**1,526 项、0 失败**（新增 26 项：Codex RPC 9、更新签名 5、ProviderModule 6、本地化 6）。
- 签名脚本本地往返：签名后校验通过，篡改 manifest 后校验失败。
- `perf.sh sample` 已对测试进程跑通；`trace` 未实际录制（需要运行中的 app）。

## 有意没做 / 留待后续

- **CI runner 固定版本与构建缓存**：无法在本地确认 runner 镜像与 Swift 6.2 工具链的组合，盲改可能让 CI 挂掉；SwiftPM 按 mtime 判断，新 checkout 基本全量重编，缓存收益有限。
- **大模块拆分以缩短编译**：实测干净构建 33s，没有类型检查超过 300ms 的函数，收益不足以支撑大规模搬迁。
- **统计诊断文案改为诊断码**：UI 目前按原文映射翻译，诊断文本也写进了快照缓存；改格式需要缓存兼容迁移，单独处理。
- **剩余 469 处 CJK 字面量**：`SettingsWorkspacePresentation`、`SettingsOverviewPresenter` 需要改签名和测试；`UsageAnalyticsSettingsView` 有自己的文案键体系；`SettingsQuotaDisplayHelpers` 还有 24 处。
- **启用更新签名**：需要维护者生成密钥、配置 `UPDATE_SIGNING_PRIVATE_KEY` secret 并提交公钥，见 `RELEASE_CHECKLIST.md`。
- **真实环境验收**：没有跑真实 Codex CLI、真实账号刷新和已安装 app 的交互；Codex RPC 的行为只由假 CLI 脚本测试覆盖。
