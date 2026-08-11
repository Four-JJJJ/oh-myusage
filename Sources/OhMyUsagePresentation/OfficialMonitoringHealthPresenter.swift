import Foundation
import OhMyUsageDomain

public enum OfficialMonitoringHealthStatus: Equatable, Sendable {
    case unknown
    case authError
    case configError
    case rateLimited
    case disconnected
    case sufficient
    case tight
    case exhausted
}

public enum OfficialMonitoringHealthPresenter {
    public static func quotaMetricPercents(
        for window: UsageQuotaWindow,
        displaysUsedQuota: Bool
    ) -> (displayPercent: Double, healthPercent: Double) {
        let healthPercent = max(0, min(100, window.remainingPercent))
        let displayPercent = displaysUsedQuota
            ? max(0, min(100, window.usedPercent))
            : healthPercent
        return (displayPercent, healthPercent)
    }

    public static func officialMonitoringHealthStatus(
        snapshot: UsageSnapshot?,
        healthPercents: [Double]
    ) -> OfficialMonitoringHealthStatus {
        guard let snapshot else {
            return .unknown
        }

        if snapshot.valueFreshness == .empty {
            switch snapshot.fetchHealth {
            case .authExpired:
                return .authError
            case .endpointMisconfigured:
                return .configError
            case .rateLimited:
                return .rateLimited
            case .unreachable:
                return .disconnected
            case .ok:
                return .tight
            }
        }

        guard let minimum = healthPercents.min() else {
            return .tight
        }
        if minimum > 30 {
            return .sufficient
        }
        if minimum > 10 {
            return .tight
        }
        return .exhausted
    }
}
