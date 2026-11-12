#!/usr/bin/env swift
// Renders the HyprSpace app icon: a dwindle tiling layout with one focused (bordered) window.
// Usage: swift script/generate-icon.swift <output.png> [size-in-pixels]
// The icon is checked in at resources/Assets.xcassets/AppIcon.appiconset/icon.png (512 pixels)

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("Usage: generate-icon.swift <output.png> [size-in-pixels]\n".data(using: .utf8)!)
    exit(2)
}
let outputPath = args[1]
let pixels = args.count >= 3 ? Int(args[2]) ?? 512 : 512

// Everything below is drawn on a 1024x1024 canvas with the origin in the top-left corner
let canvas: CGFloat = 1024
let context = CGContext(
    data: nil,
    width: pixels,
    height: pixels,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
)!
context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
context.translateBy(x: 0, y: canvas)
context.scaleBy(x: 1, y: -1)
context.setShouldAntialias(true)
context.interpolationQuality = .high

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha,
    )
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillGradient(_ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

// The standard macOS icon shape: an 824x824 rounded square in the middle of the 1024x1024 canvas
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = roundedRect(plate, 186)

// Soft shadow under the plate
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.35))
context.addPath(platePath)
context.setFillColor(color(0x10131f))
context.fillPath()
context.restoreGState()

// The desktop: a deep night-blue gradient
fillGradient(
    platePath,
    [color(0x1b2140), color(0x0d101c)],
    from: CGPoint(x: plate.minX, y: plate.minY),
    to: CGPoint(x: plate.maxX, y: plate.maxY),
)

// A thin highlight around the plate
context.addPath(roundedRect(plate.insetBy(dx: 3, dy: 3), 183))
context.setStrokeColor(color(0xffffff, 0.10))
context.setLineWidth(6)
context.strokePath()

// The windows. A dwindle layout: every new window splits the previous one in half
let padding: CGFloat = 118
let gap: CGFloat = 30
let area = plate.insetBy(dx: padding, dy: padding)
let halfWidth = (area.width - gap) / 2
let halfHeight = (area.height - gap) / 2
let quarterWidth = (halfWidth - gap) / 2

let master = CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
let focused = CGRect(x: area.minX + halfWidth + gap, y: area.minY, width: halfWidth, height: halfHeight)
let small1 = CGRect(x: focused.minX, y: area.minY + halfHeight + gap, width: quarterWidth, height: halfHeight)
let small2 = CGRect(x: focused.minX + quarterWidth + gap, y: small1.minY, width: quarterWidth, height: halfHeight)
let windowRadius: CGFloat = 40

// Unfocused windows: translucent glass
for window in [master, small1, small2] {
    fillGradient(
        roundedRect(window, windowRadius),
        [color(0x8fa3ff, 0.50), color(0x6d7fe0, 0.32)],
        from: CGPoint(x: window.minX, y: window.minY),
        to: CGPoint(x: window.maxX, y: window.maxY),
    )
    context.addPath(roundedRect(window.insetBy(dx: 3, dy: 3), windowRadius - 3))
    context.setStrokeColor(color(0xffffff, 0.14))
    context.setLineWidth(6)
    context.strokePath()
}

// The focused window: brighter, with a glowing border in the default border color of HyprSpace
let focusedPath = roundedRect(focused, windowRadius)
fillGradient(
    focusedPath,
    [color(0x4ad8ff, 0.50), color(0x3a7bff, 0.38)],
    from: CGPoint(x: focused.minX, y: focused.minY),
    to: CGPoint(x: focused.maxX, y: focused.maxY),
)
context.saveGState()
context.setShadow(offset: .zero, blur: 44, color: color(0x33ccff, 0.85))
context.addPath(roundedRect(focused.insetBy(dx: 9, dy: 9), windowRadius - 9))
context.setStrokeColor(color(0x33ccff))
context.setLineWidth(18)
context.strokePath()
context.restoreGState()
// Second pass without the glow keeps the border crisp
context.addPath(roundedRect(focused.insetBy(dx: 9, dy: 9), windowRadius - 9))
context.setStrokeColor(color(0x7fe3ff))
context.setLineWidth(18)
context.strokePath()

let image = context.makeImage()!
let url = URL(fileURLWithPath: outputPath)
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("Can't write \(outputPath)\n".data(using: .utf8)!)
    exit(1)
}
