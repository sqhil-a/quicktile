import XCTest
@preconcurrency import Network
@testable import QuickTileCore

final class WidgetTransportTests: XCTestCase {
    @MainActor func testDisabledWidgetCannotStartAConnectionOrSendAnAction() async throws {
        let connection = NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
        let session = WidgetCommandSession(connection: connection, macID: UUID())
        do {
            _ = try await session.run(tile: .init(name: "Safari", symbol: "safari", action: .launchApp(bundleID: "com.apple.Safari")), authorized: { false })
            XCTFail("Disabled widget must not execute")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Widget access changed"))
        }
        if case .setup = connection.state {} else { XCTFail("Connection must remain unstarted") }
    }
    @MainActor func testWidgetCommandUsesFreshSessionAndPreservesTargetAndKeys() async throws {
        let tile = Tile(name: "Build", symbol: "hammer", action: .keyboard(.init(key: "b", modifiers: [.command], targetBundleID: "com.apple.dt.Xcode")))
        let result = try await transaction(tile: tile)
        XCTAssertEqual(result.commands.count, 1)
        XCTAssertEqual(result.commands.first?.action, tile.action)
        XCTAssertEqual(result.message, "Sent Build")
    }
    @MainActor func testWidgetDialReadsCurrentLevelBeforeChangingIt() async throws {
        let tile = Tile(name: "Brightness", symbol: "sun.max", action: .dial(.brightness))
        let result = try await transaction(tile: tile, step: 5)
        XCTAssertEqual(result.adjustments.count, 1)
        XCTAssertEqual(result.adjustments.first?.value ?? -1, 0.55, accuracy: 0.0001)
        XCTAssertEqual(result.adjustments.first?.displayID, 88)
    }
    @MainActor func testWidgetRejectsWrongMacBeforeSendingAction() async throws {
        let result = try await transaction(tile: .init(name: "Play", symbol: "playpause", action: .media(.playPause)), wrongMac: true)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.adjustments.isEmpty)
        XCTAssertTrue(result.message.contains("identity"))
    }
    @MainActor func testDisablingWhileConnectingBlocksTheCommand() async throws {
        let result = try await transaction(tile: .init(name: "Play", symbol: "playpause", action: .media(.playPause)), revokeBeforeWelcome: true)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.message.contains("Widget access changed"))
    }
    @MainActor private func transaction(tile: Tile, step: Int = 0, wrongMac: Bool = false, revokeBeforeWelcome: Bool = false) async throws -> (commands: [Command], adjustments: [ControlAdjustment], message: String) {
        let identity = UUID(), macID = UUID(), sessionID = UUID(), key = try SecureRandom.key()
        let params = try SecureTransport.parameters(key: key, identity: identity)
        params.prohibitedInterfaceTypes = [] // Loopback is allowed only inside this fixture.
        var authorized = true
        let listener = try NWListener(using: params, on: .any)
        let ready = expectation(description: "Widget fixture listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        var channels: [WireChannel] = [], commands: [Command] = [], adjustments: [ControlAdjustment] = []
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let channel = WireChannel(connection); channels.append(channel)
                channel.onMessage = { envelope in
                    switch envelope.payload {
                    case .hello:
                        if revokeBeforeWelcome { authorized = false }
                        channel.send(Envelope(payload: .welcome(.init(macID: wrongMac ? UUID() : macID, name: "Fixture Mac", sessionID: sessionID, capabilities: .init()))))
                    case .command(let command):
                        XCTAssertEqual(command.sessionID, sessionID)
                        XCTAssertLessThan(abs(command.createdAt.timeIntervalSinceNow), 2)
                        commands.append(command)
                        channel.send(Envelope(id: envelope.id, payload: .result(.init(.accepted, ""))))
                        channel.send(Envelope(id: envelope.id, payload: .result(.init(.completed, "Sent Build", outcome: .commandSent))))
                    case .controlsRequest:
                        channel.send(Envelope(payload: .controls(.init(volume: 0.4, brightness: 0.5, displayID: 88, displayName: "Test display"))))
                    case .adjustControl(let adjustment):
                        XCTAssertEqual(adjustment.sessionID, sessionID); adjustments.append(adjustment)
                        channel.send(Envelope(id: envelope.id, payload: .controls(.init(volume: 0.4, brightness: adjustment.value, displayID: 88, displayName: "Test display"))))
                    default: break
                    }
                }
                channel.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)
        defer { channels.forEach { $0.close() }; listener.cancel() }
        let port = try XCTUnwrap(listener.port)
        let client = try SecureTransport.parameters(key: key, identity: identity); client.prohibitedInterfaceTypes = []
        let transaction = WidgetCommandSession(connection: NWConnection(host: "127.0.0.1", port: port, using: client), macID: macID)
        do {
            let message = try await transaction.run(tile: tile, adjustment: step, authorized: { authorized })
            if wrongMac { XCTFail("Wrong Mac must not execute") }
            return (commands, adjustments, message)
        } catch {
            guard wrongMac || revokeBeforeWelcome else { throw error }
            return (commands, adjustments, error.localizedDescription)
        }
    }
}
