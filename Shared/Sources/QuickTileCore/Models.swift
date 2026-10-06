import Foundation

public enum Limits {
    public static let protocolVersion = 2
    public static let frameBytes = 2_097_152
    public static let assetBytes = 262_144
    public static let commandLifetime: TimeInterval = 10
    public static let service = "_quicktile._tcp"
}

public enum TimerHapticPattern: String, Codable, CaseIterable, Sendable, Identifiable {
    case click, doubleClick, soft, pulse, alert, vibration, off
    public var id: Self { self }
    public var label: String {
        switch self { case .click: "Click"; case .doubleClick: "Double click"; case .soft: "Soft tap"; case .pulse: "Firm pulse"; case .alert: "Alert"; case .vibration: "Vibration"; case .off: "None" }
    }
    public var interval: TimeInterval { self == .alert || self == .vibration ? 2 : 1 }
}

public struct Tile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var action: DeckAction
    public var presetID: String?
    /// Relative, validated image identifier in the local board asset store.
    public var customIconReference: String?
    public var targetBundleID: String?
    public var mappingVersion: Int?
    public var configuredShortcut: KeyboardShortcut?
    public var agentSource: AgentSource?
    public var agentLauncherBundleID: String?
    public var timerHaptic: TimerHapticPattern?
    private var preservedAction: StoredValue?
    public var displaySymbol: String {
        if let fixed = action.fixedSymbol { return fixed }
        if let presetID, let item = ActionLibrary.actions.first(where: { $0.id == presetID }) { return item.symbol }
        return symbol
    }
    public init(id: UUID = UUID(), name: String, symbol: String, action: DeckAction) {
        self.id = id; self.name = name; self.symbol = symbol; self.action = action
    }
    private enum CodingKeys: String, CodingKey { case id, name, symbol, action, presetID, customIconReference, targetBundleID, mappingVersion, configuredShortcut, agentSource, agentLauncherBundleID, timerHaptic }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        symbol = try values.decode(String.self, forKey: .symbol)
        presetID = try values.decodeIfPresent(String.self, forKey: .presetID)
        customIconReference = try values.decodeIfPresent(String.self, forKey: .customIconReference)
        targetBundleID = try values.decodeIfPresent(String.self, forKey: .targetBundleID)
        mappingVersion = try values.decodeIfPresent(Int.self, forKey: .mappingVersion)
        configuredShortcut = try values.decodeIfPresent(KeyboardShortcut.self, forKey: .configuredShortcut)
        agentSource = try values.decodeIfPresent(AgentSource.self, forKey: .agentSource)
        agentLauncherBundleID = try values.decodeIfPresent(String.self, forKey: .agentLauncherBundleID)
        timerHaptic = try? values.decodeIfPresent(TimerHapticPattern.self, forKey: .timerHaptic)
        do { action = try values.decode(DeckAction.self, forKey: .action) }
        catch {
            preservedAction = try values.decode(StoredValue.self, forKey: .action)
            action = .preset("unavailable.saved-action")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(name, forKey: .name)
        try values.encode(symbol, forKey: .symbol); try values.encodeIfPresent(presetID, forKey: .presetID)
        try values.encodeIfPresent(customIconReference, forKey: .customIconReference)
        try values.encodeIfPresent(targetBundleID, forKey: .targetBundleID)
        try values.encodeIfPresent(mappingVersion, forKey: .mappingVersion)
        try values.encodeIfPresent(configuredShortcut, forKey: .configuredShortcut)
        try values.encodeIfPresent(agentSource, forKey: .agentSource)
        try values.encodeIfPresent(agentLauncherBundleID, forKey: .agentLauncherBundleID)
        try values.encodeIfPresent(timerHaptic, forKey: .timerHaptic)
        if let preservedAction, action == .preset("unavailable.saved-action") {
            try values.encode(preservedAction, forKey: .action)
        } else { try values.encode(action, forKey: .action) }
    }
}
/// Preserves newer saved tile payloads without allowing them to execute.
private enum StoredValue: Codable, Equatable, Sendable {
    case object([String: StoredValue]), array([StoredValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode([String: StoredValue].self) { self = .object(item) }
        else { self = .array(try value.decode([StoredValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }
}
public struct DeckPage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var tiles: [Tile]
    public var symbol: String
    public var tileOrder: [UUID?]?
    public var customIconReference: String?
    public var linkedAppProfileID: String?
    public var automaticSwitch: Bool?
    public var sourcePresetID: String?
    public var pageNames: [String]?
    public init(id: UUID = UUID(), name: String = "My board", tiles: [Tile] = [], symbol: String = "square.grid.2x2") {
        self.id = id; self.name = name; self.tiles = tiles; self.symbol = symbol
    }
    private enum CodingKeys: String, CodingKey { case id, name, tiles, symbol, tileOrder, customIconReference, linkedAppProfileID, automaticSwitch, sourcePresetID, pageNames }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        tiles = try values.decode([Tile].self, forKey: .tiles)
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        tileOrder = try values.decodeIfPresent([UUID?].self, forKey: .tileOrder)
        customIconReference = try values.decodeIfPresent(String.self, forKey: .customIconReference)
        linkedAppProfileID = try values.decodeIfPresent(String.self, forKey: .linkedAppProfileID)
        automaticSwitch = try values.decodeIfPresent(Bool.self, forKey: .automaticSwitch)
        sourcePresetID = try values.decodeIfPresent(String.self, forKey: .sourcePresetID)
        pageNames = try values.decodeIfPresent([String].self, forKey: .pageNames)
    }
    public var slots: [Tile?] {
        let byID = Dictionary(tiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var result: [Tile?] = (tileOrder ?? tiles.map { Optional($0.id) }).map { id in
            guard let id, let tile = byID[id], seen.insert(id).inserted else { return nil }
            return tile
        }
        for tile in tiles where !seen.contains(tile.id) {
            if let empty = result.firstIndex(where: { $0 == nil }) { result[empty] = tile }
            else { result.append(tile) }
        }
        let count = max(8, ((result.count + 7) / 8) * 8)
        result.append(contentsOf: repeatElement(nil, count: count - result.count))
        return result
    }
    public mutating func place(_ tileID: UUID, at destination: Int) {
        var order = slots.map { $0?.id }
        guard order.indices.contains(destination), let source = order.firstIndex(of: tileID) else { return }
        order.swapAt(source, destination); tileOrder = order
    }
    public mutating func removeTile(_ tileID: UUID) {
        tileOrder = slots.map { $0?.id == tileID ? nil : $0?.id }
        tiles.removeAll { $0.id == tileID }
    }
}
public enum Density: String, Codable, CaseIterable, Sendable { case comfortable, compact }
/// A saved page can span multiple screens without dropping or moving its tiles.
public struct DeckScreen: Identifiable, Equatable, Sendable {
    public static let capacity = 8
    public let pageID: UUID
    public let name: String
    public let symbol: String
    public let index: Int
    public let slots: [Tile?]
    public var tiles: [Tile] { slots.compactMap { $0 } }
    public var id: String { "\(pageID.uuidString)-\(index)" }
}
public enum Theme: String, Codable, CaseIterable, Sendable { case system, light, dark }
public struct DeckSettings: Codable, Equatable, Sendable {
    public var density: Density = .comfortable
    public var theme: Theme = .system
    public var showLabels = false
    public var haptics = true
    public var keepAwake = false
    public var timerNotifications: Bool?
    public init() {}
}
public struct DeckLayout: Codable, Equatable, Sendable {
    public var schemaVersion = 4
    public var macID: UUID
    public var pages: [DeckPage]
    public var settings: DeckSettings
    public var screens: [DeckScreen] {
        pages.flatMap { page in
            let slots = page.slots
            return (0..<(slots.count / DeckScreen.capacity)).map { index in
                DeckScreen(pageID: page.id, name: page.pageNames?.indices.contains(index) == true ? page.pageNames![index] : (index == 0 ? page.name : "\(page.name) · \(index + 1)"), symbol: page.symbol, index: index,
                           slots: Array(slots.dropFirst(index * DeckScreen.capacity).prefix(DeckScreen.capacity)))
            }
        }
    }
    public init(macID: UUID, pages: [DeckPage] = [DeckPage()], settings: DeckSettings = .init()) {
        self.macID = macID; self.pages = pages; self.settings = settings
    }
}
public enum DeckAction: Codable, Equatable, Sendable {
    case assistant
    case sequence(ActionSequence)
    case timer(seconds: Int)
    case agent(AgentProvider)
    case media(MediaCommand)
    case system(SystemCommand)
    case preset(String)
    case dial(ControlKind)
    case launchApp(bundleID: String)
    case keyboard(KeyboardShortcut)
    case music(MediaCommand)
    case volume(VolumeCommand)
    case shortcut(identifier: String)
    case website(url: String)

    public func validate() throws {
        switch self {
        case .sequence(let sequence): try sequence.validate()
        case .timer(let seconds):
            guard (1...3600).contains(seconds) else { throw QuickTileError.invalid("Choose a timer from 1 second to 60 minutes.") }
        case .preset(let id):
            guard ActionLibrary.preset(id: id) != nil else { throw QuickTileError.unsupported("This preset needs a newer QuickTile. Edit the tile to choose another action.") }
        case .launchApp(let id): try Validation.identifier(id)
        case .keyboard(let key): try key.validate()
        case .shortcut(let id):
            guard UUID(uuidString: id) != nil else { throw QuickTileError.invalid("Select a shortcut from the Mac catalog.") }
        case .website(let url): _ = try Validation.website(url)
        case .volume(.set(let value)):
            guard value.isFinite, (0...1).contains(value) else { throw QuickTileError.invalid("Volume must be between 0 and 100%.") }
        default: break
        }
    }
}
public enum MediaCommand: String, Codable, CaseIterable, Sendable { case playPause, previous, next }
public enum SystemCommand: String, Codable, CaseIterable, Sendable { case lock, sleepDisplay, showDesktop, darkMode, screenshot, screenshotArea }
extension DeckAction {
    /// Shared across duplicate tiles controlling the same playback target.
    public var playbackTarget: String? {
        switch self {
        case .media(.playPause), .music(.playPause): return "system"
        case .preset(let id):
            guard let preset = ActionLibrary.preset(id: id),
                  preset.category == .video, id.hasSuffix(".play") else { return nil }
            return preset.bundleID
        default: return nil
        }
    }
    public var fixedSymbol: String? {
        switch self {
        case .assistant: return "waveform"
        case .sequence: return "list.bullet.rectangle"
        case .timer: return "timer"
        case .agent(let provider): return provider.symbol
        case .media(let command), .music(let command):
            switch command { case .playPause: return "playpause.fill"; case .previous: return "backward.end.fill"; case .next: return "forward.end.fill" }
        case .system(let command):
            switch command { case .lock: return "lock.fill"; case .sleepDisplay: return "display"; case .showDesktop: return "rectangle.on.rectangle"; case .darkMode: return "circle.lefthalf.filled"; case .screenshot: return "camera.viewfinder"; case .screenshotArea: return "viewfinder" }
        case .dial(let kind): return kind == .volume ? "speaker.wave.2" : "sun.max"
        case .preset(let id): return ActionLibrary.preset(id: id)?.symbol ?? "questionmark.square.dashed"
        default: return nil
        }
    }
}
public enum VolumeCommand: Codable, Equatable, Sendable { case up, down, mute, set(Double) }
public enum KeyModifier: String, Codable, CaseIterable, Sendable {
    case command, option, control, shift
    public var symbol: String { switch self { case .command: "⌘"; case .option: "⌥"; case .control: "⌃"; case .shift: "⇧" } }
}
public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public var key: String
    public var modifiers: [KeyModifier]
    public var targetBundleID: String?
    public init(key: String = "space", modifiers: [KeyModifier] = [], targetBundleID: String? = nil) {
        self.key = key; self.modifiers = modifiers; self.targetBundleID = targetBundleID
    }
    // Physical ANSI key positions. Deliberately explicit, never interpreted as text or a script.
    public static let keyCodes: [String: UInt16] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,
        "q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,
        "6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,
        "]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"return":36,"l":37,"j":38,
        "'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,
        "tab":48,"space":49,"`":50,"delete":51,"escape":53,
        "f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,"f8":100,
        "f9":101,"f10":109,"f11":103,"f12":111,"left":123,"right":124,"down":125,"up":126,
        "home":115,"end":119,"pageup":116,"pagedown":121,"forwarddelete":117]
    public func validate() throws {
        guard Self.keyCodes[key] != nil, Set(modifiers).count == modifiers.count else {
            throw QuickTileError.invalid("Choose a supported key and unique modifiers.")
        }
        if let targetBundleID { try Validation.identifier(targetBundleID) }
    }
}
public enum Validation {
    public static func website(_ text: String) throws -> URL {
        guard text.count <= 4096, text == text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespaces.contains($0) }),
              let parts = URLComponents(string: text), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              let url = parts.url else { throw QuickTileError.invalid("Enter a full http:// or https:// URL without spaces or a username/password.") }
        return url
    }
    public static func identifier(_ id: String) throws {
        guard !id.isEmpty, id.utf8.count <= 512, !id.contains("/"), !id.contains("\0") else {
            throw QuickTileError.invalid("The application identifier is invalid.")
        }
    }
    public static func name(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 100 else {
            throw QuickTileError.invalid("Use a name between 1 and 100 characters.")
        }
    }
}
public enum QuickTileError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String), unauthorized, expired, duplicate, disconnected, timeout, unsupported(String), failed(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let m), .unsupported(let m), .failed(let m): return m
        case .unauthorized: return "This device is not authorized. Pair again from the Mac."
        case .expired: return "This request expired. Tap again if you still want to run it."
        case .duplicate: return "This request was already received and was not run again."
        case .disconnected: return "Connection lost. The action may have run; it will not be retried."
        case .timeout: return "No completion was received in time. Check the Mac before trying again."
        }
    }
}
public struct AppEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var iconVersion: String?
    public init(id: String, name: String, iconVersion: String? = nil) { self.id = id; self.name = name; self.iconVersion = iconVersion }
}
public struct ShortcutEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct Capabilities: Codable, Equatable, Sendable {
    public var assistantReady: Bool?
    public var features: [String]?
    public var sequenceVersion: Int?
    public var frontmostBundleID: String?
    public var playback: [PlaybackSnapshot]?
    public var brightness: Bool?
    public var agents: [AgentSnapshot]?
    public var agentSources: [AgentSnapshot]?
    public var mediaKeys: Bool?
    public var controlsVersion: Int?
    public var keyboard: Bool
    public var music: Bool
    public var volume: Bool
    public var mute: Bool
    public var shortcuts: Bool
    public var notes: [String]
    public init(keyboard: Bool = false, music: Bool = false, volume: Bool = false, mute: Bool = false, shortcuts: Bool = true, notes: [String] = []) {
        self.keyboard = keyboard; self.music = music; self.volume = volume; self.mute = mute; self.shortcuts = shortcuts; self.notes = notes
    }
}
public enum ConnectionState: String, Codable, Sendable {
    case offline, searching, connecting, awaitingApproval, connected, permissionDenied, paused
    public var label: String {
        switch self {
        case .offline: "Offline"; case .searching: "Looking for your Mac"; case .connecting: "Connecting securely"
        case .awaitingApproval: "Approve on your Mac"; case .connected: "Connected"; case .permissionDenied: "Local network access needed"; case .paused: "Mac is paused"
        }
    }
    public var permitsActions: Bool { self == .connected }
}

public struct TileCountdown: Codable, Equatable, Sendable {
    public let duration: Int
    public private(set) var remaining: TimeInterval
    public private(set) var deadline: Date?
    public private(set) var finished = false
    public init(seconds: Int) { duration = seconds; remaining = Double(seconds) }
    private enum CodingKeys: String, CodingKey { case duration, remaining, deadline, finished }
    public init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        duration = try value.decode(Int.self, forKey: .duration)
        remaining = try value.decode(TimeInterval.self, forKey: .remaining)
        deadline = try value.decodeIfPresent(Date.self, forKey: .deadline)
        finished = try value.decode(Bool.self, forKey: .finished)
        guard (1...3600).contains(duration), remaining.isFinite, (0...Double(duration)).contains(remaining),
              deadline?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw QuickTileError.invalid("This saved timer is invalid.")
        }
    }
    public mutating func update(at now: Date) {
        guard let deadline else { return }
        remaining = min(Double(duration), max(0, deadline.timeIntervalSince(now)))
        if remaining == 0 { self.deadline = nil; finished = true }
    }
    public mutating func toggle(at now: Date) {
        update(at: now)
        if finished { reset(); return }
        if deadline != nil { deadline = nil }
        else { deadline = now.addingTimeInterval(remaining) }
    }
    public mutating func reset() { remaining = Double(duration); deadline = nil; finished = false }
}
