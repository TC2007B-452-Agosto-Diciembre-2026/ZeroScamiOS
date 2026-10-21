//
//  DiagnosticoURLView.swift
//  PrototipoApp
//
//  Diagnóstico preliminar de un enlace escrito en Buscar (RF07): qué tan confiable parece y por
//  qué. El análisis se pide al tocar el botón, no al escribir: queda anotado en el servidor para
//  avisar si el riesgo del enlace sube después. El enlace siempre se muestra desactivado.
//

import SwiftUI

struct DiagnosticoURLView: View {
    /// Enlace ya normalizado (`URLTools.normalizar`).
    let url: String

    @Environment(AppState.self) private var appState
    @Environment(ReportsStore.self) private var reports
    @State private var diagnostico: DiagnosticoURL?
    @State private var analizando = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Symbol("shield.lefthalf.filled", size: 14, color: Theme.accent)
                Text("DIAGNÓSTICO PRELIMINAR").ofraude(12, .bold, color: Theme.accent)
            }
            Text(verbatim: URLTools.desactivar(url))
                .ofraude(15, .semibold, color: Theme.textLight)
                .lineLimit(3)
                .accessibilityIdentifier("diagnostico.enlace")

            if let diagnostico {
                resultado(diagnostico)
            } else {
                Text("Revisamos su certificado, la antigüedad del dominio, su estructura y si la comunidad ya lo reportó. No abrimos el enlace en tu teléfono.")
                    .ofraude(13, color: Theme.textMuted)
                FieldError(mensaje: error)
                BotonAccion(titulo: analizando ? "ANALIZANDO…" : "ANALIZAR ENLACE", icono: "magnifyingglass",
                            estilo: OfraudeButtonStyle(foreground: Theme.background, size: 14, weight: .bold, radius: 4, height: 48),
                            habilitado: !analizando, identificador: "diagnostico.analizar") {
                    await analizar()
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8, fill: Theme.field)
        // Otro enlace es otro análisis: lo anterior ya no aplica.
        .onChange(of: url) {
            diagnostico = nil
            error = nil
        }
    }

    private func resultado(_ d: DiagnosticoURL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Symbol(d.veredicto.icono, size: 26, color: d.veredicto.color).accessibilityHidden(true)
                Text(d.veredicto.titulo).ofraude(22, .bold, color: d.veredicto.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Veredicto: \(d.veredicto.titulo.lowercased())")
            .accessibilityIdentifier("diagnostico.veredicto")
            HStack(alignment: .firstTextBaseline) {
                Etiqueta(texto: "RIESGO \(d.nivelRiesgo.titulo)", color: d.nivelRiesgo.color, fondo: d.nivelRiesgo.color.opacity(0.2))
                    .accessibilityIdentifier("diagnostico.riesgo")
                Spacer()
                Text(verbatim: "\(d.puntaje) / 100").ofraude(13, .semibold, color: Theme.textMuted)
                    .accessibilityLabel("\(d.puntaje) puntos de riesgo de 100")
            }
            // La barra repite el puntaje; la cifra y la etiqueta ya lo dicen con texto.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.textPrimary.opacity(0.12))
                    Capsule().fill(d.nivelRiesgo.color).frame(width: max(6, geo.size.width * CGFloat(d.puntaje) / 100))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)

            Text(d.resumen).ofraude(14, .semibold, color: Theme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(d.verificaciones) { v in
                    HStack(alignment: .top, spacing: 10) {
                        Symbol(v.paso ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", size: 16,
                               color: v.paso ? Theme.success : Theme.dangerText)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.tipo.titulo).ofraude(13, .bold, color: Theme.textPrimary)
                            Text(v.detalle).ofraude(13, color: Theme.textMuted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(v.tipo.titulo): \(v.paso ? "sin señales" : "señal de riesgo"). \(v.detalle)")
                }
            }

            Text(verbatim: "Analizado \(Formato.relativo(d.fecha).lowercased()). Es una estimación automática, no una garantía.")
                .ofraude(12, color: Theme.textSubtle)

            Button("REPORTAR ESTE SITIO") {
                appState.push(.report(ReportePrefill(tipo: .tiendaClonada, tipoOtro: nil, urlOTexto: d.url)))
            }
            .buttonStyle(OfraudeButtonStyle(background: Theme.card, foreground: Theme.accent, size: 14, weight: .semibold,
                                            radius: 4, height: 44))
            .accessibilityIdentifier("diagnostico.reportar")
        }
    }

    private func analizar() async {
        // El teclado tapaba el resultado.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        analizando = true
        defer { analizando = false }
        error = nil
        let pedido = url
        do {
            let resultado = try await reports.analizarURL(pedido)
            // Si mientras tanto escribieron otro enlace, esta respuesta ya no es la de pantalla.
            guard pedido == url else { return }
            diagnostico = resultado
        } catch {
            guard pedido == url else { return }
            self.error = error.mensajeUsuario
        }
    }
}
