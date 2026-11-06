import XCTest
@testable import QuickTileCore

final class MediaPlayerTests: XCTestCase {
    func testAutomaticPlaybackChoosesPlayingSpotifyInsteadOfClosedMusic() {
        XCTAssertEqual(MediaRouting.player(running: [.spotify], states: [.spotify: .playing], lastControlled: nil, frontmost: nil, browserFrontmost: false), .spotify)
        XCTAssertEqual(MediaRouting.player(running: [.spotify, .music], states: [.spotify: .playing, .music: .paused], lastControlled: .music, frontmost: nil, browserFrontmost: false), .spotify)
        XCTAssertEqual(MediaRouting.player(running: [.spotify], states: [.spotify: .paused], lastControlled: .spotify, frontmost: nil, browserFrontmost: false), .spotify)
        XCTAssertNil(MediaRouting.player(running: [], states: [.music: .playing], lastControlled: .music, frontmost: nil, browserFrontmost: false))
        XCTAssertNil(MediaRouting.player(running: [.music], states: [.music: .paused], lastControlled: nil, frontmost: "com.apple.Safari", browserFrontmost: true))
        XCTAssertEqual(MediaRouting.player(running: [.spotify], states: [.spotify: .unknown], lastControlled: nil, frontmost: "com.apple.Safari", browserFrontmost: true), .spotify)
        XCTAssertEqual(PlaybackState.playing.controlSymbol, "pause.fill")
        XCTAssertEqual(PlaybackState.paused.controlSymbol, "play.fill")
        XCTAssertEqual(PlaybackState.unknown.controlSymbol, "playpause.fill")
    }
    func testObservedStatesNeverGuess() {
        XCTAssertEqual(MediaPlayer.state(from: "playing\n"), .playing)
        XCTAssertEqual(MediaPlayer.state(from: "paused"), .paused)
        XCTAssertEqual(MediaPlayer.state(from: "stopped"), .paused)
        XCTAssertEqual(MediaPlayer.state(from: "unavailable"), .unknown)
        var tile = Tile(name: "Playback", symbol: "playpause.fill", action: .media(.playPause))
        XCTAssertEqual(tile.playbackTarget, "system")
        tile.targetBundleID = MediaPlayer.spotify.rawValue
        XCTAssertEqual(tile.playbackTarget, MediaPlayer.spotify.rawValue)
        tile.action = .media(.next)
        XCTAssertNil(tile.playbackTarget)
    }
    func testSpecificPlayerRequiresNegotiationAndItsApp() {
        var caps = Capabilities(keyboard: false, music: false, volume: false, mute: false)
        let target = MediaPlayer.spotify.rawValue
        XCTAssertEqual(ActionRegistry.availability(action: .media(.playPause), capabilities: caps, apps: [], connected: true, preferredBundleID: target).kind, .updateRequired)
        caps.features = ["media-player-adapters.v1"]
        XCTAssertEqual(ActionRegistry.availability(action: .media(.playPause), capabilities: caps, apps: [], connected: true, preferredBundleID: target).kind, .appMissing)
        let app = AppEntry(id: target, name: "Spotify", iconVersion: nil)
        XCTAssertEqual(ActionRegistry.availability(action: .media(.playPause), capabilities: caps, apps: [app], connected: true, preferredBundleID: target).kind, .ready)
        XCTAssertEqual(ActionRegistry.availability(action: .media(.playPause), capabilities: caps, apps: [app], connected: true).kind, .needsSetup)
    }
}
