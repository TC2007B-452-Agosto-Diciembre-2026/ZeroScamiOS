//
//  ReportSuccessView.swift
//  PrototipoApp
//
//  Reemplaza: escena `reportsuccess-vc` / ReportSuccessViewController.
//  Muestra el folio y el estado inicial. "Continuar" vuelve a Inicio con todas las pilas vacías
//  (antes `selectedIndex = 0` + `popToViewController(tabBarController)`); "Ver mis reportes" va a Perfil.
//

import SwiftUI

struct ReportSuccessView: View {
    let id: Int64

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 14) {
            Symbol("checkmark.circle.fill", size: 28, color: Theme.success)
                .frame(width: 56, height: 56)
                .background(Theme.success.opacity(0.2), in: Circle())
                .accessibilityHidden(true)

            Text("¡Reporte enviado con éxito!").ofraude(22, .bold, color: Theme.textLight)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: "Folio \(Formato.folio(id)) · Estado: \(EstadoReporte.recibido.titulo)")
                .ofraude(14, .semibold, color: Theme.accent)
                .accessibilityIdentifier("exito.folio")
            Text("Gracias por ayudar a mantener segura a la comunidad. Te avisaremos cuando el equipo de moderación lo revise.")
                .ofraude(14, color: Theme.textMuted)
                .multilineTextAlignment(.center)

            Button("CONTINUAR") { appState.popToTabs(selecting: .home) }
                .buttonStyle(OfraudeButtonStyle())
                .accessibilityIdentifier("exito.continuar")
            Button("VER MIS REPORTES") {
                appState.profileSegment = .misReportes
                appState.popToTabs(selecting: .profile)
            }
            .buttonStyle(OfraudeButtonStyle(background: .clear, foreground: Theme.textLight))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
            .accessibilityIdentifier("exito.misReportes")
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
        .ofraudeScreen()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { ReportSuccessView(id: 1_024) }
        .entornoDePrueba()
}
