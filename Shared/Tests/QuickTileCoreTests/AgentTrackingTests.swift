import XCTest
@testable import QuickTileCore

final class AgentTrackingTests: XCTestCase {
    private func event(_ provider: AgentProvider = .codex, _ name: String, _ fields: [String: Any] = [:], at: Int) throws -> AgentEvent {
        var json = fields; json["session_id"] = "session"; json["hook_event_name"] = name
        let data = try JSONSerialization.data(withJSONObject: json)
        return try XCTUnwrap(AgentEvent(provider: provider, input: data, now: Date(timeIntervalSince1970: Double(at))))
    }
    func testCodexApprovalWithoutToolIDWaitsUntilMatchingToolCompletes() throws {
        var state = AgentSessionState(event: try event(.codex, "UserPromptSubmit", ["turn_id":"turn"], at: 1))
        state.apply(try event(.codex, "PreToolUse", ["turn_id":"turn", "tool_use_id":"call-a", "tool_name":"exec_command", "tool_input":["cmd":"build"]], at: 2))
        state.apply(try event(.codex, "PermissionRequest", ["turn_id":"turn", "tool_name":"exec_command", "tool_input":["cmd":"build"]], at: 3))
        XCTAssertEqual(state.event.phase, .waiting)
        state.apply(try event(.codex, "PostToolUse", ["turn_id":"turn", "tool_use_id":"other", "tool_name":"read_file"], at: 4))
        XCTAssertEqual(state.event.phase, .waiting)
        state.apply(try event(.codex, "PostToolUse", ["turn_id":"turn", "tool_use_id":"call-a", "tool_name":"exec_command"], at: 5))
        XCTAssertEqual(state.event.phase, .running)
        state.apply(try event(.codex, "Stop", ["turn_id":"turn"], at: 6))
        XCTAssertEqual(state.event.phase, .idle)
    }
    func testIdlessShellCompletionMatchesCommandDespiteApprovalDescription() throws {
        var state = AgentSessionState(event: try event(.codex, "UserPromptSubmit", ["turn_id":"t"], at:1))
        state.apply(try event(.codex, "PermissionRequest", ["turn_id":"t", "tool_name":"Bash", "tool_input":["command":"build", "description":"Build the app"]], at:2))
        state.apply(try event(.codex, "PermissionRequest", ["turn_id":"t", "tool_name":"Bash", "tool_input":["command":"test", "description":"Test the app"]], at:3))
        state.apply(try event(.codex, "PostToolUse", ["turn_id":"t", "tool_name":"Bash", "tool_input":["cmd":"build", "timeout":300]], at:4))
        XCTAssertEqual(state.event.phase,.waiting)
        XCTAssertEqual(state.event.pendingInputs?.count,1)
        state.apply(try event(.codex, "PostToolUse", ["turn_id":"t", "tool_name":"Bash", "tool_input":["command":"test"]], at:5))
        XCTAssertEqual(state.event.phase,.running)
    }
    func testQuestionDetailsAreBoundedAndDisappearWithResolvedInput() throws {
        var state = AgentSessionState(event: try event(.codex,"PreToolUse",["turn_id":"t","tool_use_id":"q","tool_name":"request_user_input","tool_input":["questions":[["id":"choice","question":"Which app?","options":[["label":"Xcode","description":"Build"]]]]]],at:1))
        let requests = AgentEvent.pendingRequests(provider:.codex,events:[state.event],now:Date(timeIntervalSince1970:2))
        XCTAssertEqual(requests.first?.questions.first?.text,"Which app?")
        XCTAssertFalse(requests.first?.canReply ?? true)
        state.apply(try event(.codex,"PostToolUse",["turn_id":"t","tool_use_id":"q"],at:3))
        XCTAssertTrue(AgentEvent.pendingRequests(provider:.codex,events:[state.event],now:Date(timeIntervalSince1970:4)).isEmpty)
    }
    func testLegacyUnresolvableApprovalDoesNotRemainWaiting() throws {
        var old = AgentEvent(provider:.codex,session:"session",phase:.waiting,updatedAt:Date(timeIntervalSince1970:1),lifecycle:.inputResolved,evidence:.hooks,turnID:"t")
        old.foregroundPhase = .running; old.foregroundClosed = false
        old.pendingInputs = [.init(kind:.permission,toolName:"Bash",correlationHash:"old-full-wrapper-hash")]
        var restored = AgentSessionState(event:old)
        XCTAssertEqual(restored.event.phase,.unknown)
        restored.apply(try event(.codex,"PostToolUse",["turn_id":"t","tool_name":"Bash","tool_input":["command":"test"]],at:2))
        XCTAssertEqual(restored.event.phase,.running)
    }
    func testTimerHapticChoicePersistsWithoutBreakingOlderTiles() throws {
        var tile = Tile(name:"Timer",symbol:"timer",action:.timer(seconds:300))
        XCTAssertNil(try JSONDecoder().decode(Tile.self,from:JSONEncoder().encode(tile)).timerHaptic)
        tile.timerHaptic = .doubleClick
        XCTAssertEqual(try JSONDecoder().decode(Tile.self,from:JSONEncoder().encode(tile)).timerHaptic,.doubleClick)
    }
    func testFreshHookCheckpointOverridesOlderClosedLogTurn() throws {
        let old = AgentSessionState(event:.init(provider:.codex,session:"session",phase:.idle,updatedAt:Date(timeIntervalSince1970:1),lifecycle:.turnCompleted,evidence:.codexLog,turnID:"old")).event
        var current = AgentSessionState(event:try event(.codex,"UserPromptSubmit",["turn_id":"new"],at:2))
        current.apply(try event(.codex,"PreToolUse",["turn_id":"new","tool_name":"Bash","tool_input":["command":"build"]],at:3))
        XCTAssertEqual(AgentEvent.snapshot(provider:.codex,events:[old,current.event],now:Date(timeIntervalSince1970:4)).phase,.running)
        current.apply(try event(.codex,"PermissionRequest",["turn_id":"new","tool_name":"Bash","tool_input":["command":"build"]],at:5))
        XCTAssertEqual(AgentEvent.pendingRequests(provider:.codex,events:[old,current.event],now:Date(timeIntervalSince1970:6)).count,1)
    }
    func testConcurrentApprovalsPersistAcrossHelperInvocations() throws {
        var state = AgentSessionState(event: try event(.codex, "UserPromptSubmit", ["turn_id":"t"], at: 1))
        for (index,id) in ["a","b"].enumerated() {
            state.apply(try event(.codex, "PermissionRequest", ["turn_id":"t", "tool_use_id":id, "tool_name":"tool"], at: index + 2))
        }
        let restored = try JSONDecoder().decode(AgentEvent.self, from: JSONEncoder().encode(state.event))
        state = AgentSessionState(event: restored)
        state.apply(try event(.codex, "PostToolUse", ["turn_id":"t", "tool_use_id":"a"], at: 5))
        XCTAssertEqual(state.event.phase, .waiting)
        state.apply(try event(.codex, "PostToolUse", ["turn_id":"t", "tool_use_id":"b"], at: 6))
        XCTAssertEqual(state.event.phase, .running)
    }
    func testClaudeLatePreviousPromptCannotOverwriteCurrentApproval() throws {
        var state = AgentSessionState(event: try event(.claude, "UserPromptSubmit", ["prompt_id":"old"], at: 1))
        state.apply(try event(.claude, "UserPromptSubmit", ["prompt_id":"new"], at: 2))
        state.apply(try event(.claude, "PermissionRequest", ["prompt_id":"new", "tool_use_id":"a", "tool_name":"Bash"], at: 3))
        state.apply(try event(.claude, "Stop", ["prompt_id":"old"], at: 4))
        XCTAssertEqual(state.event.phase, .waiting)
        XCTAssertEqual(state.event.turnID, "new")
    }
    func testClaudeDeniedPermissionClearsOnlyItsRequest() throws {
        var state = AgentSessionState(event: try event(.claude, "UserPromptSubmit", ["prompt_id":"t"], at: 1))
        state.apply(try event(.claude, "PermissionRequest", ["prompt_id":"t", "tool_use_id":"a", "tool_name":"Bash"], at: 2))
        state.apply(try event(.claude, "PermissionDenied", ["prompt_id":"t", "tool_use_id":"a", "tool_name":"Bash"], at: 3))
        XCTAssertEqual(state.event.phase, .running)
    }
    func testLogToolOutputDoesNotClearHookApproval() throws {
        var state = AgentSessionState(event: try event(.codex, "PermissionRequest", ["turn_id":"t", "tool_use_id":"a", "tool_name":"exec_command"], at: 1))
        state.apply(.init(provider: .codex, session: "session", phase: .running, updatedAt: Date(timeIntervalSince1970: 2), lifecycle: .inputResolved, evidence: .codexLog, turnID: "t", waitingRequestID: "b"))
        XCTAssertEqual(state.event.phase, .waiting)
    }
    func testClaudeElicitationNotificationResolvesAndCompletionClosesTurn() throws {
        var state = AgentSessionState(event: try event(.claude, "UserPromptSubmit", ["prompt_id":"t"], at: 1))
        state.apply(try event(.claude, "Notification", ["prompt_id":"t", "notification_type":"elicitation_url_dialog"], at: 2))
        XCTAssertEqual(state.event.phase, .waiting)
        state.apply(try event(.claude, "Notification", ["prompt_id":"t", "notification_type":"elicitation_complete"], at: 3))
        XCTAssertEqual(state.event.phase, .running)
        state.apply(try event(.claude, "Stop", ["prompt_id":"t", "background_tasks":[]], at: 4))
        XCTAssertEqual(state.event.phase, .idle)
    }
}
