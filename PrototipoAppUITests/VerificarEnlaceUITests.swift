//
//  VerificarEnlaceUITests.swift
//  PrototipoAppUITests
//
//  Inicio → "¿Es legítimo este enlace?" → analizar → veredicto. Y el botón Actualizar de Inicio.
//

import XCTest

@MainActor
final class VerificarEnlaceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testVerificarUnEnlaceDaUnVeredicto() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()

        let tarjeta = app.buttons["inicio.verificarEnlace"]
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 5))
        tarjeta.tap()

        let campo = app.textFields["verificar.campo"]
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.escribir("no es un enlace")
        XCTAssertFalse(app.buttons["diagnostico.analizar"].exists)

        campo.reemplazar("https://banco-seguro-mx.xyz/acceso")
        let analizar = app.buttons["diagnostico.analizar"]
        XCTAssertTrue(analizar.waitForExistence(timeout: 5))
        analizar.tap()
        let veredicto = app.descendants(matching: .any)["diagnostico.veredicto"]
        XCTAssertTrue(veredicto.waitForExistence(timeout: 10))
        XCTAssertTrue(veredicto.label.hasPrefix("Veredicto:"))
    }

    func testActualizarEnInicio() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        let actualizar = app.buttons["inicio.actualizar"]
        XCTAssertTrue(actualizar.waitForExistence(timeout: 5))
        actualizar.tap()
        XCTAssertTrue(app.buttons["inicio.actualizar"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["inicio.actualizar"].label, "Actualizar reportes")
    }
}
