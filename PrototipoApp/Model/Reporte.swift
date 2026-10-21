//
//  Reporte.swift
//  PrototipoApp
//
//  Un reporte tal como lo puede ver quien lo pide: el servidor ya quitó lo que esa persona no
//  debe ver (persona afectada, evidencia, autor anónimo). Mapea Reporte, SitioWeb_URL,
//  Evidencia y las tablas nuevas PersonaAfectada, Reporte_Guardado y Reporte_Confirmacion.
//

import Foundation

nonisolated struct AutorVisible: Codable, Sendable, Hashable {
    /// `nil` cuando quien mira no debe saber quién fue (anónimo o perfil privado).
    let idUsuario: Int64?
    /// Alias, "Anónimo", "Miembro de la comunidad", "Tú" o "Cuenta eliminada".
    let nombre: String
}

nonisolated struct PersonaAfectada: Codable, Sendable, Hashable {
    var nombre: String
    var contacto: String
    /// El reportante confirma que la persona le autorizó compartir sus datos.
    var autorizo: Bool
}

nonisolated struct SitioWeb: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    var url: String
    var nivelRiesgoGlobal: NivelRiesgo
    var estadoCertificado: String?
    var fechaUltimaEvaluacion: Date?
}

nonisolated struct Evidencia: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    var rutaArchivo: String
    var tipoArchivo: String
    var fechaCarga: Date

    var esPDF: Bool { tipoArchivo == "application/pdf" }
}

/// Archivo ya limpio (sin metadatos) en la carpeta temporal, esperando a que se envíe el reporte.
nonisolated struct Adjunto: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let nombreArchivo: String
    let tipoArchivo: String
    let bytes: Int

    var esPDF: Bool { tipoArchivo == "application/pdf" }
}

nonisolated struct Reporte: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    var autor: AutorVisible
    var tipo: TipoFraude
    var tipoOtro: String?
    var estado: EstadoReporte
    var titulo: String
    var descripcion: String
    var fechaIncidente: Date
    var nivelRiesgo: NivelRiesgo
    var fechaCreacion: Date
    var esAnonimo: Bool
    var afectado: Afectado
    var ciudad: String
    /// Solo llega al autor y al staff.
    var personaAfectada: PersonaAfectada?
    var sitio: SitioWeb?
    var textoSospechoso: String?
    /// Solo llega al autor y al staff; los demás ven `totalEvidencias`.
    var evidencias: [Evidencia]
    var totalEvidencias: Int
    var confirmaciones: Int
    var comentarios: Int
    var confirmadoPorMi: Bool
    var guardadoPorMi: Bool
    var esMio: Bool

    /// "Oferta Falsa", o lo que escribió en "Otro".
    var tipoVisible: String { tipo == .otro ? (tipoOtro ?? TipoFraude.otro.rawValue) : tipo.rawValue }
}

/// El formulario de Reportar. `limpio` (Security/Sanitizador.swift) lo deja listo para validar.
/// `Codable` para guardarlo en la cola de envíos sin conexión.
nonisolated struct ReporteBorrador: Codable, Sendable, Hashable {
    var esAnonimo = false
    var afectado: Afectado = .yo
    var persona = PersonaAfectada(nombre: "", contacto: "", autorizo: false)
    var ciudad = ""
    var tipo: TipoFraude = .ofertaFalsa
    var tipoOtro = ""
    var titulo = ""
    var fechaIncidente = Date()
    var urlOTexto = ""
    var descripcion = ""
    var adjuntos: [Adjunto] = []
    /// Al editar: evidencias ya guardadas que el autor quitó.
    var quitarEvidencias: Set<Int64> = []

    init() {}

    /// Para editar un reporte existente.
    init(desde r: Reporte) {
        esAnonimo = r.esAnonimo
        afectado = r.afectado
        persona = r.personaAfectada ?? PersonaAfectada(nombre: "", contacto: "", autorizo: false)
        ciudad = r.ciudad
        tipo = r.tipo
        tipoOtro = r.tipoOtro ?? ""
        titulo = r.titulo
        fechaIncidente = r.fechaIncidente
        urlOTexto = r.sitio?.url ?? r.textoSospechoso ?? ""
        descripcion = r.descripcion
    }
}

/// Lo que "Yo también" le pasa al formulario.
nonisolated struct ReportePrefill: Sendable, Hashable {
    var tipo: TipoFraude
    var tipoOtro: String?
    var urlOTexto: String
}
