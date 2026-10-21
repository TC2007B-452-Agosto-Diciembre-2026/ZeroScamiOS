//
//  HomeView.swift
//  PrototipoApp
//
//  Reemplaza: escena `home-vc` / HomeViewController.
//  Las tres categorías abren Buscar con un texto precargado (antes `openSearchTab(withQuery:)`)
//  y el botón naranja abre la pestaña Reportar (antes `selectedIndex = 2`).
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports
    @Environment(NotificationsStore.self) private var notifications

    var body: some View {
        VStack(spacing: 0) {
            TopBar(background: Theme.background) {
                NavigationLink(value: Route.notifications) {
                    Symbol("bell.fill", size: 24, color: Theme.accent)
                        .overlay(alignment: .topTrailing) {
                            if notifications.sinLeer > 0 {
                                Text(verbatim: "\(notifications.sinLeer)")
                                    .ofraude(10, .bold, color: Theme.background)
                                    .padding(4)
                                    .background(Theme.dangerText, in: Circle())
                                    .offset(x: 8, y: -8)
                            }
                        }
                }
                .accessibilityLabel(notifications.sinLeer > 0 ? "Notificaciones, \(notifications.sinLeer) sin leer" : "Notificaciones")
                .accessibilityIdentifier("inicio.notificaciones")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    EstadoConexionView()
                    welcomeRow
                    reportBanner
                    verificarCard
                    Hairline()

                    Text("CATEGORÍAS COMUNES").ofraude(18, .bold, color: Theme.textPrimary)
                    HStack(spacing: 16) {
                        categoryCard("OFERTAS FALSAS", "Descuentos y liquidaciones falsas",
                                     tipo: .ofertaFalsa, height: 90)
                        categoryCard("SORTEOS FALSOS", "Premios y regalos que no existen",
                                     tipo: .sorteoFalso, height: 90)
                    }
                    categoryCard("TIENDAS CLONADAS", "Sitios que imitan marcas reales", tipo: .tiendaClonada)

                    Hairline(color: Theme.danger)
                    HStack {
                        Text("ALERTAS CRÍTICAS").ofraude(18, .bold, color: Theme.danger).accessibilityAddTraits(.isHeader)
                        Spacer()
                        BotonActualizar(identificador: "inicio.actualizar") { await actualizar() }
                    }
                    CargaView(carga: reports.alertas, esVacio: \.isEmpty,
                              vacio: EstadoVacio(icono: "checkmark.shield", titulo: "Sin alertas críticas",
                                                 mensaje: "Por ahora no hay reportes validados de riesgo alto."),
                              reintentar: { await reports.cargarAlertas() }) { alertas in
                        ForEach(alertas) { alertCard($0) }
                    }

                    linkCard("RECURSOS Y CONSEJOS",
                             "Aprende a identificar las señales de un fraude antes de que ocurra.",
                             button: "CONSULTAR GUÍA", route: .guide, id: "inicio.guia")
                    linkCard("ESTADÍSTICAS DE LA COMUNIDAD",
                             "El impacto colectivo de ZeroScam en números.",
                             button: "VER ESTADÍSTICAS", route: .stats, id: "inicio.estadisticas")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .refreshable { await actualizar() }
        }
        .ofraudeScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: reports.version) { await reports.cargarAlertas() }
    }

    /// Botón Actualizar y jalar hacia abajo: alertas y notificaciones al día.
    private func actualizar() async {
        async let alertas: Void = reports.cargarAlertas()
        async let avisos: Void = notifications.cargar(avisar: session.usuario?.preferencias.notificaciones == true)
        _ = await (alertas, avisos)
    }

    private var verificarCard: some View {
        NavigationLink(value: Route.verificarEnlace) {
            HStack(spacing: 12) {
                Symbol("link.badge.plus", size: 26, color: Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("¿ES LEGÍTIMO ESTE ENLACE?").ofraude(16, .bold, color: Theme.textPrimary)
                    Text("Pégalo y te decimos si es confiable antes de abrirlo.")
                        .ofraude(13, color: Theme.textSlate)
                }
                Spacer(minLength: 0)
                Symbol("chevron.right", size: 14, color: Theme.textSlate)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .ofraudeCard(radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el verificador de enlaces")
        .accessibilityIdentifier("inicio.verificarEnlace")
    }

    private var welcomeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Hola, \(session.usuario?.nombre ?? "").").ofraude(20, .bold, color: Theme.textPrimary)
                Text("Tu vigilancia mantiene la comunidad segura.").ofraude(16, color: Theme.textSlate)
            }
            Spacer()
            AvatarView(usuario: session.usuario)
        }
        .accessibilityElement(children: .combine)
    }

    private var reportBanner: some View {
        Button {
            appState.selectedTab = .report
        } label: {
            HStack(spacing: 12) {
                Symbol("megaphone.fill", size: 28, color: Theme.background)
                VStack(alignment: .leading, spacing: 2) {
                    Text("REPORTAR INCIDENTE").ofraude(20, .bold, color: Theme.background)
                    Text("Registra actividad sospechosa inmediatamente.")
                        .ofraude(14, .medium, color: Theme.background.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            .padding(17)
            .frame(maxWidth: .infinity)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inicio.reportar")
    }

    private func categoryCard(_ title: String, _ subtitle: String, tipo: TipoFraude, height: CGFloat? = nil) -> some View {
        Button {
            appState.pendingSearch = FiltroBusqueda(tipos: [tipo])
            appState.selectedTab = .search
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).ofraude(15, .semibold, color: Theme.textPrimary)
                Text(subtitle).ofraude(12, color: Theme.textSlate)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(minHeight: height, alignment: .topLeading)
            .ofraudeCard(radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inicio.categoria.\(tipo)")
    }

    private func alertCard(_ r: Reporte) -> some View {
        NavigationLink(value: Route.reportDetail(r.id)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(r.titulo).ofraude(15, .semibold, color: Theme.textPrimary)
                Text(r.descripcion).ofraude(14, color: Theme.textSlate).lineLimit(2)
                Text(verbatim: "\(Formato.relativo(r.fechaCreacion)) · VER DETALLES ›").ofraude(12, .bold, color: Theme.textSlate)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ofraudeCard(radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el detalle del reporte")
        .accessibilityIdentifier("inicio.alerta.\(r.id)")
    }

    private func linkCard(_ title: String, _ text: String, button: String, route: Route, id: String) -> some View {
        VStack(spacing: 8) {
            Text(title).ofraude(18, .bold, color: Theme.textPrimary)
            Text(text).ofraude(14, color: Theme.textSlate).multilineTextAlignment(.center)
            NavigationLink(value: route) {
                Text(button)
            }
            .buttonStyle(OfraudeButtonStyle(background: Theme.background, foreground: Theme.textPrimary,
                                            size: 14, weight: .semibold, radius: 4, height: 36, fullWidth: false))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.defaultBorder, lineWidth: 1))
            .accessibilityIdentifier(id)
        }
        .padding(25)
        .frame(maxWidth: .infinity)
        .ofraudeCard(radius: 4)
    }
}

#Preview {
    NavigationStack { HomeView() }
        .entornoDePrueba()
}
