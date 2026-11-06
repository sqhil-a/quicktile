import SwiftUI

/// A stable image with a short crossfade, without the replacement effect's travel/bounce.
struct PlaybackGlyph: View {
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Image(systemName: symbol)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: symbol)
    }
}
