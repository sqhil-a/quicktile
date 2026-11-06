import AppKit
import CoreServices
import QuickTileCore

/// Never await the synchronous TCC probe on an action's critical path. Some OS versions
/// can stall this call; at most one background probe per player is allowed process-wide.
@MainActor private enum PlayerAutomationPermissions {
    static var cache: [MediaPlayer: (allowed: Bool, date: Date)] = [:]
    static var pending = Set<MediaPlayer>()
    static func recordAllowed(_ player: MediaPlayer) { cache[player] = (true, Date()) }
    static func current(_ player: MediaPlayer) -> Bool? {
        if let known = cache[player], Date().timeIntervalSince(known.date) < 1 { return known.allowed }
        guard pending.insert(player).inserted else { return nil }
        let started = Date()
        Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: player.rawValue)
            let allowed = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
            await MainActor.run {
                if (cache[player]?.date ?? .distantPast) <= started { cache[player] = (allowed, Date()) }
                pending.remove(player)
            }
        }
        return nil
    }
}

/// Supported player dictionaries; never starts a player merely to inspect or control it.
@MainActor final class MediaPlayerControl {
    private var selected = Set<MediaPlayer>()
    private var states: [MediaPlayer: PlaybackState] = [:]
    private var observing: Task<Void, Never>?
    private var lastControlled: MediaPlayer?
    private var spotifyNotification: NSObjectProtocol?
    private var notificationRefresh: Task<Void, Never>?
    private var controlling = Set<MediaPlayer>()
    private var reads: [MediaPlayer: UUID] = [:]
    private var observedAt: [MediaPlayer: Date] = [:]
    var onChange: (() -> Void)?
    init() {
        // This notification only triggers a verified state read; track metadata is ignored.
        spotifyNotification = DistributedNotificationCenter.default().addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.observing != nil else { return }
                self.notificationRefresh?.cancel()
                self.notificationRefresh = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled else { return }
                    await self?.refresh(.spotify)
                }
            }
        }
    }
    static let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.Browser", "company.thebrowser.Browser", "com.operasoftware.Opera"]
    private var running: Set<MediaPlayer> { Set(MediaPlayer.allCases.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.rawValue).isEmpty }) }
    private var automaticPlayer: MediaPlayer? {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return MediaRouting.player(running: running, states: states, lastControlled: lastControlled, frontmost: front, browserFrontmost: front.map(Self.browsers.contains) ?? false)
    }
    var hasRunningPlayer: Bool { !running.isEmpty }
    var canUseNativePlayer: Bool { automaticPlayer != nil }
    var systemSnapshot: PlaybackSnapshot {
        let player = automaticPlayer
        return .init(target: "system", state: player.flatMap { states[$0] } ?? .unknown, playerBundleID: player?.rawValue)
    }
    var snapshots: [PlaybackSnapshot] {
        MediaPlayer.allCases.filter { selected.contains($0) || running.contains($0) }.map { .init(target: $0.rawValue, state: states[$0] ?? .unknown, playerBundleID: $0.rawValue) }
    }
    func setObserving(_ enabled: Bool) {
        if !enabled { observing?.cancel(); observing = nil; notificationRefresh?.cancel(); notificationRefresh = nil; return }
        guard observing == nil else { return }
        observing = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRunning()
                try? await Task.sleep(for: .seconds(1))
                guard self != nil else { return }
            }
        }
    }
    func executeAutomatic(_ command: MediaCommand) async throws -> Bool {
        await refreshRunning()
        guard let player = automaticPlayer else { return false }
        try await execute(command, player: player)
        return true
    }
    func setPlayback(_ state: PlaybackState, player: MediaPlayer) async throws {
        guard state != .unknown else { throw QuickTileError.invalid("Choose play or pause.") }
        try await send(state == .playing ? "play" : "pause", player: player)
    }
    func execute(_ command: MediaCommand, player: MediaPlayer) async throws {
        let verb = switch command { case .playPause: "playpause"; case .next: "next track"; case .previous: "previous track" }
        try await send(verb, player: player)
    }
    private func send(_ verb: String, player: MediaPlayer) async throws {
        guard running.contains(player) else { throw QuickTileError.failed("Start playback in \(player.title) on your Mac first.") }
        guard controlling.insert(player).inserted else { throw QuickTileError.failed("Wait for the playback control to finish.") }
        defer { controlling.remove(player) }
        reads[player] = UUID()
        let script = """
        if application id "\(player.rawValue)" is running then
            tell application id "\(player.rawValue)" to \(verb)
            tell application id "\(player.rawValue)" to get player state as string
        else
            error "Player is not running"
        end if
        """
        let output = try await ProcessJob().run(executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 20)
        guard output.status == 0 else { throw QuickTileError.failed("Allow QuickTile to control \(player.title) in Mac Settings → Privacy & Security → Automation.") }
        PlayerAutomationPermissions.recordAllowed(player)
        selected.insert(player); lastControlled = player
        let observed = MediaPlayer.state(from: output.text)
        if observed != .unknown { states[player] = observed; observedAt[player] = Date() }
        else { await refresh(player, afterCommand: true) }
        onChange?()
    }
    func refreshRunning() async {
        let previous = systemSnapshot
        for player in MediaPlayer.allCases { await refresh(player) }
        if previous != systemSnapshot { onChange?() }
    }
    private func refresh(_ player: MediaPlayer, afterCommand: Bool = false) async {
        guard !controlling.contains(player) || afterCommand else { return }
        let previous = states[player]
        defer { if previous != states[player] { onChange?() } }
        guard running.contains(player) else { states[player] = .unknown; return }
        guard let permitted = PlayerAutomationPermissions.current(player) else {
            if Date().timeIntervalSince(observedAt[player] ?? .distantPast) > 5 { states[player] = .unknown }
            return
        }
        guard permitted, !Task.isCancelled else { states[player] = .unknown; return }
        let readID = UUID(); reads[player] = readID
        let script = """
        if application id "\(player.rawValue)" is running then
            tell application id "\(player.rawValue)" to get player state as string
        else
            error "Player is not running"
        end if
        """
        let output = try? await ProcessJob().run(executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 2)
        guard reads[player] == readID else { return }
        let observed = output?.status == 0 ? MediaPlayer.state(from: output?.text ?? "") : .unknown
        if observed != .unknown { states[player] = observed; observedAt[player] = Date() }
        else if Date().timeIntervalSince(observedAt[player] ?? .distantPast) > 5 { states[player] = .unknown }
    }
    deinit {
        observing?.cancel(); notificationRefresh?.cancel()
        if let spotifyNotification { DistributedNotificationCenter.default().removeObserver(spotifyNotification) }
    }
}
