//
//  ArranqueUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class ArranqueUITests: XCTestCase {
    @MainActor
    func testArrancaEnRegistro() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        XCTAssertTrue(app.buttons["CREAR CUENTA"].waitForExistence(timeout: 10))
    }
}
