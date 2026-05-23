import AppKit
import XCTest
@testable import OhMyUsage

final class StatusBarAppearanceResolverTests: XCTestCase {
    func testFollowWallpaperUsesDarkForegroundForBrightWallpaper() {
        let style = StatusBarAppearanceResolver.resolvedForegroundStyle(
            mode: .followWallpaper,
            wallpaperLuminance: 0.80
        )
        XCTAssertEqual(style, .dark)
    }

    func testFollowWallpaperUsesLightForegroundForDarkWallpaper() {
        let style = StatusBarAppearanceResolver.resolvedForegroundStyle(
            mode: .followWallpaper,
            wallpaperLuminance: 0.20
        )
        XCTAssertEqual(style, .light)
    }

    func testFollowWallpaperThresholdBoundary() {
        XCTAssertEqual(
            StatusBarAppearanceResolver.resolvedForegroundStyle(mode: .followWallpaper, wallpaperLuminance: 0.58),
            .dark
        )
        XCTAssertEqual(
            StatusBarAppearanceResolver.resolvedForegroundStyle(mode: .followWallpaper, wallpaperLuminance: 0.5799),
            .light
        )
    }

    func testFollowWallpaperFallsBackToLightWhenLuminanceUnavailable() {
        let style = StatusBarAppearanceResolver.resolvedForegroundStyle(
            mode: .followWallpaper,
            wallpaperLuminance: nil
        )
        XCTAssertEqual(style, .light)
    }

    func testManualModeOverridesWallpaperLuminance() {
        XCTAssertEqual(
            StatusBarAppearanceResolver.resolvedForegroundStyle(mode: .dark, wallpaperLuminance: 0.01),
            .light
        )
        XCTAssertEqual(
            StatusBarAppearanceResolver.resolvedForegroundStyle(mode: .light, wallpaperLuminance: 0.99),
            .dark
        )
    }

    func testWallpaperTopStripLuminanceSamplesTopRows() {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 64,
                pixelsHigh: 64,
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
            return
        }

        for y in 0..<64 {
            for x in 0..<64 {
                let offset = y * rep.bytesPerRow + x * rep.samplesPerPixel
                data[offset] = 255
                data[offset + 1] = 255
                data[offset + 2] = 255
                data[offset + 3] = 255
            }
        }

        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.addRepresentation(rep)

        let luminance = StatusBarAppearanceResolver.wallpaperTopStripLuminance(
            from: image,
            sampleWidth: 64,
            sampleHeight: 16,
            topStripRows: 4
        )
        XCTAssertNotNil(luminance)
        XCTAssertGreaterThan(luminance ?? 0, 0.90)
    }

    func testWallpaperTopStripLuminancePrioritizesImmediateTopStripForBrightMenuBarArea() {
        let image = verticalStripImage(
            width: 100,
            height: 100,
            topStripRows: 4,
            topStripValue: 255,
            remainderValue: 0
        )

        let luminance = StatusBarAppearanceResolver.wallpaperTopStripLuminance(
            from: image,
            sampleHeight: 256
        )

        XCTAssertNotNil(luminance)
        XCTAssertGreaterThan(luminance ?? 0, 0.90)
        XCTAssertEqual(
            StatusBarAppearanceResolver.resolvedForegroundStyle(
                mode: .followWallpaper,
                wallpaperLuminance: luminance
            ),
            .dark
        )
    }

    func testWallpaperTopStripLuminancePrioritizesImmediateTopStripForDarkMenuBarArea() {
        let image = verticalStripImage(
            width: 100,
            height: 100,
            topStripRows: 4,
            topStripValue: 0,
            remainderValue: 255
        )

        let luminance = StatusBarAppearanceResolver.wallpaperTopStripLuminance(
            from: image,
            sampleHeight: 256
        )

        XCTAssertNotNil(luminance)
        XCTAssertLessThan(luminance ?? 1, 0.10)
        XCTAssertEqual(
            StatusBarAppearanceResolver.resolvedForegroundStyle(
                mode: .followWallpaper,
                wallpaperLuminance: luminance
            ),
            .light
        )
    }

    func testWallpaperTopStripLuminanceReturnsNilForZeroSizedImage() {
        let empty = NSImage(size: .zero)
        let luminance = StatusBarAppearanceResolver.wallpaperTopStripLuminance(from: empty)
        XCTAssertNil(luminance)
    }

    func testWallpaperTopStripLuminanceSamplesAroundProvidedHorizontalCenter() {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 100,
                pixelsHigh: 40,
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
            return
        }

        for y in 0..<40 {
            for x in 0..<100 {
                let offset = y * rep.bytesPerRow + x * rep.samplesPerPixel
                let value: UInt8 = x >= 50 ? 255 : 0
                data[offset] = value
                data[offset + 1] = value
                data[offset + 2] = value
                data[offset + 3] = 255
            }
        }

        let image = NSImage(size: NSSize(width: 100, height: 40))
        image.addRepresentation(rep)

        let leftSample = StatusBarAppearanceResolver.wallpaperTopStripLuminance(
            from: image,
            horizontalCenterRatio: 0.10,
            sampleSpanRatio: 0.16
        )
        let rightSample = StatusBarAppearanceResolver.wallpaperTopStripLuminance(
            from: image,
            horizontalCenterRatio: 0.90,
            sampleSpanRatio: 0.16
        )

        XCTAssertNotNil(leftSample)
        XCTAssertNotNil(rightSample)
        XCTAssertLessThan(leftSample ?? 1, 0.20)
        XCTAssertGreaterThan(rightSample ?? 0, 0.80)
    }

    private func verticalStripImage(
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
