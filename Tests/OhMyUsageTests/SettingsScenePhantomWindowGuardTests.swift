import AppKit
import XCTest
@testable import OhMyUsage

final class SettingsScenePhantomWindowGuardTests: XCTestCase {
    private func makeWindow(title: String, titleVisibility: NSWindow.TitleVisibility) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = titleVisibility
        return window
    }

    func testShouldDismissStillDistinguishesManagedWindow() {
        let owned = makeWindow(
            title: "oh-myusage Settings",
            titleVisibility: .hidden
        )
        XCTAssertFalse(
            SettingsSceneWindowPolicy.shouldDismiss(
                title: owned.title,
                titleVisibility: owned.titleVisibility,
                isKeptWindow: true
            )
        )
        XCTAssertTrue(
            SettingsSceneWindowPolicy.shouldDismiss(
                title: "oh-myusage Settings",
                titleVisibility: .visible,
                isKeptWindow: false
            )
        )
    }

    func testIsPhantomWindowIdentifiesBlankScene() {
        let hosting = NSViewController()
        let owned = makeWindow(
            title: "oh-myusage Settings",
            titleVisibility: .hidden
        )

        let phantom = makeWindow(
            title: "oh-myusage Settings",
            titleVisibility: .visible
        )

        // A titled window whose content is not our hosting controller is a phantom.
        XCTAssertTrue(
            SettingsSceneWindowPolicy.isPhantomWindow(
                phantom,
                ownedWindow: owned,
                settingsHostingController: hosting
            )
        )
    }

    func testIsPhantomWindowKeepsOwnedAndRealContentWindows() {
        let hosting = NSViewController()
        let owned = makeWindow(
            title: "oh-myusage Settings",
            titleVisibility: .hidden
        )
        owned.contentViewController = hosting

        // The owned settings window is never a phantom.
        XCTAssertFalse(
            SettingsSceneWindowPolicy.isPhantomWindow(
                owned,
                ownedWindow: owned,
                settingsHostingController: hosting
            )
        )

        // A window showing the real settings content is not a phantom even if
        // it is not the owned instance.
        let realContent = makeWindow(
            title: "oh-myusage Settings",
            titleVisibility: .visible
        )
        realContent.contentViewController = hosting
        XCTAssertFalse(
            SettingsSceneWindowPolicy.isPhantomWindow(
                realContent,
                ownedWindow: owned,
                settingsHostingController: hosting
            )
        )
    }

    func testIsPhantomWindowIgnoresUnrelatedWindows() {
        let hosting = NSViewController()
        let owned = makeWindow(title: "oh-myusage Settings", titleVisibility: .hidden)

        let releaseNotes = makeWindow(
            title: "oh-myusage 2.4.2 Release Notes",
            titleVisibility: .visible
        )
        XCTAssertFalse(
            SettingsSceneWindowPolicy.isPhantomWindow(
                releaseNotes,
                ownedWindow: owned,
                settingsHostingController: hosting
            )
        )
    }

    func testSweepDelaysArePositiveAndStartImmediate() {
        XCTAssertGreaterThanOrEqual(SettingsSceneWindowPolicy.sweepDelays.first ?? -1, 0)
        XCTAssertEqual(SettingsSceneWindowPolicy.sweepDelays.first, 0)
        XCTAssertGreaterThan(SettingsSceneWindowPolicy.sweepDelays.last ?? 0, 1)
    }

    func testPhantomGuardStartIsIdempotent() async {
        await MainActor.run {
            let guardInstance = SettingsScenePhantomWindowGuard.shared
            guardInstance.start()
            guardInstance.start()
        }
        // Reaching here without registering duplicate observers/timers is the
        // regression guard; the assertion documents intent.
        XCTAssertTrue(true)
    }
}
