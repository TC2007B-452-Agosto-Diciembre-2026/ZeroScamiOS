//
//  ChangePasswordView.swift
//  PrototipoApp
//
//  Reemplaza: escena `changepw-vc` / ChangePasswordViewController. Antes "Guardar" solo
//  regresaba. Ahora pide la contraseña actual, aplica la política a la nueva y confirma con un
//  código que llega al correo de la cuenta (10 minutos, 3 intentos). Al guardar cierra las
//  sesiones abiertas en otros dispositivos y el servidor avisa por correo del cambio.
//

import SwiftUI

struct ChangePasswordView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appConfig) private var config

    @State private var actual = ""
    @State private var nueva = ""
    @State private var confirmacion = ""
    @State private var tocados: Set<Campo> = []
    @State private var error: String?
    @State private var listo = false
    /// `nil` mientras no se ha pedido el código.
    @State private var desafio: DesafioDosPasos?
    @State private var codigo = ""
    @State private var errorCodigo: String?
    @State private var fallos = 0
    @FocusState private var foco: Campo?

    private static let mensajeActualIncorrecta = "Tu contraseña actual no es correcta. Pide un código nuevo para intentarlo otra vez."

    private var errores: [ErrorCampo] {
        guard let u = session.usuario else { return [] }
        var lista = Validador.contrasenaNueva(nueva, confirmacion: confirmacion, alias: u.alias, correo: u.correo)
        if actual.isEmpty { lista.append(ErrorCampo(campo: .contrasenaActual, mensaje: "Escribe tu contraseña actual.")) }
        if !actual.isEmpty && actual == nueva {
            lista.append(ErrorCampo(campo: .contrasena, mensaje: "La nueva contraseña debe ser distinta de la actual."))
        }
        return lista
    }

    private var restantes: Int { max(0, CodigoCorreo.intentosMaximos - fallos) }

    private func errorDe(_ campo: Campo) -> String? { tocados.contains(campo) ? errores.mensaje(para: campo) : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Actualiza tu clave de acceso para mantener tu cuenta segura. Te enviaremos un código a tu correo para confirmar que eres tú.")
                    .ofraude(14, color: Theme.textMuted)

                LabeledSecureField(label: "CONTRASEÑA ACTUAL", placeholder: "••••••••", text: $actual, contenido: .password,
                                   error: errorDe(.contrasenaActual), foco: $foco, campo: .contrasenaActual,
                                   identificador: "contrasena.actual")
                LabeledSecureField(label: "NUEVA CONTRASEÑA", placeholder: "••••••••", text: $nueva, contenido: .newPassword,
                                   error: errorDe(.contrasena), foco: $foco, campo: .contrasena, identificador: "contrasena.nueva")
                LabeledSecureField(label: "CONFIRMAR NUEVA CONTRASEÑA", placeholder: "••••••••", text: $confirmacion,
                                   contenido: .newPassword, error: errorDe(.confirmacion), foco: $foco, campo: .confirmacion,
                                   identificador: "contrasena.confirmacion")
                ResumenErrores(errores: ["Mínimo 10 caracteres, con letras y números.",
                                         "No uses tu usuario, tu correo ni una contraseña común."], tono: .info)

                if let desafio {
                    CodigoCorreoSeccion(desafio: desafio, instrucciones: instrucciones(desafio),
                                        mostrarCodigoDemo: config.fuente == .demo, codigo: $codigo,
                                        error: errorCodigo, foco: $foco)
                }

                if let error { AvisoBanner(texto: error, tono: .error).accessibilityIdentifier("contrasena.error") }

                if let desafio {
                    // Se redibuja cada segundo para detectar que el código ya venció.
                    TimelineView(.periodic(from: .now, by: 1)) { contexto in
                        let vencido = contexto.date >= desafio.expira
                        VStack(alignment: .leading, spacing: 14) {
                            Text(CodigoCorreo.estado(restantes: restantes, vencido: vencido))
                                .ofraude(12, color: Theme.textMuted)
                                .accessibilityIdentifier("contrasena.intentos")
                            BotonAccion(titulo: "GUARDAR CONTRASEÑA",
                                        habilitado: errores.isEmpty && Validador.codigo(codigo).isEmpty && restantes > 0 && !vencido,
                                        identificador: "contrasena.guardar") {
                                await guardar(desafio)
                            }
                            botonReenviar
                        }
                    }
                } else {
                    BotonAccion(titulo: "ENVIAR CÓDIGO A MI CORREO", habilitado: errores.isEmpty,
                                identificador: "contrasena.pedirCodigo") {
                        await pedirCodigo()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Cambiar contraseña")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: foco) { anterior, _ in
            if let anterior { tocados.insert(anterior) }
        }
        .alert("Contraseña actualizada", isPresented: $listo) {
            Button("Aceptar") { dismiss() }
        } message: {
            Text(config.fuente == .demo
                 ? "Cerramos tus sesiones en otros dispositivos."
                 : "Te avisamos por correo y cerramos tus sesiones en otros dispositivos.")
        }
    }

    private var botonReenviar: some View {
        Button {
            Task { await pedirCodigo() }
        } label: {
            Text("Enviar otro código")
                .ofraude(14, .medium, color: Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("contrasena.reenviar")
    }

    private func instrucciones(_ d: DesafioDosPasos) -> String {
        let destino = d.destino.isEmpty ? "tu correo" : d.destino
        return "Escribe el código de 6 dígitos que enviamos a \(destino). Vence en 10 minutos."
    }

    private func pedirCodigo() async {
        error = nil
        errorCodigo = nil
        do {
            desafio = try await session.pedirCodigoContrasena()
            codigo = ""
            fallos = 0
            foco = .codigo
        } catch {
            self.error = error.mensajeUsuario
            AccessibilityNotification.Announcement(error.mensajeUsuario).post()
        }
    }

    private func guardar(_ d: DesafioDosPasos) async {
        error = nil
        errorCodigo = nil
        guard Date() < d.expira else {
            errorCodigo = CodigoCorreo.textoVencido
            codigo = ""
            return
        }
        do {
            try await session.cambiarContrasena(actual: actual, nueva: nueva, desafio: d.id, codigo: codigo)
            actual = ""
            nueva = ""
            confirmacion = ""
            codigo = ""
            desafio = nil
            listo = true
        } catch let e as AppError {
            switch e {
            case .codigoInvalido:
                // Solo un código equivocado gasta intento (una caída de red no).
                fallos = min(fallos + 1, CodigoCorreo.intentosMaximos)
                errorCodigo = e.mensaje()
                codigo = ""
            case .credencialesInvalidas, .cuentaBloqueada:
                // El servidor revisa el código antes que la contraseña actual: el código ya se gastó.
                desafio = nil
                codigo = ""
                error = e == .credencialesInvalidas ? Self.mensajeActualIncorrecta : e.mensaje()
            default:
                error = e.mensaje()
            }
            AccessibilityNotification.Announcement(errorCodigo ?? error ?? e.mensaje()).post()
        } catch {
            self.error = error.mensajeUsuario
        }
    }
}

#Preview {
    NavigationStack { ChangePasswordView() }
        .entornoDePrueba()
}
