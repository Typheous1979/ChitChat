#!/usr/bin/env swift
// Generates ChitChat app icons at all required macOS sizes.
// Usage: swift scripts/generate-icons.swift

import AppKit
import CoreGraphics

func generateIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    // Background: rounded rectangle with gradient
    let cornerRadius = s * 0.22
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient: deep indigo to vibrant blue
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.15, green: 0.12, blue: 0.45, alpha: 1.0),
        CGColor(red: 0.25, green: 0.35, blue: 0.85, alpha: 1.0),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])
    }

    // Waveform bars (centered, white)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    let barCount = 7
    let barWidth = s * 0.06
    let barGap = s * 0.04
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
    let startX = (s - totalWidth) / 2
    let centerY = s / 2

    // Symmetric waveform heights (as fraction of icon size)
    let heights: [CGFloat] = [0.15, 0.28, 0.42, 0.55, 0.42, 0.28, 0.15]

    for i in 0..<barCount {
        let h = heights[i] * s
        let x = startX + CGFloat(i) * (barWidth + barGap)
        let y = centerY - h / 2
        let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        ctx.addPath(barPath)
        ctx.fillPath()
    }

    // Small speech bubble dot in bottom-right
    let dotSize = s * 0.12
    let dotX = s * 0.72
    let dotY = s * 0.18
    ctx.setFillColor(CGColor(red: 0.3, green: 0.85, blue: 0.5, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize))

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, pixels: Int, path: String) {
    // Create a bitmap at exact pixel dimensions (1x scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate PNG for \(pixels)px")
        return
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Generated: \(path) (\(pixels)x\(pixels)px)")
    } catch {
        print("Failed to write \(path): \(error)")
    }
}

// Required macOS icon sizes (pixel dimensions)
let sizes: [(pixels: Int, suffix: String)] = [
    (16, "16"),
    (32, "16@2x"),
    (32, "32"),
    (64, "32@2x"),
    (128, "128"),
    (256, "128@2x"),
    (256, "256"),
    (512, "256@2x"),
    (512, "512"),
    (1024, "512@2x"),
]

let outputDir = "ChitChat/Resources/Assets.xcassets/AppIcon.appiconset"

for entry in sizes {
    let image = generateIcon(size: entry.pixels)
    let filename = "icon_\(entry.suffix).png"
    savePNG(image, pixels: entry.pixels, path: "\(outputDir)/\(filename)")
}

print("\nDone! Update Contents.json with the generated filenames.")
