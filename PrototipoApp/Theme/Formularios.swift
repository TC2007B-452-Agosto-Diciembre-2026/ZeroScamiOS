//
//  Formularios.swift
//  PrototipoApp
//
//  Piezas de formulario que se repiten en Registro, Login, Reportar, Perfil y Moderación:
//  errores bajo el campo, contraseñas ocultas, editor con contador, casilla, botón que no se
//  puede tocar dos veces, avisos y chips.
//

import SwiftUI

/// Mensaje de error bajo un campo. Rojo claro (`dangerText`) porque el rojo de marca no llega
/// al contraste mínimo como texto pequeño sobre el fondo azul.
struct FieldError: View {
    let mensaje: String?

    var body: some View {
        if let mensaje {
            Text(mensaje)
                .ofraude(12, .medium, color: Theme.dangerText)
                .accessibilityLabel("Error: \(mensaje)")
                .transition(.opacity)
        }
    }
}

/// Contraseña oculta por defecto, con botón de ojo para verla. El estado visible no se guarda.
struct OfraudeSecureField: View {
    let placeholder: String
    @Binding var text: String
    var contenido: UITextContentType = .password
    var error = false
    var foco: FocusState<Campo?>.Binding? = nil
    var campo: Campo? = nil
    var identificador: String? = nil
    /// Nombre del campo para VoiceOver (el placeholder "••••" no lo describe).
    var etiqueta: String? = nil

    @State private var visible = false
    @Environment(\.scenePhase) private var faseEscena

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if visible {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.textMuted))
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.textMuted))
                }
            }
            .textContentType(contenido)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .ofraudeFont(15)
            .foregroundStyle(Theme.textLight)
            .tint(Theme.accent)
            .enfoque(foco, campo)
            .identificador(identificador)
            .etiquetaAccesible(etiqueta)

            Button {
                visible.toggle()
                // Al cambiar entre SecureField y TextField se pierde el foco; se devuelve.
                if let foco, let campo { foco.wrappedValue = campo }
            } label: {
                Symbol(visible ? "eye.slash" : "eye", size: 18, color: Theme.textMuted)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(visible ? "Ocultar contraseña" : "Mostrar contraseña")
            .accessibilityHint("Cambia si la contraseña se ve o se oculta")
        }
        .padding(.leading, 13)
        .frame(minHeight: 48)
        .ofraudeCampo(error: error)
        // Al salir de primer plano la contraseña vuelve a ocultarse (captura del selector de apps).
        .onChange(of: faseEscena) { _, fase in
            if fase != .active { visible = false }
        }
    }
}

struct LabeledSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var contenido: UITextContentType = .password
    var error: String? = nil
    var foco: FocusState<Campo?>.Binding? = nil
    var campo: Campo? = nil
    var identificador: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(label).accessibilityHidden(true)
            OfraudeSecureField(placeholder: placeholder, text: $text, contenido: contenido, error: error != nil,
                               foco: foco, campo: campo, identificador: identificador, etiqueta: label)
            FieldError(mensaje: error)
        }
    }
}

/// Texto largo con placeholder encima (como el `UITextView` del original) y contador de caracteres.
struct OfraudeTextEditor: View {
    let placeholder: String
    @Binding var text: String
    let maximo: Int
    var altura: CGFloat = 120
    var error: String? = nil
    var foco: FocusState<Campo?>.Binding? = nil
    var campo: Campo? = nil
    var identificador: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .ofraudeFont(16)
                .foregroundStyle(Theme.textLight)
                .tint(Theme.accent)
                .scrollContentBackground(.hidden)
                .enfoque(foco, campo)
                .identificador(identificador)
                .accessibilityLabel(placeholder)
                .padding(4)
                .frame(minHeight: altura)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .ofraude(16, color: Theme.textMuted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .ofraudeCard()
                .overlay { if error != nil { Rectangle().strokeBorder(Theme.danger, lineWidth: 1) } }
            HStack(alignment: .top) {
                FieldError(mensaje: error)
                Spacer(minLength: 8)
                Text(verbatim: "\(text.count)/\(maximo)")
                    .ofraude(11, color: Theme.textMuted)
                    .accessibilityLabel("\(text.count) de \(maximo) caracteres")
            }
        }
        .onChange(of: text) { _, nuevo in
            if nuevo.count > maximo { text = String(nuevo.prefix(maximo)) }
        }
    }
}

/// Casilla para aceptar algo (aviso de privacidad, autorización de un tercero).
struct CasillaVerificacion: View {
    let texto: String
    @Binding var marcado: Bool
    var identificador: String? = nil

    var body: some View {
        Button { marcado.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Symbol(marcado ? "checkmark.square.fill" : "square", size: 22, color: marcado ? Theme.accent : Theme.textMuted)
                    .accessibilityHidden(true)
                Text(texto).ofraude(13, color: Theme.textLight).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(marcado ? "Marcado" : "Sin marcar")
        .identificador(identificador)
    }
}

/// Botón de una acción que tarda: muestra un indicador mientras trabaja y no se puede tocar dos
/// veces (evita reportes o comentarios duplicados).
struct BotonAccion: View {
    let titulo: String
    var icono: String? = nil
    var estilo = OfraudeButtonStyle()
    var habilitado = true
    var identificador: String? = nil
    let accion: () async -> Void

    @State private var trabajando = false

    var body: some View {
        Button {
            guard !trabajando else { return }
            trabajando = true
            Task {
                await accion()
                trabajando = false
            }
        } label: {
            ZStack {
                Group {
                    if let icono { Symbol(icono, size: 20, color: estilo.foreground) } else { Text(titulo) }
                }
                .opacity(trabajando ? 0 : 1)
                if trabajando { ProgressView().tint(estilo.foreground) }
            }
        }
        .buttonStyle(estilo)
        .disabled(!habilitado || trabajando)
        .opacity(habilitado ? 1 : 0.45)
        .accessibilityLabel(titulo)
        .accessibilityValue(trabajando ? "En proceso" : "")
        .identificador(identificador)
    }
}

/// Aviso en una franja de color (cuenta creada, sesión expirada, error del servidor).
struct AvisoBanner: View {
    enum Tono { case info, exito, error }

    let texto: String
    var tono: Tono = .info

    private var color: Color {
        switch tono {
        case .info: Theme.info
        case .exito: Theme.success
        case .error: Theme.dangerText
        }
    }

    private var icono: String {
        switch tono {
        case .info: "info.circle.fill"
        case .exito: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Symbol(icono, size: 18, color: color).accessibilityHidden(true)
            Text(texto).ofraude(13, .medium, color: Theme.textLight)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Lista de mensajes (mismo patrón que `ResumenErrores` de la práctica Demo-RetoSwiftUI452).
/// `.info` sirve para mostrar reglas antes de que haya errores.
struct ResumenErrores: View {
    let errores: [String]
    var tono: AvisoBanner.Tono = .error

    var body: some View {
        if !errores.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                // Por posición: dos mensajes iguales no deben chocar como identificador.
                ForEach(Array(errores.enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .top, spacing: 6) {
                        Symbol(tono == .error ? "exclamationmark.circle" : "info.circle", size: 13,
                               color: tono == .error ? Theme.dangerText : Theme.textMuted)
                            .accessibilityHidden(true)
                        Text(e).ofraude(13, color: tono == .error ? Theme.dangerText : Theme.textMuted)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// El aspecto de un chip (#Descuentos): el del storyboard, con borde naranja cuando está activo.
struct ChipEtiqueta: View {
    let titulo: String
    let activo: Bool

    var body: some View {
        Text(titulo)
            .ofraude(12, activo ? .semibold : .regular, color: activo ? Theme.accent : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(activo ? Theme.selected : Theme.card)
            .overlay(Rectangle().strokeBorder(activo ? Theme.accent : Theme.defaultBorder, lineWidth: 1))
    }
}

struct ChipFiltro: View {
    let titulo: String
    let activo: Bool
    var identificador: String? = nil
    let accion: () -> Void

    var body: some View {
        Button(action: accion) { ChipEtiqueta(titulo: titulo, activo: activo) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(activo ? .isSelected : [])
            .identificador(identificador)
    }
}

#Preview("Formularios") {
    @Previewable @State var texto = ""
    @Previewable @State var marcado = false
    VStack(alignment: .leading, spacing: 16) {
        LabeledTextField(label: "CORREO", placeholder: "tucorreo@ejemplo.com", text: $texto, error: "Escribe un correo válido.")
        LabeledSecureField(label: "CONTRASEÑA", placeholder: "••••••••", text: $texto)
        CasillaVerificacion(texto: "Acepto el aviso de privacidad.", marcado: $marcado)
        AvisoBanner(texto: "Cuenta creada. Inicia sesión para continuar.", tono: .exito)
        BotonAccion(titulo: "ENVIAR") { try? await Task.sleep(for: .seconds(1)) }
        HStack { ChipFiltro(titulo: "#Descuentos", activo: true) {}; ChipFiltro(titulo: "#SorteoFalso", activo: false) {} }
    }
    .padding()
    .ofraudeScreen()
}
