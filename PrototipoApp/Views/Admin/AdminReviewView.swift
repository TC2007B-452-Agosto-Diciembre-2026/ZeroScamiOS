//
//  AdminReviewView.swift
//  PrototipoApp
//
//  Revisión de un reporte: todo lo que el staff puede ver (persona afectada, evidencia,
//  historial) y el cambio de estado. Solo se ofrecen las transiciones válidas; el servidor las
//  vuelve a revisar, impide moderar lo propio y avisa al autor.
//

import SwiftUI

struct AdminReviewView: View {
    let id: Int64

    @Environment(AdminStore.self) private var admin
    @Environment(ReportsStore.self) private var reports
    @Environment(\.dismiss) private var dismiss
    @State private var carga: Carga<Reporte> = .cargando
    @State private var historial: [HistorialEstado] = []
    @State private var nuevo: EstadoReporte?
    @State private var riesgo: NivelRiesgo?
    @State private var observaciones = ""
    @State private var confirmar = false
    @State private var error: String?

    private var limpias: String { Sanitizador.texto(observaciones, maximo: 500, multilinea: true) }

    private var errores: [ErrorCampo] {
        guard let nuevo else { return [ErrorCampo(campo: .observaciones, mensaje: "Elige el nuevo estado.")] }
        return Validador.moderacion(nuevo: nuevo, riesgo: riesgo, observaciones: limpias)
    }

    var body: some View {
        ScrollView {
            CargaView(carga: carga, reintentar: cargar) { r in
                VStack(alignment: .leading, spacing: 20) {
                    Text(r.titulo).ofraude(22, .bold, color: Theme.textPrimary).accessibilityAddTraits(.isHeader)
                    Text(verbatim: "\(Formato.folio(r.id)) · \(r.tipoVisible) · \(r.ciudad) · Autor: \(r.autor.nombre)")
                        .ofraude(13, color: Theme.textSlate)
                    Text(r.descripcion).ofraude(15, color: Theme.textPrimary)
                    if r.sitio != nil || r.textoSospechoso != nil { SitioSospechosoView(reporte: r) }
                    if let persona = r.personaAfectada { PersonaAfectadaView(persona: persona) }
                    if !r.evidencias.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(r.evidencias) { MiniaturaEvidencia(fuente: .guardada($0)) }
                        }
                    }
                    EstadoReporteView(reporte: r, historial: historial)
                    if r.estado.siguientes.isEmpty {
                        AvisoBanner(texto: "Este reporte está en un estado final (\(r.estado.titulo)); ya no cambia.")
                    } else {
                        formulario(r)
                    }
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Revisión")
        .navigationBarTitleDisplayMode(.inline)
        .task { await cargar() }
        .confirmationDialog(nuevo.map { "¿Cambiar a \($0.titulo)?" } ?? "", isPresented: $confirmar, titleVisibility: .visible) {
            Button("Cambiar estado") { Task { await aplicar() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(nuevo == .validado ? "Será visible para toda la comunidad y se avisará al autor."
                 : nuevo == .canalizado ? "Se marcará como enviado a las autoridades y se avisará al autor."
                 : "Se avisará al autor.")
        }
    }

    private func formulario(_ r: Reporte) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CAMBIAR ESTADO").ofraude(13, .bold, color: Theme.accent)
            HStack(spacing: 8) {
                ForEach(r.estado.siguientes, id: \.self) { e in
                    ChipFiltro(titulo: e.titulo, activo: nuevo == e, identificador: "revision.estado.\(e.rawValue)") { nuevo = e }
                }
            }
            if nuevo == .validado {
                Text("NIVEL DE RIESGO").ofraude(13, .bold, color: Theme.accent)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(NivelRiesgo.asignables, id: \.self) { n in
                        ChipFiltro(titulo: n.titulo, activo: riesgo == n, identificador: "revision.riesgo.\(n.rawValue)") { riesgo = n }
                    }
                }
            }
            FieldLabel(nuevo == .rechazado ? "MOTIVO DEL RECHAZO (OBLIGATORIO)" : "OBSERVACIONES (OPCIONAL)")
            OfraudeTextEditor(placeholder: "Qué revisaste y por qué...", text: $observaciones, maximo: 500, altura: 100,
                              identificador: "revision.observaciones")
            if nuevo != nil { ResumenErrores(errores: errores.mensajes) }
            if let error { AvisoBanner(texto: error, tono: .error) }
            BotonAccion(titulo: "APLICAR CAMBIO", habilitado: errores.isEmpty, identificador: "revision.aplicar") {
                confirmar = true
            }
        }
        .padding(16)
        .ofraudeCard(radius: 8)
    }

    private func cargar() async {
        do {
            carga = .listo(try await reports.detalle(id: id))
            historial = (try? await reports.historial(id: id)) ?? []
        } catch {
            carga = .error(error.mensajeUsuario)
        }
    }

    private func aplicar() async {
        guard let nuevo else { return }
        do {
            _ = try await admin.cambiarEstado(id: id, a: nuevo, riesgo: riesgo, observaciones: limpias)
            reports.invalidar()
            dismiss()
        } catch {
            self.error = error.mensajeUsuario
        }
    }
}
