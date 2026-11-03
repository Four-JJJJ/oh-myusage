import OhMyUsageDomain
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var relayNewSiteDraftConfigPanel: some View {
        let newSiteManifest = selectedNewRelaySiteManifest()
        let newSiteRequiredInputs = relayRequiredInputs(
            for: newSiteManifest,
            tokenChannelEnabled: newSiteManifest.tokenRequest != nil && newSiteManifest.match.defaultTokenChannelEnabled,
            accountChannelEnabled: newSiteManifest.match.defaultBalanceChannelEnabled,
            showsManualUserID: relayTemplateNeedsManualUserID(newSiteManifest)
        )
        let showBaseURLField = newSiteRequiredInputs.contains(.baseURL)
        let showCredentialField = newSiteRequiredInputs.contains(.balanceAuth) || newSiteRequiredInputs.contains(.quotaAuth)
        let showUserIDField = newSiteRequiredInputs.contains(.userID)
        let credentialTemplate = relayCredentialTemplate(
            authHeader: newSiteManifest.balanceRequest.authHeader,
            authScheme: newSiteManifest.balanceRequest.authScheme
        )

        settingsConfigurationSection(title: viewModel.text(.configurationSection)) {
            settingsConfigurationRows {
                if newRelaySiteDraft.selectedPresetID == nil {
                    relayCompactConfigRow(title: viewModel.text(.relaySiteType)) {
                        relayPillControl(
                            selection: newRelaySiteDraft.templateID,
                            options: [
                                (RelayAdapterRegistry.genericNewAPIAdapterID, "NewAPI"),
                                (RelayAdapterRegistry.genericSub2APIAdapterID, "Sub2API")
                            ],
                            width: 176
                        ) { selection in
                            applyGenericRelaySiteTemplate(selection)
                        }
                    }
                }

                relayCompactConfigRow(title: viewModel.text(.relayUsagePreference)) {
                    relayPillControl(
                        selection: OfficialQuotaDisplayMode.remaining.id,
                        options: [
                            (OfficialQuotaDisplayMode.remaining.id, viewModel.text(.quotaDisplayRemaining)),
                            (OfficialQuotaDisplayMode.used.id, viewModel.text(.quotaDisplayUsed))
                        ],
                        width: 136
                    ) { _ in }
                    .allowsHitTesting(false)
                }

                if showBaseURLField {
                    relayCompactConfigRow(title: viewModel.text(.relaySiteAddress)) {
                        settingsConfigTextField(
                            viewModel.text(.relaySiteAddressPlaceholder),
                            text: Binding(
                                get: { newRelaySiteDraft.baseURL },
                                set: {
                                    newRelaySiteDraft.baseURL = $0
                                    newRelaySiteDraft.testState = .unverified
                                }
                            )
                        )
                    }
                } else if let suggestedBaseURL = suggestedBaseURL(for: newSiteManifest) {
                    thirdPartyHintText("Base URL: \(suggestedBaseURL)")
                }

                VStack(alignment: .leading, spacing: 5) {
                    relayCompactConfigRow(title: viewModel.text(.relayCredentialMode)) {
                        relayPillControl(
                            selection: RelayCredentialMode.browserPreferred.id,
                            options: relayCredentialModeConfigOptions,
                            width: 252,
                            segmentWidths: relayCredentialModeConfigSegmentWidths
                        ) { _ in }
                        .allowsHitTesting(false)
                    }

                    thirdPartyHintText(
                        viewModel.text(.relayCredentialModeHint)
                    )
                }

                if showCredentialField {
                    VStack(alignment: .leading, spacing: 5) {
                        relayCompactConfigRow(title: viewModel.text(.relayCredential)) {
                            settingsConfigSecureField(
                                credentialTemplate.placeholder,
                                text: Binding(
                                    get: { newRelaySiteDraft.credentialInput },
                                    set: {
                                        newRelaySiteDraft.credentialInput = $0
                                        newRelaySiteDraft.testState = .unverified
                                    }
                                )
                            )
                        }

                        thirdPartyHintText(credentialTemplate.hint)
                        if let balanceHint = relaySetupHint(for: newSiteManifest, field: .balanceAuth) {
                            thirdPartyHintText(balanceHint)
                        }
                    }
                }

                if showUserIDField {
                    VStack(alignment: .leading, spacing: 5) {
                        relayCompactConfigRow(title: "User ID") {
                            settingsConfigTextField(
                                viewModel.text(.relayUserIDPlaceholder),
                                text: Binding(
                                    get: { newRelaySiteDraft.userID },
                                    set: {
                                        newRelaySiteDraft.userID = $0
                                        newRelaySiteDraft.testState = .unverified
                                    }
                                )
                            )
                        }

                        if let userIDHint = relaySetupHint(for: newSiteManifest, field: .userID) {
                            thirdPartyHintText(userIDHint)
                        }
                    }
                }

                HStack(spacing: 12) {
                    settingsSmallOutlineButton(viewModel.text(.relayTestConnection), width: 60) {
                        let selectedManifest = selectedNewRelaySiteManifest()
                        let resolvedBaseURL = resolvedRelayBaseURLInput(
                            typedBaseURL: newRelaySiteDraft.baseURL,
                            manifest: selectedManifest
                        )
                        let typedName = newRelaySiteDraft.providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? relayDefaultNewSiteTitle
                            : newRelaySiteDraft.providerName
                        newRelaySiteDraft.testState = .testing
                        Task {
                            let result = await providerConfigurationFacade.testNewRelaySiteDraft(
                                name: resolvedRelayNameInput(typedName: typedName, manifest: selectedManifest),
                                baseURL: resolvedBaseURL,
                                preferredAdapterID: newRelaySiteDraft.selectedPresetID ?? newRelaySiteDraft.templateID,
                                userID: newRelaySiteDraft.userID,
                                credentialInput: newRelaySiteDraft.credentialInput
                            )
                            // 测试期间输入又被改动过（状态被重置为 unverified）则不覆盖
                            guard newRelaySiteDraft.testState == .testing else { return }
                            newRelaySiteDraft.testState = result.success ? .success : .failure(result.message)
                        }
                    }

                    settingsSmallOutlineButton(viewModel.text(.relaySaveSite), width: 60) {
                        saveNewRelaySiteDraft()
                    }

                    switch newRelaySiteDraft.testState {
                    case .unverified:
                        Text(viewModel.text(.relayNotVerifiedHint))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.40))
                            .lineLimit(1)
                    case .testing:
                        Text(viewModel.text(.relayTesting))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.60))
                            .lineLimit(1)
                    case .success:
                        Text(viewModel.text(.relayConnectionHealthy))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color(hex: 0x69BD64))
                            .lineLimit(1)
                    case .failure(let message):
                        Text(message)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color(hex: 0xEB654F))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, thirdPartyConfigLabelWidth + thirdPartyConfigLabelSpacing - 3)
            }
        }
    }
}
