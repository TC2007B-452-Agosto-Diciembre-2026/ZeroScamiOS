//
//  AppConfigTests.swift
//  PrototipoAppTests
//
//  De dónde salen los datos: solo HTTPS o la propia Mac, y las pruebas de interfaz siempre en Demo.
//

import Foundation
import Testing
@testable import PrototipoApp

struct AppConfigTests {
    @Test func porDefectoEsDemo() {
        #expect(AppConfig.actual(info: [:], argumentos: []).fuente == .demo)
    }

    @Test func remotoSoloConHTTPSoLocalhost() {
        let https = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": "https://api.zeroscam.test"], argumentos: [])
        #expect(https.fuente == .remote(URL(string: "https://api.zeroscam.test")!))
        let local = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": "http://localhost:3000"], argumentos: [])
        #expect(local.fuente == .remote(URL(string: "http://localhost:3000")!))
        let inseguro = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": "http://api.zeroscam.test"], argumentos: [])
        #expect(inseguro.fuente == .demo)
    }

    @Test func lasPruebasDeInterfazSiempreUsanDemo() {
        let c = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": "https://api.zeroscam.test"],
                                 argumentos: ["-uiTesting", "-reiniciarDemo", "-evidenciaDePrueba"])
        #expect(c.fuente == .demo)
        #expect(c.esUITest && c.reiniciarDemo && c.evidenciaDePrueba)
    }

    @Test func laEvidenciaDePruebaSoloExisteEnPruebasDeInterfaz() {
        #expect(!AppConfig.actual(info: [:], argumentos: ["-evidenciaDePrueba"]).evidenciaDePrueba)
    }

    // MARK: Bordes (la configuración viene de un plist y de argumentos: datos externos)

    @Test func laConfiguracionMalformadaCaeEnDemo() {
        let malos: [[String: Any]] = [
            ["ZSFuenteDatos": "remote"],                                        // sin URL
            ["ZSFuenteDatos": "remote", "ZSURLBase": ""],                       // URL vacía
            ["ZSFuenteDatos": "remote", "ZSURLBase": "$(ZS_URL_BASE)"],         // ajuste sin expandir
            ["ZSFuenteDatos": "remote", "ZSURLBase": 42],                       // tipo equivocado
            ["ZSFuenteDatos": 1, "ZSURLBase": "https://api.zeroscam.test"],     // fuente de otro tipo
            ["ZSFuenteDatos": "demo", "ZSURLBase": "https://api.zeroscam.test"],
            ["ZSFuenteDatos": "REMOTE", "ZSURLBase": "https://api.zeroscam.test"],
        ]
        for info in malos { #expect(AppConfig.actual(info: info, argumentos: []).fuente == .demo) }
    }

    @Test func rechazaURLsEngañosasOSinServidor() {
        let urls = [
            "https://", "https:///ruta", "ftp://api.zeroscam.test", "file:///etc/passwd",
            "http://localhost.evil.test", "http://evil.test/localhost", "http://127.0.0.1.evil.test",
            "https://usuario:clave@api.zeroscam.test", "http://localhost@evil.test",
            "javascript:alert(1)", "api.zeroscam.test",
        ]
        for texto in urls {
            let c = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": texto], argumentos: [])
            #expect(c.fuente == .demo, "no debía aceptar \(texto)")
        }
    }

    @Test func aceptaLocalhostEnVariasFormas() {
        for texto in ["http://127.0.0.1:3000", "http://LOCALHOST:3000", "HTTPS://API.ZEROSCAM.TEST", "http://[::1]:3000"] {
            let c = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": texto], argumentos: [])
            #expect(c.fuente != .demo, "debía aceptar \(texto)")
        }
    }

    /// El backend del equipo vive en la red local y se sirve por HTTP: se acepta una IPv4 privada.
    @Test func aceptaHTTPEnRedPrivada() {
        for texto in ["http://10.0.0.5:3000", "http://172.16.4.2:3000", "http://172.31.255.254", "http://192.168.1.20:3000"] {
            let c = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": texto], argumentos: [])
            #expect(c.fuente == .remote(URL(string: texto)!), "debía aceptar \(texto)")
        }
    }

    @Test func rechazaHTTPFueraDeLaRedPrivada() {
        let urls = [
            "http://8.8.8.8:3000", "http://172.15.0.1", "http://172.32.0.1", "http://192.169.1.1", "http://11.0.0.1",
            "http://10.0.0.1.evil.test", "http://192.168.1.evil.test", "http://10.0.0", "http://10.0.0.256",
            "http://servidor.local:3000", "http://192.168.1.20@evil.test",
        ]
        for texto in urls {
            let c = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": texto], argumentos: [])
            #expect(c.fuente == .demo, "no debía aceptar \(texto)")
        }
    }

    @Test func reiniciarDemoSeLeeDeLosArgumentos() {
        #expect(AppConfig.actual(info: [:], argumentos: ["-reiniciarDemo"]).reiniciarDemo)
        #expect(!AppConfig.actual(info: [:], argumentos: []).reiniciarDemo)
    }

    @Test func porDefectoEsDemoSinBanderas() {
        #expect(AppConfig.porDefecto == AppConfig.actual(info: [:], argumentos: []))
    }
}
