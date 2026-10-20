//
//  EstadosVista.swift
//  PrototipoApp
//
//  Cargando, vacío y error para cualquier lista (`CargaView`), la pantalla de arranque mientras
//  se revisa la sesión y el escudo que tapa la app en el selector de apps.
//

import SwiftUI

struct EstadoVacio {
    let icono: String
    let titulo: String
    let mensaje: String
}

struct CargaView<Valor, Contenido: View>: View {
    let carga: Carga<Valor>
    var esVacio: (Valor) -> Bool = { _ in false }
    var vacio = EstadoVacio(icono: "tray", titulo: "Sin datos", mensaje: "")
    let reintentar: () async -> Void
    @ViewBuilder let contenido: (Valor) -> Contenido

    var body: some View {
        switch carga {
        case .cargando:
            ProgressView()
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel("Cargando")
        case .error(let mensaje):
            ErrorEstadoView(mensaje: mensaje, reintentar: reintentar)
        case .listo(let valor):
            if esVacio(valor) { EstadoVacioView(estado: vacio) } else { contenido(valor) }
        }
    }
}

struct EstadoVacioView: View {
    let estado: EstadoVacio

    var body: some View {
        VStack(spacing: 8) {
            Symbol(estado.icono, size: 32, color: Theme.textSlate).accessibilityHidden(true)
            Text(estado.titulo).ofraude(16, .semibold, color: Theme.textLight)
            if !estado.mensaje.isEmpty {
                Text(estado.mensaje).ofraude(13, color: Theme.textMuted).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorEstadoView: View {
    let mensaje: String
    let reintentar: () async -> Void

    var body: some View {
        VStack(spacing: 10) {
            Symbol("exclamationmark.triangle", size: 32, color: Theme.dangerText).accessibilityHidden(true)
            Text(mensaje).ofraude(14, color: Theme.textLight).multilineTextAlignment(.center)
            BotonAccion(titulo: "REINTENTAR",
                        estilo: OfraudeButtonStyle(background: Theme.card, foreground: Theme.accent, size: 14,
                                                   weight: .semibold, radius: 8, height: 44, fullWidth: false),
                        identificador: "estado.reintentar") {
                await reintentar()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Mientras se revisa el token guardado (un instante al abrir la app).
struct LaunchGateView: View {
    var body: some View {
        VStack(spacing: 16) {
            MarcaZeroScam(size: 28)
            ProgressView().tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ofraudeScreen()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ZeroScam, cargando")
    }
}

/// Lo que se ve en el selector de apps: iOS guarda una captura al salir de primer plano.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Symbol("lock.shield.fill", size: 48, color: Theme.accent)
                MarcaZeroScam(size: 24, color: Theme.textPrimary)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Estados") {
    VStack(spacing: 8) {
        CargaView(carga: Carga<[String]>.cargando, reintentar: {}) { _ in EmptyView() }
        CargaView(carga: Carga<[String]>.listo([]), esVacio: { $0.isEmpty },
                  vacio: EstadoVacio(icono: "tray", titulo: "Sin reportes", mensaje: "Aún no hay reportes."),
                  reintentar: {}) { _ in EmptyView() }
        CargaView(carga: Carga<[String]>.error("No se pudo cargar."), reintentar: {}) { _ in EmptyView() }
    }
    .ofraudeScreen()
}
