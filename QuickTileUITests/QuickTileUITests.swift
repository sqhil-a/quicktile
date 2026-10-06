import XCTest

final class QuickTileUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(_ arguments: [String] = ["--ui-testing-full-deck"]) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = arguments; app.launch()
        XCTAssertTrue(app.buttons["editDeck"].waitForExistence(timeout: 10)); return app
    }
    @MainActor private func boards(_ app: XCUIApplication) {
        app.buttons["pageMenu"].tap()
        XCTAssertTrue(app.buttons["Manage boards"].waitForExistence(timeout: 4)); app.buttons["Manage boards"].tap()
        XCTAssertTrue(app.buttons["presetBoards"].waitForExistence(timeout: 4))
    }
    @MainActor func testEightIconOnlyTilesFitAndPagesSlideBack() {
        let app = launch(); defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let names = ["Safari", "Mail", "Calendar", "Notes", "Music", "Messages", "Photos", "Settings"]
            let tiles = names.map { app.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH 'deck-tile-'", $0)).firstMatch }
            XCTAssertTrue(tiles.last!.waitForExistence(timeout: 5))
            for tile in tiles { XCTAssertTrue(tile.isHittable); XCTAssertTrue(app.windows.firstMatch.frame.contains(tile.frame)); XCTAssertEqual(tile.staticTexts.count, 0); XCTAssertGreaterThanOrEqual(tile.frame.height, 44) }
            let columns = orientation == .portrait ? 2 : 4
            XCTAssertEqual(tiles[0].frame.minY, tiles[columns - 1].frame.minY, accuracy: 2)
            XCTAssertGreaterThan(tiles[columns].frame.minY, tiles[0].frame.maxY)
            screenshot("grid-\(orientation.rawValue)")
        }
        XCUIDevice.shared.orientation = .portrait
        let pager = app.scrollViews["deckPager"]
        pager.swipeLeft(); XCTAssertTrue(app.buttons["TextEdit"].waitForExistence(timeout: 5))
        pager.swipeRight(); XCTAssertTrue(app.buttons["Safari"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["Safari"].isHittable)
    }
    @MainActor func testHoldDragEditingRemovalAndUndo() {
        let app = launch()
        let safari = app.buttons["Safari"], mail = app.buttons["Mail"]
        let destination = mail.frame
        safari.press(forDuration: 0.65, thenDragTo: mail)
        XCTAssertTrue(app.buttons["Done editing"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["QuickTile"].exists)
        XCTAssertTrue(app.buttons["Edit Safari"].exists)
        XCTAssertEqual(app.buttons["Edit Safari"].frame.midX, destination.midX, accuracy: 5)
        XCTAssertEqual(app.buttons["Edit Safari"].frame.midY, destination.midY, accuracy: 5)
        app.buttons["Remove Mail"].tap()
        XCTAssertTrue(app.buttons["Undo removal"].waitForExistence(timeout: 3)); app.buttons["Undo removal"].tap()
        XCTAssertTrue(app.buttons["Remove Mail"].waitForExistence(timeout: 3))
        app.scrollViews["deckPager"].swipeLeft()
        XCTAssertTrue(app.buttons["Edit Safari"].isHittable, "Editing stays on the current page until Done.")
        screenshot("inline-editing")
        app.buttons["editDeck"].tap(); XCTAssertFalse(app.buttons["Remove Safari"].exists)
    }
    @MainActor func testUndoRestoresMultipleTilesAndClearsOnDone() {
        let app = launch()
        app.buttons["editDeck"].tap()
        app.buttons["Remove Safari"].tap()
        app.buttons["Remove Mail"].tap()
        app.buttons["Undo removal"].tap()
        XCTAssertTrue(app.buttons["Remove Mail"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Remove Safari"].exists)
        XCTAssertTrue(app.buttons["Undo removal"].exists)
        app.buttons["Undo removal"].tap()
        XCTAssertTrue(app.buttons["Remove Safari"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Undo removal"].exists)
        app.buttons["Remove Notes"].tap()
        XCTAssertTrue(app.buttons["Undo removal"].exists)
        app.buttons["editDeck"].tap()
        XCTAssertTrue(app.buttons["Undo removal"].waitForNonExistence(timeout: 3))
        app.buttons["editDeck"].tap()
        XCTAssertFalse(app.buttons["Undo removal"].exists)
        XCTAssertFalse(app.buttons["Remove Notes"].exists)
    }
    @MainActor func testEditingTapOpensConfigurationAndShowsTestFailureInline() {
        let app = launch()
        app.buttons["editDeck"].tap()
        app.buttons["Edit Safari"].tap()
        XCTAssertTrue(app.navigationBars["Edit tile"].waitForExistence(timeout: 4))
        if !app.buttons["Test action"].isHittable { app.swipeUp() }
        app.buttons["Test action"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["testResult"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Connect to your Mac")).firstMatch.exists)
        app.navigationBars["Edit tile"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Done editing"].exists)
    }
    @MainActor func testPrivacyPolicyIsAvailableWithoutConnection() {
        let app = launch(); app.buttons["settings"].tap()
        if !app.buttons["privacyPolicy"].isHittable { app.swipeUp() }
        app.buttons["privacyPolicy"].tap()
        XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["On your devices"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "encrypted local connection")).firstMatch.exists)
    }
    @MainActor func testPresetBoardsAndBoardIcon() {
        let app = launch(["--ui-testing-deck"]); boards(app)
        app.buttons["presetBoards"].tap(); app.buttons["preset-board-finalcut"].tap()
        XCTAssertTrue(app.staticTexts["Cut"].waitForExistence(timeout: 4))
        app.buttons["addPresetBoard"].tap(); app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["page-Final Cut Pro"].waitForExistence(timeout: 4)); app.buttons["page-Final Cut Pro"].tap()
        app.buttons["boardIcon"].tap(); app.buttons["Choose symbol"].tap(); app.buttons["Use briefcase icon"].tap()
        XCTAssertTrue(app.buttons["Use briefcase icon"].isSelected)
    }
    @MainActor func testBottomBoardPickerManagesAndSwitchesBothWays() {
        let app = launch(); boards(app)
        app.buttons["addPage"].tap()
        app.alerts["New board"].textFields.firstMatch.tap()
        app.alerts["New board"].textFields.firstMatch.typeText("Work")
        app.alerts["New board"].buttons["Add"].tap()
        XCTAssertTrue(app.buttons["page-Work"].waitForExistence(timeout: 4))
        app.navigationBars["Boards"].buttons["Done"].tap()
        app.buttons["pageMenu"].tap()
        let work = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'choose-page-' AND label CONTAINS 'Work'")).firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 4)); work.tap()
        XCTAssertTrue(app.buttons["emptyEditDeck"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["pageMenu"].label.contains("Work"))
        app.buttons["pageMenu"].tap()
        let original = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'choose-page-' AND label CONTAINS 'My board'")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 4)); original.tap()
        XCTAssertTrue(app.buttons["Safari"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Safari"].isHittable)
        boards(app)
        XCTAssertTrue(app.buttons["page-Work"].exists)
    }
    @MainActor func testCategoryNavigationAndTimer() {
        let app = launch(); app.buttons["editDeck"].tap(); app.buttons["Remove Safari"].tap(); app.buttons["Add tile in slot 1"].tap()
        if !app.buttons["Video editing"].exists { app.swipeUp() }
        app.buttons["Video editing"].tap(); app.buttons["video-app-After Effects"].tap()
        XCTAssertTrue(app.buttons["library-action-aftereffects.play"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap(); app.navigationBars.buttons.firstMatch.tap()
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("Timer")
        app.buttons["library-action-timer"].tap()
        app.buttons["timerHapticPicker"].tap(); app.buttons["Double click"].tap()
        XCTAssertTrue(app.buttons["Preview haptic"].isEnabled)
        app.buttons["saveTile"].tap(); app.buttons["editDeck"].tap()
        XCTAssertTrue(app.buttons["Start timer"].waitForExistence(timeout: 4)); app.buttons["Start timer"].tap()
        XCTAssertTrue(app.buttons["Pause timer"].waitForExistence(timeout: 3)); app.buttons["Pause timer"].tap(); app.buttons["Reset timer"].tap()
        XCTAssertTrue(app.buttons["Reset timer"].waitForNonExistence(timeout: 3))
    }
    @MainActor func testAgentQuestionReplySheetUsesChoicesAndReturnsToRunning() {
        let app = launch(["--ui-testing-full-deck","--ui-testing-agent-requests"])
        app.buttons.matching(NSPredicate(format:"label == %@", "Codex, Waiting for input")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Which app should be used to create the file?"].waitForExistence(timeout:3))
        XCTAssertFalse(app.buttons["Send answer"].isEnabled)
        app.buttons.containing(.staticText,identifier:"Xcode").firstMatch.tap()
        XCTAssertTrue(app.buttons["Send answer"].isEnabled)
        screenshot("codex-request-sheet")
        app.buttons["Send answer"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label == %@", "Codex, Running")).firstMatch.waitForExistence(timeout:3))
    }
    @MainActor func testAssistantRecordingPresentationStopsAndCancelsWithoutChangingBoards() {
        let app = launch(["--ui-testing-full-deck", "--ui-testing-assistant"])
        app.buttons["assistantTile"].tap()
        XCTAssertEqual(app.buttons["assistantTile"].label, "Stop recording and send command")
        XCTAssertFalse(app.buttons["pageMenu"].isEnabled)
        screenshot("assistant-waveform")
        app.buttons["assistantTile"].tap()
        XCTAssertEqual(app.buttons["assistantTile"].label, "Cancel assistant request")
        app.buttons["assistantTile"].tap()
        XCTAssertEqual(app.buttons["assistantTile"].label, "Assistant. Record a voice command")
        XCTAssertTrue(app.buttons["pageMenu"].isEnabled)
        app.buttons["assistantTile"].tap(); app.buttons["editDeck"].tap()
        XCTAssertTrue(app.buttons["Edit Assistant"].exists)
        app.buttons["editDeck"].tap()
        XCTAssertEqual(app.buttons["assistantTile"].label, "Assistant. Record a voice command")
    }
    @MainActor func testAssistantTileAddsThroughLibraryAndExplainsOfflineState() {
        let app = launch(); app.buttons["editDeck"].tap(); app.buttons["Remove Safari"].tap(); app.buttons["Add tile in slot 1"].tap()
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("Assistant")
        XCTAssertTrue(app.buttons["library-action-assistant"].waitForExistence(timeout: 3)); app.buttons["library-action-assistant"].tap()
        XCTAssertTrue(app.staticTexts["Tap to speak. Tap again to send your command."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Choose symbol"].exists)
        app.buttons["saveTile"].tap(); app.buttons["editDeck"].tap()
        XCTAssertTrue(app.buttons["assistantTile"].waitForExistence(timeout: 3))
        let frame = app.buttons["assistantTile"].frame
        app.buttons["assistantTile"].tap()
        XCTAssertTrue(app.staticTexts["Connect to your Mac."].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["assistantTile"].frame.minY, frame.minY, accuracy: 1)
        XCTAssertTrue(app.buttons["dismissNotice"].isHittable)
        screenshot("floating-notice")
        app.buttons["dismissNotice"].tap()
        XCTAssertTrue(app.staticTexts["Connect to your Mac."].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.alerts["Use Groq for voice commands?"].exists)
    }
    @MainActor func testSequenceConfigurationUsesForwardNavigation() {
        let app = launch(); app.buttons["editDeck"].tap(); app.buttons["Remove Safari"].tap(); app.buttons["Add tile in slot 1"].tap()
        app.swipeUp(); app.buttons["library-action-sequence"].tap()
        XCTAssertTrue(app.buttons["Add step"].waitForExistence(timeout: 3)); app.buttons["Add step"].tap()
        XCTAssertTrue(app.navigationBars["Sequence step"].waitForExistence(timeout: 3))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "identifier is invalid")).firstMatch.waitForExistence(timeout: 3))
    }
    @MainActor func testLargeCatalogFindsLastEntry() {
        let app = launch(["--ui-testing-large-catalog"]); app.buttons["editDeck"].tap(); app.buttons["Add tile in slot 1"].tap()
        app.buttons["Apps & links"].tap(); app.buttons["library-action-app"].tap(); app.buttons["Choose a Mac app"].tap()
        XCTAssertTrue(app.buttons["catalog-choice-test.app.0"].waitForExistence(timeout: 4))
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("1499")
        XCTAssertTrue(app.buttons["catalog-choice-test.app.1499"].waitForExistence(timeout: 4)); app.buttons["catalog-choice-test.app.1499"].tap()
        XCTAssertEqual(app.textFields["tileName"].value as? String, "Application 1499")
    }
    @MainActor func testPreviewIsClearlyLabeledAndNeverExecutes() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing-onboarding"]; app.launch()
        app.buttons["previewBoard"].tap(); XCTAssertTrue(app.staticTexts["Preview"].waitForExistence(timeout: 3))
        app.buttons["Safari"].tap(); XCTAssertTrue(app.staticTexts["Action status: Preview only"].waitForExistence(timeout: 2)); XCTAssertFalse(app.alerts["QuickTile"].exists)
    }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
