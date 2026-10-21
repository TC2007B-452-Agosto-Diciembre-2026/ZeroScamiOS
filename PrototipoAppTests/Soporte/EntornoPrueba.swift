//
//  EntornoPrueba.swift
//  PrototipoAppTests
//
//  Servidor Demo con carpeta temporal, semilla fresca y un reloj que la prueba puede adelantar.
//

import Foundation
import Synchronization
@testable import PrototipoApp

nonisolated final class RelojPrueba: Sendable {
    private let actual: Mutex<Date>

    init(_ inicio: Date) { actual = Mutex(inicio) }

    var ahora: Date { actual.withLock { $0 } }

    func avanzar(_ segundos: TimeInterval) {
        actual.withLock { $0 = $0.addingTimeInterval(segundos) }
    }
}

struct EntornoPrueba {
    static let inicio = Date(timeIntervalSince1970: 1_791_072_000)
    static let usuario = (correo: "usuario@0fraude.mx", contrasena: "Alerta#2026mx")
    static let admin = (correo: "admin@0fraude.mx", contrasena: "Revisa#2026zs")
    static let owner = (correo: "owner@0fraude.mx", contrasena: "Equipo#2026zs")

    let carpeta: URL
    let reloj: RelojPrueba
    /// La misma carpeta de evidencia que usa el servidor (para preparar adjuntos).
    let archivos: ArchivosEvidencia
    let servidor: DemoServer

    init() {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-prueba-\(UUID().uuidString)")
        let reloj = RelojPrueba(Self.inicio)
        let archivos = ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia"))
        self.carpeta = carpeta
        self.reloj = reloj
        self.archivos = archivos
        servidor = DemoServer(almacen: DemoAlmacen(carpeta: carpeta), archivos: archivos,
                              hasher: PasswordHasher(iteraciones: 1_000),
                              reloj: { reloj.ahora })
    }

    /// Inicia sesión y devuelve el token, como la app lo guardaría en el Keychain.
    func token(_ cuenta: (correo: String, contrasena: String)) async throws -> String {
        guard case .sesion(let sesion) = try await servidor.iniciarSesion(correo: cuenta.correo, contrasena: cuenta.contrasena) else {
            throw AppError.codigoInvalido
        }
        return sesion.accessToken
    }

    static func datosNuevos(alias: String = "prueba_01", correo: String = "prueba@comunidad.test") -> RegistroDatos {
        var d = RegistroDatos()
        d.nombre = "Prueba"
        d.apellido = "Uno"
        d.alias = alias
        d.correo = correo
        d.contrasena = "Segura#2026x"
        d.confirmacion = "Segura#2026x"
        d.aceptaAviso = true
        return d
    }

    /// Registra a alguien nuevo (hash rápido de 1,000 iteraciones) y devuelve su token.
    func nuevaCuenta(alias: String = "prueba_01", correo: String = "prueba@comunidad.test") async throws -> String {
        _ = try await servidor.registrar(Self.datosNuevos(alias: alias, correo: correo))
        return try await token((correo, "Segura#2026x"))
    }
}

extension EntornoPrueba {
    /// El backend que usarían los stores, leyendo el token de `secretos`.
    func backend(_ secretos: any SecretStore) -> DemoBackend {
        DemoBackend(servidor: servidor, secretos: secretos)
    }
}
