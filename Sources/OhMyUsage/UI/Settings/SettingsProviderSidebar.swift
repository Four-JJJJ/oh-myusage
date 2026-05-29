import AppKit
import OhMyUsageDomain
import SwiftUI
import UniformTypeIdentifiers

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
            SettingsCheckbox(isOn: Binding(
                get: { provider.enabled },
                set: {
                    viewModel.setEnabled($0, providerID: provider.id)
                    navigationState.selectedProviderID = provider.id
                }
            ))

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
            Text(viewModel.localizedText(
                "快来添加你的第一个代理中转站点吧～",
                "Add your first relay proxy site to get started"
            ))
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
        applyNewRelayTemplate("generic-newapi")
        newRelaySiteDraft.providerName = ""
        newRelaySiteDraft.baseURL = ""
        newRelaySiteDraft.credentialInput = ""
        newRelaySiteDraft.userID = ""
        newRelaySiteDraft.testStatusVisible = false
        showingRelayNewSiteDraft = true
    }

    func relayNewAPISiteButtonLabel() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .regular))
                .frame(width: 12, height: 12, alignment: .center)

            Text(viewModel.localizedText("NewAPI站点", "NewAPI Site"))
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
        viewModel.localizedText("NewAPI站点", "NewAPI Site")
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
                    accessibilityLabel: viewModel.localizedText("编辑名称", "Edit name"),
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
        settingsConfigurationSection(title: viewModel.localizedText("用量", "Usage")) {
            officialSubscriptionCenteredPlaceholder(
                viewModel.localizedText("暂无用量信息", "No usage data yet"),
                minHeight: 80,
                textColor: settingsMutedHintColor
            )
        }
    }

    func relayProviderDetailPage(_ provider: ProviderDescriptor) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        return VStack(alignment: .leading, spacing: 24) {
            relayProviderHeader(provider)
            relayUsagePanel(provider, snapshot: snapshot)
            relayConfigPanel(provider)
            relaySitePanel(provider, snapshot: snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func relayProviderHeader(_ provider: ProviderDescriptor) -> some View {
        let isEditing = editingRelayProviderID == provider.id
        let focusID = "relay-title-\(provider.id)"
        let nameBinding = Binding(
            get: { relayEditorDraft.providerNameInputs[provider.id] ?? provider.name },
            set: { relayEditorDraft.providerNameInputs[provider.id] = $0 }
        )

        return HStack(alignment: .center, spacing: 8) {
            relayProviderIcon(size: SettingsVisualTokens.Sidebar.headerIconSize)
                .frame(
                    width: SettingsVisualTokens.Sidebar.headerIconSize,
                    height: SettingsVisualTokens.Sidebar.headerIconSize
                )

            if isEditing {
                relayTitleEditField(
                    text: nameBinding,
                    focusID: focusID,
                    placeholder: viewModel.text(.providerName),
                    onSubmit: { commitRelayProviderNameEdit(provider) },
                    onCommitButton: { commitRelayProviderNameEdit(provider) }
                )
            } else {
                relayHeaderTitleLabel(sidebarDisplayName(for: provider))

                relayTitleIconButton(
                    systemName: "pencil",
                    accessibilityLabel: viewModel.localizedText("编辑名称", "Edit name"),
                    action: { beginRelayProviderNameEdit(provider) }
                )
            }

            Spacer(minLength: 0)

            relayHeaderTrailingControls(provider)
        }
        .frame(
            width: SettingsVisualTokens.SettingsLayout.configurationWidth,
            height: SettingsVisualTokens.SettingsLayout.rowHeight,
            alignment: .leading
        )
    }

    func beginNewRelaySiteNameEdit() {
        relayTitleEditOriginalValue = newRelaySiteDraft.providerName
        if newRelaySiteDraft.providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newRelaySiteDraft.providerName = relayDefaultNewSiteTitle
        }
        editingRelayProviderID = nil
        editingNewRelaySiteName = true
        DispatchQueue.main.async {
            focusedRelayTitleEditorID = "relay-new-site-title"
        }
    }

    func commitNewRelaySiteNameEdit() {
        let trimmed = newRelaySiteDraft.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        newRelaySiteDraft.providerName = trimmed.isEmpty ? relayDefaultNewSiteTitle : trimmed
        editingNewRelaySiteName = false
        focusedRelayTitleEditorID = nil
    }

    func cancelNewRelaySiteNameEdit() {
        newRelaySiteDraft.providerName = relayTitleEditOriginalValue
        editingNewRelaySiteName = false
        focusedRelayTitleEditorID = nil
    }

    func beginRelayProviderNameEdit(_ provider: ProviderDescriptor) {
        let currentName = relayEditorDraft.providerNameInputs[provider.id] ?? provider.name
        relayTitleEditOriginalValue = currentName
        relayEditorDraft.providerNameInputs[provider.id] = currentName
        editingNewRelaySiteName = false
        editingRelayProviderID = provider.id
        DispatchQueue.main.async {
            focusedRelayTitleEditorID = "relay-title-\(provider.id)"
        }
    }

    func commitRelayProviderNameEdit(_ provider: ProviderDescriptor) {
        let input = relayEditorDraft.providerNameInputs[provider.id] ?? provider.name
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelRelayProviderNameEdit(provider)
            return
        }
        relayEditorDraft.providerNameInputs[provider.id] = trimmed
        viewModel.saveRelayDraft(currentRelaySettingsDraft(for: provider))
        editingRelayProviderID = nil
        focusedRelayTitleEditorID = nil
    }

    func cancelRelayProviderNameEdit(_ provider: ProviderDescriptor) {
        relayEditorDraft.providerNameInputs[provider.id] = relayTitleEditOriginalValue
        editingRelayProviderID = nil
        focusedRelayTitleEditorID = nil
    }

    func cancelActiveRelayTitleEdit() {
        if editingNewRelaySiteName {
            newRelaySiteDraft.providerName = relayTitleEditOriginalValue
        }
        if let editingRelayProviderID {
            relayEditorDraft.providerNameInputs[editingRelayProviderID] = relayTitleEditOriginalValue
        }
        editingNewRelaySiteName = false
        editingRelayProviderID = nil
        focusedRelayTitleEditorID = nil
    }

    func relayTitleEditField(
        text: Binding<String>,
        focusID: String,
        placeholder: String,
        onSubmit: @escaping () -> Void,
        onCommitButton: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .trailing) {
            TextField("", text: text, prompt: settingsInputPrompt(placeholder))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settingsTitleColor)
                .lineLimit(1)
                .padding(.leading, 8)
                .padding(.trailing, 34)
                .focused($focusedRelayTitleEditorID, equals: focusID)
                .onSubmit(onSubmit)

            Button(action: onCommitButton) {
                relayTitleIconImage(named: "relay_title_commit_icon", fallback: "checkmark")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel(viewModel.localizedText("保存名称", "Save name"))
        }
        .frame(width: 240, height: 24, alignment: .leading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.control)
                .fill(settingsUsesLightAppearance ? Color.white.opacity(0.10) : SettingsVisualTokens.Fill.control)
        )
    }

    func relayTitleIconButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            relayTitleIconImage(named: "relay_title_edit_icon", fallback: systemName)
        }
        .buttonStyle(.plain)
        .frame(width: 14, height: 14)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    func relayTitleIconImage(named name: String, fallback: String) -> some View {
        if let image = bundledImage(named: name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        } else {
            Image(systemName: fallback)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(settingsTitleColor)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
    }

    func relayHeaderTitleLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(settingsTitleColor)
            .lineLimit(1)
            .frame(height: 14, alignment: .center)
    }

    func relayHeaderTrailingControls(_ provider: ProviderDescriptor) -> some View {
        HStack(spacing: 16) {
            Button {
                viewModel.refreshNow()
            } label: {
                settingsCompactToolbarIcon(named: "refresh_icon", fallback: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            SettingsToggleSwitch(
                isOn: Binding(
                    get: { provider.enabled },
                    set: { viewModel.setEnabled($0, providerID: provider.id) }
                ),
                offTrackColor: SettingsVisualTokens.Fill.control,
                onTrackColor: SettingsVisualTokens.Text.tertiary,
                knobColor: SettingsVisualTokens.Text.primary
            )
        }
        .frame(width: 88, height: 24, alignment: .trailing)
    }

    func relayUsagePanel(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        let remaining = snapshot?.remaining
        let used = snapshot?.used
        let limit = snapshot?.limit ?? relayUsageTotalFallback(remaining: remaining, used: used)

        return settingsConfigurationSection(title: viewModel.localizedText("用量", "Usage")) {
            HStack(alignment: .center, spacing: 0) {
                relayUsageMetric(
                    title: viewModel.localizedText("余额", "Balance"),
                    value: formattedRelayUsageAmount(remaining ?? 0)
                )

                Spacer(minLength: 0)

                relayUsageMetric(
                    title: viewModel.localizedText("已消耗", "Used"),
                    value: formattedRelayUsageAmount(used ?? 0)
                )

                Spacer(minLength: 0)

                relayUsageMetric(
                    title: viewModel.localizedText("总额", "Total"),
                    value: formattedRelayUsageAmount(limit ?? 0)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(width: 566, height: 64, alignment: .center)
        }
        .frame(width: 566, alignment: .topLeading)
    }

    func relayUsageMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                .lineLimit(1)
                .frame(height: 10, alignment: .leading)

            Text(value)
                .font(AppFonts.numeric(size: 14, fallbackWeight: .bold))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .lineLimit(1)
                .frame(width: 140, height: 14, alignment: .leading)
        }
        .frame(width: 140, height: 32, alignment: .leading)
    }

    func relayUsageTotalFallback(remaining: Double?, used: Double?) -> Double? {
        guard let remaining, let used else { return nil }
        return remaining + used
    }

    func formattedRelayUsageAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    @ViewBuilder
    func relayConfigPanel(_ provider: ProviderDescriptor) -> some View {
        settingsConfigurationSection(title: viewModel.localizedText("配置", "Configuration")) {
            relayCondensedConfigSection(provider)
        }
    }

    var relayNewSiteDraftSitePanel: some View {
        settingsConfigurationSection(title: viewModel.localizedText("站点", "Site")) {
            relayNewSiteDraftSiteRow
        }
    }

    var relayNewSiteDraftSiteRow: some View {
        let statusText = newRelaySiteDraft.testStatusVisible
            ? viewModel.localizedText("链接成功接口正常", "Connection succeeded and endpoint is healthy")
            : ""
        let metrics = [
            SettingsCompactRecordMetric(
                id: "balance",
                title: viewModel.localizedText("余额", "Balance"),
                valueText: "-",
                resetText: nil
            ),
            SettingsCompactRecordMetric(
                id: "used",
                title: viewModel.localizedText("已用", "Used"),
                valueText: "-",
                resetText: nil
            )
        ]
        let actions = [
            SettingsCompactRecordAction(
                id: "delete",
                title: viewModel.localizedText("删除站点", "Delete Site"),
                destructive: true,
                action: discardRelayNewSiteDraft
            )
        ]

        return officialSubscriptionAccountRecordRow(
            title: relayNewSiteDraftSiteTitle,
            currentText: nil,
            planType: nil,
            statusText: statusText,
            statusColor: newRelaySiteDraft.testStatusVisible ? SettingsVisualTokens.Status.sufficient : .clear,
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

    func relaySitePanel(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        settingsConfigurationSection(title: viewModel.localizedText("站点", "Site")) {
            relaySiteRow(provider, snapshot: snapshot)
        }
    }

    func relaySiteRow(
        _ provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        let status = relayProviderSummaryStatus(
            snapshot: snapshot,
            hasError: (viewModel.errors[provider.id]?.isEmpty == false)
        )
        let metrics = [
            SettingsCompactRecordMetric(
                id: "balance",
                title: viewModel.localizedText("余额", "Balance"),
                valueText: snapshot?.remaining.map(formattedSettingsAmount) ?? "-",
                resetText: nil
            ),
            SettingsCompactRecordMetric(
                id: "used",
                title: viewModel.localizedText("已用", "Used"),
                valueText: snapshot?.used.map(formattedSettingsAmount) ?? "-",
                resetText: nil
            )
        ]
        let actions = [
            SettingsCompactRecordAction(
                id: "delete",
                title: viewModel.localizedText("删除站点", "Delete Site"),
                destructive: true,
                action: { viewModel.removeProvider(providerID: provider.id) }
            )
        ]

        return officialSubscriptionAccountRecordRow(
            title: sidebarDisplayName(for: provider),
            currentText: nil,
            planType: nil,
            statusText: status.text,
            statusColor: status.color,
            errorText: nil,
            metrics: metrics,
            actions: actions,
            showsBottomSeparator: false
        )
    }

    var officialSubscriptionsSidebar: some View {
        let enabledProviders = orderedEnabledSidebarProviders
        let disabledProviders = disabledSidebarProviders

        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(enabledProviders) { provider in
                    officialSubscriptionSidebarRow(provider)
                }
                ForEach(disabledProviders) { provider in
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
        return HStack(spacing: 6) {
            SettingsCheckbox(isOn: Binding(
                get: { provider.enabled },
                set: {
                    viewModel.setEnabled($0, providerID: provider.id)
                    navigationState.selectedProviderID = provider.id
                }
            ))

            providerIcon(for: provider, size: SettingsVisualTokens.Sidebar.iconSize)
                .frame(
                    width: SettingsVisualTokens.Sidebar.iconSize,
                    height: SettingsVisualTokens.Sidebar.iconSize,
                    alignment: .center
                )
                .opacity(0.8)

            Text(sidebarDisplayName(for: provider))
                .font(.system(size: 12, weight: provider.enabled ? .semibold : .regular))
                .foregroundStyle(provider.enabled ? SettingsVisualTokens.Text.primary : SettingsVisualTokens.Text.tertiary)
                .lineLimit(1)

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

    func officialSubscriptionDetailPage(_ provider: ProviderDescriptor) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let error = viewModel.errors[provider.id]

        return VStack(alignment: .leading, spacing: 24) {
            officialSubscriptionHeader(provider)
            officialSubscriptionUsageSection(provider: provider, snapshot: snapshot)
            officialSubscriptionAccountsSection(provider: provider, snapshot: snapshot, error: error)
            officialSubscriptionConfigSection(provider)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func officialSubscriptionHeader(_ provider: ProviderDescriptor) -> some View {
        HStack(alignment: .center, spacing: 8) {
            providerIcon(for: provider, size: SettingsVisualTokens.Sidebar.headerIconSize)
                .frame(
                    width: SettingsVisualTokens.Sidebar.headerIconSize,
                    height: SettingsVisualTokens.Sidebar.headerIconSize
                )
                .opacity(0.8)

            Text(sidebarDisplayName(for: provider))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(settingsTitleColor)

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                Button {
                    viewModel.refreshNow()
                } label: {
                    settingsCompactToolbarIcon(named: "refresh_icon", fallback: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                SettingsToggleSwitch(
                    isOn: Binding(
                        get: { provider.enabled },
                        set: { viewModel.setEnabled($0, providerID: provider.id) }
                    ),
                    offTrackColor: SettingsVisualTokens.Fill.control,
                    onTrackColor: SettingsVisualTokens.Text.tertiary,
                    knobColor: SettingsVisualTokens.Text.primary
                )
            }
        }
        .frame(
            width: SettingsVisualTokens.SettingsLayout.configurationWidth,
            height: SettingsVisualTokens.SettingsLayout.rowHeight,
            alignment: .leading
        )
    }

    @ViewBuilder
    func relayProviderIcon(size: CGFloat) -> some View {
        if let image = bundledImage(named: "relay_provider_third_icon") {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(settingsTitleColor)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .foregroundStyle(settingsBodyColor)
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    func settingsCompactToolbarIcon(named name: String, fallback: String) -> some View {
        if let image = bundledImage(named: name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .opacity(0.8)
        } else {
            Image(systemName: fallback)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .frame(width: 16, height: 16)
        }
    }

    func officialSubscriptionPanel<Content: View>(
        title: String,
        spacing: CGFloat = 12,
        @ViewBuilder controls: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, height: 12, alignment: .leading)

            controls()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func officialSubscriptionUsageSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> some View {
        let hasNoAccounts = officialSubscriptionHasNoAccounts(provider)
        let shouldShowEmptyState = hasNoAccounts
            || !officialUsageSectionHasData(provider: provider, snapshot: snapshot)

        officialSubscriptionPanel(title: viewModel.localizedText("用量", "Usage"), spacing: 12) {
            if shouldShowEmptyState {
                officialSubscriptionSectionCard(
                    padding: 0,
                    cornerRadius: SettingsVisualTokens.Radius.control,
                    strokeOpacity: 0.15
                ) {
                    officialSubscriptionCenteredPlaceholder(
                        viewModel.localizedText("暂无用量信息", "No usage data yet"),
                        minHeight: 80,
                        textColor: settingsMutedHintColor
                    )
                }
                .onAppear {
                    if !hasNoAccounts {
                        refreshOfficialUsageSectionIfNeeded(provider: provider, snapshot: snapshot)
                    }
                }
            } else {
                officialSubscriptionSectionCard(
                    padding: 0,
                    cornerRadius: SettingsVisualTokens.Radius.control,
                    strokeOpacity: 0.15
                ) {
                    officialLocalTrendSection(
                        provider: provider,
                        snapshot: snapshot,
                        showsDivider: false,
                        showsTitle: false,
                        usesSubscriptionUsageLayout: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    func officialSubscriptionAccountsSection(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(viewModel.localizedText("账号", "Accounts"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(settingsBodyColor)

                Spacer(minLength: 0)

                if provider.type == .codex || provider.type == .claude {
                    HStack(spacing: 8) {
                        officialSubscriptionAddAccountButton(
                            viewModel.localizedText("json添加", "Add JSON"),
                            width: 60
                        ) {
                            if provider.type == .codex {
                                openCodexProfileEditor(slotID: viewModel.nextCodexProfileSlotID(), existingProfile: nil)
                            } else {
                                openClaudeProfileEditor(slotID: viewModel.nextClaudeProfileSlotID(), existingProfile: nil)
                            }
                        }
                        officialSubscriptionAddAccountButton(
                            viewModel.localizedText("OAuth添加", "Add OAuth"),
                            width: 69
                        ) {
                            if provider.type == .codex {
                                viewModel.startOAuthImport(providerType: .codex, slotID: viewModel.nextCodexProfileSlotID())
                            } else {
                                viewModel.startOAuthImport(providerType: .claude, slotID: viewModel.nextClaudeProfileSlotID())
                            }
                        }
                    }
                }
            }
            .frame(width: SettingsVisualTokens.SettingsLayout.configurationWidth, height: 22, alignment: .center)

            officialSubscriptionSectionCard(
                padding: 0,
                cornerRadius: SettingsVisualTokens.Radius.control,
                strokeOpacity: 0.15
            ) {
                if officialSubscriptionHasNoAccounts(provider) {
                    officialSubscriptionCenteredPlaceholder(
                        viewModel.localizedText("快来添加你的第一个账号吧～", "Add your first account to get started"),
                        minHeight: 80,
                        textColor: settingsMutedHintColor
                    )
                } else {
                    officialSubscriptionAccountsList(provider: provider, snapshot: snapshot, error: error)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func officialSubscriptionAddAccountButton(
        _ title: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(SettingsVisualTokens.Text.primary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minWidth: width)
                .frame(height: 22)
                .background(Color.clear)
                .overlay(
                    SettingsSmoothedRoundedRectangle(cornerRadius: SettingsVisualTokens.Radius.compact)
                        .stroke(SettingsVisualTokens.Text.primary, lineWidth: SettingsVisualTokens.Stroke.hairline)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func officialSubscriptionConfigSection(_ provider: ProviderDescriptor) -> some View {
        settingsConfigurationSection(title: viewModel.localizedText("配置", "Configuration")) {
            switch SettingsProviderConfigurationSectionPresenter.sectionKind(for: provider) {
            case .official:
                officialProviderConfigurationContent(provider)
            case .relay:
                relayCondensedConfigSection(provider)
            }
        }
    }

    func officialSubscriptionSectionCard<Content: View>(
        padding: CGFloat = 24,
        cornerRadius: CGFloat = 12,
        strokeOpacity: Double = 0.12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(padding)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.clear)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(strokeOpacity), lineWidth: SettingsVisualTokens.Stroke.hairline)
        )
    }

    func officialSubscriptionCenteredPlaceholder(
        _ text: String,
        minHeight: CGFloat,
        textColor: Color? = nil
    ) -> some View {
        VStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(textColor ?? settingsHintColor)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
    }

    @ViewBuilder
    func officialSubscriptionAccountsList(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?
    ) -> some View {
        switch provider.type {
        case .codex:
            codexProfileManagementSection()
        case .claude:
            claudeProfileManagementSection()
        default:
            officialSingleAccountRow(
                provider: provider,
                snapshot: snapshot,
                error: error
            )
        }
    }

    func officialSubscriptionHasNoAccounts(_ provider: ProviderDescriptor) -> Bool {
        switch provider.type {
        case .codex:
            return viewModel.codexProfilesForSettings().isEmpty
        case .claude:
            return viewModel.claudeProfilesForSettings().isEmpty
        default:
            return false
        }
    }

    var dividerLine: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: SettingsVisualTokens.Menu.dividerHeight)
    }

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
                Text(viewModel.localizedText("从左侧选择一个来源后，这里会显示完整配置。", "Choose a source on the left to inspect and edit its full configuration."))
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
            applyNewRelayTemplate("generic-newapi")
            newRelaySiteDraft.baseURL = ""
            newRelaySiteDraft.credentialInput = ""
            newRelaySiteDraft.userID = ""
            newRelaySiteDraft.testStatusVisible = false
            if newRelaySiteDraft.providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newRelaySiteDraft.providerName = "NewAPI"
            }
            dialogState.isNewAPISiteDialogPresented = true
        } label: {
            Text(viewModel.language == .zhHans ? "添加 NewAPI 站点" : "Add NewAPI Site")
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

    func reorderHandle() -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(settingsHintColor)
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
    }

    func providerReorderHandle(providerID: String) -> some View {
        Button(action: {}) {
            reorderHandle()
        }
        .buttonStyle(.plain)
        .help(viewModel.localizedText("拖拽排序", "Drag to reorder"))
        .accessibilityLabel(viewModel.localizedText("拖拽排序", "Drag to reorder"))
        .onDrag {
            beginProviderReorderDrag(providerID: providerID)
        }
    }

    func beginProviderReorderDrag(providerID: String) -> NSItemProvider {
        navigationState.draggingProviderID = providerID
        navigationState.reorderPreviewProviderIDs = enabledSidebarProviders.map(\.id)
        navigationState.dropTargetProviderID = providerID
        navigationState.dropTargetInsertAfter = false
        installProviderReorderMouseUpMonitors(providerID: providerID)
        return NSItemProvider(object: providerID as NSString)
    }

    func commitProviderReorder() -> Bool {
        defer { resetProviderReorderState() }
        guard let sourceProviderID = navigationState.draggingProviderID else { return false }

        let originalIDs = enabledSidebarProviders.map(\.id)
        let finalIDs = navigationState.reorderPreviewProviderIDs ?? originalIDs

        guard let sourceIndex = originalIDs.firstIndex(of: sourceProviderID),
              let destinationIndex = finalIDs.firstIndex(of: sourceProviderID) else {
            return false
        }

        guard sourceIndex != destinationIndex else { return true }

        moveEnabledProviders(from: IndexSet(integer: sourceIndex), to: destinationIndex)
        navigationState.selectedProviderID = sourceProviderID
        return true
    }

    func resetProviderReorderState() {
        navigationState.clearProviderReorderingState()
        removeProviderReorderMouseUpMonitors()
    }

    func installProviderReorderMouseUpMonitors(providerID: String) {
        removeProviderReorderMouseUpMonitors()
        providerReorderLocalMouseUpMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { event in
            DispatchQueue.main.async {
                if navigationState.draggingProviderID == providerID {
                    resetProviderReorderState()
                }
            }
            return event
        }
        providerReorderGlobalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { _ in
            DispatchQueue.main.async {
                if navigationState.draggingProviderID == providerID {
                    resetProviderReorderState()
                }
            }
        }
    }

    func removeProviderReorderMouseUpMonitors() {
        if let providerReorderLocalMouseUpMonitor {
            NSEvent.removeMonitor(providerReorderLocalMouseUpMonitor)
            self.providerReorderLocalMouseUpMonitor = nil
        }
        if let providerReorderGlobalMouseUpMonitor {
            NSEvent.removeMonitor(providerReorderGlobalMouseUpMonitor)
            self.providerReorderGlobalMouseUpMonitor = nil
        }
    }

    var enabledSidebarProviders: [ProviderDescriptor] {
        sidebarProviders.filter(\.enabled)
    }

    var disabledSidebarProviders: [ProviderDescriptor] {
        sidebarProviders.filter { !$0.enabled }
    }

    var orderedEnabledSidebarProviders: [ProviderDescriptor] {
        let enabledProviders = enabledSidebarProviders
        guard let previewIDs = navigationState.reorderPreviewProviderIDs else { return enabledProviders }

        let providerByID = Dictionary(uniqueKeysWithValues: enabledProviders.map { ($0.id, $0) })
        let ordered = previewIDs.compactMap { providerByID[$0] }
        let missing = enabledProviders.filter { !previewIDs.contains($0.id) }
        return ordered + missing
    }

    var sidebarProviders: [ProviderDescriptor] {
        let providers = viewModel.config.providers.filter { provider in
            switch navigationState.selectedGroup {
            case .official:
                return provider.family == .official || provider.isOfficialRelayProvider
            case .thirdParty:
                return provider.family == .thirdParty && !provider.isOfficialRelayProvider
            }
        }
        return providers.filter(\.enabled) + providers.filter { !$0.enabled }
    }

    var selectedFamily: ProviderFamily {
        switch navigationState.selectedGroup {
        case .official:
            return .official
        case .thirdParty:
            return .thirdParty
        }
    }

    func moveEnabledProviders(from source: IndexSet, to destination: Int) {
        viewModel.reorderEnabledProviders(
            family: selectedFamily,
            fromOffsets: source,
            toOffset: destination
        )
    }

    var selectedProvider: ProviderDescriptor? {
        guard let selectedProviderID = navigationState.selectedProviderID else { return nil }
        return sidebarProviders.first(where: { $0.id == selectedProviderID })
    }

    func syncSelection() {
        let ids = sidebarProviders.map(\.id)
        guard !ids.isEmpty else {
            navigationState.selectedProviderID = nil
            return
        }
        if let selectedProviderID = navigationState.selectedProviderID, ids.contains(selectedProviderID) {
            return
        }
        self.navigationState.selectedProviderID = ids.first
    }

    func sidebarDisplayName(for provider: ProviderDescriptor) -> String {
        ProviderDefinitionRegistry.definition(for: provider).displayName
    }

    func iconName(for provider: ProviderDescriptor) -> String {
        ProviderDefinitionRegistry.definition(for: provider).iconName
    }

    func fallbackIcon(for provider: ProviderDescriptor) -> String {
        ProviderDefinitionRegistry.definition(for: provider).fallbackSystemIcon
    }

    @ViewBuilder
    func providerIcon(for provider: ProviderDescriptor, size: CGFloat) -> some View {
        if let image = themedBundledImage(named: iconName(for: provider)) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackIcon(for: provider))
                .resizable()
                .scaledToFit()
                .foregroundStyle(settingsBodyColor)
                .frame(width: size, height: size)
        }
    }

    func themedBundledImage(named name: String) -> NSImage? {
        if settingsUsesLightAppearance,
           let darkImage = bundledImage(named: "\(name)_dark") {
            return darkImage
        }
        return bundledImage(named: name)
    }

    func bundledImage(named name: String) -> NSImage? {
        if let pngURL = Bundle.module.url(forResource: name, withExtension: "png"),
           let pngImage = NSImage(contentsOf: pngURL) {
            return pngImage
        }
        if let svgURL = Bundle.module.url(forResource: name, withExtension: "svg"),
           let svgImage = NSImage(contentsOf: svgURL) {
            return svgImage
        }
        return nil
    }

    func seedInputsFromConfig() {
        for provider in viewModel.config.providers {
            relayEditorDraft.seed(from: provider)
            officialEditorDraft.seed(from: provider)
        }

        for profile in viewModel.codexProfilesForSettings() {
            let key = profile.slotID.rawValue
            if profileDraftState.codexProfileJSONInputs[key] == nil {
                profileDraftState.codexProfileJSONInputs[key] = profile.authJSON
            }
        }

        for profile in viewModel.claudeProfilesForSettings() {
            let key = profile.slotID.rawValue
            if profileDraftState.claudeProfileJSONInputs[key] == nil {
                profileDraftState.claudeProfileJSONInputs[key] = profile.credentialsJSON ?? ""
            }
            if profileDraftState.claudeProfileConfigDirInputs[key] == nil {
                profileDraftState.claudeProfileConfigDirInputs[key] = profile.configDir ?? ""
            }
        }
    }

    struct ProviderRowDropDelegate: DropDelegate {
        let targetProviderID: String
        let enabledProviderIDs: [String]
        @Binding var draggingProviderID: String?
        @Binding var previewProviderIDs: [String]?
        @Binding var dropTargetProviderID: String?
        @Binding var dropTargetInsertAfter: Bool
        let onPerformDrop: () -> Bool
        var insertAfterThresholdY: CGFloat = 19

        func validateDrop(info: DropInfo) -> Bool {
            draggingProviderID != nil
        }

        func dropEntered(info: DropInfo) {
            updatePreview(with: info)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            updatePreview(with: info)
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            if dropTargetProviderID == targetProviderID {
                dropTargetProviderID = nil
            }
        }

        func performDrop(info: DropInfo) -> Bool {
            updatePreview(with: info)
            return onPerformDrop()
        }

        private func updatePreview(with info: DropInfo) {
            guard let draggingProviderID else { return }
            guard draggingProviderID != targetProviderID else {
                dropTargetProviderID = nil
                return
            }

            let insertAfter = info.location.y > insertAfterThresholdY
            dropTargetProviderID = targetProviderID
            dropTargetInsertAfter = insertAfter

            var ids = previewProviderIDs ?? enabledProviderIDs
            guard let sourceIndex = ids.firstIndex(of: draggingProviderID),
                  let targetIndex = ids.firstIndex(of: targetProviderID) else {
                return
            }

            let destinationIndex = Self.destinationIndex(
                sourceIndex: sourceIndex,
                targetIndex: targetIndex,
                insertAfter: insertAfter
            )

            if sourceIndex == destinationIndex || sourceIndex + 1 == destinationIndex {
                previewProviderIDs = ids
                return
            }

            ids.remove(at: sourceIndex)
            let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
            ids.insert(draggingProviderID, at: adjustedDestination)
            previewProviderIDs = ids
        }

        private static func destinationIndex(
            sourceIndex: Int,
            targetIndex: Int,
            insertAfter: Bool
        ) -> Int {
            if sourceIndex < targetIndex {
                return insertAfter ? targetIndex + 1 : targetIndex
            }
            return insertAfter ? targetIndex + 1 : targetIndex
        }
    }
}
