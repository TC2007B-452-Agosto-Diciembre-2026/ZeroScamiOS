//
//  DemoBackend.swift
//  PrototipoApp
//
//  Adaptador entre los protocolos de repositorio y el DemoServer. Lee el token del Keychain en
//  cada llamada y se lo pasa al servidor, igual que el interceptor de `api.ts` agrega el Bearer.
//

import Foundation

nonisolated struct DemoBackend: Backend {
    let servidor: DemoServer
    let secretos: any SecretStore

    private var token: String? { try? secretos.leer(.accessToken) }

    // MARK: AuthRepository
    func registrar(_ datos: RegistroDatos) async throws -> Usuario { try await servidor.registrar(datos) }
    func iniciarSesion(correo: String, contrasena: String) async throws -> ResultadoLogin {
        try await servidor.iniciarSesion(correo: correo, contrasena: contrasena)
    }
    func verificarCodigo(desafio: String, codigo: String) async throws -> SesionActiva {
        try await servidor.verificarCodigo(desafio: desafio, codigo: codigo)
    }
    func usuarioActual() async throws -> Usuario { try await servidor.usuarioActual(token) }
    func cerrarSesion() async throws { try await servidor.cerrarSesion(token: token) }
    func pedirCodigoContrasena() async throws -> DesafioDosPasos { try await servidor.pedirCodigoContrasena(token: token) }
    /// El servidor Demo conserva la sesión de quien cambió la contraseña: no hay tokens nuevos.
    func cambiarContrasena(actual: String, nueva: String, desafio: String, codigo: String) async throws -> TokensSesion? {
        try await servidor.cambiarContrasena(token: token, actual: actual, nueva: nueva, desafio: desafio, codigo: codigo)
        return nil
    }
    func olvideContrasena(correo: String) async throws -> DesafioDosPasos { try await servidor.olvideContrasena(correo: correo) }
    func restablecerContrasena(desafio: String, codigo: String, nueva: String) async throws {
        try await servidor.restablecerContrasena(desafio: desafio, codigo: codigo, nueva: nueva)
    }
    func eliminarCuenta(contrasena: String) async throws { try await servidor.eliminarCuenta(token: token, contrasena: contrasena) }

    // MARK: ReportRepository
    func feed(_ filtro: FiltroBusqueda) async throws -> [Reporte] { try await servidor.feed(token: token, filtro: filtro) }
    func misReportes() async throws -> [Reporte] { try await servidor.misReportes(token: token) }
    func guardados() async throws -> [Reporte] { try await servidor.guardados(token: token) }
    func detalle(id: Int64) async throws -> Reporte { try await servidor.detalle(token: token, id: id) }
    /// El servidor Demo vive dentro de la app y nunca pierde la conexión: no necesita la clave.
    func crear(_ borrador: ReporteBorrador, clave: String) async throws -> Reporte { try await servidor.crear(token: token, borrador) }
    func actualizar(id: Int64, _ borrador: ReporteBorrador) async throws -> Reporte {
        try await servidor.actualizar(token: token, id: id, borrador)
    }
    func eliminar(id: Int64) async throws { try await servidor.eliminar(token: token, id: id) }
    func marcarGuardado(id: Int64, _ guardado: Bool) async throws { try await servidor.marcarGuardado(token: token, id: id, guardado) }
    func confirmar(id: Int64) async throws -> Reporte { try await servidor.confirmar(token: token, id: id) }
    func comentarios(id: Int64) async throws -> [Comentario] { try await servidor.comentarios(token: token, id: id) }
    func comentar(id: Int64, texto: String) async throws -> Comentario { try await servidor.comentar(token: token, id: id, texto: texto) }
    func eliminarComentario(id: Int64) async throws { try await servidor.eliminarComentario(token: token, id: id) }
    func historial(id: Int64) async throws -> [HistorialEstado] { try await servidor.historial(token: token, id: id) }
    func estadisticas() async throws -> EstadisticasComunidad { try await servidor.estadisticas(token: token) }
    func categorias() async throws -> [ConteoCategoria] { try await servidor.categorias(token: token) }
    func datosEvidencia(_ evidencia: Evidencia) async throws -> Data { try await servidor.datosEvidencia(token: token, evidencia) }
    func perfilPublico(id: Int64) async throws -> PerfilPublico { try await servidor.perfilPublico(token: token, id: id) }
    func analizarURL(_ url: String) async throws -> DiagnosticoURL { try await servidor.analizarURL(token: token, url) }
    func avatarPublico(idUsuario: Int64) async throws -> Data? { try await servidor.avatarPublico(token: token, idUsuario: idUsuario) }

    // MARK: ProfileRepository
    func actualizarPerfil(_ datos: PerfilDatos) async throws -> Usuario { try await servidor.actualizarPerfil(token: token, datos) }
    func aceptarAviso(version: String) async throws -> Usuario {
        try await servidor.aceptarAviso(token: token, version: version)
    }
    func actualizarPreferencias(_ preferencias: Preferencias, contrasena: String?) async throws -> Usuario {
        try await servidor.actualizarPreferencias(token: token, preferencias, contrasena: contrasena)
    }
    func actualizarAvatar(_ adjunto: Adjunto?) async throws -> Usuario { try await servidor.actualizarAvatar(token: token, adjunto) }
    func datosAvatar(de usuario: Usuario) async throws -> Data? { try await servidor.datosAvatar(token: token, de: usuario) }
    func exportarMisDatos() async throws -> Data { try await servidor.exportarMisDatos(token: token) }

    // MARK: NotificationRepository
    func notificaciones() async throws -> [Notificacion] { try await servidor.notificaciones(token: token) }
    func marcarLeidas(_ ids: [Int64]) async throws { try await servidor.marcarLeidas(token: token, ids) }

    // MARK: AdminRepository
    func colaModeracion(estado: EstadoReporte?) async throws -> [Reporte] { try await servidor.colaModeracion(token: token, estado: estado) }
    func cambiarEstado(id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) async throws -> Reporte {
        try await servidor.cambiarEstado(token: token, id: id, a: nuevo, riesgo: riesgo, observaciones: observaciones)
    }
    func usuarios() async throws -> [Usuario] { try await servidor.usuarios(token: token) }
    func cambiarRol(idUsuario: Int64, a rol: Rol) async throws -> Usuario { try await servidor.cambiarRol(token: token, idUsuario: idUsuario, a: rol) }
    func cambiarEstadoCuenta(idUsuario: Int64, a estado: EstadoCuenta) async throws -> Usuario {
        try await servidor.cambiarEstadoCuenta(token: token, idUsuario: idUsuario, a: estado)
    }
    func analiticas() async throws -> [String: Int] { try await servidor.analiticas(token: token) }
    func restablecerDemo() async throws { try await servidor.restablecerDemo(token: token) }
}
