//
//  RemoteDTO.swift
//  PrototipoApp
//
//  El JSON de la API NestJS (campos en inglés) y su traducción a los modelos de la app. Todo lo
//  que llega es dato externo: un id que no es número o un estado desconocido es un error del
//  servidor, no un valor por defecto silencioso.
//

import Foundation

nonisolated struct TokensDTO: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
}

/// Respuesta de `POST /auth/login`: los tokens, o el desafío de dos pasos.
nonisolated struct LoginDTO: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let twoFactorRequired: Bool?
    let challengeId: String?
    let destination: String?
    let expiresAt: Date?
}

/// Respuesta de `POST /auth/password/code` y `POST /auth/password/forgot` (esta no trae `destination`).
nonisolated struct CodigoCorreoDTO: Decodable, Sendable {
    let challengeId: String
    let destination: String?
    let expiresAt: Date
}

nonisolated struct CuentaDTO: Decodable, Sendable {
    nonisolated struct Privacidad: Decodable, Sendable {
        let version: String?
        let acceptedAt: Date?
    }

    let id: String
    let role: String
    let name: String
    let lastName: String
    let country: String
    let alias: String
    let email: String
    let bio: String
    let hasAvatar: Bool
    let accountStatus: String
    let createdAt: Date
    let preferences: PreferenciasDTO
    let privacy: Privacidad

    func usuario() throws -> Usuario {
        guard let id = Int64(id), let rol = Rol(rawValue: role), let estado = EstadoCuenta(rawValue: accountStatus) else {
            throw AppError.servidor(ClienteHTTP.mensajeServidor)
        }
        return Usuario(
            id: id, rol: rol, nombre: name, apellido: lastName, pais: country, alias: alias, correo: email,
            biografia: bio,
            // La app solo necesita saber si hay avatar; los bytes se piden a /account/avatar/:id.
            avatarRuta: hasAvatar ? "avatar" : nil,
            estadoCuenta: estado, fechaRegistro: createdAt,
            preferencias: Preferencias(notificaciones: preferences.notifications, modoOscuro: preferences.darkMode,
                                       dosPasos: preferences.twoStep, perfilPublico: preferences.publicProfile,
                                       analiticas: preferences.analytics),
            // Las cuentas de arranque del servidor no pasaron por el registro: sin fecha, cuenta la de alta.
            consentimiento: Consentimiento(versionAviso: privacy.version ?? Consentimiento.versionAvisoVigente,
                                           fecha: privacy.acceptedAt ?? createdAt))
    }
}

/// Preferencias como viajan en `GET /account` y `PATCH /account/preferences`.
nonisolated struct PreferenciasDTO: Codable, Sendable {
    var notifications: Bool
    var darkMode: Bool
    var twoStep: Bool
    var publicProfile: Bool
    var analytics: Bool
    /// Solo se manda para apagar los dos pasos.
    var password: String?

    init(_ p: Preferencias, contrasena: String?) {
        notifications = p.notificaciones
        darkMode = p.modoOscuro
        twoStep = p.dosPasos
        publicProfile = p.perfilPublico
        analytics = p.analiticas
        password = contrasena
    }
}

nonisolated struct RegistroEnvio: Encodable, Sendable {
    let name: String
    let lastName: String
    let country: String
    let email: String
    let password: String
    let acceptsPrivacy: Bool
    let alias: String
    let privacyVersion: String
}

nonisolated struct PerfilEnvio: Encodable, Sendable {
    let name: String
    let lastName: String
    let country: String
    let alias: String
    let email: String
    let bio: String
    let currentPassword: String?
}

nonisolated struct ReporteDTO: Decodable, Sendable {
    nonisolated struct Autor: Decodable, Sendable {
        let userId: String?
        let name: String
    }

    nonisolated struct Persona: Codable, Sendable {
        let name: String
        let contact: String
        let authorized: Bool
    }

    nonisolated struct Sitio: Decodable, Sendable {
        let id: Int64
        let url: String
        let riskLevel: String
        let certificateStatus: String?
        let lastEvaluatedAt: Date?
    }

    nonisolated struct Archivo: Decodable, Sendable {
        let id: Int64
        let mimeType: String
        let uploadedAt: Date
    }

    let id: Int64
    let author: Autor
    let fraudType: String
    let otherType: String?
    let status: String
    let title: String
    let description: String
    let incidentDate: Date
    let riskLevel: String
    let createdAt: Date
    let anonymous: Bool
    let affected: String
    let city: String
    let affectedPerson: Persona?
    let site: Sitio?
    let suspiciousText: String?
    let evidence: [Archivo]
    let evidenceCount: Int
    let confirmations: Int
    let comments: Int
    let confirmedByMe: Bool
    let savedByMe: Bool
    let mine: Bool

    func reporte() throws -> Reporte {
        guard let estado = EstadoReporte(rawValue: status) else { throw AppError.servidor(ClienteHTTP.mensajeServidor) }
        // El catálogo del servidor tiene más tipos que la app: los que no conoce se muestran como
        // "Otro" con el nombre que les da el servidor.
        let tipo = TipoFraude(rawValue: fraudType) ?? .otro
        let tipoOtro = tipo == .otro ? (otherType ?? (fraudType == TipoFraude.otro.rawValue ? nil : fraudType)) : nil
        return Reporte(
            id: id,
            autor: AutorVisible(idUsuario: author.userId.flatMap { Int64($0) }, nombre: author.name),
            tipo: tipo, tipoOtro: tipoOtro, estado: estado, titulo: title, descripcion: description,
            fechaIncidente: incidentDate, nivelRiesgo: NivelRiesgo(rawValue: riskLevel) ?? .noEvaluado,
            fechaCreacion: createdAt, esAnonimo: anonymous, afectado: Afectado(rawValue: affected) ?? .yo, ciudad: city,
            personaAfectada: affectedPerson.map { PersonaAfectada(nombre: $0.name, contacto: $0.contact, autorizo: $0.authorized) },
            sitio: site.map {
                SitioWeb(id: $0.id, url: $0.url, nivelRiesgoGlobal: NivelRiesgo(rawValue: $0.riskLevel) ?? .bajo,
                         estadoCertificado: $0.certificateStatus ?? URLTools.estadoCertificado($0.url),
                         fechaUltimaEvaluacion: $0.lastEvaluatedAt)
            },
            textoSospechoso: suspiciousText,
            // La "ruta" es el id: el archivo se pide a /community/evidence/:id, nunca por nombre.
            evidencias: evidence.map { Evidencia(id: $0.id, rutaArchivo: String($0.id), tipoArchivo: $0.mimeType, fechaCarga: $0.uploadedAt) },
            totalEvidencias: max(0, evidenceCount), confirmaciones: max(0, confirmations), comentarios: max(0, comments),
            confirmadoPorMi: confirmedByMe, guardadoPorMi: savedByMe, esMio: mine)
    }
}

/// El formulario de Reportar tal como lo espera `POST/PATCH /community/reports`.
nonisolated struct ReporteEnvio: Encodable, Sendable {
    let fraudType: String
    let otherType: String?
    let title: String
    let description: String
    let incidentDate: Date
    let anonymous: Bool
    let affected: String
    let affectedPerson: ReporteDTO.Persona?
    let city: String
    let url: String?
    let suspiciousText: String?
    let removeEvidenceIds: [Int64]?

    /// `b` ya debe venir limpio (`ReporteBorrador.limpio`). `quitar` solo se manda al editar.
    init(_ b: ReporteBorrador, quitar: [Int64]?) {
        fraudType = b.tipo.rawValue
        otherType = b.tipo == .otro ? b.tipoOtro : nil
        title = b.titulo
        description = b.descripcion
        incidentDate = b.fechaIncidente
        anonymous = b.esAnonimo
        affected = b.afectado.rawValue
        affectedPerson = b.afectado == .otraPersona
            ? ReporteDTO.Persona(name: b.persona.nombre, contact: b.persona.contacto, authorized: b.persona.autorizo)
            : nil
        city = b.ciudad
        // Misma regla que el modo Demo: lo que parece enlace va como URL normalizada; lo demás, como texto.
        if b.urlOTexto.isEmpty {
            url = nil
            suspiciousText = nil
        } else if URLTools.pareceURL(b.urlOTexto) {
            url = URLTools.normalizar(b.urlOTexto)
            suspiciousText = nil
        } else {
            url = nil
            suspiciousText = b.urlOTexto
        }
        removeEvidenceIds = quitar
    }
}

nonisolated struct ComentarioDTO: Decodable, Sendable {
    let id: Int64
    let reportId: Int64
    let author: String
    let mine: Bool
    let text: String
    let createdAt: Date

    var comentario: Comentario {
        Comentario(id: id, idReporte: reportId, autor: author, esMio: mine, texto: text, fecha: createdAt)
    }
}

nonisolated struct HistorialDTO: Decodable, Sendable {
    let id: Int64
    let reportId: Int64
    let responsible: String
    let fromStatus: String?
    let toStatus: String
    let observations: String?
    let changedAt: Date

    func historial() throws -> HistorialEstado {
        guard let nuevo = EstadoReporte(rawValue: toStatus) else { throw AppError.servidor(ClienteHTTP.mensajeServidor) }
        return HistorialEstado(id: id, idReporte: reportId, responsable: responsible,
                               anterior: fromStatus.flatMap { EstadoReporte(rawValue: $0) }, nuevo: nuevo,
                               observaciones: observations, fecha: changedAt)
    }
}

nonisolated struct NotificacionDTO: Decodable, Sendable {
    let id: Int64
    let reportId: Int64?
    let message: String
    let read: Bool
    let sentAt: Date

    var notificacion: Notificacion {
        Notificacion(id: id, idReporte: reportId, mensaje: message, leida: read, fecha: sentAt)
    }
}

nonisolated struct EstadisticasDTO: Decodable, Sendable {
    let peopleHelped: Int
    let verifiedReports: Int
    let scamsStopped: Int
    let zonesCovered: Int

    var estadisticas: EstadisticasComunidad {
        EstadisticasComunidad(personasAyudadas: max(0, peopleHelped), reportesVerificados: max(0, verifiedReports),
                              estafasDetenidas: max(0, scamsStopped), zonasCubiertas: max(0, zonesCovered))
    }
}

nonisolated struct CategoriaDTO: Decodable, Sendable {
    let fraudType: String
    let total: Int
    let maxRisk: String
}

/// Respuesta de `GET /community/users/:id`.
nonisolated struct PerfilPublicoDTO: Decodable, Sendable {
    let id: String
    let alias: String
    let bio: String
    let hasAvatar: Bool
    let memberSince: Date
    let reports: [ReporteDTO]

    func perfil() throws -> PerfilPublico {
        guard let id = Int64(id) else { throw AppError.servidor(ClienteHTTP.mensajeServidor) }
        return PerfilPublico(id: id, alias: alias, biografia: bio, tieneAvatar: hasAvatar, miembroDesde: memberSince,
                             reportes: try reports.map { try $0.reporte() })
    }
}

/// Respuesta de `POST /risk/analyze`.
nonisolated struct DiagnosticoDTO: Decodable, Sendable {
    nonisolated struct Verificacion: Decodable, Sendable {
        let name: String
        let passed: Bool
        let detail: String
    }

    let url: String
    let hostname: String
    let riskLevel: String
    let score: Int
    let checks: [Verificacion]
    let certificateStatus: String?
    let evaluatedAt: Date

    func diagnostico() throws -> DiagnosticoURL {
        guard let nivel = NivelRiesgo(rawValue: riskLevel) else { throw AppError.servidor(ClienteHTTP.mensajeServidor) }
        return DiagnosticoURL(
            url: url, dominio: hostname, nivelRiesgo: nivel, puntaje: min(max(0, score), 100),
            // Los textos vienen de fuera: se limpian y se acotan antes de mostrarlos.
            verificaciones: checks.prefix(12).map {
                VerificacionURL(tipo: VerificacionURL.Tipo(rawValue: $0.name) ?? .otra, paso: $0.passed,
                                detalle: Sanitizador.texto($0.detail, maximo: 300))
            },
            estadoCertificado: certificateStatus.map { Sanitizador.texto($0, maximo: 40) },
            fecha: evaluatedAt)
    }
}
