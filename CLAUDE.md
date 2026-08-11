# Repository Guidelines

## Project Structure & Module Organization
`OhMyUsage` is a Swift Package for a macOS menu bar app. Main code lives in `Sources/OhMyUsage`, split by responsibility:
- `App/` for app lifecycle and window/status bar wiring
- `UI/` for SwiftUI views
- `Providers/` for provider-specific integrations
- `Services/`, `Models/`, and `Utils/` for shared logic
- `Resources/` for icons and bundled relay adapter JSON files

Tests live in `Tests/OhMyUsageTests` and mirror production types, for example `CodexProvider.swift` with `CodexLocalUsageServiceTests.swift`. Supporting docs are in `docs/`, and release/packaging scripts are in `scripts/`.

## Build, Test, and Development Commands
- `swift build` builds the executable target for local verification.
- `swift run` launches the app from source on macOS 14+.
- `swift test` runs the XCTest suite in `Tests/OhMyUsageTests`.
- `./scripts/package_dmg.sh` builds a distributable DMG into `dist/`.

Use `VERSION` for release versioning. Packaging supports ad-hoc signing by default and Developer ID/notarization through environment variables consumed by `scripts/package_dmg.sh`.

## Coding Style & Naming Conventions
Follow existing Swift conventions: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and one primary type per file named after that type. Keep provider-specific code in `Providers/` and shared behavior in `Services/` or `Utils/`.

No formatter or linter is configured in this repo, so match the surrounding style and rely on Xcode/SwiftPM defaults. Prefer small, explicit methods and XCTest-friendly seams for services.

## Testing Guidelines
Write tests with XCTest using `final class ...Tests: XCTestCase` and `test...` method names. Add or update tests whenever changing provider parsing, config defaults, credential handling, or countdown/quota logic. Run `swift test` before opening a PR.

## Commit & Pull Request Guidelines
Recent history mixes concise imperative messages (`Fix update detection and menubar update badge`) with scoped prefixes (`feat:`, `chore:`, `release:`). Keep commits short, specific, and focused on one change.

PRs should include:
- a brief summary of user-visible behavior
- linked issue or context when applicable
- screenshots for menu bar or settings UI changes
- notes on new config, auth, signing, or packaging behavior
