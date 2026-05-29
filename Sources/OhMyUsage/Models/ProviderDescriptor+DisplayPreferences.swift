import Foundation
import OhMyUsageDomain

extension ProviderDescriptor {
    var usesXiaomimimoTokenPlanQuota: Bool {
        relayConfig?.adapterID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "xiaomimimo-token-plan"
    }

    var displaysUsedQuota: Bool {
        switch family {
        case .official:
            if isRelay {
                return (relayConfig?.quotaDisplayMode ?? .remaining) == .used
            }
            return (officialConfig?.quotaDisplayMode ?? ProviderDescriptor.defaultOfficialConfig(type: type).quotaDisplayMode) == .used
        case .thirdParty:
            return (relayConfig?.quotaDisplayMode ?? .remaining) == .used
        }
    }

    var showsExpirationTimeInMenuBar: Bool {
        if isRelay {
            return relayConfig?.showExpirationTimeInMenuBar ?? true
        }
        guard family == .official else {
            return true
        }
        return officialConfig?.showExpirationTimeInMenuBar
            ?? ProviderDescriptor.defaultOfficialConfig(type: type).showExpirationTimeInMenuBar
    }

    func supportsExpirationTimeDisplay(snapshot: UsageSnapshot?) -> Bool {
        guard isRelay else {
            return snapshot?.quotaWindows.contains { $0.resetAt != nil } ?? false
        }
        if usesXiaomimimoTokenPlanQuota {
            return true
        }
        let metadata = RelaySnapshotDisplayMetadata(
            snapshot: snapshot,
            fallbackAdapterID: relayConfig?.adapterID
        )
        if let end = metadata.tokenPlanCurrentPeriodEnd?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !end.isEmpty {
            return true
        }
        return snapshot?.quotaWindows.contains { $0.resetAt != nil } ?? false
    }

    var traeDisplaysAmount: Bool {
        family == .official
            && type == .trae
            && (officialConfig?.traeValueDisplayMode
                ?? ProviderDescriptor.defaultOfficialConfig(type: .trae).traeValueDisplayMode
                ?? .percent) == .amount
    }

    var supportedOfficialSourceModes: [OfficialSourceMode] {
        ProviderMetadataCatalog.supportedOfficialSourceModes(for: self)
    }

    var supportedOfficialWebModes: [OfficialWebMode] {
        ProviderMetadataCatalog.supportedOfficialWebModes(for: self)
    }

    var supportsOfficialManualCookieInput: Bool {
        family == .official
            && !(officialConfig?.manualCookieAccount?.isEmpty ?? true)
            && supportedOfficialWebModes.contains(.manual)
    }
}
