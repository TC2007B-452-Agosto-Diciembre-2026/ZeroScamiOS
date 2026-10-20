//
//  DependenciesTests.swift
//  PrototipoAppTests
//
//  El armado de la app en modo Demo con la configuración de pruebas de interfaz (carpeta y
//  servicio de Keychain propios, hash rápido).
//

import Foundation
import Testing
@testable import PrototipoApp

@Suite(.serialized)
struct DependenciesTests {
    @Test func armaUnBackendDemoQueFunciona() async throws {
        let config = AppConfig(fuente: .demo, esUITest: true, reiniciarDemo: true, evidenciaDePrueba: false)
        let d = Dependencies.crear(config)
        #expect(d.config == config)
        // Reiniciar borra tokens de una corrida anterior: sin token no hay sesión.
        #expect(try d.secretos.leer(.accessToken) == nil)
        await #expect(throws: AppError.sesionExpirada) { _ = try await d.backend.misReportes() }
        guard case .sesion(let s) = try await d.backend.iniciarSesion(correo: EntornoPrueba.usuario.correo,
                                                                      contrasena: EntornoPrueba.usuario.contrasena) else {
            Issue.record("El usuario demo no debería pedir código")
            return
        }
        try d.secretos.guardar(s.accessToken, para: .accessToken)
        #expect(try await d.backend.usuarioActual().alias == "usuario_01")
        try d.secretos.borrarTodo()
    }

    @Test func reiniciarDemoDejaLaSemillaDeFabrica() async throws {
        let config = AppConfig(fuente: .demo, esUITest: true, reiniciarDemo: true, evidenciaDePrueba: false)
        let a = Dependencies.crear(config)
        guard case .sesion(let s) = try await a.backend.iniciarSesion(correo: EntornoPrueba.usuario.correo,
                                                                      contrasena: EntornoPrueba.usuario.contrasena) else { return }
        try a.secretos.guardar(s.accessToken, para: .accessToken)
        let b = Dependencies.crear(config)
        #expect(try b.secretos.leer(.accessToken) == nil)
        await #expect(throws: AppError.sesionExpirada) { _ = try await b.backend.usuarioActual() }
    }

    /// Previews y pruebas de stores: nada de Keychain ni de la carpeta de la app o de las pruebas de interfaz.
    @Test func efimerasEstanAisladasDelDisco() async throws {
        let a = Dependencies.efimeras()
        let b = Dependencies.efimeras()
        #expect(a.secretos is MemorySecretStore)
        #expect(!(a.secretos is KeychainStore))
        // Cada una trae su propia base: registrar en una no se ve en la otra.
        let datos = EntornoPrueba.datosNuevos()
        _ = try await a.backend.registrar(datos)
        await #expect(throws: AppError.credencialesInvalidas) {
            _ = try await b.backend.iniciarSesion(correo: datos.correo, contrasena: datos.contrasena)
        }
        guard case .sesion = try await a.backend.iniciarSesion(correo: datos.correo, contrasena: datos.contrasena) else {
            Issue.record("La cuenta recién creada debe poder entrar")
            return
        }
        // Sus archivos viven en la carpeta temporal.
        let tmp = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        #expect(a.archivos.carpeta.path(percentEncoded: false).hasPrefix(tmp))
    }
}
