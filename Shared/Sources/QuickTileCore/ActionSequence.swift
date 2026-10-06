import Foundation

/// A bounded workflow. Steps are data, never interpreted as shell commands.
public struct ActionSequence: Codable, Equatable, Sendable {
    public var name: String
    public var steps: [SequenceStep]
    public static let maximumSteps = 12
    public static let maximumDuration: TimeInterval = 300
    public init(name: String = "Sequence", steps: [SequenceStep] = []) { self.name = name; self.steps = steps }
    public func validate() throws {
        try Validation.name(name)
        guard (1...Self.maximumSteps).contains(steps.count) else { throw QuickTileError.invalid("Add between 1 and 12 steps.") }
        for step in steps { try step.validate() }
        guard steps.reduce(0, { $0 + $1.waitDuration }) <= Self.maximumDuration else { throw QuickTileError.invalid("A sequence must finish within five minutes.") }
    }
}
public enum SequenceStep: Codable, Equatable, Sendable {
    case launchApp(bundleID: String)
    case keyboard(KeyboardShortcut)
    case website(url: String)
    case shortcut(identifier: String)
    case wait(seconds: Double)
    public var action: DeckAction? {
        switch self {
        case .launchApp(let id): .launchApp(bundleID: id)
        case .keyboard(let key): .keyboard(key)
        case .website(let url): .website(url: url)
        case .shortcut(let id): .shortcut(identifier: id)
        case .wait: nil
        }
    }
    public var waitDuration: TimeInterval { if case .wait(let seconds) = self { seconds } else { 0 } }
    public var title: String {
        switch self {
        case .launchApp: "Open app"
        case .keyboard(let shortcut): "Send \(shortcut.displayText)"
        case .website: "Open website"
        case .shortcut: "Run Apple Shortcut"
        case .wait(let seconds): "Wait \(seconds.formatted()) seconds"
        }
    }
    public func validate() throws {
        if case .wait(let seconds) = self {
            guard seconds.isFinite, seconds > 0, seconds <= 10 else { throw QuickTileError.invalid("Waits must be greater than zero and no longer than ten seconds.") }
        } else {
            if case .keyboard(let key) = self, key.targetBundleID == nil {
                throw QuickTileError.invalid("Choose a target app for every keyboard step.")
            }
            try action?.validate()
        }
    }
}
public struct SequenceProgress: Codable, Equatable, Sendable {
    public var stepIndex: Int
    public var stepCount: Int
    public var title: String
    public init(stepIndex: Int, stepCount: Int, title: String) { self.stepIndex = stepIndex; self.stepCount = stepCount; self.title = title }
}
public enum PlaybackState: String, Codable, Sendable { case playing, paused, unknown }
public struct PlaybackSnapshot: Codable, Equatable, Sendable {
    public var target: String
    public var state: PlaybackState
    public var playerBundleID: String?
    public init(target: String, state: PlaybackState, playerBundleID: String? = nil) { self.target = target; self.state = state; self.playerBundleID = playerBundleID }
}
