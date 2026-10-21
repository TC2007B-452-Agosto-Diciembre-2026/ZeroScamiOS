//
//  AutenticacionUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class AutenticacionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testRegistroValidaYLlevaALogin() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        let crear = app.buttons["registro.crear"]
        XCTAssertTrue(crear.waitForExistence(timeout: 10))
        capturar(app, "01-registro")

        app.textFields["registro.nombre"].escribir("Lucía")
        app.textFields["registro.apellido"].escribir("Torres")
        app.textFields["registro.alias"].escribir("lucia_t")
        app.textFields["registro.correo"].escribir("correo-malo")
        app.secureTextFields["registro.contrasena"].escribir("password123")
        app.secureTextFields["registro.confirmacion"].escribir("password123")
        XCTAssertFalse(crear.isEnabled)
        // FieldError antepone «Error: » a su etiqueta de VoiceOver, por eso se busca por contenido.
        XCTAssertTrue(app.elemento(contiene: "Escribe un correo válido, por ejemplo nombre@dominio.com.").exists)
        XCTAssertTrue(app.elemento(contiene: "Esa contraseña es muy común; elige otra.").exists)
        capturar(app, "02-registro-errores")

        app.textFields["registro.correo"].reemplazar("lucia@comunidad.test")
        app.secureTextFields["registro.contrasena"].reemplazar("Fraude0-Cero")
        app.secureTextFields["registro.confirmacion"].reemplazar("Fraude0-Cero")
        app.buttons["registro.aviso"].tocar(en: app)
        XCTAssertTrue(crear.isEnabled)
        crear.tocar(en: app)

        XCTAssertTrue(app.elemento(contiene: "Cuenta creada. Inicia sesión para continuar.").waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["login.correo"].value as? String, "lucia@comunidad.test")
    }

    @MainActor
    func testElAvisoDePrivacidadSeAbreDesdeRegistro() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.buttons["registro.leerAviso"].tocar(en: app)
        XCTAssertTrue(app.staticTexts["Aviso de privacidad"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLoginIncorrectoYBloqueo() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.irALogin()
        let correo = app.textFields["login.correo"]
        XCTAssertTrue(correo.waitForExistence(timeout: 5))
        correo.escribir("usuario@0fraude.mx")
        for intento in 1...5 {
            app.secureTextFields["login.contrasena"].escribir("incorrecta\(intento)")
            app.buttons["login.entrar"].tap()
            _ = app.staticTexts["login.error"].waitForExistence(timeout: 5)
        }
        XCTAssertTrue(app.staticTexts["login.error"].label.hasPrefix("Demasiados intentos"))
        XCTAssertFalse(app.buttons["login.entrar"].isEnabled)
        XCTAssertTrue(app.buttons["login.entrar"].label.hasPrefix("ESPERA"))
        capturar(app, "03-login-bloqueado")
    }

    /// Return con la contraseña vacía no manda ningún intento: tras 4 fallos más un Return vacío,
    /// el botón sigue libre y solo el 5º intento real bloquea.
    @MainActor
    func testReturnConContrasenaVaciaNoCuentaComoIntento() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.irALogin()
        let correo = app.textFields["login.correo"]
        XCTAssertTrue(correo.waitForExistence(timeout: 5))
        correo.escribir("usuario@0fraude.mx")
        for intento in 1...4 {
            app.secureTextFields["login.contrasena"].escribir("incorrecta\(intento)")
            app.buttons["login.entrar"].tap()
            _ = app.staticTexts["login.error"].waitForExistence(timeout: 5)
        }
        XCTAssertEqual(app.staticTexts["login.error"].label, "Correo o contraseña incorrectos.")
        let campo = app.secureTextFields["login.contrasena"]
        campo.tap()
        campo.typeText("\n")
        // Si el Return hubiera contado como 5º fallo, el botón pasaría a «ESPERA ...».
        let bloqueo = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'ESPERA'"),
                                                object: app.buttons["login.entrar"])
        bloqueo.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [bloqueo], timeout: 2), .completed)
        XCTAssertEqual(app.staticTexts["login.error"].label, "Correo o contraseña incorrectos.")

        campo.escribir("incorrecta5")
        app.buttons["login.entrar"].tap()
        let quintoFallo = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Demasiados intentos'"),
                                                    object: app.staticTexts["login.error"])
        XCTAssertEqual(XCTWaiter.wait(for: [quintoFallo], timeout: 10), .completed, "El 5º intento real debía bloquear")
    }

    @MainActor
    func testLoginCorrectoPersisteSesion() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.terminate()
        let otraVez = XCUIApplication.zeroScam(reiniciar: false)
        otraVez.launch()
        XCTAssertTrue(otraVez.tabBars.buttons["Inicio"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testCerrarSesion() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.ajustes"].tap()
        app.buttons["ajustes.cerrarSesion"].tocar(en: app)
        app.buttons["salir.cancelar"].tap()
        XCTAssertTrue(app.buttons["ajustes.cerrarSesion"].waitForExistence(timeout: 5))
        app.buttons["ajustes.cerrarSesion"].tocar(en: app)
        app.buttons["salir.confirmar"].tap()
        XCTAssertTrue(app.buttons["registro.crear"].waitForExistence(timeout: 10))
        app.terminate()
        let otraVez = XCUIApplication.zeroScam(reiniciar: false)
        otraVez.launch()
        XCTAssertTrue(otraVez.buttons["registro.crear"].waitForExistence(timeout: 10))
    }
}
