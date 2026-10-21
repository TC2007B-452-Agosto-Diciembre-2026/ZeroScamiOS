//
//  ReportDetailView.swift
//  PrototipoApp
//
//  Reemplaza: escena `reportdetail-vc` / ReportDetailViewController.
//  Antes el contenido era fijo; ahora muestra el reporte de la tarjeta que se tocó. Lo que la
//  persona no debe ver (autor anónimo, persona afectada, evidencia) ya viene filtrado del servidor.
//  Guardar, compartir, "Yo también" y comentarios eran TODO del original.
//

import SwiftUI

struct ReportDetailView: View {
    let id: Int64

    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports
    @State private var carga: Carga<Reporte> = .cargando
    @State private var historial: [HistorialEstado] = []
    @State private var errorAccion: String?
    @State private var preguntarReporte: Reporte?

    private var esStaff: Bool { session.usuario?.rol.esStaff == true }

    var body: some View {
        ScrollView {
            CargaView(carga: carga, reintentar: cargar) { reporte in
                contenido(reporte)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Reporte")
        .navigationBarTitleDisplayMode(.inline)
        // Se recarga si algo cambió en otra pantalla (borrado, moderado, comentado).
        .task(id: reports.version) { await cargar() }
        .alert("No se pudo completar", isPresented: Binding(get: { errorAccion != nil }, set: { if !$0 { errorAccion = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorAccion ?? "")
        }
        .confirmationDialog("¿Quieres reportar tu caso?", isPresented: Binding(get: { preguntarReporte != nil },
                                                                             set: { if !$0 { preguntarReporte = nil } }),
                            titleVisibility: .visible, presenting: preguntarReporte) { r in
            Button("Sí, reportar mi caso") {
                appState.push(.report(ReportePrefill(tipo: r.tipo, tipoOtro: r.tipoOtro,
                                                     urlOTexto: r.sitio?.url ?? r.textoSospechoso ?? "")))
            }
            Button("Solo confirmar", role: .cancel) {}
        } message: { _ in
            Text("Tu confirmación ya cuenta. Si te pasó a ti, un reporte propio con tus datos ayuda más.")
        }
    }

    private func cargar() async {
        do {
            let r = try await reports.detalle(id: id)
            carga = .listo(r)
            if r.esMio || esStaff { historial = (try? await reports.historial(id: id)) ?? [] }
        } catch {
            carga = .error(error.mensajeUsuario)
        }
    }

    private func contenido(_ r: Reporte) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            encabezado(r)

            Text(verbatim: r.nivelRiesgo >= .alto ? "Alerta: \(r.titulo)" : r.titulo)
                .ofraude(28, .bold, color: Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("detalle.titulo")

            autor(r)

            if r.esMio || esStaff { EstadoReporteView(reporte: r, historial: historial) }

            Text(r.descripcion).ofraude(16, color: Theme.textPrimary)

            if r.sitio != nil || r.textoSospechoso != nil { SitioSospechosoView(reporte: r) }
            if let persona = r.personaAfectada { PersonaAfectadaView(persona: persona) }

            if !r.evidencias.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Evidencia").ofraude(20, .bold, color: Theme.textPrimary).accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(r.evidencias) { MiniaturaEvidencia(fuente: .guardada($0)) }
                    }
                }
            } else if r.totalEvidencias > 0 {
                Text(verbatim: "Incluye \(r.totalEvidencias) archivo(s) de evidencia revisados por moderación.")
                    .ofraude(13, color: Theme.textMuted)
            }

            Text("Modus Operandi").ofraude(24, .bold, color: Theme.textPrimary).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(r.tipo.modusOperandi, id: \.self) { paso in
                    Text(paso).ofraude(16, color: Theme.textPrimary)
                }
            }

            if r.estado.esPublico && !r.esMio { tarjetaYoTambien(r) }

            if r.estado.esPublico {
                ComentariosView(reporte: r, puedeModerar: esStaff)
            } else {
                Text("Los comentarios se abren cuando el reporte se valida.").ofraude(13, color: Theme.textMuted)
            }

            if esStaff {
                NavigationLink(value: Route.adminReview(r.id)) { Text("MODERAR REPORTE") }
                    .buttonStyle(OfraudeButtonStyle(background: Theme.card, foreground: Theme.accent, size: 15,
                                                    weight: .semibold, radius: 8, height: 48))
                    .accessibilityIdentifier("detalle.moderar")
            }
        }
    }

    private func encabezado(_ r: Reporte) -> some View {
        HStack(spacing: 8) {
            Etiqueta(texto: r.tipoVisible, color: Theme.textPrimary.opacity(0.8), fondo: Theme.textPrimary.opacity(0.1))
            if r.estado.esPublico {
                Etiqueta(texto: "SEVERIDAD \(r.nivelRiesgo.titulo)", color: r.nivelRiesgo.color, fondo: r.nivelRiesgo.color.opacity(0.2))
            } else {
                Etiqueta(texto: r.estado.titulo, color: r.estado.color, fondo: r.estado.color.opacity(0.2))
            }
            Spacer()
            if r.estado.esPublico || r.esMio {
                Button { Task { await alternarGuardado(r) } } label: {
                    Symbol(r.guardadoPorMi ? "bookmark.fill" : "bookmark", size: 24,
                           color: r.guardadoPorMi ? Theme.accent : Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(r.guardadoPorMi ? "Quitar de guardados" : "Guardar reporte")
                .accessibilityIdentifier("detalle.guardar")
            }
            if r.estado.esPublico {
                ShareLink(item: r.textoParaCompartir, subject: Text("Alerta de ZeroScam"), preview: SharePreview(r.titulo)) {
                    Symbol("square.and.arrow.up", size: 24, color: Theme.textPrimary)
                }
                .accessibilityLabel("Compartir alerta")
                .accessibilityIdentifier("detalle.compartir")
            }
        }
    }

    /// Si quien reportó dejó su perfil público (su id llega del servidor), la fila abre ese perfil.
    /// Anónimos y perfiles privados llegan sin id: la fila no se puede tocar.
    @ViewBuilder private func autor(_ r: Reporte) -> some View {
        if let idAutor = r.autor.idUsuario {
            NavigationLink(value: Route.publicProfile(idAutor)) {
                HStack(spacing: 12) {
                    filaAutor(r)
                    Spacer(minLength: 0)
                    Symbol("chevron.right", size: 14, color: Theme.textSlate).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre el perfil de quien reportó")
            .accessibilityIdentifier("detalle.autor")
        } else {
            filaAutor(r)
        }
    }

    private func filaAutor(_ r: Reporte) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
                .frame(width: 40, height: 40)
                .overlay(Symbol(r.esAnonimo ? "theatermasks.fill" : "person.fill", size: 18, color: Theme.textSlate))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Reportado por \(r.autor.nombre)").ofraude(14, .semibold, color: Theme.textPrimary)
                Text(verbatim: "\(Formato.relativo(r.fechaCreacion)) · \(r.ciudad) · ocurrió el \(Formato.fechaCorta(r.fechaIncidente))")
                    .ofraude(12, color: Theme.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tarjetaYoTambien(_ r: Reporte) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("¿Has recibido esto?").ofraude(16, .bold, color: Theme.textPrimary)
                Text(verbatim: "\(Formato.conteoCorto(r.confirmaciones)) personas lo confirmaron.")
                    .ofraude(14, color: Theme.textPrimary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("detalle.confirmaciones")
            }
            Spacer(minLength: 0)
            BotonAccion(titulo: r.confirmadoPorMi ? "Confirmado" : "Yo también",
                        estilo: OfraudeButtonStyle(foreground: Theme.background, size: 14, weight: .bold,
                                                   radius: 4, height: 40, fullWidth: false),
                        habilitado: !r.confirmadoPorMi, identificador: "detalle.yoTambien") {
                await yoTambien(r)
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8)
    }

    private func yoTambien(_ r: Reporte) async {
        do {
            carga = .listo(try await reports.confirmar(id: r.id))
            preguntarReporte = r
        } catch {
            errorAccion = error.mensajeUsuario
        }
    }

    /// Cambia el marcador al instante y lo confirma con el servidor; si falla, lo regresa.
    private func alternarGuardado(_ r: Reporte) async {
        var cambiado = r
        cambiado.guardadoPorMi.toggle()
        carga = .listo(cambiado)
        do {
            try await reports.marcarGuardado(id: r.id, cambiado.guardadoPorMi)
        } catch {
            carga = .listo(r)
            errorAccion = error.mensajeUsuario
        }
    }
}

#Preview {
    NavigationStack { ReportDetailView(id: 101) }
        .entornoDePrueba()
}
