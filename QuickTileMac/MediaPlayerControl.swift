import AppKit
import CoreServices
import QuickTileCore

/// Public AppleScript dictionaries supplied by Spotify and Music. No private now-playing APIs.
@MainActor final class MediaPlayerControl {
    private var selected = Set<MediaPlayer>()
    private var states: [MediaPlayer: PlaybackState] = [:]
    private var observing: Task<Void, Never>?
    var snapshots: [PlaybackSnapshot] {
        MediaPlayer.allCases.filter { selected.contains($0) }.map { .init(target: $0.rawValue, state: states[$0] ?? .unknown, playerBundleID: $0.rawValue) }
    }
    func setPlayback(_ state: PlaybackState, player: MediaPlayer) async throws {
        guard state != .unknown, NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) != nil else { throw QuickTileError.unsupported("Choose an installed player.") }
        let verb = state == .playing ? "play" : "pause"
        let output = try await ProcessJob().run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application id \"\(player.rawValue)\" to \(verb)"], timeout: 20)
        guard output.status == 0 else { throw QuickTileError.failed("Allow QuickTile to control \(player.title) in Automation settings.") }
        selected.insert(player); await refresh(player); beginObserving()
    }
    func execute(_ command: MediaCommand, player: MediaPlayer) async throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) != nil else { throw QuickTileError.failed("\(player.title) is not installed.") }
        let verb = switch command { case .playPause: "playpause"; case .next: "next track"; case .previous: "previous track" }
        // Both values are fixed enums, never user-supplied AppleScript.
        let output = try await ProcessJob().run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application id \"\(player.rawValue)\" to \(verb)"], timeout: 20)
        guard output.status == 0 else { throw QuickTileError.failed("Allow QuickTile to control \(player.title) in Mac System Settings → Privacy & Security → Automation.") }
        selected.insert(player)
        await refresh(player)
        beginObserving()
    }
    private func beginObserving() {
        if observing == nil {
            observing = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    for player in self.selected { await self.refresh(player) }
                }
            }
        }
    }
    private func refresh(_ player: MediaPlayer) async {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).isEmpty else { states[player] = .unknown; return }
        // A background read must never summon a new Automation permission prompt.
        let permitted = await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: player.rawValue)
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
        }.value
        guard permitted, !Task.isCancelled else { states[player] = .unknown; return }
        let output = try? await ProcessJob().run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application id \"\(player.rawValue)\" to get player state as string"], timeout: 2)
        states[player] = output?.status == 0 ? MediaPlayer.state(from: output?.text ?? "") : .unknown
    }
}
