import AppKit

enum ProcessIcon {
    static let menuSize = NSSize(width: 16, height: 16)

    static func image(for entry: PortEntry, domain: String? = nil, usesHTTPS: Bool = false) -> NSImage {
        if let favicon = FaviconStore.shared.cachedImage(for: entry, domain: domain, usesHTTPS: usesHTTPS) {
            return scaled(favicon)
        }

        FaviconStore.shared.prefetch(for: entry, domain: domain, usesHTTPS: usesHTTPS)

        if let icon = appIcon(for: entry) {
            return scaled(icon)
        }

        return scaled(terminalFallback)
    }

    static func placeholder() -> NSImage {
        NSImage(size: menuSize)
    }

    static func liveDot() -> NSImage {
        let image = NSImage(size: menuSize, flipped: false) { rect in
            NSColor.black.setFill()
            let dot = NSRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6)
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static let terminalFallback: NSImage = {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        let paths = [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app"
        ]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }

        return NSImage(size: menuSize)
    }()

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
