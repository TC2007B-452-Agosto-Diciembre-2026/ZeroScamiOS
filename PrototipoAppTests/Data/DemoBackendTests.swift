//
//  DemoBackendTests.swift
//  PrototipoAppTests
//
//  El adaptador lee el token del SecretStore en cada llamada y deja pasar los errores del servidor.
//

import Foundation
import Security
import Testing
@testable import PrototipoApp

struct DemoBackendTests {
    let e = EntornoPrueba()

    @Test func sinTokenNoHaySesion() async {
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.backend(MemorySecretStore()).misReportes() }
    }

    @Test func conTokenEnElSecretStoreFunciona() async throws {
        let secretos = MemorySecretStore()
        let backend = e.backend(secretos)
        guard case .sesion(let s) = try await backend.iniciarSesion(correo: EntornoPrueba.usuario.correo,
                                                                    contrasena: EntornoPrueba.usuario.contrasena) else { return }
        try secretos.guardar(s.accessToken, para: .accessToken)
        #expect(try await backend.misReportes().count == 3)
        #expect(try await backend.usuarioActual().alias == "usuario_01")
    }

    // MARK: Bordes

    /// El token se lee en cada llamada: al cerrar sesión y borrarlo del almacén, ya no hay acceso.
    @Test func alBorrarElTokenSePierdeElAcceso() async throws {
        let secretos = MemorySecretStore()
        let backend = e.backend(secretos)
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        #expect(try await backend.usuarioActual().alias == "usuario_01")
        try secretos.borrar(.accessToken)
        await #expect(throws: AppError.sesionExpirada) { _ = try await backend.usuarioActual() }
    }

    @Test func unTokenQueNoExisteEsSesionExpirada() async throws {
        let secretos = MemorySecretStore()
        try secretos.guardar("token-inventado", para: .accessToken)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.backend(secretos).feed(FiltroBusqueda()) }
    }

    /// Si el Keychain no se puede leer (teléfono bloqueado) no hay token: sesión expirada, sin crash.
    @Test func unKeychainIlegibleEsSesionExpirada() async {
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.backend(SecretosQueFallan()).misReportes() }
    }

    /// Cambiar de cuenta cambia de identidad con solo cambiar el token guardado.
    @Test func cadaTokenEsOtraIdentidad() async throws {
        let secretos = MemorySecretStore()
        let backend = e.backend(secretos)
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        #expect(try await backend.usuarioActual().rol == .usuario)
        try secretos.guardar(try await e.token(EntornoPrueba.admin), para: .accessToken)
        #expect(try await backend.usuarioActual().rol == .administrador)
    }

    @Test func unUsuarioNormalNoUsaLaModeracion() async throws {
        let secretos = MemorySecretStore()
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        await #expect(throws: AppError.sinPermiso) { _ = try await e.backend(secretos).usuarios() }
    }

    /// El bloqueo por intentos sale tal cual del servidor (el adaptador no lo traduce).
    @Test func eliminarCuentaDejaPasarElBloqueo() async throws {
        let secretos = MemorySecretStore()
        let backend = e.backend(secretos)
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        let hasta = EntornoPrueba.inicio.addingTimeInterval(LimiteIntentos.bloqueoBase)
        var ultimo: AppError?
        for _ in 0..<LimiteIntentos.intentosPermitidos {
            do { try await backend.eliminarCuenta(contrasena: "incorrecta#1A") } catch let error as AppError { ultimo = error }
        }
        #expect(ultimo == .cuentaBloqueada(hasta: hasta))
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) { try await backend.eliminarCuenta(contrasena: EntornoPrueba.usuario.contrasena) }
        var perfil = PerfilDatos(desde: try await backend.usuarioActual())
        perfil.correo = "nuevo@comunidad.test"
        perfil.contrasenaActual = EntornoPrueba.usuario.contrasena
        let cambio = perfil
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) { _ = try await backend.actualizarPerfil(cambio) }
    }
}

/// Un SecretStore cuyo Keychain no deja leer.
nonisolated struct SecretosQueFallan: SecretStore {
    func leer(_ clave: ClaveSecreta) throws -> String? { throw ErrorKeychain(estado: errSecInteractionNotAllowed) }
    func guardar(_ valor: String, para clave: ClaveSecreta) throws { throw ErrorKeychain(estado: errSecInteractionNotAllowed) }
    func borrar(_ clave: ClaveSecreta) throws { throw ErrorKeychain(estado: errSecInteractionNotAllowed) }
}
