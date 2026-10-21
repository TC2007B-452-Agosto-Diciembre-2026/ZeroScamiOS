//
//  RecuperarContrasenaView.swift
//  PrototipoApp
//
//  "¿Olvidaste tu contraseña?" desde Login. Dos pasos: el correo, y después el código que llegó
//  (10 minutos, 3 intentos) con la contraseña nueva. La respuesta es la misma exista o no la
//  cuenta, así que la pantalla nunca dice si el correo está registrado. Al terminar, Login
//  muestra el aviso y deja el correo escrito; las demás sesiones de la cuenta se cierran.
//

import SwiftUI

struct RecuperarContrasenaView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appConfig) private var config

    @State private var correo: String
    @State private var desafio: DesafioDosPasos?
    @State private var codigo = ""
    @State private var nueva = ""
    @State private var confirmacion = ""
    @State private var tocados: Set<Campo> = []
    @State private var error: String?
    @State private var errorCodigo: String?
    @State private var fallos = 0
    @FocusState private var foco: Campo?

    init(correo: String = "") {
        _correo = State(initialValue: correo)
    }

    private var restantes: Int { max(0, CodigoCorreo.intentosMaximos - fallos) }

    /// Sin sesión no se conoce el alias: la regla de "no uses tu usuario" se revisa con el correo.
    private var errores: [ErrorCampo] {
        Validador.contrasenaNueva(nueva, confirmacion: confirmacion, alias: "", correo: Sanitizador.correo(correo))
    }

    private func errorDe(_ campo: Campo) -> String? { tocados.contains(campo) ? errores.mensaje(para: campo) : nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Recuperar contraseña").ofraude(22, .bold, color: Theme.textLight)
                    if let desafio {
                        pasoCodigo(desafio)
                    } else {
                        pasoCorreo
                    }
                }
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .ofraudeScreen()
            .hideKeyboardOnTap()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .accessibilityIdentifier("recuperar.cancelar")
                }
            }
            .onChange(of: foco) { anterior, _ in
                if let anterior { tocados.insert(anterior) }
            }
        }
    }

    // MARK: Paso 1: correo

    private var pasoCorreo: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Escribe el correo de tu cuenta y te enviaremos un código para poner una contraseña nueva.")
                .ofraude(14, color: Theme.textMuted)
            LabeledTextField(label: "CORREO ELECTRÓNICO", placeholder: "tucorreo@ejemplo.com", text: $correo,
                             keyboard: .emailAddress, contenido: .username, maximo: 150,
                             foco: $foco, campo: .correo, identificador: "recuperar.correo")
            if let error { AvisoBanner(texto: error, tono: .error).accessibilityIdentifier("recuperar.error") }
            BotonAccion(titulo: "ENVIAR CÓDIGO", habilitado: Validador.esCorreoValido(Sanitizador.correo(correo)),
                        identificador: "recuperar.enviar") {
                await pedirCodigo()
            }
        }
    }

    // MARK: Paso 2: código y contraseña nueva

    private func pasoCodigo(_ d: DesafioDosPasos) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            CodigoCorreoSeccion(
                desafio: d,
                instrucciones: "Si \(d.destino) tiene una cuenta, le enviamos un código de 6 dígitos. Vence en 10 minutos.",
                mostrarCodigoDemo: config.fuente == .demo, codigo: $codigo, error: errorCodigo, foco: $foco)

            LabeledSecureField(label: "NUEVA CONTRASEÑA", placeholder: "••••••••", text: $nueva, contenido: .newPassword,
                               error: errorDe(.contrasena), foco: $foco, campo: .contrasena, identificador: "recuperar.nueva")
            LabeledSecureField(label: "CONFIRMAR NUEVA CONTRASEÑA", placeholder: "••••••••", text: $confirmacion,
                               contenido: .newPassword, error: errorDe(.confirmacion), foco: $foco, campo: .confirmacion,
                               identificador: "recuperar.confirmacion")
            ResumenErrores(errores: ["Mínimo 10 caracteres, con letras y números.",
                                     "No uses tu correo ni una contraseña común."], tono: .info)

            if let error { AvisoBanner(texto: error, tono: .error).accessibilityIdentifier("recuperar.error") }

            // Se redibuja cada segundo para detectar que el código ya venció.
            TimelineView(.periodic(from: .now, by: 1)) { contexto in
                let vencido = contexto.date >= d.expira
                VStack(alignment: .leading, spacing: 14) {
                    Text(CodigoCorreo.estado(restantes: restantes, vencido: vencido))
                        .ofraude(12, color: Theme.textMuted)
                        .accessibilityIdentifier("recuperar.intentos")
                    BotonAccion(titulo: "CAMBIAR CONTRASEÑA",
                                habilitado: errores.isEmpty && Validador.codigo(codigo).isEmpty && restantes > 0 && !vencido,
                                identificador: "recuperar.guardar") {
                        await restablecer(d)
                    }
                }
            }

            HStack {
                botonTexto("Enviar otro código", identificador: "recuperar.reenviar") {
                    Task { await pedirCodigo() }
                }
                botonTexto("Usar otro correo", identificador: "recuperar.otroCorreo") {
                    desafio = nil
                    codigo = ""
                    error = nil
                    errorCodigo = nil
                }
            }
        }
    }

    private func botonTexto(_ titulo: String, identificador: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(titulo)
                .ofraude(14, .medium, color: Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identificador)
    }

    // MARK: Acciones

    private func pedirCodigo() async {
        error = nil
        errorCodigo = nil
        foco = nil
        do {
            desafio = try await session.olvideContrasena(correo: correo)
            codigo = ""
            fallos = 0
            foco = .codigo
        } catch {
            self.error = error.mensajeUsuario
            AccessibilityNotification.Announcement(error.mensajeUsuario).post()
        }
    }

    private func restablecer(_ d: DesafioDosPasos) async {
        error = nil
        errorCodigo = nil
        guard Date() < d.expira else {
            errorCodigo = CodigoCorreo.textoVencido
            codigo = ""
            return
        }
        do {
            try await session.restablecerContrasena(correo: correo, desafio: d.id, codigo: codigo, nueva: nueva)
            nueva = ""
            confirmacion = ""
            dismiss()
        } catch {
            if (error as? AppError) == .codigoInvalido {
                // Solo un código equivocado gasta intento (una caída de red no).
                fallos = min(fallos + 1, CodigoCorreo.intentosMaximos)
                errorCodigo = error.mensajeUsuario
                codigo = ""
            } else {
                self.error = error.mensajeUsuario
            }
            AccessibilityNotification.Announcement(error.mensajeUsuario).post()
        }
    }
}

#Preview {
    RecuperarContrasenaView(correo: "ana@ejemplo.com")
        .entornoDePrueba()
}
