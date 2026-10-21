//
//  ComentariosView.swift
//  PrototipoApp
//
//  Comentarios de un reporte público (antes "publicar comentario" era un TODO y la lista era
//  fija). El servidor limpia el texto, limita a 5 por minuto y decide quién puede borrar.
//

import SwiftUI

struct ComentariosView: View {
    let reporte: Reporte
    let puedeModerar: Bool

    @Environment(ReportsStore.self) private var reports
    @State private var carga: Carga<[Comentario]> = .cargando
    @State private var texto = ""
    @State private var error: String?
    @State private var paraBorrar: Comentario?
    @FocusState private var foco: Campo?

    private var limpio: String { Sanitizador.texto(texto, maximo: 500, multilinea: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                OfraudeTextField(placeholder: "Escribe un comentario...", text: $texto, maximo: 500,
                                 foco: $foco, campo: .comentario, identificador: "detalle.comentario")
                    .submitLabel(.send)
                    .onSubmit { Task { await publicar() } }
                BotonAccion(titulo: "Publicar comentario", icono: "arrow.up",
                            estilo: OfraudeButtonStyle(radius: 8, height: 48, fullWidth: false),
                            habilitado: Validador.comentario(limpio).isEmpty, identificador: "detalle.publicar") {
                    await publicar()
                }
            }
            FieldError(mensaje: error)
            Hairline()
            Text(verbatim: "Comentarios de la comunidad (\(carga.valor?.count ?? reporte.comentarios))")
                .ofraude(20, .bold, color: Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            CargaView(carga: carga, esVacio: \.isEmpty,
                      vacio: EstadoVacio(icono: "bubble.left", titulo: "Sin comentarios", mensaje: "Sé la primera persona en comentar."),
                      reintentar: cargar) { lista in
                ForEach(lista) { tarjeta($0) }
            }
        }
        .task(id: reporte.id) { await cargar() }
        .alert("¿Eliminar comentario?", isPresented: Binding(get: { paraBorrar != nil }, set: { if !$0 { paraBorrar = nil } }),
               presenting: paraBorrar) { c in
            Button("Eliminar", role: .destructive) { Task { await borrar(c) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("No se puede deshacer.")
        }
    }

    private func tarjeta(_ c: Comentario) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(c.autor) · \(Formato.relativo(c.fecha).lowercased())").ofraude(13, .bold, color: Theme.textPrimary)
                Text(c.texto).ofraude(14, color: Theme.textPrimary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            // A la vista, además del menú contextual: mantener presionado no es fácil de descubrir.
            if c.esMio || puedeModerar {
                Button { paraBorrar = c } label: { Symbol("trash", size: 16, color: Theme.textSlate) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Eliminar comentario")
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8)
        .contextMenu {
            if c.esMio || puedeModerar {
                Button("Eliminar comentario", systemImage: "trash", role: .destructive) { paraBorrar = c }
            }
        }
    }

    private func cargar() async {
        do { carga = .listo(try await reports.comentarios(id: reporte.id)) }
        catch { carga = .error(error.mensajeUsuario) }
    }

    private func publicar() async {
        guard Validador.comentario(limpio).isEmpty else { return }
        error = nil
        do {
            _ = try await reports.comentar(id: reporte.id, texto: limpio)
            texto = ""
            foco = nil
            await cargar()
        } catch {
            self.error = error.mensajeUsuario
        }
    }

    private func borrar(_ c: Comentario) async {
        do {
            try await reports.eliminarComentario(id: c.id)
            await cargar()
        } catch {
            self.error = error.mensajeUsuario
        }
    }
}
