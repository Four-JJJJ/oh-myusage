import Foundation

package enum BackoffPolicy {
    /// Delay in seconds before the next refresh attempt.
    ///
    /// - Ordinary failures back off to 120s after the first failure and 300s
    ///   after subsequent ones (existing behavior).
    /// - Rate-limited (429) responses use twice those magnitudes (plan §9.6),
    ///   and twice the base interval when no failure has been counted yet
    ///   (the cached-snapshot path does not increment the failure counter).
    package static func delaySeconds(
        baseInterval: Int,
        consecutiveFailures: Int,
        isRateLimited: Bool = false
    ) -> Int {
        if isRateLimited {
            if consecutiveFailures <= 0 {
                return max(1, baseInterval * 2)
            }
            if consecutiveFailures == 1 {
                return 240
            }
            return 600
        }
        if consecutiveFailures <= 0 {
            return baseInterval
        }
        if consecutiveFailures == 1 {
            return 120
        }
        return 300
    }
}
