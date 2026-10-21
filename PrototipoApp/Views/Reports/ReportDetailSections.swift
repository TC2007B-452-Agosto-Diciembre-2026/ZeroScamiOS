//
//  ReportDetailSections.swift
//  PrototipoApp
//
//  Piezas del detalle que también usa la revisión de moderación: el sitio reportado,
//  el estado con su historial y la persona afectada.
//

import SwiftUI

/// El enlace o dato reportado, "desactivado": nunca se puede abrir ni copiar desde la app.
struct SitioSospechosoView: View {
    let reporte: Reporte

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Symbol("exclamationmark.triangle.fill", size: 14, color: Theme.danger)
                Text("NO ABRAS ESTE ENLACE").ofraude(12, .bold, color: Theme.dangerText)
            }
            if let sitio = reporte.sitio {
                Text(verbatim: URLTools.desactivar(sitio.url))
                    .ofraude(15, .semibold, color: Theme.textLight)
                    .accessibilityIdentifier("detalle.sitio")
                Text(verbatim: "\(sitio.estadoCertificado ?? "SIN DATOS") · Riesgo del sitio: \(sitio.nivelRiesgoGlobal.titulo)")
                    .ofraude(12, color: Theme.textMuted)
                if URLTools.esPosibleHomografo(sitio.url) {
                    Text("Este dominio usa caracteres que imitan a otros (posible homógrafo).")
                        .ofraude(12, .semibold, color: Theme.accent)
                }
            } else if let texto = reporte.textoSospechoso {
                Text(texto).ofraude(15, .semibold, color: Theme.textLight).textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8, fill: Theme.field)
    }
}

/// Estado actual y la historia de cambios (solo autor y staff).
struct EstadoReporteView: View {
    let reporte: Reporte
    let historial: [HistorialEstado]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ESTADO").ofraude(12, .bold, color: Theme.textMuted)
                Etiqueta(texto: reporte.estado.titulo, color: reporte.estado.color, fondo: reporte.estado.color.opacity(0.2))
                    .accessibilityIdentifier("detalle.estado")
            }
            ForEach(historial) { h in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(h.nuevo.titulo) · \(Formato.relativo(h.fecha)) · \(h.responsable)")
                        .ofraude(12, .semibold, color: Theme.textLight)
                    if let observaciones = h.observaciones {
                        Text(observaciones).ofraude(12, color: Theme.textMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8)
    }
}

/// Datos de un tercero: nunca públicos.
struct PersonaAfectadaView: View {
    let persona: PersonaAfectada

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Symbol("lock.fill", size: 12, color: Theme.textMuted)
                Text("PERSONA AFECTADA (PRIVADO)").ofraude(12, .bold, color: Theme.textMuted)
            }
            Text(persona.nombre).ofraude(15, .semibold, color: Theme.textLight)
            Text(persona.contacto).ofraude(13, color: Theme.textMuted)
            Text("Solo tú y el equipo de moderación ven estos datos.").ofraude(12, color: Theme.textSubtle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8, fill: Theme.field)
        .accessibilityElement(children: .combine)
    }
}
