import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    @ViewBuilder
    func relayNewSiteDraftDetailPage(contextProvider: ProviderDescriptor?) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            relayNewSiteDraftHeader(contextProvider: contextProvider)
            relayNewSiteDraftUsagePanel
            relayNewSiteDraftConfigPanel
            relayNewSiteDraftSitePanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var relayDefaultNewSiteTitle: String {
        if newRelaySiteDraft.templateID == RelayAdapterRegistry.genericSub2APIAdapterID {
            return viewModel.text(.relaySub2APISiteName)
        }
        return viewModel.text(.relayNewAPISiteName)
    }

    var relayNewSiteHeaderTitle: String {
        let trimmed = newRelaySiteDraft.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? relayDefaultNewSiteTitle : trimmed
    }

    func relayNewSiteDraftHeader(contextProvider _: ProviderDescriptor?) -> some View {
        let focusID = "relay-new-site-title"
        let titleBinding = Binding(
            get: { newRelaySiteDraft.providerName },
            set: { newRelaySiteDraft.providerName = $0 }
        )

        return HStack(alignment: .center, spacing: 8) {
            relayProviderIcon(size: SettingsVisualTokens.Sidebar.headerIconSize)
                .frame(
                    width: SettingsVisualTokens.Sidebar.headerIconSize,
                    height: SettingsVisualTokens.Sidebar.headerIconSize
                )

            if editingNewRelaySiteName {
                relayTitleEditField(
                    text: titleBinding,
                    focusID: focusID,
                    placeholder: relayDefaultNewSiteTitle,
                    onSubmit: commitNewRelaySiteNameEdit,
                    onCommitButton: commitNewRelaySiteNameEdit
                )
            } else {
                relayHeaderTitleLabel(relayNewSiteHeaderTitle)

                relayTitleIconButton(
                    systemName: "pencil",
                    accessibilityLabel: viewModel.text(.editName),
                    action: beginNewRelaySiteNameEdit
                )
            }

            Spacer(minLength: 0)
        }
        .frame(
            width: SettingsVisualTokens.SettingsLayout.configurationWidth,
            height: SettingsVisualTokens.SettingsLayout.rowHeight,
            alignment: .leading
        )
    }

    var relayNewSiteDraftUsagePanel: some View {
        settingsConfigurationSection(title: viewModel.text(.usageSection)) {
            officialSubscriptionCenteredPlaceholder(
                viewModel.text(.noUsageData),
                minHeight: 80,
                textColor: settingsMutedHintColor
            )
        }
    }

    var relayNewSiteDraftSitePanel: some View {
        settingsConfigurationSection(title: viewModel.text(.relaySiteSection)) {
            relayNewSiteDraftSiteRow
        }
    }

    var relayNewSiteDraftSiteRow: some View {
        let statusText = newRelaySiteDraft.testState == .success
            ? viewModel.text(.relayConnectionHealthy)
            : ""
        let metrics = [
            SettingsCompactRecordMetric(
                id: "balance",
                title: viewModel.text(.balanceLabel),
                valueText: "-",
                resetText: nil
            ),
            SettingsCompactRecordMetric(
                id: "used",
                title: viewModel.text(.used),
                valueText: "-",
                resetText: nil
            )
        ]
        let actions = [
            SettingsCompactRecordAction(
                id: "delete",
                title: viewModel.text(.relayDeleteSite),
                destructive: true,
                action: discardRelayNewSiteDraft
            )
        ]

        return officialSubscriptionAccountRecordRow(
            title: relayNewSiteDraftSiteTitle,
            currentText: nil,
            planType: nil,
            statusText: statusText,
            statusColor: newRelaySiteDraft.testState == .success ? SettingsVisualTokens.Status.sufficient : .clear,
            errorText: nil,
            metrics: metrics,
            actions: actions,
            showsBottomSeparator: false
        )
    }

    var relayNewSiteDraftSiteTitle: String {
        relayNewSiteHeaderTitle
    }

    func discardRelayNewSiteDraft() {
        cancelActiveRelayTitleEdit()
        let templateID = newRelaySiteDraft.templateID
        newRelaySiteDraft.reset(using: templateID)
        showingRelayNewSiteDraft = false
        if navigationState.selectedProviderID == nil {
            navigationState.selectedProviderID = sidebarProviders.first?.id
        }
    }
}
