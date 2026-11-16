#!/usr/bin/env swift
// Generates Vaakya's macOS/iOS app icon set from an SF Symbol.
//
// Output: VaakyaApp/Sources/Resources/Assets.xcassets/AppIcon.appiconset/
// Re-run via: make app-icon

import AppKit
import CoreGraphics
import Foundation

// MARK: - Brand
let symbolName = "text.bubble.fill"
let bgColor    = NSColor(red: 0x34/255.0, green: 0xA8/255.0, blue: 0x53/255.0, alpha: 1.0)
let fgColor    = NSColor.white

// MARK: - Output paths
let cwd = FileManager.default.currentDirectoryPath
let iconsetDir = "\(cwd)/VaakyaApp/Sources/Resources/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// MARK: - Render one PNG at given pixel size
func renderIcon(pixels: Int, to outPath: String) throws {
    let size = CGFloat(pixels)
    let scale = size / 1024.0

    guard let ctx = CGContext(
        data: nil,
        width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "ctx", code: 1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    // Squircle background (macOS-style rounded tile)
    let inset: CGFloat = 0 // bleed to edges; system handles further masking if needed
    let rect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
    let cornerRadius = size * 0.225  // matches macOS Big Sur+ squircle
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgColor.setFill()
    path.fill()

    // SF Symbol foreground
    let symbolPointSize = size * 0.55
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
        throw NSError(domain: "symbol", code: 1, userInfo: [NSLocalizedDescriptionKey: "SF Symbol '\(symbolName)' not found"])
    }

    // Tint to white
    let tinted = NSImage(size: symbol.size, flipped: false) { dstRect in
        symbol.draw(in: dstRect)
        fgColor.set()
        dstRect.fill(using: .sourceAtop)
        return true
    }

    // Center the symbol
    let drawRect = CGRect(
        x: (size - tinted.size.width) / 2,
        y: (size - tinted.size.height) / 2,
        width: tinted.size.width,
        height: tinted.size.height
    )
    tinted.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = ctx.makeImage() else { throw NSError(domain: "cg", code: 1) }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "png", code: 1)
    }
    try data.write(to: URL(fileURLWithPath: outPath))
    _ = scale // silence
}

// MARK: - macOS icon set sizes (size@scale → pixels, filename)
struct IconEntry { let size: Int; let scale: Int; let idiom: String }
let entries: [IconEntry] = [
    .init(size: 16,  scale: 1, idiom: "mac"),
    .init(size: 16,  scale: 2, idiom: "mac"),
    .init(size: 32,  scale: 1, idiom: "mac"),
    .init(size: 32,  scale: 2, idiom: "mac"),
    .init(size: 128, scale: 1, idiom: "mac"),
    .init(size: 128, scale: 2, idiom: "mac"),
    .init(size: 256, scale: 1, idiom: "mac"),
    .init(size: 256, scale: 2, idiom: "mac"),
    .init(size: 512, scale: 1, idiom: "mac"),
    .init(size: 512, scale: 2, idiom: "mac"),
]

// MARK: - Generate PNGs
for e in entries {
    let pixels = e.size * e.scale
    let filename = "icon_\(e.size)x\(e.size)\(e.scale == 2 ? "@2x" : "").png"
    let outPath = "\(iconsetDir)/\(filename)"
    try renderIcon(pixels: pixels, to: outPath)
    print("  ✅ \(filename)  (\(pixels)x\(pixels))")
}

// MARK: - iOS marketing 1024 (universal)
let iosFilename = "icon_ios_1024.png"
try renderIcon(pixels: 1024, to: "\(iconsetDir)/\(iosFilename)")
print("  ✅ \(iosFilename)  (1024x1024, iOS)")

// MARK: - Contents.json
var images: [[String: Any]] = entries.map { e in
    [
        "size": "\(e.size)x\(e.size)",
        "idiom": e.idiom,
        "filename": "icon_\(e.size)x\(e.size)\(e.scale == 2 ? "@2x" : "").png",
        "scale": "\(e.scale)x",
    ]
}
// No "scale" key: actool only treats a universal 1024 entry as the iOS single-size icon without one.
images.append([
    "size": "1024x1024",
    "idiom": "universal",
    "platform": "ios",
    "filename": iosFilename,
])

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "vaakya"],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: "\(iconsetDir)/Contents.json"))
print("  ✅ Contents.json")

// MARK: - Asset catalog root Contents.json (if missing)
let rootContents = "\(cwd)/VaakyaApp/Sources/Resources/Assets.xcassets/Contents.json"
if !FileManager.default.fileExists(atPath: rootContents) {
    let root: [String: Any] = ["info": ["version": 1, "author": "vaakya"]]
    try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: rootContents))
    print("  ✅ Assets.xcassets/Contents.json (created)")
}

print("\n✅ Icon set generated: \(iconsetDir)")
