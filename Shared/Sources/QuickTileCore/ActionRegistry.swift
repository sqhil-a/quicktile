import Foundation

public enum ActionAvailabilityKind: String, Codable, Sendable { case ready, needsSetup, appMissing, unsupportedHardware, disconnected, updateRequired }
public struct ActionAvailability: Codable, Equatable, Sendable {
    public let kind: ActionAvailabilityKind
    public let message: String?
    public var isReady: Bool { kind == .ready }
    public init(_ kind: ActionAvailabilityKind, _ message: String? = nil) { self.kind = kind; self.message = message }
}
public enum ExecutionSemantics: String, Codable, Sendable { case local, commandSent, verifiedStateChange, longRunning }
public enum MappingVerification: String, Codable, Sendable { case needsRuntimeVerification, userConfigured }
public struct ActionDefinition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: ActionCategory
    public let symbol: String
    public let action: DeckAction
    public let appProfileID: String?
    public let requiresAccessibility: Bool
    public let semantics: ExecutionSemantics
    public let context: String?
    public let mappingVersion: Int
    public let verification: MappingVerification?
    public let documentationURL: String?
}
public enum ActionRegistry {
    public static let definitions: [ActionDefinition] = ActionLibrary.actions.map { item in
        let profile = item.preset.flatMap { AppProfiles.profile(bundleID: $0.bundleID) }
        return ActionDefinition(id: item.id, title: item.title, category: item.category, symbol: item.symbol, action: item.action,
                                appProfileID: profile?.id, requiresAccessibility: needsAccessibility(item.action),
                                semantics: semantics(item.action), context: context(item.action), mappingVersion: 1,
                                verification: item.preset == nil ? nil : .needsRuntimeVerification, documentationURL: profile?.shortcutDocumentation)
    }
    public static func definition(id: String) -> ActionDefinition? { definitions.first { $0.id == id } }
    public static func definition(for action: DeckAction) -> ActionDefinition? { definitions.first { $0.action == action } }
    public static func availability(action: DeckAction, capabilities: Capabilities, apps: [AppEntry], connected: Bool, preferredBundleID: String? = nil) -> ActionAvailability {
        if case .timer = action { return .init(.ready) }
        guard connected else { return .init(.disconnected, "Connect to your Mac.") }
        if case .media = action, let target = preferredBundleID {
            guard let player = MediaPlayer(rawValue: target) else { return .init(.needsSetup, "Choose a supported media player.") }
            guard capabilities.features?.contains("media-player-adapters.v1") == true else { return .init(.updateRequired, "Update the Mac companion to control a specific player.") }
            return apps.contains(where: { $0.id == target }) ? .init(.ready) : .init(.appMissing, "Install \(player.title) or choose Mac playback.")
        }
        if needsAccessibility(action), !capabilities.keyboard { return .init(.needsSetup, "Allow Accessibility for QuickTile on your Mac.") }
        switch action {
        case .assistant:
            guard capabilities.features?.contains("voice-assistant.v1") == true else { return .init(.updateRequired, "Update the Mac companion to use the assistant.") }
            return capabilities.assistantReady == true ? .init(.ready) : .init(.needsSetup, "Add your Groq API key in QuickTile’s Mac Settings.")
        case .dial(.volume):
            return capabilities.volume ? .init(.ready) : .init(.unsupportedHardware, "This audio output needs its hardware volume control.")
        case .dial(.brightness):
            return capabilities.brightness == true ? .init(.ready) : .init(.unsupportedHardware, "No supported brightness display is available.")
        case .volume(.mute):
            return capabilities.mute ? .init(.ready) : .init(.unsupportedHardware, "This audio output needs its hardware mute control.")
        case .volume:
            return capabilities.volume ? .init(.ready) : .init(.unsupportedHardware, "This audio output needs its hardware volume control.")
        case .media, .music:
            return capabilities.mediaKeys == true ? .init(.ready) : .init(.needsSetup, "Allow Accessibility for media keys on your Mac.")
        case .sequence(let sequence):
            guard capabilities.sequenceVersion == 1 else { return .init(.updateRequired, "Update the Mac companion to run action sequences.") }
            if (try? sequence.validate()) == nil { return .init(.needsSetup, "Configure this sequence.") }
            for step in sequence.steps {
                if let action = step.action {
                    let availability = availability(action: action, capabilities: capabilities, apps: apps, connected: connected)
                    if !availability.isReady { return availability }
                }
            }
        case .preset(let id):
            guard let preset = ActionLibrary.preset(id: id) else { return .init(.updateRequired, "This action needs a newer QuickTile.") }
            guard AppProfiles.resolve(bundleID: preset.bundleID, apps: apps, preferredBundleID: preferredBundleID) != nil else { return .init(.appMissing, "Install \(preset.appName) or select an installed version.") }
        case .launchApp(let id):
            guard !id.isEmpty else { return .init(.needsSetup, "Choose an application.") }
            guard AppProfiles.resolve(bundleID: id, apps: apps, preferredBundleID: preferredBundleID) != nil else { return .init(.appMissing, "This application is not in the Mac catalog.") }
        case .keyboard(let key):
            if let id = key.targetBundleID, AppProfiles.resolve(bundleID: id, apps: apps, preferredBundleID: preferredBundleID) == nil { return .init(.appMissing, "Choose an installed target application.") }
        case .shortcut(let id):
            if UUID(uuidString: id) == nil { return .init(.needsSetup, "Choose an Apple Shortcut.") }
            if !capabilities.shortcuts { return .init(.needsSetup, "Open Shortcuts on your Mac and refresh.") }
        case .website(let url):
            if (try? Validation.website(url)) == nil { return .init(.needsSetup, "Enter a website URL.") }
        case .agent(let provider):
            if let snapshot = capabilities.agents?.first(where: { $0.provider == provider }), snapshot.phase == .unavailable {
                return .init(.needsSetup, "Set up agent tracking in the Mac companion.")
            }
        default: break
        }
        return .init(.ready)
    }
    public static func needsAccessibility(_ action: DeckAction) -> Bool {
        switch action {
        case .keyboard, .preset, .media, .music: true
        case .system(let command): command != .sleepDisplay && command != .darkMode
        case .sequence(let sequence): sequence.steps.contains { $0.action.map(needsAccessibility) == true }
        default: false
        }
    }
    public static func semantics(_ action: DeckAction) -> ExecutionSemantics {
        switch action {
        case .timer: .local
        case .keyboard, .preset, .media, .music: .commandSent
        case .assistant, .sequence, .shortcut: .longRunning
        case .system(.lock), .system(.showDesktop), .system(.screenshot), .system(.screenshotArea): .commandSent
        default: .verifiedStateChange
        }
    }
    private static func context(_ action: DeckAction) -> String? {
        switch action {
        case .preset(let id):
            guard let preset = ActionLibrary.preset(id: id) else { return nil }
            return preset.category == .video ? "Open a project and focus the timeline or relevant panel. Test with the app’s current keymap." : "Open a document and focus the relevant panel. Test with the app’s current keymap."
        case .keyboard: return "Keys use physical ANSI positions. The focused panel and keymap determine the effect."
        default: return nil
        }
    }
}
