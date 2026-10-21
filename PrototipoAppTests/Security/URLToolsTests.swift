//
//  URLToolsTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct URLToolsTests {
    @Test(arguments: ["http://a.com", "https://a.com/x", "www.a.com", "sitio-falso.com", "javascript:alert(1)", "data:text/html,x"])
    func pareceURL(_ s: String) { #expect(URLTools.pareceURL(s)) }

    @Test(arguments: ["", "+52 55 1234 5678", "Perfil Gamer Store", "hola"])
    func noPareceURL(_ s: String) { #expect(!URLTools.pareceURL(s)) }

    @Test func normalizaEsquemaYHost() {
        #expect(URLTools.normalizar("HTTP://Sitio-Falso.COM/Pago") == "http://sitio-falso.com/Pago")
        #expect(URLTools.normalizar("sitio-falso.com") == "https://sitio-falso.com")
        #expect(URLTools.normalizar("www.sitio-falso.com/a") == "https://www.sitio-falso.com/a")
    }

    @Test func normalizarQuitaCredenciales() {
        #expect(URLTools.normalizar("https://banco.com@estafa.com/login") == "https://estafa.com/login")
        #expect(URLTools.host(de: URLTools.normalizar("https://usuario:clave@estafa.com") ?? "") == "estafa.com")
    }

    @Test(arguments: ["javascript:alert(1)", "ftp://a.com", "file:///etc/passwd", "https://localhost", "https://", "http://a .com"])
    func rechazaLoQueNoEsHTTP(_ s: String) { #expect(URLTools.normalizar(s) == nil) }

    @Test func rechazaLoMuyLargo() {
        #expect(URLTools.normalizar("https://a.com/" + String(repeating: "x", count: 2_100)) == nil)
    }

    @Test func desactivaParaCompartir() {
        #expect(URLTools.desactivar("https://sitio-falso.com/pago.html") == "hxxps://sitio-falso[.]com/pago.html")
        #expect(URLTools.desactivar("http://a.b.c") == "hxxp://a[.]b[.]c")
    }

    @Test func detectaHomografo() {
        #expect(URLTools.esPosibleHomografo("https://xn--pple-43d.com"))
        #expect(!URLTools.esPosibleHomografo("https://apple.com"))
    }

    @Test func estadoDelCertificado() {
        #expect(URLTools.estadoCertificado("https://a.com") == "HTTPS")
        #expect(URLTools.estadoCertificado("http://a.com") == "SIN HTTPS")
    }

    // MARK: - Bordes: ningún texto externo o malformado debe provocar crash

    @Test(arguments: [
        "", "   ", "\n\t", "\u{0}", "https://a.com:99999999999", "https://a.com:65536", "https://a.com:0",
        "https://a.com:abc", "https://:80", "https://a..com", "https://.a.com", "https://a.com.",
        "mailto:x@y.com", "foo:bar@baz.com", "banco.com@estafa.com", "https://evil.com\\@good.com",
        "http://a\tb.com", "http://a\nb.com", "https://a.com/\u{0}", "https://a.com/\u{202E}gnp.exe",
        "https://a\u{200B}.com", "https://\u{FEFF}a.com", "https://a.com/x\u{2066}y", "https://a.com/\u{7F}",
        "JaVaScRiPt:alert(1)", "vbscript:x", "HTTPS:/a.com", "://a.com", "http://[::1]", "https://%00.com",
        "https://" + String(repeating: "a", count: 300) + ".com",
    ])
    func rechazaEntradasRaras(_ s: String) { #expect(URLTools.normalizar(s) == nil) }

    @Test func aceptaPuertoValido() {
        #expect(URLTools.normalizar("https://a.com:8080/x") == "https://a.com:8080/x")
        #expect(URLTools.normalizar("a.com:443") == "https://a.com:443")
        #expect(URLTools.normalizar("  HTTPS://A.COM/Ruta?q=1#f  ") == "https://a.com/Ruta?q=1#f")
    }

    @Test func schemelessConArrobaNoSeNormaliza() {
        // Sin esquema, "x@y" no es un enlace: tampoco lo es para pareceURL.
        #expect(!URLTools.pareceURL("banco.com@estafa.com"))
    }

    @Test(arguments: ["https://аpple.com", "https://paypal.com", "https://日本語.jp", "http://ａ.com", "https://a.com/путь"])
    func unicodeNuncaProvocaCrashNiPasaSinAviso(_ s: String) {
        // Resultado seguro: o se rechaza, o la salida se marca como posible homógrafo cuando el host no es ASCII.
        if let n = URLTools.normalizar(s) {
            let hostEsASCII = URLTools.host(de: n)?.unicodeScalars.allSatisfy(\.isASCII) ?? false
            #expect(hostEsASCII || URLTools.esPosibleHomografo(n))
        }
        _ = URLTools.pareceURL(s)
        _ = URLTools.desactivar(s)
    }

    @Test func hostCirilicoSeMarcaComoHomografo() {
        // "а" cirílica (U+0430) en lugar de la "a" latina.
        #expect(URLTools.esPosibleHomografo("https://\u{0430}pple.com"))
        #expect(URLTools.esPosibleHomografo("https://%D0%B0pple.com"))
        if let n = URLTools.normalizar("https://\u{0430}pple.com") { #expect(URLTools.esPosibleHomografo(n)) }
    }

    @Test(arguments: ["", "https://", "garbage", "https://a.com:99999999999", "\u{0}", "https://[::1"])
    func esPosibleHomografoYHostNoFallanConBasura(_ s: String) {
        _ = URLTools.esPosibleHomografo(s)
        _ = URLTools.host(de: s)
    }

    @Test func homografoEnMayusculasYSubdominios() {
        #expect(URLTools.esPosibleHomografo("HTTPS://XN--PPLE-43D.COM"))
        #expect(URLTools.esPosibleHomografo("https://www.xn--pple-43d.com/x"))
        #expect(!URLTools.esPosibleHomografo("https://a.com/путь"))   // solo cuenta el host
        #expect(!URLTools.esPosibleHomografo("https://apple.com/xn--x"))
    }

    @Test func barraInvertidaCortaLaAutoridad() {
        // Los navegadores tratan "\\" como "/": el host real es el anterior a la barra.
        #expect(URLTools.esPosibleHomografo("https://xn--pple-43d.com\\@apple.com"))
        #expect(URLTools.host(de: "https://estafa.com\\@banco.com") == "estafa.com")
        #expect(URLTools.host(de: "https://estafa.com\\ruta") == "estafa.com")
        #expect(URLTools.desactivar("https://estafa.com\\@banco.com") == "hxxps://estafa[.]com\\@banco.com")
    }

    @Test func desactivarBordes() {
        #expect(URLTools.desactivar("") == "")
        #expect(URLTools.desactivar("https://") == "hxxps://")
        #expect(URLTools.desactivar("HTTPS://A.com/x.y") == "hxxps://A[.]com/x.y")
        #expect(URLTools.desactivar("https://u@a.com") == "hxxps://u@a[.]com")
        #expect(URLTools.desactivar("a.com/r?u=http://b.com") == "a[.]com/r?u=hxxp://b.com")   // "://" en la consulta no es el esquema: se desactiva el host real y el enlace incrustado
        #expect(URLTools.desactivar("www.a.com") == "www[.]a[.]com")
        #expect(URLTools.desactivar("javascript:x.y") == "javascript:x[.]y")
        #expect(!URLTools.desactivar(String(repeating: "http://a.com/", count: 500)).contains("http://"))
        _ = URLTools.desactivar("http\u{301}://é.com")
    }

    @Test func estadoCertificadoBordes() {
        #expect(URLTools.estadoCertificado("") == "SIN HTTPS")
        #expect(URLTools.estadoCertificado("  HTTPS://a.com") == "HTTPS")
        #expect(URLTools.estadoCertificado("https:/a.com") == "SIN HTTPS")
    }

    @Test func pareceURLBordes() {
        #expect(!URLTools.pareceURL("   "))
        #expect(!URLTools.pareceURL("a.com\nb.com"))
        #expect(!URLTools.pareceURL("a.com\tb.com"))
        #expect(!URLTools.pareceURL("\u{0}"))
        #expect(URLTools.pareceURL("  https://a.com  "))
        #expect(URLTools.pareceURL("\u{0430}pple.com"))   // dominio con letras no latinas: también es un enlace
        #expect(!URLTools.pareceURL(String(repeating: "a", count: 100_000) + "!"))
    }
}
