import AppKit

enum ProcessIcon {
    static let menuSize = NSSize(width: 16, height: 16)

    static func image(for entry: PortEntry, domain: String? = nil) -> NSImage {
        if let icon = appIcon(for: entry) {
            return scaled(icon)
        }

        if let favicon = FaviconStore.shared.cachedImage(for: entry, domain: domain) {
            return scaled(favicon)
        }

        FaviconStore.shared.prefetch(for: entry, domain: domain)
        return placeholder()
    }

    static func placeholder() -> NSImage {
        NSImage(size: menuSize)
    }

    static func liveDot() -> NSImage {
        let image = NSImage(size: menuSize, flipped: false) { rect in
            NSColor.secondaryLabelColor.setFill()
            let dot = NSRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6)
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func appIcon(for entry: PortEntry) -> NSImage? {
        if let running = NSRunningApplication(processIdentifier: entry.pid),
           let bundleURL = running.bundleURL,
           bundleURL.pathExtension == "app" {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        if let executablePath = entry.executablePath,
           let bundleURL = ProcessMetadata.bundleURL(containingExecutable: executablePath) {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return nil
    }

    static func scaled(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = menuSize
        copy.isTemplate = false
        return copy
    }
}
