#!/usr/bin/env swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
for (filename, dark) in [("QuickTile.png", false), ("QuickTile-dark.png", true), ("QuickTile-tinted.png", true)] {
    let url = root.appendingPathComponent("QuickTile/Assets.xcassets/AppIcon.appiconset/" + filename)
    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url))!
    precondition(bitmap.pixelsWide == 1024 && bitmap.pixelsHigh == 1024)
    var bounds: [(Int, Int, Int, Int)] = []
    for row in 0..<2 { for column in 0..<2 {
        var minX = 1024, minY = 1024, maxX = -1, maxY = -1
        for y in (row * 512)..<((row + 1) * 512) { for x in (column * 512)..<((column + 1) * 512) {
            let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            guard dark ? color.redComponent > 0.85 : color.redComponent < 0.15 else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        precondition(maxX - minX + 1 == 236 && maxY - minY + 1 == 236, "All four squares must have the same dimensions.")
        bounds.append((minX, minY, maxX, maxY))
    } }
    precondition(bounds[0].0 == bounds[2].0 && bounds[1].0 == bounds[3].0)
    precondition(bounds[0].1 == bounds[1].1 && bounds[2].1 == bounds[3].1)
    precondition(bounds[0].0 + bounds[1].2 == 1023 && bounds[0].1 + bounds[2].3 == 1023, "The mark must be centered.")
    precondition(bounds[1].0 - bounds[0].2 == bounds[2].1 - bounds[0].3, "Grid spacing must match.")
    print("Aligned grid: \(filename)")
}
