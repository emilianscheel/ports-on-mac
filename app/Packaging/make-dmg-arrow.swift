#!/usr/bin/env swift

import AppKit
import Foundation

private let logicalSize = NSSize(width: 112, height: 112)
private let arrowPointSize: CGFloat = 42
private let arrowColor = NSColor(calibratedWhite: 0.62, alpha: 1)

private func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

private func applyFinderIcon(to tiffURL: URL) {
    guard let image = NSImage(contentsOf: tiffURL) else {
        die("Could not read the DMG arrow TIFF.")
    }
    guard NSWorkspace.shared.setIcon(image, forFile: tiffURL.path, options: []) else {
        die("Could not apply the DMG arrow as a Finder icon.")
    }
}

private func render(scale: Int, to outputURL: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(logicalSize.width) * scale,
        pixelsHigh: Int(logicalSize.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        die("Could not allocate the DMG arrow bitmap.")
    }

    bitmap.size = logicalSize
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        die("Could not create the DMG arrow drawing context.")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: logicalSize)).fill()

    let sizeConfiguration = NSImage.SymbolConfiguration(
        pointSize: arrowPointSize,
        weight: .regular
    )
    let colorConfiguration = NSImage.SymbolConfiguration(
        paletteColors: [arrowColor]
    )
    guard let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(sizeConfiguration.applying(colorConfiguration)) else {
        die("The arrow.right SF Symbol is unavailable.")
    }

    let arrowRect = NSRect(
        x: (logicalSize.width - arrow.size.width) / 2,
        y: (logicalSize.height - arrow.size.height) / 2,
        width: arrow.size.width,
        height: arrow.size.height
    )
    arrow.draw(in: arrowRect)

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        die("Could not encode the DMG arrow PNG.")
    }
    try png.write(to: outputURL, options: .atomic)
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--set-icon" {
    applyFinderIcon(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

guard CommandLine.arguments.count == 3 else {
    die("Usage: make-dmg-arrow.swift <1x-output.png> <2x-output.png>\n       make-dmg-arrow.swift --set-icon <arrow.tiff>")
}

do {
    try render(scale: 1, to: URL(fileURLWithPath: CommandLine.arguments[1]))
    try render(scale: 2, to: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    die("Could not write the DMG arrow: \(error.localizedDescription)")
}
