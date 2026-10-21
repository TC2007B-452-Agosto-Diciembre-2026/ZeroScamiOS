//
//  SessionStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct SessionStoreTests {
    let e: EntornoPrueba
    let secretos: MemorySecretStore
    let session: SessionStore

    init() {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        self.e = e
        self.secretos = secretos
        session = SessionStore(backend: e.backend(secretos), secretos: secretos)
    }

    private func entrar() async throws {
        try await session.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
    }

    /// Con el servidor real la ruta del avatar siempre es "avatar": sin esta versión, la segunda foto
    /// no se volvía a bajar y seguía la anterior.
    @Test func cambiarLaFotoSubeLaVersionDelAvatar() async throws {
        try await entrar()
        #expect(session.versionAvatar == 0)
        try await session.actualizarAvatar(try e.archivos.guardarTemporal(Data([0xFF, 0xD8, 0xFF, 0xE0]), tipo: "image/jpeg"))
        try await session.actualizarAvatar(try e.archivos.guardarTemporal(Data([0xFF, 0xD8, 0xFF, 0xE0]), tipo: "image/jpeg"))
        #expect(session.versionAvatar == 2)
        try await session.actualizarAvatar(nil)
        #expect(session.versionAvatar == 3)
        #expect(session.usuario?.avatarRuta == nil)
    }

    @Test func sinTokenQuedaSinSesion() async {
        await session.restaurar()
        #expect(session.estado == .sinSesion)
    }

    @Test func iniciarSesionGuardaElTokenYActiva() async throws {
        try await session.iniciarSesion(correo: " USUARIO@0fraude.mx ", contrasena: EntornoPrueba.usuario.contrasena)
        #expect(session.usuario?.alias == "usuario_01")
        #expect(try secretos.leer(.accessToken) != nil)
    }

    @Test func laSesionSobreviveAUnNuevoArranque() async throws {
        try await entrar()
        let otraVez = SessionStore(backend: e.backend(secretos), secretos: secretos)
        await otraVez.restaurar()
        #expect(otraVez.usuario?.alias == "usuario_01")
    }

    @Test func tokenInvalidoSeBorraAlRestaurar() async throws {
        try secretos.guardar("inventado", para: .accessToken)
        await session.restaurar()
        #expect(session.estado == .sinSesion)
        #expect(try secretos.leer(.accessToken) == nil)
    }

    @Test func cerrarSesionBorraYRevocaElToken() async throws {
        try await entrar()
        let token = try #require(try secretos.leer(.accessToken))
        await session.cerrarSesion()
        #expect(session.estado == .sinSesion)
        #expect(try secretos.leer(.accessToken) == nil)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(token) }
    }

    @Test func registrarDejaCorreoYAvisoParaLogin() async throws {
        await session.restaurar()
        try await session.registrar(EntornoPrueba.datosNuevos())
        #expect(session.correoSugerido == "prueba@comunidad.test")
        #expect(session.aviso == "Cuenta creada. Inicia sesión para continuar.")
        #expect(session.usuario == nil)
    }

    @Test func dosPasosGuardaElDesafioYDespuesEntra() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        try await session.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x")
        let desafio = try #require(session.desafio)
        #expect(session.usuario == nil)
        try await session.verificarCodigo(try #require(desafio.codigoDemo))
        #expect(session.usuario?.alias == "prueba_01")
        #expect(session.desafio == nil)
    }

    @Test func expirarDejaAvisoYBorraElToken() async throws {
        try await entrar()
        session.expirar(.sesionExpirada)
        #expect(session.aviso == "Tu sesión expiró. Inicia sesión de nuevo.")
        #expect(session.estado == .sinSesion)
        #expect(try secretos.leer(.accessToken) == nil)
    }

    @Test func unaOperacionConSesionVencidaCierraLaSesion() async throws {
        try await entrar()
        e.reloj.avanzar(7 * 24 * 3_600 + 1)
        await #expect(throws: AppError.sesionExpirada) {
            _ = try await session.pedirCodigoContrasena()
        }
        #expect(session.estado == .sinSesion)
    }

    @Test func cambiarLaContrasenaConElCodigoConservaLaSesion() async throws {
        try await entrar()
        let token = try secretos.leer(.accessToken)
        let desafio = try await session.pedirCodigoContrasena()
        try await session.cambiarContrasena(actual: EntornoPrueba.usuario.contrasena, nueva: "Distinta#2026y",
                                            desafio: desafio.id, codigo: try #require(desafio.codigoDemo))
        #expect(session.usuario?.alias == "usuario_01")
        // En Demo no hay tokens nuevos: se queda el mismo.
        #expect(try secretos.leer(.accessToken) == token)
        _ = try await e.token((EntornoPrueba.usuario.correo, "Distinta#2026y"))
    }

    @Test func restablecerDejaCorreoYAvisoParaLogin() async throws {
        await session.restaurar()
        let desafio = try await session.olvideContrasena(correo: " USUARIO@0fraude.mx ")
        try await session.restablecerContrasena(correo: " USUARIO@0fraude.mx ", desafio: desafio.id,
                                                codigo: try #require(desafio.codigoDemo), nueva: "Distinta#2026y")
        #expect(session.correoSugerido == "usuario@0fraude.mx")
        #expect(session.aviso == SessionStore.avisoContrasenaRestablecida)
        #expect(session.usuario == nil)
        try await session.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: "Distinta#2026y")
        #expect(session.usuario?.alias == "usuario_01")
    }

    @Test func unCodigoMaloNoDejaAvisoNiCorreo() async throws {
        await session.restaurar()
        let desafio = try await session.olvideContrasena(correo: EntornoPrueba.usuario.correo)
        let codigo = try #require(desafio.codigoDemo)
        await #expect(throws: AppError.codigoInvalido) {
            try await session.restablecerContrasena(correo: EntornoPrueba.usuario.correo, desafio: desafio.id,
                                                    codigo: codigo == "000000" ? "111111" : "000000", nueva: "Distinta#2026y")
        }
        #expect(session.aviso == nil)
        #expect(session.correoSugerido.isEmpty)
    }
}
