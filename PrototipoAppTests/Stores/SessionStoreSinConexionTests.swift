//
//  SessionStoreSinConexionTests.swift
//  PrototipoAppTests
//
//  Entrar sin conexión con la sesión guardada y confirmarla cuando vuelve la red.
//

import Foundation
import Testing
@testable import PrototipoApp

struct SessionStoreSinConexionTests {
    let e: EntornoPrueba
    let secretos: MemorySecretStore
    let cable: Cable
    let backend: BackendSinRed

    init() {
        let e = EntornoPrueba()
        self.e = e
        secretos = MemorySecretStore()
        cable = Cable()
        backend = BackendSinRed(base: e.backend(secretos), cable: cable)
    }

    private func nuevaSesion() -> SessionStore { SessionStore(backend: backend, secretos: secretos) }

    /// Inicia sesión con red, como la primera vez que alguien usa la app.
    private func entrar() async throws -> SessionStore {
        let s = nuevaSesion()
        try await s.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
        return s
    }

    @Test func iniciarSesionGuardaElPerfil() async throws {
        let s = try await entrar()
        #expect(try secretos.leer(.usuario)?.contains("usuario_01") == true)
        #expect(!s.sinConexion)
    }

    @Test func sinRedEntraConElPerfilGuardado() async throws {
        _ = try await entrar()
        cable.conectado = false
        let otraVez = nuevaSesion()
        await otraVez.restaurar()
        #expect(otraVez.usuario?.alias == "usuario_01")
        #expect(otraVez.sinConexion)
        #expect(try secretos.leer(.accessToken) != nil)
    }

    @Test func laPrimeraVezSinRedNoSePuedeEntrar() async {
        cable.conectado = false
        let s = nuevaSesion()
        await #expect(throws: AppError.sinConexion) {
            try await s.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
        }
        #expect(s.usuario == nil)
    }

    /// Hay token pero no perfil (una sesión de antes de esta versión): sin red no se sabe con quién
    /// entrar. Se pide iniciar sesión y el token se conserva.
    @Test func sinPerfilGuardadoPideIniciarSesion() async throws {
        _ = try await entrar()
        try secretos.borrar(.usuario)
        cable.conectado = false
        let otraVez = nuevaSesion()
        await otraVez.restaurar()
        #expect(otraVez.estado == .sinSesion)
        #expect(otraVez.aviso == AppError.sinConexion.mensaje())
        #expect(try secretos.leer(.accessToken) != nil)
    }

    @Test func alVolverLaRedSeConfirmaLaSesion() async throws {
        _ = try await entrar()
        cable.conectado = false
        let s = nuevaSesion()
        await s.restaurar()
        #expect(s.sinConexion)

        await s.revalidar()   // sigue sin red: no cambia nada
        #expect(s.sinConexion)
        #expect(s.usuario != nil)

        cable.conectado = true
        await s.revalidar()
        #expect(!s.sinConexion)
        #expect(s.usuario?.alias == "usuario_01")
    }

    /// Mientras no había red la sesión se cerró del lado del servidor: al volver la red se sale.
    @Test func siLaSesionVencioMientrasTantoSeCierra() async throws {
        _ = try await entrar()
        let token = try #require(try secretos.leer(.accessToken))
        cable.conectado = false
        let s = nuevaSesion()
        await s.restaurar()
        #expect(s.sinConexion)

        try await e.servidor.cerrarSesion(token: token)
        cable.conectado = true
        await s.revalidar()
        #expect(s.estado == .sinSesion)
        #expect(!s.sinConexion)
        #expect(try secretos.leer(.usuario) == nil)
    }

    @Test func cerrarSesionSinRedBorraTokensYPerfil() async throws {
        _ = try await entrar()
        cable.conectado = false
        let s = nuevaSesion()
        await s.restaurar()
        await s.cerrarSesion()
        #expect(s.estado == .sinSesion)
        #expect(!s.sinConexion)
        #expect(try secretos.leer(.accessToken) == nil)
        #expect(try secretos.leer(.usuario) == nil)
    }

    @Test func conRedNoQuedaSinConexion() async throws {
        _ = try await entrar()
        let s = nuevaSesion()
        await s.restaurar()
        #expect(s.usuario != nil)
        #expect(!s.sinConexion)
    }
}
