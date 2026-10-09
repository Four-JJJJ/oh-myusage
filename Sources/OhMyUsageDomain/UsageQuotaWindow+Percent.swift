import Foundation

extension UsageQuotaWindow {
    public static func percent(
        id: String,
        title: String,
        usedPercent: Double,
        resetAt: Date? = nil,
        kind: UsageQuotaKind,
        resetSource: UsageQuotaResetSource = .unknown,
        observedAt: Date? = nil,
        serverClockSkew: TimeInterval? = nil,
        confidence: UsageQuotaResetConfidence = .unknown,
        windowIdentity: String? = nil
    ) -> UsageQuotaWindow {
        let used = min(100, max(0, usedPercent))
        return UsageQuotaWindow(
            id: id, title: title, remainingPercent: max(0, 100 - used), usedPercent: used,
            resetAt: resetAt, kind: kind, resetSource: resetSource, observedAt: observedAt,
            serverClockSkew: serverClockSkew, confidence: confidence, windowIdentity: windowIdentity
        )
    }
}
