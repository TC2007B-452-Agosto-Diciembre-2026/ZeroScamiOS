//
//  AdminQueueView.swift
//  PrototipoApp
//
//  Cola de moderación (Administrador y Owner): los reportes por estado, los más viejos primero.
//  El servidor decide si quien la pide tiene permiso; aquí solo se muestra su respuesta.
//

import SwiftUI

struct AdminQueueView: View {
    @Environment(AdminStore.self) private var admin
    @Environment(ReportsStore.self) private var reports
    @State private var estado: EstadoReporte?
    @State private var todos = false

    private struct Filtro: Identifiable {
        let titulo: String
        let estado: EstadoReporte?
        let todos: Bool
        var id: String { titulo }
    }

    private let filtros = [
        Filtro(titulo: "PENDIENTES", estado: nil, todos: false),
        Filtro(titulo: "TODOS", estado: nil, todos: true),
    ] + EstadoReporte.allCases.map { Filtro(titulo: $0.titulo, estado: $0, todos: false) }

    private struct Clave: Hashable {
        let estado: EstadoReporte?
        let todos: Bool
        let version: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filtros) { f in
                            ChipFiltro(titulo: f.titulo, activo: estado == f.estado && todos == f.todos,
                                       identificador: "moderacion.filtro.\(f.titulo)") {
                                estado = f.estado
                                todos = f.todos
                            }
                        }
                    }
                }
                CargaView(carga: admin.cola, esVacio: \.isEmpty,
                          vacio: EstadoVacio(icono: "tray", titulo: "Nada por revisar", mensaje: "No hay reportes en este estado."),
                          reintentar: { await cargar() }) { lista in
                    ForEach(lista) { r in
                        NavigationLink(value: Route.adminReview(r.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Etiqueta(texto: r.estado.titulo, color: r.estado.color, fondo: r.estado.color.opacity(0.2))
                                    Spacer()
                                    Text(Formato.folio(r.id)).ofraude(12, color: Theme.textMuted)
                                }
                                Text(r.titulo).ofraude(17, .semibold, color: Theme.textPrimary)
                                Text(verbatim: "\(r.tipoVisible) · \(r.ciudad) · \(Formato.relativo(r.fechaCreacion)) · \(r.autor.nombre)")
                                    .ofraude(12, color: Theme.textSlate)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ofraudeCard(radius: 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("moderacion.reporte.\(r.id)")
                    }
                }
            }
            .padding(16)
        }
        .ofraudeScreen()
        .navigationTitle("Moderación")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Clave(estado: estado, todos: todos, version: reports.version)) { await cargar() }
    }

    /// "TODOS" pide cada estado; "PENDIENTES" (nil) son RECIBIDO y EN_REVISION.
    private func cargar() async {
        if todos {
            await admin.cargarColaCompleta()
        } else {
            await admin.cargarCola(estado: estado)
        }
    }
}
