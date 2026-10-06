import Foundation
import Security

public struct LayoutStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(macID: UUID) throws -> DeckLayout {
        let url = directory.appendingPathComponent(macID.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return DeckLayout(macID: macID) }
        let layout: DeckLayout
        do { layout = try Self.decode(Data(contentsOf: url)) }
        catch {
            let backup = directory.appendingPathComponent(macID.uuidString + ".backup.json")
            guard let recovered = try? Self.decode(Data(contentsOf: backup)), recovered.macID == macID else { throw error }
            return recovered
        }
        guard layout.macID == macID else { throw QuickTileError.invalid("DeckLayout belongs to another Mac.") }
        return layout
    }
    public static func decode(_ data: Data) throws -> DeckLayout {
        struct Header: Decodable { let schemaVersion: Int }
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        var result: DeckLayout
        switch version {
        case 1:
            struct Legacy: Decodable { let macID: UUID; let pages: [DeckPage] }
            let old = try JSONDecoder().decode(Legacy.self, from: data)
            result = DeckLayout(macID: old.macID, pages: old.pages)
        case 2, 3, 4: result = try JSONDecoder().decode(DeckLayout.self, from: data)
        default: throw QuickTileError.unsupported("This layout was saved by a newer QuickTile. Update the app; your file has been preserved.")
        }
        if result.pages.isEmpty { result.pages = [DeckPage()] }
        guard Set(result.pages.map(\.id)).count == result.pages.count else { throw QuickTileError.invalid("Duplicate page identifiers.") }
        let tiles = result.pages.flatMap(\.tiles)
        guard Set(tiles.map(\.id)).count == tiles.count else { throw QuickTileError.invalid("Duplicate tile identifiers.") }
        for page in result.pages { try Validation.name(page.name) }
        for tile in tiles {
            try Validation.name(tile.name)
            if case .preset = tile.action { continue } // Preserve unavailable presets for repair in the editor.
            try tile.action.validate()
        }
        for page in result.pages.indices {
            for tile in result.pages[page].tiles.indices {
                if case .volume = result.pages[page].tiles[tile].action {
                    result.pages[page].tiles[tile].action = .dial(.volume)
                    result.pages[page].tiles[tile].symbol = "speaker.wave.2"
                }
                if case .music(let command) = result.pages[page].tiles[tile].action {
                    result.pages[page].tiles[tile].action = .media(command)
                }
                if let symbol = result.pages[page].tiles[tile].action.fixedSymbol {
                    result.pages[page].tiles[tile].symbol = symbol
                }
            }
        }
        result.schemaVersion = 4; result.settings.showLabels = false
        return result
    }
    public func save(_ layout: DeckLayout) throws {
        let data = try JSONEncoder().encode(layout)
        _ = try Self.decode(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(layout.macID.uuidString + ".json")
        // Preserve a known-good previous revision, never a damaged primary file.
        if let previous = try? Data(contentsOf: url), (try? Self.decode(previous)) != nil {
            try previous.write(to: directory.appendingPathComponent(layout.macID.uuidString + ".backup.json"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}

/// Encoding, validation and disk access stay off the UI actor. Writes serialize
/// across board switches, so a slower old revision cannot replace a newer one.
public actor LayoutWriter {
    private let store: LayoutStore
    public init(store: LayoutStore) { self.store = store }
    public func save(_ layout: DeckLayout) throws { try store.save(layout) }
    public func load(macID: UUID) throws -> DeckLayout { try store.load(macID: macID) }
}
public enum SecureRandom {
    public static func key() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw QuickTileError.failed("Could not generate secure pairing credentials.") }
        return Data(bytes)
    }
}
/// Credentials are device-only generic passwords; never included in layout JSON or exports.
public struct KeychainStore {
    public let service: String
    public init(service: String) { self.service = service }
    public func read<T: Decodable>(_ type: T.Type, account: String, allowAuthenticationUI: Bool = true) throws -> T? {
        var query = base(account)
        if !allowAuthenticationUI { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw failure(status) }
        return try JSONDecoder().decode(type, from: data)
    }
    public func write<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(base(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = base(account)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }
    public func delete(account: String) throws {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    private func failure(_ status: OSStatus) -> QuickTileError { .failed("Keychain error (\(status)). Unlock this device and try again.") }
}
