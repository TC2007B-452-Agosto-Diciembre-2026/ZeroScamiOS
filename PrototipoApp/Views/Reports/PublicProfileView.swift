//
//  PublicProfileView.swift
//  PrototipoApp
//
//  Perfil de quien firmó un reporte. Se llega tocando "Reportado por…" en el detalle, y solo si
//  esa persona activó "perfil público". Muestra lo que ella eligió mostrar: alias, biografía,
//  foto y sus reportes públicos no anónimos. Nunca su correo ni su nombre real.
//

import SwiftUI

struct PublicProfileView: View {
    let id: Int64

    @Environment(ReportsStore.self) private var reports
    @State private var carga: Carga<PerfilPublico> = .cargando
    @State private var foto: UIImage?

    var body: some View {
        ScrollView {
            CargaView(carga: carga, reintentar: cargar) { perfil in
                contenido(perfil)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reports.version) { await cargar() }
    }

    private func cargar() async {
        do {
            let perfil = try await reports.perfilPublico(id: id)
            carga = .listo(perfil)
            foto = perfil.tieneAvatar ? (await reports.avatarPublico(idUsuario: id)).flatMap(UIImage.init(data:)) : nil
        } catch {
            carga = .error(error.mensajeUsuario)
        }
    }

    private func contenido(_ p: PerfilPublico) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Group {
                    if let foto {
                        Image(uiImage: foto).resizable().scaledToFill()
                    } else {
                        Symbol("person.fill", size: 30, color: Theme.textPrimary)
                    }
                }
                .frame(width: 72, height: 72)
                .background(Theme.avatarBackground, in: Circle())
                .clipShape(Circle())
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "@\(p.alias)").ofraude(22, .bold, color: Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("perfilPublico.alias")
                    Text(verbatim: "En ZeroScam desde el \(Formato.fechaCorta(p.miembroDesde))")
                        .ofraude(13, color: Theme.textSlate)
                }
            }

            if !p.biografia.isEmpty {
                Text(p.biografia).ofraude(15, color: Theme.textPrimary)
            }

            Hairline()
            Text(verbatim: "REPORTES PÚBLICOS (\(p.reportes.count))").ofraude(18, .bold, color: Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if p.reportes.isEmpty {
                EstadoVacioView(estado: EstadoVacio(icono: "tray", titulo: "Sin reportes públicos",
                                                    mensaje: "Aquí aparecen sus reportes validados que no son anónimos."))
            } else {
                ForEach(p.reportes) { tarjeta($0) }
            }
        }
    }

    private func tarjeta(_ r: Reporte) -> some View {
        NavigationLink(value: Route.reportDetail(r.id)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "\(r.nivelRiesgo.titulo) · \(Formato.relativo(r.fechaCreacion))")
                    .ofraude(12, .bold, color: r.nivelRiesgo.color)
                Text(r.titulo).ofraude(18, .bold, color: Theme.textPrimary)
                Text(r.descripcion).ofraude(14, color: Theme.textSlate).lineLimit(2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ofraudeCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("perfilPublico.reporte.\(r.id)")
    }
}

#Preview {
    NavigationStack { PublicProfileView(id: 1) }
        .entornoDePrueba()
}
