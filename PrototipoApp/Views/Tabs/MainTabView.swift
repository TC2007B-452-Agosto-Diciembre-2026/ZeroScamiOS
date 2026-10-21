//
//  MainTabView.swift
//  PrototipoApp
//
//  Reemplaza: escena `Nxu-re-6aT` / MainTabBarController (Main.storyboard).
//  Pestañas: Inicio, Buscar, Reportar, Perfil (mismos títulos e íconos que el original).
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(NotificationsStore.self) private var notifications
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            Tab("Inicio", systemImage: "house.fill", value: AppTab.home) {
                TabStack(path: $appState.homePath) { HomeView() }
            }
            Tab("Buscar", systemImage: "magnifyingglass", value: AppTab.search) {
                TabStack(path: $appState.searchPath) { SearchView() }
            }
            Tab("Reportar", systemImage: "megaphone.fill", value: AppTab.report) {
                TabStack(path: $appState.reportPath) { ReportView() }
            }
            Tab("Perfil", systemImage: "person.fill", value: AppTab.profile) {
                TabStack(path: $appState.profilePath) { ProfileView() }
            }
        }
        // La campana se actualiza al entrar, tras cada cambio y al volver a primer plano.
        .task(id: reports.version) { await cargarNotificaciones() }
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { Task { await cargarNotificaciones() } }
        }
    }

    private func cargarNotificaciones() async {
        await notifications.cargar(avisar: session.usuario?.preferencias.notificaciones == true)
    }
}

/// Un `NavigationStack` por pestaña. Las pantallas empujadas ocultan el tab bar: en el original
/// se empujaban sobre el navigation controller que contiene al tab bar y lo cubrían por completo.
struct TabStack<Root: View>: View {
    @Binding var path: [Route]
    let root: Root

    init(path: Binding<[Route]>, @ViewBuilder root: () -> Root) {
        _path = path
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: $path) {
            root.navigationDestination(for: Route.self) { route in
                route.destination.toolbar(.hidden, for: .tabBar)
            }
        }
    }
}
