//
//  EditProfileView.swift
//  PrototipoApp
//
//  Reemplaza: escena `editprofile-vc` / EditProfileViewController. Antes "Guardar cambios" solo
//  regresaba y "Cambiar Avatar" era texto. Ahora guarda con validación (derecho de
//  rectificación), pide la contraseña si cambia el correo y la foto se guarda sin metadatos.
//

import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports
    @Environment(\.dismiss) private var dismiss

    @State private var datos = PerfilDatos(desde: Usuario.vacio)
    @State private var cargado = false
    @State private var tocados: Set<Campo> = []
    @State private var pedirContrasena = false
    @State private var error: String?
    @State private var foto: PhotosPickerItem?
    @State private var procesandoFoto = false
    @FocusState private var foco: Campo?

    private var original: Usuario? { session.usuario }

    private var limpio: PerfilDatos {
        var d = datos
        d.nombre = Sanitizador.texto(d.nombre, maximo: 50)
        d.apellido = Sanitizador.texto(d.apellido, maximo: 50)
        d.alias = Sanitizador.alias(d.alias)
        d.correo = Sanitizador.correo(d.correo)
        d.biografia = Sanitizador.texto(d.biografia, maximo: 300, multilinea: true)
        return d
    }

    /// La contraseña para cambiar el correo se pide en una hoja aparte, así que no bloquea el botón.
    private var errores: [ErrorCampo] {
        Validador.perfil(limpio, correoOriginal: original?.correo ?? "").filter { $0.campo != .contrasenaActual }
    }

    private func errorDe(_ campo: Campo) -> String? { tocados.contains(campo) ? errores.mensaje(para: campo) : nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AvatarView(usuario: original, tamano: 128)
                    .overlay(Circle().strokeBorder(Theme.defaultBorder, lineWidth: 4))
                    .overlay { if procesandoFoto { ProgressView().tint(Theme.accent) } }

                HStack(spacing: 20) {
                    PhotosPicker(selection: $foto, matching: .images) {
                        Text("Cambiar Avatar").ofraude(15, color: Theme.accent)
                    }
                    .accessibilityIdentifier("perfil.avatar")
                    if original?.avatarRuta != nil {
                        Button { Task { await quitarAvatar() } } label: {
                            Text("Quitar foto").ofraude(15, color: Theme.dangerText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("perfil.quitarAvatar")
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    LabeledTextField(label: "NOMBRE", placeholder: "", text: $datos.nombre, contenido: .givenName,
                                     error: errorDe(.nombre), maximo: 50, foco: $foco, campo: .nombre, identificador: "perfil.nombre")
                    LabeledTextField(label: "APELLIDO", placeholder: "", text: $datos.apellido, contenido: .familyName,
                                     error: errorDe(.apellido), maximo: 50, foco: $foco, campo: .apellido, identificador: "perfil.apellido")
                }
                LabeledTextField(label: "NOMBRE DE USUARIO", placeholder: "", text: $datos.alias, contenido: .nickname,
                                 error: errorDe(.alias), maximo: 20, foco: $foco, campo: .alias, identificador: "perfil.alias")
                LabeledTextField(label: "CORREO ELECTRÓNICO (PRIVADO)", placeholder: "", text: $datos.correo,
                                 keyboard: .emailAddress, contenido: .emailAddress, error: errorDe(.correo), maximo: 150,
                                 foco: $foco, campo: .correo, identificador: "perfil.correo")

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("PAÍS")
                    Picker("País", selection: $datos.pais) {
                        ForEach(Validador.paises, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.textLight)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .ofraudeCampo()
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("BIOGRAFÍA / ESPECIALIDAD")
                    OfraudeTextEditor(placeholder: "Breve descripción de tus áreas de investigación...", text: $datos.biografia,
                                      maximo: 300, error: errorDe(.biografia), foco: $foco, campo: .biografia,
                                      identificador: "perfil.biografia")
                }

                if let error { AvisoBanner(texto: error, tono: .error) }

                BotonAccion(titulo: "GUARDAR CAMBIOS", estilo: OfraudeButtonStyle(size: 15, weight: .semibold, radius: 4),
                            habilitado: errores.isEmpty, identificador: "perfil.guardar") {
                    if limpio.correo != original?.correo { pedirContrasena = true } else { await guardar(contrasena: nil) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Editar perfil")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !cargado, let original else { return }
            datos = PerfilDatos(desde: original)
            cargado = true
        }
        .onChange(of: foco) { anterior, _ in
            if let anterior { tocados.insert(anterior) }
        }
        .onChange(of: foto) { _, item in
            guard let item else { return }
            Task { await cambiarAvatar(item) }
        }
        .sheet(isPresented: $pedirContrasena) {
            ConfirmarContrasenaView(titulo: "Confirma tu contraseña",
                                    mensaje: "Para cambiar tu correo necesitamos confirmar que eres tú.",
                                    boton: "CONFIRMAR Y GUARDAR") { contrasena in
                try await guardarOLanzar(contrasena: contrasena)
            }
        }
    }

    private func guardar(contrasena: String?) async {
        do { try await guardarOLanzar(contrasena: contrasena) } catch { self.error = error.mensajeUsuario }
    }

    private func guardarOLanzar(contrasena: String?) async throws {
        error = nil
        var d = limpio
        d.contrasenaActual = contrasena
        try await session.actualizarPerfil(d)
        dismiss()
    }

    private func cambiarAvatar(_ item: PhotosPickerItem) async {
        procesandoFoto = true
        defer { procesandoFoto = false; foto = nil }
        do {
            guard let datos = try await item.loadTransferable(type: Data.self) else { return }
            let limpia = try await Task.detached(priority: .userInitiated) {
                try ProcesadorEvidencia.limpiarImagen(datos, ladoMaximo: 512)
            }.value
            try await session.actualizarAvatar(try reports.archivos.guardarTemporal(limpia, tipo: "image/jpeg"))
        } catch {
            self.error = "No se pudo usar esa imagen."
        }
    }

    private func quitarAvatar() async {
        do { try await session.actualizarAvatar(nil) } catch { self.error = error.mensajeUsuario }
    }
}

#Preview {
    NavigationStack { EditProfileView() }
        .entornoDePrueba()
}
