#!/usr/bin/env swift

import AppKit
import Foundation

private let fileManager = FileManager.default
private let scriptURL = URL(fileURLWithPath: #filePath)
private let projectRoot = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let assetDirectory = projectRoot
    .appendingPathComponent("Tokiburn/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
private let brandAssetDirectory = projectRoot
    .appendingPathComponent("Tokiburn/Assets.xcassets/BrandIcon.imageset", isDirectory: true)
private let brandMaster = projectRoot
    .appendingPathComponent("brand/Tokiburn-AppIcon-Master.png")

private let graphite = NSColor(calibratedRed: 23 / 255, green: 24 / 255, blue: 27 / 255, alpha: 1)
private let paper = NSColor(calibratedRed: 244 / 255, green: 241 / 255, blue: 236 / 255, alpha: 1)
private let coral = NSColor(calibratedRed: 255 / 255, green: 98 / 255, blue: 72 / 255, alpha: 1)

private struct GridCell {
    enum Shape {
        case square
        case lowerLeftTriangle
    }

    let column: Int
    let row: Int
    let shape: Shape
    let color: NSColor
}

private let cells: [GridCell] = [
    .init(column: 0, row: 0, shape: .lowerLeftTriangle, color: graphite),
    .init(column: 1, row: 0, shape: .square, color: graphite),
    .init(column: 2, row: 0, shape: .square, color: graphite),
    .init(column: 3, row: 0, shape: .square, color: graphite),
    .init(column: 0, row: 1, shape: .square, color: graphite),
    .init(column: 1, row: 1, shape: .lowerLeftTriangle, color: graphite),
    .init(column: 3, row: 1, shape: .square, color: graphite),
    .init(column: 0, row: 2, shape: .square, color: graphite),
    .init(column: 1, row: 2, shape: .square, color: coral),
    .init(column: 2, row: 2, shape: .lowerLeftTriangle, color: graphite),
    .init(column: 3, row: 2, shape: .square, color: graphite),
    .init(column: 0, row: 3, shape: .square, color: graphite),
    .init(column: 1, row: 3, shape: .square, color: graphite),
    .init(column: 2, row: 3, shape: .square, color: graphite),
    .init(column: 3, row: 3, shape: .lowerLeftTriangle, color: graphite),
]

private func renderIcon(pixels: Int, to outputURL: URL) throws {
    guard let bitmap = NSBitmapImageRep(
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
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    let context = graphicsContext.cgContext
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let tileRect = NSRect(x: 48, y: 48, width: 928, height: 928)
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    paper.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor.black.withAlphaComponent(0.10).setStroke()
    tilePath.lineWidth = 2
    tilePath.stroke()

    let origin: CGFloat = 244
    let cellSize: CGFloat = 110
    let gap: CGFloat = 24

    for cell in cells {
        let x = origin + CGFloat(cell.column) * (cellSize + gap)
        let top = 1024 - origin - CGFloat(cell.row) * (cellSize + gap)
        let y = top - cellSize
        cell.color.setFill()

        switch cell.shape {
        case .square:
            NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: cellSize, height: cellSize),
                xRadius: 8,
                yRadius: 8
            ).fill()
        case .lowerLeftTriangle:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x, y: y + cellSize))
            path.line(to: NSPoint(x: x + cellSize, y: y))
            path.close()
            path.fill()
        }
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try pngData.write(to: outputURL, options: .atomic)
}

try fileManager.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
try fileManager.createDirectory(at: brandAssetDirectory, withIntermediateDirectories: true)
try renderIcon(pixels: 2048, to: brandMaster)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try renderIcon(
        pixels: size,
        to: assetDirectory.appendingPathComponent("AppIcon-\(size).png")
    )
}

try renderIcon(
    pixels: 512,
    to: brandAssetDirectory.appendingPathComponent("BrandIcon-512.png")
)
try renderIcon(
    pixels: 1024,
    to: brandAssetDirectory.appendingPathComponent("BrandIcon-1024.png")
)

print("Generated Tokiburn app icon master and asset catalog PNGs.")
