//
//  CodigoDosPasosView.swift
//  PrototipoApp
//
//  Segundo paso del login. En modo Demo no se envía ningún correo: el código "enviado" se
//  muestra en un aviso para poder presentarlo. Vence en 5 minutos y admite 3 intentos; para
//  recibir otro código se cancela y se inicia sesión de nuevo.
//

import SwiftUI

struct CodigoDosPasosView: View {
    let desafio: DesafioDosPasos
    let mostrarCodigoDemo: Bool

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var codigo = ""
    @State private var error: String?
    @State private var fallos = 0
    @FocusState private var foco: Campo?

    private static let intentosMaximos = 3

    private var restantes: Int { max(0, Self.intentosMaximos - fallos) }

    private func estado(vencido: Bool) -> String {
        if vencido { return Self.textoVencido }
        if restantes > 0 { return "Intentos restantes: \(restantes)" }
        return "Se agotaron los intentos. Cancela e inicia sesión de nuevo para recibir otro código."
    }

    private static let textoVencido = "El código venció. Cancela e inicia sesión de nuevo para recibir otro."

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Verificación en dos pasos").ofraude(22, .bold, color: Theme.textLight)
                Text(verbatim: "Escribe el código de 6 dígitos que enviamos a \(desafio.destino). Vence en 5 minutos.")
                    .ofraude(14, color: Theme.textMuted)
                if mostrarCodigoDemo, let demo = desafio.codigoDemo {
                    AvisoBanner(texto: "Modo demo: el correo con tu código diría «\(demo)».")
                        .accessibilityIdentifier("codigo.demo")
                }
                OfraudeTextField(placeholder: "000000", text: $codigo, keyboard: .numberPad,
                                 contenido: .oneTimeCode,
                                 maximo: 6, foco: $foco, campo: .codigo, identificador: "codigo.campo",
                                 etiqueta: "Código de verificación")
                FieldError(mensaje: error)
                    .accessibilityIdentifier("codigo.error")
                // Se redibuja cada segundo para detectar que el código ya venció.
                TimelineView(.periodic(from: .now, by: 1)) { contexto in
                    let vencido = contexto.date >= desafio.expira
                    VStack(alignment: .leading, spacing: 18) {
                        Text(estado(vencido: vencido))
                            .ofraude(12, color: Theme.textMuted)
                            .accessibilityIdentifier("codigo.intentos")
                        BotonAccion(titulo: "VERIFICAR",
                                    habilitado: Validador.codigo(codigo).isEmpty && restantes > 0 && !vencido,
                                    identificador: "codigo.verificar") {
                            await verificar()
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .ofraudeScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        session.cancelarDesafio()
                        dismiss()
                    }
                    .accessibilityIdentifier("codigo.cancelar")
                }
            }
            .onAppear { foco = .codigo }
        }
        .presentationDetents([.medium, .large])
    }

    private func verificar() async {
        error = nil
        guard Date() < desafio.expira else {
            error = Self.textoVencido
            AccessibilityNotification.Announcement(Self.textoVencido).post()
            codigo = ""
            return
        }
        do {
            try await session.verificarCodigo(codigo)
        } catch {
            // Solo un código equivocado gasta intento (una caída de red no).
            if (error as? AppError) == .codigoInvalido { fallos = min(fallos + 1, Self.intentosMaximos) }
            self.error = error.mensajeUsuario
            AccessibilityNotification.Announcement(error.mensajeUsuario).post()
            codigo = ""
        }
    }
}
