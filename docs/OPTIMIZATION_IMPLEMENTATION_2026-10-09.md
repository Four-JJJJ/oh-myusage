# OhMyUsage 优化实施与验收记录

日期：2026-10-09
基线：`main` / `a9259ca` / `VERSION=2.5.3`
对应方案：[优化方案 v2](OPTIMIZATION_PLAN_2026-10-09.md)

## 1. 结论和操作边界

本轮实施正确性、异步展示缓存、取消、容量治理、限流恢复和局部职责提取。保留原设计系统、默认刷新并发与启动 jitter，不以代码减少量或后台任务数量宣称性能收益。

没有提交、推送、安装覆盖、发布、版本升级、生产访问、付费调用或真实数据库/凭据迁移。新增数据库及缓存写入回归场景使用生成的临时 fixture；没有执行真实“重置应用”或删除用户数据。为已有删除/重置按钮接入缓存失效逻辑，不代表本轮执行过这些按钮。

原始方案是实施前证据快照，行号不随本轮提取更新；本文记录实施状态，二者不应混用。

## 2. 实施对照

| 项目 | 本轮落地 | 验证与边界 |
|---|---|---|
| C1 缓存容错 | 历史/统计缓存兼容旧 schema，未知版本忽略；重复 key 保留较新合法条目；FileHandle 有界读取；损坏、超大及非法输入安全降级 | 历史 16 MiB、统计 32 MiB、Provider 512 KiB 读取预算；不是原始日志大小上限，也不是总内存上限 |
| C2 Cursor 分页 | 根据原始 rows 数量续页，纯分页解析、请求注入；重复页/页数上限/后续页失败标记 partial | 生成满页过滤、全无效、短页、重复页、后续失败 fixture；未在线核验私有 API 契约 |
| C3 指纹 | 主库 + WAL，逐文件规范化 metadata 摘要含 inode；强制刷新绕过静态指纹缓存；有上限真实重读 | 非最新等长改动、文件替换、WAL fixture；metadata 全恢复的内容更改仍依靠真实重读兜底 |
| C3 inventory 共享 | 明确 descriptor/filter identity、有界 8-entry inventory；Codex allAccounts JSONL 的指纹/parser 共用清单 | 同 roots 不同 filter 隔离；其他 Provider 的 parser 清单未统一，不以 roots-only 缓存混用 |
| C4 失败与成功时间 | 失败保留最后成功时间、旧图表和错误；分离 attempt/验证时间，30 秒失败重试退避 | 相同指纹不清除失败；成功真实读取后清错；Cursor 远端最多 60 秒重新读取，其他历史最多 30 分钟真实重读 |
| P1 三类展示缓存 I/O | 历史/统计 utility 串行恢复与合并写入；Provider 启动后台恢复；恢复不覆盖新状态；退出 best-effort flush | reset/remove/慢读/晚到 worker fixture；正常退出等待最多 2 秒，突然终止可损失尚未落盘的可重建缓存 |
| P2 取消和复用 | detached worker 显式取消；scanner 文件/批次检查；生产 Cursor async URLSession、60 秒总 deadline；raw records 最多 100k、60 秒复用 | 单个等待者取消立即退出；仍有等待者则共享请求继续，最后一个退出取消请求；等价时间范围及身份才合并 |
| P3 官方缓存 | 默认 64 项、LRU、独立 24 小时 stale-age；可取消 gate；load epoch 随条目存储并在读取拒绝旧 epoch | 超容量、过旧、排队取消、失效后 actor hop、时钟回拨测试；凭据变化采用保守全局官方缓存失效 |
| P4 Provider 持久化 | 调用侧 revision + reset/provider generation；短锁、串行写盘、内存索引、待写合并与删除 fence | A/B 乱序、reset 后新写、删除、时钟回拨测试；显式磁盘读取可识别外部损坏/版本替换 |
| M1 同义工具 | regex/base64URL/percent clamp 公共原语；保留 Double 和窗口 metadata 的百分比工厂 | Unicode/base64、旧 Provider fixture、窗口 kind/reset/source/confidence 等字段回归 |
| M2 职责提取 | 排序 preview policy、Relay draft builder/凭据模板、趋势 identity resolver/格式化、MiniMax 纯解析 | 保留旧拖拽与配置语义；不全量策略化 Relay、不迁移 OAuth/凭据事务 |
| M3 双语/依赖 | UI 通用账号标签改用 Presentation，不再直接依赖 Provider parser；新增 UI 边界测试和关键双语测试 | 保留现有 typed key + localizedText；保留迁移 typealias 和已有边界护栏，不为删除几行引入广泛引用改动 |
| E1 限流 | Retry-After 秒数/HTTP-date 经 typed error、fallback、部分渠道结果传入调度；多渠道保留最大 deadline；区分取消/离线/timeout | 合法/非法/过去/不可表达时间、429、多渠道失败、调度测试；不任意截短服务端期限，手工 force 保留原有明确语义 |
| E2 参数/重型扫描 | 生成 1k/10k 文件指纹样例；默认并发与 jitter 不变 | 没有 p95/CPU/能耗/RSS 对比证据；50k 压力、增量索引、SQL 下推不作为本轮已完成内容 |

Cursor 的本地回退/部分 dashboard 结果会显示“数据可能不完整，仅供趋势参考”的双语提示，而不是完整成功；取消结果不发布为健康数据。统计用 typed `isPartial`，不再靠中文诊断子串决定缓存有效性。cc-switch 缺失与读取失败分别处理：未安装是正常可选来源缺失，读取失败是 partial。

## 3. 关键回归问题

集成期间发现并修正的新增竞态也纳入测试，而非只验证初始报告：

- 内存索引掩盖磁盘损坏/未知版本：显式读取重新验证磁盘，内部保存使用串行索引。
- reset 删除吞掉 reset 后的新写：generation 与 drain fence 保持先后边界。
- official cache 失效发生于检查之后、actor 存储之前：条目携带 load epoch，拒绝延迟旧存储。
- 凭据变化期间旧请求晚到：刷新 revision 守护快照、错误、持久化和通知。
- 移除 A 时异步恢复尚未完成：恢复 tombstone 只过滤 A，保留 B/C 暖缓存，再写合并结果。
- raw cache 重置延迟清理：独立短锁 epoch 即时失效，scanner 不阻塞 MainActor。
- 多渠道首个普通错误掩盖后续限流：独立聚合最大服务端 deadline。
- 较新 revision 在系统时钟回拨时被旧 savedAt 拒绝：生产以 revision 为顺序依据。

## 4. 验证

最终集中验证（2026-10-09）：

- 全量 XCTest **1,326 项通过，0 失败**，执行约 46.65 秒；相对方案记录的 1,277 项基线新增 49 项。不是把测试项数当作性能提升证据。
- 独立 debug `swift build` 成功；没有验证 release/DMG/签名/公证。
- `git diff --check` 通过；两份优化文档本地链接检查通过。
- 最终日志：`/tmp/omu-integration-test.log`、`/tmp/omu-integration-build.log`。
- 工程原有编译警告没有批量清理；本轮未更改范围外文件来消除警告。

验证入口不更改全局 `xcode-select`：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --build-system native --scratch-path /tmp/omu-integration-build

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift build --build-system native --scratch-path /tmp/omu-integration-build
```

本机 native SwiftPM 后端已弃用，本轮仅作为完整 Xcode 工具链的临时验证路径，不修改 Package/CI，也不声称默认后端的资源签名环境问题已经修复。

已生成并逐张查看菜单中英文、认证失效/限流、旧缓存/长名称，以及设置详情凭据收起/展开截图。截图位置为 `/tmp/omu-visual/`，使用占位账号和缓存；不是线上真实账号截图。可见场景没有发现本轮造成的布局破坏；既有设置字段截断不在此作“全面视觉合格”断言。

应用菜单自身固定暗色及宽度，向它注入 light/narrow 得到相同截图，因此没有把该无效用例计为明暗/窄窗口验收。未完成已安装 App 的真实滚动、拖拽、权限弹窗、账号切换、登录、退出重启、更新安装交互验收。

生成指纹样例在最终集中测试中，1k 文件单次 0.0504 秒，10k 单次 0.5165 秒（本轮多次运行约 0.50–0.58 秒）。它只说明当前实现的样例成本，不是旧版对照、p95、启动/UI/能耗收益；不同磁盘缓存、并行负载会影响结果。原始日志未复制到基准 fixture。

## 5. 保留的后续范围

- 其他 Provider 的 source inventory 共享是渐进适配器迁移，正确性修复已覆盖其 metadata/WAL/有界真实重读，但没有消除全部重复枚举。
- Cursor single-flight 只合并完全相同时间范围与身份的请求；独立捕获的 `until` 不同可能不合并，不改变时间语义来制造命中率。
- 大规模启动/设置页 trace、50k 文件压力、RSS、CPU/唤醒/能耗和真实交互尚未测量，不为参数调优作背书。
- 通用 OAuth/凭据拆分、全量 string catalog 和 migration alias 删除继续保留既有边界，不是本轮重写目标。
- 没有真实 Provider 请求证明接口契约与线上成功率；测试全绿不替代真实账号发布前验收。

本轮改动未提交，回退/拆分可按独立工作包进行；不得借此重置用户工作区或清理应用原始日志。

## 6. 2.5.4 发布前补充

用户随后授权提交推送、更新 README 与发布 `v2.5.4`。`VERSION` 更新至 2.5.4，中英文 README 同步本版说明；Release workflow 优先读取 `docs/releases/v2.5.4.md`，资产与更新 manifest 继续由既有 CI 流程生成。

- 发布前重跑全量 1,326 项测试通过，0 失败（约 45.47 秒）。
- 本地 2.5.4 通用 Release 打包通过；DMG 校验、挂载后的签名、版本、Bundle ID 与双架构检查通过。
- 修正上一版远端 CI 暴露的短墙钟模拟退出测试，将该 fixture 改为确定性状态切换；不修改生产退出逻辑。
- 打包仅跳过 Finder DMG 窗口美化，产物内容不受影响；本地构建为 ad-hoc，未公证。
- 当前安装 App 仍为此前覆盖安装的 2.5.3；本次发布操作不额外覆盖本机安装。

上述为本地发布门槛，不代表远端 CI 或 Release 已成功；远端结果以实际工作流与下载资产复核为准。
