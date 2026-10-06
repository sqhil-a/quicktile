import XCTest
import CryptoKit
@testable import QuickTileCore

final class ReleaseFoundationTests: XCTestCase {
    func testPackageCopiesPreserveGapsButReplaceIdentities() throws {
        let a = Tile(name: "A", symbol: "app", action: .timer(seconds: 60))
        let b = Tile(name: "B", symbol: "globe", action: .website(url: "https://example.com/private"))
        var board = DeckPage(name: "Work", tiles: [a, b], symbol: "hammer")
        board.tileOrder = [a.id, nil, b.id, nil, nil, nil, nil, nil]; board.automaticSwitch = true
        let package = try BoardPackage.decode(BoardPackage(boards: [board]).encoded())
        let copy = try XCTUnwrap(package.copies().first)
        XCTAssertNotEqual(copy.id, board.id)
        XCTAssertEqual(copy.slots.map { $0?.name }, board.slots.map { $0?.name })
        XCTAssertTrue(Set(copy.tiles.map(\.id)).isDisjoint(with: Set(board.tiles.map(\.id))))
        XCTAssertEqual(copy.automaticSwitch, false)
        let text = String(decoding: try package.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("credential")); XCTAssertFalse(text.contains("sessionID"))
    }
    func testPackageRejectsUnsafeAssetReferencesAndCorruption() throws {
        let asset = Data("icon".utf8)
        let hash = SHA256.hash(data: asset).map { String(format: "%02x", $0) }.joined()
        var board = DeckPage(); board.customIconReference = hash
        XCTAssertNoThrow(try BoardPackage(boards: [board], assets: [hash: asset]).validate())
        XCTAssertThrowsError(try BoardPackage(boards: [board]).validate())
        XCTAssertThrowsError(try BoardPackage(boards: [board], assets: [hash: Data("wrong".utf8)]).validate())
        board.customIconReference = "../../secret"
        XCTAssertThrowsError(try BoardPackage(boards: [board]).validate())
        XCTAssertThrowsError(try BoardPackage(boards: [board, board]).validate())
    }
    func testLayoutRecoversKnownGoodBackupWithoutOverwritingDamagedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LayoutStore(directory: directory), id = UUID()
        var layout = DeckLayout(macID: id)
        try store.save(layout)
        layout.pages[0].name = "Changed"; try store.save(layout)
        let primary = directory.appendingPathComponent(id.uuidString + ".json")
        try Data("damaged".utf8).write(to: primary)
        XCTAssertEqual(try store.load(macID: id).pages[0].name, "My board")
        XCTAssertEqual(try Data(contentsOf: primary), Data("damaged".utf8))
    }
    func testTimerDeadlineAndAcknowledgementSurvivePersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TimerPersistence(directory: directory), mac = UUID(), id = UUID()
        var timer = TileCountdown(seconds: 60)
        timer.toggle(at: Date().addingTimeInterval(-65))
        try await store.save([id: timer], macID: mac)
        let restored = try await store.load(macID: mac)
        XCTAssertEqual(restored[id]?.finished, true)
        var acknowledged = try XCTUnwrap(restored[id]); acknowledged.toggle(at: Date())
        try await store.save([id: acknowledged], macID: mac)
        let final = try await store.load(macID: mac)
        XCTAssertEqual(final[id]?.finished, false); XCTAssertNil(final[id]?.deadline)
        XCTAssertEqual(final[id]?.remaining, 60)
    }
    func testAgentWaitingRequiresMatchingResolutionAndOldTurnCannotRevive() {
        let now = Date()
        func event(_ lifecycle: AgentLifecycle, _ phase: AgentPhase, offset: Double, turn: String = "one", request: String? = nil) -> AgentEvent {
            .init(provider: .codex, session: "local", phase: phase, updatedAt: now.addingTimeInterval(offset), lifecycle: lifecycle, evidence: .hooks, turnID: turn, waitingRequestID: request)
        }
        var state = AgentSessionState(event: event(.turnStarted, .running, offset: 0))
        state.apply(event(.waiting, .waiting, offset: 1, request: "question"))
        state.apply(event(.inputResolved, .running, offset: 2, request: "other"))
        XCTAssertEqual(state.event.phase, .waiting)
        state.apply(event(.activity, .running, offset: 3)); XCTAssertEqual(state.event.phase, .waiting)
        state.apply(event(.inputResolved, .running, offset: 3.1)); XCTAssertEqual(state.event.phase, .waiting)
        state.apply(event(.waiting, .waiting, offset: 3.2)); XCTAssertEqual(state.event.waitingRequestID, "question")
        state.apply(event(.inputResolved, .running, offset: 4, request: "question")); XCTAssertEqual(state.event.phase, .running)
        state.apply(event(.turnCompleted, .idle, offset: 5))
        state.apply(event(.activity, .running, offset: 6)); XCTAssertEqual(state.event.phase, .idle)
        state.apply(event(.turnStarted, .running, offset: 7, turn: "two"))
        state.apply(event(.turnCompleted, .idle, offset: 8, turn: "one")); XCTAssertEqual(state.event.phase, .running)
    }
    func testAgentIgnoresGenericMessageCompletionAndStaleSessions() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let input = try JSONSerialization.data(withJSONObject: ["timestamp": timestamp, "type": "response_item", "payload": ["type": "message", "role": "assistant", "status": "completed"]])
        XCTAssertEqual(AgentEvent.codexActivity(in: input, session: "local")?.phase, .running)
        let now = Date()
        let stale = AgentEvent(provider: .codex, session: "old", phase: .waiting, updatedAt: now.addingTimeInterval(-901), evidence: .hooks)
        let fresh = AgentEvent(provider: .codex, session: "new", phase: .idle, updatedAt: now, evidence: .hooks)
        XCTAssertEqual(AgentEvent.snapshot(provider: .codex, events: [stale, fresh], now: now).phase, .idle)
    }
    func testHookUpdatePreservesOtherHandlersAndUninstallsOnlyQuickTile() throws {
        let original = Data(#"{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/true"},{"type":"command","command":"echo '/tmp/QuickTileAgentEvent' codex"},{"type":"command","command":"echo QuickTileMac --agent-event codex"}]}]}}"#.utf8)
        let command = "'/tmp/QuickTileAgentEvent' codex"
        let installed = try AgentHookConfiguration.update(original, provider: .codex, command: command)
        let removed = try AgentHookConfiguration.update(installed, provider: .codex, command: command, removing: true)
        let restored = try JSONSerialization.jsonObject(with: removed) as? NSDictionary
        let initial = try JSONSerialization.jsonObject(with: original) as? NSDictionary
        XCTAssertEqual(restored, initial)
        XCTAssertThrowsError(try AgentHookConfiguration.update(Data("[]".utf8), provider: .codex, command: command))
    }
}
