import Foundation
import AppIntents
import WidgetKit
import QuickTileCore

struct WidgetBoard: Codable, Identifiable {
    var id: String
    var name: String
    var symbol: String
    var pages: [[Tile?]]
}
struct WidgetSnapshot: Codable {
    var macID: UUID?
    var macName: String
    var boards: [WidgetBoard]
    var updated: Date
    var icons: [String: Data]? = nil
    var playback: [PlaybackSnapshot]? = nil
    var playbackDate: Date? = nil
    var feedback: String?
    var feedbackDate: Date?
    static let empty = WidgetSnapshot(macName: "QuickTile", boards: [], updated: .distantPast)
}
enum WidgetStore {
    static let group = "group.sahil.QuickTile"
    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }
    static var enabled: Bool { defaults?.bool(forKey: "widgetControlsEnabled") == true }
    static func clear() {
        defaults?.removeObject(forKey: "widgetSnapshot")
        for key in defaults?.dictionaryRepresentation().keys ?? Dictionary<String, Any>().keys where key.hasPrefix("widget-panel-") { defaults?.removeObject(forKey: key) }
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func load() -> WidgetSnapshot {
        guard enabled, let data = defaults?.data(forKey: "widgetSnapshot"), data.count <= 2_097_152,
              let value = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return value
    }
    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= 2_097_152 else {
            defaults?.removeObject(forKey: "widgetSnapshot"); WidgetCenter.shared.reloadAllTimelines(); return
        }
        defaults?.set(data, forKey: "widgetSnapshot")
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func feedback(_ message: String, playback: [PlaybackSnapshot]? = nil) {
        guard enabled else { return }
        var snapshot = load(); if let playback { snapshot.playback = playback; snapshot.playbackDate = Date() }; snapshot.feedback = String(message.prefix(120)); snapshot.feedbackDate = Date(); save(snapshot)
    }
    static func tile(_ id: String) -> Tile? { load().boards.flatMap(\.pages).flatMap { $0 }.compactMap { $0 }.first { $0.id.uuidString == id } }
    static func needsApp(_ tile: Tile) -> Bool {
        WidgetControlPolicy.requiresApp(tile.action)
    }
    static func url(_ tile: Tile) -> URL { URL(string: "quicktile://tile/" + tile.id.uuidString)! }
}
struct BoardEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Board"
    static var defaultQuery = BoardQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}
struct BoardQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BoardEntity] { values.filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [BoardEntity] { values }
    func defaultResult() async -> BoardEntity? { values.first }
    private var values: [BoardEntity] { WidgetStore.load().boards.map { .init(id: $0.id, name: $0.name) } }
}
struct TileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tile"
    static var defaultQuery = TileQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}
struct TileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TileEntity] { values.filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [TileEntity] { values }
    func defaultResult() async -> TileEntity? { values.first }
    private var values: [TileEntity] {
        WidgetStore.load().boards.flatMap { board in board.pages.flatMap { $0 }.compactMap { $0 }.map { .init(id: $0.id.uuidString, name: "\(board.name) · \($0.name)") } }
    }
}
struct BoardWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Board controls"
    @Parameter(title: "Board") var board: BoardEntity?
    @Parameter(title: "Page", default: 1, inclusiveRange: (1, 1000)) var page: Int
    @Parameter(title: "Last four tiles", default: false) var lastFour: Bool
}
struct TileWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Single tile"
    @Parameter(title: "Tile") var tile: TileEntity?
}
struct RunWidgetTile: LiveActivityIntent {
    static var title: LocalizedStringResource = "Run QuickTile action"
    static var openAppWhenRun = false
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .background }
    @Parameter(title: "Tile ID") var tileID: String
    @Parameter(title: "Adjustment", default: 0) var adjustment: Int
    init() {}
    init(_ id: String, adjustment: Int = 0) { self.tileID = id; self.adjustment = adjustment }
    @MainActor func perform() async throws -> some IntentResult {
        #if QUICKTILE_WIDGET_EXTENSION
        throw WidgetActionError.unavailable("Open QuickTile once to enable controls.")
        #else
        do { try await WidgetActionRunner.shared.run(tileID: tileID, adjustment: adjustment) }
        catch { WidgetStore.feedback(error.localizedDescription, playback: []); throw error }
        #endif
        return .result()
    }
}
enum WidgetActionError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { switch self { case .unavailable(let message): message } }
}

struct WidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Next QuickTile page"
    static var openAppWhenRun = false
    @Parameter(title: "Board") var boardID: String
    @Parameter(title: "Starting page") var originPage: Int
    @Parameter(title: "Starting half") var originHalf: Bool
    @Parameter(title: "Small widget") var small: Bool
    init() {}
    init(boardID: String, page: Int, half: Bool, small: Bool) { self.boardID = boardID; originPage = page; originHalf = half; self.small = small }
    var key: String { "widget-panel-\(boardID)-\(originPage)-\(originHalf)-\(small)" }
    func perform() async throws -> some IntentResult {
        guard WidgetStore.enabled, originPage > 0, let board = WidgetStore.load().boards.first(where: { $0.id == boardID }), board.pages.indices.contains(originPage - 1) else { return .result() }
        let count = board.pages.count * (small ? 2 : 1)
        let current = WidgetStore.defaults?.integer(forKey: key) ?? 0
        WidgetStore.defaults?.set((current % count + 1) % count, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
