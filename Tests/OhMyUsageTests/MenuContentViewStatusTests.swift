import XCTest
@testable import OhMyUsage

final class MenuContentViewStatusTests: XCTestCase {
    func testCachedAuthExpiredStatusTextNamesAuthFailure() {
        XCTAssertEqual(
            MenuContentView.cachedFetchHealthStatusText(.authExpired, language: .zhHans),
            "认证失败"
        )
        XCTAssertNotEqual(
            MenuContentView.cachedFetchHealthStatusText(.authExpired, language: .zhHans),
            "失联"
        )
    }

    func testCachedAuthExpiredStatusTextUsesEnglishAuthFailureLabel() {
        XCTAssertEqual(
            MenuContentView.cachedFetchHealthStatusText(.authExpired, language: .en),
            "Auth failed"
        )
    }

    func testHealthyCachedFallbackStatusTextUsesLocalCacheLabel() {
        XCTAssertEqual(
            MenuContentView.cachedFetchHealthStatusText(.ok, language: .zhHans),
            "本地缓存"
        )
        XCTAssertEqual(
            MenuContentView.cachedFetchHealthStatusText(.ok, language: .en),
            "Cached"
        )
    }
}
