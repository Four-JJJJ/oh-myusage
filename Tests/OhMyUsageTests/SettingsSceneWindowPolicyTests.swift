import AppKit
import XCTest
@testable import OhMyUsage

final class SettingsSceneWindowPolicyTests: XCTestCase {
    func testKeepsManagedSettingsWindow() {
        let shouldDismiss = SettingsSceneWindowPolicy.shouldDismiss(
            title: "oh-myusage Settings",
            titleVisibility: .hidden,
            isKeptWindow: true
        )
        XCTAssertFalse(shouldDismiss)
    }

    func testDismissesVisibleTitledSwiftUISettingsScene() {
        let shouldDismiss = SettingsSceneWindowPolicy.shouldDismiss(
            title: "oh-myusage Settings",
            titleVisibility: .visible,
            isKeptWindow: false
        )
        XCTAssertTrue(shouldDismiss)
    }

    func testIgnoresOtherVisibleWindows() {
        let shouldDismiss = SettingsSceneWindowPolicy.shouldDismiss(
            title: "What's New in 1.2.3",
            titleVisibility: .visible,
            isKeptWindow: false
        )
        XCTAssertFalse(shouldDismiss)
    }

    func testIgnoresHiddenTitleCustomWindowsThatAreNotKept() {
        // Our real settings window hides the title; never treat it as phantom.
        let shouldDismiss = SettingsSceneWindowPolicy.shouldDismiss(
            title: "oh-myusage Settings",
            titleVisibility: .hidden,
            isKeptWindow: false
        )
        XCTAssertFalse(shouldDismiss)
    }
}
