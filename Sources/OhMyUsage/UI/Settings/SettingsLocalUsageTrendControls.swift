import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    @ViewBuilder
    func localUsageTrendControls(
        provider: ProviderDescriptor,
        scope: LocalUsageTrendScope,
        selectedAccountKey: String?,
        accountOptions: [LocalUsageTrendAccountOption]
    ) -> some View {
        let showsAccountSelector = scope == .currentAccount && !accountOptions.isEmpty

        if showsAccountSelector {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    localUsageTrendScopeSegmentControl(provider: provider)
                        .frame(width: localUsageTrendScopeControlWidth, height: 24)

                    Spacer(minLength: 12)

                    localUsageTrendAccountSelector(
                        providerID: provider.id,
                        selectedAccountKey: selectedAccountKey,
                        options: accountOptions
                    )
                    .frame(width: 205, height: 24, alignment: .trailing)
                    .frame(height: 24)
                }

                VStack(alignment: .leading, spacing: 10) {
                    localUsageTrendScopeSegmentControl(provider: provider)
                        .frame(width: localUsageTrendScopeControlWidth, height: 24)

                    localUsageTrendAccountSelector(
                        providerID: provider.id,
                        selectedAccountKey: selectedAccountKey,
                        options: accountOptions
                    )
                    .frame(width: 205, alignment: .leading)
                    .frame(height: 24)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                localUsageTrendScopeSegmentControl(provider: provider)
                    .frame(width: localUsageTrendScopeControlWidth, height: 24)
                Spacer(minLength: 0)
            }
        }
    }

    private var localUsageTrendScopeControlWidth: CGFloat {
        viewModel.language == .zhHans ? 140 : 170
    }

    private func localUsageTrendScopeSegmentControl(provider: ProviderDescriptor) -> some View {
        Picker("", selection: Binding(
            get: { localUsageTrendScope(for: provider).id },
            set: { newValue in
                if let scope = LocalUsageTrendScope.allCases.first(where: { $0.id == newValue }) {
                    localUsageTrendScopeBinding(for: provider).wrappedValue = scope
                }
            }
        )) {
            Text(viewModel.text(.usageTrendScopeAll)).tag(LocalUsageTrendScope.allAccounts.id)
            Text(viewModel.text(.usageTrendScopeByAccount)).tag(LocalUsageTrendScope.currentAccount.id)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(height: 24)
    }

    @ViewBuilder
    private func localUsageTrendAccountSelector(
        providerID: String,
        selectedAccountKey: String?,
        options: [LocalUsageTrendAccountOption]
    ) -> some View {
        let resolved = options.first(where: { $0.id == selectedAccountKey }) ?? options.first
        let isExpanded = navigationState.localUsageTrendExpandedAccountSelectorProviderID == providerID
        let selectorText = localUsageTrendTrimmed(resolved?.selectorLabel)
            ?? viewModel.text(.usageTrendSelectAccount)

        Button {
            navigationState.localUsageTrendExpandedAccountSelectorProviderID = isExpanded ? nil : providerID
        } label: {
            HStack(spacing: 8) {
                Text(selectorText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(settingsBodyColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settingsHintColor)
                    .frame(width: 14, height: 14, alignment: .center)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(settingsControlFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(settingsControlStrokeColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: localUsageTrendAccountSelectorExpandedBinding(providerID: providerID),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            localUsageTrendAccountSelectorPopover(
                providerID: providerID,
                selectedAccountKey: selectedAccountKey,
                options: options
            )
        }
    }

    func localUsageTrendAccountSelectorExpandedBinding(providerID: String) -> Binding<Bool> {
        Binding(
            get: { navigationState.localUsageTrendExpandedAccountSelectorProviderID == providerID },
            set: { isPresented in
                if isPresented {
                    navigationState.localUsageTrendExpandedAccountSelectorProviderID = providerID
                } else if navigationState.localUsageTrendExpandedAccountSelectorProviderID == providerID {
                    navigationState.localUsageTrendExpandedAccountSelectorProviderID = nil
                }
            }
        )
    }

    func localUsageTrendAccountSelectorPopover(
        providerID: String,
        selectedAccountKey: String?,
        options: [LocalUsageTrendAccountOption]
    ) -> some View {
        let selectedID = selectedAccountKey ?? options.first?.id
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(options) { option in
                Button {
                    navigationState.localUsageTrendSelectedAccountKeys[providerID] = option.id
                    navigationState.localUsageTrendExpandedAccountSelectorProviderID = nil
                } label: {
                    HStack(spacing: 8) {
                        Text(option.label)
                            .font(.system(size: 12, weight: option.id == selectedID ? .semibold : .regular))
                            .foregroundStyle(option.id == selectedID ? settingsTitleColor : settingsBodyColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        if option.id == selectedID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(settingsAccentBlue)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(option.id == selectedID ? settingsPopoverSelectedFillColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(settingsPopoverFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(settingsControlStrokeColor, lineWidth: 1)
        )
    }
}
