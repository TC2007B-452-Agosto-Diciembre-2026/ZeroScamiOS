//
//  BackendConPuerta.swift
//  PrototipoAppTests
//
//  Backend de prueba que RETIENE la primera respuesta de algunas lecturas hasta que la prueba abre
//  la puerta. Sirve para probar de forma determinista qué pasa cuando una respuesta llega tarde
//  (después de cerrar sesión o de reiniciar un store), sin depender de tiempos del sistema.
//

import Foundation
@testable import PrototipoApp

/// La primera llamada que llega se detiene aquí; las siguientes pasan sin esperar.
actor Puerta {
    private var llegadas = 0
    private var abierta = false
    private var esperandoApertura: [CheckedContinuation<Void, Never>] = []
    private var esperandoLlegada: [CheckedContinuation<Void, Never>] = []

    func pasar() async {
        llegadas += 1
        let avisar = esperandoLlegada
        esperandoLlegada = []
        avisar.forEach { $0.resume() }
        guard llegadas == 1, !abierta else { return }
        await withCheckedContinuation { esperandoApertura.append($0) }
    }

    /// Termina cuando la primera llamada ya llegó (y está retenida).
    func esperarLlegada() async {
        if llegadas > 0 { return }
        await withCheckedContinuation { esperandoLlegada.append($0) }
    }

    func abrir() {
        abierta = true
        let liberar = esperandoApertura
        esperandoApertura = []
        liberar.forEach { $0.resume() }
    }
}

nonisolated struct BackendConPuerta: Backend {
    let base: DemoBackend
    let puerta: Puerta

    /// Ejecuta la operación, y retiene su resultado (o su error) hasta que se abra la puerta.
    private func retener<T>(_ operacion: () async throws -> T) async throws -> T {
        let resultado: Result<T, Error>
        do { resultado = .success(try await operacion()) } catch { resultado = .failure(error) }
        await puerta.pasar()
        return try resultado.get()
    }

    // MARK: Con puerta
    func usuarioActual() async throws -> Usuario { try await retener { try await base.usuarioActual() } }
    func feed(_ filtro: FiltroBusqueda) async throws -> [Reporte] { try await retener { try await base.feed(filtro) } }
    func misReportes() async throws -> [Reporte] { try await retener { try await base.misReportes() } }
    func notificaciones() async throws -> [Notificacion] { try await retener { try await base.notificaciones() } }
    func colaModeracion(estado: EstadoReporte?) async throws -> [Reporte] { try await retener { try await base.colaModeracion(estado: estado) } }
    func crear(_ borrador: ReporteBorrador, clave: String) async throws -> Reporte { try await retener { try await base.crear(borrador, clave: clave) } }
    func comentar(id: Int64, texto: String) async throws -> Comentario { try await retener { try await base.comentar(id: id, texto: texto) } }
    func exportarMisDatos() async throws -> Data { try await retener { try await base.exportarMisDatos() } }
    func cerrarSesion() async throws { try await retener { try await base.cerrarSesion() } }

    // MARK: Sin puerta (pasan directo)
    func registrar(_ datos: RegistroDatos) async throws -> Usuario { try await base.registrar(datos) }
    func iniciarSesion(correo: String, contrasena: String) async throws -> ResultadoLogin { try await base.iniciarSesion(correo: correo, contrasena: contrasena) }
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

    func guardados() async throws -> [Reporte] { try await base.guardados() }
    func detalle(id: Int64) async throws -> Reporte { try await base.detalle(id: id) }
    func actualizar(id: Int64, _ borrador: ReporteBorrador) async throws -> Reporte { try await base.actualizar(id: id, borrador) }
    func eliminar(id: Int64) async throws { try await base.eliminar(id: id) }
    func marcarGuardado(id: Int64, _ guardado: Bool) async throws { try await base.marcarGuardado(id: id, guardado) }
    func confirmar(id: Int64) async throws -> Reporte { try await base.confirmar(id: id) }
    func comentarios(id: Int64) async throws -> [Comentario] { try await base.comentarios(id: id) }
    func eliminarComentario(id: Int64) async throws { try await base.eliminarComentario(id: id) }
    func historial(id: Int64) async throws -> [HistorialEstado] { try await base.historial(id: id) }
    func estadisticas() async throws -> EstadisticasComunidad { try await base.estadisticas() }
    func categorias() async throws -> [ConteoCategoria] { try await base.categorias() }
    func datosEvidencia(_ evidencia: Evidencia) async throws -> Data { try await base.datosEvidencia(evidencia) }

    func actualizarPerfil(_ datos: PerfilDatos) async throws -> Usuario { try await base.actualizarPerfil(datos) }
    func actualizarPreferencias(_ preferencias: Preferencias, contrasena: String?) async throws -> Usuario {
        try await base.actualizarPreferencias(preferencias, contrasena: contrasena)
    }
    func actualizarAvatar(_ adjunto: Adjunto?) async throws -> Usuario { try await base.actualizarAvatar(adjunto) }
    func aceptarAviso(version: String) async throws -> Usuario { try await base.aceptarAviso(version: version) }
    func datosAvatar(de usuario: Usuario) async throws -> Data? { try await base.datosAvatar(de: usuario) }
    func perfilPublico(id: Int64) async throws -> PerfilPublico { try await base.perfilPublico(id: id) }
    func analizarURL(_ url: String) async throws -> DiagnosticoURL { try await base.analizarURL(url) }
    func avatarPublico(idUsuario: Int64) async throws -> Data? { try await base.avatarPublico(idUsuario: idUsuario) }

    func marcarLeidas(_ ids: [Int64]) async throws { try await base.marcarLeidas(ids) }

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
