//
//  Ayudantes.swift
//  PrototipoAppUITests
//
//  Atajos de las pruebas de interfaz. La app se abre con -uiTesting (datos demo en otra carpeta,
//  otro servicio de Keychain y hash rápido) y, salvo que se pida lo contrario, -reiniciarDemo
//  (vuelve a la semilla). No necesita el permiso de Accesibilidad de macOS.
//

import XCTest

@MainActor
extension XCUIApplication {
    static func zeroScam(reiniciar: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (reiniciar ? ["-reiniciarDemo"] : []) + extra
        return app
    }

    /// Desde Registro, el enlace a Login (está al final del formulario). Un toque que cae mientras
    /// el desplazamiento automático todavía frena solo lo detiene, así que se intenta una vez más.
    func irALogin() {
        let irLogin = buttons["registro.irLogin"]
        guard irLogin.waitForExistence(timeout: 10) else { return }
        irLogin.tocar(en: self)
        if !textFields["login.correo"].waitForExistence(timeout: 3) && irLogin.exists { irLogin.tap() }
    }

    /// Desde Registro: va a Login, escribe y entra. Por defecto, la cuenta Usuario.
    func entrar(_ correo: String = "usuario@0fraude.mx", _ contrasena: String = "Alerta#2026mx") {
        irALogin()
        let campo = textFields["login.correo"]
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.reemplazar(correo)
        secureTextFields["login.contrasena"].escribir(contrasena)
        buttons["login.entrar"].tap()
        XCTAssertTrue(tabBars.buttons["Inicio"].waitForExistence(timeout: 15))
    }

    /// Regresa con la flecha de la barra hasta la raíz de la pestaña (ahí se ve el tab bar).
    func volverALaRaiz() {
        var intentos = 0
        while !tabBars.firstMatch.isHittable && navigationBars.buttons.firstMatch.exists && intentos < 8 {
            navigationBars.buttons.firstMatch.tap()
            intentos += 1
        }
    }

    /// Perfil → Ajustes → Cerrar sesión → confirmar (desde cualquier pantalla).
    func salir() {
        volverALaRaiz()
        tabBars.buttons["Perfil"].tap()
        buttons["perfil.ajustes"].tap()
        buttons["ajustes.cerrarSesion"].tocar(en: self)
        buttons["salir.confirmar"].tap()
        XCTAssertTrue(buttons["registro.crear"].waitForExistence(timeout: 10))
    }

    /// Cualquier elemento cuya etiqueta contenga el texto (las tarjetas combinan sus textos para VoiceOver).
    func elemento(contiene texto: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", texto)).firstMatch
    }
}

@MainActor
extension XCUIElement {
    /// Desliza hacia arriba hasta que el elemento se pueda tocar y lo toca.
    func tocar(en app: XCUIApplication, intentos: Int = 8) {
        var n = 0
        while !(exists && isHittable) && n < intentos {
            app.swipeUp()
            n += 1
        }
        tap()
    }

    func escribir(_ texto: String) {
        tap()
        typeText(texto)
    }

    /// Si el campo quedó detrás de la barra de navegación (el formulario ya se desplazó hacia
    /// abajo), desliza hacia abajo hasta que se vea: tocarlo ahí no le da el foco.
    func traerALaVista() {
        let app = XCUIApplication()
        let barra = app.navigationBars.firstMatch
        var intentos = 0
        while barra.exists && frame.minY < barra.frame.maxY && intentos < 5 {
            app.swipeDown()
            intentos += 1
        }
    }

    /// Borra lo que haya y escribe el texto nuevo.
    func reemplazar(_ texto: String) {
        traerALaVista()
        tap()
        if let actual = value as? String, !actual.isEmpty, actual != placeholderValue {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: actual.count))
        }
        typeText(texto)
    }
}

@MainActor
extension XCTestCase {
    /// Captura con nombre que se conserva en el .xcresult (Q3 las exporta a docs/capturas).
    func capturar(_ app: XCUIApplication, _ nombre: String) {
        let adjunto = XCTAttachment(screenshot: app.screenshot())
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        add(adjunto)
    }

    func esperar(_ elemento: XCUIElement, etiqueta: String, segundos: TimeInterval = 5) {
        let condicion = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", etiqueta), object: elemento)
        XCTAssertEqual(XCTWaiter.wait(for: [condicion], timeout: segundos), .completed, "Esperaba «\(etiqueta)»")
    }

    func esperar(_ elemento: XCUIElement, valor: String, segundos: TimeInterval = 5) {
        let condicion = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", valor), object: elemento)
        XCTAssertEqual(XCTWaiter.wait(for: [condicion], timeout: segundos), .completed, "Esperaba el valor «\(valor)»")
    }
}
