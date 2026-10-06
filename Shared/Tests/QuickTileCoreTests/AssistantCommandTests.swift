import XCTest
@testable import QuickTileCore

final class AssistantCommandTests: XCTestCase {
    private let safari = AppEntry(id: "com.apple.Safari", name: "Safari")
    private let xcode = AppEntry(id: "com.apple.dt.Xcode", name: "Xcode")
    private func plan(_ text: String, _ context: AssistantCommandContext = .init(), file: StaticString = #filePath, line: UInt = #line) throws -> AssistantCommandPlan {
        let result = AssistantCommandParser.parse(text, context: context)
        guard case .plan(let plan) = result else { XCTFail("Expected a plan for \(text): \(result)", file: file, line: line); throw QuickTileError.failed("No plan") }
        return plan
    }
    private func assertUnsupported(_ text: String, _ context: AssistantCommandContext = .init(), file: StaticString = #filePath, line: UInt = #line) {
        guard case .unsupported(let message) = AssistantCommandParser.parse(text, context: context) else {
            return XCTFail("Expected unsupported: \(text)", file: file, line: line)
        }
        XCTAssertFalse(message.isEmpty, file: file, line: line)
    }
    func testAppResolutionUsesCatalogAndTypoMatch() throws {
        let context = AssistantCommandContext(apps: [safari, xcode])
        XCTAssertEqual(try plan("Please open Safri", context).action, .launchApp(bundleID: safari.id))
        XCTAssertEqual(try plan("launch com.apple.Safari", context).targetBundleID, safari.id)
        assertUnsupported("open Uninstalled App", context)
        assertUnsupported("open com.fake.Invented", context)
    }
    func testAmbiguousAppAndVersionRequireSelection() throws {
        let code = AppEntry(id: "com.microsoft.VSCode", name: "Visual Studio Code")
        let context = AssistantCommandContext(apps: [xcode, code])
        guard case .choices(_, let choices) = AssistantCommandParser.parse("open code", context: context) else { return XCTFail("Ambiguous code must not silently choose Xcode") }
        XCTAssertEqual(Set(choices.compactMap(\.targetBundleID)), [xcode.id, code.id])
        let variants = [AppEntry(id: "com.apple.FinalCut", name: "Final Cut Pro"), AppEntry(id: "com.apple.FinalCutApp", name: "Final Cut Pro Trial")]
        guard case .choices(_, let versions) = AssistantCommandParser.parse("launch FCP", context: .init(apps: variants)) else { return XCTFail("An alias must ask about installed variants") }
        XCTAssertEqual(versions.count, 2)
    }
    func testAbsolutePercentagesRejectInvalidValues() throws {
        XCTAssertEqual(try plan("set volume to 50%").controlValue, 0.5)
        XCTAssertEqual(try plan("volume twenty five percent").controlValue, 0.25)
        XCTAssertEqual(try plan("set volume to zero").controlValue, 0)
        XCTAssertEqual(try plan("set volume to one hundred").controlValue, 1)
        for command in ["volume -1", "volume 101", "volume NaN", "volume infinity", "volume 50 and delete files"] { assertUnsupported(command) }
    }
    func testRelativeControlsRequireStateAndClamp() throws {
        let context = AssistantCommandContext(controls: .init(volume: 0.95, brightness: 0.05, displayID: 42, displayName: "Built-in"))
        XCTAssertEqual(try plan("increase volume by 20 percent", context).controlValue, 1)
        let brightness = try plan("brightness down by 20 percentage points", context)
        XCTAssertEqual(brightness.controlValue, 0)
        XCTAssertEqual(brightness.displayID, 42)
        XCTAssertEqual(try plan("volume down", context).controlValue ?? -1, 0.85, accuracy: 0.0001)
        assertUnsupported("volume up")
        assertUnsupported("brightness down", .init(controls: .init(volume: nil, brightness: .nan, displayID: 42, displayName: nil)))
        assertUnsupported("increase volume by -5", context)
    }
    func testBrightnessRequiresSelectedDisplay() throws {
        assertUnsupported("set brightness to 40 percent")
        let context = AssistantCommandContext(controls: .init(volume: nil, brightness: 0.5, displayID: 7, displayName: "Monitor"))
        let result = try plan("set brightness to 40 percent", context)
        XCTAssertEqual(result.action, .dial(.brightness)); XCTAssertEqual(result.controlValue, 0.4); XCTAssertEqual(result.displayID, 7)
    }
    func testMuteAndAppearanceRetainDesiredState() throws {
        XCTAssertEqual(try plan("mute").desiredMuted, true)
        XCTAssertEqual(try plan("unmute").desiredMuted, false)
        XCTAssertEqual(try plan("enable dark mode").desiredDarkMode, true)
        XCTAssertEqual(try plan("switch to light mode").desiredDarkMode, false)
        XCTAssertNil(try plan("toggle appearance").desiredDarkMode)
    }
    func testPlaybackDoesNotGuessUnknownSystemStateOrWrongPlayer() throws {
        assertUnsupported("pause music")
        let known = AssistantCommandContext(playback: [.init(target: "system", state: .playing)])
        XCTAssertEqual(try plan("pause music", known).desiredPlayback, .paused)
        XCTAssertEqual(try plan("toggle playback").action, .media(.playPause))
        XCTAssertEqual(try plan("next track").action, .media(.next))
        assertUnsupported("pause Firefox", known)
        assertUnsupported("pause Spotify")
        let spotify = AssistantCommandContext(apps: [.init(id: MediaPlayer.spotify.rawValue, name: "Spotify")])
        let result = try plan("pause in Spotify", spotify)
        XCTAssertEqual(result.targetBundleID, MediaPlayer.spotify.rawValue); XCTAssertEqual(result.desiredPlayback, .paused)
        assertUnsupported("next track in Safari", .init(apps: [safari]))
    }
    func testWebsitesKeepExplicitPrivatePathWithoutFabrication() throws {
        let url = "https://example.com/private/Account?token=AbC%20123#section"
        XCTAssertEqual(try plan("open website " + url).action, .website(url: url))
        for command in ["open website example.com", "visit my bank", "open http://example.com", "open file:///etc/passwd", "open javascript:alert(1)", "open https://user:pass@example.com", "open https://example.com and launch Terminal"] { assertUnsupported(command) }
    }
    func testShortcutsUseCatalogIDsAndAskAboutDuplicateNames() throws {
        let a = ShortcutEntry(id: UUID().uuidString, name: "Daily backup")
        let b = ShortcutEntry(id: UUID().uuidString, name: "Daily backup")
        XCTAssertEqual(try plan("run Apple Shortcut Daily backup", .init(shortcuts: [a])).action, .shortcut(identifier: a.id))
        guard case .choices(_, let choices) = AssistantCommandParser.parse("run shortcut Daily backup", context: .init(shortcuts: [a, b])) else { return XCTFail("Duplicate names need selection") }
        XCTAssertEqual(choices.count, 2)
        assertUnsupported("run shortcut Invented", .init(shortcuts: [a]))
        assertUnsupported("run shortcut Fake", .init(shortcuts: [.init(id: "/bin/sh", name: "Fake")]))
    }
    func testPresetsResolveInstalledProfileAndNeverWrongApp() throws {
        let fcp = AppEntry(id: "com.apple.FinalCutApp", name: "Final Cut Pro")
        let result = try plan("split clip in Final Cut Pro", .init(apps: [fcp, safari]))
        XCTAssertEqual(result.action, .preset("finalcut.split")); XCTAssertEqual(result.targetBundleID, fcp.id)
        assertUnsupported("split clip in Safari", .init(apps: [fcp, safari]))
        assertUnsupported("split clip")
        assertUnsupported("export in Photoshop", .init(apps: [fcp]))
        let save = try plan("save in Safari", .init(apps: [safari]))
        guard case .keyboard(let key) = save.action else { return XCTFail("Expected targeted existing key mapping") }
        XCTAssertEqual(key.targetBundleID, safari.id)
    }
    func testSupportedSystemActionsAndUnsafeCommands() throws {
        XCTAssertEqual(try plan("lock my Mac").action, .system(.lock))
        XCTAssertEqual(try plan("show desktop").action, .system(.showDesktop))
        XCTAssertEqual(try plan("take a screenshot").action, .system(.screenshot))
        for text in ["run shell rm -rf /", "sudo reboot", "set wifi off", "delete Downloads", "open Safari; rm -rf /", "open $(touch /tmp/a)", "lock screen and erase disk", "open Safari\nrun shell echo hi"] { assertUnsupported(text, .init(apps: [safari])) }
    }
    func testPlanCodableRoundTripPreservesStateAndDeterminism() throws {
        let context = AssistantCommandContext(controls: .init(volume: 0.5, brightness: 0.5, displayID: 99, displayName: "Built-in"))
        let result = try plan("increase brightness by 10 percent", context)
        XCTAssertEqual(result, try plan("increase brightness by 10 percent", context))
        XCTAssertEqual(try JSONDecoder().decode(AssistantCommandPlan.self, from: JSONEncoder().encode(result)), result)
        let appearance = try plan("enable dark mode")
        XCTAssertEqual(try JSONDecoder().decode(AssistantCommandPlan.self, from: JSONEncoder().encode(appearance)), appearance)
    }
}
