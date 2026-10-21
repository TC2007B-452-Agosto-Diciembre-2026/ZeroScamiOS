//
//  ConfirmarContrasenaView.swift
//  PrototipoApp
//
//  Pide la contraseña actual antes de un cambio delicado (cambiar el correo, apagar la
//  verificación en dos pasos). Así, alguien con el teléfono desbloqueado no puede hacerlo solo.
//

import SwiftUI

struct ConfirmarContrasenaView: View {
    let titulo: String
    let mensaje: String
    let boton: String
    let accion: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contrasena = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(titulo).ofraude(22, .bold, color: Theme.textLight)
                Text(mensaje).ofraude(14, color: Theme.textMuted)
                LabeledSecureField(label: "CONTRASEÑA ACTUAL", placeholder: "••••••••", text: $contrasena,
                                   contenido: .password, identificador: "confirmar.contrasena")
                FieldError(mensaje: error)
                BotonAccion(titulo: boton, habilitado: !contrasena.isEmpty, identificador: "confirmar.boton") {
                    do {
                        try await accion(contrasena)
                        dismiss()
                    } catch {
                        self.error = error.mensajeUsuario
                        contrasena = ""
                    }
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .ofraudeScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
