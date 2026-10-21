//
//  SettingsView.swift
//  PrototipoApp
//
//  Reemplaza: escena `settings-vc` / SettingsViewController.
//  "Reportes Guardados" vuelve a Perfil en el segmento Guardados (antes `savedReportsTapped`).
//  Los switches arrancan como en el storyboard: Notificaciones apagado, Modo Oscuro encendido.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports
    @Environment(NotificationsStore.self) private var notifications

    @State private var aviso: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("CUENTA") {
                    NavigationLink(value: Route.editProfile) { rowLabel("Editar Perfil", height: 47) }
                        .buttonStyle(.plain)
                    Hairline()
                    NavigationLink(value: Route.privacy) { rowLabel("Seguridad y Privacidad", height: 46) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ajustes.privacidad")
                }

                section("PREFERENCIAS") {
                    toggleRow("Notificaciones", isOn: Binding(
                        get: { session.usuario?.preferencias.notificaciones ?? false },
                        set: { nuevo in Task { await cambiarNotificaciones(nuevo) } }), id: "ajustes.notificaciones")
                    Hairline()
                    toggleRow("Modo Oscuro", isOn: Binding(
                        get: { session.usuario?.preferencias.modoOscuro ?? true },
                        set: { nuevo in Task { await cambiarModoOscuro(nuevo) } }), id: "ajustes.modoOscuro")
                    Hairline()
                    HStack {
                        Text("Idioma").ofraude(16, color: .white)
                        Spacer()
                        Text("Español").ofraude(14, color: Theme.textSection)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 47)
                }

                section("COMUNIDAD") {
                    Button {
                        appState.profileSegment = .guardados
                        appState.popToTabs(selecting: .profile)
                    } label: {
                        rowLabel("Reportes Guardados  (\(reports.guardados.valor?.count ?? 0))", height: 47)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ajustes.guardados")
                    Hairline()
                    NavigationLink(value: Route.guide) { rowLabel("Guía de Seguridad", height: 46) }
                        .buttonStyle(.plain)
                }

                if session.usuario?.rol.esStaff == true {
                    section("ADMINISTRACIÓN") {
                        NavigationLink(value: Route.adminQueue) { rowLabel("Revisión de reportes", height: 47) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ajustes.moderacion")
                        if session.usuario?.rol == .owner {
                            Hairline()
                            NavigationLink(value: Route.ownerUsers) { rowLabel("Usuarios y roles", height: 46) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("ajustes.usuarios")
                        }
                    }
                }

                NavigationLink(value: Route.signOut) {
                    Text("CERRAR SESIÓN")
                }
                .buttonStyle(OfraudeButtonStyle(background: Theme.card, foreground: Theme.dangerText,
                                                size: 15, weight: .semibold, radius: 16, height: 52))
                .accessibilityIdentifier("ajustes.cerrarSesion")
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task { await reports.cargarGuardados() }
        .alert("Aviso", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("Aceptar", role: .cancel) { }
        } message: {
            Text(aviso ?? "")
        }
    }

    /// Encender pide permiso a iOS; si la persona lo niega, el switch se queda apagado y se explica por qué.
    private func cambiarNotificaciones(_ activar: Bool) async {
        if activar, !(await notifications.pedirPermiso()) {
            aviso = "Activa las notificaciones de ZeroScam en Ajustes de iOS para recibir avisos."
            return
        }
        guard var p = session.usuario?.preferencias else { return }
        p.notificaciones = activar
        do { try await session.actualizarPreferencias(p) } catch { aviso = error.mensajeUsuario }
    }

    private func cambiarModoOscuro(_ activar: Bool) async {
        guard var p = session.usuario?.preferencias else { return }
        p.modoOscuro = activar
        do { try await session.actualizarPreferencias(p) } catch { aviso = error.mensajeUsuario }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).ofraude(13, color: Theme.textSection)
            VStack(spacing: 0) { content() }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func rowLabel(_ title: String, height: CGFloat) -> some View {
        Text(title)
            .ofraude(16, color: .white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: height)
            .contentShape(Rectangle())
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            Text(title).ofraude(16, color: .white)
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .frame(minHeight: 47)
        .accessibilityIdentifier(id)
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .entornoDePrueba()
}
