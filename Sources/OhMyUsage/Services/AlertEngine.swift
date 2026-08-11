import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

struct AlertEngine {
    static func shouldAlertLowRemaining(
        snapshot: UsageSnapshot,
        rule: AlertRule,
        displaysUsedQuota: Bool = false
    ) -> Bool {
        if displaysUsedQuota {
            guard let used = snapshot.used else {
                return false
            }
            return used >= (100 - rule.lowRemaining)
        }

        guard let remaining = snapshot.remaining else {
            return false
        }
        return remaining <= rule.lowRemaining
    }

    static func lowQuotaWindows(
        snapshot: UsageSnapshot,
        rule: AlertRule,
        displaysUsedQuota: Bool = false
    ) -> [UsageQuotaWindow] {
        snapshot.quotaWindows.filter { window in
            if displaysUsedQuota {
                return window.usedPercent >= (100 - rule.lowRemaining)
            }
            return window.remainingPercent <= rule.lowRemaining
        }
    }

    static func shouldAlertFailures(consecutiveFailures: Int, rule: AlertRule) -> Bool {
        consecutiveFailures >= rule.maxConsecutiveFailures
    }

    static func isAuthError(_ error: Error) -> Bool {
        if case ProviderError.unauthorized = error {
            return true
        }
        if case ProviderError.unauthorizedDetail = error {
            return true
        }
        return false
    }
}
