# Architecture Debt Reduction 实现计划

> **不要 git commit，除非用户明确要求。**

**目标：** Providers 分层 + Catalog 去重 + AppViewModel facades + 分层补齐 — 已基本收口。

---

## 阶段 1：Providers — DONE
- [x] Batch A：Core runtime/工具迁入 OhMyUsageProviders
- [x] Batch B：Shell/JSON/SQLite 端口 + Official 注入
- [x] Batch C：Token/Browser/Kimi cookie/BrowserCredential 端口
- [x] Relay/Trae/Claude/Kimi/Codex/OpenRouter/Ollama/OpenCodeGo 端口化
- [ ] 整文件迁入 Providers（仍受 ProviderDescriptor 留 executable 阻塞）

## 阶段 3：Catalog — DONE
- [x] 图标 / 默认列表 / CatalogFacades

## 阶段 2：AppViewModel — DONE（物理 store 迁出 Observation 风险项已用写入口收口替代）
- [x] Update / Permission / Analytics / OfficialProfiles / Refresh / Configuration facades
- [x] StatusBar 偏好进 ConfigurationModel
- [x] OfficialProfiles display/lifecycle 迁出；+OfficialProfiles / +ProviderConfiguration 薄转发
- [x] ProviderStateStore **写入口**唯一化到 RefreshModel + 架构护栏
- [x] 全局设置薄转发迁入 `+ProviderConfiguration`（language / resourceMode / launchAtLogin / refreshInterval）

## 阶段 4 / Bootstrap — DONE（策略 A）
- [x] Application/Infra/Presentation 首批
- [x] `AppCompositionFactory` / `AppDependencyGraph` 收口 VM 服务树组装

## 架构护栏（收尾）— DONE
- [x] 非 executable 层不得引用 `AppCompositionFactory` / `AppDependencyGraph`
- [x] ProviderConfiguration 职责守卫覆盖全局设置与 persist/reset 转发

## 稳定性
- [x] KimiLocalUsage 挂起防御
- [x] Persistence auto-clear：wall-clock deadline + reconcile（抗 MainActor 饿死）
- [x] ProviderRefreshScheduler：替换/deinit 时取消 poll loop，避免测试间泄漏

## 已知阻塞
- ProviderDescriptor 整文件迁入 Providers（边界测试要求 Descriptor 留 executable）

---

## 验收
```bash
swift build
swift test
# 护栏子集：
swift test --filter 'ArchitectureTargetBoundaryTests|MonolithRetirementBoundaryTests'
```

**最新验收（2026-08-11）：**
- Persistence：deadline + reconcile + `clearGeneration` + 离 MainActor sleep
- 全量 `swift test` → **933 tests, 0 failures**
