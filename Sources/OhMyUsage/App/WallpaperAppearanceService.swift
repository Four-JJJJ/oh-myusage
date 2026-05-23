import AppKit

struct WallpaperAppearanceProbe: Equatable {
    var screenID: String
    var wallpaperURL: URL
    var horizontalCenterRatio: Double
}

final class WallpaperAppearanceService {
    private let cacheLimit: Int
    private let imageLoader: (URL) -> NSImage?
    private let luminanceResolver: (NSImage, Double) -> Double?
    private var luminanceCache: [String: Double] = [:]
    private var cacheOrder: [String] = []

    init(
        cacheLimit: Int = 12,
        imageLoader: @escaping (URL) -> NSImage? = { NSImage(contentsOf: $0) },
        luminanceResolver: @escaping (NSImage, Double) -> Double? = { image, horizontalCenterRatio in
            StatusBarAppearanceResolver.wallpaperTopStripLuminance(
                from: image,
                sampleHeight: 256,
                horizontalCenterRatio: horizontalCenterRatio
            )
        }
    ) {
        self.cacheLimit = cacheLimit
        self.imageLoader = imageLoader
        self.luminanceResolver = luminanceResolver
    }

    func resolvedForegroundStyle(
        mode: StatusBarAppearanceMode,
        probe: WallpaperAppearanceProbe?,
        fallbackStyle: StatusBarForegroundStyle?
    ) -> StatusBarForegroundStyle {
        guard mode == .followWallpaper else {
            return StatusBarAppearanceResolver.resolvedForegroundStyle(
                mode: mode,
                wallpaperLuminance: nil
            )
        }

        let luminance = wallpaperLuminance(for: probe)
        if luminance != nil {
            let wallpaperStyle = StatusBarAppearanceResolver.resolvedForegroundStyle(
                mode: .followWallpaper,
                wallpaperLuminance: luminance
            )
            return reconciledForegroundStyle(
                wallpaperStyle: wallpaperStyle,
                fallbackStyle: fallbackStyle
            )
        }
        if let fallbackStyle {
            return fallbackStyle
        }
        return StatusBarAppearanceResolver.resolvedForegroundStyle(
            mode: .followWallpaper,
            wallpaperLuminance: nil
        )
    }

    private func reconciledForegroundStyle(
        wallpaperStyle: StatusBarForegroundStyle,
        fallbackStyle: StatusBarForegroundStyle?
    ) -> StatusBarForegroundStyle {
        // Full-screen spaces can expose a dark menu bar over a bright desktop wallpaper.
        // When AppKit reports that dark bar, keep the light foreground for readability.
        if fallbackStyle == .light {
            return .light
        }
        return wallpaperStyle
    }

    func clearCache() {
        luminanceCache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
    }

    private func wallpaperLuminance(for probe: WallpaperAppearanceProbe?) -> Double? {
        guard let probe else { return nil }
        let cacheKey = "\(probe.screenID)|\(Int((probe.horizontalCenterRatio * 1000).rounded()))|\(probe.wallpaperURL.path)"
        if let cached = luminanceCache[cacheKey] {
            return cached
        }
        guard let image = imageLoader(probe.wallpaperURL) else {
            return nil
        }
        guard let luminance = luminanceResolver(image, probe.horizontalCenterRatio) else {
            return nil
        }
        cache(luminance, forKey: cacheKey)
        return luminance
    }

    private func cache(_ value: Double, forKey key: String) {
        if luminanceCache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheLimit {
                let evicted = cacheOrder.removeFirst()
                luminanceCache.removeValue(forKey: evicted)
            }
        }
        luminanceCache[key] = value
    }
}
