import XCTest
import OhMyUsageApplication
@testable import OhMyUsage

final class BackoffPolicyTests: XCTestCase {
    func testBackoffUsesBaseIntervalOnSuccess() {
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 60, consecutiveFailures: 0), 60)
    }

    func testBackoffUses120OnFirstFailure() {
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 60, consecutiveFailures: 1), 120)
    }

    func testBackoffUses300OnRepeatedFailures() {
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 60, consecutiveFailures: 2), 300)
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 60, consecutiveFailures: 9), 300)
    }

    func testRateLimitedBackoffIsLongerThanOrdinaryFailureBackoff() {
        // Doc §9.6: a 429 backs off with twice the ordinary magnitudes.
        XCTAssertEqual(
            BackoffPolicy.delaySeconds(baseInterval: 180, consecutiveFailures: 0, isRateLimited: true),
            360
        )
        XCTAssertEqual(
            BackoffPolicy.delaySeconds(baseInterval: 180, consecutiveFailures: 1, isRateLimited: true),
            240
        )
        XCTAssertEqual(
            BackoffPolicy.delaySeconds(baseInterval: 180, consecutiveFailures: 2, isRateLimited: true),
            600
        )

        for failures in 0...3 {
            let ordinary = BackoffPolicy.delaySeconds(baseInterval: 60, consecutiveFailures: failures)
            let rateLimited = BackoffPolicy.delaySeconds(
                baseInterval: 60,
                consecutiveFailures: failures,
                isRateLimited: true
            )
            XCTAssertGreaterThan(
                rateLimited,
                ordinary,
                "429 backoff must exceed the ordinary failure backoff at \(failures) failures"
            )
        }
    }
}
