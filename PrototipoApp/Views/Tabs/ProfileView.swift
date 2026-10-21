//
//  ProfileView.swift
//  PrototipoApp
//
//  Reemplaza: escena `profile-vc` / ProfileViewController.
//  - Mis reportes y Guardados vienen del backend (antes tarjetas fijas que reaparecían).
//  - El menú Editar / Eliminar / Cancelar es un `confirmationDialog`; Editar solo antes de que se
//    valide el reporte y Eliminar pide confirmación porque no se puede deshacer.
//  - El aro del avatar es un `strokeBorder` negro, como en el original.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports

    @State private var optionsFor: Reporte?
    @State private var paraEliminar: Reporte?
    @State private var aviso: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(background: Theme.card, titleSize: 16, titleColor: Theme.textPrimary) {
                NavigationLink(value: Route.settings) {
                    Symbol("gearshape.fill", size: 24, color: Theme.textPrimary)
                }
                .accessibilityLabel("Ajustes")
                .accessibilityIdentifier("perfil.ajustes")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    avatar
                    Text(verbatim: session.usuario.map { "@\($0.alias)" } ?? "")
                        .ofraude(28, .bold, color: Theme.textPrimary)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 16) {
                        statCard("REPORTES ENVIADOS", reports.mios.valor.map { "\($0.count)" } ?? "–", labelColor: Theme.textSlate)
                            .accessibilityIdentifier("perfil.enviados")
                        statCard("PERSONAS AYUDADAS",
                                 reports.mios.valor.map { Formato.miles($0.reduce(0) { $0 + $1.confirmaciones }) } ?? "–",
                                 labelColor: Theme.accent)
                    }

                    NavigationLink(value: Route.editProfile) { Text("EDITAR PERFIL") }
                        .buttonStyle(OfraudeButtonStyle(background: Theme.card, size: 15, weight: .semibold, radius: 0, height: 48))
                        .accessibilityIdentifier("perfil.editar")

                    segments

                    if appState.profileSegment == .misReportes {
                        CargaView(carga: reports.mios, esVacio: \.isEmpty,
                                  vacio: EstadoVacio(icono: "megaphone", titulo: "Aún no has reportado",
                                                     mensaje: "Cuando envíes un reporte aparecerá aquí con su estado."),
                                  reintentar: { await reports.cargarMios() }) { lista in
                            ForEach(lista) { r in
                                reportCard(r, titleSize: 20,
                                           header: "\(r.estado.titulo) · \(Formato.relativo(r.fechaCreacion).uppercased())",
                                           headerColor: r.estado.color, icon: "ellipsis.circle", iconColor: Theme.textSlate,
                                           iconLabel: "Opciones del reporte", iconId: "perfil.opciones.\(r.id)") {
                                    optionsFor = r
                                }
                            }
                        }
                    } else {
                        CargaView(carga: reports.guardados, esVacio: \.isEmpty,
                                  vacio: EstadoVacio(icono: "bookmark", titulo: "Sin guardados",
                                                     mensaje: "Toca el marcador de un reporte para guardarlo aquí."),
                                  reintentar: { await reports.cargarGuardados() }) { lista in
                            ForEach(lista) { r in
                                reportCard(r, titleSize: 18,
                                           header: "\(r.nivelRiesgo.titulo) · \(Formato.relativo(r.fechaCreacion))",
                                           headerColor: r.nivelRiesgo.color, icon: "bookmark.fill", iconColor: Theme.accent,
                                           iconLabel: "Quitar de guardados", iconId: "perfil.quitarGuardado.\(r.id)") {
                                    Task { await quitarGuardado(r) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 20)
            }
            .refreshable { await actualizar() }
        }
        .ofraudeScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: reports.version) {
            await reports.cargarMios()
            await reports.cargarGuardados()
        }
        .confirmationDialog(optionsFor?.titulo ?? "", isPresented: Binding(get: { optionsFor != nil }, set: { if !$0 { optionsFor = nil } }),
                            titleVisibility: .visible, presenting: optionsFor) { r in
            Button("Editar") {
                if r.estado.permiteEdicion {
                    appState.push(.editReport(r.id))
                } else {
                    aviso = "Este reporte ya fue revisado y no se puede editar."
                }
            }
            Button("Eliminar", role: .destructive) { paraEliminar = r }
            Button("Cancelar", role: .cancel) { }
        }
        .alert("¿Eliminar este reporte?", isPresented: Binding(get: { paraEliminar != nil }, set: { if !$0 { paraEliminar = nil } }),
               presenting: paraEliminar) { r in
            Button("Eliminar", role: .destructive) { Task { await eliminar(r) } }
            Button("Cancelar", role: .cancel) { }
        } message: { r in
            Text(r.estado.esPublico ? "Dejará de ser visible para la comunidad. No se puede deshacer."
                                    : "Se borrará junto con su evidencia. No se puede deshacer.")
        }
        .alert("Aviso", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("Aceptar", role: .cancel) { }
        } message: {
            Text(aviso ?? "")
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(usuario: session.usuario, tamano: 128, fondo: Theme.card)
                .overlay(Circle().strokeBorder(Theme.defaultBorder, lineWidth: 4))
            NavigationLink(value: Route.editProfile) {
                Symbol("pencil", size: 16, color: Theme.background)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent, in: Circle())
            }
            .accessibilityLabel("Cambiar foto de perfil")
            // El storyboard mete la insignia 2 pt hacia dentro del borde del avatar.
            .padding(.bottom, 2)
            .padding(.trailing, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func statCard(_ title: String, _ value: String, labelColor: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).ofraude(12, color: labelColor)
            Text(value).ofraude(22, .bold, color: Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 90)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func actualizar() async {
        async let mios: Void = reports.cargarMios()
        async let guardados: Void = reports.cargarGuardados()
        _ = await (mios, guardados)
    }

    private var segments: some View {
        HStack(spacing: 24) {
            segmentButton("MIS REPORTES", .misReportes, id: "perfil.segmento.misReportes")
            segmentButton("GUARDADOS", .guardados, id: "perfil.segmento.guardados")
            Spacer(minLength: 0)
            BotonActualizar(identificador: "perfil.actualizar") { await actualizar() }
        }
    }

    private func segmentButton(_ title: String, _ segment: ProfileSegment, id: String) -> some View {
        Button {
            appState.profileSegment = segment
        } label: {
            Text(title).ofraude(15, .semibold, color: appState.profileSegment == segment ? Theme.textPrimary : Theme.textSlate)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(appState.profileSegment == segment ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    /// Tarjeta tocable (abre el detalle) con un botón de 24 pt arriba a la derecha.
    private func reportCard(_ r: Reporte, titleSize: CGFloat, header: String, headerColor: Color, icon: String,
                            iconColor: Color, iconLabel: String, iconId: String, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: Route.reportDetail(r.id)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(header).ofraude(12, .bold, color: headerColor)
                    Text(r.titulo).ofraude(titleSize, .semibold, color: Theme.textPrimary)
                    Text(r.descripcion).ofraude(16, color: Theme.textSlate).lineLimit(2)
                    if r.estado.esPublico {
                        HStack(spacing: 12) {
                            Label(Formato.conteoCorto(r.confirmaciones), systemImage: "person.2.fill")
                            Label("\(r.comentarios)", systemImage: "bubble.left.fill")
                        }
                        .ofraudeFont(13, .semibold)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("\(r.confirmaciones) confirmaciones, \(r.comentarios) comentarios")
                    }
                }
                .padding(.leading, 21)
                .padding(.trailing, 45)
                .padding(.vertical, 21)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("perfil.tarjeta.\(r.id)")

            Button(action: action) {
                Symbol(icon, size: 24, color: iconColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(iconLabel)
            .accessibilityIdentifier(iconId)
            .padding(.top, 21)
            .padding(.trailing, 21)
        }
    }

    private func quitarGuardado(_ r: Reporte) async {
        do { try await reports.marcarGuardado(id: r.id, false) }
        catch { aviso = error.mensajeUsuario }
    }

    private func eliminar(_ r: Reporte) async {
        do { try await reports.eliminar(id: r.id) }
        catch { aviso = error.mensajeUsuario }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .entornoDePrueba()
}
