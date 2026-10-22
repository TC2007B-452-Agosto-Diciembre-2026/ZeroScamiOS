//
//  BackendSinRed.swift
//  PrototipoAppTests
//
//  Backend de prueba con un "cable" que la prueba puede desconectar: sin red, `usuarioActual` y
//  `crear` fallan con `.sinConexion`, igual que RemoteBackend cuando no llega al servidor. También
//  imita la `Idempotency-Key` de la API (la misma clave regresa el mismo reporte) y puede simular
//  que la red se corta DESPUÉS de que el servidor creó el reporte.
//

import Foundation
@testable import PrototipoApp

nonisolated final class Cable: Sendable {
    private struct Estado {
        var conectado = true
        var cortarDespuesDeCrear = false
        var errorAlCrear: AppError?
        var claves: [String] = []
        var creados: [String: Reporte] = [:]
    }

    private let estado = Mutex(Estado())

    var conectado: Bool {
        get { estado.withLock { $0.conectado } }
        set { estado.withLock { $0.conectado = newValue } }
    }

    /// El servidor crea el reporte, pero la respuesta no llega (se corta la red en ese momento).
    var cortarDespuesDeCrear: Bool {
        get { estado.withLock { $0.cortarDespuesDeCrear } }
        set { estado.withLock { $0.cortarDespuesDeCrear = newValue } }
    }

    /// Error que el "servidor" responde al crear (por ejemplo, datos rechazados).
    var errorAlCrear: AppError? {
        get { estado.withLock { $0.errorAlCrear } }
        set { estado.withLock { $0.errorAlCrear = newValue } }
    }

    /// Las `Idempotency-Key` con que se intentó crear, en orden.
    var claves: [String] { estado.withLock { $0.claves } }

    fileprivate func anotar(_ clave: String) { estado.withLock { $0.claves.append(clave) } }
    fileprivate func creado(_ clave: String) -> Reporte? { estado.withLock { $0.creados[clave] } }
    fileprivate func guardar(_ r: Reporte, clave: String) { estado.withLock { $0.creados[clave] = r } }
}

nonisolated struct BackendSinRed: Backend {
    let base: DemoBackend
    let cable: Cable

    private func conRed<T>(_ operacion: () async throws -> T) async throws -> T {
        guard cable.conectado else { throw AppError.sinConexion }
        return try await operacion()
    }

    func usuarioActual() async throws -> Usuario { try await conRed { try await base.usuarioActual() } }

    func crear(_ borrador: ReporteBorrador, clave: String) async throws -> Reporte {
        try await conRed {
            cable.anotar(clave)
            if let error = cable.errorAlCrear { throw error }
            if let ya = cable.creado(clave) { return ya }
            let r = try await base.crear(borrador, clave: clave)
            cable.guardar(r, clave: clave)
            if cable.cortarDespuesDeCrear {
                cable.cortarDespuesDeCrear = false
                throw AppError.sinConexion
            }
            return r
        }
    }

    func iniciarSesion(correo: String, contrasena: String) async throws -> ResultadoLogin {
        try await conRed { try await base.iniciarSesion(correo: correo, contrasena: contrasena) }
    }
    func cerrarSesion() async throws { try await conRed { try await base.cerrarSesion() } }

    // MARK: Pasan directo
    func registrar(_ datos: RegistroDatos) async throws -> Usuario { try await base.registrar(datos) }
    func verificarCodigo(desafio: String, codigo: String) async throws -> SesionActiva { try await base.verificarCodigo(desafio: desafio, codigo: codigo) }
    func pedirCodigoContrasena() async throws -> DesafioDosPasos { try await base.pedirCodigoContrasena() }
    func cambiarContrasena(actual: String, nueva: String, desafio: String, codigo: String) async throws -> TokensSesion? {
        try await base.cambiarContrasena(actual: actual, nueva: nueva, desafio: desafio, codigo: codigo)
    }
    func olvideContrasena(correo: String) async throws -> DesafioDosPasos { try await base.olvideContrasena(correo: correo) }
    func restablecerContrasena(desafio: String, codigo: String, nueva: String) async throws {
        try await base.restablecerContrasena(desafio: desafio, codigo: codigo, nueva: nueva)
    }
    func eliminarCuenta(contrasena: String) async throws { try await base.eliminarCuenta(contrasena: contrasena) }

    func feed(_ filtro: FiltroBusqueda) async throws -> [Reporte] { try await base.feed(filtro) }
    func misReportes() async throws -> [Reporte] { try await base.misReportes() }
    func guardados() async throws -> [Reporte] { try await base.guardados() }
    func detalle(id: Int64) async throws -> Reporte { try await base.detalle(id: id) }
    func actualizar(id: Int64, _ borrador: ReporteBorrador) async throws -> Reporte { try await base.actualizar(id: id, borrador) }
    func eliminar(id: Int64) async throws { try await base.eliminar(id: id) }
    func marcarGuardado(id: Int64, _ guardado: Bool) async throws { try await base.marcarGuardado(id: id, guardado) }
    func confirmar(id: Int64) async throws -> Reporte { try await base.confirmar(id: id) }
    func comentarios(id: Int64) async throws -> [Comentario] { try await base.comentarios(id: id) }
    func comentar(id: Int64, texto: String) async throws -> Comentario { try await base.comentar(id: id, texto: texto) }
    func eliminarComentario(id: Int64) async throws { try await base.eliminarComentario(id: id) }
    func historial(id: Int64) async throws -> [HistorialEstado] { try await base.historial(id: id) }
    func estadisticas() async throws -> EstadisticasComunidad { try await base.estadisticas() }
    func categorias() async throws -> [ConteoCategoria] { try await base.categorias() }
    func datosEvidencia(_ evidencia: Evidencia) async throws -> Data { try await base.datosEvidencia(evidencia) }
    func perfilPublico(id: Int64) async throws -> PerfilPublico { try await base.perfilPublico(id: id) }
    func analizarURL(_ url: String) async throws -> DiagnosticoURL { try await base.analizarURL(url) }
    func avatarPublico(idUsuario: Int64) async throws -> Data? { try await base.avatarPublico(idUsuario: idUsuario) }

    func actualizarPerfil(_ datos: PerfilDatos) async throws -> Usuario { try await base.actualizarPerfil(datos) }
    func actualizarPreferencias(_ preferencias: Preferencias, contrasena: String?) async throws -> Usuario {
        try await base.actualizarPreferencias(preferencias, contrasena: contrasena)
    }
    func actualizarAvatar(_ adjunto: Adjunto?) async throws -> Usuario { try await base.actualizarAvatar(adjunto) }
    func aceptarAviso(version: String) async throws -> Usuario { try await base.aceptarAviso(version: version) }
    func datosAvatar(de usuario: Usuario) async throws -> Data? { try await base.datosAvatar(de: usuario) }
    func exportarMisDatos() async throws -> Data { try await base.exportarMisDatos() }

    func notificaciones() async throws -> [Notificacion] { try await base.notificaciones() }
    func marcarLeidas(_ ids: [Int64]) async throws { try await base.marcarLeidas(ids) }

    func colaModeracion(estado: EstadoReporte?) async throws -> [Reporte] { try await base.colaModeracion(estado: estado) }
    func cambiarEstado(id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) async throws -> Reporte {
        try await base.cambiarEstado(id: id, a: nuevo, riesgo: riesgo, observaciones: observaciones)
    }
    func usuarios() async throws -> [Usuario] { try await base.usuarios() }
    func cambiarRol(idUsuario: Int64, a rol: Rol) async throws -> Usuario { try await base.cambiarRol(idUsuario: idUsuario, a: rol) }
    func cambiarEstadoCuenta(idUsuario: Int64, a estado: EstadoCuenta) async throws -> Usuario {
        try await base.cambiarEstadoCuenta(idUsuario: idUsuario, a: estado)
    }
    func analiticas() async throws -> [String: Int] { try await base.analiticas() }
    func restablecerDemo() async throws { try await base.restablecerDemo() }
}
