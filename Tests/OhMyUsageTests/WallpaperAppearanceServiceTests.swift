import AppKit
import XCTest
@testable import OhMyUsage

final class WallpaperAppearanceServiceTests: XCTestCase {
    func testFollowWallpaperUsesFallbackStyleWhenProbeCannotResolveLuminance() {
        let service = WallpaperAppearanceService(
            imageLoader: { _ in nil },
            luminanceResolver: { _, _ in nil }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "main",
            wallpaperURL: URL(fileURLWithPath: "/tmp/missing.png"),
            horizontalCenterRatio: 0.5
        )

        let style = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: .dark
        )

        XCTAssertEqual(style, .dark)
    }

    func testDefaultResolverPrioritizesImmediateTopStripForMenuBarArea() {
        let service = WallpaperAppearanceService(
            imageLoader: { _ in
                Self.verticalStripImage(
                    width: 100,
                    height: 100,
                    topStripRows: 4,
                    topStripValue: 255,
                    remainderValue: 0
                )
            }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "main",
            wallpaperURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
            horizontalCenterRatio: 0.5
        )

        let style = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: .dark
        )

        XCTAssertEqual(style, .dark)
    }

    func testFollowWallpaperKeepsLightForegroundWhenStatusItemAppearanceReportsDarkMenuBar() {
        let service = WallpaperAppearanceService(
            imageLoader: { _ in NSImage(size: NSSize(width: 1, height: 1)) },
            luminanceResolver: { _, _ in 0.9 }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "fullscreen",
            wallpaperURL: URL(fileURLWithPath: "/tmp/bright-wallpaper.png"),
            horizontalCenterRatio: 0.5
        )

        let style = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: .light
        )

        XCTAssertEqual(style, .light)
    }

    func testManualModeDoesNotLoadWallpaperProbe() {
        var loadCount = 0
        let service = WallpaperAppearanceService(
            imageLoader: { _ in
                loadCount += 1
                return NSImage(size: NSSize(width: 1, height: 1))
            },
            luminanceResolver: { _, _ in 0.9 }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "main",
            wallpaperURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
            horizontalCenterRatio: 0.5
        )

        let style = service.resolvedForegroundStyle(
            mode: .dark,
            probe: probe,
            fallbackStyle: .light
        )

        XCTAssertEqual(style, .light)
        XCTAssertEqual(loadCount, 0)
    }

    func testCacheAvoidsReloadingSameWallpaperProbe() {
        var loadCount = 0
        let service = WallpaperAppearanceService(
            imageLoader: { _ in
                loadCount += 1
                return NSImage(size: NSSize(width: 1, height: 1))
            },
            luminanceResolver: { _, _ in 0.85 }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "screen-1",
            wallpaperURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
            horizontalCenterRatio: 0.42
        )

        let first = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: nil
        )
        let second = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: nil
        )

        XCTAssertEqual(first, .dark)
        XCTAssertEqual(second, .dark)
        XCTAssertEqual(loadCount, 1)
    }

    func testClearCacheForcesWallpaperProbeReload() {
        var loadCount = 0
        let service = WallpaperAppearanceService(
            imageLoader: { _ in
                loadCount += 1
                return NSImage(size: NSSize(width: 1, height: 1))
            },
            luminanceResolver: { _, _ in 0.2 }
        )
        let probe = WallpaperAppearanceProbe(
            screenID: "screen-1",
            wallpaperURL: URL(fileURLWithPath: "/tmp/wallpaper.png"),
            horizontalCenterRatio: 0.42
        )

        _ = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: nil
        )
        service.clearCache()
        _ = service.resolvedForegroundStyle(
            mode: .followWallpaper,
            probe: probe,
            fallbackStyle: nil
        )

        XCTAssertEqual(loadCount, 2)
    }

    private static func verticalStripImage(
        width: Int,
        height: Int,
        topStripRows: Int,
        topStripValue: UInt8,
        remainderValue: UInt8
    ) -> NSImage {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let data = rep.bitmapData
        else {
            XCTFail("Expected bitmap image representation")
            return NSImage(size: NSSize(width: width, height: height))
        }

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rep.bytesPerRow + x * rep.samplesPerPixel
                let value = y < topStripRows ? topStripValue : remainderValue
                data[offset] = value
                data[offset + 1] = value
                data[offset + 2] = value
                data[offset + 3] = 255
            }
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
}
