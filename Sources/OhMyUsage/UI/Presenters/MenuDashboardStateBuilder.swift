import OhMyUsageDomain
import Foundation

enum MenuDashboardStateBuilder {
    static func build(
        config: AppConfig,
        snapshots: [String: UsageSnapshot],
        errors: [String: String],
        lastUpdatedAt: Date?,
        updateState: MenuUpdateDisplayState,
        now: Date,
        shouldShowPermissionGuide: Bool,
        codexSlots: [CodexSlotViewModel],
        claudeSlots: [ClaudeSlotViewModel],
        localization: MenuViewLocalization
    ) -> MenuViewState {
        let header = MenuDashboardPresenter.headerPresentation(
            lastUpdatedAt: lastUpdatedAt,
            language: config.language,
            now: now,
            updatedAgoLabel: localization.updatedAgoLabel,
            updateState: updateState
        )
        let cards = displayProviders(from: config.providers).compactMap { provider in
            cardState(
                for: provider,
                snapshots: snapshots,
                errors: errors,
                language: config.language,
                showOfficialAccountEmail: config.showOfficialAccountEmailInMenuBar,
                now: now,
                codexSlots: codexSlots,
                claudeSlots: claudeSlots,
                localization: localization
            )
        }

        return MenuViewState(
            header: header,
            shouldShowPermissionGuide: shouldShowPermissionGuide,
            cards: cards
        )
    }

    private static func displayProviders(from providers: [ProviderDescriptor]) -> [ProviderDescriptor] {
        let enabledProviders = providers.filter(\.enabled)
        let officialProviders = enabledProviders.filter { $0.family == .official }
        let thirdPartyProviders = enabledProviders.filter { $0.family == .thirdParty }
        return officialProviders + thirdPartyProviders
    }

    private static func cardState(
        for provider: ProviderDescriptor,
        snapshots: [String: UsageSnapshot],
        errors: [String: String],
        language: AppLanguage,
        showOfficialAccountEmail: Bool,
        now: Date,
        codexSlots: [CodexSlotViewModel],
        claudeSlots: [ClaudeSlotViewModel],
        localization: MenuViewLocalization
    ) -> MenuCardViewState? {
        if provider.family == .official && provider.type == .codex {
            let codexTeamAliases = MenuSubtitlePresenter.codexTeamAliasMap(from: codexSlots.map(\.snapshot))
            let slotPresentations = codexSlots.map {
                codexSlotPresentation(
                    $0,
                    provider: provider,
                    codexTeamAliases: codexTeamAliases,
                    language: language,
                    showOfficialAccountEmail: showOfficialAccountEmail,
                    now: now,
                    localization: localization
                )
            }
            if !codexSlots.isEmpty,
               let group = MenuOfficialProviderGroupPresenter.group(from: slotPresentations) {
                return .officialGroup(
                    MenuOfficialProviderGroupCardViewState(
                        id: provider.id,
                        switchKind: .codex,
                        iconName: "menu_codex_icon",
                        iconFallback: "terminal.fill",
                        group: group
                    )
                )
            }
            return singleProviderCardState(
                for: provider,
                snapshot: snapshots[provider.id],
                error: errors[provider.id],
                language: language,
                showOfficialAccountEmail: showOfficialAccountEmail,
                codexTeamAliases: codexTeamAliases,
                now: now,
                localization: localization
            )
        }

        if provider.family == .official && provider.type == .claude {
            guard let group = MenuOfficialProviderGroupPresenter.group(
                from: claudeSlots.map {
                    claudeSlotPresentation(
                        $0,
                        provider: provider,
                        language: language,
                        showOfficialAccountEmail: showOfficialAccountEmail,
                        now: now,
                        localization: localization
                    )
                }
            ) else {
                return nil
            }
            return .officialGroup(
                MenuOfficialProviderGroupCardViewState(
                    id: provider.id,
                    switchKind: .claude,
                    iconName: iconName(for: provider),
                    iconFallback: fallbackIcon(for: provider),
                    group: group
                )
            )
        }

        return singleProviderCardState(
            for: provider,
            snapshot: snapshots[provider.id],
            error: errors[provider.id],
            language: language,
            showOfficialAccountEmail: showOfficialAccountEmail,
            codexTeamAliases: [:],
            now: now,
            localization: localization
        )
    }

    private static func singleProviderCardState(
        for provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        error: String?,
        language: AppLanguage,
        showOfficialAccountEmail: Bool,
        codexTeamAliases: [String: String],
        now: Date,
        localization: MenuViewLocalization
    ) -> MenuCardViewState {
        if ProviderCapabilities.capabilities(for: provider).usesPercentageMenuCard {
            let metrics = MenuQuotaPresenter.quotaMetrics(
                provider: provider,
                snapshot: snapshot,
                language: language,
                localization: localization.quota
            )
            let visibleMetrics = MenuQuotaPresenter.visibleMetrics(
                provider: provider,
                metrics: metrics,
                language: language,
                localization: localization.quota
            )
            let visual = percentageVisualPresentation(
                snapshot: snapshot,
                errorText: error,
                healthPercents: visibleMetrics.map(\.healthPercent),
                language: language,
                localization: localization
            )
            let metricDisplays = quotaMetricDisplays(
                from: visibleMetrics,
                blockageCandidates: metrics,
                provider: provider,
                snapshot: snapshot,
                disconnected: visual.isDisconnected,
                language: language,
                now: now
            )

            return .percentage(
                MenuPercentageCardViewState(
                    id: provider.id,
                    title: displayName(for: provider),
                    planType: MenuCardStatusPresenter.planType(for: provider, snapshot: snapshot),
                    iconName: iconName(for: provider),
                    iconFallback: fallbackIcon(for: provider),
                    subtitle: provider.isRelay
                        ? MenuSubtitlePresenter.relayQuotaSubtitle(
                            snapshot: snapshot,
                            language: language,
                            showExpirationTime: provider.showsExpirationTimeInMenuBar
                        )
                        : provider.family == .official
                        ? MenuSubtitlePresenter.officialAccountSubtitle(
                            providerType: provider.type,
                            snapshot: snapshot,
                            showAccountEmail: showOfficialAccountEmail,
                            codexTeamAliases: codexTeamAliases
                        )
                        : MenuSubtitlePresenter.relayQuotaSubtitle(
                            snapshot: snapshot,
                            language: language,
                            showExpirationTime: provider.showsExpirationTimeInMenuBar
                        ),
                    status: visual.status,
                    metrics: metricDisplays,
                    errorText: visual.errorText,
                    isDisconnected: visual.isDisconnected,
                    showsErrorHighlight: visual.showsErrorHighlight
                )
            )
        }

        let amountPresentation = MenuCardStatePresenter.amountPresentation(
            provider: provider,
            snapshot: snapshot,
            errorText: error,
            language: language,
            secondaryText: MenuSubtitlePresenter.relaySecondaryText(
                provider: provider,
                snapshot: snapshot,
                language: language
            ),
            usedLabel: localization.usedLabel,
            balanceLabel: localization.balanceLabel,
            tightText: localization.tightText,
            sufficientText: localization.sufficientText,
            exhaustedText: localization.exhaustedText,
            disconnectedText: localization.disconnectedText
        )

        return .amount(
            MenuAmountCardViewState(
                id: provider.id,
                title: displayName(for: provider),
                planType: MenuCardStatusPresenter.planType(for: provider, snapshot: snapshot),
                iconName: iconName(for: provider),
                iconFallback: fallbackIcon(for: provider),
                status: amountPresentation.visual.status,
                amountText: amountPresentation.amountText,
                secondaryText: amountPresentation.secondaryText,
                errorText: amountPresentation.visual.errorText,
                isDisconnected: amountPresentation.visual.isDisconnected,
                showsErrorHighlight: amountPresentation.visual.showsErrorHighlight,
                balanceLabel: amountPresentation.balanceLabel
            )
        )
    }

    private static func codexSlotPresentation(
        _ slot: CodexSlotViewModel,
        provider: ProviderDescriptor,
        codexTeamAliases: [String: String],
        language: AppLanguage,
        showOfficialAccountEmail: Bool,
        now: Date,
        localization: MenuViewLocalization
    ) -> MenuOfficialSlotCardPresentation<CodexSlotID> {
        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: slot.snapshot,
            language: language,
            localization: localization.quota
        )
        let visibleMetrics = MenuQuotaPresenter.visibleMetrics(
            provider: provider,
            metrics: metrics,
            language: language,
            localization: localization.quota
        )
        let metricDisplays = quotaMetricDisplays(
            from: visibleMetrics,
            blockageCandidates: metrics,
            provider: provider,
            snapshot: slot.snapshot,
            disconnected: false,
            language: language,
            now: now
        )

        return MenuOfficialProviderGroupPresenter.slotCardPresentation(
            id: slot.slotID,
            title: slot.title,
            planType: MenuCardStatusPresenter.planType(for: provider, snapshot: slot.snapshot),
            subtitle: MenuSubtitlePresenter.officialAccountSubtitle(
                providerType: provider.type,
                snapshot: slot.snapshot,
                showAccountEmail: showOfficialAccountEmail,
                codexTeamAliases: codexTeamAliases
            ),
            status: percentageStatus(
                snapshot: slot.snapshot,
                healthPercents: visibleMetrics.map(\.healthPercent),
                disconnected: false,
                language: language,
                localization: localization
            ),
            metricDisplays: metricDisplays,
            isActive: slot.isActive,
            canSwitch: slot.canSwitch,
            isSwitching: slot.isSwitching,
            switchActionLabel: localization.codexSwitchAction
        )
    }

    private static func claudeSlotPresentation(
        _ slot: ClaudeSlotViewModel,
        provider: ProviderDescriptor,
        language: AppLanguage,
        showOfficialAccountEmail: Bool,
        now: Date,
        localization: MenuViewLocalization
    ) -> MenuOfficialSlotCardPresentation<CodexSlotID> {
        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: provider,
            snapshot: slot.snapshot,
            language: language,
            localization: localization.quota
        )
        let visibleMetrics = MenuQuotaPresenter.visibleMetrics(
            provider: provider,
            metrics: metrics,
            language: language,
            localization: localization.quota
        )
        let metricDisplays = quotaMetricDisplays(
            from: visibleMetrics,
            blockageCandidates: metrics,
            provider: provider,
            snapshot: slot.snapshot,
            disconnected: false,
            language: language,
            now: now
        )

        return MenuOfficialProviderGroupPresenter.slotCardPresentation(
            id: slot.slotID,
            title: slot.title,
            planType: MenuCardStatusPresenter.planType(for: provider, snapshot: slot.snapshot),
            subtitle: MenuSubtitlePresenter.officialAccountSubtitle(
                providerType: provider.type,
                snapshot: slot.snapshot,
                showAccountEmail: showOfficialAccountEmail
            ),
            status: percentageStatus(
                snapshot: slot.snapshot,
                healthPercents: visibleMetrics.map(\.healthPercent),
                disconnected: false,
                language: language,
                localization: localization
            ),
            metricDisplays: metricDisplays,
            isActive: slot.isActive,
            canSwitch: slot.canSwitch,
            isSwitching: slot.isSwitching,
            switchActionLabel: localization.claudeSwitchAction
        )
    }

    private static func quotaMetricDisplays(
        from metrics: [MenuQuotaMetric],
        blockageCandidates: [MenuQuotaMetric],
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        disconnected: Bool,
        language: AppLanguage,
        now: Date
    ) -> [MenuQuotaMetricDisplayPresentation] {
        MenuQuotaPresenter.metricDisplays(
            metrics: metrics,
            blockageCandidates: blockageCandidates,
            provider: provider,
            snapshot: snapshot,
            disconnected: disconnected,
            language: language,
            now: now
        )
    }

    private static func percentageVisualPresentation(
        snapshot: UsageSnapshot?,
        errorText: String?,
        healthPercents: [Double?],
        language: AppLanguage,
        localization: MenuViewLocalization
    ) -> MenuCardVisualPresentation {
        MenuCardStatePresenter.percentageVisualPresentation(
            snapshot: snapshot,
            errorText: errorText,
            healthPercents: healthPercents,
            language: language,
            tightText: localization.tightText,
            sufficientText: localization.sufficientText,
            exhaustedText: localization.exhaustedText,
            disconnectedText: localization.disconnectedText
        )
    }

    private static func percentageStatus(
        snapshot: UsageSnapshot?,
        healthPercents: [Double?],
        disconnected: Bool,
        language: AppLanguage,
        localization: MenuViewLocalization
    ) -> MenuCardStatusPresentation {
        MenuCardStatusPresenter.percentageStatus(
            healthPercents: healthPercents,
            snapshot: snapshot,
            disconnected: disconnected,
            language: language,
            tightText: localization.tightText,
            sufficientText: localization.sufficientText,
            exhaustedText: localization.exhaustedText,
            disconnectedText: localization.disconnectedText
        )
    }

    private static func displayName(for provider: ProviderDescriptor) -> String {
        ProviderDefinitionRegistry.definition(for: provider).displayName
    }

    private static func iconName(for provider: ProviderDescriptor) -> String {
        ProviderDefinitionRegistry.definition(for: provider).iconName
    }

    private static func fallbackIcon(for provider: ProviderDescriptor) -> String {
        ProviderDefinitionRegistry.definition(for: provider).fallbackSystemIcon
    }
}
