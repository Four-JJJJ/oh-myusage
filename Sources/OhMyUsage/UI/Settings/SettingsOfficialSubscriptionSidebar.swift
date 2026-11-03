import OhMyUsageDomain
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var officialSubscriptionsSidebar: some View {
        let enabledProviders = orderedEnabledSidebarProviders
        let disabledProviders = disabledSidebarProviders

        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(enabledProviders + disabledProviders) { provider in
                    officialSubscriptionSidebarRow(provider)
                }
            }
            .padding(.horizontal, SettingsVisualTokens.Sidebar.horizontalPadding)
            .padding(.top, SettingsVisualTokens.Sidebar.verticalPadding)
            .padding(.bottom, SettingsVisualTokens.Sidebar.verticalPadding)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    var officialSubscriptionsDetailPane: some View {
        if let provider = selectedProvider {
            ScrollView {
                officialSubscriptionDetailPage(provider)
                    .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, alignment: .leading)
                    .padding(.leading, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .padding(.trailing, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .padding(.top, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .padding(.bottom, SettingsVisualTokens.SettingsLayout.rowHeight)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    func officialSubscriptionSidebarRow(_ provider: ProviderDescriptor) -> some View {
        let row = officialSubscriptionSidebarRowContent(provider)
        if provider.enabled {
            row
                .onDrag {
                    beginProviderReorderDrag(providerID: provider.id)
                }
                .onDrop(
                    of: [UTType.text.identifier],
                    delegate: ProviderRowDropDelegate(
                        targetProviderID: provider.id,
                        enabledProviderIDs: enabledSidebarProviders.map(\.id),
                        draggingProviderID: $navigationState.draggingProviderID,
                        previewProviderIDs: $navigationState.reorderPreviewProviderIDs,
                        dropTargetProviderID: $navigationState.dropTargetProviderID,
                        dropTargetInsertAfter: $navigationState.dropTargetInsertAfter,
                        onPerformDrop: { commitProviderReorder() },
                        insertAfterThresholdY: 15
                    )
                )
        } else {
            row
        }
    }

    func officialSubscriptionSidebarRowContent(_ provider: ProviderDescriptor) -> some View {
        let isSelected = navigationState.selectedProviderID == provider.id
        let displayName = sidebarDisplayName(for: provider)
        let isAPI = OfficialSettingsCategory.resolve(for: provider) == .api
        return HStack(spacing: 6) {
            SettingsCheckbox(
                isOn: Binding(
                    get: { provider.enabled },
                    set: {
                        viewModel.setEnabled($0, providerID: provider.id)
                        navigationState.selectedProviderID = provider.id
                    }
                ),
                accessibilityLabel: Localizer.format(.enableProviderAccessibility, language: viewModel.language, displayName)
            )

            providerIcon(for: provider, size: SettingsVisualTokens.Sidebar.iconSize)
                .frame(
                    width: SettingsVisualTokens.Sidebar.iconSize,
                    height: SettingsVisualTokens.Sidebar.iconSize,
                    alignment: .center
                )
                .opacity(0.8)

            HStack(spacing: 0) {
                Text(isAPI ? String(displayName.dropLast(" (API)".count)) : displayName)
                    .lineLimit(1)
                if isAPI {
                    Text(" (API)")
                        .fixedSize()
                }
            }
            .font(.system(size: 12, weight: provider.enabled ? .semibold : .regular))
            .foregroundStyle(provider.enabled ? SettingsVisualTokens.Text.primary : SettingsVisualTokens.Text.tertiary)
            .help(displayName)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(displayName)

            Spacer(minLength: 0)

            if provider.enabled {
                providerReorderHandle(providerID: provider.id)
            }
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
        .overlay(alignment: navigationState.dropTargetInsertAfter ? .bottom : .top) {
            if provider.enabled,
               let draggingProviderID = navigationState.draggingProviderID,
               draggingProviderID != provider.id,
               navigationState.dropTargetProviderID == provider.id {
                Rectangle()
                    .fill(settingsDropIndicatorColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            navigationState.selectedProviderID = provider.id
        }
        .animation(.easeInOut(duration: 0.12), value: orderedEnabledSidebarProviders.map(\.id))
        .animation(.easeInOut(duration: 0.12), value: navigationState.dropTargetProviderID)
    }
}
