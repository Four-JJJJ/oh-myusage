import Foundation
import OhMyUsageDomain

enum AppConfigSiteDefaultsMigrator {
    static func migrated(_ config: AppConfig) -> AppConfig {
        var migrated = config

        // Remove legacy Kimi (For Coding) provider: keep official Kimi only.
        migrated.providers.removeAll { provider in
            provider.id == "kimi-coding" || (provider.type == .kimi && provider.family == .thirdParty)
        }
        // Remove historical sample relay entries from older builds.
        migrated.providers.removeAll(where: isLegacyRelayExampleProvider)

        let officialRelayProviderIDMap = migrateOfficialRelayProvidersToStableIDs(&migrated.providers)

        for defaultProvider in AppConfig.default.providers {
            if let idx = migrated.providers.firstIndex(where: { $0.id == defaultProvider.id }) {
                migrated.providers[idx] = migratedSiteDefaults(migrated.providers[idx], from: defaultProvider)
            } else {
                migrated.providers.append(defaultProvider)
            }
        }
        migrateOfficialRelayDefaultOrderAfterKimiIfNeeded(&migrated.providers)

        for idx in migrated.providers.indices {
            let providerID = migrated.providers[idx].id
            guard providerID == "codex-official" || providerID == "claude-official" else {
                continue
            }
            // Only migrate historical defaults; keep user-custom intervals untouched.
            if migrated.providers[idx].pollIntervalSec == 60 {
                migrated.providers[idx].pollIntervalSec = 120
            }
        }

        if let selected = migrated.statusBarProviderID,
           let remapped = officialRelayProviderIDMap[selected] {
            migrated.statusBarProviderID = remapped
        }
        migrated.statusBarMultiProviderIDs = migrated.statusBarMultiProviderIDs.map {
            officialRelayProviderIDMap[$0] ?? $0
        }

        if let selected = migrated.statusBarProviderID,
           migrated.providers.contains(where: { $0.id == selected }) == false {
            migrated.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: migrated.providers)
        }
        if migrated.statusBarProviderID == nil {
            migrated.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: migrated.providers)
        }
        migrated.statusBarMultiProviderIDs = AppConfig.normalizedStatusBarMultiProviderIDs(
            migrated.statusBarMultiProviderIDs,
            providers: migrated.providers
        )
        if migrated.statusBarMultiProviderIDs.isEmpty,
           let selected = migrated.statusBarProviderID {
            migrated.statusBarMultiProviderIDs = [selected]
        }

        return migrated
    }

    private static func migrateOfficialRelayDefaultOrderAfterKimiIfNeeded(_ providers: inout [ProviderDescriptor]) {
        let preferredIDs = ProviderDescriptor.officialRelayDefaultProviderOrder
        let preferredIDSet = Set(preferredIDs)
        let providerIDs = providers.map(\.id)
        let existingPreferredIDs = preferredIDs.filter { providerIDs.contains($0) }
        guard !existingPreferredIDs.isEmpty,
              let kimiIndex = providerIDs.firstIndex(of: "kimi-official") else {
            return
        }

        let afterKimiStart = providerIDs.index(after: kimiIndex)
        if afterKimiStart + existingPreferredIDs.count <= providerIDs.endIndex {
            let afterKimiIDs = Array(providerIDs[afterKimiStart..<(afterKimiStart + existingPreferredIDs.count)])
            if afterKimiIDs == existingPreferredIDs {
                return
            }
        }

        let relayIDsInCurrentOrder = providerIDs.filter { preferredIDSet.contains($0) }
        guard relayIDsInCurrentOrder == existingPreferredIDs,
              shouldMigrateOfficialRelayDefaultOrder(providerIDs: providerIDs, relayIDs: existingPreferredIDs) else {
            return
        }

        let movingProviders = existingPreferredIDs.compactMap { id in
            providers.first(where: { $0.id == id })
        }
        providers.removeAll { preferredIDSet.contains($0.id) }
        guard let updatedKimiIndex = providers.firstIndex(where: { $0.id == "kimi-official" }) else {
            providers.append(contentsOf: movingProviders)
            return
        }
        providers.insert(contentsOf: movingProviders, at: providers.index(after: updatedKimiIndex))
    }

    private static func shouldMigrateOfficialRelayDefaultOrder(providerIDs: [String], relayIDs: [String]) -> Bool {
        guard let firstRelayIndex = relayIDs.compactMap({ providerIDs.firstIndex(of: $0) }).min() else {
            return false
        }

        if let openCodeIndex = providerIDs.firstIndex(of: "opencode-go-official"),
           firstRelayIndex > openCodeIndex {
            return true
        }

        return firstRelayIndex >= providerIDs.count - relayIDs.count
    }

    private static func isLegacyRelayExampleProvider(_ provider: ProviderDescriptor) -> Bool {
        provider.isLegacyRelayExample
    }

    private static func migrateOfficialRelayProvidersToStableIDs(_ providers: inout [ProviderDescriptor]) -> [String: String] {
        var migratedProviders: [ProviderDescriptor] = []
        var providerIDMap: [String: String] = [:]

        for provider in providers {
            var normalized = provider.normalized()
            guard normalized.isOfficialRelayProvider,
                  let targetID = normalized.officialRelayDefaultProviderID else {
                migratedProviders.append(normalized)
                continue
            }

            if normalized.id != targetID {
                providerIDMap[normalized.id] = targetID
                normalized.id = targetID
            }
            normalized.family = .official
            if let adapterID = normalized.officialRelayAdapterID,
               let displayName = ProviderDescriptor.officialRelayDisplayName(adapterID: adapterID) {
                normalized.name = displayName
            }

            if let existingIndex = migratedProviders.firstIndex(where: { $0.id == targetID }) {
                migratedProviders[existingIndex] = mergedOfficialRelayProvider(
                    current: migratedProviders[existingIndex],
                    legacy: normalized
                )
            } else {
                migratedProviders.append(normalized)
            }
        }

        providers = migratedProviders
        return providerIDMap
    }

    private static func mergedOfficialRelayProvider(
        current: ProviderDescriptor,
        legacy: ProviderDescriptor
    ) -> ProviderDescriptor {
        var merged = current
        merged.family = .official
        merged.type = .relay
        merged.enabled = current.enabled || legacy.enabled
        if legacy.pollIntervalSec > 0 {
            merged.pollIntervalSec = legacy.pollIntervalSec
        }
        merged.threshold = legacy.threshold
        merged.auth = legacy.auth
        if let baseURL = legacy.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !baseURL.isEmpty {
            merged.baseURL = baseURL
        }
        if let relayConfig = legacy.relayConfig {
            merged.relayConfig = relayConfig
        }
        if let adapterID = merged.officialRelayAdapterID,
           let displayName = ProviderDescriptor.officialRelayDisplayName(adapterID: adapterID) {
            merged.name = displayName
        }
        merged.officialConfig = nil
        merged.openConfig = nil
        return merged.normalized()
    }

    private static func migratedSiteDefaults(
        _ provider: ProviderDescriptor,
        from defaults: ProviderDescriptor
    ) -> ProviderDescriptor {
        var copy = provider

        copy.family = defaults.family
        if defaults.isRelay,
           ProviderDescriptor.officialRelayDefaultProviderIDs.contains(copy.id) {
            copy.type = defaults.type
            copy.officialConfig = nil
        }

        if (copy.baseURL ?? "").isEmpty {
            copy.baseURL = defaults.baseURL
        }

        if copy.isRelay, defaults.isRelay {
            return migratedRelayDefaults(copy, from: defaults)
        }

        if defaults.family == .official {
            if copy.officialConfig == nil {
                copy.officialConfig = defaults.officialConfig
            } else {
                if var official = copy.officialConfig {
                    let manualCookieAccount = official.manualCookieAccount
                    official.manualCookieAccount = manualCookieAccount ?? defaults.officialConfig?.manualCookieAccount
                    copy.officialConfig = official
                }
            }
            if copy.pollIntervalSec <= 0 {
                copy.pollIntervalSec = defaults.pollIntervalSec
            }
            return copy.normalized()
        }

        if copy.type == .kimi {
            if copy.kimiConfig == nil {
                copy.kimiConfig = defaults.kimiConfig
            } else if copy.kimiConfig?.browserOrder.isEmpty ?? true {
                copy.kimiConfig?.browserOrder = defaults.kimiConfig?.browserOrder
                    ?? [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]
            }
            return copy.normalized()
        }

        guard copy.isRelay,
              let defaultRelay = defaults.relayConfig else {
            return copy.normalized()
        }

        if copy.relayConfig == nil {
            copy.relayConfig = defaultRelay
            return copy.normalized()
        }

        guard var relay = copy.relayConfig else {
            return copy.normalized()
        }

        if copy.id == "open-ailinyu" {
            if copy.pollIntervalSec < 120 {
                copy.pollIntervalSec = 120
            }
        }

        relay.adapterID = relay.adapterID ?? defaultRelay.adapterID
        relay.baseURL = ProviderDescriptor.normalizeRelayBaseURL(
            relay.baseURL.isEmpty ? (copy.baseURL ?? defaults.baseURL ?? defaultRelay.baseURL) : relay.baseURL
        )
        relay.balanceAuth = relay.balanceAuth.withFallback(
            service: defaultRelay.balanceAuth.keychainService ?? KeychainService.defaultServiceName,
            account: defaultRelay.balanceAuth.keychainAccount
        )
        if relay.manualOverrides == nil {
            relay.manualOverrides = defaultRelay.manualOverrides
        }
        relay = migratedOfficialRelayAdapterDefaults(relay, providerID: copy.id, defaults: defaultRelay)
        copy.relayConfig = relay
        return copy.normalized()
    }

    private static func migratedRelayDefaults(
        _ provider: ProviderDescriptor,
        from defaults: ProviderDescriptor
    ) -> ProviderDescriptor {
        var copy = provider
        copy.family = defaults.family

        if (copy.baseURL ?? "").isEmpty {
            copy.baseURL = defaults.baseURL
        }
        if copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.name = defaults.name
        }
        if copy.relayConfig == nil {
            copy.relayConfig = defaults.relayConfig
            return copy.normalized()
        }

        guard var relay = copy.relayConfig,
              let defaultRelay = defaults.relayConfig else {
            return copy.normalized()
        }

        relay.adapterID = relay.adapterID ?? defaultRelay.adapterID
        relay.baseURL = ProviderDescriptor.normalizeRelayBaseURL(
            relay.baseURL.isEmpty ? (copy.baseURL ?? defaults.baseURL ?? defaultRelay.baseURL) : relay.baseURL
        )
        relay.balanceAuth = relay.balanceAuth.withFallback(
            service: defaultRelay.balanceAuth.keychainService ?? KeychainService.defaultServiceName,
            account: defaultRelay.balanceAuth.keychainAccount
        )
        if relay.manualOverrides == nil {
            relay.manualOverrides = defaultRelay.manualOverrides
        }
        relay = migratedOfficialRelayAdapterDefaults(relay, providerID: copy.id, defaults: defaultRelay)
        copy.relayConfig = relay
        return copy.normalized()
    }

    private static func migratedOfficialRelayAdapterDefaults(
        _ relay: RelayProviderConfig,
        providerID: String,
        defaults: RelayProviderConfig
    ) -> RelayProviderConfig {
        var copy = relay
        guard providerID == "xiaomi-mimo-official",
              defaults.adapterID == "xiaomimimo-token-plan" else {
            return copy
        }
        let isMigratingLegacyAdapter = copy.adapterID != defaults.adapterID
        copy.adapterID = defaults.adapterID
        if isMigratingLegacyAdapter {
            copy.tokenChannelEnabled = defaults.tokenChannelEnabled
            copy.balanceChannelEnabled = defaults.balanceChannelEnabled
            copy.quotaDisplayMode = .used
        }
        return copy
    }
}
