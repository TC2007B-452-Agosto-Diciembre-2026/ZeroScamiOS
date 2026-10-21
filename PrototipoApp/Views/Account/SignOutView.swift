//
//  SignOutView.swift
//  PrototipoApp
//
//  Reemplaza: escena `signout-vc` / SignOutViewController.
//  «Cerrar sesión» revoca la sesión y vuelve a Registro (antes `popToRootViewController`);
//  «Cancelar» regresa. RootView limpia la navegación y los stores al quedar sin sesión.
//

import SwiftUI

struct SignOutView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ColaReportes.self) private var cola
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Symbol("rectangle.portrait.and.arrow.right", size: 28, color: Theme.danger)
                .frame(width: 56, height: 56)
                .background(Theme.danger.opacity(0.2), in: Circle())
                .accessibilityHidden(true)

            Text("¿Cerrar sesión?").ofraude(22, .bold, color: Theme.textLight)
            Text("Tendrás que iniciar sesión de nuevo para volver a acceder a tu cuenta.")
                .ofraude(14, color: Theme.textMuted)
                .multilineTextAlignment(.center)
            if !cola.pendientes.isEmpty {
                AvisoBanner(texto: cola.pendientes.count == 1
                            ? "Tienes 1 reporte sin enviar. Si cierras sesión se borra de este teléfono."
                            : "Tienes \(cola.pendientes.count) reportes sin enviar. Si cierras sesión se borran de este teléfono.",
                            tono: .error)
                    .accessibilityIdentifier("salir.pendientes")
            }

            BotonAccion(titulo: "CERRAR SESIÓN", estilo: OfraudeButtonStyle(background: Theme.danger),
                        identificador: "salir.confirmar") {
                // Los reportes sin enviar de esta persona no se quedan en el teléfono.
                if let id = session.usuario?.id { cola.borrar(usuario: id) }
                // Revoca el token en el servidor y lo borra del Keychain; RootView vuelve a Registro.
                await session.cerrarSesion()
            }

            Button("CANCELAR") { dismiss() }
                .buttonStyle(OfraudeButtonStyle(background: .clear, foreground: Theme.textLight))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.defaultBorder, lineWidth: 1))
                .accessibilityIdentifier("salir.cancelar")
        }
        .padding(.horizontal, 32)
        .padding(.top, 64)
        .frame(maxHeight: .infinity, alignment: .top)
        .ofraudeScreen()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { SignOutView() }
        .entornoDePrueba()
}
