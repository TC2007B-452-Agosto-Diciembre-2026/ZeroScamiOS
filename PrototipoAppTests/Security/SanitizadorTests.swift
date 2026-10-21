//
//  SanitizadorTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct SanitizadorTests {
    @Test func recortaYColapsaEspacios() {
        #expect(Sanitizador.texto("  hola    mundo  ", maximo: 50) == "hola mundo")
    }

    @Test func quitaCaracteresInvisibles() {
        #expect(Sanitizador.texto("ad\u{200B}min", maximo: 50) == "admin")
        #expect(Sanitizador.texto("abc\u{202E}fdp.exe", maximo: 50) == "abcfdp.exe")
        #expect(Sanitizador.texto("\u{FEFF}hola\u{0007}", maximo: 50) == "hola")
    }

    @Test func multilineaConservaSaltosPeroNoMasDeDos() {
        #expect(Sanitizador.texto("uno\n\n\n\ndos", maximo: 50, multilinea: true) == "uno\n\ndos")
        #expect(Sanitizador.texto("uno\ndos", maximo: 50) == "uno dos")
    }

    @Test func cortaAlMaximo() {
        #expect(Sanitizador.texto(String(repeating: "a", count: 600), maximo: 500).count == 500)
    }

    @Test func correoYAliasEnMinusculas() {
        #expect(Sanitizador.correo("  Ana@Ejemplo.MX ") == "ana@ejemplo.mx")
        #expect(Sanitizador.alias(" Usuario_01 ") == "usuario_01")
    }

    @Test func borradorLimpio() {
        var b = ReporteBorrador()
        b.titulo = "  Tienda   falsa  "
        b.descripcion = "Línea uno\n\n\n\nLínea dos"
        #expect(b.limpio.titulo == "Tienda falsa")
        #expect(b.limpio.descripcion == "Línea uno\n\nLínea dos")
    }

    // MARK: Bordes (vacío, límites, unicode)

    @Test func vacioYSoloEspacios() {
        #expect(Sanitizador.texto("", maximo: 10) == "")
        #expect(Sanitizador.texto(" \t\r\n  \u{00A0}\u{3000} ", maximo: 10) == "")
        #expect(Sanitizador.texto("\n\n \n", maximo: 10, multilinea: true) == "")
    }

    @Test(arguments: [0, -1, -9_999])
    func maximoCeroONegativoNoRevienta(_ maximo: Int) {
        #expect(Sanitizador.texto("hola", maximo: maximo) == "")
    }

    @Test func espaciosYSaltosRaros() {
        #expect(Sanitizador.texto("a\u{00A0}\u{00A0}b\u{3000}c", maximo: 50) == "a b c")
        #expect(Sanitizador.texto("a\r\nb", maximo: 50) == "a b")
        #expect(Sanitizador.texto("a\u{2028}b\u{0085}c", maximo: 50) == "a b c")
        #expect(Sanitizador.texto("a\r\nb\u{2029}c", maximo: 50, multilinea: true) == "a\nb\nc")
        #expect(Sanitizador.texto("uno  \n  dos", maximo: 50, multilinea: true) == "uno\ndos")
        #expect(Sanitizador.texto("\n\nhola\n\n", maximo: 50, multilinea: true) == "hola")
    }

    @Test func quitaInvisiblesQueDisfrazanNombres() {
        #expect(Sanitizador.texto("\u{3164}", maximo: 50) == "")
        #expect(Sanitizador.texto("\u{2800}\u{115F}\u{FFA0}", maximo: 50) == "")
        #expect(Sanitizador.texto("ad\u{00AD}min", maximo: 50) == "admin")
        #expect(Sanitizador.texto("a\u{2066}b\u{2069}c\u{061C}d", maximo: 50) == "abcd")
        #expect(Sanitizador.texto("a\u{E0041}b", maximo: 50) == "ab")      // caracteres "tag" (ASCII escondido)
        #expect(Sanitizador.texto("a\u{E000}b", maximo: 50) == "ab")        // uso privado
    }

    @Test func uniónDeEmojiYBanderasSeConserva() {
        let familia = "👨\u{200D}👩\u{200D}👧"
        #expect(Sanitizador.texto(familia, maximo: 50) == familia)
        #expect(Sanitizador.texto(familia, maximo: 50).count == 1)
        #expect(Sanitizador.texto("🇲🇽", maximo: 50) == "🇲🇽")
        #expect(Sanitizador.texto("❤️", maximo: 50) == "❤️")
        #expect(Sanitizador.texto("🙂", maximo: 50) == "🙂")
    }

    @Test func unionInvisibleEntreLetrasAsciiSeQuita() {
        #expect(Sanitizador.texto("a\u{200D}b", maximo: 50) == "ab")
        #expect(Sanitizador.texto("a\u{200C}b", maximo: 50) == "ab")
        #expect(Sanitizador.texto("\u{200D}hola\u{200D}", maximo: 50) == "hola")
        #expect(Sanitizador.texto("🙂\u{200D} x", maximo: 50) == "🙂 x")
    }

    @Test func normalizaAFormaPrecompuesta() {
        let descompuesto = "Jose\u{0301}"
        let r = Sanitizador.texto(descompuesto, maximo: 50)
        #expect(r == "José")
        #expect(r.unicodeScalars.count == 4)
    }

    @Test func cortarNoPartePersonajesNiSuperaElMaximoEnEscalares() {
        let banderas = String(repeating: "🇲🇽", count: 10)       // cada bandera = 2 escalares
        let r = Sanitizador.texto(banderas, maximo: 5)
        #expect(r == "🇲🇽🇲🇽")
        #expect(r.unicodeScalars.count <= 5)
        let acentos = "a" + String(repeating: "\u{0301}", count: 5_000)   // un solo "carácter" gigante
        let z = Sanitizador.texto(acentos, maximo: 50)
        #expect(z.unicodeScalars.count <= 50)
        let mezcla = "ok " + acentos
        #expect(Sanitizador.texto(mezcla, maximo: 50) == "ok")
    }

    @Test func cadenaEnormeTerminaRapidoYRespetaElMaximo() {
        let enorme = String(repeating: "ab \u{200B}\n", count: 600_000)
        let reloj = ContinuousClock()
        var r = ""
        let t = reloj.measure { r = Sanitizador.texto(enorme, maximo: 500, multilinea: true) }
        #expect(r.unicodeScalars.count <= 500)
        #expect(!r.isEmpty)
        #expect(t < .seconds(5))
    }

    @Test func aliasYCorreoNuncaSuperanSuMaximoAunqueMinusculasExpandaEscalares() {
        // "İ".lowercased() son 2 escalares: si se pasara a minúsculas después de cortar, se excedería.
        #expect(Sanitizador.alias(String(repeating: "İ", count: 30)).unicodeScalars.count <= 20)
        #expect(Sanitizador.correo(String(repeating: "İ", count: 200)).unicodeScalars.count <= 150)
    }

    @Test(arguments: ["", "  a  b ", "ad\u{200B}min", "👨\u{200D}👩", "Jose\u{0301}", "x\n\n\n\ny", "\u{202E}fdp"])
    func esIdempotente(_ s: String) {
        for multi in [false, true] {
            let una = Sanitizador.texto(s, maximo: 50, multilinea: multi)
            #expect(Sanitizador.texto(una, maximo: 50, multilinea: multi) == una)
        }
    }

    @Test func borradorLimpioTocaTodosLosCampos() {
        var b = ReporteBorrador()
        b.ciudad = " Ciudad\u{200B} de   México "
        b.persona = PersonaAfectada(nombre: " Rosa\u{202E} ", contacto: " +52 81  5555 ", autorizo: true)
        b.tipoOtro = "  Falso\ttécnico "
        b.urlOTexto = " https://a.com/\u{200B}x "
        b.titulo = String(repeating: "t", count: 300)
        b.descripcion = String(repeating: "d", count: 5_000)
        let l = b.limpio
        #expect(l.ciudad == "Ciudad de México")
        #expect(l.persona.nombre == "Rosa")
        #expect(l.persona.contacto == "+52 81 5555")
        #expect(l.persona.autorizo)
        #expect(l.tipoOtro == "Falso técnico")
        #expect(l.urlOTexto == "https://a.com/x")
        #expect(l.titulo.count == 120)
        #expect(l.descripcion.count == 2_000)
    }
}
