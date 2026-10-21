//
//  SessionStoreBordesTests.swift
//  PrototipoAppTests
//
//  Casos límite del SessionStore: Keychain ilegible, bloqueo por intentos, datos aún no
//  disponibles, respuestas tardías y limpieza al cerrar sesión.
//

import Foundation
import Synchronization
import Testing
@testable import PrototipoApp

/// Un Keychain real puede dejar de leerse un rato (teléfono bloqueado) sin haber perdido el token.
nonisolated final class SecretosRompibles: SecretStore {
    let base = MemorySecretStore()
    private let lecturaFalla = Mutex(false)

    func romperLectura(_ roto: Bool) { lecturaFalla.withLock { $0 = roto } }

    func leer(_ clave: ClaveSecreta) throws -> String? {
        if lecturaFalla.withLock({ $0 }) { throw ErrorKeychain(estado: errSecInteractionNotAllowed) }
        return try base.leer(clave)
    }
    func guardar(_ valor: String, para clave: ClaveSecreta) throws { try base.guardar(valor, para: clave) }
    func borrar(_ clave: ClaveSecreta) throws { try base.borrar(clave) }
}

struct SessionStoreBordesTests {
    let e = EntornoPrueba()

    private func tienda(_ secretos: any SecretStore) -> SessionStore {
        SessionStore(backend: e.backend(secretos), secretos: secretos)
    }

    private func entrar(_ s: SessionStore) async throws {
        try await s.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
    }

    // MARK: Keychain ilegible no es sesión vencida

    @Test func keychainIlegibleAlRestaurarNoBorraElToken() async throws {
        let secretos = SecretosRompibles()
        try secretos.base.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        secretos.romperLectura(true)
        let s = tienda(secretos)
        await s.restaurar()
        #expect(s.estado == .sinSesion)
        #expect(s.aviso == SessionStore.avisoKeychainIlegible)
        #expect(try secretos.base.leer(.accessToken) != nil)
        // Cuando el Keychain vuelve a responder, la sesión sigue ahí.
        secretos.romperLectura(false)
        let otra = tienda(secretos)
        await otra.restaurar()
        #expect(otra.usuario?.alias == "usuario_01")
    }

    @Test func expirarConKeychainIlegibleConservaElToken() async throws {
        let secretos = SecretosRompibles()
        let s = tienda(secretos)
        try await entrar(s)
        secretos.romperLectura(true)
        s.expirar(.sesionExpirada)
        #expect(s.estado == .sinSesion)
        #expect(s.aviso == SessionStore.avisoKeychainIlegible)
        #expect(try secretos.base.leer(.accessToken) != nil)
    }

    @Test func noPoderGuardarElTokenNoDejaEntrarAMedias() async {
        let s = tienda(SecretosQueFallan())
        await #expect(throws: AppError.servidor(SessionStore.errorAlGuardarSesion)) {
            try await s.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
        }
        #expect(s.estado == .restaurando)
        #expect(s.usuario == nil)
    }

    // MARK: Datos aún no disponibles (error del servidor, no sesión vencida)

    @Test func datosNoDisponiblesAlRestaurarConservanElToken() async throws {
        // El archivo de la base existe pero no se puede leer (aquí, es una carpeta): el servidor
        // responde "datos no disponibles" y un token válido NO debe borrarse por eso.
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-ilegible-\(UUID().uuidString)")
        let almacen = DemoAlmacen(carpeta: carpeta)
        try FileManager.default.createDirectory(at: almacen.archivo, withIntermediateDirectories: true)
        let archivos = ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia"))
        let servidor = DemoServer(almacen: almacen, archivos: archivos, hasher: PasswordHasher(iteraciones: 1_000))
        let secretos = MemorySecretStore()
        try secretos.guardar("token-valido-de-antes", para: .accessToken)
        let s = SessionStore(backend: DemoBackend(servidor: servidor, secretos: secretos), secretos: secretos)
        await s.restaurar()
        #expect(s.estado == .sinSesion)
        #expect(s.aviso == DemoServer.mensajeDatosNoDisponibles)
        #expect(try secretos.leer(.accessToken) == "token-valido-de-antes")
    }

    // MARK: Cuenta bloqueada se propaga con su mensaje

    @Test func eliminarCuentaBloqueadaPropagaElMensajeYMantieneLaSesion() async throws {
        let secretos = MemorySecretStore()
        let s = tienda(secretos)
        try await entrar(s)
        var ultimo: AppError?
        for _ in 0..<LimiteIntentos.intentosPermitidos {
            do { try await s.eliminarCuenta(contrasena: "incorrecta#1A") } catch let error as AppError { ultimo = error }
        }
        let bloqueo = try #require(ultimo)
        guard case .cuentaBloqueada = bloqueo else { Issue.record("Se esperaba cuentaBloqueada, llegó \(bloqueo)"); return }
        #expect(bloqueo.mensajeUsuario.hasPrefix("Demasiados intentos"))
        #expect(s.usuario?.alias == "usuario_01")
        #expect(try secretos.leer(.accessToken) != nil)
    }

    @Test func contrasenaIncorrectaAlEliminarNoCierraLaSesion() async throws {
        let s = tienda(MemorySecretStore())
        try await entrar(s)
        await #expect(throws: AppError.self) { try await s.eliminarCuenta(contrasena: "incorrecta#1A") }
        #expect(s.usuario != nil)
    }

    @Test func eliminarCuentaLimpiaTodoYDejaAviso() async throws {
        let secretos = MemorySecretStore()
        let s = tienda(secretos)
        try await entrar(s)
        try await s.eliminarCuenta(contrasena: EntornoPrueba.usuario.contrasena)
        #expect(s.estado == .sinSesion)
        #expect(s.aviso == SessionStore.avisoCuentaEliminada)
        #expect(try secretos.leer(.accessToken) == nil)
    }

    // MARK: Perfil

    @Test func actualizarPerfilCambiaElUsuarioActivo() async throws {
        let s = tienda(MemorySecretStore())
        try await entrar(s)
        var datos = PerfilDatos(desde: try #require(s.usuario))
        datos.biografia = "Reporto estafas en mi barrio."
        try await s.actualizarPerfil(datos)
        #expect(s.usuario?.biografia == "Reporto estafas en mi barrio.")
    }

    @Test func actualizarPerfilConSesionVencidaVuelveALogin() async throws {
        let s = tienda(MemorySecretStore())
        try await entrar(s)
        e.reloj.avanzar(7 * 24 * 3_600 + 1)
        let datos = PerfilDatos(desde: try #require(s.usuario))
        await #expect(throws: AppError.sesionExpirada) { try await s.actualizarPerfil(datos) }
        #expect(s.estado == .sinSesion)
        #expect(s.aviso == AppError.sesionExpirada.mensaje())
    }

    // MARK: Cerrar sesión no deja rastro

    @Test func cerrarSesionLimpiaDesafioCorreoYArchivoExportado() async throws {
        let secretos = MemorySecretStore()
        let s = tienda(secretos)
        try await s.registrar(EntornoPrueba.datosNuevos())
        #expect(s.correoSugerido == "prueba@comunidad.test")
        try await entrar(s)
        #expect(s.correoSugerido.isEmpty)   // al entrar ya no hace falta
        let url = try await s.exportarDatos()
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        await s.cerrarSesion()
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(s.desafio == nil)
        #expect(s.aviso == nil)
        #expect(s.usuario == nil)
    }

    @Test func cancelarDesafioLoBorra() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        let s = tienda(MemorySecretStore())
        try await s.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x")
        #expect(s.desafio != nil)
        s.cancelarDesafio()
        #expect(s.desafio == nil)
        await #expect(throws: AppError.codigoInvalido) { try await s.verificarCodigo("123456") }
    }

    @Test func unaRespuestaTardiaDeExpirarNoPisaElAvisoDeLogin() async throws {
        let s = tienda(MemorySecretStore())
        try await entrar(s)
        await s.cerrarSesion()
        s.aviso = "Cuenta creada. Inicia sesión para continuar."
        s.expirar(.sesionExpirada)   // la respuesta tardía de un store de la sesión anterior
        #expect(s.aviso == "Cuenta creada. Inicia sesión para continuar.")
    }

    @Test func recargarUsuarioQueLlegaTardeNoResucitaLaSesion() async throws {
        let secretos = MemorySecretStore()
        let puerta = Puerta()
        let s = SessionStore(backend: BackendConPuerta(base: e.backend(secretos), puerta: puerta), secretos: secretos)
        try await entrar(s)
        let tarea = Task { await s.recargarUsuario() }
        await puerta.esperarLlegada()
        await s.cerrarSesion()
        await puerta.abrir()
        await tarea.value
        #expect(s.estado == .sinSesion)
        #expect(s.usuario == nil)
    }

    @Test func laSesionVencidaDeUnaOperacionAnteriorNoSacaALaPersonaQueEntroDespues() async throws {
        let secretos = MemorySecretStore()
        let puerta = Puerta()
        let s = SessionStore(backend: BackendConPuerta(base: e.backend(secretos), puerta: puerta), secretos: secretos)
        try await entrar(s)
        e.reloj.avanzar(7 * 24 * 3_600 + 1)       // la sesión de antes ya venció en el servidor
        let tarea = Task { await s.recargarUsuario() }
        await puerta.esperarLlegada()             // la respuesta "sesión expirada" queda retenida
        await s.cerrarSesion()
        try await s.iniciarSesion(correo: EntornoPrueba.admin.correo, contrasena: EntornoPrueba.admin.contrasena)
        await puerta.abrir()
        await tarea.value
        #expect(s.usuario?.alias == "admin_zs")
    }

    // MARK: Ronda 1: cierre voluntario, restablecer y exportar

    private func conPuerta(_ secretos: MemorySecretStore) -> (SessionStore, Puerta) {
        let puerta = Puerta()
        return (SessionStore(backend: BackendConPuerta(base: e.backend(secretos), puerta: puerta), secretos: secretos), puerta)
    }

    @Test func unCierreVoluntarioNoMuestraSesionExpiradaSiLlegaUnaRespuestaTardia() async throws {
        let secretos = MemorySecretStore()
        let (s, puerta) = conPuerta(secretos)
        try await entrar(s)
        let cierre = Task { await s.cerrarSesion() }
        await puerta.esperarLlegada()                  // el servidor aún no responde el cierre
        #expect(s.estado == .sinSesion)                // Login ya se ve
        s.expirar(.sesionExpirada)                     // llega la respuesta tardía de un store
        #expect(s.aviso == nil)
        await puerta.abrir()
        await cierre.value
        #expect(s.aviso == nil)
        #expect(try secretos.leer(.accessToken) == nil)
    }

    @Test func entrarMientrasSeCierraNoBorraElTokenDeLaNuevaSesion() async throws {
        let secretos = MemorySecretStore()
        let (s, puerta) = conPuerta(secretos)
        try await entrar(s)
        let cierre = Task { await s.cerrarSesion() }
        await puerta.esperarLlegada()
        try await s.iniciarSesion(correo: EntornoPrueba.admin.correo, contrasena: EntornoPrueba.admin.contrasena)
        await puerta.abrir()
        await cierre.value
        #expect(s.usuario?.alias == "admin_zs")
        #expect(try secretos.leer(.accessToken) != nil)
    }

    @Test func elAvisoDeRestablecidoSeConservaAunqueAntesLleguePorSesionExpirada() async throws {
        let secretos = MemorySecretStore()
        let s = tienda(secretos)
        try await entrar(s)
        s.expirar(.sesionExpirada)                     // un store se enteró primero
        #expect(s.aviso == AppError.sesionExpirada.mensaje())
        s.sesionRestablecida()                         // luego Ajustes termina de restablecer
        #expect(s.aviso == SessionStore.avisoDemoRestablecida)
        #expect(s.estado == .sinSesion)
        s.expirar(.sesionExpirada)                     // y una respuesta más tardía no lo pisa
        #expect(s.aviso == SessionStore.avisoDemoRestablecida)
        #expect(try secretos.leer(.accessToken) == nil)
    }

    @Test func sesionRestablecidaCierraUnaSesionActiva() async throws {
        let secretos = MemorySecretStore()
        let s = tienda(secretos)
        try await entrar(s)
        s.sesionRestablecida()
        #expect(s.estado == .sinSesion)
        #expect(s.aviso == SessionStore.avisoDemoRestablecida)
        #expect(try secretos.leer(.accessToken) == nil)
    }

    @Test func exportarDatosEscribeUnArchivoPropioYSeBorraAlCerrarSesion() async throws {
        let s = tienda(MemorySecretStore())
        try await entrar(s)
        let url = try await s.exportarDatos()
        #expect(url.lastPathComponent == "zeroscam-mis-datos.json")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        await s.cerrarSesion()
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path(percentEncoded: false)))
        #expect(s.archivoExportado == nil)
    }

    @Test func exportarDatosQueLlegaTardeDespuesDeCerrarSesionNoEscribeNada() async throws {
        let secretos = MemorySecretStore()
        let (s, puerta) = conPuerta(secretos)
        try await entrar(s)
        let exportar = Task { try await s.exportarDatos() }
        await puerta.esperarLlegada()                  // los datos ya salieron del servidor, retenidos
        await s.cerrarSesion()
        await puerta.abrir()
        let resultado = await exportar.result
        #expect(throws: AppError.sesionExpirada) { try resultado.get() }
        #expect(s.archivoExportado == nil)
    }
}
