//
//  DeleteAccountView.swift
//  PrototipoApp
//
//  Derecho de cancelación. Explica qué se borra y qué se queda anónimo, y pide dos pruebas de
//  intención: la contraseña y escribir ELIMINAR.
//

import SwiftUI

struct DeleteAccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ColaReportes.self) private var cola
    @State private var contrasena = ""
    @State private var confirmacion = ""
    @State private var preguntar = false
    @State private var error: String?

    private var listo: Bool { !contrasena.isEmpty && confirmacion.trimmingCharacters(in: .whitespaces) == "ELIMINAR" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Eliminar mi cuenta").ofraude(24, .bold, color: Theme.textLight).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Qué pasa al eliminarla").ofraude(15, .bold, color: Theme.textLight)
                    Text("• Se borran tu cuenta, tus guardados, tus confirmaciones, tus notificaciones y tus reportes que aún no se validan, con su evidencia.").ofraude(14, color: Theme.textMuted)
                    Text("• Tus reportes ya validados se quedan para alertar a la comunidad, pero sin tu nombre, sin datos de terceros y sin evidencia.").ofraude(14, color: Theme.textMuted)
                    Text("• Tus comentarios se quedan como «Cuenta eliminada».").ofraude(14, color: Theme.textMuted)
                    Text("• No se puede deshacer.").ofraude(14, .semibold, color: Theme.dangerText)
                }
                .padding(16)
                .ofraudeCard(radius: 8)

                LabeledSecureField(label: "CONTRASEÑA", placeholder: "••••••••", text: $contrasena, contenido: .password,
                                   identificador: "eliminar.contrasena")
                LabeledTextField(label: "ESCRIBE ELIMINAR PARA CONFIRMAR", placeholder: "ELIMINAR", text: $confirmacion,
                                 maximo: 20, identificador: "eliminar.confirmacion")
                if let error { AvisoBanner(texto: error, tono: .error) }
                BotonAccion(titulo: "ELIMINAR MI CUENTA", estilo: OfraudeButtonStyle(background: Theme.danger),
                            habilitado: listo, identificador: "eliminar.boton") {
                    preguntar = true
                }
            }
            .padding(24)
        }
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Eliminar cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .alert("¿Eliminar tu cuenta para siempre?", isPresented: $preguntar) {
            Button("Eliminar mi cuenta", role: .destructive) { Task { await eliminar() } }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func eliminar() async {
        do {
            let id = session.usuario?.id
            try await session.eliminarCuenta(contrasena: contrasena)
            // Sus reportes sin enviar tampoco se quedan en el teléfono.
            if let id { cola.borrar(usuario: id) }
        } catch {
            self.error = error.mensajeUsuario
            contrasena = ""
        }
    }
}
