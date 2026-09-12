import Foundation
import OhMyUsageDomain

struct AppProviderListMutationOutcome: Equatable {
    var shouldPersistAndRestart: Bool = false
    var shouldNotifyDisplayConfigChange: Bool = false
    var shouldRefreshDisplayedProviders: Bool = false
    var removedThirdPartyBaselineProviderIDs: [String] = []

    static let none = AppProviderListMutationOutcome()
}

struct AppProviderListMutationCoordinator {
    func setEnabled(
        _ enabled: Bool,
        providerID: String,
        config: inout AppConfig
    ) -> AppProviderListMutationOutcome {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }) else { return .none }
        if config.providers[idx].enabled == enabled { return .none }

        var removedBaselineIDs: [String] = []
        if !enabled, config.providers[idx].family == .thirdParty {
            removedBaselineIDs = [providerID]
        }
        config.providers[idx].enabled = enabled
        if enabled {
            config.providers[idx].showInMenuBar = true
        }

        if enabled {
            let provider = config.providers.remove(at: idx)
            let family = provider.family
            let familyIndices = config.providers.indices.filter { config.providers[$0].family == family }
            let enabledFamilyIndices = familyIndices.filter { config.providers[$0].enabled }

            let insertAt: Int
            if let lastEnabled = enabledFamilyIndices.last {
                insertAt = lastEnabled + 1
            } else if let firstFamily = familyIndices.first {
                insertAt = firstFamily
            } else {
                insertAt = config.providers.count
            }
            config.providers.insert(provider, at: min(max(0, insertAt), config.providers.count))
        }

        if !enabled, config.statusBarProviderID == providerID {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        } else if enabled {
            config.statusBarProviderID = providerID
        }

        if config.statusBarMultiUsageEnabled {
            if enabled {
                if !config.statusBarMultiProviderIDs.contains(providerID) {
                    config.statusBarMultiProviderIDs.append(providerID)
                }
            } else {
                config.statusBarMultiProviderIDs.removeAll { $0 == providerID }
            }
            config.statusBarMultiProviderIDs = AppConfig.statusBarMultiProviderIDsMatchingProviderOrder(
                config.statusBarMultiProviderIDs,
                providers: config.providers
            )
        }

        return AppProviderListMutationOutcome(
            shouldPersistAndRestart: true,
            shouldNotifyDisplayConfigChange: true,
            shouldRefreshDisplayedProviders: true,
            removedThirdPartyBaselineProviderIDs: removedBaselineIDs
        )
    }

    func reorderEnabledProviders(
        family: ProviderFamily,
        fromOffsets: IndexSet,
        toOffset: Int,
        config: inout AppConfig
    ) -> AppProviderListMutationOutcome {
        let enabledIndices = config.providers.indices.filter {
            config.providers[$0].family == family && config.providers[$0].enabled
        }
        guard enabledIndices.count > 1 else { return .none }

        var enabledProviders = enabledIndices.map { config.providers[$0] }
        moveArray(&enabledProviders, fromOffsets: fromOffsets, toOffset: toOffset)

        for (position, index) in enabledIndices.enumerated() {
            config.providers[index] = enabledProviders[position]
        }

        config.statusBarMultiProviderIDs = AppConfig.statusBarMultiProviderIDsMatchingProviderOrder(
            config.statusBarMultiProviderIDs,
            providers: config.providers
        )

        return AppProviderListMutationOutcome(
            shouldPersistAndRestart: true,
            shouldNotifyDisplayConfigChange: true
        )
    }

    func commitThreshold(
        _ value: Double,
        providerID: String,
        config: inout AppConfig
    ) -> AppProviderListMutationOutcome {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }) else { return .none }
        let clamped = min(max(value, 0), 100)
        guard config.providers[idx].threshold.lowRemaining != clamped else { return .none }
        config.providers[idx].threshold.lowRemaining = clamped
        return AppProviderListMutationOutcome(shouldPersistAndRestart: true)
    }

    private func moveArray<T>(_ array: inout [T], fromOffsets: IndexSet, toOffset: Int) {
        let moving = fromOffsets.sorted().map { array[$0] }
        for index in fromOffsets.sorted(by: >) {
            array.remove(at: index)
        }
        let insertion = min(max(0, toOffset), array.count)
        array.insert(contentsOf: moving, at: insertion)
    }
}
