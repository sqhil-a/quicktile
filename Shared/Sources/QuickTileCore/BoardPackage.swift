import Foundation
import CryptoKit

/// A portable, data-only board package. Credentials and agent history are not
/// members of this type and therefore cannot be included by export.
public struct BoardPackage: Codable, Sendable {
    public var version = 1
    public var boards: [DeckPage]
    public var assets: [String: Data]
    public init(boards: [DeckPage], assets: [String: Data] = [:]) { self.boards = boards; self.assets = assets }
    public func encoded() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= 32 * 1024 * 1024 else { throw QuickTileError.invalid("This export exceeds 32 MB. Export fewer boards.") }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 32 * 1024 * 1024 else { throw QuickTileError.invalid("Board file exceeds 32 MB.") }
        let package = try JSONDecoder().decode(Self.self, from: data)
        try package.validate()
        return package
    }
    public func validate() throws {
        guard version == 1, !boards.isEmpty, boards.count <= 256 else { throw QuickTileError.invalid("Unsupported or empty board file.") }
        guard boards.flatMap(\.tiles).count <= 4096 else { throw QuickTileError.invalid("Too many tiles in one import.") }
        guard Set(boards.map(\.id)).count == boards.count,
              Set(boards.flatMap(\.tiles).map(\.id)).count == boards.flatMap(\.tiles).count else { throw QuickTileError.invalid("Duplicate board or tile identifiers.") }
        for board in boards {
            try Validation.name(board.name)
            guard board.symbol.count <= 128, !board.symbol.contains("/") else { throw QuickTileError.invalid("Invalid board icon.") }
            try validateReference(board.customIconReference)
            if let profile = board.linkedAppProfileID { try Validation.identifier(profile) }
            if let names = board.pageNames { guard names.count <= 512 else { throw QuickTileError.invalid("Too many page names.") }; for name in names { try Validation.name(name) } }
            for tile in board.tiles {
                try Validation.name(tile.name)
                guard tile.symbol.count <= 128, !tile.symbol.contains("/") else { throw QuickTileError.invalid("Invalid tile icon.") }
                try validateReference(tile.customIconReference)
                if let id = tile.targetBundleID { try Validation.identifier(id) }
                if let id = tile.agentLauncherBundleID { try Validation.identifier(id) }
                try tile.configuredShortcut?.validate()
                if case .preset = tile.action { } else { try tile.action.validate() }
            }
            if let order = board.tileOrder {
                let ids = order.compactMap { $0 }
                guard order.count <= 4096, Set(ids).count == ids.count, Set(ids).isSubset(of: Set(board.tiles.map(\.id))) else { throw QuickTileError.invalid("Invalid tile positions.") }
            }
        }
        guard assets.count <= 256 else { throw QuickTileError.invalid("Too many custom icons.") }
        for (key, value) in assets {
            let hash = SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
            guard key.count == 64, key.allSatisfy(\.isHexDigit), !value.isEmpty, value.count <= Limits.assetBytes, hash == key else { throw QuickTileError.invalid("Invalid custom icon asset.") }
        }
    }
    private func validateReference(_ reference: String?) throws {
        guard let reference else { return }
        guard reference.count == 64, reference.allSatisfy(\.isHexDigit), assets[reference] != nil else {
            throw QuickTileError.invalid("A custom icon is missing or has an invalid reference.")
        }
    }
    /// Preserve gaps and references while creating new IDs for every import.
    public func copies() -> [DeckPage] {
        boards.map { original in
            var board = original
            board.id = UUID()
            let ids = Dictionary(uniqueKeysWithValues: board.tiles.map { ($0.id, UUID()) })
            board.tiles = board.tiles.map { original in var tile = original; tile.id = ids[original.id]!; return tile }
            board.tileOrder = board.tileOrder?.map { $0.flatMap { ids[$0] } }
            board.automaticSwitch = false
            return board
        }
    }
}
