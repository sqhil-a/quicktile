import XCTest
@testable import QuickTileCore

final class ActionContractTests: XCTestCase {
    func testGameBoardsResolveInstalledEditorsAndKeepEightSlots() throws {
        let apps = [AppEntry(id: "com.unity3d.UnityEditor5.x", name: "Unity"), AppEntry(id: "org.godotengine.godot.mono", name: "Godot .NET"), AppEntry(id: "com.epicgames.UE4Editor", name: "Unreal Editor")]
        for id in ["unity", "godot", "unreal"] {
            let board = try XCTUnwrap(PresetBoards.board(id: id))
            XCTAssertEqual(board.pages.count, 2)
            let layout = board.makePage(apps: apps)
            XCTAssertEqual(layout.tileOrder?.count, 16)
            for tile in layout.tiles {
                XCTAssertTrue(apps.contains { $0.id == tile.targetBundleID })
                guard case .preset(let actionID) = tile.action else { return XCTFail("Expected engine preset") }
                XCTAssertEqual(ActionLibrary.preset(id: actionID)?.category, .game)
            }
        }
        XCTAssertEqual(ActionLibrary.preset(id: "godot.play")?.shortcut?.key, "b")
        XCTAssertEqual(ActionLibrary.preset(id: "godot.play")?.shortcut?.modifiers, [.command])
        XCTAssertEqual(ActionLibrary.preset(id: "unity.play")?.shortcut?.modifiers, [.command])
        XCTAssertEqual(ActionLibrary.preset(id: "unreal.play")?.shortcut?.modifiers, [.option])
    }
    func testProfileResolutionUsesInstalledVariantsAndValidatedPreferences() {
        let apps = [AppEntry(id: "com.apple.FinalCutApp", name: "Final Cut Pro"), AppEntry(id: "com.adobe.PremierePro.26", name: "Premiere Pro 2026"), AppEntry(id: "other.app", name: "Other")]
        XCTAssertEqual(AppProfiles.resolve(bundleID: "com.apple.FinalCut", apps: apps)?.id, "com.apple.FinalCutApp")
        XCTAssertEqual(AppProfiles.resolve(bundleID: "com.adobe.PremierePro", apps: apps)?.id, "com.adobe.PremierePro.26")
        XCTAssertEqual(AppProfiles.resolve(bundleID: "com.apple.FinalCut", apps: apps, preferredBundleID: "other.app")?.id, "com.apple.FinalCutApp")
        XCTAssertNil(AppProfiles.resolve(bundleID: "missing.app", apps: apps))
    }
    func testSequenceRequiresExplicitTargetsAndEnforcesBounds() throws {
        XCTAssertThrowsError(try ActionSequence(steps: []).validate())
        XCTAssertThrowsError(try ActionSequence(steps: [.keyboard(.init(key: "s", modifiers: [.command]))]).validate())
        XCTAssertThrowsError(try ActionSequence(steps: [.wait(seconds: 11)]).validate())
        XCTAssertThrowsError(try ActionSequence(steps: Array(repeating: .wait(seconds: 1), count: 13)).validate())
        XCTAssertNoThrow(try ActionSequence(steps: [.launchApp(bundleID: "com.apple.dt.Xcode"), .keyboard(.init(key: "b", modifiers: [.command], targetBundleID: "com.apple.dt.Xcode")), .wait(seconds: 0.5)]).validate())
    }
    func testPresetPagesReferenceRealActionsAndAlwaysHaveEightSlots() {
        let available = Set(ActionLibrary.actions.map(\.id))
        for board in PresetBoards.boards {
            for page in board.pages { for id in page.actionIDs { XCTAssertTrue(available.contains(id), "Missing action \(id) in \(board.title)/\(page.name)") } }
            XCTAssertEqual(board.makePage().slots.count, board.pages.count * 8)
            XCTAssertEqual(board.makePage().tiles.count, board.pages.reduce(0) { $0 + $1.actionIDs.count })
        }
    }
    func testLegacyProtocolAndCustomizedMappingsRoundTrip() throws {
        let legacy = Data(#"{"status":"completed","message":"Sent"}"#.utf8)
        let result = try JSONDecoder().decode(ActionResult.self, from: legacy)
        XCTAssertNil(result.outcome); XCTAssertNil(result.sequenceProgress)
        var tile = Tile(name: "Build", symbol: "hammer", action: .preset("xcode.build"))
        tile.configuredShortcut = .init(key: "b", modifiers: [.command, .shift], targetBundleID: "com.apple.dt.Xcode")
        tile.targetBundleID = "com.apple.dt.Xcode"; tile.mappingVersion = 1
        tile.symbol = tile.displaySymbol
        let restored = try LayoutStore.decode(JSONEncoder().encode(DeckLayout(macID: UUID(), pages: [DeckPage(tiles: [tile])])))
        XCTAssertEqual(restored.pages[0].tiles.first, tile)
    }
}
