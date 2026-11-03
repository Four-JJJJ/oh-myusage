# Release Checklist

This checklist is the pre-push and release gate for `oh-myusage`. It should be completed from the release branch before creating or dispatching a `v*` release.

## 1. Version And Scope

- Confirm the release version uses `vX.Y.Z` tag format. The release workflow also accepts `X.Y.Z` through manual dispatch and normalizes it to `vX.Y.Z`.
- Confirm `VERSION` matches the intended app version before local packaging. The GitHub release workflow rewrites `VERSION` from the tag or workflow input during CI.
- Confirm release notes and README user-facing copy describe the version being shipped.
- Confirm `git status --short` only contains intentional changes, especially after the `AIPlanMonitor` to `OhMyUsage` rename.

## 2. Update Source And Repository

- Confirm the canonical repository is `Four-JJJJ/oh-myusage`.
- Confirm update detection points at `https://github.com/Four-JJJJ/oh-myusage/releases/latest/download/latest.json` through [AppUpdateService.swift](../Sources/OhMyUsage/Services/AppUpdateService.swift), with the legacy `AI-Plan-Monitor` endpoint kept as a compatibility fallback for 1.x clients.
- If the old repository or old release URL remains public, add a redirect notice there before announcing the release.
- If update metadata was ever hosted elsewhere, verify that source now redirects users to the GitHub Release for `oh-myusage`.

## 3. Build And Test Gate

- Run `swift build`.
- Run `swift test`.
- Run `APP_VERSION=<version> ./scripts/package_dmg.sh` for a local packaging smoke test.
- Confirm the generated artifacts exist:
  - `dist/oh-myusage.dmg`
  - `dist/oh-myusage-macOS.zip`
- Mount the DMG locally and verify the app bundle, Applications symlink, and install guide are present.

## 4. Signing And Notarization

- For a public unsigned or ad-hoc build, confirm the install guide and `docs/DOWNLOAD.md` still explain first-launch Gatekeeper handling.
- For a Developer ID build, provide `DEVELOPER_ID_APPLICATION` or `CODESIGN_IDENTITY` before running the packaging script.
- For notarization, set one supported credential path:
  - `NOTARYTOOL_PROFILE`
  - `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`
  - `APPLE_API_KEY_PATH`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER_ID`
- Set `NOTARIZE_DMG=1` when notarization is required but credentials might not be auto-detected.
- Verify `codesign --verify` and notarization/stapling output from [package_dmg.sh](../scripts/package_dmg.sh) before publishing.

## 5. latest.json Manifest

- Let `.github/workflows/release.yml` generate `dist/latest.json`; do not hand-edit the manifest for a normal release.
- Confirm the manifest contains:
  - `version` matching the release version without the leading `v`
  - UTC `pub_date`
  - `release_url` and `notes_url` pointing to the release tag
  - `assets.macos_zip.url`, `sha256`, and `size`
  - `assets.macos_dmg.url`, `sha256`, and `size`
- Confirm the workflow `Validate update manifest` step passes before announcing the release.

### Manifest signature (Ed25519)

The app verifies a detached `latest.json.sig` once `Sources/OhMyUsage/Resources/update_signing_public_key.txt` holds a key. While the file is empty, verification is off and the workflow publishes an unsigned manifest.

One-time provisioning:

1. `swift scripts/update_signing.swift generate` prints a private key and a public key.
2. Store the private key as the repository secret `UPDATE_SIGNING_PRIVATE_KEY`. Keep an offline backup; never commit it.
3. Commit the public key into `update_signing_public_key.txt` and ship it in the next release.

After that, the `Sign update manifest` step fails the release if the secret is missing, so a release can never strand users on a version that rejects unsigned manifests. Losing the private key means shipping a new public key through a release signed with the old one, so keep the backup.

## 6. Publish

- Prefer pushing a signed or reviewed tag like `v2.0.0`, or use the `Release` workflow manual dispatch with the same version.
- Confirm the GitHub Release includes:
  - `latest.json`
  - `oh-myusage.dmg`
  - `oh-myusage-macOS.zip`
- Confirm generated release notes do not mention stale `AI Plan Monitor` asset names unless they are explicitly part of migration notes.

## 7. Post-Release Verification

- Open `https://github.com/Four-JJJJ/oh-myusage/releases/latest` and confirm it resolves to the expected tag.
- Download `latest.json` from the current and legacy latest-release endpoints, then verify both asset URLs return `200`.
- Download the DMG from the latest release, install it into `Applications`, and launch it on macOS 14 or newer.
- In the app, verify the update screen sees the current version as latest and links back to the same release.
- Verify at least one official provider and one relay provider still render expected menu states from existing saved config or test credentials.

## 8. Rollback

- If the release is broken before broad announcement, delete or mark the GitHub Release as draft and remove the bad tag only after confirming no users rely on it.
- If users may already have installed it, publish a patch tag instead of rewriting history.
- Re-upload `latest.json`, DMG, and ZIP for the last known good version only when intentionally rolling the update source back.
- Leave a release note explaining the rollback reason and the next safe upgrade path.
