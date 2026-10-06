import Foundation

public enum PairingStage: String, Codable, Sendable {
    case scanning, connecting, awaitingApproval, approved, failed, expired, cancelled
    public var label: String {
        switch self {
        case .scanning: "Scan your Mac’s code"
        case .connecting: "Connecting to your Mac"
        case .awaitingApproval: "Approve this iPhone on your Mac"
        case .approved: "Pairing approved"
        case .failed: "Pairing failed"
        case .expired: "Pairing code expired"
        case .cancelled: "Pairing cancelled"
        }
    }
}

public struct PairingInvite: Codable, Equatable, Sendable {
    public var version = 1
    public var macID: UUID
    public var name: String
    public var identity: UUID
    public var key: Data
    public var expiresAt: Date
    public init(macID: UUID, name: String, identity: UUID = UUID(), key: Data, expiresAt: Date = Date().addingTimeInterval(120)) {
        self.macID = macID; self.name = name; self.identity = identity; self.key = key; self.expiresAt = expiresAt
    }
    public var serviceName: String { identity.uuidString }
    public func encoded() throws -> String { "quicktile://pair/" + (try JSONEncoder().encode(self)).base64EncodedString() }
    public static func decode(_ text: String, now: Date = Date()) throws -> Self {
        let prefix = "quicktile://pair/"
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix(prefix), normalized.utf8.count < 4096 else { throw QuickTileError.invalid("This is not a QuickTile pairing QR.") }
        var encoded = String(normalized.dropFirst(prefix.count))
        if let decoded = encoded.removingPercentEncoding { encoded = decoded }
        encoded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded.append("=") }
        guard let data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]) else { throw QuickTileError.invalid("This is not a QuickTile pairing QR.") }
        let invite = try JSONDecoder().decode(Self.self, from: data)
        guard invite.version == 1, invite.key.count == 32, invite.expiresAt > now,
              invite.expiresAt.timeIntervalSince(now) <= 180, !invite.name.isEmpty, invite.name.count <= 100 else { throw QuickTileError.invalid("This pairing QR is invalid or expired. Generate a new one on your Mac.") }
        return invite
    }
}
public struct Credential: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var macID: UUID
    public var name: String
    public var key: Data
    public var createdAt: Date
    public init(id: UUID = UUID(), macID: UUID, name: String, key: Data, createdAt: Date = Date()) {
        self.id = id; self.macID = macID; self.name = name; self.key = key; self.createdAt = createdAt
    }
}
public struct Hello: Codable, Sendable {
    public var name: String
    public var features: [String]?
    public init(name: String, features: [String]? = nil) { self.name = name; self.features = features }
}
public struct Welcome: Codable, Sendable {
    public var macID: UUID
    public var name: String
    public var sessionID: UUID
    public var serverTime: Date
    public var capabilities: Capabilities
    public init(macID: UUID, name: String, sessionID: UUID, capabilities: Capabilities) {
        self.macID = macID; self.name = name; self.sessionID = sessionID; self.serverTime = Date(); self.capabilities = capabilities
    }
}
public struct Command: Codable, Sendable {
    public var sessionID: UUID
    public var createdAt: Date
    public var action: DeckAction
    public var targetBundleID: String?
    public var configuredShortcut: KeyboardShortcut?
    public init(sessionID: UUID, createdAt: Date = Date(), action: DeckAction, targetBundleID: String? = nil, configuredShortcut: KeyboardShortcut? = nil) { self.sessionID = sessionID; self.createdAt = createdAt; self.action = action; self.targetBundleID = targetBundleID; self.configuredShortcut = configuredShortcut }
}
public enum ResultStatus: String, Codable, Sendable { case accepted, completed, failed }
public enum ActionOutcome: String, Codable, Sendable { case opened, commandSent, shortcutCompleted, stateChanged, sequenceCompleted, cancelled }
public struct ActionResult: Codable, Sendable {
    public var status: ResultStatus
    public var message: String
    public var outcome: ActionOutcome?
    public var sequenceProgress: SequenceProgress?
    public init(_ status: ResultStatus, _ message: String, outcome: ActionOutcome? = nil, sequenceProgress: SequenceProgress? = nil) { self.status = status; self.message = message; self.outcome = outcome; self.sequenceProgress = sequenceProgress }
}
public struct CatalogChunk: Codable, Sendable {
    public var generation: UUID
    public var index: Int
    public var apps: [AppEntry]
    public var shortcuts: [ShortcutEntry]
    public var isLast: Bool
    public var note: String?
    public init(generation: UUID, index: Int = 0, apps: [AppEntry], shortcuts: [ShortcutEntry] = [], isLast: Bool, note: String? = nil) {
        self.generation = generation; self.index = index; self.apps = apps; self.shortcuts = shortcuts; self.isLast = isLast; self.note = note
    }
}
public struct IconAsset: Codable, Sendable {
    public var version: String
    public var png: Data
    public init(version: String, png: Data) { self.version = version; self.png = png }
}
public struct AssistantRequest: Codable, Sendable {
    public var sessionID: UUID
    public var createdAt: Date
    public var text: String
    public init(sessionID: UUID, createdAt: Date, text: String) { self.sessionID = sessionID; self.createdAt = createdAt; self.text = text }
    public func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2000, !text.unicodeScalars.contains(where: { $0.value == 0 }) else { throw QuickTileError.invalid("Say a short command and try again.") }
    }
}
public enum Payload: Codable, Sendable {
    case agentRequestsRequest(AgentProvider, AgentSource)
    case agentRequests([AgentInputRequest])
    case agentReply(AgentInputReply)
    case assistantRequest(AssistantRequest)
    case cancelCommand(UUID)
    case selectedDisplay(UInt32)
    case controlsRequest, controls(ControlState), adjustControl(ControlAdjustment)
    case hello(Hello), pairRequest(Hello), paired(Credential), welcome(Welcome)
    case catalogRequest, catalog(CatalogChunk), iconRequest(version: String), icon(IconAsset)
    case command(Command), result(ActionResult), ping, pong, capabilities(Capabilities), closed(String)
}
public enum ControlKind: String, Codable, CaseIterable, Sendable { case volume, brightness }
public struct ControlState: Codable, Equatable, Sendable {
    public var volume: Double?
    public var brightness: Double?
    public var displayID: UInt32?
    public var displayName: String?
    public var muted: Bool?
    public var outputDeviceID: UInt32?
    public var outputDeviceName: String?
    public var restoreLevel: Double?
    public var displays: [DisplayControlState]?
    public init(volume: Double?, brightness: Double?, displayID: UInt32?, displayName: String?, muted: Bool? = nil, outputDeviceID: UInt32? = nil, outputDeviceName: String? = nil, restoreLevel: Double? = nil, displays: [DisplayControlState]? = nil) {
        self.volume = volume; self.brightness = brightness; self.displayID = displayID; self.displayName = displayName
        self.muted = muted; self.outputDeviceID = outputDeviceID; self.outputDeviceName = outputDeviceName; self.restoreLevel = restoreLevel; self.displays = displays
    }
}
public struct DisplayControlState: Codable, Equatable, Identifiable, Sendable {
    public var id: UInt32
    public var name: String
    public var brightness: Double?
    public var builtIn: Bool
    public init(id: UInt32, name: String, brightness: Double?, builtIn: Bool) { self.id = id; self.name = name; self.brightness = brightness; self.builtIn = builtIn }
}
public struct ControlAdjustment: Codable, Sendable {
    public var sessionID: UUID
    public var createdAt: Date
    public var kind: ControlKind
    public var value: Double
    public var displayID: UInt32?
    public init(sessionID: UUID, createdAt: Date, kind: ControlKind, value: Double, displayID: UInt32?) {
        self.sessionID = sessionID; self.createdAt = createdAt; self.kind = kind; self.value = value; self.displayID = displayID
    }
    public func validate() throws {
        guard value.isFinite, (0...1).contains(value), kind != .brightness || displayID != nil else {
            throw QuickTileError.invalid("Choose a supported control and a level between 0 and 100%.")
        }
    }
}
public struct Envelope: Codable, Sendable {
    public var version: Int
    public var id: UUID
    public var payload: Payload
    public init(id: UUID = UUID(), payload: Payload, version: Int = Limits.protocolVersion) { self.version = version; self.id = id; self.payload = payload }
    public func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Limits.frameBytes else { throw QuickTileError.invalid("Message is too large.") }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= Limits.frameBytes else { throw QuickTileError.invalid("Invalid message size.") }
        let message = try JSONDecoder().decode(Self.self, from: data)
        guard message.version == Limits.protocolVersion else { throw QuickTileError.unsupported("Update QuickTile on both devices to use the same protocol version.") }
        if case .icon(let asset) = message.payload {
            guard asset.png.count <= Limits.assetBytes, asset.version.count == 64 else { throw QuickTileError.invalid("Invalid icon asset.") }
        }
        if case .catalog(let chunk) = message.payload {
            guard chunk.apps.count <= 100, chunk.shortcuts.count <= 100 else { throw QuickTileError.invalid("Catalog chunk is too large.") }
        }
        return message
    }
}
/// Single-session gate. Every reconnect has a new session, and IDs are never evicted while usable.
public struct CommandGate {
    public let sessionID: UUID
    public var authorized: Bool
    private var received: [UUID: Date] = [:]
    public init(sessionID: UUID = UUID(), authorized: Bool = false) { self.sessionID = sessionID; self.authorized = authorized }
    public mutating func revoke() { authorized = false }
    public mutating func admit(id: UUID, command: Command, now: Date = Date()) throws {
        guard authorized, command.sessionID == sessionID else { throw QuickTileError.unauthorized }
        let age = now.timeIntervalSince(command.createdAt)
        guard age >= -2, age <= Limits.commandLifetime else { throw QuickTileError.expired }
        received = received.filter { now.timeIntervalSince($0.value) < 60 }
        guard received[id] == nil else { throw QuickTileError.duplicate }
        guard received.count < 512 else { throw QuickTileError.failed("Too many requests. Wait a minute before trying again.") }
        try command.action.validate()
        if let target = command.targetBundleID { try Validation.identifier(target) }
        try command.configuredShortcut?.validate()
        received[id] = now
    }
}
