//
//  Theme+Dominio.swift
//  PrototipoApp
//
//  Color de cada nivel de riesgo y de cada estado. Riesgo alto en `dangerText`: el rojo de marca
//  como texto pequeño no llega al contraste mínimo sobre el fondo azul.
//

import SwiftUI

extension DiagnosticoURL.Veredicto {
    var color: Color {
        switch self {
        case .pareceLegitimo: Theme.success
        case .dudoso: Theme.accent
        case .noLegitimo: Theme.dangerText
        }
    }

    var icono: String {
        switch self {
        case .pareceLegitimo: "checkmark.shield.fill"
        case .dudoso: "questionmark.diamond.fill"
        case .noLegitimo: "xmark.octagon.fill"
        }
    }
}

extension TipoFraude {
    var icono: String {
        switch self {
        case .ofertaFalsa: "tag.fill"
        case .sorteoFalso: "gift.fill"
        case .tiendaClonada: "storefront.fill"
        case .marketplace: "cart.fill"
        case .llamada: "phone.fill"
        case .otro: "exclamationmark.bubble.fill"
        }
    }
}

extension NivelRiesgo {
    var color: Color {
        switch self {
        case .muyAlto, .alto: Theme.dangerText
        case .medio: Theme.accent
        case .bajo: Theme.info
        case .noEvaluado: Theme.textSlate
        }
    }
}

extension EstadoReporte {
    var color: Color {
        switch self {
        case .recibido: Theme.textSlate
        case .enRevision: Theme.accent
        case .validado: Theme.success
        case .rechazado: Theme.dangerText
        case .canalizado: Theme.info
        }
    }
}
