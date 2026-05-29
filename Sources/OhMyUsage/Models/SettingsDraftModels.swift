import Foundation
import OhMyUsageDomain

enum ProviderGroup: String, CaseIterable, Identifiable {
    case official
    case thirdParty

    var id: String { rawValue }
}

enum PermissionPrompt: Identifiable, Equatable {
    case notifications
    case keychain
    case fullDisk
    case autoDiscovery
    case resetLocalData

    var id: String {
        switch self {
        case .notifications: return "notifications"
        case .keychain: return "keychain"
        case .fullDisk: return "fullDisk"
        case .autoDiscovery: return "autoDiscovery"
        case .resetLocalData: return "resetLocalData"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case overview
    case general
    case menuBar
    case usageAnalytics
    case permissions
    case localData
    case officialProviders
    case customProviders
    case donate

    var id: String { rawValue }

    var isProviderSection: Bool {
        self == .officialProviders || self == .customProviders
    }
}

struct CodexProfileEditorState: Identifiable, Equatable {
    var slotID: CodexSlotID
    var title: String
    var isNewSlot: Bool

    var id: String { "\(slotID.rawValue)-\(isNewSlot ? "new" : "edit")" }
}

struct ClaudeProfileEditorState: Identifiable, Equatable {
    var slotID: CodexSlotID
    var title: String
    var isNewSlot: Bool

    var id: String { "\(slotID.rawValue)-\(isNewSlot ? "new" : "edit")" }
}

struct SettingsNavigationState: Equatable {
    var selectedSettingsTab: SettingsTab = .usageAnalytics
    var selectedGroup: ProviderGroup = .official
    var selectedProviderID: String?
    var draggingProviderID: String?
    var reorderPreviewProviderIDs: [String]?
    var dropTargetProviderID: String?
    var dropTargetInsertAfter = false
    var localUsageTrendScopes: [String: LocalUsageTrendScope] = [:]
    var localUsageTrendSelectedAccountKeys: [String: String] = [:]
    var localUsageTrendExpandedAccountSelectorProviderID: String?

    mutating func selectTab(_ tab: SettingsTab) {
        selectedSettingsTab = tab
        switch tab {
        case .officialProviders:
            selectedGroup = .official
        case .customProviders:
            selectedGroup = .thirdParty
        default:
            break
        }
    }

    mutating func selectGroup(_ group: ProviderGroup) {
        selectedGroup = group
        selectedSettingsTab = group == .official ? .officialProviders : .customProviders
    }

    mutating func clearProviderReorderingState() {
        draggingProviderID = nil
        reorderPreviewProviderIDs = nil
        dropTargetProviderID = nil
        dropTargetInsertAfter = false
    }
}

struct SettingsDialogState: Equatable {
    var codexProfilePendingDelete: CodexSlotID?
    var codexProfileEditor: CodexProfileEditorState?
    var codexProfileEditorJSON = ""
    var codexProfileEditorNote = ""
    var claudeProfilePendingDelete: CodexSlotID?
    var claudeProfileEditor: ClaudeProfileEditorState?
    var claudeProfileEditorSource: ClaudeProfileSource = .configDir
    var claudeProfileEditorConfigDir = ""
    var claudeProfileEditorJSON = ""
    var claudeProfileEditorNote = ""
    var permissionPrompt: PermissionPrompt?
    var permissionResultMessage: [String: String] = [:]
    var permissionResultIsError: [String: Bool] = [:]
    var isNewAPISiteDialogPresented = false

    mutating func clearCodexProfileEditor() {
        codexProfileEditor = nil
        codexProfileEditorJSON = ""
        codexProfileEditorNote = ""
    }

    mutating func clearClaudeProfileEditor() {
        claudeProfileEditor = nil
        claudeProfileEditorConfigDir = ""
        claudeProfileEditorJSON = ""
        claudeProfileEditorNote = ""
        claudeProfileEditorSource = .configDir
    }
}

struct SettingsProfileDraftState {
    var codexProfileJSONInputs: [String: String] = [:]
    var codexProfileNoteInputs: [String: String] = [:]
    var codexProfileResult: [String: String] = [:]
    var claudeProfileJSONInputs: [String: String] = [:]
    var claudeProfileConfigDirInputs: [String: String] = [:]
    var claudeProfileNoteInputs: [String: String] = [:]
    var claudeProfileResult: [String: String] = [:]

    mutating func clearCodexState(forKey key: String) {
        codexProfileJSONInputs.removeValue(forKey: key)
        codexProfileNoteInputs.removeValue(forKey: key)
        codexProfileResult.removeValue(forKey: key)
    }

    mutating func clearClaudeState(forKey key: String) {
        claudeProfileJSONInputs.removeValue(forKey: key)
        claudeProfileConfigDirInputs.removeValue(forKey: key)
        claudeProfileNoteInputs.removeValue(forKey: key)
        claudeProfileResult.removeValue(forKey: key)
    }
}

struct NewRelaySiteDraftState {
    var providerName = ""
    var baseURL = ""
    var credentialInput = ""
    var userID = ""
    var testStatusVisible = false
    var templateID = "generic-newapi"
    var selectedPresetID: String?

    mutating func reset(using templateID: String) {
        providerName = ""
        baseURL = ""
        credentialInput = ""
        userID = ""
        testStatusVisible = false
        selectedPresetID = nil
        self.templateID = templateID
    }
}

struct SettingsRuntimeState {
    var autoDiscoveryScanning = false
    var permissionTileHeight: CGFloat = 0
    var settingsNow = Date()
    var settingsClockTask: Task<Void, Never>?
    var showingRelayNewSiteDraft = false
    var editingNewRelaySiteName = false
    var editingRelayProviderID: String?
    var relayTitleEditOriginalValue = ""

    mutating func beginNewRelaySiteTitleEdit(originalValue: String) {
        relayTitleEditOriginalValue = originalValue
        editingRelayProviderID = nil
        editingNewRelaySiteName = true
    }

    mutating func beginRelayProviderTitleEdit(providerID: String, originalValue: String) {
        relayTitleEditOriginalValue = originalValue
        editingNewRelaySiteName = false
        editingRelayProviderID = providerID
    }

    mutating func clearRelayTitleEditingState() {
        editingNewRelaySiteName = false
        editingRelayProviderID = nil
        relayTitleEditOriginalValue = ""
    }
}

struct RelayProviderEditorDraft: Equatable {
    var tokenInputs: [String: String] = [:]
    var systemTokenInputs: [String: String] = [:]
    var providerNameInputs: [String: String] = [:]
    var baseURLInputs: [String: String] = [:]
    var tokenUsageEnabledInputs: [String: Bool] = [:]
    var accountEnabledInputs: [String: Bool] = [:]
    var authHeaderInputs: [String: String] = [:]
    var authSchemeInputs: [String: String] = [:]
    var userIDInputs: [String: String] = [:]
    var userHeaderInputs: [String: String] = [:]
    var endpointPathInputs: [String: String] = [:]
    var remainingPathInputs: [String: String] = [:]
    var usedPathInputs: [String: String] = [:]
    var limitPathInputs: [String: String] = [:]
    var successPathInputs: [String: String] = [:]
    var unitInputs: [String: String] = [:]
    var thirdPartyQuotaDisplayModeInputs: [String: OfficialQuotaDisplayMode] = [:]
    var relayTestResult: [String: RelayDiagnosticResult] = [:]
    var relayAdvancedExpanded: [String: Bool] = [:]
    var selectedRelayTemplateInputs: [String: String] = [:]
    var relayCredentialModeInputs: [String: RelayCredentialMode] = [:]
    var relayShowExpirationTimeInputs: [String: Bool] = [:]

    mutating func seed(from provider: ProviderDescriptor) {
        guard provider.isRelay else { return }

        let seed = RelaySettingsDraftSeed(provider: provider)
        if selectedRelayTemplateInputs[provider.id] == nil {
            if seed.preferredAdapterID == "generic-newapi" {
                selectedRelayTemplateInputs[provider.id] = "generic-newapi"
            }
        }
        if providerNameInputs[provider.id] == nil {
            providerNameInputs[provider.id] = seed.name
        }
        if baseURLInputs[provider.id] == nil {
            baseURLInputs[provider.id] = seed.baseURL
        }
        if tokenUsageEnabledInputs[provider.id] == nil {
            tokenUsageEnabledInputs[provider.id] = seed.tokenUsageEnabled
        }
        if accountEnabledInputs[provider.id] == nil {
            accountEnabledInputs[provider.id] = seed.accountEnabled
        }
        if authHeaderInputs[provider.id] == nil {
            authHeaderInputs[provider.id] = seed.authHeader
        }
        if authSchemeInputs[provider.id] == nil {
            authSchemeInputs[provider.id] = seed.authScheme
        }
        if userIDInputs[provider.id] == nil {
            userIDInputs[provider.id] = seed.userID
        }
        if userHeaderInputs[provider.id] == nil {
            userHeaderInputs[provider.id] = seed.userIDHeader
        }
        if endpointPathInputs[provider.id] == nil {
            endpointPathInputs[provider.id] = seed.endpointPath
        }
        if remainingPathInputs[provider.id] == nil {
            remainingPathInputs[provider.id] = seed.remainingJSONPath
        }
        if usedPathInputs[provider.id] == nil {
            usedPathInputs[provider.id] = seed.usedJSONPath
        }
        if limitPathInputs[provider.id] == nil {
            limitPathInputs[provider.id] = seed.limitJSONPath
        }
        if successPathInputs[provider.id] == nil {
            successPathInputs[provider.id] = seed.successJSONPath
        }
        if unitInputs[provider.id] == nil {
            unitInputs[provider.id] = seed.unit
        }
        if relayCredentialModeInputs[provider.id] == nil {
            relayCredentialModeInputs[provider.id] = seed.balanceCredentialMode
        }
        if thirdPartyQuotaDisplayModeInputs[provider.id] == nil {
            thirdPartyQuotaDisplayModeInputs[provider.id] = seed.quotaDisplayMode
        }
        if relayShowExpirationTimeInputs[provider.id] == nil {
            relayShowExpirationTimeInputs[provider.id] = seed.showExpirationTimeInMenuBar
        }
    }
}

struct OfficialProviderEditorDraft: Equatable {
    var officialSourceModeInputs: [String: OfficialSourceMode] = [:]
    var officialWebModeInputs: [String: OfficialWebMode] = [:]
    var officialQuotaDisplayModeInputs: [String: OfficialQuotaDisplayMode] = [:]
    var officialTraeValueDisplayModeInputs: [String: OfficialTraeValueDisplayMode] = [:]
    var officialWorkspaceInputs: [String: String] = [:]
    var officialCookieInputs: [String: String] = [:]
    var officialThresholdInputs: [String: String] = [:]
    var thresholdDraftValues: [String: Double] = [:]

    mutating func seed(from provider: ProviderDescriptor) {
        if thresholdDraftValues[provider.id] == nil {
            thresholdDraftValues[provider.id] = provider.threshold.lowRemaining
        }
        if officialThresholdInputs[provider.id] == nil {
            officialThresholdInputs[provider.id] = Self.formattedThreshold(provider.threshold.lowRemaining)
        }

        guard provider.family == .official else { return }

        if officialSourceModeInputs[provider.id] == nil {
            officialSourceModeInputs[provider.id] = provider.officialConfig?.sourceMode ?? .auto
        }
        if officialWebModeInputs[provider.id] == nil {
            officialWebModeInputs[provider.id] = provider.officialConfig?.webMode ?? .disabled
        }
        if officialQuotaDisplayModeInputs[provider.id] == nil {
            officialQuotaDisplayModeInputs[provider.id] = provider.officialConfig?.quotaDisplayMode
                ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).quotaDisplayMode
        }
        if officialTraeValueDisplayModeInputs[provider.id] == nil {
            officialTraeValueDisplayModeInputs[provider.id] = provider.officialConfig?.traeValueDisplayMode
                ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).traeValueDisplayMode
                ?? .percent
        }
    }

    private static func formattedThreshold(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

struct RelaySettingsDraft: Equatable {
    var providerID: String
    var name: String
    var baseURL: String
    var preferredAdapterID: String
    var balanceCredentialMode: RelayCredentialMode
    var tokenUsageEnabled: Bool
    var accountEnabled: Bool
    var authHeader: String
    var authScheme: String
    var userID: String
    var userIDHeader: String
    var endpointPath: String
    var remainingJSONPath: String
    var usedJSONPath: String
    var limitJSONPath: String
    var successJSONPath: String
    var unit: String
    var quotaDisplayMode: OfficialQuotaDisplayMode
    var showExpirationTimeInMenuBar: Bool

    init(
        providerID: String,
        name: String,
        baseURL: String,
        preferredAdapterID: String,
        balanceCredentialMode: RelayCredentialMode,
        tokenUsageEnabled: Bool,
        accountEnabled: Bool,
        authHeader: String,
        authScheme: String,
        userID: String,
        userIDHeader: String,
        endpointPath: String,
        remainingJSONPath: String,
        usedJSONPath: String,
        limitJSONPath: String,
        successJSONPath: String,
        unit: String,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        showExpirationTimeInMenuBar: Bool = true
    ) {
        self.providerID = providerID
        self.name = name
        self.baseURL = baseURL
        self.preferredAdapterID = preferredAdapterID
        self.balanceCredentialMode = balanceCredentialMode
        self.tokenUsageEnabled = tokenUsageEnabled
        self.accountEnabled = accountEnabled
        self.authHeader = authHeader
        self.authScheme = authScheme
        self.userID = userID
        self.userIDHeader = userIDHeader
        self.endpointPath = endpointPath
        self.remainingJSONPath = remainingJSONPath
        self.usedJSONPath = usedJSONPath
        self.limitJSONPath = limitJSONPath
        self.successJSONPath = successJSONPath
        self.unit = unit
        self.quotaDisplayMode = quotaDisplayMode
        self.showExpirationTimeInMenuBar = showExpirationTimeInMenuBar
    }

    init(provider: ProviderDescriptor, preferredAdapterID: String? = nil) {
        self = RelaySettingsDraftSeed(provider: provider, preferredAdapterID: preferredAdapterID).draft
    }
}

struct OfficialSettingsDraft: Equatable {
    var providerID: String
    var sourceMode: OfficialSourceMode
    var webMode: OfficialWebMode
    var quotaDisplayMode: OfficialQuotaDisplayMode
    var traeValueDisplayMode: OfficialTraeValueDisplayMode
    var credentialInput: String
    var secondaryCredentialInput: String

    init(
        providerID: String,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        traeValueDisplayMode: OfficialTraeValueDisplayMode,
        credentialInput: String = "",
        secondaryCredentialInput: String = ""
    ) {
        self.providerID = providerID
        self.sourceMode = sourceMode
        self.webMode = webMode
        self.quotaDisplayMode = quotaDisplayMode
        self.traeValueDisplayMode = traeValueDisplayMode
        self.credentialInput = credentialInput
        self.secondaryCredentialInput = secondaryCredentialInput
    }

    init(provider: ProviderDescriptor) {
        let defaults = ProviderDescriptor.defaultOfficialConfig(type: provider.type)
        let config = provider.officialConfig ?? defaults
        let supportedSourceModes = provider.supportedOfficialSourceModes
        let supportedWebModes = provider.supportedOfficialWebModes
        let sourceMode = supportedSourceModes.contains(config.sourceMode)
            ? config.sourceMode
            : (supportedSourceModes.first ?? .auto)
        let webMode = supportedWebModes.contains(config.webMode)
            ? config.webMode
            : (supportedWebModes.first ?? .disabled)
        self.init(
            providerID: provider.id,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: config.quotaDisplayMode,
            traeValueDisplayMode: config.traeValueDisplayMode ?? defaults.traeValueDisplayMode ?? .percent
        )
    }
}
