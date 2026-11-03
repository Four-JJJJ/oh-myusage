# Extending The App

This guide records the post-refactor integration path for three common changes:

- adding a new official provider
- adding a new relay template
- adding a new settings item

The goal is to keep future work on the extracted seams instead of pushing logic back into `AppViewModel.swift`, `SettingsView.swift`, or `RelayProvider.swift`.

## Add A New Official Provider

Per-type facts live in one `ProviderModule` per provider under
[Sources/OhMyUsage/Providers/Modules](../Sources/OhMyUsage/Providers/Modules). The catalogs and
registries (`ProviderTypeMetadataCatalog`, `OfficialProviderDefaultCatalog`, `ProviderDefaultCatalog`,
`ProviderFetchPlanRegistry`, `ProviderFactoryRegistry`) look the type up in
[ProviderModuleRegistry.swift](../Sources/OhMyUsage/Providers/Modules/ProviderModuleRegistry.swift)
instead of keeping their own switch or dictionary, so they do not need editing.

### 1. Add the provider type and its module

- Add the case to [ProviderType.swift](../Sources/OhMyUsageDomain/ProviderType.swift).
- Create `Sources/OhMyUsage/Providers/Modules/ProviderModule+<Name>.swift` declaring
  `extension ProviderModule { static let <name> = ProviderModule(...) }`, using
  [ProviderModule+Windsurf.swift](../Sources/OhMyUsage/Providers/Modules/ProviderModule+Windsurf.swift) as the minimal
  example. A module declares:
  - `metadata`: display name, icons, preferred metric count, capability flags (account switching,
    local usage history, bearer input), supported source/web modes, and presentation constants
    (`isPureBalance`, `planTypeDisplayStyle` — `nil` hides the plan type, `titlesSessionQuotaAsSession`);
  - `defaultBaseURL` and `defaultOfficialConfig` (defaults to `ProviderModule.standardOfficialConfig`);
  - `defaults`: `.official(id:name:pollIntervalSec:auth:)` for the built-in disabled descriptor
    (also returned by `OfficialProviderDefaultCatalog.descriptor(for:)`), `.custom` or `.none`;
  - `fetchPlan`: the `ProviderFetchPlan` request-cost policy, with a comment describing the requests;
  - `makeProvider`: how the runtime provider is constructed from `ProviderFactoryRegistry.Dependencies`;
  - optionally `migrateLegacyOfficialConfig` for a provider-specific config fix-up during normalization.
- Add the module to `ProviderModuleRegistry.allModules`. Its position is the provider's position in
  `AppConfig.default.providers`, so update the expected order in
  `MonolithRetirementBoundaryTests.testDefaultProviderCatalogPreservesDefaultOrderAndCredentialAccounts`.
- [ProviderModuleRegistryTests.swift](../Tests/OhMyUsageTests/ProviderModuleRegistryTests.swift) fails when a
  `ProviderType` has no module or more than one, so a missing entry never falls back to a default silently.
- Optionally add a `ProviderDescriptor.defaultOfficial<Name>()` convenience in
  [ProviderDescriptor+CatalogFacades.swift](../Sources/OhMyUsage/Models/ProviderDescriptor+CatalogFacades.swift)
  for tests; it should only forward to `OfficialProviderDefaultCatalog.descriptor(for:)`.
- If the provider has settings-specific capability flags, update [ProviderSettingsSpec.swift](../Sources/OhMyUsage/Models/ProviderSettingsSpec.swift).

### 2. Add per-provider presentation that is real logic

These switches stay outside the module because their branches are localized UI logic, not constants:

- Menu placeholder metrics shown before the first snapshot: `placeholderMetrics` in
  [MenuQuotaPresenter.swift](../Sources/OhMyUsage/UI/Presenters/MenuQuotaPresenter.swift)
  (exhaustive, so the compiler asks for a new case).
- Settings placeholder quota windows: `codexQuotaMetrics` in
  [SettingsQuotaDisplayHelpers.swift](../Sources/OhMyUsage/UI/Settings/SettingsQuotaDisplayHelpers.swift)
  (has a default five-hour/weekly placeholder).
- Account-switching providers (Codex, Claude) also need their profile stores and coordinators.

### 3. Implement the runtime

- Create the provider in `Sources/OhMyUsage/Providers/`.
- Reuse the shared official runtime pieces where possible:
  - [OfficialProviderFetchRuntime.swift](../Sources/OhMyUsage/Providers/OfficialProviderFetchRuntime.swift)
  - [OfficialProviderAuthRuntime.swift](../Sources/OhMyUsage/Providers/OfficialProviderAuthRuntime.swift)
  - [OfficialProviderWebOverlayRuntime.swift](../Sources/OhMyUsage/Providers/OfficialProviderWebOverlayRuntime.swift)
  - [OfficialSnapshotFallback.swift](../Sources/OhMyUsage/Providers/OfficialSnapshotFallback.swift)
- Keep provider-local code focused on:
  - request building
  - endpoint/auth specifics
  - response parsing
  - provider-only fallback rules

### 4. Wire app-state handling

- No factory edit is needed: [ProviderFactoryRegistry.swift](../Sources/OhMyUsage/Services/ProviderFactoryRegistry.swift)
  builds its makers from each module's `makeProvider`.
- If the provider needs special app-state handling for profile/session behavior, extend the extracted app coordinators before touching `AppViewModel`:
  - [AppProviderRefreshCoordinator.swift](../Sources/OhMyUsage/App/AppProviderRefreshCoordinator.swift)
  - [AppOfficialProfileRefreshCoordinator.swift](../Sources/OhMyUsage/App/AppOfficialProfileRefreshCoordinator.swift)
  - [AppOfficialProfileStateCoordinator.swift](../Sources/OhMyUsage/App/AppOfficialProfileStateCoordinator.swift)

### 5. Expose settings

- Extend [ProviderSettingsSpec.swift](../Sources/OhMyUsage/Models/ProviderSettingsSpec.swift) with supported source modes, web modes, and credential fields.
- Keep provider-detail UI in `Sources/OhMyUsage/UI/Settings/` instead of adding new branching directly to root settings composition.

### 6. Add tests

- Prefer provider fixture tests beside the provider file in `Tests/OhMyUsageTests/`.
- Add app-state tests if the provider changes refresh/fallback/account behavior.
- Run `swift build` and `swift test`.

## Add A New Relay Template

### 1. Add the adapter manifest

- Add a JSON manifest under [Sources/OhMyUsage/Resources/RelayAdapters](../Sources/OhMyUsage/Resources/RelayAdapters).
- The registry loads templates through [RelayAdapterRegistry.swift](../Sources/OhMyUsage/Services/RelayAdapterRegistry.swift).

### 2. Use the extracted relay seams

- Request/path resolution belongs in [RelayRequestResolver.swift](../Sources/OhMyUsage/Providers/RelayRequestResolver.swift).
- Credential selection belongs in [RelayCredentialResolver.swift](../Sources/OhMyUsage/Providers/RelayCredentialResolver.swift).
- Transport belongs in [RelayHTTPClient.swift](../Sources/OhMyUsage/Providers/RelayHTTPClient.swift).
- Token and balance execution belong in:
  - [RelayTokenChannelExecutor.swift](../Sources/OhMyUsage/Providers/RelayTokenChannelExecutor.swift)
  - [RelayBalanceChannelExecutor.swift](../Sources/OhMyUsage/Providers/RelayBalanceChannelExecutor.swift)
- Response parsing belongs in [RelayResponseInterpreter.swift](../Sources/OhMyUsage/Providers/RelayResponseInterpreter.swift).
- Recovery and browser retry policy belong in [RelayRecoveryPolicy.swift](../Sources/OhMyUsage/Providers/RelayRecoveryPolicy.swift).

`RelayProvider.swift` should remain an orchestration shell. New site-specific parsing or auth branches should not be added there first.

### 3. Expose it in settings

- Relay editor defaults and template seeding flow through [SettingsDraftModels.swift](../Sources/OhMyUsage/Models/SettingsDraftModels.swift).
- Relay-specific view state and presentation should stay in the extracted settings feature files under `Sources/OhMyUsage/UI/Settings/`.

### 4. Add tests

- Add or update relay fixture tests in [RelayProviderTests.swift](../Tests/OhMyUsageTests/RelayProviderTests.swift).
- If the manifest changes presenter output, add focused presenter tests instead of only broad end-to-end assertions.

## Add A New Settings Item

### 1. Add the persisted model field

- Add the field to [ProviderModels.swift](../Sources/OhMyUsage/Models/ProviderModels.swift) or the appropriate config model.
- If compatibility or migration is needed, extend [ConfigStore.swift](../Sources/OhMyUsage/Services/ConfigStore.swift).

### 2. Add draft/runtime state only when needed

- Draft/editing state belongs in [SettingsDraftModels.swift](../Sources/OhMyUsage/Models/SettingsDraftModels.swift).
- Avoid adding new scattered `@State [String: T]` collections to root settings composition.

### 3. Place UI in the extracted settings tree

- Root composition lives in:
  - [SettingsRootView.swift](../Sources/OhMyUsage/UI/Settings/SettingsRootView.swift)
  - [SettingsHeaderView.swift](../Sources/OhMyUsage/UI/Settings/SettingsHeaderView.swift)
  - [SettingsOverlayPresenter.swift](../Sources/OhMyUsage/UI/Settings/SettingsOverlayPresenter.swift)
  - [SettingsResetDialogView.swift](../Sources/OhMyUsage/UI/Settings/SettingsResetDialogView.swift)
  - [SettingsWorkspaceSidebarView.swift](../Sources/OhMyUsage/UI/Settings/SettingsWorkspaceSidebarView.swift)
  - [SettingsWorkspacePresentation.swift](../Sources/OhMyUsage/UI/Settings/SettingsWorkspacePresentation.swift)
  - [SettingsOverviewPresenter.swift](../Sources/OhMyUsage/UI/Presenters/SettingsOverviewPresenter.swift)
  - [SettingsTabContentView.swift](../Sources/OhMyUsage/UI/Settings/SettingsTabContentView.swift)
  - [SettingsPaneContainersView.swift](../Sources/OhMyUsage/UI/Settings/SettingsPaneContainersView.swift)
- Tab-specific screens live under `Sources/OhMyUsage/UI/Settings/`.
- Shared settings-only view primitives belong in [SettingsSharedTypes.swift](../Sources/OhMyUsage/UI/Settings/SettingsSharedTypes.swift) and [SettingsSharedHelpers.swift](../Sources/OhMyUsage/UI/Settings/SettingsSharedHelpers.swift) instead of the root facade file.
- Settings window lifecycle helpers belong in:
  - [SettingsWindowAppearanceController.swift](../Sources/OhMyUsage/UI/Settings/SettingsWindowAppearanceController.swift)
  - [VisibleClockController.swift](../Sources/OhMyUsageApplication/VisibleClockController.swift)
- Keep common presentation logic in presenters when it can be pure and tested.

### 4. Keep menu and status presentation on presenters

- Menu header copy belongs in [MenuDashboardPresenter.swift](../Sources/OhMyUsage/UI/Presenters/MenuDashboardPresenter.swift).
- Menu card status / plan / subtitle logic belongs in:
  - [MenuCardStatePresenter.swift](../Sources/OhMyUsage/UI/Presenters/MenuCardStatePresenter.swift)
  - [MenuCardStatusPresenter.swift](../Sources/OhMyUsage/UI/Presenters/MenuCardStatusPresenter.swift)
  - [MenuQuotaPresenter.swift](../Sources/OhMyUsage/UI/Presenters/MenuQuotaPresenter.swift)
  - [MenuSubtitlePresenter.swift](../Sources/OhMyUsage/UI/Presenters/MenuSubtitlePresenter.swift)
- Typed display metadata belongs in:
  - [RelaySnapshotDisplayMetadata.swift](../Sources/OhMyUsage/Models/RelaySnapshotDisplayMetadata.swift)
  - [OfficialSnapshotIdentityMetadata.swift](../Sources/OhMyUsage/Models/OfficialSnapshotIdentityMetadata.swift)
- Status-bar source selection and rendering input belong in:
  - [StatusBarDisplaySourceBuilder.swift](../Sources/OhMyUsage/UI/Presenters/StatusBarDisplaySourceBuilder.swift)
  - [StatusBarDisplayPresenter.swift](../Sources/OhMyUsage/UI/Presenters/StatusBarDisplayPresenter.swift)

### 5. Keep save/update flows on extracted seams

- App-level save and feedback logic belongs in:
  - [AppConfigurationRepository.swift](../Sources/OhMyUsage/Services/AppConfigurationRepository.swift)
  - [AppSessionStore.swift](../Sources/OhMyUsage/App/AppSessionStore.swift)
  - [AppTransientFeedbackCoordinator.swift](../Sources/OhMyUsage/App/AppTransientFeedbackCoordinator.swift)
  - [AppOfficialProfileDisplayCoordinator.swift](../Sources/OhMyUsage/App/AppOfficialProfileDisplayCoordinator.swift)
  - [AppOfficialProfileMenuPresenter.swift](../Sources/OhMyUsage/App/AppOfficialProfileMenuPresenter.swift)
  - [AppOfficialProfileRefreshCoordinator.swift](../Sources/OhMyUsage/App/AppOfficialProfileRefreshCoordinator.swift)
  - [AppViewModel.swift](../Sources/OhMyUsage/App/AppViewModel.swift) only as compatibility facade when no smaller seam exists yet

### 6. Add tests

- Draft behavior: [SettingsDraftModelsTests.swift](../Tests/OhMyUsageTests/SettingsDraftModelsTests.swift)
- Quota/presenter behavior: the focused presenter test next to the extracted presenter
- App save/feedback behavior: [AppViewModelConfigurationPersistenceTests.swift](../Tests/OhMyUsageTests/AppViewModelConfigurationPersistenceTests.swift)
- Presentation smoke coverage: [PresentationSmokeTests.swift](../Tests/OhMyUsageTests/PresentationSmokeTests.swift)

## Validation Checklist

For any of the changes above, the minimum ship gate is:

- `swift build`
- `swift test`
- focused tests for the new seam you touched
