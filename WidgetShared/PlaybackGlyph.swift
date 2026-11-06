import SwiftUI

/// Replace the glyph immediately, including inside an animated parent or widget update.
struct PlaybackGlyph: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .contentTransition(.identity)
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true
            }
    }
}
