import XCTest
@testable import QuickTileCore

final class CoreTests: XCTestCase {
    func testTileSlotsPreserveGapsAndSwapWithoutChangingOtherPages() throws {
        let tiles = (0..<9).map { Tile(name: "Tile \($0)", symbol: "star", action: .media(.next)) }
        var page = DeckPage(tiles: tiles)
        page.place(tiles[0].id, at: 7)
        XCTAssertEqual(page.slots[7]?.id, tiles[0].id)
        XCTAssertEqual(page.slots[0]?.id, tiles[7].id)
        page.removeTile(tiles[0].id)
        XCTAssertNil(page.slots[7])
        XCTAssertEqual(page.slots[8]?.id, tiles[8].id)
        page.place(tiles[1].id, at: 7)
        XCTAssertNil(page.slots[1])
        let added = Tile(name: "Added", symbol: "star", action: .media(.next))
        page.tiles.append(added); page.place(added.id, at: 5)
        XCTAssertEqual(page.slots[5]?.id, added.id)
        let layout = DeckLayout(macID: UUID(), pages: [page])
        let restored = try LayoutStore.decode(JSONEncoder().encode(layout))
        XCTAssertEqual(restored.screens.map { $0.slots.map { $0?.id } }, layout.screens.map { $0.slots.map { $0?.id } })
        XCTAssertEqual(restored.screens.count, 2)
        XCTAssertEqual(Set(restored.screens.flatMap(\.tiles).map(\.id)).count, page.tiles.count)
    }
    func testUnknownSavedActionIsPreservedForRepair() throws {
        let tile = Tile(name: "Future action", symbol: "star", action: .media(.next))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(tile)) as? [String: Any])
        object["action"] = ["futureAction": ["value": "keep me"]]
        let restored = try JSONDecoder().decode(Tile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.id, tile.id)
        XCTAssertThrowsError(try restored.action.validate())
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        XCTAssertEqual(saved["action"] as? NSDictionary, object["action"] as? NSDictionary)
    }
    func testActionLibraryAndMediaMigration() throws {
        XCTAssertGreaterThan(ActionLibrary.presets.count, 90)
        XCTAssertEqual(Set(ActionLibrary.actions.map(\.id)).count, ActionLibrary.actions.count)
        for preset in ActionLibrary.presets {
            try DeckAction.preset(preset.id).validate()
            let shortcut = try XCTUnwrap(preset.shortcut)
            try DeckAction.keyboard(shortcut).validate()
            XCTAssertEqual(shortcut.targetBundleID, preset.bundleID)
            XCTAssertFalse(preset.symbol.isEmpty)
        }
        let tile = Tile(name: "Play", symbol: "music.note", action: .music(.playPause))
        var layout = DeckLayout(macID: UUID(), pages: [DeckPage(tiles: [tile])])
        layout.schemaVersion = 2; layout.settings.showLabels = true
        let migrated = try LayoutStore.decode(JSONEncoder().encode(layout))
        XCTAssertEqual(migrated.pages[0].tiles[0].id, tile.id)
        XCTAssertEqual(migrated.pages[0].tiles[0].action, .media(.playPause))
        XCTAssertEqual(migrated.pages[0].tiles[0].displaySymbol, "playpause.fill")
        XCTAssertFalse(migrated.settings.showLabels)
        layout.pages[0].tiles[0].action = .preset("missing.preset")
        XCTAssertEqual(try LayoutStore.decode(JSONEncoder().encode(layout)).pages[0].tiles[0].id, tile.id)
    }
    func testAgentActivityReportsRunningAndUnknownHonestly() throws {
        XCTAssertEqual(AgentEvent.phase(for: []), .unknown)
        let start = #"{"timestamp":"2026-09-13T03:30:00.000Z","type":"event_msg","payload":{"type":"task_started"}}"#
        let done = #"{"timestamp":"2026-09-13T03:31:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#
        let question = #"{"timestamp":"2026-09-13T03:30:10.000Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input"}}"#
        let finalMessage = #"{"timestamp":"2026-09-13T03:31:01.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final"}}"#
        XCTAssertEqual(AgentEvent.codexActivity(in: Data(start.utf8), session: "test")?.phase, .running)
        XCTAssertEqual(AgentEvent.codexActivity(in: Data((start + "\n" + question).utf8), session: "test")?.phase, .waiting)
        XCTAssertEqual(AgentEvent.codexActivity(in: Data((start + "\n" + done).utf8), session: "test")?.phase, .idle)
        XCTAssertEqual(AgentEvent.codexActivity(in: Data((start + "\n" + finalMessage).utf8), session: "test")?.phase, .idle)
        let compact = try XCTUnwrap(AgentEvent(provider: .claude, input: Data(#"{"session_id":"test","hook_event_name":"SessionStart","source":"compact"}"#.utf8)))
        XCTAssertEqual(compact.phase, .running)
        let failure = try XCTUnwrap(AgentEvent(provider: .claude, input: Data(#"{"session_id":"test","hook_event_name":"PostToolUseFailure"}"#.utf8)))
        XCTAssertEqual(failure.phase, .running)
    }
    func testTimerBoundariesAndLifecycle() throws {
        XCTAssertThrowsError(try DeckAction.timer(seconds: 0).validate())
        XCTAssertThrowsError(try DeckAction.timer(seconds: 3601).validate())
        XCTAssertNoThrow(try DeckAction.timer(seconds: 3600).validate())
        var timer = TileCountdown(seconds: 60)
        let start = Date(timeIntervalSince1970: 1000)
        timer.toggle(at: start)
        timer.toggle(at: start.addingTimeInterval(10))
        XCTAssertNil(timer.deadline)
        XCTAssertEqual(timer.remaining, 50)
        timer.update(at: start.addingTimeInterval(100))
        XCTAssertEqual(timer.remaining, 50)
        timer.toggle(at: start.addingTimeInterval(100))
        timer.update(at: start.addingTimeInterval(151))
        XCTAssertTrue(timer.finished)
        XCTAssertEqual(timer.remaining, 0)
        timer.toggle(at: start.addingTimeInterval(152))
        XCTAssertFalse(timer.finished)
        XCTAssertNil(timer.deadline)
        XCTAssertEqual(timer.remaining, 60)
        timer.toggle(at: start); timer.reset()
        XCTAssertNil(timer.deadline)
        let tile = Tile(name: "Timer", symbol: "timer", action: .timer(seconds: 3600))
        let layout = DeckLayout(macID: UUID(), pages: [DeckPage(tiles: [tile])])
        XCTAssertEqual(try LayoutStore.decode(JSONEncoder().encode(layout)).pages[0].tiles[0].action, tile.action)
    }
    func testPhotoLibraryProfiles() throws {
        for profile in ["photoshop", "pixelmator", "affinity-photo", "affinity-designer"] {
            XCTAssertGreaterThan(ActionLibrary.presets.filter { $0.id.hasPrefix(profile + ".") }.count, 40)
        }
        XCTAssertEqual(ActionLibrary.preset(id: "pixelmator.export")?.shortcut?.key, "e")
        XCTAssertEqual(ActionLibrary.preset(id: "photoshop.clone-tool")?.shortcut?.key, "s")
        XCTAssertEqual(ActionLibrary.preset(id: "affinity-photo.clone-tool")?.shortcut?.key, "k")
        XCTAssertEqual(ActionLibrary.preset(id: "affinity-designer.node-tool")?.shortcut?.key, "a")
    }
    func testVideoPlaybackTargetsAndMappings() throws {
        let profiles = ["finalcut", "premiere", "resolve", "motion", "aftereffects"]
        for profile in profiles {
            let preset = try XCTUnwrap(ActionLibrary.preset(id: profile + ".play"))
            XCTAssertEqual(DeckAction.preset(preset.id).playbackTarget, preset.bundleID)
            XCTAssertGreaterThanOrEqual(ActionLibrary.presets.filter { $0.id.hasPrefix(profile + ".") }.count, 35)
        }
        XCTAssertNil(DeckAction.preset("xcode.continue").playbackTarget)
        XCTAssertEqual(DeckAction.media(.playPause).playbackTarget, DeckAction.music(.playPause).playbackTarget)
        XCTAssertEqual(ActionLibrary.preset(id: "aftereffects.split")?.shortcut?.key, "d")
        XCTAssertEqual(ActionLibrary.preset(id: "aftereffects.split")?.shortcut?.modifiers, [.command, .shift])
        XCTAssertEqual(ActionLibrary.preset(id: "aftereffects.frame-forward")?.shortcut?.key, "pagedown")
    }
    func testLegacyVolumeButtonsBecomeDials() throws {
        let old = Tile(name: "Volume up", symbol: "plus", action: .volume(.up))
        let original = DeckLayout(macID: UUID(), pages: [DeckPage(tiles: [old])])
        let migrated = try LayoutStore.decode(JSONEncoder().encode(original))
        XCTAssertEqual(migrated.pages[0].tiles[0].id, old.id)
        XCTAssertEqual(migrated.pages[0].tiles[0].action, .dial(.volume))
        XCTAssertEqual(migrated.pages[0].tiles[0].symbol, "speaker.wave.2")
    }
    func testDialAdjustmentValidationAndCompatibility() throws {
        let layout = DeckLayout(macID: UUID(), pages: [DeckPage(tiles: [
            Tile(name: "Volume", symbol: "speaker.wave.2", action: .dial(.volume)),
            Tile(name: "Brightness", symbol: "sun.max", action: .dial(.brightness))
        ])])
        XCTAssertEqual(try JSONDecoder().decode(DeckLayout.self, from: JSONEncoder().encode(layout)), layout)
        let session = UUID()
        for kind in ControlKind.allCases {
            let value = ControlAdjustment(sessionID: session, createdAt: Date(), kind: kind, value: 0.4, displayID: 1)
            try value.validate()
            let decoded = try Envelope.decode(Envelope(payload: .adjustControl(value)).encoded())
            guard case .adjustControl(let restored) = decoded.payload else { return XCTFail("Lost dial command") }
            XCTAssertEqual(restored.kind, kind); XCTAssertEqual(restored.value, 0.4)
            for invalid in [-0.01, 1.01, Double.nan, Double.infinity] {
                var bad = value; bad.value = invalid
                XCTAssertThrowsError(try bad.validate())
            }
        }
        let missing = ControlAdjustment(sessionID: session, createdAt: Date(), kind: .brightness, value: 0.5, displayID: nil)
        XCTAssertThrowsError(try missing.validate())
        let legacy = Data("{\"keyboard\":false,\"music\":false,\"volume\":true,\"mute\":true,\"shortcuts\":true,\"notes\":[]}".utf8)
        XCTAssertNil(try JSONDecoder().decode(Capabilities.self, from: legacy).controlsVersion)
    }
    func testBoardIconsPreserveLegacyPagesAndOverflow() throws {
        let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Work\",\"tiles\":[]}".utf8)
        var page = try JSONDecoder().decode(DeckPage.self, from: legacy)
        XCTAssertEqual(page.symbol, "square.grid.2x2")
        page.symbol = "briefcase"
        page.tiles = (0..<9).map { Tile(name: "App \($0)", symbol: "app", action: .launchApp(bundleID: "com.apple.Safari")) }
        let layout = DeckLayout(macID: UUID(), pages: [page])
        let restored = try JSONDecoder().decode(DeckLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(restored, layout)
        XCTAssertEqual(restored.screens.map(\.symbol), ["briefcase", "briefcase"])
    }
    func testIconQueueDoesNotDropOverflowAndRecoversAfterReconnect() {
        var queue = IconRequestQueue()
        for i in 0..<100 { queue.enqueue("icon-\(i)"); queue.enqueue("icon-\(i)") }
        var first: [IconRequestQueue.Request] = []
        while let request = queue.next() { first.append(request) }
        XCTAssertEqual(first.count, 6)
        XCTAssertEqual(queue.pendingCount, 100)
        queue.reconnect()
        XCTAssertNil(queue.key(for: first[0].id), "Old session replies cannot complete a new request")
        var received = Set<String>()
        while let request = queue.next() { received.insert(queue.complete(request.id)!) }
        XCTAssertEqual(received.count, 100)
        XCTAssertEqual(queue.pendingCount, 0)
    }
    func testIconQueueRetriesTimeoutsAndStopsAfterThreeAttempts() {
        var queue = IconRequestQueue(); queue.enqueue("missing")
        let now = Date()
        for attempt in 0..<3 {
            XCTAssertNotNil(queue.next(now: now))
            XCTAssertEqual(queue.expire(now: now.addingTimeInterval(13)), attempt == 2 ? ["missing"] : [])
        }
        XCTAssertEqual(queue.pendingCount, 0)
    }
    func testWebsiteIconsUseOriginAndPreferDeclaredTouchIcons() throws {
        let origin = try XCTUnwrap(WebsiteIcons.origin("https://example.com/private/account?secret=123#fragment"))
        XCTAssertEqual(origin.absoluteString, "https://example.com/")
        let html = #"<link href='/small.ico' rel='shortcut icon'><link REL="apple-touch-icon" sizes="180x180" href="/brand.png"><link rel="icon" href="javascript:bad"><link rel=icon href=https://cdn.example.com/site.png>"#
        XCTAssertEqual(WebsiteIcons.candidates(html: html, origin: origin).map(\.absoluteString), [
            "https://example.com/brand.png", "https://example.com/small.ico", "https://cdn.example.com/site.png",
            "https://example.com/apple-touch-icon.png", "https://example.com/favicon.ico"
        ])
        XCTAssertNil(WebsiteIcons.origin("javascript:bad"))
        XCTAssertEqual(WebsiteIcons.candidates(html: "", origin: origin).count, 2)
    }
    func testEightTileScreensPreserveEveryTileAndEmptyPage() {
        let tiles = (0..<19).map { Tile(name: "App \($0)", symbol: "app", action: .launchApp(bundleID: "test.app.\($0)")) }
        let page = DeckPage(name: "Work", tiles: tiles)
        let empty = DeckPage(name: "Personal")
        let layout = DeckLayout(macID: UUID(), pages: [page, empty])
        XCTAssertEqual(layout.screens.map { $0.tiles.count }, [8, 8, 3, 0])
        XCTAssertEqual(layout.screens.flatMap(\.tiles), tiles)
        XCTAssertEqual(Set(layout.screens.map(\.id)).count, 4)
        XCTAssertEqual(layout.screens.last?.pageID, empty.id)
        XCTAssertEqual(layout.screens[1].name, "Work · 2")
        XCTAssertEqual(layout.screens[0].id, DeckLayout(macID: layout.macID, pages: [DeckPage(id: page.id, name: "Renamed", tiles: tiles)]).screens[0].id)
    }
    func testProtocolRoundTripAndMalformedInput() throws {
        let message = Envelope(payload: .command(Command(sessionID: UUID(), action: .website(url: "https://example.com/a?q=one%20two"))))
        XCTAssertEqual(try Envelope.decode(message.encoded()).id, message.id)
        for data in [Data(), Data("{broken".utf8), Data("{\"version\":1}".utf8), Data(repeating: 0, count: Limits.frameBytes + 1)] {
            XCTAssertThrowsError(try Envelope.decode(data))
        }
        XCTAssertThrowsError(try Envelope.decode(Envelope(payload: .ping, version: 99).encoded()))
        XCTAssertThrowsError(try Envelope.decode(Envelope(payload: .icon(IconAsset(version: String(repeating: "a", count: 64), png: Data(repeating: 0, count: Limits.assetBytes + 1)))).encoded()))
    }
    func testPairingRandomSecretAndExpiry() throws {
        let key = try SecureRandom.key()
        XCTAssertEqual(key.count, 32); XCTAssertNotEqual(key, try SecureRandom.key())
        let invite = PairingInvite(macID: UUID(), name: "My Mac", key: key)
        XCTAssertEqual(try PairingInvite.decode(invite.encoded()), invite)
        XCTAssertThrowsError(try PairingInvite.decode(invite.encoded(), now: Date().addingTimeInterval(121)))
        XCTAssertThrowsError(try PairingInvite.decode("123456"))
        var broken = invite; broken.key = Data(repeating: 1, count: 6)
        XCTAssertThrowsError(try PairingInvite.decode(broken.encoded()))
    }
    func testAuthorizationRevocationAndSessionIsolation() throws {
        var gate = CommandGate()
        let request = Command(sessionID: gate.sessionID, action: .launchApp(bundleID: "com.apple.TextEdit"))
        XCTAssertThrowsError(try gate.admit(id: UUID(), command: request)) { XCTAssertEqual($0 as? QuickTileError, .unauthorized) }
        gate.authorized = true
        try gate.admit(id: UUID(), command: request)
        gate.revoke()
        XCTAssertThrowsError(try gate.admit(id: UUID(), command: request))
        var reconnected = CommandGate(authorized: true)
        XCTAssertThrowsError(try reconnected.admit(id: UUID(), command: request))
    }
    func testDuplicateExpiredFutureAndBurstCommands() throws {
        var gate = CommandGate(authorized: true)
        let now = Date(), id = UUID()
        let request = Command(sessionID: gate.sessionID, createdAt: now, action: .volume(.up))
        try gate.admit(id: id, command: request, now: now)
        XCTAssertThrowsError(try gate.admit(id: id, command: request, now: now)) { XCTAssertEqual($0 as? QuickTileError, .duplicate) }
        XCTAssertThrowsError(try gate.admit(id: UUID(), command: request, now: now.addingTimeInterval(11))) { XCTAssertEqual($0 as? QuickTileError, .expired) }
        XCTAssertThrowsError(try gate.admit(id: UUID(), command: request, now: now.addingTimeInterval(-3)))
        for _ in 0..<511 { try gate.admit(id: UUID(), command: request, now: now) }
        XCTAssertThrowsError(try gate.admit(id: UUID(), command: request, now: now))
    }
    func testURLValidation() throws {
        for url in ["https://example.com", "http://localhost:8080/path?q=a%20b", "https://例え.jp/path"] { XCTAssertNoThrow(try Validation.website(url)) }
        for url in ["file:///etc/passwd", "javascript:alert(1)", "ftp://example.com", "https://", "https://user:pass@example.com", " https://example.com", "https://example.com/a b", "https://example.com\n", "example.com"] { XCTAssertThrowsError(try Validation.website(url), url) }
    }
    func testKeyValidationAndNoShellAction() throws {
        XCTAssertNoThrow(try KeyboardShortcut(key: "k", modifiers: [.command, .shift], targetBundleID: "com.apple.TextEdit").validate())
        XCTAssertThrowsError(try KeyboardShortcut(key: "rm -rf", modifiers: []).validate())
        XCTAssertThrowsError(try KeyboardShortcut(key: "k", modifiers: [.command, .command]).validate())
        XCTAssertThrowsError(try DeckAction.launchApp(bundleID: "/bin/sh").validate())
        XCTAssertThrowsError(try DeckAction.shortcut(identifier: "--output-path").validate())
        XCTAssertThrowsError(try DeckAction.volume(.set(.nan)).validate())
    }
    func testLayoutPersistenceAndMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LayoutStore(directory: directory), mac = UUID()
        var layout = DeckLayout(macID: mac)
        layout.pages.append(DeckPage(name: "Work", tiles: [Tile(name: "Search", symbol: "globe", action: .website(url: "https://example.com"))]))
        layout.settings.theme = .dark
        try store.save(layout); XCTAssertEqual(try store.load(macID: mac), layout)
        XCTAssertNotEqual(try store.load(macID: UUID()).macID, mac)
        struct Legacy: Encodable { let schemaVersion = 1; let macID: UUID; let pages: [DeckPage] }
        let migrated = try LayoutStore.decode(JSONEncoder().encode(Legacy(macID: mac, pages: layout.pages)))
        XCTAssertEqual(migrated.schemaVersion, 4); XCTAssertEqual(migrated.pages, layout.pages); XCTAssertEqual(migrated.settings.theme, .system)
        layout.schemaVersion = 99
        XCTAssertThrowsError(try LayoutStore.decode(JSONEncoder().encode(layout)))
        XCTAssertEqual(try store.load(macID: mac).schemaVersion, 4)
    }
    func testInvalidLayoutIDsAndConnectionActions() throws {
        var layout = DeckLayout(macID: UUID()); layout.pages.append(layout.pages[0])
        XCTAssertThrowsError(try LayoutStore.decode(JSONEncoder().encode(layout)))
        XCTAssertTrue(ConnectionState.connected.permitsActions)
        for state: ConnectionState in [.offline, .connecting, .searching, .awaitingApproval, .permissionDenied, .paused] { XCTAssertFalse(state.permitsActions) }
        XCTAssertTrue(QuickTileError.disconnected.localizedDescription.contains("not be retried"))
    }
}
