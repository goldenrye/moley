import XCTest

final class MoleyUITests: XCTestCase {
    func testScannerUnavailableCanCancelWithoutImporting() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("The unavailable-camera path is specific to the simulator.")
        #endif
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["setupButton"].waitForExistence(timeout: 15))
        app.buttons["setupButton"].tap()
        let scan = app.buttons["scanQRButton"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        let message = app.staticTexts["qrScannerMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("physical iPhone or iPad"))
        app.buttons["cancelQRScanner"].tap()
        XCTAssertTrue(app.buttons["chooseFileButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No configuration selected"].exists)
        app.swipeUp()
        XCTAssertFalse(app.buttons["saveConfiguration"].isEnabled)
    }

    func testSetupAndInvalidImport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let setup = app.buttons["setupButton"]
        XCTAssertTrue(setup.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["sessionPolicy"].exists)
        setup.tap()
        XCTAssertTrue(app.buttons["chooseFileButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scanQRButton"].exists)
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
