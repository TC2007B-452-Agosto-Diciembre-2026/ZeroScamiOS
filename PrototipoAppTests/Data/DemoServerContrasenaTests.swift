//
//  DemoServerContrasenaTests.swift
//  PrototipoAppTests
//
//  Cambiar y recuperar la contraseña con el código "del correo" (10 minutos, 3 intentos).
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerContrasenaTests {
    let e = EntornoPrueba()
    let correo = "prueba@comunidad.test"

    /// Un código de 6 dígitos que no es el correcto.
    private func otroCodigo(que codigo: String) -> String { codigo == "000000" ? "111111" : "000000" }

    // MARK: Cambiar con sesión

    @Test func cambiarSinElCodigoCorrectoNoCambiaNada() async throws {
        let token = try await e.nuevaCuenta()
        let desafio = try await e.servidor.pedirCodigoContrasena(token: token)
        #expect(desafio.destino == "p•••••@comunidad.test")
        let codigo = try #require(desafio.codigoDemo)
        await #expect(throws: AppError.codigoInvalido) {
            try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y",
                                                   desafio: desafio.id, codigo: otroCodigo(que: codigo))
        }
        _ = try await e.token((correo, "Segura#2026x"))
    }

    /// Sin un código bueno la contraseña actual ni se revisa: un token robado no sirve para adivinarla.
    @Test func sinCodigoBuenoNoSeRevisaLaActual() async throws {
        let token = try await e.nuevaCuenta()
        let desafio = try await e.servidor.pedirCodigoContrasena(token: token)
        let malo = otroCodigo(que: try #require(desafio.codigoDemo))
        await #expect(throws: AppError.codigoInvalido) {
            try await e.servidor.cambiarContrasena(token: token, actual: "equivocada1", nueva: "Distinta#2026y",
                                                   desafio: desafio.id, codigo: malo)
        }
        #expect(await e.servidor.db.intentos[correo] == nil)
    }

    @Test func conLaActualEquivocadaElCodigoSeGasta() async throws {
        let token = try await e.nuevaCuenta()
        let desafio = try await e.servidor.pedirCodigoContrasena(token: token)
        let codigo = try #require(desafio.codigoDemo)
        await #expect(throws: AppError.credencialesInvalidas) {
            try await e.servidor.cambiarContrasena(token: token, actual: "equivocada1", nueva: "Distinta#2026y",
                                                   desafio: desafio.id, codigo: codigo)
        }
        await #expect(throws: AppError.codigoInvalido) {
            try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y",
                                                   desafio: desafio.id, codigo: codigo)
        }
    }

    @Test func alTercerCodigoMaloElDesafioMuere() async throws {
        let token = try await e.nuevaCuenta()
        let desafio = try await e.servidor.pedirCodigoContrasena(token: token)
        let codigo = try #require(desafio.codigoDemo)
        for _ in 0..<3 {
            await #expect(throws: AppError.codigoInvalido) {
                try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y",
                                                       desafio: desafio.id, codigo: otroCodigo(que: codigo))
            }
        }
        await #expect(throws: AppError.codigoInvalido) {
            try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y",
                                                   desafio: desafio.id, codigo: codigo)
        }
    }

    @Test func elCodigoVenceALosDiezMinutos() async throws {
        let token = try await e.nuevaCuenta()
        let desafio = try await e.servidor.pedirCodigoContrasena(token: token)
        #expect(desafio.expira == EntornoPrueba.inicio.addingTimeInterval(10 * 60))
        e.reloj.avanzar(10 * 60 + 1)
        await #expect(throws: AppError.codigoInvalido) {
            try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y",
                                                   desafio: desafio.id, codigo: try #require(desafio.codigoDemo))
        }
    }

    @Test func pedirOtroCodigoAnulaElAnterior() async throws {
        let token = try await e.nuevaCuenta()
        let primero = try await e.servidor.pedirCodigoContrasena(token: token)
        let segundo = try await e.servidor.pedirCodigoContrasena(token: token)
        await #expect(throws: AppError.codigoInvalido) {
            try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y",
                                                   desafio: primero.id, codigo: try #require(primero.codigoDemo))
        }
        try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y",
                                               desafio: segundo.id, codigo: try #require(segundo.codigoDemo))
    }

    @Test func elCodigoDeOtraCuentaNoSirveNiLeGastaIntentos() async throws {
        let mio = try await e.nuevaCuenta()
        let ajeno = try await e.token(EntornoPrueba.usuario)
        let suyo = try await e.servidor.pedirCodigoContrasena(token: ajeno)
        let codigo = try #require(suyo.codigoDemo)
        for _ in 0..<3 {
            await #expect(throws: AppError.codigoInvalido) {
                try await e.servidor.cambiarContrasena(token: mio, actual: "Segura#2026x", nueva: "Distinta#2026y",
                                                       desafio: suyo.id, codigo: codigo)
            }
        }
        // Su dueño todavía lo puede usar.
        try await e.servidor.cambiarContrasena(token: ajeno, actual: EntornoPrueba.usuario.contrasena,
                                               nueva: "Distinta#2026y", desafio: suyo.id, codigo: codigo)
    }

    @Test func unCodigoDeLoginNoSirveParaCambiarNiAlReves() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        guard case .requiereCodigo(let login) = try await e.servidor.iniciarSesion(correo: correo, contrasena: "Segura#2026x") else {
            Issue.record("Debía pedir código"); return
        }
        let cambio = try await e.servidor.pedirCodigoContrasena(token: token)
        await #expect(throws: AppError.codigoInvalido) {
            try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y",
                                                   desafio: login.id, codigo: try #require(login.codigoDemo))
        }
        await #expect(throws: AppError.codigoInvalido) {
            _ = try await e.servidor.verificarCodigo(desafio: cambio.id, codigo: try #require(cambio.codigoDemo))
        }
        // Pedir el código de cambio no anuló el de login (cada propósito tiene el suyo).
        _ = try await e.servidor.verificarCodigo(desafio: login.id, codigo: try #require(login.codigoDemo))
    }

    @Test func soloTresCodigosCadaQuinceMinutos() async throws {
        let token = try await e.nuevaCuenta()
        for _ in 0..<3 { _ = try await e.servidor.pedirCodigoContrasena(token: token) }
        await #expect(throws: AppError.limiteExcedido(DemoServer.mensajeDemasiadosCodigos)) {
            _ = try await e.servidor.pedirCodigoContrasena(token: token)
        }
        // El cupo de recuperar es aparte, y también se agota (sin decirlo: responde como sin cuenta).
        for _ in 0..<3 { #expect(try await e.servidor.olvideContrasena(correo: correo).codigoDemo != nil) }
        #expect(try await e.servidor.olvideContrasena(correo: correo).codigoDemo == nil)
        e.reloj.avanzar(15 * 60)
        _ = try await e.servidor.pedirCodigoContrasena(token: token)
        #expect(try await e.servidor.olvideContrasena(correo: correo).codigoDemo != nil)
    }

    @Test func pedirCodigoSinSesionEsSesionExpirada() async {
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.pedirCodigoContrasena(token: nil) }
    }

    // MARK: Olvidé mi contraseña

    @Test func olvideConCorreoDesconocidoRespondeIgualPeroSinCodigo() async throws {
        let existe = try await e.servidor.olvideContrasena(correo: EntornoPrueba.usuario.correo)
        let noExiste = try await e.servidor.olvideContrasena(correo: "nadie@comunidad.test")
        #expect(existe.codigoDemo != nil)
        #expect(noExiste.codigoDemo == nil)
        #expect(existe.expira == noExiste.expira)
        #expect(noExiste.destino == "n••••@comunidad.test")
        await #expect(throws: AppError.codigoInvalido) {
            try await e.servidor.restablecerContrasena(desafio: noExiste.id, codigo: "123456", nueva: "Distinta#2026y")
        }
    }

    @Test func restablecerCambiaLaContrasenaYCierraTodasLasSesiones() async throws {
        let token = try await e.nuevaCuenta()
        let desafio = try await e.servidor.olvideContrasena(correo: " PRUEBA@Comunidad.test ")
        try await e.servidor.restablecerContrasena(desafio: desafio.id, codigo: try #require(desafio.codigoDemo),
                                                   nueva: "Distinta#2026y")
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(token) }
        await #expect(throws: AppError.credencialesInvalidas) { _ = try await e.token((correo, "Segura#2026x")) }
        _ = try await e.token((correo, "Distinta#2026y"))
    }

    @Test func unaContrasenaDebilNoGastaElCodigo() async throws {
        _ = try await e.nuevaCuenta()
        let desafio = try await e.servidor.olvideContrasena(correo: correo)
        let codigo = try #require(desafio.codigoDemo)
        for _ in 0..<3 {
            await #expect(throws: AppError.self) {
                try await e.servidor.restablecerContrasena(desafio: desafio.id, codigo: codigo, nueva: "corta1")
            }
        }
        try await e.servidor.restablecerContrasena(desafio: desafio.id, codigo: codigo, nueva: "Distinta#2026y")
    }

    @Test func elCodigoSoloSirveUnaVez() async throws {
        _ = try await e.nuevaCuenta()
        let desafio = try await e.servidor.olvideContrasena(correo: correo)
        let codigo = try #require(desafio.codigoDemo)
        try await e.servidor.restablecerContrasena(desafio: desafio.id, codigo: codigo, nueva: "Distinta#2026y")
        await #expect(throws: AppError.codigoInvalido) {
            try await e.servidor.restablecerContrasena(desafio: desafio.id, codigo: codigo, nueva: "Otra#2026zz")
        }
    }

    @Test func restablecerQuitaElBloqueoPorIntentos() async throws {
        _ = try await e.nuevaCuenta()
        for _ in 0..<5 {
            _ = try? await e.servidor.iniciarSesion(correo: correo, contrasena: "equivocada1")
        }
        await #expect(throws: AppError.self) { _ = try await e.token((correo, "Segura#2026x")) }
        let desafio = try await e.servidor.olvideContrasena(correo: correo)
        try await e.servidor.restablecerContrasena(desafio: desafio.id, codigo: try #require(desafio.codigoDemo),
                                                   nueva: "Distinta#2026y")
        _ = try await e.token((correo, "Distinta#2026y"))
    }

    @Test func unaCuentaSuspendidaNoRecibeCodigo() async throws {
        let token = try await e.nuevaCuenta()
        let yo = try await e.servidor.usuarioActual(token)
        let owner = try await e.token(EntornoPrueba.owner)
        _ = try await e.servidor.cambiarEstadoCuenta(token: owner, idUsuario: yo.id, a: .suspendido)
        let desafio = try await e.servidor.olvideContrasena(correo: correo)
        #expect(desafio.codigoDemo == nil)
    }
}
