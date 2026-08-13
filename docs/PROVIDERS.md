# Supported Services

This page summarizes what oh-myusage can currently monitor and how each service is typically connected.

For extension and integration paths after the refactor, see [EXTENDING.md](./EXTENDING.md).

## Official Providers

| Provider | Typical Source | Notes |
| --- | --- | --- |
| Codex | local desktop auth + web/API overlays | Supports multiple desktop accounts and local switching |
| Claude | API, CLI, or web session depending on mode | Web overlays can enrich usage windows |
| Gemini | official API/web quota data | Supports model-specific windows |
| GitHub Copilot | local GitHub auth | Reads Copilot usage and quota state |
| Cursor | official/local session data | Monthly and on-demand usage |
| Windsurf | official API | Daily and weekly windows |
| Grok | local Grok CLI auth (`~/.grok/auth.json`) | Weekly shared pool, plan name, and pay-as-you-go cap |
| Kimi | official API | Session and overall usage |
| Amp | official API | Free and credit views |
| Z.ai | official API | Session, weekly, and web usage |
| JetBrains AI | local data | Local XML usage parsing |
| Kiro | CLI/local output | Credit-based usage |
| OpenCode Go | opencode.ai web usage + local sqlite fallback | Remote truth first with local fallback when remote fails |

## Third-Party Relay Templates

Known templates reduce setup friction by hiding endpoint and parser details behind validated presets.

| Template | Typical Credential | Extra Field |
| --- | --- | --- |
| `open.ailinyu.de` | Cookie | optional user ID override |
| `platform.moonshot.cn` | Bearer or Cookie | auto-resolves org context |
| `platform.xiaomimimo.com` | Cookie | none |
| `platform.minimaxi.com` | Cookie | `GroupId` |
| `hongmacc.com` | Bearer | none |
| `platform.deepseek.com` | Bearer | none |
| `dragoncode.codes` | relay token | support is still evolving |
| generic New API | Bearer or Cookie | depends on the site |

## Relay Credential Modes

Relay sites can use one of three credential strategies:

- `Manual Preferred`
  Saved token or cookie first, browser-derived credentials as fallback.

- `Browser Preferred`
  Browser-derived credentials first, saved token or cookie as fallback.

- `Browser Only`
  Use browser state only and ignore saved credentials.

## Diagnostic States

For relay providers, the app classifies fetch failures into stable user-facing states:

- auth expired
- rate limited
- endpoint misconfigured
- unreachable

This makes it easier to tell the difference between:
- a bad token
- a changed site response
- a temporary network problem

## Notes on Third-Party Coverage

Third-party sites change more often than official APIs. oh-myusage tries to keep them stable through:

- per-site templates
- browser-first credential fallback
- dynamic parameter detection
- clearer user-facing diagnostics

If a relay changes its payload or auth flow, it may need a template update.

## Integration Notes

- Official profile monitoring now reuses the shared runtime seams:
  - [OfficialProviderFetchRuntime.swift](../Sources/OhMyUsage/Providers/OfficialProviderFetchRuntime.swift)
  - [OfficialProviderAuthRuntime.swift](../Sources/OhMyUsage/Providers/OfficialProviderAuthRuntime.swift)
  - [OfficialProfileSnapshotRuntime.swift](../Sources/OhMyUsage/Services/OfficialProfileSnapshotRuntime.swift)
- Relay and official display-layer metadata now flow through typed helpers instead of scattered `rawMeta` lookups:
  - [RelaySnapshotDisplayMetadata.swift](../Sources/OhMyUsage/Models/RelaySnapshotDisplayMetadata.swift)
  - [OfficialSnapshotIdentityMetadata.swift](../Sources/OhMyUsage/Models/OfficialSnapshotIdentityMetadata.swift)
- For new provider onboarding after the refactor, prefer [EXTENDING.md](./EXTENDING.md) as the source of truth for UI/app integration seams.
