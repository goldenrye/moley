import XCTest

final class MoleyUITests: XCTestCase {
    func testSetupAndInvalidImport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let setup = app.buttons["setupButton"]
        XCTAssertTrue(setup.waitForExistence(timeout: 15))
        setup.tap()
        XCTAssertTrue(app.buttons["chooseFileButton"].waitForExistence(timeout: 5))
        let reveal = app.switches["revealConfiguration"]
        // SwiftUI exposes the row and the actual toggle as separate switches.
        reveal.switches.firstMatch.tap()
        XCTAssertEqual(reveal.value as? String, "1", app.debugDescription)
        let editor = app.textViews["configurationEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), app.debugDescription)
        editor.tap()
        editor.typeText("invalid configuration")
        app.swipeUp()
        app.buttons["saveConfiguration"].tap()
        XCTAssertTrue(app.alerts["Check your configuration"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Invalid configuration structure on line 1."].exists)
    }
}
