//
//  Fixtures.swift
//  PrototipoAppTests
//
//  Reportes de ejemplo para las pruebas.
//

import Foundation
@testable import PrototipoApp

extension Reporte {
    static func ejemplo(id: Int64 = 1,
                        titulo: String = "Tienda clonada de tenis deportivos",
                        descripcion: String = "Venden tenis a mitad de precio y nunca entregan.",
                        tipo: TipoFraude = .tiendaClonada,
                        riesgo: NivelRiesgo = .alto,
                        estado: EstadoReporte = .validado,
                        ciudad: String = "Monterrey",
                        url: String? = "https://n1ke-outlet-mexico.com",
                        texto: String? = nil) -> Reporte {
        Reporte(id: id,
                autor: AutorVisible(idUsuario: nil, nombre: "Anónimo"),
                tipo: tipo, tipoOtro: nil, estado: estado,
                titulo: titulo, descripcion: descripcion,
                fechaIncidente: Date(timeIntervalSince1970: 1_790_000_000),
                nivelRiesgo: riesgo,
                fechaCreacion: Date(timeIntervalSince1970: 1_790_000_000),
                esAnonimo: true, afectado: .yo, ciudad: ciudad, personaAfectada: nil,
                sitio: url.map { SitioWeb(id: 9, url: $0, nivelRiesgoGlobal: riesgo, estadoCertificado: "HTTPS", fechaUltimaEvaluacion: nil) },
                textoSospechoso: texto, evidencias: [], totalEvidencias: 0,
                confirmaciones: 0, comentarios: 0,
                confirmadoPorMi: false, guardadoPorMi: false, esMio: false)
    }
}
