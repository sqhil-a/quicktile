import Foundation
import Network
import QuickTileCore

/// Runs in the containing app, including for StandBy. Pairing keys never enter the app group or extension.
@MainActor final class WidgetActionRunner {
    static let shared = WidgetActionRunner()
    private var busy = false
    func run(tileID: String, adjustment: Int) async throws {
        guard [-5, 0, 5].contains(adjustment) else { throw WidgetActionError.unavailable("Choose a five-percent control step.") }
        guard WidgetStore.enabled else { throw WidgetActionError.unavailable("Enable widgets in QuickTile Settings.") }
        guard !busy else { throw WidgetActionError.unavailable("Wait for the current action.") }
        let snapshot = WidgetStore.load()
        let virtual: Tile? = switch tileID {
        case "control.volume": Tile(name: "Volume", symbol: "speaker.wave.2.fill", action: .dial(.volume))
        case "control.brightness": Tile(name: "Brightness", symbol: "sun.max.fill", action: .dial(.brightness))
        case "control.play": Tile(name: "Playback", symbol: "playpause.fill", action: .media(.playPause))
        case "control.next": Tile(name: "Next track", symbol: "forward.fill", action: .media(.next))
        default: nil
        }
        guard let tile = WidgetStore.tile(tileID) ?? virtual, !WidgetStore.needsApp(tile) else { throw WidgetActionError.unavailable("Open this tile in QuickTile.") }
        try tile.action.validate()
        guard let macID = snapshot.macID,
              let credential = try KeychainStore(service: "sahil.QuickTile.credentials").read([Credential].self, account: "macs", allowAuthenticationUI: false)?.first(where: { $0.macID == macID }) else {
            throw WidgetActionError.unavailable("Unlock your iPhone and pair a Mac in QuickTile.")
        }
        busy = true; defer { busy = false }
        let endpoint = NWEndpoint.service(name: credential.id.uuidString, type: Limits.service, domain: "local.", interface: nil)
        let connection = NWConnection(to: endpoint, using: try SecureTransport.parameters(key: credential.key, identity: credential.id))
        var observedPlayback: [PlaybackSnapshot]?
        let result = try await WidgetCommandSession(connection: connection, macID: macID).run(tile: tile, adjustment: adjustment, playbackChanged: { observedPlayback = $0 }) {
            let current = WidgetStore.load()
            return WidgetStore.enabled && current.macID == macID && (virtual != nil || WidgetStore.tile(tileID) == tile)
        }
        WidgetStore.feedback(result, playback: observedPlayback)
    }
}
