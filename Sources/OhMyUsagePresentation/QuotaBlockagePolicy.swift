import Foundation
import OhMyUsageDomain

public enum QuotaBlockagePolicy {
    public static func isBlockedByDepletedWeeklyQuota(
        currentKind: UsageQuotaKind?,
        currentRemainingPercent: Double?,
        currentIsAvailable: Bool = true,
        candidateWindows: [(kind: UsageQuotaKind?, remainingPercent: Double?, isAvailable: Bool)]
    ) -> Bool {
        guard currentIsAvailable,
              currentKind == .session,
              (currentRemainingPercent ?? 0) > 0 else {
            return false
        }

        return candidateWindows.contains { candidate in
            candidate.isAvailable
                && candidate.kind == .weekly
                && (candidate.remainingPercent ?? 100) <= 0
        }
    }
}
