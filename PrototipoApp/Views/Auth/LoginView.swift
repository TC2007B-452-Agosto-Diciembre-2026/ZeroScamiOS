//
//  LoginView.swift
//  PrototipoApp
//
//  Reemplaza: escena `login-vc` / LoginViewController (archivo ViewController.swift).
//  Ya no hay credenciales en el código: valida contra la sesión real (SessionStore). Tras 5 fallos
//  el servidor bloquea el correo y aquí se muestra la cuenta regresiva. Si la cuenta tiene
//  verificación en dos pasos, se pide el código en una hoja. «¿Olvidaste tu contraseña?» abre
//  RecuperarContrasenaView, que manda un código al correo.
//

import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appConfig) private var config

    @State private var correo = ""
    @State private var contrasena = ""
    @State private var error: String?
    @State private var bloqueadoHasta: Date?
    /// Se activa de forma síncrona antes de lanzar la petición: un segundo Return inmediato no entra.
    @State private var enviando = false
    @State private var recuperando = false
    @FocusState private var foco: Campo?

    private static let avisosDeExito: Set<String> = [SessionStore.avisoCuentaCreada, SessionStore.avisoContrasenaRestablecida]

    /// Con `.password` iOS ofrece autollenado y en el simulador eso rompe XCUITest; solo en las
    /// pruebas de interfaz se usa `.oneTimeCode`.
    private var tipoContrasena: UITextContentType { config.esUITest ? .oneTimeCode : .password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Estos 3 textos van centrados en el storyboard (textAlignment="center").
                MarcaZeroScam(size: 28)
                    .frame(maxWidth: .infinity)
                Text("Bienvenido de nuevo").ofraude(22, .bold, color: Theme.textLight)
                    .frame(maxWidth: .infinity)
                Text("Inicia sesión para seguir protegiendo a tu comunidad.")
                    .ofraude(14, color: Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                // «Cuenta creada», sesión vencida, cuenta eliminada: lo que dejó la pantalla anterior.
                if let aviso = session.aviso {
                    AvisoBanner(texto: aviso, tono: Self.avisosDeExito.contains(aviso) ? .exito : .info)
                        .accessibilityIdentifier("login.aviso")
                }

                VStack(alignment: .leading, spacing: 18) {
                    LabeledTextField(label: "CORREO ELECTRÓNICO", placeholder: "tucorreo@ejemplo.com", text: $correo,
                                     keyboard: .emailAddress, contenido: .username, maximo: 150,
                                     foco: $foco, campo: .correo, identificador: "login.correo")
                        .submitLabel(.next)
                        .onSubmit { foco = .contrasena }
                    LabeledSecureField(label: "CONTRASEÑA", placeholder: "••••••••", text: $contrasena, contenido: tipoContrasena,
                                       foco: $foco, campo: .contrasena, identificador: "login.contrasena")
                        .submitLabel(.go)
                        .onSubmit(enviarDesdeTeclado)
                    Button {
                        recuperando = true
                    } label: {
                        Text("¿Olvidaste tu contraseña?")
                            .ofraude(13, .medium, color: Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("login.olvide")
                }

                if let error {
                    Text(error).ofraude(13, .medium, color: Theme.dangerText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("login.error")
                }

                // Se redibuja cada segundo para la cuenta regresiva del bloqueo.
                TimelineView(.periodic(from: .now, by: 1)) { contexto in
                    let restante = segundosRestantes(en: contexto.date)
                    BotonAccion(titulo: restante > 0 ? "ESPERA \(restante) S" : "INICIAR SESIÓN",
                                habilitado: puedeEntrar(en: contexto.date),
                                identificador: "login.entrar") {
                        guard puedeEntrar(en: .now) else { return }
                        enviando = true
                        await entrar()
                    }
                    // Al terminar la espera desaparece el aviso de bloqueo.
                    .onChange(of: restante) { _, nuevo in
                        if nuevo == 0, bloqueadoHasta != nil {
                            bloqueadoHasta = nil
                            error = nil
                        }
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("¿No tienes cuenta? Crear cuenta")
                        .ofraude(14, color: Theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("login.irRegistro")
            }
            .padding(.horizontal, 28)
            .padding(.top, 90)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: desafio) { d in
            CodigoDosPasosView(desafio: d, mostrarCodigoDemo: config.fuente == .demo)
        }
        // Si se puso una contraseña nueva, el correo queda escrito y el bloqueo anterior ya no aplica.
        .sheet(isPresented: $recuperando, onDismiss: {
            guard session.aviso == SessionStore.avisoContrasenaRestablecida else { return }
            correo = session.correoSugerido
            contrasena = ""
            error = nil
            bloqueadoHasta = nil
        }) {
            RecuperarContrasenaView(correo: correo)
        }
        // Después de registrarse, el correo ya viene escrito.
        .onAppear { if correo.isEmpty { correo = session.correoSugerido } }
        // Otro correo es otra cuenta: el error y el bloqueo del anterior ya no aplican.
        .onChange(of: correo) {
            error = nil
            bloqueadoHasta = nil
        }
    }

    private var desafio: Binding<DesafioDosPasos?> {
        Binding(get: { session.desafio }, set: { if $0 == nil { session.cancelarDesafio() } })
    }

    /// Segundos que faltan del bloqueo; una fecha corrupta (NaN, infinita) no puede tronar la conversión.
    private func segundosRestantes(en ahora: Date) -> Int {
        guard let hasta = bloqueadoHasta else { return 0 }
        let s = hasta.timeIntervalSince(ahora).rounded(.up)
        guard s.isFinite, s > 0 else { return 0 }
        return Int(exactly: min(s, 86_400)) ?? 0
    }

    /// Una sola regla para el botón y para Return: campos llenos, sin petición en curso y sin espera.
    private func puedeEntrar(en ahora: Date) -> Bool {
        !correo.isEmpty && !contrasena.isEmpty && !enviando && segundosRestantes(en: ahora) == 0
    }

    private func enviarDesdeTeclado() {
        guard puedeEntrar(en: .now) else { return }
        enviando = true
        Task { await entrar() }
    }

    /// Quien la llama ya comprobó `puedeEntrar` y activó `enviando`.
    private func entrar() async {
        defer { enviando = false }
        error = nil
        foco = nil
        do {
            try await session.iniciarSesion(correo: correo, contrasena: contrasena)
        } catch let e as AppError {
            if case .cuentaBloqueada(let hasta) = e { bloqueadoHasta = hasta }
            error = e.mensaje()
            AccessibilityNotification.Announcement(e.mensaje()).post()
        } catch {
            self.error = error.mensajeUsuario
            AccessibilityNotification.Announcement(error.mensajeUsuario).post()
        }
        // La contraseña no se queda en memoria de la pantalla después de un intento.
        contrasena = ""
    }
}

#Preview {
    NavigationStack { LoginView() }
        .entornoDePrueba()
}
