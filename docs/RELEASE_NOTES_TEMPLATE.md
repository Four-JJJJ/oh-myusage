# Release Notes 模板

仓库没有单独的 CHANGELOG 文件。GitHub Release 正文由 `.github/workflows/release.yml` 在发布时以本模板为骨架自动渲染（版本号、构建 commit、SHA-256 与资产链接会被替换为真实值，"本版变更"由 GitHub 提交摘要填充），确保以下必含项齐全（对应优化文档 11.5）：

- 版本号
- 构建 commit
- 各产物 SHA-256（与 `SHA256SUMS.txt` 一致）
- 未公证（notarize）说明
- 首次打开方法
- 升级后可能再次出现 Keychain 确认的说明

占位符用 `<...>` 标注，发布前删除本提示段落。

---

## oh-myusage <version>（如 2.1.0）

**版本号**：`<X.Y.Z>`（tag `v<X.Y.Z>`，与 `VERSION` 一致）

**构建 commit**：`<full-or-short-commit-hash>`（分支 `<branch>`）

**下载**：

- [oh-myusage.dmg](<release-asset-url>) — 推荐
- [oh-myusage-macOS.zip](<release-asset-url>)
- [SHA256SUMS.txt](<release-asset-url>)

**SHA-256**（与 `SHA256SUMS.txt` 一致，可用 `shasum -a 256 -c SHA256SUMS.txt` 校验）：

```text
<digest>  oh-myusage.dmg
<digest>  oh-myusage-macOS.zip
```

**签名与公证说明（重要，请勿删除或改写为"已公证"）**：

- 本构建使用 ad-hoc / 自签名代码签名，**未使用 Apple Developer ID 签名，也未经过 Apple 公证（notarization）**。
- 自签名不等于 Developer ID，不能消除 Gatekeeper 首次打开提示。

**首次打开方法**：

1. 将 `oh-myusage.app` 拖入 `Applications`（不要从 DMG 内直接启动）。
2. 右键 `oh-myusage.app` 选择"打开"，在弹窗中再点"打开"（仅需一次）。
3. 如仍被拦截：打开"系统设置 -> 隐私与安全性"，点击"仍要打开"。

详见 [docs/INSTALL_UNSIGNED.md](../docs/INSTALL_UNSIGNED.md)。

**升级说明（Keychain）**：

- 覆盖升级后，macOS 可能将新版视为不同的代码主体（ad-hoc / 自签名构建的固有行为），再次弹出钥匙串（Keychain）访问确认，已保存的凭证可能需要重新授权或重新输入一次。
- 钥匙串条目本身不会丢失；如无法恢复读取，在设置中重新保存对应凭证即可。

**本版变更**：

- <变更要点，逐条列出>

**已知问题**：

- <如有则列出；没有则删除本节>
