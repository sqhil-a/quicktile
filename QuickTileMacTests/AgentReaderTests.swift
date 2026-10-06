import XCTest
import QuickTileCore

final class AgentReaderTests: XCTestCase {
    func testReaderResetsWhenAFileIsRewrittenAtTheSameLength() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.jsonl")
        let header = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": ["id": "session", "source": "cli"]])
        let time = ISO8601DateFormatter().string(from: Date())
        func record(_ name: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["timestamp": time, "type": "event_msg", "payload": ["type": name, "turn_id": "turn"]], options: [.sortedKeys])
        }
        let started = try record("task_started")
        let completed = try record("task_complete")
        let padding = Data(repeating: 32, count: max(0, completed.count - started.count))
        let initial = header + Data([10]) + started + padding + Data([10])
        let replacement = header + Data([10]) + completed + Data([10])
        XCTAssertEqual(initial.count, replacement.count)
        try initial.write(to: file)
        let reader = CodexActivityReader(root: directory)
        let first = await reader.refresh()
        XCTAssertEqual(first.first?.phase, .running)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: replacement)
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(1)], ofItemAtPath: file.path)
        let second = await reader.refresh()
        XCTAssertEqual(second.first?.phase, .idle)
    }

    func testTrackingInstallationReportsMissingHelperAndLegacyHooks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hookFile = directory.appendingPathComponent("hooks.json")
        XCTAssertNotNil(AgentTrackingInstallation.issue(directory: directory, hookFile: hookFile, provider: .codex))
        let helper = directory.appendingPathComponent("QuickTileAgentEvent")
        try Data("test fixture; never executed".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let legacy = try AgentHookConfiguration.update(Data("{}".utf8), provider: .codex, command: "'/Applications/QuickTileMac.app/Contents/MacOS/QuickTileMac' --agent-event codex")
        try legacy.write(to: hookFile)
        let previous = try Data(contentsOf: hookFile)
        XCTAssertNotNil(AgentTrackingInstallation.issue(directory: directory, hookFile: hookFile, provider: .codex))
        XCTAssertEqual(try Data(contentsOf: hookFile), previous, "Read-only health checks must not alter hook configuration or trust.")
        let current = try AgentHookConfiguration.update(Data("{}".utf8), provider: .codex, command: "'\(helper.path)' codex")
        try current.write(to: hookFile)
        XCTAssertNil(AgentTrackingInstallation.issue(directory: directory, hookFile: hookFile, provider: .codex))
    }

    func testTrackingInstallationRequiresApprovalAndCompletionCoveragePerProvider() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("QuickTileAgentEvent")
        try Data("test fixture; never executed".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        for provider in AgentProvider.allCases {
            let file = directory.appendingPathComponent("\(provider.rawValue).json")
            let configuration = try AgentHookConfiguration.update(Data("{}".utf8), provider: provider, command: "'\(helper.path)' \(provider.rawValue)")
            try configuration.write(to: file)
            XCTAssertNil(AgentTrackingInstallation.issue(directory: directory, hookFile: file, provider: provider))
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: configuration) as? [String: Any])
            var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
            hooks.removeValue(forKey: "PermissionRequest")
            root["hooks"] = hooks
            try JSONSerialization.data(withJSONObject: root).write(to: file)
            XCTAssertNotNil(AgentTrackingInstallation.issue(directory: directory, hookFile: file, provider: provider))
        }
    }

    func testIncrementalReaderHandlesLargeHeaderAndPartialTrailingRecord() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.jsonl")
        let header = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": ["id": "session", "source": "cli", "metadata": String(repeating: "x", count: 160_000)]])
        func record(_ type: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["timestamp": ISO8601DateFormatter().string(from: Date()), "type": "event_msg", "payload": ["type": type, "turn_id": "turn"]])
        }
        let completion = try record("task_complete")
        try (header + Data([10]) + record("task_started") + Data([10]) + completion.prefix(completion.count / 2)).write(to: file)
        let reader = CodexActivityReader(root: directory)
        let running = await reader.refresh()
        XCTAssertEqual(running.first?.phase, .running)
        XCTAssertEqual(running.first?.source, .terminal)
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
        try handle.write(contentsOf: completion.suffix(completion.count - completion.count / 2) + Data([10])); try handle.close()
        let completed = await reader.refresh()
        XCTAssertEqual(completed.first?.phase, .idle)
        XCTAssertEqual(completed.first?.turnID, "turn")
    }
}

extension AgentReaderTests {
    @MainActor func testControlStatusDoesNotKeepWaitingAfterRequestResolves() {
        let bridge = CodexControlBridge()
        bridge.ingest(["id":99,"method":"item/tool/requestUserInput","params":["threadId":"s","turnId":"t","questions":[["id":"q","question":"Which app?","isOther":true,"options":[["label":"Xcode","description":"Build"]]]]]])
        XCTAssertEqual(bridge.phases["s"],.waiting)
        XCTAssertEqual(bridge.requests.first?.questions.first?.text,"Which app?")
        XCTAssertTrue(bridge.requests.first?.canReply ?? false)
        bridge.ingest(["method":"serverRequest/resolved","params":["threadId":"s","requestId":99]])
        bridge.ingest(["method":"thread/status/changed","params":["threadId":"s","status":["type":"active","activeFlags":[]]]])
        XCTAssertTrue(bridge.requests.isEmpty)
        XCTAssertEqual(bridge.phases["s"],.running)
    }
    @MainActor func testCancelledTurnCannotKeepAReplyTarget() async throws {
        let bridge = CodexControlBridge()
        bridge.ingest(["id":"approval","method":"item/commandExecution/requestApproval","params":["threadId":"s","turnId":"t","reason":"Build the app","command":"build"]])
        let request = try XCTUnwrap(bridge.requests.first)
        bridge.ingest(["method":"turn/completed","params":["threadId":"s"]])
        do { try await bridge.reply(.init(sessionID:UUID(),createdAt:Date(),requestID:request.id,decision:.approveOnce)); XCTFail("Stale reply accepted") }
        catch { XCTAssertTrue(bridge.requests.isEmpty) }
    }
    @MainActor func testNonblockingQuestionDoesNotManufactureWaiting() {
        let bridge = CodexControlBridge()
        bridge.ingest(["method":"thread/status/changed","params":["threadId":"s","status":["type":"active","activeFlags":[]]]])
        bridge.ingest(["id":2,"method":"item/tool/requestUserInput","params":["threadId":"s","turnId":"t","isBlocking":false,"questions":[["id":"q","question":"Which app?"]]]])
        XCTAssertEqual(bridge.phases["s"],.running)
    }
}

extension AgentReaderTests {
    @MainActor func testAnswerUsesOriginalRequestAndWaitsForMatchingConfirmation() async throws {
        var sent: [String:Any]?
        let bridge = CodexControlBridge(testingSend:{ sent = $0 })
        bridge.ingest(["id":99,"method":"item/tool/requestUserInput","params":["threadId":"s","turnId":"t","questions":[["id":"q","question":"Which app?","options":[["label":"Xcode","description":"Build"]]]]]])
        let request = try XCTUnwrap(bridge.requests.first)
        let task = Task { try await bridge.reply(.init(sessionID:UUID(),createdAt:Date(),requestID:request.id,answers:["q":"Xcode"])) }
        await Task.yield()
        XCTAssertEqual(sent?["id"] as? Int,99)
        let result = sent?["result"] as? [String:Any]
        let answers = result?["answers"] as? [String:[String:[String]]]
        XCTAssertEqual(answers?["q"]?["answers"],["Xcode"])
        XCTAssertFalse(bridge.requests.first?.canReply ?? true)
        bridge.ingest(["method":"serverRequest/resolved","params":["threadId":"s","requestId":98]])
        XCTAssertEqual(bridge.requests.count,1)
        bridge.ingest(["method":"serverRequest/resolved","params":["threadId":"s","requestId":99]])
        try await task.value
        XCTAssertTrue(bridge.requests.isEmpty)
    }
}
