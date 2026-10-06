import AppKit
import CryptoKit
import QuickTileCore

@MainActor final class Catalog {
    private(set) var apps: [AppEntry] = []
    private(set) var shortcuts: [ShortcutEntry] = []
    private(set) var note: String?
    private(set) var generation = UUID()
    private var locations: [String: URL] = [:]
    private var icons: [String: Data] = [:]
    private var refreshing = false
    func refresh() async {
        guard !refreshing else { return }; refreshing = true
        defer { refreshing = false }
        let indexed = try? await ProcessJob().run(executable: "/usr/bin/mdfind", arguments: ["-0", "kMDItemContentType == 'com.apple.application-bundle'"], timeout: 10)
        let indexedURLs = indexed?.status == 0 ? (indexed?.text.split(separator: "\0").map { URL(fileURLWithPath: String($0)) } ?? []) : []
        let runningURLs = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        let addedURLs = (UserDefaults.standard.stringArray(forKey: "additionalApplicationPaths") ?? []).map { URL(fileURLWithPath: $0) }
        let urls: [URL] = await Task.detached(priority: .utility) {
            var results = Set<URL>()
            let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices", "/System/Cryptexes/App/System/Applications", NSHomeDirectory() + "/Applications"]
            for root in roots {
                guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                while let url = enumerator.nextObject() as? URL {
                    if url.pathExtension.lowercased() == "app" { results.insert(url); enumerator.skipDescendants() }
                    else if ["framework", "bundle", "plugin"].contains(url.pathExtension) { enumerator.skipDescendants() }
                }
            }
            return Self.applicationURLs(candidates: Array(results) + indexedURLs + runningURLs + addedURLs)
        }.value
        var entries: [String: AppEntry] = [:], paths: [String: URL] = [:], images: [String: Data] = [:]
        for url in urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  (try? Validation.identifier(id)) != nil, entries[id] == nil else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
            let png = Self.iconPNG(url)
            let version = png.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
            if let version, let png { images[version] = png }
            entries[id] = AppEntry(id: id, name: name, iconVersion: version); paths[id] = url
            await Task.yield()
        }
        apps = entries.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        locations = paths; icons = images; generation = UUID()
        do {
            let output = try await ProcessJob().run(executable: "/usr/bin/shortcuts", arguments: ["list", "--show-identifiers"], timeout: 20)
            guard output.status == 0 else { throw QuickTileError.failed("Shortcuts catalog unavailable. Open Shortcuts on this Mac, then refresh.") }
            shortcuts = Self.parseShortcuts(output.text)
            note = nil
        } catch { shortcuts = []; note = error.localizedDescription }
    }
    /// Resolve symlinked installations and merge Spotlight, directory, and running-app results.
    nonisolated static func applicationURLs(candidates: [URL]) -> [URL] {
        Set(candidates.map { $0.resolvingSymlinksInPath().standardizedFileURL }).filter { url in
            guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier, (try? Validation.identifier(id)) != nil,
                  let executable = bundle.executableURL, FileManager.default.fileExists(atPath: executable.path) else { return false }
            if let platforms = bundle.object(forInfoDictionaryKey: "CFBundleSupportedPlatforms") as? [String],
               !platforms.contains("MacOSX") { return false }
            // Don't offer embedded updaters/helpers as standalone applications.
            let ancestors = url.deletingLastPathComponent().pathComponents
            if ancestors.contains(where: { $0.lowercased().hasSuffix(".app") }), !url.path.contains("/Contents/Applications/") { return false }
            return true
        }.sorted {
            func rank(_ url: URL) -> Int {
                if url.path.hasPrefix("/Applications/") || url.path.hasPrefix("/System/") { return 0 }
                if url.path.hasPrefix(NSHomeDirectory() + "/Applications/") { return 1 }
                return 2
            }
            return rank($0) == rank($1) ? $0.path < $1.path : rank($0) < rank($1)
        }
    }
    func addApplication(_ url: URL) throws {
        guard let app = Self.applicationURLs(candidates: [url]).first else { throw QuickTileError.invalid("Choose a runnable Mac application.") }
        var paths = UserDefaults.standard.stringArray(forKey: "additionalApplicationPaths") ?? []
        if !paths.contains(app.path) { paths.append(app.path) }
        UserDefaults.standard.set(paths, forKey: "additionalApplicationPaths")
    }
    static func parseShortcuts(_ text: String) -> [ShortcutEntry] {
        // Apple's CLI emits Name (UUID); match only the final UUID so names can contain parentheses.
        let regex = try! NSRegularExpression(pattern: #"^(.+) \(([0-9A-Fa-f-]{36})\)$"#, options: .anchorsMatchLines)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: text), let idRange = Range(match.range(at: 2), in: text), let id = UUID(uuidString: String(text[idRange])) else { return nil }
            return ShortcutEntry(id: id.uuidString, name: String(text[nameRange]))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func url(for bundleID: String) -> URL? {
        if let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), Bundle(url: resolved)?.bundleIdentifier == bundleID { return resolved }
        if let known = locations[bundleID], FileManager.default.fileExists(atPath: known.path), Bundle(url: known)?.bundleIdentifier == bundleID { return known }
        return nil
    }
    func icon(version: String) -> Data? { icons[version] }
    private static func iconPNG(_ url: URL) -> Data? {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context; context.imageInterpolation = .high
        let size = image.size
        let ratio = min(256 / max(1, size.width), 256 / max(1, size.height))
        let target = NSRect(x: (256 - size.width * ratio) / 2, y: (256 - size.height * ratio) / 2, width: size.width * ratio, height: size.height * ratio)
        image.draw(in: target, from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        guard let png = bitmap.representation(using: .png, properties: [:]), png.count <= Limits.assetBytes else { return nil }
        return png
    }
}
