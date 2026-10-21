//
//  AvisoPrivacidadTests.swift
//  PrototipoAppTests
//
//  Cuando el aviso cambia, la app pide aceptarlo antes de seguir y guarda la versión aceptada.
//

import Foundation
import Testing
@testable import PrototipoApp

struct AvisoPrivacidadTests {
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

    private func entrarConAvisoAnterior() async throws {
        try await session.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
        let token = try #require(try secretos.leer(.accessToken))
        _ = try await e.servidor.aceptarAviso(token: token, version: "2026-10")
        await session.recargarUsuario()
    }

    @Test func conElAvisoVigenteNoSePide() async throws {
        try await session.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
        #expect(session.debeAceptarAviso == false)
    }

    @Test func conUnAvisoAnteriorSePideAceptarlo() async throws {
        try await entrarConAvisoAnterior()
        #expect(session.usuario?.consentimiento.versionAviso == "2026-10")
        #expect(session.debeAceptarAviso)
    }

    @Test func aceptarGuardaLaVersionVigenteEnElServidor() async throws {
        try await entrarConAvisoAnterior()
        let antes = Date()
        try await session.aceptarAvisoVigente()
        #expect(session.debeAceptarAviso == false)
        let token = try #require(try secretos.leer(.accessToken))
        let enServidor = try await e.servidor.usuarioActual(token)
        #expect(enServidor.consentimiento.versionAviso == Consentimiento.versionAvisoVigente)
        #expect(enServidor.consentimiento.fecha >= antes)
    }

    @Test func alCerrarSesionYaNoSePide() async throws {
        try await entrarConAvisoAnterior()
        #expect(session.debeAceptarAviso)
        await session.cerrarSesion()
        #expect(session.debeAceptarAviso == false)
    }
}
