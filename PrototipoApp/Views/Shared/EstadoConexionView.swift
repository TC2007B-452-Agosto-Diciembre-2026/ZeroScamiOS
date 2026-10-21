//
//  EstadoConexionView.swift
//  PrototipoApp
//
//  Aviso de Inicio y Reportar: sesión abierta sin conexión, reportes esperando la red, los que ya
//  se enviaron solos y los que el servidor rechazó (con Reintentar y Descartar). No ocupa lugar si
//  no hay nada que decir.
//

import SwiftUI

struct EstadoConexionView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ColaReportes.self) private var cola

    static let textoSinConexion = "Sin conexión. Puedes hacer reportes: se guardan en tu teléfono y se envían solos cuando regrese la red."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.sinConexion {
                AvisoBanner(texto: Self.textoSinConexion).accessibilityIdentifier("conexion.sinRed")
            }
            if cola.porEnviar > 0 {
                HStack(spacing: 12) {
                    AvisoBanner(texto: cola.porEnviar == 1
                                ? "1 reporte esperando conexión."
                                : "\(cola.porEnviar) reportes esperando conexión.")
                    if !session.sinConexion {
                        Button(cola.enviando ? "Enviando…" : "Enviar") { Task { await cola.enviarPendientes() } }
                            .disabled(cola.enviando)
                            .font(.footnote.bold())
                            .tint(Theme.accent)
                            .accessibilityIdentifier("conexion.enviar")
                    }
                }
                .accessibilityIdentifier("conexion.pendientes")
            }
            if cola.enviadosRecientes > 0 {
                AvisoBanner(texto: cola.enviadosRecientes == 1
                            ? "Se envió 1 reporte que estaba esperando conexión."
                            : "Se enviaron \(cola.enviadosRecientes) reportes que estaban esperando conexión.",
                            tono: .exito)
                    .onTapGesture { cola.olvidarEnviados() }
                    .accessibilityIdentifier("conexion.enviados")
            }
            ForEach(cola.pendientes.filter { $0.error != nil }) { p in
                VStack(alignment: .leading, spacing: 8) {
                    AvisoBanner(texto: "No se pudo enviar «\(p.borrador.titulo)»: \(p.error ?? "")", tono: .error)
                    HStack(spacing: 16) {
                        Button("Reintentar") { Task { await cola.reintentar(p.id) } }
                            .tint(Theme.accent)
                        Button("Descartar", role: .destructive) { cola.descartar(p.id) }
                            .tint(Theme.dangerText)
                    }
                    .font(.footnote.bold())
                }
            }
        }
    }
}
