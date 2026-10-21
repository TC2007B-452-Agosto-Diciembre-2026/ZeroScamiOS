//
//  DemoDatabase.swift
//  PrototipoApp
//
//  Las "tablas" del modo Demo. Cada fila es el espejo de una tabla de ZeroScam (o de las
//  propuestas en database/zeroscam_migracion_0fraude.sql). A diferencia de los modelos de
//  Model/, las filas guardan todo: el hash de la contraseña, el autor real de un anónimo.
//

import Foundation

nonisolated struct UsuarioFila: Codable, Sendable {
    var usuario: Usuario
    var contrasenaHash: String
}

/// Tabla `Sesion`: solo el SHA-256 del token, nunca el token.
nonisolated struct SesionFila: Codable, Sendable {
    let tokenHash: String
    let idUsuario: Int64
    let creada: Date
    let expira: Date
}

/// Para qué sirve un código de `Codigo_Correo` (en el API, `RECUPERAR` y `CAMBIAR`).
nonisolated enum PropositoCodigo: String, Codable, Sendable {
    case recuperar, cambiar
}

/// Tablas `Desafio_DosPasos` y `Codigo_Correo`: el código de 6 dígitos también se guarda como SHA-256.
nonisolated struct DesafioFila: Codable, Sendable {
    let id: String
    let idUsuario: Int64
    let codigoHash: String
    let expira: Date
    var intentos: Int
    /// `nil` = segundo paso del login. Opcional para que los archivos guardados antes se sigan leyendo.
    var proposito: PropositoCodigo? = nil
}

nonisolated struct ReporteFila: Codable, Sendable {
    let id: Int64
    /// `nil` cuando la cuenta se eliminó y el reporte público se anonimizó.
    var idUsuario: Int64?
    var tipo: TipoFraude
    var tipoOtro: String?
    var estado: EstadoReporte
    var titulo: String
    var descripcion: String
    var fechaIncidente: Date
    var nivelRiesgo: NivelRiesgo
    let fechaCreacion: Date
    var esAnonimo: Bool
    var afectado: Afectado
    var ciudad: String
    var persona: PersonaAfectada?
    /// Tabla `Reporte_URL` (la app usa un sitio por reporte).
    var idSitio: Int64?
    var textoSospechoso: String?
    /// Solo datos semilla: conteo histórico de "Yo también". En MySQL es COUNT(*) de Reporte_Confirmacion.
    var confirmacionesPrevias: Int = 0
}

nonisolated struct EvidenciaFila: Codable, Sendable {
    let id: Int64
    let idReporte: Int64
    let rutaArchivo: String
    let tipoArchivo: String
    let fechaCarga: Date

    var evidencia: Evidencia {
        Evidencia(id: id, rutaArchivo: rutaArchivo, tipoArchivo: tipoArchivo, fechaCarga: fechaCarga)
    }
}

nonisolated struct HistorialFila: Codable, Sendable {
    let id: Int64
    let idReporte: Int64
    let idResponsable: Int64
    let anterior: EstadoReporte?
    let nuevo: EstadoReporte
    let observaciones: String?
    let fecha: Date
}

nonisolated struct NotificacionFila: Codable, Sendable {
    let id: Int64
    let idUsuario: Int64
    var idReporte: Int64?
    let mensaje: String
    var leida: Bool
    let fecha: Date
}

nonisolated struct ComentarioFila: Codable, Sendable {
    let id: Int64
    let idReporte: Int64
    var idUsuario: Int64?
    let texto: String
    let fecha: Date
}

/// Tablas `Reporte_Guardado` y `Reporte_Confirmacion`.
nonisolated struct ParUsuarioReporte: Codable, Sendable, Hashable {
    let idUsuario: Int64
    let idReporte: Int64
    let fecha: Date
}

nonisolated struct DemoDatabase: Codable, Sendable {
    /// Si cambia la forma del archivo, se sube y la app vuelve a sembrar.
    static let versionActual = 1

    var version = DemoDatabase.versionActual
    var ultimoID: Int64 = 1_000
    var usuarios: [UsuarioFila] = []
    /// Intentos de login por correo normalizado (exista o no la cuenta).
    var intentos: [String: RegistroIntentos] = [:]
    var sesiones: [SesionFila] = []
    var desafios: [DesafioFila] = []
    var reportes: [ReporteFila] = []
    var sitios: [SitioWeb] = []
    var evidencias: [EvidenciaFila] = []
    var historial: [HistorialFila] = []
    var notificaciones: [NotificacionFila] = []
    var comentarios: [ComentarioFila] = []
    var guardados: [ParUsuarioReporte] = []
    var confirmaciones: [ParUsuarioReporte] = []
    /// Contadores anónimos (sin id de usuario).
    var analiticas: [String: Int] = [:]

    /// Tope de los ids: el entero máximo que JavaScript (NestJS) representa sin perder precisión.
    static let idMaximo: Int64 = 1 << 53

    /// Nunca desborda: un contador manipulado en el límite se queda ahí en vez de detener la app.
    mutating func siguienteID() -> Int64 {
        let (siguiente, desbordo) = ultimoID.addingReportingOverflow(1)
        ultimoID = desbordo ? Int64.max : siguiente
        return ultimoID
    }

    /// Revisa un archivo recién leído: versión conocida y contador dentro de rango. Además sube el
    /// contador hasta el id más alto que ya exista, para que el siguiente id nunca se repita.
    func validadaOReconciliada() -> DemoDatabase? {
        guard version == DemoDatabase.versionActual, ultimoID >= 0, ultimoID <= DemoDatabase.idMaximo else { return nil }
        var copia = self
        let ids: [Int64] = usuarios.map(\.usuario.id) + sitios.map(\.id) + reportes.map(\.id)
            + evidencias.map(\.id) + historial.map(\.id) + notificaciones.map(\.id) + comentarios.map(\.id)
        let maximo = ids.max() ?? 0
        guard maximo <= DemoDatabase.idMaximo else { return nil }
        copia.ultimoID = max(copia.ultimoID, maximo)
        return copia
    }
}
