import AppKit

@MainActor
enum AppIconImageProvider {
    static func image(size: CGFloat? = nil) -> NSImage? {
        guard let image = bundledImage() ?? applicationIconImage() else {
            return nil
        }
        if let size {
            image.size = NSSize(width: size, height: size)
        }
        image.isTemplate = false
        return image
    }

    static func applyApplicationIcon(size: CGFloat = 256) {
        guard let image = image(size: size) else { return }
        NSApp.applicationIconImage = image
    }

    private static func bundledImage() -> NSImage? {
        let candidates: [(Bundle, String, String)] = [
            (.main, "AppIcon", "icns"),
            (.module, "AppIcon", "icns")
        ]

        for (bundle, name, ext) in candidates {
            guard let url = bundle.url(forResource: name, withExtension: ext),
                  let image = NSImage(contentsOf: url),
                  image.isValid else {
                continue
            }
            return image
        }

        return nil
    }

    private static func applicationIconImage() -> NSImage? {
        guard let image = NSApp.applicationIconImage?.copy() as? NSImage,
              image.isValid else {
            return nil
        }
        return image
    }
}
