#!/usr/bin/env swift
import AppKit

// Original QuickTile mark: a centered grid of four equal soft squares.
// All artwork is geometry authored here; no bundled or downloaded application icons.
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let positions = [(244,544),(544,544),(244,244),(544,244)]
func icon(size: Int, mac: Bool, dark: Bool = true) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(size) / 1024); (transform as NSAffineTransform).concat()
    let bg = dark ? NSColor(white: 0.065, alpha: 1) : NSColor(white: 0.95, alpha: 1)
    let fg = dark ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.08, alpha: 1)
    bg.setFill()
    if mac { NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 204, yRadius: 204).fill() }
    else { NSRect(x: 0, y: 0, width: 1024, height: 1024).fill() }
    fg.setFill()
    precondition(Set(positions.map(\.0)).count == 2 && Set(positions.map(\.1)).count == 2)
    precondition(positions.reduce(0) { $0 + $1.0 + 118 } / 4 == 512)
    precondition(positions.reduce(0) { $0 + $1.1 + 118 } / 4 == 512)
    for (x,y) in positions {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 236, height: 236), xRadius: 55, yRadius: 55).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
let ios = root.appendingPathComponent("QuickTile/Assets.xcassets/AppIcon.appiconset")
let mac = root.appendingPathComponent("QuickTileMac/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: ios, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: mac, withIntermediateDirectories: true)
try icon(size: 1024, mac: false, dark: false).write(to: ios.appendingPathComponent("QuickTile.png"))
try icon(size: 1024, mac: false).write(to: ios.appendingPathComponent("QuickTile-dark.png"))
try icon(size: 1024, mac: false).write(to: ios.appendingPathComponent("QuickTile-tinted.png"))
let iosJSON: [String: Any] = ["images": [["filename":"QuickTile.png","idiom":"universal","platform":"ios","size":"1024x1024"], ["filename":"QuickTile-dark.png","idiom":"universal","platform":"ios","size":"1024x1024","appearances":[["appearance":"luminosity","value":"dark"]]], ["filename":"QuickTile-tinted.png","idiom":"universal","platform":"ios","size":"1024x1024","appearances":[["appearance":"luminosity","value":"tinted"]]]], "info":["author":"QuickTile","version":1]]
try JSONSerialization.data(withJSONObject: iosJSON, options: [.prettyPrinted, .sortedKeys]).write(to: ios.appendingPathComponent("Contents.json"))
var images: [[String: String]] = []
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let filename = "icon_\(points)@\(scale)x.png"
        try icon(size: points * scale, mac: true).write(to: mac.appendingPathComponent(filename))
        images.append(["filename":filename,"idiom":"mac","size":"\(points)x\(points)","scale":"\(scale)x"])
    }
}
try JSONSerialization.data(withJSONObject: ["images":images,"info":["author":"QuickTile","version":1]], options: [.prettyPrinted,.sortedKeys]).write(to: mac.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"QuickTile\",\"version\":1}}".utf8).write(to: mac.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Generated original iOS and macOS icons.")
let mark = root.appendingPathComponent("QuickTileMac/Assets.xcassets/MenuBarMark.imageset")
try FileManager.default.createDirectory(at: mark, withIntermediateDirectories: true)
var menuImages: [[String: String]] = []
for scale in [1, 2] {
    let size = 18 * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.black.setFill()
    let factor = CGFloat(14 * scale) / 536
    for (x, y) in positions {
        NSBezierPath(roundedRect: NSRect(x: CGFloat(2 * scale) + CGFloat(x - 244) * factor, y: CGFloat(2 * scale) + CGFloat(y - 244) * factor, width: 236 * factor, height: 236 * factor), xRadius: 55 * factor, yRadius: 55 * factor).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let filename = "mark@\(scale)x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: mark.appendingPathComponent(filename))
    menuImages.append(["filename":filename, "idiom":"mac", "scale":"\(scale)x"])
}
try JSONSerialization.data(withJSONObject: ["images":menuImages, "info":["author":"QuickTile", "version":1], "properties":["template-rendering-intent":"template"]], options: [.prettyPrinted,.sortedKeys]).write(to: mark.appendingPathComponent("Contents.json"))
