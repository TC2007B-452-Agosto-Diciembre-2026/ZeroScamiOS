//
//  FormatoTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct FormatoTests {
    let ahora = Date(timeIntervalSince1970: 1_791_072_000)   // 2026-10-04 00:00 UTC

    @Test func relativoEnEspanolConMayuscula() {
        let texto = Formato.relativo(ahora.addingTimeInterval(-7_200), ahora: ahora)
        #expect(texto.lowercased().contains("2 horas"))
        #expect(texto.first?.isUppercase == true)
    }

    @Test func relativoDeAyer() {
        #expect(Formato.relativo(ahora.addingTimeInterval(-86_400), ahora: ahora).lowercased().contains("ayer"))
    }

    @Test func conteoCortoComoElStoryboard() {
        #expect(Formato.conteoCorto(340) == "340")
        #expect(Formato.conteoCorto(1_000) == "1k")
        #expect(Formato.conteoCorto(1_200) == "1.2k")
    }

    @Test func milesConComa() {
        #expect(Formato.miles(4_302) == "4,302")
    }

    @Test func folioConSeisDigitos() {
        #expect(Formato.folio(123) == "#000123")
    }

    @Test func borradorDesdeReporteCopiaLosCampos() {
        let r = Reporte.ejemplo(texto: nil)
        let b = ReporteBorrador(desde: r)
        #expect(b.titulo == r.titulo)
        #expect(b.urlOTexto == "https://n1ke-outlet-mexico.com")
        #expect(b.tipo == .tiendaClonada)
        #expect(b.adjuntos.isEmpty)
    }
}
