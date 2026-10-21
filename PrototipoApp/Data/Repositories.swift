//
//  Repositories.swift
//  PrototipoApp
//
//  El "enchufe" entre la app y sus datos. DemoBackend (servidor dentro de la app) y
//  RemoteBackend (API NestJS del Equipo ZeroScam) cumplen los mismos protocolos, así que las
//  pantallas no saben cuál se usa. Ningún método recibe el token: cada implementación lo lee
//  del SecretStore, como el interceptor de `api.ts` del demo del profesor.
//

import Foundation

nonisolated struct SesionActiva: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let usuario: Usuario
}

/// Código de 6 dígitos pendiente: el segundo paso del login, o el de cambiar o recuperar la
/// contraseña. `codigoDemo` solo existe en el modo Demo: es lo que en producción llegaría por correo.
nonisolated struct DesafioDosPasos: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let destino: String
    let expira: Date
    let codigoDemo: String?
}

/// Tokens que el servidor emite al cambiar la contraseña: los de antes ya no se renuevan.
nonisolated struct TokensSesion: Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
}

nonisolated enum ResultadoLogin: Sendable, Equatable {
    case sesion(SesionActiva)
    case requiereCodigo(DesafioDosPasos)
}

nonisolated protocol AuthRepository: Sendable {
    func registrar(_ datos: RegistroDatos) async throws -> Usuario
    func iniciarSesion(correo: String, contrasena: String) async throws -> ResultadoLogin
    func verificarCodigo(desafio: String, codigo: String) async throws -> SesionActiva
    func usuarioActual() async throws -> Usuario
    func cerrarSesion() async throws
    /// Manda al correo de la cuenta el código que pide `cambiarContrasena`.
    func pedirCodigoContrasena() async throws -> DesafioDosPasos
    /// `nil` = el token actual sigue sirviendo (modo Demo); si no, hay que guardar los nuevos.
    func cambiarContrasena(actual: String, nueva: String, desafio: String, codigo: String) async throws -> TokensSesion?
    /// "Olvidé mi contraseña". Responde igual exista o no la cuenta, para no revelar qué correos
    /// están registrados.
    func olvideContrasena(correo: String) async throws -> DesafioDosPasos
    /// Cierra las demás sesiones de la cuenta.
    func restablecerContrasena(desafio: String, codigo: String, nueva: String) async throws
    func eliminarCuenta(contrasena: String) async throws
}

nonisolated protocol ReportRepository: Sendable {
    /// Solo reportes VALIDADO y CANALIZADO.
    func feed(_ filtro: FiltroBusqueda) async throws -> [Reporte]
    func misReportes() async throws -> [Reporte]
    func guardados() async throws -> [Reporte]
    func detalle(id: Int64) async throws -> Reporte
    /// `clave` viaja como `Idempotency-Key`: reintentar con la misma clave (la cola de envíos sin
    /// conexión) regresa el reporte que ya se creó en vez de duplicarlo.
    func crear(_ borrador: ReporteBorrador, clave: String) async throws -> Reporte
    func actualizar(id: Int64, _ borrador: ReporteBorrador) async throws -> Reporte
    func eliminar(id: Int64) async throws
    /// Idempotente: marcar dos veces deja un solo guardado.
    func marcarGuardado(id: Int64, _ guardado: Bool) async throws
    /// "Yo también". Idempotente por usuario.
    func confirmar(id: Int64) async throws -> Reporte
    func comentarios(id: Int64) async throws -> [Comentario]
    func comentar(id: Int64, texto: String) async throws -> Comentario
    func eliminarComentario(id: Int64) async throws
    func historial(id: Int64) async throws -> [HistorialEstado]
    func estadisticas() async throws -> EstadisticasComunidad
    func categorias() async throws -> [ConteoCategoria]
    /// El archivo pasa por el servidor para revisar el permiso de quien lo pide.
    func datosEvidencia(_ evidencia: Evidencia) async throws -> Data
    /// Perfil que alguien dejó público. Si no lo es (o no existe) responde `noEncontrado`.
    func perfilPublico(id: Int64) async throws -> PerfilPublico
    /// Diagnóstico preliminar de un enlace http(s) ya normalizado (RF07).
    func analizarURL(_ url: String) async throws -> DiagnosticoURL
    /// Foto de un perfil público; `nil` si no tiene o no se puede ver.
    func avatarPublico(idUsuario: Int64) async throws -> Data?
}

nonisolated protocol ProfileRepository: Sendable {
    func actualizarPerfil(_ datos: PerfilDatos) async throws -> Usuario
    /// `contrasena` es obligatoria para apagar la verificación en dos pasos.
    func actualizarPreferencias(_ preferencias: Preferencias, contrasena: String?) async throws -> Usuario
    func actualizarAvatar(_ adjunto: Adjunto?) async throws -> Usuario
    /// Deja constancia de que se aceptó esta versión del aviso de privacidad.
    func aceptarAviso(version: String) async throws -> Usuario
    func datosAvatar(de usuario: Usuario) async throws -> Data?
    func exportarMisDatos() async throws -> Data
}

nonisolated protocol NotificationRepository: Sendable {
    func notificaciones() async throws -> [Notificacion]
    func marcarLeidas(_ ids: [Int64]) async throws
}

nonisolated protocol AdminRepository: Sendable {
    /// `nil` = pendientes (RECIBIDO y EN_REVISION).
    func colaModeracion(estado: EstadoReporte?) async throws -> [Reporte]
    func cambiarEstado(id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) async throws -> Reporte
    func usuarios() async throws -> [Usuario]
    func cambiarRol(idUsuario: Int64, a rol: Rol) async throws -> Usuario
    func cambiarEstadoCuenta(idUsuario: Int64, a estado: EstadoCuenta) async throws -> Usuario
    func analiticas() async throws -> [String: Int]
    /// Solo existe en el modo Demo.
    func restablecerDemo() async throws
}

typealias Backend = AuthRepository & ReportRepository & ProfileRepository & NotificationRepository & AdminRepository
