//
//  NotificationsView.swift
//  PrototipoApp
//
//  Notificaciones de la persona (tabla Notificacion_Alerta): cambios de estado de sus reportes y
//  comentarios nuevos. Tocar una la marca como leída y abre el reporte.
//

import SwiftUI

struct NotificationsView: View {
    @Environment(NotificationsStore.self) private var notifications
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CargaView(carga: notifications.lista, esVacio: \.isEmpty,
                          vacio: EstadoVacio(icono: "bell.slash", titulo: "Sin notificaciones",
                                             mensaje: "Aquí verás cuando cambie el estado de tus reportes o alguien los comente."),
                          reintentar: { await notifications.cargar(avisar: false) }) { lista in
                    ForEach(lista) { fila($0) }
                }
            }
            .padding(16)
        }
        .ofraudeScreen()
        .navigationTitle("Notificaciones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Marcar leídas") {
                    Task { await notifications.marcarLeidas(notifications.lista.valor?.filter { !$0.leida }.map(\.id) ?? []) }
                }
                .disabled(notifications.sinLeer == 0)
                .accessibilityIdentifier("notificaciones.marcarLeidas")
            }
        }
        .task { await notifications.cargar(avisar: false) }
    }

    private func fila(_ n: Notificacion) -> some View {
        Button {
            Task { await notifications.marcarLeidas([n.id]) }
            if let idReporte = n.idReporte { appState.push(.reportDetail(idReporte)) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(n.leida ? Color.clear : Theme.accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.mensaje).ofraude(14, n.leida ? .regular : .semibold, color: Theme.textPrimary)
                    Text(Formato.relativo(n.fecha)).ofraude(12, color: Theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ofraudeCard(radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(n.leida ? "Leída" : "Sin leer")
        .accessibilityIdentifier("notificaciones.fila.\(n.id)")
    }
}
