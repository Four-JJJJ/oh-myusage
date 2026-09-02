# 未签名构建安装说明（INSTALL_UNSIGNED）

本页面说明如何安装和升级通过 GitHub Releases 分发、**未经 Apple Developer ID 签名且未公证（notarize）** 的 oh-myusage 构建。适用范围：默认的 ad-hoc 签名构建，以及使用本地自签名证书（`LOCAL_CODESIGN_IDENTITY`）的构建。

先说结论，避免误解：

- **自签名不等于 Developer ID。** 本地自签名证书只是给 bundle 一个稳定一点的代码签名，不会被 macOS 视为受信任的开发者。
- **自签名和 ad-hoc 都不能消除 Gatekeeper 首次打开提示。** 每台新 Mac 上首次启动仍需按下面步骤手动放行。
- **本构建未经过 Apple 公证（notarization）。** 除非未来改用 Developer ID 签名并完成公证，否则始终如此；打包脚本在无 Developer ID 时不会执行公证，也不会输出"已公证"字样。

## 为什么会有 Gatekeeper 提示

macOS Gatekeeper 会检查应用的代码签名和公证状态。GitHub 分发的构建没有 Developer ID 签名，Apple 无法据此确认"这个应用来自某个已知的开发者、且未经篡改"，因此首次打开会被拦截，提示类似"无法打开，因为无法验证开发者"或"macOS 无法验证此 App 不包含恶意软件"。

这是签名机制按设计工作的表现，**不代表文件一定有问题，也不代表文件一定安全**：请只从本项目的 GitHub Releases 页面下载，并通过下面的 SHA-256 校验确认文件完整。

## 首次打开方法

按顺序尝试：

1. 将 `oh-myusage.app` 拖入 `Applications` 文件夹（不要从 DMG 内直接启动）。
2. 在"应用程序"文件夹中**右键** `oh-myusage.app`，选择"打开"，在弹出的对话框中再点"打开"。这一步只需做一次。

如果系统仍然拦截：

1. 打开"系统设置"（macOS 13+）或"系统偏好设置"（更早版本）
2. 进入"隐私与安全性"
3. 在页面底部找到关于 `oh-myusage` 被阻止的提示，点击"仍要打开"

极少数情况下仍无法启动，可以在终端移除隔离属性后再启动：

```bash
xattr -dr com.apple.quarantine "/Applications/oh-myusage.app"
```

更多排障步骤见 [DOWNLOAD.md](DOWNLOAD.md)。

## SHA-256 校验方法

每个 Release 会附带 `SHA256SUMS.txt`，其中包含 `oh-myusage.dmg` 和 `oh-myusage-macOS.zip` 的 SHA-256 摘要（`shasum -a 256` 输出格式：摘要 + 两个空格 + 文件名）。

下载后在本机计算并比对：

```bash
shasum -a 256 ~/Downloads/oh-myusage.dmg
shasum -a 256 ~/Downloads/oh-myusage-macOS.zip
```

输出的第一段 64 位十六进制字符串应与 `SHA256SUMS.txt` 中对应行完全一致；也可以把 `SHA256SUMS.txt` 与下载文件放在同一目录，执行：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

注意：SHA-256 只能确认"下载内容与发布时一致"，不能证明"发布内容本身可信"。校验值的可信度取决于你获取 `SHA256SUMS.txt` 的渠道（GitHub Release 页面）。

## 升级后可能需要重新确认 Keychain 访问

这是 ad-hoc / 自签名分发的**固有行为**，请知悉：

- ad-hoc 签名的代码签名哈希随每次构建变化，自签名证书也无法提供与 Developer ID 同等稳定的代码主体标识。因此覆盖升级后，macOS 可能把新版视为**不同的代码主体**。
- 表现为：升级后首次启动时，系统可能再次弹出 Keychain（钥匙串）访问确认，应用也可能暂时读不到已保存的凭证，需要你重新允许访问或重新输入一次 Token / Cookie。
- 已保存的钥匙串条目本身不会丢失；重新授权后通常即可恢复读取。如确实无法恢复，在应用设置里重新保存对应凭证即可。
- 应用使用固定的 Bundle ID（`com.oh-myusage.app`），不随版本变化，这能减少设置与数据迁移问题，但不能完全消除上述签名层面的重新确认。

## 其他说明

- 本应用仅支持 macOS 14 及以上版本，通过 GitHub Releases 分发，非 App Store 安装包。
- 如需从源码构建，见仓库 `README.md` 的"从源码运行"章节。
