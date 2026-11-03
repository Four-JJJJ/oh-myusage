import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    var relayProvidersSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sidebarProviders) { provider in
                        relayProviderSidebarRow(provider)
                    }
                }
                .padding(.horizontal, SettingsVisualTokens.Sidebar.horizontalPadding)
                .padding(.top, SettingsVisualTokens.Sidebar.verticalPadding)
                .padding(.bottom, SettingsVisualTokens.Sidebar.verticalPadding)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            relayAddSiteButton
                .padding(.horizontal, SettingsVisualTokens.Sidebar.horizontalPadding)
                .padding(.bottom, SettingsVisualTokens.Sidebar.addButtonBottomPadding)
        }
    }

    @ViewBuilder
    var relayProvidersDetailPane: some View {
        if showingRelayNewSiteDraft {
            ScrollView {
                relayNewSiteDraftDetailPage(contextProvider: selectedProvider)
                    .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, alignment: .leading)
                    .padding(.leading, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .padding(.trailing, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .padding(.top, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .padding(.bottom, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
        } else if let provider = selectedProvider {
            ScrollView {
                relayProviderDetailPage(provider)
                    .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, alignment: .leading)
                    .padding(.leading, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .padding(.trailing, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .padding(.top, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .padding(.bottom, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
        } else {
            relayProvidersEmptyState
        }
    }

    func relayProviderSidebarRow(_ provider: ProviderDescriptor) -> some View {
        let isSelected = navigationState.selectedProviderID == provider.id
        return HStack(spacing: 6) {
            SettingsCheckbox(
                isOn: Binding(
                    get: { provider.enabled },
                    set: {
                        viewModel.setEnabled($0, providerID: provider.id)
                        navigationState.selectedProviderID = provider.id
                    }
                ),
                accessibilityLabel: Localizer.format(.enableProviderAccessibility, language: viewModel.language, sidebarDisplayName(for: provider))
            )

            relayProviderIcon(size: SettingsVisualTokens.Sidebar.iconSize)
                .frame(
                    width: SettingsVisualTokens.Sidebar.iconSize,
                    height: SettingsVisualTokens.Sidebar.iconSize,
                    alignment: .center
                )

            Text(sidebarDisplayName(for: provider))
                .font(.system(size: 12, weight: provider.enabled ? .semibold : .regular))
                .foregroundStyle(provider.enabled ? SettingsVisualTokens.Text.primary : SettingsVisualTokens.Text.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(
            width: SettingsVisualTokens.Sidebar.rowWidth,
            height: SettingsVisualTokens.Sidebar.rowHeight,
            alignment: .leading
        )
        .background {
            if isSelected {
                SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control)
                    .fill(SettingsVisualTokens.Fill.selectedRow)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            cancelActiveRelayTitleEdit()
            showingRelayNewSiteDraft = false
            navigationState.selectedProviderID = provider.id
        }
    }

    var relayAddSiteButton: some View {
        Button {
            beginRelayNewSiteDraft()
        } label: {
            relayNewAPISiteButtonLabel()
        }
        .buttonStyle(.plain)
    }

    var relayProvidersEmptyState: some View {
        VStack(spacing: 16) {
            Text(viewModel.text(.relaySidebarEmptyState))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                .multilineTextAlignment(.center)

            Button {
                beginRelayNewSiteDraft()
            } label: {
                relayNewAPISiteButtonLabel()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -36)
    }

    func beginRelayNewSiteDraft() {
        cancelActiveRelayTitleEdit()
        newRelaySiteDraft.selectedPresetID = nil
        applyNewRelayTemplate(RelayAdapterRegistry.genericNewAPIAdapterID)
        newRelaySiteDraft.providerName = ""
        newRelaySiteDraft.baseURL = ""
        newRelaySiteDraft.credentialInput = ""
        newRelaySiteDraft.userID = ""
        newRelaySiteDraft.testState = .unverified
        showingRelayNewSiteDraft = true
    }

    func relayNewAPISiteButtonLabel() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .regular))
                .frame(width: 12, height: 12, alignment: .center)

            Text(viewModel.text(.relayAddSite))
                .font(.system(size: 12, weight: .regular))
        }
        .foregroundStyle(SettingsVisualTokens.Text.primary)
        .frame(
            width: SettingsVisualTokens.Sidebar.rowWidth,
            height: SettingsVisualTokens.Sidebar.addButtonHeight,
            alignment: .center
        )
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control)
                .fill(SettingsVisualTokens.Fill.selectedRow)
        )
    }
}
