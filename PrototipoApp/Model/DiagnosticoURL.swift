//
//  DiagnosticoURL.swift
//  PrototipoApp
//
//  Diagnóstico preliminar de un enlace (RF07): el servidor revisa su estructura, su certificado,
//  la antigüedad del dominio, las listas negras y los reportes validados de la comunidad, y de
//  ahí sale un puntaje y un nivel de riesgo. Es una estimación automática, no una garantía.
//

import Foundation

/// Una de las verificaciones del análisis.
nonisolated struct VerificacionURL: Codable, Sendable, Hashable, Identifiable {
    nonisolated enum Tipo: String, Codable, Sendable, CaseIterable {
        case estructura = "heuristics"
        case certificado = "certificate"
        case antiguedad = "domainAge"
        case listaNegra = "blacklist"
        case comunidad = "communityReports"
        case otra

        var titulo: String {
            switch self {
            case .estructura: "Estructura del enlace"
            case .certificado: "Certificado de seguridad"
            case .antiguedad: "Antigüedad del dominio"
            case .listaNegra: "Listas negras"
            case .comunidad: "Reportes de la comunidad"
            case .otra: "Otra verificación"
            }
        }
    }

    let tipo: Tipo
    /// `true` = no encontró nada sospechoso.
    let paso: Bool
    let detalle: String

    var id: String { "\(tipo.rawValue)|\(detalle)" }
}

nonisolated struct DiagnosticoURL: Codable, Sendable, Hashable {
    /// El enlace ya normalizado, que es el que se analizó.
    let url: String
    let dominio: String
    let nivelRiesgo: NivelRiesgo
    /// Puntos de riesgo, de 0 (sin señales) a 100.
    let puntaje: Int
    let verificaciones: [VerificacionURL]
    /// VALIDO, INSEGURO, EXPIRADO o INACCESIBLE.
    let estadoCertificado: String?
    let fecha: Date

    var senales: Int { verificaciones.filter { !$0.paso }.count }

    /// La respuesta a "¿es legítimo?" en una palabra. Sale del nivel de riesgo del servidor: un
    /// sitio sin certificado verificable o con señales sueltas queda como dudoso, nunca legítimo.
    nonisolated enum Veredicto: Sendable {
        case pareceLegitimo, dudoso, noLegitimo

        var titulo: String {
            switch self {
            case .pareceLegitimo: "PARECE LEGÍTIMO"
            case .dudoso: "DUDOSO"
            case .noLegitimo: "NO ES LEGÍTIMO"
            }
        }
    }

    /// Estados del certificado con los que no se puede decir que un sitio parece legítimo
    /// (los del servidor y los del Demo).
    static let certificadosSinConfianza: Set<String> = ["INACCESIBLE", "INSEGURO", "EXPIRADO", "SIN HTTPS"]

    /// Falla cerrada: solo un riesgo BAJO con verificaciones, todas aprobadas, y un certificado
    /// revisado y sin problema dice "parece legítimo". Sin evaluar, sin verificaciones o sin
    /// estado de certificado queda como dudoso.
    var veredicto: Veredicto {
        switch nivelRiesgo {
        case .alto, .muyAlto: return .noLegitimo
        case .medio, .noEvaluado: return .dudoso
        case .bajo:
            guard !verificaciones.isEmpty, senales == 0, let certificado = estadoCertificado,
                  !Self.certificadosSinConfianza.contains(certificado.uppercased()) else { return .dudoso }
            return .pareceLegitimo
        }
    }

    /// Una frase para quien no va a leer la lista.
    var resumen: String {
        switch nivelRiesgo {
        case .muyAlto: "Muy probablemente es un fraude. No lo abras ni escribas tus datos."
        case .alto: "Hay señales claras de riesgo. No lo abras ni escribas tus datos."
        case .medio: "Tiene señales de alerta. Verifica por un canal oficial antes de confiar."
        case .noEvaluado: "No pudimos evaluarlo. No escribas tus datos hasta confirmarlo por un canal oficial."
        case .bajo:
            senales == 0 ? "No encontramos señales de riesgo. Aun así, revisa que sea el sitio oficial."
                         : "Riesgo bajo, pero revisa las señales marcadas."
        }
    }
}
