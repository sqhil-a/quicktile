import SwiftUI
import Combine
import CryptoKit
import ImageIO
import QuickTileCore

@MainActor final class IconResource: ObservableObject {
    @Published var image: UIImage?
    var loading = false
    var retryAfter = Date.distantPast
}

/// Each image has its own observation scope. Receiving an icon never invalidates
/// the deck, search field, list, or other icons.
@MainActor final class PhoneImages {
    enum Source: Hashable {
        case app(String), website(String), custom(String)
        var key: String {
            switch self {
            case .app(let hash): return hash
            case .website(let url): return "web-" + ImageDisk.digest(Data(url.utf8))
            case .custom(let reference): return "custom-" + reference
            }
        }
    }
    private let resources = NSCache<NSString, IconResource>()
    private final class WeakResource {
        weak var value: IconResource?
        init(_ value: IconResource) { self.value = value }
    }
    // Visible views retain their resource even if NSCache evicts it.
    private var liveResources: [String: WeakResource] = [:]
    private var pending: [String: IconResource] = [:]
    private let disk: ImageDisk
    private var websites: [(Source, IconResource)] = []
    private var websiteLoads = 0
    var requestApp: ((String) -> Void)?
    init(directory: URL) {
        disk = ImageDisk(directory: directory)
        resources.countLimit = 192 // At most ~48 MB of 256 px decoded images, plus visible resources.
    }
    func resource(_ source: Source) -> IconResource {
        if let current = liveResources[source.key]?.value ?? pending[source.key] ?? resources.object(forKey: source.key as NSString) { return current }
        if liveResources.count > 256 { liveResources = liveResources.filter { $0.value.value != nil } }
        let resource = IconResource(); resources.setObject(resource, forKey: source.key as NSString)
        liveResources[source.key] = WeakResource(resource)
        return resource
    }
    func load(_ source: Source, into resource: IconResource) async {
        guard resource.image == nil, !resource.loading, resource.retryAfter < Date() else { return }
        if case .app(let hash) = source {
            guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else {
                resource.retryAfter = .distantFuture; return
            }
        }
        if case .custom(let hash) = source, !(hash.count == 64 && hash.allSatisfy(\.isHexDigit)) { resource.retryAfter = .distantFuture; return }
        resource.loading = true; pending[source.key] = resource
        if let image = await disk.read(source.key) { finish(source.key, image: image); return }
        switch source {
        case .app(let hash): requestApp?(hash)
        case .website:
            websites.append((source, resource)); pumpWebsites()
        case .custom: finish(source.key, image: nil)
        }
    }
    func receive(_ asset: IconAsset) async -> Bool {
        guard let image = await disk.storeApp(asset) else { return false }
        finish(asset.version, image: image)
        return true
    }
    func failed(_ key: String) { finish(key, image: nil) }
    /// Import once at a bounded size; views observe the same resource as remote artwork.
    func importCustomImage(_ data: Data) async throws -> String {
        let (reference, image) = try await disk.storeCustom(data)
        resource(.custom(reference)).image = image
        return reference
    }
    func exportCustomAssets(references: Set<String>) async throws -> [String: Data] {
        try await disk.customAssets(references)
    }
    func importCustomAssets(_ assets: [String: Data]) async throws -> [String: String] {
        guard assets.count <= 512 else { throw QuickTileError.invalid("This file contains too many custom icons.") }
        var result: [String: String] = [:]
        for (old, data) in assets { result[old] = try await importCustomImage(data) }
        return result
    }
    func resetAppRequests() {
        for key in Array(pending.keys) where !key.hasPrefix("web-") && !key.hasPrefix("custom-") {
            pending.removeValue(forKey: key)?.loading = false
        }
    }
    func retryAppRequests() {
        for (key, reference) in liveResources where !key.hasPrefix("web-") && !key.hasPrefix("custom-") {
            guard let resource = reference.value, resource.image == nil else { continue }
            resource.retryAfter = .distantPast
            resource.loading = true
            pending[key] = resource
            requestApp?(key)
        }
    }
    private func finish(_ key: String, image: UIImage?) {
        let resource = pending.removeValue(forKey: key) ?? liveResources[key]?.value ?? resources.object(forKey: key as NSString)
        resource?.image = image; resource?.loading = false
        resource?.retryAfter = image == nil ? Date().addingTimeInterval(key.hasPrefix("web-") ? 1800 : 60) : .distantPast
    }
    private func pumpWebsites() {
        while websiteLoads < 2, !websites.isEmpty {
            let (source, _) = websites.removeFirst(); websiteLoads += 1
            Task {
                var image: UIImage?
                if case .website(let url) = source { image = await disk.website(url, key: source.key) }
                finish(source.key, image: image); websiteLoads -= 1; pumpWebsites()
            }
        }
    }
}

actor ImageDisk {
    private let directory: URL
    private let customDirectory: URL
    private let session: URLSession
    init(directory: URL) {
        self.directory = directory
        customDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuickTile/BoardIcons", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6; config.timeoutIntervalForResource = 12
        config.httpMaximumConnectionsPerHost = 2
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }
    nonisolated static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func read(_ key: String) -> UIImage? {
        let custom = key.hasPrefix("custom-")
        let reference = String(key.dropFirst(7))
        if custom, !(reference.count == 64 && reference.allSatisfy(\.isHexDigit)) { return nil }
        let file = (custom ? customDirectory : directory).appendingPathComponent(key + ".png")
        if custom, !FileManager.default.fileExists(atPath: file.path), let cached = try? Data(contentsOf: directory.appendingPathComponent(key + ".png")), Self.digest(cached) == reference {
            try? FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
            try? cached.write(to: file, options: .atomic)
        }
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Limits.assetBytes,
              let data = try? Data(contentsOf: file), key.hasPrefix("web-") || Self.digest(data) == (custom ? reference : key) else { return nil }
        return Self.decode(data, maxSourceDimension: key.hasPrefix("web-") ? 4096 : 512)
    }
    func storeApp(_ asset: IconAsset) -> UIImage? {
        guard asset.png.count <= Limits.assetBytes, Self.digest(asset.png) == asset.version,
              let image = Self.decode(asset.png, maxSourceDimension: 512) else { return nil }
        write(asset.png, key: asset.version); return image
    }
    func storeCustom(_ data: Data) throws -> (String, UIImage) {
        guard data.count <= 20_971_520, let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw QuickTileError.invalid("Choose a supported image under 20 MB.") }
        for size in [512, 384, 256] {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { continue }
            let result = UIImage(cgImage: image)
            guard let png = result.pngData(), png.count <= Limits.assetBytes else { continue }
            let reference = Self.digest(png)
            try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
            try png.write(to: customDirectory.appendingPathComponent("custom-" + reference + ".png"), options: .atomic)
            return (reference, result)
        }
        throw QuickTileError.invalid("This image could not be used as an icon.")
    }
    func customAssets(_ references: Set<String>) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for reference in references {
            guard reference.count == 64, reference.allSatisfy(\.isHexDigit) else { throw QuickTileError.invalid("Invalid icon reference.") }
            let data = try Data(contentsOf: customDirectory.appendingPathComponent("custom-" + reference + ".png"))
            guard data.count <= Limits.assetBytes, Self.digest(data) == reference else { throw QuickTileError.invalid("Icon exceeds the file limit or is damaged.") }
            result[reference] = data
        }
        return result
    }
    private func write(_ data: Data, key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(key + ".png"), options: .atomic)
    }
    private static func decode(_ data: Data, maxSourceDimension: Int = 4096) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        guard let width, let height, (1...maxSourceDimension).contains(width), (1...maxSourceDimension).contains(height),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    func website(_ text: String, key: String) async -> UIImage? {
        // Fetch only the site's origin, never the saved URL's private path/query.
        guard let origin = WebsiteIcons.origin(text) else { return nil }
        var candidates = WebsiteIcons.candidates(html: "", origin: origin)
        if let data = try? await fetch(origin, limit: 262_144), let html = String(data: data, encoding: .utf8) {
            candidates = WebsiteIcons.candidates(html: html, origin: origin)
        }
        for url in candidates.prefix(6) {
            guard let data = try? await fetch(url, limit: Limits.assetBytes), let image = Self.decode(data) else { continue }
            if let png = image.pngData(), png.count <= Limits.assetBytes { write(png, key: key) }
            return image
        }
        return nil
    }
    private func fetch(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url); request.setValue("QuickTile/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.url?.scheme == "https", response.expectedContentLength <= limit else { throw QuickTileError.invalid("Icon unavailable") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw QuickTileError.invalid("Icon too large") }
            data.append(byte)
        }
        return data
    }
}

struct RemoteIcon: View {
    let source: PhoneImages.Source
    let store: PhoneImages
    let fallback: String
    @ObservedObject private var resource: IconResource
    init(source: PhoneImages.Source, store: PhoneImages, fallback: String) {
        self.source = source; self.store = store; self.fallback = fallback
        resource = store.resource(source)
    }
    var body: some View {
        Group {
            if let image = resource.image { Image(uiImage: image).renderingMode(.original).resizable().scaledToFit() }
            else { Image(systemName: fallback).resizable().scaledToFit().padding(8).foregroundStyle(.secondary) }
        }.task(id: ObjectIdentifier(resource)) {
            repeat {
                await store.load(source, into: resource)
                if resource.image != nil { return }
                try? await Task.sleep(for: .seconds(15))
            } while !Task.isCancelled
        }
    }
}
