import Foundation
import Network

/// One bounded authenticated widget transaction. It never retries or queues a command.
@MainActor public final class WidgetCommandSession {
    private let connection: NWConnection
    private let macID: UUID
    private var used = false
    private var channel: WireChannel?
    private var completion: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var session: Welcome?
    private var commandID = UUID()
    private var sentAdjustment = false
    public init(connection: NWConnection, macID: UUID) { self.connection = connection; self.macID = macID }
    public func run(tile: Tile, adjustment: Int = 0, playbackChanged: @escaping ([PlaybackSnapshot]) -> Void = { _ in }, authorized: @escaping () -> Bool = { true }) async throws -> String {
        try Task.checkCancellation()
        guard authorized() else { throw QuickTileError.failed("Widget access changed. Open QuickTile to refresh controls.") }
        guard !used, [-5, 0, 5].contains(adjustment), !WidgetControlPolicy.requiresApp(tile.action) else { throw QuickTileError.invalid("Open this action in QuickTile.") }
        try tile.action.validate(); used = true
        commandID = UUID(); sentAdjustment = false; session = nil
        let wire = WireChannel(connection)
        channel = wire
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                completion = continuation
                wire.onReady = { wire.send(Envelope(payload: .hello(.init(name: "QuickTile widget", features: ["structured-results.v1", "display-selection.v1", "media-player-adapters.v1", "playback-state.v1"])))) }
                wire.onMessage = { [weak self] message in
                    guard let self else { return }
                    switch message.payload {
                    case .welcome(let welcome):
                        guard welcome.macID == macID && self.session == nil else { self.finish(.failure(QuickTileError.failed("Mac identity changed. Open QuickTile."))); return }
                        guard authorized() else { self.finish(.failure(QuickTileError.failed("Widget access changed. Open QuickTile to refresh controls."))); return }
                        playbackChanged(welcome.capabilities.playback ?? [])
                        self.session = welcome
                        if case .dial(let kind) = tile.action {
                            if kind == .volume && adjustment == 0 {
                                wire.send(Envelope(id: self.commandID, payload: .command(.init(sessionID: welcome.sessionID, createdAt: welcome.serverTime, action: .volume(.mute)))))
                            } else { wire.send(Envelope(payload: .controlsRequest)) }
                        }
                        else {
                            wire.send(Envelope(id: self.commandID, payload: .command(.init(sessionID: welcome.sessionID, createdAt: welcome.serverTime, action: tile.action, targetBundleID: tile.targetBundleID, configuredShortcut: tile.configuredShortcut))))
                        }
                    case .capabilities(let capabilities):
                        playbackChanged(capabilities.playback ?? [])
                    case .controls(let controls):
                        guard case .dial(let kind) = tile.action, let welcome = self.session else { return }
                        if self.sentAdjustment {
                            guard message.id == self.commandID else { return }
                            self.finish(.success(kind == .volume ? "Volume updated" : "Brightness updated")); return
                        }
                        guard authorized() else { self.finish(.failure(QuickTileError.failed("Widget access changed. Open QuickTile to refresh controls."))); return }
                        let current = kind == .volume ? controls.volume : controls.brightness
                        guard let current, current.isFinite, kind != .brightness || controls.displayID != nil else { self.finish(.failure(QuickTileError.failed("This Mac output does not support that control."))); return }
                        self.sentAdjustment = true
                        guard let value = try? WidgetControlPolicy.adjustedLevel(current: current, step: adjustment) else { self.finish(.failure(QuickTileError.failed("The Mac returned an invalid control level."))); return }
                        wire.send(Envelope(id: self.commandID, payload: .adjustControl(.init(sessionID: welcome.sessionID, createdAt: Date().addingTimeInterval(welcome.serverTime.timeIntervalSinceNow), kind: kind, value: value, displayID: kind == .brightness ? controls.displayID : nil))))
                    case .result(let result):
                        guard message.id == self.commandID else { return }
                        if result.status == .failed { self.finish(.failure(QuickTileError.failed(result.message))) }
                        else if result.status == .completed { self.finish(.success(result.message)) }
                    default: break
                    }
                }
                wire.onClose = { [weak self] reason in self?.finish(.failure(QuickTileError.failed(reason))) }
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(QuickTileError.failed("Mac unavailable, or action not confirmed. Nothing will retry. Open QuickTile to reconnect.")))
                }
                wire.start()
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }
    private func finish(_ result: Result<String, Error>) {
        guard let continuation = completion else { return }; completion = nil
        timeout?.cancel(); timeout = nil
        let old = channel; channel = nil; old?.onClose = nil; old?.onReady = nil; old?.onMessage = nil; old?.close()
        continuation.resume(with: result)
    }
}
