import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class SettingsDraftModelsTests: XCTestCase {
    func testSettingsNavigationStateDefaultsToUsageAnalyticsTab() {
        let state = SettingsNavigationState()

        XCTAssertEqual(state.selectedSettingsTab, .usageAnalytics)
    }

    func testSettingsNavigationStateKeepsProviderSelectionInSync() {
        var state = SettingsNavigationState()

        state.selectTab(.customProviders)
        XCTAssertEqual(state.selectedSettingsTab, .customProviders)
        XCTAssertEqual(state.selectedGroup, .thirdParty)

        state.selectGroup(.official)
        XCTAssertEqual(state.selectedGroup, .official)
        XCTAssertEqual(state.selectedSettingsTab, .officialProviders)

        state.draggingProviderID = "relay.demo"
        state.reorderPreviewProviderIDs = ["relay.demo"]
        state.dropTargetProviderID = "relay.demo"
        state.dropTargetInsertAfter = true
        state.clearProviderReorderingState()

        XCTAssertNil(state.draggingProviderID)
        XCTAssertNil(state.reorderPreviewProviderIDs)
        XCTAssertNil(state.dropTargetProviderID)
        XCTAssertFalse(state.dropTargetInsertAfter)
    }

    func testSettingsDialogStateClearsProfileEditors() {
        var state = SettingsDialogState(
            codexProfilePendingDelete: nil,
            codexProfileEditor: CodexProfileEditorState(slotID: .a, title: "Codex A", isNewSlot: false),
            codexProfileEditorJSON: "{\"token\":\"demo\"}",
            codexProfileEditorNote: "work",
            claudeProfilePendingDelete: nil,
            claudeProfileEditor: ClaudeProfileEditorState(slotID: .b, title: "Claude B", isNewSlot: true),
            claudeProfileEditorSource: .manualCredentials,
            claudeProfileEditorConfigDir: "~/.claude-work",
            claudeProfileEditorJSON: "{\"email\":\"demo@example.com\"}",
            claudeProfileEditorNote: "personal",
            permissionPrompt: nil,
            permissionResultMessage: [:],
            permissionResultIsError: [:],
            isNewAPISiteDialogPresented: false
        )

        state.clearCodexProfileEditor()
        XCTAssertNil(state.codexProfileEditor)
        XCTAssertEqual(state.codexProfileEditorJSON, "")
        XCTAssertEqual(state.codexProfileEditorNote, "")

        state.clearClaudeProfileEditor()
        XCTAssertNil(state.claudeProfileEditor)
        XCTAssertEqual(state.claudeProfileEditorConfigDir, "")
        XCTAssertEqual(state.claudeProfileEditorJSON, "")
        XCTAssertEqual(state.claudeProfileEditorNote, "")
        XCTAssertEqual(state.claudeProfileEditorSource, .configDir)
    }

    func testSettingsProfileDraftStateClearHelpersRemoveStoredInputs() {
        var state = SettingsProfileDraftState(
            codexProfileJSONInputs: ["A": "{}"],
            codexProfileNoteInputs: ["A": "work"],
            codexProfileResult: ["A": "saved"],
            claudeProfileJSONInputs: ["B": "{}"],
            claudeProfileConfigDirInputs: ["B": "~/.claude"],
            claudeProfileNoteInputs: ["B": "personal"],
            claudeProfileResult: ["B": "saved"]
        )

        state.clearCodexState(forKey: "A")
        XCTAssertTrue(state.codexProfileJSONInputs.isEmpty)
        XCTAssertTrue(state.codexProfileNoteInputs.isEmpty)
        XCTAssertTrue(state.codexProfileResult.isEmpty)

        state.clearClaudeState(forKey: "B")
        XCTAssertTrue(state.claudeProfileJSONInputs.isEmpty)
        XCTAssertTrue(state.claudeProfileConfigDirInputs.isEmpty)
        XCTAssertTrue(state.claudeProfileNoteInputs.isEmpty)
        XCTAssertTrue(state.claudeProfileResult.isEmpty)
    }

    func testNewRelaySiteDraftStateResetPreservesTemplateAndClearsTransientSelection() {
        var state = NewRelaySiteDraftState(
            providerName: "Demo",
            baseURL: "https://relay.example.com",
            templateID: "moonshot",
            selectedPresetID: "moonshot"
        )

        state.reset(using: "generic-newapi")

        XCTAssertEqual(state.providerName, "")
        XCTAssertEqual(state.baseURL, "")
        XCTAssertEqual(state.templateID, "generic-newapi")
        XCTAssertNil(state.selectedPresetID)
    }

    func testSettingsRuntimeStateKeepsRelayTitleEditorsMutuallyExclusive() {
        var state = SettingsRuntimeState()

        state.beginNewRelaySiteTitleEdit(originalValue: "Draft Relay")

        XCTAssertTrue(state.editingNewRelaySiteName)
        XCTAssertNil(state.editingRelayProviderID)
        XCTAssertEqual(state.relayTitleEditOriginalValue, "Draft Relay")

        state.beginRelayProviderTitleEdit(
            providerID: "relay.demo",
            originalValue: "Demo Relay"
        )

        XCTAssertFalse(state.editingNewRelaySiteName)
        XCTAssertEqual(state.editingRelayProviderID, "relay.demo")
        XCTAssertEqual(state.relayTitleEditOriginalValue, "Demo Relay")

        state.clearRelayTitleEditingState()

        XCTAssertFalse(state.editingNewRelaySiteName)
        XCTAssertNil(state.editingRelayProviderID)
        XCTAssertEqual(state.relayTitleEditOriginalValue, "")
    }

    func testRelayDraftSeedsGenericNewAPIDefaults() {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Demo Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )

        let draft = RelaySettingsDraft(provider: provider)

        XCTAssertEqual(draft.providerID, provider.id)
        XCTAssertEqual(draft.name, "Demo Relay")
        XCTAssertEqual(draft.baseURL, "https://relay.example.com")
        XCTAssertEqual(draft.preferredAdapterID, "generic-newapi")
        XCTAssertFalse(draft.tokenUsageEnabled)
        XCTAssertTrue(draft.accountEnabled)
        XCTAssertEqual(draft.authHeader, "Authorization")
        XCTAssertEqual(draft.authScheme, "Bearer")
        XCTAssertEqual(draft.userIDHeader, "New-Api-User")
        XCTAssertEqual(draft.endpointPath, "/api/user/self")
        XCTAssertEqual(draft.remainingJSONPath, "data.quota")
        XCTAssertEqual(draft.unit, "quota")
        XCTAssertTrue(draft.showExpirationTimeInMenuBar)
    }

    func testRelaySettingsDraftSeedPreservesGenericNewAPIDefaults() {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Demo Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )

        let seed = RelaySettingsDraftSeed(provider: provider)

        XCTAssertEqual(seed.providerID, provider.id)
        XCTAssertEqual(seed.name, "Demo Relay")
        XCTAssertEqual(seed.baseURL, "https://relay.example.com")
        XCTAssertEqual(seed.preferredAdapterID, "generic-newapi")
        XCTAssertFalse(seed.tokenUsageEnabled)
        XCTAssertTrue(seed.accountEnabled)
        XCTAssertEqual(seed.authHeader, "Authorization")
        XCTAssertEqual(seed.authScheme, "Bearer")
        XCTAssertEqual(seed.userIDHeader, "New-Api-User")
        XCTAssertEqual(seed.endpointPath, "/api/user/self")
        XCTAssertEqual(seed.remainingJSONPath, "data.quota")
        XCTAssertEqual(seed.unit, "quota")
    }

    func testRelayDescriptorResolverUsesInjectedRegistryForViewConfig() {
        let manifest = RelayAdapterManifest(
            id: "draft-template",
            displayName: "Draft Relay",
            match: RelayAdapterMatch(
                hostPatterns: ["relay.draft.test"],
                defaultDisplayName: "Draft Relay",
                defaultTokenChannelEnabled: false,
                defaultBalanceChannelEnabled: true
            ),
            authStrategies: [.init(kind: .savedBearer)],
            balanceRequest: RelayRequestManifest(
                method: "POST",
                path: "/draft/balance",
                bodyJSON: #"{"includeUsage":true}"#,
                userID: "42",
                userIDHeader: "X-User-ID",
                authHeader: "X-Token",
                authScheme: "Token"
            ),
            extract: RelayExtractManifest(
                success: "ok",
                remaining: "payload.remaining",
                used: "payload.used",
                limit: "payload.limit",
                unit: "credits"
            )
        )
        let resolver = RelayProviderDescriptorResolver(
            registry: RelayAdapterRegistry(builtInManifests: [RelayAdapterRegistry.genericManifest, manifest])
        )
        let provider = ProviderDescriptor(
            id: "relay-draft",
            name: "Draft Relay",
            family: .thirdParty,
            type: .relay,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: "DraftService", keychainAccount: "relay.draft.test/sk-token"),
            baseURL: "https://relay.draft.test",
            relayConfig: RelayProviderConfig(
                baseURL: "https://relay.draft.test",
                tokenChannelEnabled: false,
                balanceChannelEnabled: true,
                balanceAuth: AuthConfig(kind: .bearer, keychainService: "DraftService", keychainAccount: "relay.draft.test/system-token")
            )
        )

        let resolvedManifest = resolver.manifest(for: provider)
        let viewConfig = resolver.viewConfig(for: provider)

        XCTAssertEqual(resolvedManifest?.id, "draft-template")
        XCTAssertEqual(viewConfig?.tokenUsageEnabled, false)
        XCTAssertEqual(viewConfig?.accountBalance?.auth.keychainAccount, "relay.draft.test/system-token")
        XCTAssertEqual(viewConfig?.accountBalance?.authHeader, "X-Token")
        XCTAssertEqual(viewConfig?.accountBalance?.authScheme, "Token")
        XCTAssertEqual(viewConfig?.accountBalance?.requestMethod, "POST")
        XCTAssertEqual(viewConfig?.accountBalance?.requestBodyJSON, #"{"includeUsage":true}"#)
        XCTAssertEqual(viewConfig?.accountBalance?.endpointPath, "/draft/balance")
        XCTAssertEqual(viewConfig?.accountBalance?.userID, "42")
        XCTAssertEqual(viewConfig?.accountBalance?.userIDHeader, "X-User-ID")
        XCTAssertEqual(viewConfig?.accountBalance?.remainingJSONPath, "payload.remaining")
        XCTAssertEqual(viewConfig?.accountBalance?.usedJSONPath, "payload.used")
        XCTAssertEqual(viewConfig?.accountBalance?.limitJSONPath, "payload.limit")
        XCTAssertEqual(viewConfig?.accountBalance?.successJSONPath, "ok")
        XCTAssertEqual(viewConfig?.accountBalance?.unit, "credits")
    }

    func testRelaySettingsDraftSeedUsesInjectedResolverForTemplateDefaults() {
        let manifest = RelayAdapterManifest(
            id: "draft-template",
            displayName: "Draft Relay",
            match: RelayAdapterMatch(
                hostPatterns: ["relay.draft.test"],
                defaultDisplayName: "Draft Relay",
                defaultTokenChannelEnabled: true,
                defaultBalanceChannelEnabled: false
            ),
            authStrategies: [.init(kind: .savedBearer)],
            balanceRequest: RelayRequestManifest(
                method: "POST",
                path: "/draft/balance",
                bodyJSON: #"{"includeUsage":true}"#,
                userID: "42",
                userIDHeader: "X-User-ID",
                authHeader: "X-Token",
                authScheme: "Token"
            ),
            extract: RelayExtractManifest(
                success: "ok",
                remaining: "payload.remaining",
                used: "payload.used",
                limit: "payload.limit",
                unit: "credits"
            )
        )
        let resolver = RelayProviderDescriptorResolver(
            registry: RelayAdapterRegistry(builtInManifests: [RelayAdapterRegistry.genericManifest, manifest])
        )
        let provider = ProviderDescriptor(
            id: "relay-draft",
            name: "Draft Relay",
            family: .thirdParty,
            type: .relay,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: AuthConfig(kind: .bearer, keychainService: "DraftService", keychainAccount: "relay.draft.test/sk-token"),
            baseURL: "https://relay.draft.test",
            relayConfig: nil
        )

        let seed = RelaySettingsDraftSeed(
            provider: provider,
            adapter: RelayProviderDescriptorModelAdapter(resolver: resolver)
        )

        XCTAssertEqual(seed.preferredAdapterID, "draft-template")
        XCTAssertTrue(seed.tokenUsageEnabled)
        XCTAssertFalse(seed.accountEnabled)
        XCTAssertEqual(seed.authHeader, "X-Token")
        XCTAssertEqual(seed.authScheme, "Token")
        XCTAssertEqual(seed.endpointPath, "/draft/balance")
        XCTAssertEqual(seed.userID, "42")
        XCTAssertEqual(seed.userIDHeader, "X-User-ID")
        XCTAssertEqual(seed.remainingJSONPath, "payload.remaining")
        XCTAssertEqual(seed.usedJSONPath, "payload.used")
        XCTAssertEqual(seed.limitJSONPath, "payload.limit")
        XCTAssertEqual(seed.successJSONPath, "ok")
        XCTAssertEqual(seed.unit, "credits")
    }

    func testRelayProviderEditorDraftSeedsExistingProviderState() {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Demo Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )

        var state = RelayProviderEditorDraft()
        state.seed(from: provider)

        XCTAssertEqual(state.selectedRelayTemplateInputs[provider.id], "generic-newapi")
        XCTAssertEqual(state.providerNameInputs[provider.id], "Demo Relay")
        XCTAssertEqual(state.baseURLInputs[provider.id], "https://relay.example.com")
        XCTAssertEqual(state.relayCredentialModeInputs[provider.id], .manualPreferred)
        XCTAssertEqual(state.thirdPartyQuotaDisplayModeInputs[provider.id], .remaining)
        XCTAssertEqual(state.relayShowExpirationTimeInputs[provider.id], true)
    }

    func testOfficialDraftNormalizesUnsupportedModes() {
        var provider = ProviderDescriptor.defaultOfficialKiro()
        provider.officialConfig = OfficialProviderConfig(sourceMode: .web, webMode: .manual)

        let draft = OfficialSettingsDraft(provider: provider)

        XCTAssertEqual(draft.sourceMode, .auto)
        XCTAssertEqual(draft.webMode, .disabled)
        XCTAssertEqual(draft.quotaDisplayMode, .remaining)
    }

    func testOfficialProviderEditorDraftSeedsThresholdAndModes() {
        let provider = ProviderDescriptor.defaultOfficialCodex()

        var state = OfficialProviderEditorDraft()
        state.seed(from: provider)

        XCTAssertEqual(state.thresholdDraftValues[provider.id], provider.threshold.lowRemaining)
        XCTAssertEqual(state.officialThresholdInputs[provider.id], String(format: "%.2f", provider.threshold.lowRemaining))
        XCTAssertEqual(state.officialSourceModeInputs[provider.id], provider.officialConfig?.sourceMode ?? .auto)
        XCTAssertEqual(state.officialWebModeInputs[provider.id], provider.officialConfig?.webMode ?? .disabled)
    }
}
