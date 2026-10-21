//
//  PrivacyView.swift
//  PrototipoApp
//
//  Reemplaza: escena `privacy-vc` / PrivacyViewController. Los switches ya no son decorativos:
//  - Autenticación en 2 pasos: pide un código al iniciar sesión; apagarla exige la contraseña.
//  - Perfil público: decide si la comunidad ve tu alias en reportes y comentarios.
//  - Analíticas anónimas: cuenta (o no) eventos sin identificarte.
//  También es la puerta a los derechos ARCO (aviso, exportar, eliminar cuenta).
//

import SwiftUI

struct PrivacyView: View {
    @Environment(SessionStore.self) private var session
    @State private var pedirContrasena = false
    @State private var error: String?
    @State private var exportado: URL?
    @State private var exportando = false

    private var preferencias: Preferencias { session.usuario?.preferencias ?? Preferencias() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                section("SEGURIDAD") {
                    NavigationLink(value: Route.changePassword) {
                        Text("CAMBIAR CONTRASEÑA")
                            .ofraude(15, .semibold, color: Theme.textLight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacidad.cambiarContrasena")
                    Hairline()
                    toggleRow("Autenticación en 2 pasos", "Te pediremos un código al iniciar sesión",
                              isOn: Binding(get: { preferencias.dosPasos }, set: { nuevo in
                                  if nuevo { Task { await cambiar { $0.dosPasos = true } } } else { pedirContrasena = true }
                              }), id: "privacidad.dosPasos")
                }

                section("PRIVACIDAD") {
                    toggleRow("Perfil Público", "Mostrar tu nombre de usuario en tus reportes y comentarios",
                              isOn: Binding(get: { preferencias.perfilPublico },
                                            set: { nuevo in Task { await cambiar { $0.perfilPublico = nuevo } } }),
                              id: "privacidad.perfilPublico")
                    Hairline()
                    toggleRow("Analíticas Anónimas", "Contadores de uso sin datos personales",
                              isOn: Binding(get: { preferencias.analiticas },
                                            set: { nuevo in Task { await cambiar { $0.analiticas = nuevo } } }),
                              id: "privacidad.analiticas")
                }

                section("TUS DATOS") {
                    NavigationLink(value: Route.privacyNotice) {
                        Text("AVISO DE PRIVACIDAD")
                            .ofraude(15, .semibold, color: Theme.textLight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacidad.aviso")
                    Hairline()
                    if let exportado {
                        ShareLink(item: exportado) {
                            Text("COMPARTIR MIS DATOS (JSON)").ofraude(15, .semibold, color: Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 52)
                        }
                        .accessibilityIdentifier("privacidad.compartirDatos")
                    } else {
                        Button { Task { await exportar() } } label: {
                            Text(exportando ? "PREPARANDO…" : "DESCARGAR MIS DATOS").ofraude(15, .semibold, color: Theme.textLight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(exportando)
                        .accessibilityIdentifier("privacidad.exportar")
                    }
                    Hairline()
                    NavigationLink(value: Route.deleteAccount) {
                        Text("ELIMINAR MI CUENTA").ofraude(15, .semibold, color: Theme.dangerText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacidad.eliminarCuenta")
                }

                if let error { AvisoBanner(texto: error, tono: .error) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationTitle("Seguridad y privacidad")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pedirContrasena) {
            ConfirmarContrasenaView(titulo: "Apagar la verificación en dos pasos",
                                    mensaje: "Tu cuenta quedará protegida solo con la contraseña. Confirma que eres tú.",
                                    boton: "APAGAR") { contrasena in
                var p = preferencias
                p.dosPasos = false
                try await session.actualizarPreferencias(p, contrasena: contrasena)
            }
        }
    }

    /// Derecho de acceso: todo lo de la persona en un archivo que ella decide a dónde mandar.
    private func exportar() async {
        exportando = true
        defer { exportando = false }
        do { exportado = try await session.exportarDatos() } catch { self.error = error.mensajeUsuario }
    }

    private func cambiar(_ ajuste: (inout Preferencias) -> Void) async {
        var p = preferencias
        ajuste(&p)
        do {
            try await session.actualizarPreferencias(p)
            error = nil
        } catch {
            self.error = error.mensajeUsuario
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).ofraude(18, .bold, color: Theme.accent).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard(borderWidth: 2)
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).ofraude(14, .semibold, color: Theme.textLight)
                Text(subtitle).ofraude(13, color: Theme.textSubtle)
            }
        }
        .tint(Theme.accent)
        .accessibilityIdentifier(id)
    }
}

#Preview {
    NavigationStack { PrivacyView() }
        .entornoDePrueba()
}
