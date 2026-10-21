//
//  CatalogosTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct CatalogosTests {
    @Test func rawValuesIgualesAlSQL() {
        #expect(Rol.allCases.map(\.rawValue) == ["Usuario", "Administrador", "Policia", "Owner"])
        #expect(EstadoReporte.allCases.map(\.rawValue) == ["RECIBIDO", "EN_REVISION", "VALIDADO", "RECHAZADO", "CANALIZADO"])
        #expect(NivelRiesgo.allCases.map(\.rawValue) == ["NO_EVALUADO", "BAJO", "MEDIO", "ALTO", "MUY_ALTO"])
        #expect(TipoFraude.allCases.map(\.rawValue) == ["Oferta Falsa", "Sorteo Falso", "Tienda Clonada", "Marketplace", "Llamada", "Otro"])
    }

    @Test func soloValidadoYCanalizadoSonPublicos() {
        #expect(EstadoReporte.allCases.filter(\.esPublico) == [.validado, .canalizado])
    }

    @Test func transicionesPermitidas() {
        #expect(EstadoReporte.recibido.siguientes == [.enRevision, .rechazado])
        #expect(EstadoReporte.enRevision.siguientes == [.validado, .rechazado])
        #expect(EstadoReporte.validado.siguientes == [.canalizado])
        #expect(EstadoReporte.rechazado.siguientes.isEmpty)
        #expect(EstadoReporte.canalizado.siguientes.isEmpty)
    }

    @Test func finalesYOrdenComoElCatalogo() {
        #expect(EstadoReporte.allCases.filter(\.esFinal) == [.rechazado, .canalizado])
        #expect(EstadoReporte.allCases.map(\.orden) == [1, 2, 3, 4, 5])
    }

    @Test func soloSeEditaAntesDeValidar() {
        #expect(EstadoReporte.allCases.filter(\.permiteEdicion) == [.recibido, .enRevision])
    }

    @Test func riesgoSeOrdena() {
        #expect(NivelRiesgo.bajo < .alto)
        #expect([NivelRiesgo.muyAlto, .bajo, .medio].max() == .muyAlto)
        #expect(!NivelRiesgo.asignables.contains(.noEvaluado))
    }

    @Test func soloAdministradorYOwnerSonStaff() {
        #expect(Rol.allCases.filter(\.esStaff) == [.administrador, .owner])
    }

    @Test func cadaTipoTieneCategoriaResumenYTresPasos() {
        for tipo in TipoFraude.allCases {
            #expect(!tipo.categoria.isEmpty)
            #expect(!tipo.resumen.isEmpty)
            #expect(tipo.modusOperandi.count == 3)
        }
    }
}
