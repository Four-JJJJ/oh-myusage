# oh-myusage

A macOS menu bar app for monitoring AI plan limits, credits, relay balances, and local desktop account state in one place.

[Download Latest Release](https://github.com/Four-JJJJ/oh-myusage/releases/latest) · [Install Guide](DOWNLOAD.md) · [Supported Services](PROVIDERS.md) · [中文说明](../README.md)

## V2.6.7

- The X Subscription included usage is one weekly pool shared by Grok, Cursor, and Grok Bot. All three cards show that same weekly remaining
- Cursor accounts on the unified plan read the weekly pool instead of the stale monthly Cursor Models / Other Models split. Third-party models are no longer shown as Other Models at 100%. Legacy monthly Cursor plans are unchanged
- Grok keeps `creditUsagePercent` as the weekly pool. Per-product figures are a breakdown of that pool, not extra quota bars, and a prepaid balance is shown when present
- Grok Bot uses the same weekly pool and shows the X Subscription tier (Plus / Premium / Super / Ultra) instead of the generic “Grok Bot Plan” label

All 1,500 tests pass. See the [release notes](releases/v2.6.7.md).

## V2.6.6

- Fix Cursor official quota failing entirely since late October: Cursor IDE now stores `cursorAuth/*` tokens encrypted with Electron safeStorage (`cursor-safe-storage:v1:`), so the app sent ciphertext as the session token, got 401, had its refresh rejected with `{"access_token":"","shouldLogout":true}`, and reported it as "Config Error / Invalid response: Cursor refresh failed"
- Add `CursorSafeStorage`: strips the prefix, base64-decodes, and decrypts through the existing safeStorage crypto with the `Cursor Safe Storage` keychain passphrase; plaintext tokens from older Cursor builds pass through untouched and never touch the keychain
- Classify Cursor's `shouldLogout` or empty-token refresh response as an auth error with a "sign in again in Cursor" hint instead of a configuration error
- Never write a plaintext token back into an encrypted `state.vscdb`; plaintext stores keep their previous write-back behavior
- An undecryptable credential now fails with an actionable message before any request is sent
- 11 new tests (6 decryptor, 5 provider); all 1,494 tests pass

Upgrading needs one keychain approval (Cursor's item only trusts Cursor.app); later overwrite installs do not ask again. See the [release notes](releases/v2.6.6.md).

## V2.6.1

- Session-cookie sites now renew themselves the same way: in Browser First or auto-import mode the app re-reads the browser every 30 minutes and swaps in a newer login before the saved cookie expires, then leaves the browser alone until the window opens again
- Covers Xiaomi MIMO, MiniMax, Ailinyu and the other cookie-based relays, plus Qwen, Ollama, OpenCode Go, and the web modes of Codex and Claude; a browser with nothing newer keeps the saved cookie working
- A rejected credential is retried against the browser immediately, and the wait after a browser with no login is unified to 1 minute, including Trae
- Manual First and pasted credentials are unchanged and are never replaced; generic relay templates that also accept an API key are not rotated, so a background read cannot overwrite a key you pasted
- In-app updates no longer stay on “Installing and restarting”; after install the app returns to the menu bar and does not open a release-notes window

Renewal needs the site to stay logged in inside a Chromium browser (Chrome, Arc, Edge); Safari and Firefox logins cannot be read. API keys and logins stored inside another app's own data (Windsurf, Amp, JetBrains, Kiro) still need manual action. See the [release notes](releases/v2.6.1.md).

## V2.6.0

- Merge credential writes against the persisted vault under a shared in-process transaction; preserve previous credentials on failure and prevent deleted legacy entries from migrating back
- Archive corrupt configuration bytes before replacement; ordinary saves and later launches preserve the archive for manual recovery
- Create profile files with 0600 permissions and private atomic replacement; tighten existing files and reject symbolic-link and hard-link targets
- Propagate refresh cancellation to background workers, suppress stale results, remove the persistent window-scan timer, and reuse Grok/Gemini enumeration caches
- Unify subscription and API sources under Official Services, label API entries by name, and present account, plan-quota, or balance details appropriate to each source
- Localize statistics headings, metrics, options, empty states, and month labels; provide checkout-isolated build commands and enforce production-source warning checks before release
- Use a controllable clock in persistence-feedback tests to remove CI scheduling-dependent failures; cover duplicate saves, cancelled timers, and delayed-task reconciliation without changing the app's default timing behavior

All 1,382 local tests pass, including 20 consecutive runs of the 12 persistence-feedback tests, and the production-source warnings-as-errors build passes. Universal Release compilation also passed earlier in this release cycle. Final DMG, signing, notarization, and upgrade-installation validation follow the actual Release and acceptance record; real-account flows require separate acceptance. Profiles remain plaintext accessible to the same user; credential transactions do not provide cross-process concurrency guarantees. No unmeasured performance or energy saving is claimed.

See the [release notes](releases/v2.6.0.md) and [repair validation record](OPTIMIZATION_REPAIRS_2026-10-17.md).

## V2.5.4

- Fix Cursor pagination using raw page lengths; disclose partial results and local fallback, including cc-switch read failures
- Detect SQLite WAL and per-file changes; preserve the last successful refresh time and usable charts after failures
- Move display-cache I/O to ordered background queues, cancel obsolete workers, reuse bounded short-lived raw statistics, and bound official cache size and stale age
- Prevent late requests and out-of-order writes from restoring old account data after credential changes, removal, or reset; handle clock reversal safely
- Respect server `Retry-After` deadlines in background scheduling and preserve the latest deadline across relay channels
- All 1,326 local tests pass; no measured startup, CPU, memory, or energy improvement percentage is claimed, and default refresh concurrency remains unchanged

See the [implementation and validation record](OPTIMIZATION_IMPLEMENTATION_2026-10-09.md) for scope and remaining verification limits.

## V2.5.3

- Show relay token-plan expiry as a countdown instead of an absolute date

## V2.5.2

- Make plan names readable across official providers: map `PLAN_` / `LEVEL_` codes to Plus, Pro, SuperGrok, and Kimi music-term tiers; hide placeholders such as `unknown`
- Add a generic Sub2API relay template for group API keys and `/v1/usage`
- Show a 24-hour trend chart in local usage history

## V2.5.1

- Add official Grok Bot usage from the Grok Bot desktop app or Cursor session
- Keep the menu bar provider order in sync with the settings list
- Show subscription plan tiers (Pro, Ultra, SuperGrok, and similar) on cards that already expose that metadata

## What It Is

oh-myusage solves a simple but annoying problem: AI usage and balance information is scattered everywhere.

- official products expose quotas in different formats
- relay sites often require custom cookies, bearer tokens, account IDs, group IDs, or org IDs
- local desktop usage is frequently unavailable through public dashboards

This project brings those signals into one macOS menu bar app so you can quickly check:

- which official plan is running low
- when session, 5-hour, weekly, or monthly windows reset
- which relay balance is about to run out
- which credential has expired
- which Codex desktop account is currently active

## Why It Stands Out

### 1. Official and third-party monitoring in one app

The app is not limited to a single official provider or a single OpenAI-style billing endpoint. It combines both official products and relay sites into one menu bar experience.

Official coverage currently includes:
- Codex
- Claude
- Gemini
- GitHub Copilot
- Cursor
- Grok Bot
- Windsurf
- Grok
- Kimi
- Amp
- Z.ai
- JetBrains AI
- Kiro

### 2. Template-driven relay setup

For validated relay sites, users do not need to understand endpoint paths, field mappings, or parser expressions. The app exposes only the fields that actually need user input.

Built-in templates currently include:
- `open.ailinyu.de`
- `platform.moonshot.cn`
- `platform.xiaomimimo.com`
- `platform.minimaxi.com`
- `hongmacc.com`
- `platform.deepseek.com`
- `dragoncode.codes`
- generic New API compatible sites
- generic Sub2API compatible sites

### 3. Practical credential modes

In addition to manually saved tokens and cookies, relay providers support:
- manual preferred
- browser preferred
- browser only

This makes the app much more practical for sites whose credentials expire often.

### 4. Better diagnostics

Instead of collapsing most failures into one generic error, the app tries to distinguish between:
- expired auth
- rate limiting
- endpoint mismatch
- network or reachability issues

This is especially useful for relay integrations.

### 5. Codex local multi-account switching

One of the more distinctive features is local Codex desktop account switching.

The app supports:
- capturing the current local Codex `auth.json`
- importing multiple Codex desktop accounts
- switching the local desktop account from the menu bar
- keeping inactive account reset windows visible

## Core Features

- Per-provider enable and disable
- Per-provider low-balance thresholds
- Menu bar pinning for a selected provider
- Low balance alerts
- Auth error alerts
- Repeated failure alerts
- Launch at login
- Real-time menu bar quota and reset display
- Template-driven relay setup
- Codex multi-account import and switching

## Installation

1. Download the latest `oh-myusage.dmg` from [Releases](https://github.com/Four-JJJJ/oh-myusage/releases/latest)
2. Open the DMG
3. Drag `oh-myusage.app` into `Applications`
4. On first launch, right-click the app and choose `Open`
5. If macOS blocks the app, allow it in `System Settings -> Privacy & Security`

For step-by-step instructions, see [Install Guide](DOWNLOAD.md).

## Security

- Credentials saved from settings are stored in macOS Keychain by default
- Legacy `OhMyUsage` keychain entries are migrated to `oh-myusage`
- App configuration is stored under `~/Library/Application Support/OhMyUsage`
- Browser-derived credentials can be used as fallback for supported relay sites

## Build From Source

Requirements:
- macOS 14+
- Xcode / Swift 6 toolchain

Run locally:

```bash
swift run
```

Build a universal DMG:

```bash
./scripts/package_dmg.sh
```

## Distribution Notes

- Public builds are currently distributed through GitHub Releases, not the App Store
- Unsigned or ad-hoc builds may require `right click -> Open` on first launch
- The packaging script already supports Developer ID signing and notarization when Apple credentials are provided

## Roadmap

- more validated relay templates
- richer release automation
- better provider diagnostics
- smoother first-run UX for non-technical users

## License

MIT. See [LICENSE](../LICENSE).
