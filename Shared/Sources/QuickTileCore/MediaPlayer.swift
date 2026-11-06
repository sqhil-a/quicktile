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

extension PlaybackState {
    public var controlSymbol: String { switch self { case .playing: "pause.fill"; case .paused: "play.fill"; case .unknown: "playpause.fill" } }
}
public enum MediaRouting {
    public static func player(running: Set<MediaPlayer>, states: [MediaPlayer: PlaybackState], lastControlled: MediaPlayer?, frontmost: String?, browserFrontmost: Bool) -> MediaPlayer? {
        let playing = running.filter { states[$0] == .playing }
        if let front = playing.first(where: { $0.rawValue == frontmost }) { return front }
        if let lastControlled, playing.contains(lastControlled) { return lastControlled }
        if playing.count == 1 { return playing.first }
        // A sole running Spotify with ungranted observation needs its first explicit
        // control/Automation request, rather than a media key that can launch Music.
        if playing.isEmpty, running == [.spotify], states[.spotify] == .unknown { return .spotify }
        if !playing.isEmpty || browserFrontmost { return nil }
        if let lastControlled, running.contains(lastControlled) { return lastControlled }
        if running.count == 1 { return running.first }
        return running.first(where: { $0.rawValue == frontmost })
    }
}
