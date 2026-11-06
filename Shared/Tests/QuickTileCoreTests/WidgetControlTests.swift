import XCTest
@testable import QuickTileCore

final class WidgetControlTests: XCTestCase {
    func testDialStepsUseFreshObservedLevelAndClampLimits() throws {
        XCTAssertEqual(try WidgetControlPolicy.adjustedLevel(current: 0.99, step: 5), 1)
        XCTAssertEqual(try WidgetControlPolicy.adjustedLevel(current: 0.01, step: -5), 0)
        XCTAssertEqual(try WidgetControlPolicy.adjustedLevel(current: 0.6, step: -5), 0.55, accuracy: 0.0001)
        for invalid in [Double.nan, .infinity, -0.01, 1.01] {
            XCTAssertThrowsError(try WidgetControlPolicy.adjustedLevel(current: invalid, step: 5))
        }
        XCTAssertThrowsError(try WidgetControlPolicy.adjustedLevel(current: 0.5, step: 100))
    }
    func testLongAndInteractiveActionsRequireForegroundInsteadOfBackgroundTimeout() {
        XCTAssertTrue(WidgetControlPolicy.requiresApp(.assistant))
        XCTAssertTrue(WidgetControlPolicy.requiresApp(.timer(seconds: 60)))
        XCTAssertTrue(WidgetControlPolicy.requiresApp(.shortcut(identifier: UUID().uuidString)))
        XCTAssertTrue(WidgetControlPolicy.requiresApp(.agent(.codex)))
        XCTAssertFalse(WidgetControlPolicy.requiresApp(.launchApp(bundleID: "com.apple.Safari")))
        XCTAssertFalse(WidgetControlPolicy.requiresApp(.website(url: "https://www.youtube.com")))
        XCTAssertFalse(WidgetControlPolicy.requiresApp(.preset("unity.play")))
        XCTAssertFalse(WidgetControlPolicy.requiresApp(.dial(.brightness)))
    }
}
