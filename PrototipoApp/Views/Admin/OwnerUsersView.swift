//
//  OwnerUsersView.swift
//  PrototipoApp
//
//  Solo Owner: cuentas, roles (Usuario ↔ Administrador), suspensión, analíticas anónimas y
//  "restablecer datos de demostración". El Owner no puede tocarse a sí mismo ni crear otro Owner.
//

import SwiftUI

struct OwnerUsersView: View {
    @Environment(AdminStore.self) private var admin
    @Environment(SessionStore.self) private var session
    @Environment(\.appConfig) private var config
    @State private var seleccionado: Usuario?
    @State private var confirmarRestablecer = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CargaView(carga: admin.usuarios, reintentar: { await admin.cargarUsuarios() }) { lista in
                    ForEach(lista) { fila($0) }
                }
                if let error { AvisoBanner(texto: error, tono: .error) }

                VStack(alignment: .leading, spacing: 6) {
                    Text("USO ANÓNIMO").ofraude(13, .bold, color: Theme.accent).accessibilityAddTraits(.isHeader)
                    Text(verbatim: "Inicios de sesión: \(admin.analiticas["inicio_sesion"] ?? 0)").ofraude(14, color: Theme.textLight)
                    Text(verbatim: "Búsquedas: \(admin.analiticas["busqueda"] ?? 0)").ofraude(14, color: Theme.textLight)
                    Text(verbatim: "Reportes enviados: \(admin.analiticas["reporte_enviado"] ?? 0)").ofraude(14, color: Theme.textLight)
                    Text("Solo cuenta a quienes lo permiten en Seguridad y privacidad, y no guarda quién hizo qué.")
                        .ofraude(12, color: Theme.textMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard(radius: 8)

                if config.fuente == .demo {
                    BotonAccion(titulo: "RESTABLECER DATOS DE DEMOSTRACIÓN",
                                estilo: OfraudeButtonStyle(background: Theme.card, foreground: Theme.dangerText, size: 14,
                                                           weight: .semibold, radius: 8, height: 48),
                                identificador: "usuarios.restablecer") {
                        confirmarRestablecer = true
                    }
                }
            }
            .padding(16)
        }
        .ofraudeScreen()
        .navigationTitle("Usuarios y roles")
        .navigationBarTitleDisplayMode(.inline)
        .task { await admin.cargarUsuarios() }
        .confirmationDialog(seleccionado.map { "@\($0.alias)" } ?? "",
                            isPresented: Binding(get: { seleccionado != nil }, set: { if !$0 { seleccionado = nil } }),
                            titleVisibility: .visible, presenting: seleccionado) { u in
            if u.rol == .usuario {
                Button("Hacer Administrador") { Task { await cambiarRol(u, a: .administrador) } }
            } else if u.rol == .administrador {
                Button("Quitar rol de Administrador") { Task { await cambiarRol(u, a: .usuario) } }
            }
            if u.estadoCuenta == .activo {
                Button("Suspender cuenta", role: .destructive) { Task { await cambiarEstado(u, a: .suspendido) } }
            } else {
                Button("Reactivar cuenta") { Task { await cambiarEstado(u, a: .activo) } }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Suspender cierra todas sus sesiones al instante.")
        }
        .alert("¿Restablecer los datos de demostración?", isPresented: $confirmarRestablecer) {
            Button("Restablecer", role: .destructive) { Task { await restablecer() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borran las cuentas, reportes y archivos creados durante la demo y se vuelve a los datos iniciales. Se cerrará tu sesión.")
        }
    }

    private func fila(_ u: Usuario) -> some View {
        Button { seleccionado = u } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "@\(u.alias)").ofraude(15, .semibold, color: Theme.textPrimary)
                    Text(u.correo).ofraude(12, color: Theme.textMuted)
                }
                Spacer()
                if u.estadoCuenta == .suspendido {
                    Etiqueta(texto: "SUSPENDIDA", color: Theme.dangerText, fondo: Theme.danger.opacity(0.2))
                }
                Etiqueta(texto: u.rol.titulo.uppercased(), color: Theme.accent, fondo: Theme.accent.opacity(0.15))
            }
            .padding(14)
            .ofraudeCard(radius: 8)
        }
        .buttonStyle(.plain)
        .disabled(u.id == session.usuario?.id || u.rol == .owner)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("usuarios.fila.\(u.alias)")
    }

    private func cambiarRol(_ u: Usuario, a rol: Rol) async {
        do { try await admin.cambiarRol(idUsuario: u.id, a: rol) } catch { self.error = error.mensajeUsuario }
    }

    private func cambiarEstado(_ u: Usuario, a estado: EstadoCuenta) async {
        do { try await admin.cambiarEstadoCuenta(idUsuario: u.id, a: estado) } catch { self.error = error.mensajeUsuario }
    }

    private func restablecer() async {
        do {
            try await admin.restablecerDemo()
            session.sesionRestablecida()
        } catch {
            self.error = error.mensajeUsuario
        }
    }
}
