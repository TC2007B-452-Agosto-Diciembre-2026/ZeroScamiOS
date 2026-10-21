//
//  FiltroBusquedaTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct FiltroBusquedaTests {
    let reporte = Reporte.ejemplo()

    @Test func filtroVacioCoincideConTodo() {
        #expect(FiltroBusqueda().estaVacio)
        #expect(FiltroBusqueda().coincide(reporte))
    }

    @Test func ignoraMayusculasYAcentos() {
        #expect(FiltroBusqueda(texto: "TENIS").coincide(reporte))
        #expect(FiltroBusqueda(texto: "clonáda").coincide(reporte))
    }

    @Test func todasLasPalabrasDebenAparecer() {
        #expect(FiltroBusqueda(texto: "tenis monterrey").coincide(reporte))
        #expect(!FiltroBusqueda(texto: "tenis cdmx").coincide(reporte))
    }

    @Test func buscaTambienEnLaURLYElTextoSospechoso() {
        #expect(FiltroBusqueda(texto: "n1ke").coincide(reporte))
        let llamada = Reporte.ejemplo(tipo: .llamada, url: nil, texto: "+52 55 8765 4321")
        #expect(FiltroBusqueda(texto: "8765").coincide(llamada))
    }

    @Test func filtraPorTipoYRiesgoMinimo() {
        #expect(FiltroBusqueda(tipos: [.tiendaClonada]).coincide(reporte))
        #expect(!FiltroBusqueda(tipos: [.llamada]).coincide(reporte))
        #expect(FiltroBusqueda(riesgoMinimo: .alto).coincide(reporte))
        #expect(!FiltroBusqueda(riesgoMinimo: .muyAlto).coincide(reporte))
        #expect(!FiltroBusqueda(riesgoMinimo: .medio).estaVacio)
    }

    @Test func espaciosNoCuentanComoTexto() {
        #expect(FiltroBusqueda(texto: "   ").estaVacio)
    }

    // MARK: Motor de búsqueda

    @Test func singularYPluralSeEncuentran() {
        #expect(FiltroBusqueda(texto: "tiendas clonadas").coincide(reporte))   // nombre de la tarjeta de categoría
        #expect(FiltroBusqueda(texto: "tenis").coincide(reporte))
        let oferta = Reporte.ejemplo(titulo: "Descuento falso", descripcion: "Oferta que no existe.")
        #expect(FiltroBusqueda(texto: "descuentos").coincide(oferta))
        #expect(FiltroBusqueda(texto: "ofertas").coincide(oferta))
    }

    @Test func laPuntuacionNoRompeLaBusqueda() {
        #expect(FiltroBusqueda(texto: "tenis,").coincide(reporte))
        #expect(FiltroBusqueda(texto: "\"tenis\" (monterrey)").coincide(reporte))
        #expect(FiltroBusqueda(texto: "#tenis").coincide(reporte))
    }

    @Test func telefonoSeEncuentraConOSinSeparadores() {
        let llamada = Reporte.ejemplo(tipo: .llamada, url: nil, texto: "+52 55 8765 4321")
        #expect(FiltroBusqueda(texto: "5587654321").coincide(llamada))
        #expect(FiltroBusqueda(texto: "55-8765-4321").coincide(llamada))
        #expect(FiltroBusqueda(texto: "(55) 8765 4321").coincide(llamada))
        #expect(!FiltroBusqueda(texto: "5587654322").coincide(llamada))
        let pegado = Reporte.ejemplo(tipo: .llamada, url: nil, texto: "5587654321")
        #expect(FiltroBusqueda(texto: "55 8765 4321").coincide(pegado))
    }

    @Test func marcaConOSinEspacio() {
        let ml = Reporte.ejemplo(titulo: "Falso vendedor", url: "https://mercadolibre-ofertas.com")
        #expect(FiltroBusqueda(texto: "mercado libre").coincide(ml))
        let ml2 = Reporte.ejemplo(titulo: "Falso vendedor en Mercado Libre", url: nil)
        #expect(FiltroBusqueda(texto: "mercadolibre").coincide(ml2))
        #expect(!FiltroBusqueda(texto: "mercado pago").coincide(ml2))
    }

    @Test func dominioEscritoSeEncuentra() {
        #expect(FiltroBusqueda(texto: "n1ke-outlet-mexico.com").coincide(reporte))
        #expect(FiltroBusqueda(texto: "n1ke outlet").coincide(reporte))
    }

    @Test func textoSinPalabrasUtilesNoCoincideConTodo() {
        // Solo signos: antes se descartaba como "sin palabras" y mostraba todo; ahora no encuentra nada.
        #expect(!FiltroBusqueda(texto: "???").coincide(reporte))
    }
}
