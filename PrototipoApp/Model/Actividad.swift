//
//  Actividad.swift
//  PrototipoApp
//
//  Lo que pasa alrededor de un reporte: comentarios, historial de estados (Historial_Estado),
//  notificaciones (Notificacion_Alerta) y los números de la comunidad.
//

import Foundation

nonisolated struct Comentario: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    let idReporte: Int64
    /// Alias, "Miembro de la comunidad", "Tú" o "Cuenta eliminada".
    let autor: String
    let esMio: Bool
    let texto: String
    let fecha: Date
}

nonisolated struct HistorialEstado: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    let idReporte: Int64
    /// Alias para el staff; "Equipo de moderación" para el autor (protege a quien modera).
    let responsable: String
    let anterior: EstadoReporte?
    let nuevo: EstadoReporte
    let observaciones: String?
    let fecha: Date
}

nonisolated struct Notificacion: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    let idReporte: Int64?
    let mensaje: String
    var leida: Bool
    let fecha: Date
}

nonisolated struct EstadisticasComunidad: Codable, Sendable, Hashable {
    var personasAyudadas: Int
    var reportesVerificados: Int
    var estafasDetenidas: Int
    var zonasCubiertas: Int
}

/// Una tarjeta de "Categorías principales" en Buscar.
nonisolated struct ConteoCategoria: Codable, Sendable, Hashable, Identifiable {
    let tipo: TipoFraude
    let total: Int
    let riesgoMaximo: NivelRiesgo

    var id: TipoFraude { tipo }
}
