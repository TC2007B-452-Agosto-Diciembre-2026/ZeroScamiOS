//
//  AppState.swift
//  PrototipoApp
//
//  Estado de navegación de la app. En el original, los saltos entre pestañas se hacían buscando
//  controllers dentro del tab bar (`selectedIndex`, `presetQuery`, `showGuardados()`); en SwiftUI
//  basta con cambiar un valor aquí. Quién tiene sesión ya no vive aquí: está en SessionStore.
//  No importa SwiftUI a propósito, para poder probarlo solo.
//

import Observation

enum AppTab: Hashable {
    case home, search, report, profile
}

enum ProfileSegment {
    case misReportes, guardados
}

/// Pantallas que se empujan en la pila de una pestaña. Las que muestran un reporte llevan su id.
enum Route: Hashable {
    case reportDetail(Int64)
    case settings, editProfile, privacy, changePassword, signOut
    case guide, article(Articulo), stats
    case report(ReportePrefill?)
    case editReport(Int64)
    case reportSuccess(Int64)
    case notifications, privacyNotice, deleteAccount
    case adminQueue, adminReview(Int64), ownerUsers
    case publicProfile(Int64)
    case verificarEnlace
}

@Observable
final class AppState {
    var selectedTab: AppTab = .home

    /// Búsqueda que Inicio le deja a Buscar (antes `presetQuery`). Buscar la consume y la vacía.
    var pendingSearch: FiltroBusqueda?

    /// Segmento de Perfil (antes `showGuardados()`).
    var profileSegment: ProfileSegment = .misReportes

    /// Una pila de navegación por pestaña. Guardarlas aquí permite volver a la raíz desde
    /// cualquier pantalla (antes `popToViewController(tabBarController)`).
    var homePath: [Route] = []
    var searchPath: [Route] = []
    var reportPath: [Route] = []
    var profilePath: [Route] = []

    /// Empuja una pantalla en la pila de la pestaña que está a la vista.
    func push(_ route: Route) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .search: searchPath.append(route)
        case .report: reportPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    /// Vuelve a la raíz de todas las pestañas y selecciona una.
    func popToTabs(selecting tab: AppTab) {
        homePath = []
        searchPath = []
        reportPath = []
        profilePath = []
        selectedTab = tab
    }

    /// Deja la navegación como al abrir la app (al cerrar sesión o cuando expira).
    func resetNavigation() {
        popToTabs(selecting: .home)
        pendingSearch = nil
        profileSegment = .misReportes
    }
}
