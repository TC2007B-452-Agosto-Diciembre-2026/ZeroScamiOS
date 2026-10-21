//
//  ReportsStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

final class RegistroExpiraciones {
    var errores: [AppError] = []
}

struct ReportsStoreTests {
    let e: EntornoPrueba
    let secretos: MemorySecretStore
    let expiraciones: RegistroExpiraciones
    let reports: ReportsStore

    init() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        let expiraciones = RegistroExpiraciones()
        self.e = e
        self.secretos = secretos
        self.expiraciones = expiraciones
        reports = ReportsStore(backend: e.backend(secretos), archivos: e.archivos) { expiraciones.errores.append($0) }
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
    }

    @Test func lasAlertasSonLasDosCriticas() async {
        await reports.cargarAlertas()
        #expect(reports.alertas.valor?.map(\.id) == [101, 102])
    }

    @Test func buscarFiltraPorTipo() async {
        await reports.buscar(FiltroBusqueda(tipos: [.llamada]))
        #expect(reports.resultados.valor?.map(\.id) == [105, 112])
    }

    @Test func crearSubeLaVersionYApareceEnMisReportes() async throws {
        let antes = reports.version
        let r = try await reports.crear(DemoServerReportesTests.borrador())
        #expect(reports.version == antes + 1)
        await reports.cargarMios()
        #expect(reports.mios.valor?.contains { $0.id == r.id } == true)
    }

    @Test func sesionVencidaAvisaAlExpirar() async throws {
        try secretos.borrar(.accessToken)
        await reports.cargarMios()
        #expect(reports.mios == .error("Tu sesión expiró. Inicia sesión de nuevo."))
        #expect(expiraciones.errores == [.sesionExpirada])
    }

    @Test func noEncontradoNoCierraLaSesion() async {
        await #expect(throws: AppError.noEncontrado) { _ = try await reports.detalle(id: 99_999) }
        #expect(expiraciones.errores.isEmpty)
    }

    @Test func reiniciarVuelveACargando() async {
        await reports.cargarMios()
        reports.reiniciar()
        #expect(reports.mios == .cargando)
        #expect(reports.version == 0)
    }
}
