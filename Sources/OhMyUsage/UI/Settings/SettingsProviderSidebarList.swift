import OhMyUsageDomain
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    @ViewBuilder
    var detailPane: some View {
        SettingsProviderDetailPaneView(hasSelection: selectedProvider != nil) {
            if let selectedProvider {
                providerSettingsCard(selectedProvider)
            }
        } emptyState: {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(settingsHintColor)
                Text(viewModel.text(.selectProviderHint))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(settingsTitleColor)
                Text(viewModel.text(.providerDetailPlaceholder))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(settingsHintColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Spacer()
            }
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                modelGroupSegmentControl
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Group {
                if navigationState.selectedGroup == .thirdParty {
                    thirdPartySidebarContent
                } else {
                    officialSidebarContent
                }
            }
            .padding(.horizontal, 16)
        }
    }

    var modelGroupSegmentControl: some View {
        Picker("", selection: Binding(
            get: { navigationState.selectedGroup.id },
            set: { newValue in
                if let group = ProviderGroup(rawValue: newValue) {
                    navigationState.selectGroup(group)
                }
            }
        )) {
            Text(viewModel.text(.officialTab)).tag(ProviderGroup.official.id)
            Text(viewModel.text(.thirdPartyTab)).tag(ProviderGroup.thirdParty.id)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 188, height: 20)
    }

    var thirdPartySidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    providerSidebarList

                    if !unaddedRelayBuiltInPresets.isEmpty {
                        Spacer()
                            .frame(height: 12)

                        dividerLine

                        Spacer()
                            .frame(height: 12)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(unaddedRelayBuiltInPresets) { preset in
                                relayPresetSidebarRow(preset)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(minHeight: 220, maxHeight: .infinity, alignment: .top)

            Spacer(minLength: 16)

            dividerLine

            Spacer()
                .frame(height: 16)

            addNewAPISiteButton
        }
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    var officialSidebarContent: some View {
        ScrollView {
            providerSidebarList
        }
        .scrollIndicators(.never)
        .frame(minHeight: 220, maxHeight: .infinity, alignment: .top)
    }

    var providerSidebarList: some View {
        let enabledProviders = orderedEnabledSidebarProviders
        let disabledProviders = disabledSidebarProviders

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(enabledProviders) { provider in
                    sidebarProviderRow(provider)
                }
            }

            if !enabledProviders.isEmpty, !disabledProviders.isEmpty {
                Spacer()
                    .frame(height: 12)

                dividerLine

                Spacer()
                    .frame(height: 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(disabledProviders) { provider in
                    sidebarProviderRow(provider)
                }
            }
        }
    }

    var addNewAPISiteButton: some View {
        Button {
            newRelaySiteDraft.selectedPresetID = nil
            applyNewRelayTemplate(RelayAdapterRegistry.genericNewAPIAdapterID)
            newRelaySiteDraft.baseURL = ""
            newRelaySiteDraft.credentialInput = ""
            newRelaySiteDraft.userID = ""
            newRelaySiteDraft.testState = .unverified
            dialogState.isNewAPISiteDialogPresented = true
        } label: {
            Text(viewModel.text(.relayAddSite))
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(settingsAccentBlue)
    }

    @ViewBuilder
    func sidebarProviderRow(_ provider: ProviderDescriptor) -> some View {
        let row = sidebarProviderRowContent(provider)
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
                        onPerformDrop: { commitProviderReorder() }
                    )
                )
        } else {
            row
        }
    }

    func sidebarProviderRowContent(_ provider: ProviderDescriptor) -> some View {
        let isSelected = navigationState.selectedProviderID == provider.id

        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { provider.enabled },
                set: {
                    viewModel.setEnabled($0, providerID: provider.id)
                    navigationState.selectedProviderID = provider.id
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            providerIcon(for: provider, size: 12)

            Text(sidebarDisplayName(for: provider))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsBodyColor)
                .lineLimit(1)
            Spacer(minLength: 0)

            if provider.enabled {
                providerReorderHandle(providerID: provider.id)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                .fill(isSelected ? settingsSelectedRowFillColor : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control, style: .continuous)
                .stroke(
                    isSelected ? settingsSelectedRowStrokeColor : settingsRowStrokeColor,
                    lineWidth: SettingsVisualTokens.Stroke.hairline
                )
        )
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
