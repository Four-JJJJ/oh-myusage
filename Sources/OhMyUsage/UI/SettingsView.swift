import AppKit
import OhMyUsageApplication
import OhMyUsageDomain
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
    var onDone: (() -> Void)? = nil
    let visibleClockController = VisibleClockController()

    @State var relayEditorDraft = RelayProviderEditorDraft()
    @State var relayTestResultGeneration = 0
    @State var officialEditorDraft = OfficialProviderEditorDraft()
    @State var profileDraftState = SettingsProfileDraftState()
    @State var dialogState = SettingsDialogState()
    @State var runtimeState = SettingsRuntimeState()
    @FocusState var focusedThresholdProviderID: String?

    @State var newRelaySiteDraft = NewRelaySiteDraftState()
    @State var navigationState = SettingsNavigationState()
    @State var providerReorderLocalMouseUpMonitor: Any?
    @State var providerReorderGlobalMouseUpMonitor: Any?
    @FocusState var focusedRelayTitleEditorID: String?

    var providerConfigurationFacade: SettingsProviderConfigurationFacade {
        SettingsProviderConfigurationFacade(viewModel: viewModel)
    }

    var showingRelayNewSiteDraft: Bool {
        get { runtimeState.showingRelayNewSiteDraft }
        nonmutating set { runtimeState.showingRelayNewSiteDraft = newValue }
    }

    var editingNewRelaySiteName: Bool {
        get { runtimeState.editingNewRelaySiteName }
        nonmutating set { runtimeState.editingNewRelaySiteName = newValue }
    }

    var editingRelayProviderID: String? {
        get { runtimeState.editingRelayProviderID }
        nonmutating set { runtimeState.editingRelayProviderID = newValue }
    }

    var relayTitleEditOriginalValue: String {
        get { runtimeState.relayTitleEditOriginalValue }
        nonmutating set { runtimeState.relayTitleEditOriginalValue = newValue }
    }

    struct RelayTemplatePreset: Identifiable {
        let manifest: RelayAdapterManifest
        let suggestedBaseURL: String?

        var id: String { manifest.id }
        var displayName: String { manifest.displayName }
    }

    struct CodexQuotaMetricDisplay: Identifiable {
        var id: String
        var title: String
        var valueText: String
        var resetText: String
        var detailText: String? = nil
        var percent: Double?
        var barColor: Color
        var isAvailable: Bool = true
        var healthPercent: Double? = nil
        var isBlockedByDepletedQuota: Bool = false
    }

    enum OfficialMonitoringHealthStatus: Equatable {
        case unknown
        case authError
        case configError
        case rateLimited
        case disconnected
        case sufficient
        case tight
        case exhausted
    }

    nonisolated static func resolvedOfficialMonitoringProvider(
        type: ProviderType,
        providers: [ProviderDescriptor]
    ) -> ProviderDescriptor {
        SettingsQuotaPresenter.resolvedOfficialMonitoringProvider(type: type, providers: providers)
    }

    nonisolated static func quotaMetricPercents(
        for window: UsageQuotaWindow,
        displaysUsedQuota: Bool
    ) -> (displayPercent: Double, healthPercent: Double) {
        SettingsQuotaPresenter.quotaMetricPercents(for: window, displaysUsedQuota: displaysUsedQuota)
    }

    nonisolated static func officialMonitoringHealthStatus(
        snapshot: UsageSnapshot?,
        healthPercents: [Double]
    ) -> OfficialMonitoringHealthStatus {
        switch SettingsQuotaPresenter.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: healthPercents
        ) {
        case .unknown:
            return .unknown
        case .authError:
            return .authError
        case .configError:
            return .configError
        case .rateLimited:
            return .rateLimited
        case .disconnected:
            return .disconnected
        case .sufficient:
            return .sufficient
        case .tight:
            return .tight
        case .exhausted:
            return .exhausted
        }
    }

}

#Preview("Settings / General") {
    SettingsView(viewModel: {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyUsagePreview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vm = AppViewModel(
            configurationRepository: AppConfigurationRepository(
                store: ConfigStore(baseDirectoryURL: root)
            )
        )
        vm.setLanguage(.zhHans)
        return vm
    }())
    .frame(width: 1000, height: 720)
    .preferredColorScheme(.dark)
}
