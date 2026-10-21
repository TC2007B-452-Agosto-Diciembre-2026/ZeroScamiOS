//
//  ReaceptarAvisoView.swift
//  PrototipoApp
//
//  Se muestra en lugar de la app cuando el aviso de privacidad cambió desde que la cuenta lo
//  aceptó (LFPDPPP art. 15-VI). Aceptar deja la versión y la fecha en el servidor; quien no acepte
//  puede cerrar sesión o eliminar su cuenta desde aquí, sin usar la app con un aviso que no aceptó.
//

import SwiftUI

struct ReaceptarAvisoView: View {
    @Environment(SessionStore.self) private var session
    @State private var acepta = false
    @State private var error: String?

    private enum Ruta: Hashable { case aviso, eliminar }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Symbol("hand.raised.fill", size: 32, color: Theme.accent).accessibilityHidden(true)
                    Text("Actualizamos el aviso de privacidad").ofraude(24, .bold, color: Theme.textLight)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "Versión \(Consentimiento.versionAvisoVigente). Antes de seguir, léelo y dinos si lo aceptas. Si no, puedes cerrar sesión o eliminar tu cuenta.")
                        .ofraude(14, color: Theme.textMuted)

                    AvisoSimplificadoView()
                    NavigationLink(value: Ruta.aviso) {
                        Text("Leer el aviso de privacidad completo ›").ofraude(14, .semibold, color: Theme.accent)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reaceptar.leer")

                    CasillaVerificacion(texto: "He leído y acepto el aviso de privacidad.", marcado: $acepta,
                                        identificador: "reaceptar.casilla")

                    if let error { AvisoBanner(texto: error, tono: .error) }

                    BotonAccion(titulo: "ACEPTAR Y CONTINUAR", habilitado: acepta, identificador: "reaceptar.aceptar") {
                        error = nil
                        do { try await session.aceptarAvisoVigente() } catch { self.error = error.mensajeUsuario }
                    }

                    VStack(spacing: 4) {
                        Button { Task { await session.cerrarSesion() } } label: {
                            Text("Cerrar sesión").ofraude(14, .semibold, color: Theme.textLight)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reaceptar.cerrarSesion")
                        NavigationLink(value: Ruta.eliminar) {
                            Text("Eliminar mi cuenta").ofraude(14, .semibold, color: Theme.dangerText)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reaceptar.eliminar")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .ofraudeScreen()
            .navigationDestination(for: Ruta.self) { ruta in
                switch ruta {
                case .aviso: PrivacyNoticeView()
                case .eliminar: DeleteAccountView()
                }
            }
        }
    }
}

#Preview {
    ReaceptarAvisoView()
        .entornoDePrueba()
}
