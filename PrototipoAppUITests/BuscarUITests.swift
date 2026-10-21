//
//  BuscarUITests.swift
//  PrototipoAppUITests
//
//  Buscar muestra reportes desde que se abre (sin escribir nada), filtra por categoría y por
//  texto, y con texto grande los reportes se siguen pudiendo abrir.
//

import XCTest

@MainActor
final class BuscarUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func resultados(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'buscar.resultado.'"))
    }

    func testSinFiltrosMuestraReportesYFiltraPorCategoriaYTexto() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Buscar"].tap()

        XCTAssertTrue(resultados(app).firstMatch.waitForExistence(timeout: 10), "Buscar debe mostrar reportes sin filtros")
        XCTAssertFalse(app.buttons["buscar.limpiar"].exists)
        capturar(app, "buscar-1-recientes")

        let categoria = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'buscar.categoria.'")).firstMatch
        XCTAssertTrue(categoria.waitForExistence(timeout: 5))
        categoria.tap()
        XCTAssertTrue(app.buttons["buscar.limpiar"].waitForExistence(timeout: 5))
        capturar(app, "buscar-2-categoria")

        app.buttons["buscar.limpiar"].tap()
        let campo = app.textFields["buscar.campo"]
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.escribir("banco")
        XCTAssertTrue(app.buttons["buscar.borrarTexto"].waitForExistence(timeout: 5))
        XCTAssertTrue(resultados(app).firstMatch.waitForExistence(timeout: 10))
        capturar(app, "buscar-3-texto")

        resultados(app).firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))
    }

    func testConTextoGrandeLosReportesSeAbren() {
        let app = XCUIApplication.zeroScam(extra: ["-UIPreferredContentSizeCategoryName",
                                                   "UICTContentSizeCategoryAccessibilityL"])
        app.launch()
        app.entrar()
        capturar(app, "texto-grande-inicio")
        app.tabBars.buttons["Buscar"].tap()
        let primero = resultados(app).firstMatch
        XCTAssertTrue(primero.waitForExistence(timeout: 10))
        capturar(app, "texto-grande-buscar")
        // Con letra grande la tarjeta queda debajo de la barra de pestañas flotante: se sube hasta
        // que su parte de arriba se vea y se toca ahí.
        let pestanas = app.tabBars.firstMatch
        var intentos = 0
        while primero.frame.minY > pestanas.frame.minY - 160 && intentos < 10 {
            app.swipeUp(velocity: .slow)
            intentos += 1
        }
        primero.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 40)).tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))
        capturar(app, "texto-grande-detalle")
    }
}
