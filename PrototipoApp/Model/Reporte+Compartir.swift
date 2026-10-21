//
//  Reporte+Compartir.swift
//  PrototipoApp
//
//  Texto para compartir una alerta. El enlace va "desactivado" (hxxps, [.]) para que nadie lo
//  abra por accidente desde WhatsApp, y no incluye a quien reportó.
//

import Foundation

nonisolated extension Reporte {
    var textoParaCompartir: String {
        var lineas = ["Alerta de ZeroScam: \(titulo)", "Tipo: \(tipoVisible) · Riesgo: \(nivelRiesgo.titulo)"]
        if let url = sitio?.url {
            lineas.append("Sitio reportado (no lo abras): \(URLTools.desactivar(url))")
        } else if let textoSospechoso {
            lineas.append("Dato reportado: \(textoSospechoso)")
        }
        if !ciudad.isEmpty { lineas.append("Reportado en \(ciudad).") }
        lineas.append("Consulta más alertas en la app ZeroScam (de 0Fraude).")
        return lineas.joined(separator: "\n")
    }
}
