//
//  Carga.swift
//  PrototipoApp
//
//  Estado de algo que se pide al backend. Las vistas lo pintan con `CargaView`
//  (Theme/EstadosVista.swift): indicador, contenido, vacío o error con "Reintentar".
//

import Foundation

nonisolated enum Carga<Valor> {
    case cargando
    case listo(Valor)
    case error(String)

    var valor: Valor? {
        if case .listo(let valor) = self { return valor }
        return nil
    }
}

nonisolated extension Carga: Equatable where Valor: Equatable {}
nonisolated extension Carga: Sendable where Valor: Sendable {}
