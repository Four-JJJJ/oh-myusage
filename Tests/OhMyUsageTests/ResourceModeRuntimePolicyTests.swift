import XCTest
@testable import OhMyUsage

final class ResourceModeRuntimePolicyTests: XCTestCase {
    func testThreeMinuteBackgroundRefreshUsesThreeMinuteFloor() {
        let config = ResourceMode.background3Minutes.refreshSchedulerConfig

        XCTAssertEqual(config.backgroundProviderPollIntervalSeconds, 180)
        XCTAssertEqual(config.activeProviderPollIntervalSeconds, 180)
        XCTAssertEqual(config.maxConcurrentRefreshes, 2)
        XCTAssertEqual(config.localSessionSignalActiveSleepSeconds, 10)
        XCTAssertEqual(config.localSessionSignalIdleSleepSeconds, 30)
        XCTAssertEqual(config.inFlightProviderSleepSeconds, 5)
    }

    func testFiveMinuteBackgroundRefreshUsesDefaultSignalIntervals() {
        let config = ResourceMode.background5Minutes.refreshSchedulerConfig

        XCTAssertEqual(config.backgroundProviderPollIntervalSeconds, 5 * 60)
        XCTAssertEqual(config.activeProviderPollIntervalSeconds, 180)
        XCTAssertEqual(config.maxConcurrentRefreshes, 2)
        XCTAssertEqual(config.localSessionSignalActiveSleepSeconds, 15)
        XCTAssertEqual(config.localSessionSignalIdleSleepSeconds, 60)
        XCTAssertEqual(config.inFlightProviderSleepSeconds, 5)
    }

    func testTenMinuteBackgroundRefreshUsesTenMinuteFloor() {
        let config = ResourceMode.background10Minutes.refreshSchedulerConfig

        XCTAssertEqual(config.backgroundProviderPollIntervalSeconds, 10 * 60)
        XCTAssertEqual(config.activeProviderPollIntervalSeconds, 180)
        XCTAssertEqual(config.maxConcurrentRefreshes, 2)
        XCTAssertEqual(config.localSessionSignalActiveSleepSeconds, 20)
        XCTAssertEqual(config.localSessionSignalIdleSleepSeconds, 90)
        XCTAssertEqual(config.inFlightProviderSleepSeconds, 10)
    }

    func testFifteenMinuteLowPowerModeUsesLongestIntervals() {
        // Doc §9.3 low-power mode: 300s active floor, 1800s background floor.
        let config = ResourceMode.background15Minutes.refreshSchedulerConfig

        XCTAssertEqual(config.backgroundProviderPollIntervalSeconds, 1_800)
        XCTAssertEqual(config.activeProviderPollIntervalSeconds, 300)
        XCTAssertEqual(config.maxConcurrentRefreshes, 2)
        XCTAssertEqual(config.localSessionSignalActiveSleepSeconds, 30)
        XCTAssertEqual(config.localSessionSignalIdleSleepSeconds, 120)
        XCTAssertEqual(config.inFlightProviderSleepSeconds, 15)
    }
}
