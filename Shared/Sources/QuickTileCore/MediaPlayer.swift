import Foundation

/// Explicit, supported player adapters. System media keys remain the default.
public enum MediaPlayer: String, Codable, CaseIterable, Sendable, Identifiable {
    case spotify = "com.spotify.client", music = "com.apple.Music"
    public var id: String { rawValue }
    public var title: String { self == .spotify ? "Spotify" : "Music" }
    public static func state(from value: String) -> PlaybackState {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "playing": .playing
        case "paused", "stopped": .paused
        default: .unknown
        }
    }
}

extension Tile {
    public var playbackTarget: String? {
        if case .media(.playPause) = action, let targetBundleID, MediaPlayer(rawValue: targetBundleID) != nil { return targetBundleID }
        return action.playbackTarget
    }
}
