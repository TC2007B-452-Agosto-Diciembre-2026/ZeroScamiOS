//
//  AppStateTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct AppStateTests {
    @Test func pushUsaLaPilaDeLaPestanaVisible() {
        let estado = AppState()
        estado.selectedTab = .search
        estado.push(.reportDetail(101))
        #expect(estado.searchPath == [.reportDetail(101)])
        #expect(estado.homePath.isEmpty)
    }

    @Test func popToTabsVaciaTodasLasPilas() {
        let estado = AppState()
        estado.homePath = [.reportDetail(101)]
        estado.profilePath = [.settings, .privacy]
        estado.popToTabs(selecting: .profile)
        #expect(estado.homePath.isEmpty && estado.profilePath.isEmpty)
        #expect(estado.selectedTab == .profile)
    }

    @Test func resetNavigationDejaTodoComoAlAbrir() {
        let estado = AppState()
        estado.selectedTab = .search
        estado.pendingSearch = FiltroBusqueda(tipos: [.llamada])
        estado.profileSegment = .guardados
        estado.reportPath = [.reportSuccess(5)]
        estado.resetNavigation()
        #expect(estado.selectedTab == .home)
        #expect(estado.pendingSearch == nil)
        #expect(estado.profileSegment == .misReportes)
        #expect(estado.reportPath.isEmpty)
    }
}
