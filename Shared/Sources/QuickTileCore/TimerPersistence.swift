import Foundation

/// Running timers store their deadline, so elapsed time survives suspension or restart.
public actor TimerPersistence {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(macID: UUID) throws -> [UUID: TileCountdown] {
        let file = directory.appendingPathComponent(macID.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        guard data.count <= 1_048_576 else { throw QuickTileError.invalid("Saved timers are too large.") }
        var values = try JSONDecoder().decode([UUID: TileCountdown].self, from: data)
        for id in Array(values.keys) { values[id]?.update(at: Date()) }
        return values
    }
    public func save(_ values: [UUID: TileCountdown], macID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: directory.appendingPathComponent(macID.uuidString + ".json"), options: .atomic)
    }
}
