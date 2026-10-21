//
//  RegisterView.swift
//  PrototipoApp
//
//  Reemplaza: escena `reg-vc` / RegisterViewController. Es la pantalla de arranque.
//  Crea la cuenta de verdad: valida cada campo al salir de él, pide aceptar el aviso de
//  privacidad y al terminar lleva a Login con el correo escrito (el segue original Registro → Login).
//

import SwiftUI

struct RegisterView: View {
    var alCrearCuenta: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.appConfig) private var config
    @State private var datos = RegistroDatos()
    @State private var tocados: Set<Campo> = []
    @State private var errorServidor: String?
    @FocusState private var foco: Campo?

    /// Lo que se valida y se envía: sin espacios sobrantes ni caracteres invisibles.
    private var limpio: RegistroDatos {
        var d = datos
        d.nombre = Sanitizador.texto(d.nombre, maximo: 50)
        d.apellido = Sanitizador.texto(d.apellido, maximo: 50)
        d.alias = Sanitizador.alias(d.alias)
        d.correo = Sanitizador.correo(d.correo)
        return d
    }

    /// Con `.newPassword` iOS ofrece una contraseña segura, y en el simulador ese relleno automático se
    /// come las letras que teclea XCUITest en el primer campo (solo queda la última). Solo en las pruebas
    /// de interfaz se usa `.oneTimeCode`, que no activa ese relleno.
    private var tipoContrasena: UITextContentType { config.esUITest ? .oneTimeCode : .newPassword }

    private var errores: [ErrorCampo] { Validador.registro(limpio) }

    /// El error de un campo se muestra hasta que la persona sale de él (no mientras escribe).
    private func error(_ campo: Campo) -> String? {
        tocados.contains(campo) ? errores.mensaje(para: campo) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Únete a la comunidad y ayuda a prevenir fraudes.")
                    .ofraude(14, color: Theme.textMuted)

                HStack(alignment: .top, spacing: 12) {
                    LabeledTextField(label: "NOMBRE", placeholder: "Ana", text: $datos.nombre, contenido: .givenName,
                                     error: error(.nombre), maximo: 50, foco: $foco, campo: .nombre, identificador: "registro.nombre")
                    LabeledTextField(label: "APELLIDO", placeholder: "López", text: $datos.apellido, contenido: .familyName,
                                     error: error(.apellido), maximo: 50, foco: $foco, campo: .apellido, identificador: "registro.apellido")
                }
                LabeledTextField(label: "NOMBRE DE USUARIO", placeholder: "usuario_01", text: $datos.alias, contenido: .nickname,
                                 error: error(.alias), maximo: 20, foco: $foco, campo: .alias, identificador: "registro.alias")
                LabeledTextField(label: "CORREO ELECTRÓNICO", placeholder: "tucorreo@ejemplo.com", text: $datos.correo,
                                 keyboard: .emailAddress, contenido: .username, error: error(.correo), maximo: 150,
                                 foco: $foco, campo: .correo, identificador: "registro.correo")

                VStack(alignment: .leading, spacing: 8) {
                    // El selector ya se llama "País" para VoiceOver; la etiqueta visual se oculta.
                    FieldLabel("PAÍS").accessibilityHidden(true)
                    Picker("País", selection: $datos.pais) {
                        ForEach(Validador.paises, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.textLight)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .ofraudeCampo()
                    .accessibilityIdentifier("registro.pais")
                }

                LabeledSecureField(label: "CONTRASEÑA", placeholder: "••••••••", text: $datos.contrasena, contenido: tipoContrasena,
                                   error: error(.contrasena), foco: $foco, campo: .contrasena, identificador: "registro.contrasena")
                Text("Mínimo 10 caracteres, con letras y números. Una frase larga es más segura.")
                    .ofraude(12, color: Theme.textMuted)
                LabeledSecureField(label: "CONFIRMAR CONTRASEÑA", placeholder: "••••••••", text: $datos.confirmacion,
                                   contenido: tipoContrasena, error: error(.confirmacion), foco: $foco, campo: .confirmacion,
                                   identificador: "registro.confirmacion")

                CasillaVerificacion(texto: "He leído y acepto el aviso de privacidad.", marcado: $datos.aceptaAviso,
                                    identificador: "registro.aviso")
                NavigationLink(value: AuthRoute.aviso) {
                    Text("Leer el aviso de privacidad ›").ofraude(13, .semibold, color: Theme.accent)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("registro.leerAviso")

                if let errorServidor { AvisoBanner(texto: errorServidor, tono: .error) }

                BotonAccion(titulo: "CREAR CUENTA", habilitado: errores.isEmpty, identificador: "registro.crear") {
                    await crear()
                }
                if !errores.isEmpty {
                    Text("Completa los campos para crear tu cuenta.")
                        .ofraude(12, color: Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }

                NavigationLink(value: AuthRoute.login) {
                    Text("¿Ya tienes cuenta? Inicia sesión")
                        .ofraude(14, color: Theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("registro.irLogin")
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Crear cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: foco) { anterior, _ in
            if let anterior { tocados.insert(anterior) }
        }
    }

    private func crear() async {
        errorServidor = nil
        do {
            try await session.registrar(limpio)
            datos = RegistroDatos()
            tocados = []
            alCrearCuenta()
        } catch {
            let mensaje = error.mensajeUsuario
            errorServidor = mensaje
            AccessibilityNotification.Announcement(mensaje).post()
        }
    }
}

#Preview {
    NavigationStack { RegisterView() }
        .entornoDePrueba()
}
