import XCTest
import Network
import AppKit
import QuickTileCore

final class CompanionTests: XCTestCase {
    func testAgentLifecycleEventsStayMinimalAndPrioritizeWaiting() throws {
        let running = try XCTUnwrap(AgentEvent(provider: .codex, input: Data(#"{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"secret"}}"#.utf8)))
        let waiting = try XCTUnwrap(AgentEvent(provider: .codex, input: Data(#"{"session_id":"s2","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#.utf8)))
        XCTAssertEqual(running.phase, .running)
        XCTAssertEqual(waiting.phase, .waiting)
        XCTAssertEqual(AgentEvent.phase(for: [running, waiting]), .waiting)
        let encoded = try JSONEncoder().encode(running)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("secret"))
    }
    func testClaudeDesktopAndTerminalEventsUseSameLifecycleMapping() throws {
        let prompt = try XCTUnwrap(AgentEvent(provider: .claude, input: Data(#"{"session_id":"s1","hook_event_name":"UserPromptSubmit"}"#.utf8)))
        let question = try XCTUnwrap(AgentEvent(provider: .claude, input: Data(#"{"session_id":"s1","hook_event_name":"Notification","notification_type":"permission_prompt"}"#.utf8)))
        XCTAssertEqual(prompt.phase, .running)
        XCTAssertEqual(question.phase, .waiting)
    }
    @MainActor func testMediaKeysHaveMatchingPressAndRelease() throws {
        for (command, code) in [(MediaCommand.playPause, 16), (.next, 17), (.previous, 18)] {
            let events = try ActionExecutor.mediaEvents(command)
            XCTAssertEqual(events.count, 2)
            XCTAssertEqual(events[0].type, .systemDefined)
            XCTAssertEqual(events[0].subtype.rawValue, 8)
            XCTAssertEqual(events[0].data1, code << 16 | 0xA00)
            XCTAssertEqual(events[1].data1, code << 16 | 0xB00)
            XCTAssertNotNil(events[0].cgEvent); XCTAssertNotNil(events[1].cgEvent)
        }
    }
    @MainActor func testChangedApplicationIdentityCannotReceiveKeys() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        let contents = directory.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plist: [String: Any] = ["CFBundleIdentifier": "test.actual.app", "CFBundleName": "Test", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertNoThrow(try ActionExecutor.validateAppIdentity(directory, expected: "test.actual.app"))
        XCTAssertThrowsError(try ActionExecutor.validateAppIdentity(directory, expected: "test.old.app"))
    }
    func testDialZeroActuallyMutesAndPreservesLevel() throws {
        guard ProcessInfo.processInfo.environment["QUICKTILE_TEST_HARDWARE"] == "1" else { throw XCTSkip("Hardware-changing checks require QUICKTILE_TEST_HARDWARE=1.") }
        let control = VolumeControl()
        guard control.supportsMute, let original = control.read(includeMute: false), let wasMuted = control.isMuted() else {
            throw XCTSkip("Output does not expose software mute")
        }
        defer { try? control.execute(.set(original)); try? control.setMuted(wasMuted) }
        try control.setDialLevel(0)
        XCTAssertEqual(control.isMuted(), true)
        XCTAssertEqual(control.read(), 0)
        XCTAssertEqual(control.read(includeMute: false)!, original, accuracy: 0.001)
        if original > 0 {
            try control.setDialLevel(original)
            XCTAssertEqual(control.isMuted(), false)
            XCTAssertEqual(control.read()!, original, accuracy: 0.001)
        }
    }
    @MainActor func testDialHardwareReadAndWriteCurrentLevels() throws {
        guard ProcessInfo.processInfo.environment["QUICKTILE_TEST_HARDWARE"] == "1" else { throw XCTSkip("Hardware-changing checks require QUICKTILE_TEST_HARDWARE=1.") }
        let state = BrightnessControl.shared.snapshot()
        if let volume = VolumeControl().read(includeMute: false) {
            XCTAssertTrue((0...1).contains(volume))
            try VolumeControl().execute(.set(volume))
            XCTAssertEqual(VolumeControl().read(includeMute: false)!, volume, accuracy: 0.01)
        }
        if let brightness = state.brightness, let id = state.displayID {
            XCTAssertTrue((0...1).contains(brightness))
            try BrightnessControl.shared.set(brightness, displayID: id)
            XCTAssertEqual(BrightnessControl.shared.snapshot().brightness!, brightness, accuracy: 0.01)
        }
        XCTAssertThrowsError(try BrightnessControl.shared.set(1.2, displayID: state.displayID ?? 0))
        XCTAssertThrowsError(try BrightnessControl.shared.set(0.5, displayID: 0))
    }
    func testApplicationDiscoveryMergesExternalPathsAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func makeApp(_ path: String, platforms: [String] = ["MacOSX"]) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": "test." + UUID().uuidString, "CFBundleExecutable": "Run", "CFBundlePackageType": "APPL", "CFBundleSupportedPlatforms": platforms]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
            try Data("fixture".utf8).write(to: url.appendingPathComponent("Contents/MacOS/Run"))
            return url
        }
        let external = try makeApp("Other Folder/External.app")
        let alias = root.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: external)
        let mobile = try makeApp("Mobile.app", platforms: ["iPhoneOS"])
        let helper = try makeApp("Host.app/Contents/Helpers/Helper.app")
        let developerTool = try makeApp("Xcode.app/Contents/Applications/Inspector.app")
        let found = Catalog.applicationURLs(candidates: [external, alias, external, mobile, helper, developerTool, root.appendingPathComponent("Missing.app")])
        XCTAssertEqual(Set(found.map(\.path)), Set([external.path, developerTool.path]))
    }
    @MainActor func testRealPairApprovalCatalogLaunchRevocationAndReconnect() async throws {
        // The unbundled xctest runner is otherwise activation-prohibited, unlike the companion.
        let previousPolicy = NSApplication.shared.activationPolicy()
        defer { _ = NSApplication.shared.setActivationPolicy(previousPolicy) }
        _ = NSApplication.shared.setActivationPolicy(.accessory)
        let identifier = "QuickTile.tests." + UUID().uuidString
        let vault = KeychainStore(service: identifier)
        let defaults = UserDefaults(suiteName: identifier)!
        let assistantConfig = URLSessionConfiguration.ephemeral; assistantConfig.protocolClasses = [AssistantTransportStub.self]
        let server = MacServer(vault: vault, defaults: defaults, assistant: GroqAssistant(testingKey: "fake-test-key-never-live", sessionConfiguration: assistantConfig))
        server.testAllowsLoopback = true
        defer { server.shutdown(); try? vault.delete(account: "devices"); defaults.removePersistentDomain(forName: identifier) }
        server.createInvite()
        guard let invite = server.invite else { XCTFail(server.error ?? "No invite"); return }
        try await until { server.testPort(invite.identity) != nil }
        let pair = try channel(key: invite.key, identity: invite.identity, port: server.testPort(invite.identity)!)
        var credential: Credential?
        pair.onReady = { pair.send(Envelope(payload: .pairRequest(Hello(name: "QuickTile integration test")))) }
        pair.onMessage = { message in if case .paired(let value) = message.payload { credential = value } }
        pair.onClose = { reason in print("Pair transport closed: \(reason)") }
        pair.start()
        try await until { !server.pending.isEmpty }
        XCTAssertTrue(server.devices.isEmpty, "TLS invite must not authorize commands")
        server.approve(server.pending[0])
        XCTAssertNil(server.error, "Approval error: \(server.error ?? "none")")
        try await until { credential != nil }
        let saved = try XCTUnwrap(credential)
        XCTAssertEqual(try vault.read([Credential].self, account: "devices")?.count, 1)
        XCTAssertNil(server.invite, "Invite must be consumed")
        try await until { server.testPort(saved.id) != nil }
        let control = try channel(key: saved.key, identity: saved.id, port: server.testPort(saved.id)!)
        var welcome: Welcome?, catalogCount = 0, result: ActionResult?, icon: IconAsset?, controls: ControlState?, closeReason: String?
        control.onReady = { control.send(Envelope(payload: .hello(Hello(name: "QuickTile integration test", features: ["voice-assistant.v1"])))) }
        control.onMessage = { message in
            switch message.payload {
            case .welcome(let value): welcome = value
            case .catalog(let chunk): catalogCount += chunk.apps.count
            case .result(let value): if value.status != .accepted { result = value }
            case .icon(let value): icon = value
            case .controls(let value): controls = value
            case .closed(let reason): closeReason = reason; control.close(reason)
            default: break
            }
        }
        control.start(); try await until { welcome != nil }
        XCTAssertEqual(welcome?.capabilities.controlsVersion, 1)
        XCTAssertEqual(welcome?.capabilities.assistantReady, true)
        let assistantRequest = Envelope(payload: .assistantRequest(.init(sessionID: welcome!.sessionID, createdAt: Date(), text: "Open Safari")))
        control.send(assistantRequest); try await until { result != nil }
        XCTAssertEqual(result?.status, .failed)
        XCTAssertTrue(result?.message.contains("API limit") == true)
        XCTAssertFalse(result?.message.contains("private provider body") == true)
        result = nil; control.send(assistantRequest); try await until { result != nil }
        XCTAssertEqual(result?.status, .failed, "Assistant requests must reject replay before provider/execution")
        result = nil
        control.send(Envelope(payload: .controlsRequest))
        try await until { controls != nil }
        if ProcessInfo.processInfo.environment["QUICKTILE_TEST_HARDWARE"] == "1", let volume = controls?.volume {
            controls = nil
            let adjustment = ControlAdjustment(sessionID: welcome!.sessionID, createdAt: Date(), kind: .volume, value: volume, displayID: nil)
            let command = Envelope(payload: .adjustControl(adjustment))
            control.send(command)
            try await until { controls != nil }
            XCTAssertEqual(controls!.volume!, volume, accuracy: 0.01)
            control.send(command)
            try await until { result != nil }
            XCTAssertEqual(result?.status, .failed, "Dial commands must reject replays")
            result = nil
        }
        await server.refresh()
        control.send(Envelope(payload: .catalogRequest))
        try await until { catalogCount > 0 }
        XCTAssertGreaterThan(server.catalog.apps.count, 0)
        for identifier in ["com.apple.finder", "com.apple.Safari"] where NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil {
            XCTAssertTrue(server.catalog.apps.contains { $0.id == identifier }, "Catalog should include \(identifier)")
        }
        if let version = server.catalog.apps.first(where: { $0.iconVersion != nil })?.iconVersion {
            control.send(Envelope(payload: .iconRequest(version: version))); try await until { icon != nil }
            XCTAssertLessThanOrEqual(icon!.png.count, Limits.assetBytes)
            XCTAssertNotNil(NSImage(data: icon!.png))
        }
        let requestID = UUID()
        let launch = Command(sessionID: welcome!.sessionID, action: .launchApp(bundleID: "com.apple.TextEdit"))
        control.send(Envelope(id: requestID, payload: .command(launch)))
        try await until { result != nil }
        XCTAssertEqual(result?.status, .completed, result?.message ?? "No result")
        XCTAssertTrue(NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.TextEdit" })
        result = nil; control.send(Envelope(id: requestID, payload: .command(launch)))
        try await until { result != nil }; XCTAssertEqual(result?.status, .failed)
        result = nil
        control.send(Envelope(payload: .command(Command(sessionID: welcome!.sessionID, action: .launchApp(bundleID: "org.quicktile.nonexistent")))))
        try await until { result != nil }; XCTAssertEqual(result?.status, .failed)
        let oldSession = welcome!.sessionID
        server.togglePaused()
        try await until { closeReason != nil && control.isClosed }
        XCTAssertEqual(closeReason, "QuickTile is paused on the Mac.", "The phone needs the explicit reason to show its paused overlay")
        XCTAssertTrue(server.connectedNames.isEmpty, "Pausing must immediately revoke active work")
        server.togglePaused()
        try await until { server.testPort(saved.id) != nil }
        let second = try channel(key: saved.key, identity: saved.id, port: server.testPort(saved.id)!)
        var secondWelcome: Welcome?, staleRejected = false, revokedReason: String?
        second.onReady = { second.send(Envelope(payload: .hello(Hello(name: "Reconnected test")))) }
        second.onMessage = { message in
            if case .welcome(let value) = message.payload { secondWelcome = value }
            if case .result(let value) = message.payload { staleRejected = value.status == .failed }
            if case .closed(let reason) = message.payload { revokedReason = reason; second.close(reason) }
        }
        second.start(); try await until { secondWelcome != nil }
        XCTAssertNotEqual(oldSession, secondWelcome?.sessionID)
        second.send(Envelope(payload: .command(Command(sessionID: oldSession, action: .volume(.up)))))
        try await until { staleRejected }
        server.revoke(saved)
        try await until { second.isClosed && revokedReason != nil }
        XCTAssertEqual(revokedReason, "This device was revoked on the Mac.")
        XCTAssertTrue(server.devices.isEmpty)
        XCTAssertEqual(try vault.read([Credential].self, account: "devices")?.count, 0)
        pair.close(); control.close(); second.close()
    }
    @MainActor func testUnapprovedCannotReadCatalogOrExecute() async throws {
        let name = "QuickTile.tests." + UUID().uuidString, vault = KeychainStore(service: UUID().uuidString)
        let defaults = UserDefaults(suiteName: name)!
        let server = MacServer(vault: vault, defaults: defaults); server.testAllowsLoopback = true
        defer { server.shutdown(); defaults.removePersistentDomain(forName: name) }
        server.createInvite(); let invite = try XCTUnwrap(server.invite)
        try await until { server.testPort(invite.identity) != nil }
        let unauthorized = try channel(key: invite.key, identity: invite.identity, port: server.testPort(invite.identity)!)
        unauthorized.onReady = { unauthorized.send(Envelope(payload: .catalogRequest)) }
        var rejection: String?
        unauthorized.onMessage = { message in
            if case .closed(let reason) = message.payload { rejection = reason; unauthorized.close(reason) }
            else { XCTFail("Pairing endpoint disclosed data before approval") }
        }
        unauthorized.start(); try await until { unauthorized.isClosed }
        XCTAssertEqual(rejection, "Pairing request rejected.")
        XCTAssertTrue(server.devices.isEmpty)
    }
    @MainActor func testProcessArgumentsAndShortcutParsing() async throws {
        let id = UUID()
        let name = "A name (with parentheses) & $HOME; 'quotes'"
        let parsed = Catalog.parseShortcuts("\(name) (\(id.uuidString))\n")
        XCTAssertEqual(parsed.first?.name, name); XCTAssertEqual(parsed.first?.id, id.uuidString)
        let output = try await ProcessJob().run(executable: "/usr/bin/printf", arguments: ["%s", name], timeout: 3)
        XCTAssertEqual(output.text, name)
        do { _ = try await ProcessJob().run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.3); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? QuickTileError, .timeout) }
    }
    @MainActor private func channel(key: Data, identity: UUID, port: NWEndpoint.Port) throws -> WireChannel {
        let params = try SecureTransport.parameters(key: key, identity: identity); params.prohibitedInterfaceTypes = []
        return WireChannel(NWConnection(host: "127.0.0.1", port: port, using: params))
    }
    @MainActor private func until(timeout: TimeInterval = 25, file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate(), "Integration condition timed out", file: file, line: line)
        if !predicate() { throw QuickTileError.timeout }
    }
}
