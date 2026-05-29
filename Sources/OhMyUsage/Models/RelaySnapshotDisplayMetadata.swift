import OhMyUsageDomain
import Foundation

struct RelayRecoveryDisplayMetadata: Equatable {
    var source: String
    var recoveredAt: Date?
}

struct RelaySnapshotDisplayMetadata: Equatable {
    var resolvedAdapterID: String
    var requestCount: Int?
    var tokenPlanCurrentPeriodEnd: String?
    var tokenPlanRemainingTokens: Double?
    var tokenPlanUsedTokens: Double?
    var tokenPlanLimitTokens: Double?
    var authSource: String?
    var recovery: RelayRecoveryDisplayMetadata?

    private var quotaValueTextByWindowID: [String: String]

    init(snapshot: UsageSnapshot?, fallbackAdapterID: String? = nil) {
        let rawMeta = snapshot?.rawMeta ?? [:]
        let resolvedFallbackAdapterID = fallbackAdapterID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let adapterID = OfficialValueParser.nonPlaceholderString(rawMeta["relay.adapterID"])
            ?? OfficialValueParser.nonPlaceholderString(resolvedFallbackAdapterID)
            ?? "generic-newapi"
        resolvedAdapterID = adapterID

        if let rawRequestCount = OfficialValueParser.nonPlaceholderString(rawMeta["account.requestCount"]),
           let requestCount = Int(rawRequestCount) {
            self.requestCount = requestCount
        } else {
            requestCount = nil
        }

        tokenPlanCurrentPeriodEnd = OfficialValueParser.nonPlaceholderString(
            rawMeta["account.tokenPlanCurrentPeriodEnd"] ?? rawMeta["tokenPlanCurrentPeriodEnd"]
        )
        tokenPlanRemainingTokens = Self.doubleValue(
            rawMeta["account.tokenPlanRemaining"] ?? rawMeta["tokenPlanRemaining"]
        )
        tokenPlanUsedTokens = Self.doubleValue(
            rawMeta["account.tokenPlanUsed"] ?? rawMeta["tokenPlanUsed"]
        )
        tokenPlanLimitTokens = Self.doubleValue(
            rawMeta["account.tokenPlanLimit"] ?? rawMeta["tokenPlanLimit"]
        )
        authSource = snapshot?.authSourceLabel
            ?? OfficialValueParser.nonPlaceholderString(rawMeta["account.authSource"])
            ?? OfficialValueParser.nonPlaceholderString(rawMeta["token.authSource"])

        if rawMeta["relay.recovery.succeeded"] == "true",
           let source = OfficialValueParser.nonPlaceholderString(rawMeta["relay.recovery.source"]) {
            recovery = RelayRecoveryDisplayMetadata(
                source: source,
                recoveredAt: OfficialValueParser.nonPlaceholderString(rawMeta["relay.recovery.at"])
                    .flatMap(OfficialValueParser.isoDate(_:))
            )
        } else {
            recovery = nil
        }

        var quotaValueTextByWindowID: [String: String] = [:]
        for (key, value) in rawMeta {
            guard let resolvedValue = OfficialValueParser.nonPlaceholderString(value) else { continue }
            if key.hasPrefix("account.quotaValueText.") {
                quotaValueTextByWindowID[String(key.dropFirst("account.quotaValueText.".count))] = resolvedValue
            } else if key.hasPrefix("quotaValueText.") {
                let windowID = String(key.dropFirst("quotaValueText.".count))
                quotaValueTextByWindowID[windowID] = quotaValueTextByWindowID[windowID] ?? resolvedValue
            }
        }
        self.quotaValueTextByWindowID = quotaValueTextByWindowID
    }

    func quotaValueText(for windowID: String) -> String? {
        quotaValueTextByWindowID[windowID]
    }

    private static func doubleValue(_ raw: String?) -> Double? {
        guard let resolved = OfficialValueParser.nonPlaceholderString(raw) else { return nil }
        return Double(resolved)
    }
}
