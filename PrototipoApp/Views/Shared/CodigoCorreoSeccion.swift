//
//  CodigoCorreoSeccion.swift
//  PrototipoApp
//
//  El código de 6 dígitos que llega por correo para cambiar o recuperar la contraseña: a dónde
//  se mandó, el aviso del modo Demo (ahí no sale ningún correo) y el campo. Dura 10 minutos y
//  admite 3 intentos; los intentos los cuenta la pantalla que lo usa, porque solo ella sabe si
//  el error fue del código o de otro dato.
//

import SwiftUI

struct CodigoCorreoSeccion: View {
    let desafio: DesafioDosPasos
    let instrucciones: String
    let mostrarCodigoDemo: Bool
    @Binding var codigo: String
    let error: String?
    var foco: FocusState<Campo?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: instrucciones)
                .ofraude(14, color: Theme.textMuted)
                .accessibilityIdentifier("codigoCorreo.instrucciones")
            if mostrarCodigoDemo, let demo = desafio.codigoDemo {
                AvisoBanner(texto: "Modo demo: el correo con tu código diría «\(demo)».")
                    .accessibilityIdentifier("codigoCorreo.demo")
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("CÓDIGO DEL CORREO").accessibilityHidden(true)
                OfraudeTextField(placeholder: "000000", text: $codigo, keyboard: .numberPad, contenido: .oneTimeCode,
                                 error: error != nil, maximo: 6, foco: foco, campo: .codigo,
                                 identificador: "codigoCorreo.campo", etiqueta: "Código del correo")
                FieldError(mensaje: error)
                    .accessibilityIdentifier("codigoCorreo.error")
            }
        }
    }
}

/// Reglas compartidas del código por correo.
enum CodigoCorreo {
    static let intentosMaximos = 3

    static let textoVencido = "El código venció. Pide uno nuevo."
    static let textoSinIntentos = "Se agotaron los intentos. Pide un código nuevo."

    static func estado(restantes: Int, vencido: Bool) -> String {
        if vencido { return textoVencido }
        if restantes > 0 { return "Intentos restantes: \(restantes)" }
        return textoSinIntentos
    }
}
