//
//  DemoServerAuthTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerAuthTests {
    let e = EntornoPrueba()

    @Test func registrarCreaUsuarioConRolYConsentimiento() async throws {
        let u = try await e.servidor.registrar(EntornoPrueba.datosNuevos())
        #expect(u.rol == .usuario)
        #expect(u.estadoCuenta == .activo)
        #expect(u.consentimiento.versionAviso == Consentimiento.versionAvisoVigente)
        #expect(u.correo == "prueba@comunidad.test")
    }

    @Test func registrarNormalizaCorreoYAlias() async throws {
        let u = try await e.servidor.registrar(EntornoPrueba.datosNuevos(alias: "  Prueba_01 ", correo: " PRUEBA@Comunidad.TEST "))
        #expect(u.alias == "prueba_01")
        #expect(u.correo == "prueba@comunidad.test")
    }

    @Test func registrarRechazaCorreoRepetido() async throws {
        await #expect(throws: AppError.conflicto("Ese correo ya tiene una cuenta. Inicia sesión.")) {
            _ = try await e.servidor.registrar(EntornoPrueba.datosNuevos(correo: "usuario@0fraude.mx"))
        }
    }

    @Test func registrarRechazaDatosInvalidos() async throws {
        var d = EntornoPrueba.datosNuevos()
        d.contrasena = "123"
        d.confirmacion = "123"
        await #expect(throws: AppError.self) { _ = try await e.servidor.registrar(d) }
    }

    @Test func laContrasenaNoQuedaEnClaroEnDisco() async throws {
        _ = try await e.nuevaCuenta()
        let texto = try String(contentsOf: e.carpeta.appending(path: "zeroscam-demo.json"), encoding: .utf8)
        #expect(!texto.contains("Segura#2026x"))
        #expect(texto.contains("pbkdf2_sha256$1000$"))
    }

    @Test func loginCorrectoAbreSesion() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let yo = try await e.servidor.usuarioActual(token)
        #expect(yo.alias == "usuario_01")
        #expect(!token.isEmpty)
    }

    @Test func elTokenNoSeGuardaEnClaro() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let texto = try String(contentsOf: e.carpeta.appending(path: "zeroscam-demo.json"), encoding: .utf8)
        #expect(!texto.contains(token))
        #expect(texto.contains(DemoServer.huella(token)))
    }

    @Test func errorGenericoConCorreoInexistenteOContrasenaMala() async {
        await #expect(throws: AppError.credencialesInvalidas) {
            _ = try await e.servidor.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: "malamala123")
        }
        await #expect(throws: AppError.credencialesInvalidas) {
            _ = try await e.servidor.iniciarSesion(correo: "nadie@0fraude.mx", contrasena: "malamala123")
        }
    }

    @Test func cincoFallosBloqueanYElBloqueoVence() async throws {
        for _ in 1...4 {
            await #expect(throws: AppError.credencialesInvalidas) {
                _ = try await e.servidor.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: "malamala123")
            }
        }
        let hasta = EntornoPrueba.inicio.addingTimeInterval(60)
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) {
            _ = try await e.servidor.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: "malamala123")
        }
        // Bloqueado: ni la contraseña correcta entra.
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) {
            _ = try await e.token(EntornoPrueba.usuario)
        }
        e.reloj.avanzar(61)
        _ = try await e.token(EntornoPrueba.usuario)
    }

    @Test func elBloqueoTambienAplicaAUnCorreoQueNoExiste() async {
        for _ in 1...4 { _ = try? await e.servidor.iniciarSesion(correo: "nadie@0fraude.mx", contrasena: "x") }
        await #expect(throws: AppError.cuentaBloqueada(hasta: EntornoPrueba.inicio.addingTimeInterval(60))) {
            _ = try await e.servidor.iniciarSesion(correo: "nadie@0fraude.mx", contrasena: "x")
        }
    }

    @Test func laSesionCaducaALosSieteDias() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        e.reloj.avanzar(7 * 24 * 3_600 + 1)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(token) }
    }

    @Test func cerrarSesionRevocaElToken() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        try await e.servidor.cerrarSesion(token: token)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(token) }
    }

    @Test func tokenInventadoNoSirve() async {
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual("inventado") }
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(nil) }
    }

    @Test func cambiarContrasenaPideLaActualYCierraLasOtrasSesiones() async throws {
        let token = try await e.nuevaCuenta()
        let otro = try await e.token(("prueba@comunidad.test", "Segura#2026x"))
        await #expect(throws: AppError.self) {
            try await e.servidor.cambiarContrasena(token: token, actual: "equivocada1", nueva: "Distinta#2026y")
        }
        try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y")
        _ = try await e.servidor.usuarioActual(token)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(otro) }
        _ = try await e.token(("prueba@comunidad.test", "Distinta#2026y"))
    }

    @Test func dosPasosPideCodigoYLoVerifica() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        guard case .requiereCodigo(let desafio) = try await e.servidor.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x") else {
            Issue.record("Debía pedir código"); return
        }
        #expect(desafio.destino == "p•••••@comunidad.test")
        let codigo = try #require(desafio.codigoDemo)
        let sesion = try await e.servidor.verificarCodigo(desafio: desafio.id, codigo: codigo)
        #expect(sesion.usuario.alias == "prueba_01")
    }

    @Test func codigoMalTresVecesAnulaElDesafio() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        guard case .requiereCodigo(let d) = try await e.servidor.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x") else { return }
        for _ in 1...3 {
            await #expect(throws: AppError.codigoInvalido) { _ = try await e.servidor.verificarCodigo(desafio: d.id, codigo: "000000") }
        }
        await #expect(throws: AppError.codigoInvalido) { _ = try await e.servidor.verificarCodigo(desafio: d.id, codigo: d.codigoDemo ?? "") }
    }

    @Test func elCodigoVenceACincoMinutos() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        guard case .requiereCodigo(let d) = try await e.servidor.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x") else { return }
        e.reloj.avanzar(301)
        await #expect(throws: AppError.codigoInvalido) { _ = try await e.servidor.verificarCodigo(desafio: d.id, codigo: d.codigoDemo ?? "") }
    }

    @Test func apagarDosPasosExigeContrasena() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        p.dosPasos = false
        await #expect(throws: AppError.self) { _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil) }
        let u = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: "Segura#2026x")
        #expect(!u.preferencias.dosPasos)
    }
}
