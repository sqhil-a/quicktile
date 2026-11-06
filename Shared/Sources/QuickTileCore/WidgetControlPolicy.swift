import Foundation

/// Widgets execute short Mac commands; interactions needing UI or longer runtime hand off to the app.
public enum WidgetControlPolicy {
    public static func requiresApp(_ action: DeckAction) -> Bool {
        switch action { case .assistant, .timer, .agent, .sequence, .shortcut: true; default: false }
    }
    public static func adjustedLevel(current: Double, step: Int) throws -> Double {
        guard current.isFinite, (0...1).contains(current), [-5, 0, 5].contains(step) else {
            throw QuickTileError.invalid("Choose a supported control and a five-percent step.")
        }
        return min(1, max(0, current + Double(step) / 100))
    }
}
