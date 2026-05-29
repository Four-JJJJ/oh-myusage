import Foundation
import OhMyUsageDomain

@MainActor
struct SettingsProviderConfigurationFacade {
    var language: AppLanguage

    var showOfficialAccountEmailInMenuBarValue: () -> Bool = { false }
    var isStatusBarProviderHandler: (String) -> Bool = { _ in false }
    var setStatusBarDisplayEnabledHandler: (Bool, String) -> Void = { _, _ in }
    var setShowOfficialAccountEmailInMenuBarHandler: (Bool) -> Void = { _ in }
    var showOfficialPlanTypeInMenuBarHandler: (String) -> Bool = { _ in true }
    var setShowOfficialPlanTypeInMenuBarHandler: (Bool, String) -> Void = { _, _ in }
    var showExpirationTimeInMenuBarHandler: (String) -> Bool = { _ in true }
    var setShowExpirationTimeInMenuBarHandler: (Bool, String) -> Void = { _, _ in }
    var hasTokenForProviderHandler: (ProviderDescriptor) -> Bool = { _ in false }
    var savedTokenLengthForProviderHandler: (ProviderDescriptor) -> Int? = { _ in nil }
    var hasTokenForAuthHandler: (AuthConfig) -> Bool = { _ in false }
    var savedTokenLengthForAuthHandler: (AuthConfig) -> Int? = { _ in nil }
    var hasOfficialManualCookieHandler: (ProviderDescriptor) -> Bool = { _ in false }
    var savedOfficialManualCookieLengthHandler: (ProviderDescriptor) -> Int? = { _ in nil }
    var saveTokenForProviderHandler: (String, ProviderDescriptor) -> Bool = { _, _ in false }
    var saveTokenAndRestartForProviderHandler: (String, ProviderDescriptor) -> Bool = { _, _ in false }
    var saveTokenAndRestartForAuthHandler: (String, AuthConfig) -> Bool = { _, _ in false }
    var saveOfficialManualCookieHandler: (String, String) -> Bool = { _, _ in false }
    var updateOfficialProviderSettingsHandler: (
        String,
        OfficialSourceMode,
        OfficialWebMode,
        OfficialQuotaDisplayMode?,
        OfficialTraeValueDisplayMode?
    ) -> Void = { _, _, _, _, _ in }
    var commitProviderThresholdHandler: (Double, String) -> Void = { _, _ in }
    var saveRelayDraftHandler: (RelaySettingsDraft) -> Void = { _ in }
    var testRelayDraftHandler: (RelaySettingsDraft) async -> RelayDiagnosticResult = {
        RelayDiagnosticResult(
            success: false,
            fetchHealth: .endpointMisconfigured,
            resolvedAdapterID: $0.preferredAdapterID,
            resolvedAuthSource: nil,
            message: "",
            snapshotPreview: nil
        )
    }
    var importRelayDraftFromBrowserHandler: (RelaySettingsDraft) async -> RelayDiagnosticResult = {
        RelayDiagnosticResult(
            success: false,
            fetchHealth: .endpointMisconfigured,
            resolvedAdapterID: $0.preferredAdapterID,
            resolvedAuthSource: nil,
            message: "",
            snapshotPreview: nil
        )
    }
    var updateThirdPartyQuotaDisplayModeHandler: (String, OfficialQuotaDisplayMode) -> Void = { _, _ in }
    var removeProviderHandler: (String) -> Void = { _ in }

    var showOfficialAccountEmailInMenuBar: Bool {
        showOfficialAccountEmailInMenuBarValue()
    }

    init(
        language: AppLanguage,
        showOfficialAccountEmailInMenuBar: @escaping () -> Bool = { false },
        isStatusBarProvider: @escaping (String) -> Bool = { _ in false },
        setStatusBarDisplayEnabled: @escaping (Bool, String) -> Void = { _, _ in },
        setShowOfficialAccountEmailInMenuBar: @escaping (Bool) -> Void = { _ in },
        showOfficialPlanTypeInMenuBar: @escaping (String) -> Bool = { _ in true },
        setShowOfficialPlanTypeInMenuBar: @escaping (Bool, String) -> Void = { _, _ in },
        showExpirationTimeInMenuBar: @escaping (String) -> Bool = { _ in true },
        setShowExpirationTimeInMenuBar: @escaping (Bool, String) -> Void = { _, _ in },
        hasTokenForProvider: @escaping (ProviderDescriptor) -> Bool = { _ in false },
        savedTokenLengthForProvider: @escaping (ProviderDescriptor) -> Int? = { _ in nil },
        hasTokenForAuth: @escaping (AuthConfig) -> Bool = { _ in false },
        savedTokenLengthForAuth: @escaping (AuthConfig) -> Int? = { _ in nil },
        hasOfficialManualCookie: @escaping (ProviderDescriptor) -> Bool = { _ in false },
        savedOfficialManualCookieLength: @escaping (ProviderDescriptor) -> Int? = { _ in nil },
        saveTokenForProvider: @escaping (String, ProviderDescriptor) -> Bool = { _, _ in false },
        saveTokenAndRestartForProvider: @escaping (String, ProviderDescriptor) -> Bool = { _, _ in false },
        saveTokenAndRestartForAuth: @escaping (String, AuthConfig) -> Bool = { _, _ in false },
        saveOfficialManualCookie: @escaping (String, String) -> Bool = { _, _ in false },
        updateOfficialProviderSettings: @escaping (
            String,
            OfficialSourceMode,
            OfficialWebMode,
            OfficialQuotaDisplayMode?,
            OfficialTraeValueDisplayMode?
        ) -> Void = { _, _, _, _, _ in },
        commitProviderThreshold: @escaping (Double, String) -> Void = { _, _ in },
        saveRelayDraft: @escaping (RelaySettingsDraft) -> Void = { _ in },
        testRelayDraft: @escaping (RelaySettingsDraft) async -> RelayDiagnosticResult = {
            RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: $0.preferredAdapterID,
                resolvedAuthSource: nil,
                message: "",
                snapshotPreview: nil
            )
        },
        importRelayDraftFromBrowser: @escaping (RelaySettingsDraft) async -> RelayDiagnosticResult = {
            RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: $0.preferredAdapterID,
                resolvedAuthSource: nil,
                message: "",
                snapshotPreview: nil
            )
        },
        updateThirdPartyQuotaDisplayMode: @escaping (String, OfficialQuotaDisplayMode) -> Void = { _, _ in },
        removeProvider: @escaping (String) -> Void = { _ in }
    ) {
        self.language = language
        showOfficialAccountEmailInMenuBarValue = showOfficialAccountEmailInMenuBar
        isStatusBarProviderHandler = isStatusBarProvider
        setStatusBarDisplayEnabledHandler = setStatusBarDisplayEnabled
        setShowOfficialAccountEmailInMenuBarHandler = setShowOfficialAccountEmailInMenuBar
        showOfficialPlanTypeInMenuBarHandler = showOfficialPlanTypeInMenuBar
        setShowOfficialPlanTypeInMenuBarHandler = setShowOfficialPlanTypeInMenuBar
        showExpirationTimeInMenuBarHandler = showExpirationTimeInMenuBar
        setShowExpirationTimeInMenuBarHandler = setShowExpirationTimeInMenuBar
        hasTokenForProviderHandler = hasTokenForProvider
        savedTokenLengthForProviderHandler = savedTokenLengthForProvider
        hasTokenForAuthHandler = hasTokenForAuth
        savedTokenLengthForAuthHandler = savedTokenLengthForAuth
        hasOfficialManualCookieHandler = hasOfficialManualCookie
        savedOfficialManualCookieLengthHandler = savedOfficialManualCookieLength
        saveTokenForProviderHandler = saveTokenForProvider
        saveTokenAndRestartForProviderHandler = saveTokenAndRestartForProvider
        saveTokenAndRestartForAuthHandler = saveTokenAndRestartForAuth
        saveOfficialManualCookieHandler = saveOfficialManualCookie
        updateOfficialProviderSettingsHandler = updateOfficialProviderSettings
        commitProviderThresholdHandler = commitProviderThreshold
        saveRelayDraftHandler = saveRelayDraft
        testRelayDraftHandler = testRelayDraft
        importRelayDraftFromBrowserHandler = importRelayDraftFromBrowser
        updateThirdPartyQuotaDisplayModeHandler = updateThirdPartyQuotaDisplayMode
        removeProviderHandler = removeProvider
    }

    init(viewModel: AppViewModel) {
        self.init(
            language: viewModel.language,
            showOfficialAccountEmailInMenuBar: { viewModel.showOfficialAccountEmailInMenuBar },
            isStatusBarProvider: { viewModel.isStatusBarProvider(providerID: $0) },
            setStatusBarDisplayEnabled: { viewModel.setStatusBarDisplayEnabled($0, providerID: $1) },
            setShowOfficialAccountEmailInMenuBar: { viewModel.setShowOfficialAccountEmailInMenuBar($0) },
            showOfficialPlanTypeInMenuBar: { viewModel.showOfficialPlanTypeInMenuBar(providerID: $0) },
            setShowOfficialPlanTypeInMenuBar: { viewModel.setShowOfficialPlanTypeInMenuBar($0, providerID: $1) },
            showExpirationTimeInMenuBar: { viewModel.showExpirationTimeInMenuBar(providerID: $0) },
            setShowExpirationTimeInMenuBar: { viewModel.setShowExpirationTimeInMenuBar($0, providerID: $1) },
            hasTokenForProvider: { viewModel.hasToken(for: $0) },
            savedTokenLengthForProvider: { viewModel.savedTokenLength(for: $0) },
            hasTokenForAuth: { viewModel.hasToken(auth: $0) },
            savedTokenLengthForAuth: { viewModel.savedTokenLength(auth: $0) },
            hasOfficialManualCookie: { viewModel.hasOfficialManualCookie(for: $0) },
            savedOfficialManualCookieLength: { viewModel.savedOfficialManualCookieLength(for: $0) },
            saveTokenForProvider: { viewModel.saveToken($0, for: $1) },
            saveTokenAndRestartForProvider: { viewModel.saveTokenAndRestart($0, for: $1) },
            saveTokenAndRestartForAuth: { viewModel.saveTokenAndRestart($0, auth: $1) },
            saveOfficialManualCookie: { viewModel.saveOfficialManualCookie($0, providerID: $1) },
            updateOfficialProviderSettings: {
                viewModel.updateOfficialProviderSettings(
                    providerID: $0,
                    sourceMode: $1,
                    webMode: $2,
                    quotaDisplayMode: $3,
                    traeValueDisplayMode: $4
                )
            },
            commitProviderThreshold: { viewModel.commitProviderThreshold($0, providerID: $1) },
            saveRelayDraft: { viewModel.saveRelayDraft($0) },
            testRelayDraft: { await viewModel.testRelayDraft($0) },
            importRelayDraftFromBrowser: { await viewModel.importRelayDraftFromBrowser($0) },
            updateThirdPartyQuotaDisplayMode: { viewModel.updateThirdPartyQuotaDisplayMode(providerID: $0, quotaDisplayMode: $1) },
            removeProvider: { viewModel.removeProvider(providerID: $0) }
        )
    }

    func text(_ key: L10nKey) -> String {
        Localizer.text(key, language: language)
    }

    func localizedText(_ zhHans: String, _ en: String) -> String {
        language == .zhHans ? zhHans : en
    }

    func isStatusBarProvider(providerID: String) -> Bool {
        isStatusBarProviderHandler(providerID)
    }

    func setStatusBarDisplayEnabled(_ enabled: Bool, providerID: String) {
        setStatusBarDisplayEnabledHandler(enabled, providerID)
    }

    func setShowOfficialAccountEmailInMenuBar(_ enabled: Bool) {
        setShowOfficialAccountEmailInMenuBarHandler(enabled)
    }

    func showOfficialPlanTypeInMenuBar(providerID: String) -> Bool {
        showOfficialPlanTypeInMenuBarHandler(providerID)
    }

    func setShowOfficialPlanTypeInMenuBar(_ enabled: Bool, providerID: String) {
        setShowOfficialPlanTypeInMenuBarHandler(enabled, providerID)
    }

    func showExpirationTimeInMenuBar(providerID: String) -> Bool {
        showExpirationTimeInMenuBarHandler(providerID)
    }

    func setShowExpirationTimeInMenuBar(_ enabled: Bool, providerID: String) {
        setShowExpirationTimeInMenuBarHandler(enabled, providerID)
    }

    func hasToken(for provider: ProviderDescriptor) -> Bool {
        hasTokenForProviderHandler(provider)
    }

    func savedTokenLength(for provider: ProviderDescriptor) -> Int? {
        savedTokenLengthForProviderHandler(provider)
    }

    func hasToken(auth: AuthConfig) -> Bool {
        hasTokenForAuthHandler(auth)
    }

    func savedTokenLength(auth: AuthConfig) -> Int? {
        savedTokenLengthForAuthHandler(auth)
    }

    func hasOfficialManualCookie(for provider: ProviderDescriptor) -> Bool {
        hasOfficialManualCookieHandler(provider)
    }

    func savedOfficialManualCookieLength(for provider: ProviderDescriptor) -> Int? {
        savedOfficialManualCookieLengthHandler(provider)
    }

    @discardableResult
    func saveToken(_ token: String, for provider: ProviderDescriptor) -> Bool {
        saveTokenForProviderHandler(token, provider)
    }

    @discardableResult
    func saveTokenAndRestart(_ token: String, for provider: ProviderDescriptor) -> Bool {
        saveTokenAndRestartForProviderHandler(token, provider)
    }

    @discardableResult
    func saveTokenAndRestart(_ token: String, auth: AuthConfig) -> Bool {
        saveTokenAndRestartForAuthHandler(token, auth)
    }

    @discardableResult
    func saveOfficialManualCookie(_ value: String, providerID: String) -> Bool {
        saveOfficialManualCookieHandler(value, providerID)
    }

    func updateOfficialProviderSettings(
        providerID: String,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) {
        updateOfficialProviderSettingsHandler(
            providerID,
            sourceMode,
            webMode,
            quotaDisplayMode,
            traeValueDisplayMode
        )
    }

    func commitProviderThreshold(_ value: Double, providerID: String) {
        commitProviderThresholdHandler(value, providerID)
    }

    func saveRelayDraft(_ draft: RelaySettingsDraft) {
        saveRelayDraftHandler(draft)
    }

    func testRelayDraft(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult {
        await testRelayDraftHandler(draft)
    }

    func importRelayDraftFromBrowser(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult {
        await importRelayDraftFromBrowserHandler(draft)
    }

    func updateThirdPartyQuotaDisplayMode(
        providerID: String,
        quotaDisplayMode: OfficialQuotaDisplayMode
    ) {
        updateThirdPartyQuotaDisplayModeHandler(providerID, quotaDisplayMode)
    }

    func removeProvider(providerID: String) {
        removeProviderHandler(providerID)
    }
}
