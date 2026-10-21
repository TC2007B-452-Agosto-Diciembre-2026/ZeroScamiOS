//
//  ValidadorTests.swift
//  PrototipoAppTests
//
//  Una prueba por regla (AC3), más los bordes: vacío, unicode, invisibles, emojis, cadenas enormes.
//

import Foundation
import Testing
@testable import PrototipoApp

struct ValidadorTests {
    static func registroValido() -> RegistroDatos {
        var d = RegistroDatos()
        d.nombre = "Ana María"
        d.apellido = "López-Ruiz"
        d.alias = "ana_lopez"
        d.correo = "ana@comunidad.test"
        d.contrasena = "Fraude0-Cero"
        d.confirmacion = "Fraude0-Cero"
        d.aceptaAviso = true
        return d
    }

    static func borradorValido() -> ReporteBorrador {
        var b = ReporteBorrador()
        b.ciudad = "CDMX"
        b.titulo = "Tienda falsa de consolas"
        b.descripcion = "Piden transferencia y nunca entregan el producto."
        b.urlOTexto = "https://consolas-baratas.store"
        b.fechaIncidente = Date(timeIntervalSince1970: 1_791_000_000)
        return b
    }

    let ahora = Date(timeIntervalSince1970: 1_791_072_000)

    @Test func registroValidoNoTieneErrores() { #expect(Validador.registro(Self.registroValido()).isEmpty) }

    @Test(arguments: ["", "A", "Ana1", String(repeating: "a", count: 51)])
    func nombreInvalido(_ nombre: String) {
        var d = Self.registroValido(); d.nombre = nombre
        #expect(Validador.registro(d).mensaje(para: .nombre) == "Escribe tu nombre (2 a 50 letras).")
    }

    @Test func apellidoInvalido() {
        var d = Self.registroValido(); d.apellido = ""
        #expect(Validador.registro(d).mensaje(para: .apellido) == "Escribe tu apellido (2 a 50 letras).")
    }

    @Test func paisFueraDeLaLista() {
        var d = Self.registroValido(); d.pais = "Narnia"
        #expect(Validador.registro(d).mensaje(para: .pais) == "Elige un país de la lista.")
    }

    @Test(arguments: ["ab", "con espacio", "MAYUS", "ñandú", String(repeating: "a", count: 21)])
    func aliasInvalido(_ alias: String) {
        var d = Self.registroValido(); d.alias = alias
        #expect(Validador.registro(d).mensaje(para: .alias) != nil)
    }

    @Test(arguments: ["", "ana", "ana@", "ana@dominio", "ana@@dominio.mx", "ana..lopez@dominio.mx", "ana@dominio.mx extra"])
    func correoInvalido(_ correo: String) {
        #expect(!Validador.esCorreoValido(correo))
    }

    @Test func correoValido() { #expect(Validador.esCorreoValido("ana.lopez+0fraude@comunidad.test")) }

    @Test func contrasenaCorta() {
        #expect(Validador.contrasenaNueva("Abc12345", confirmacion: "Abc12345", alias: "x", correo: "x@y.mx")
            .mensaje(para: .contrasena) == "La contraseña debe tener entre 10 y 64 caracteres.")
    }

    @Test func contrasenaSinNumero() {
        #expect(Validador.contrasenaNueva("SoloLetrasAqui", confirmacion: "SoloLetrasAqui", alias: "x", correo: "x@y.mx")
            .mensaje(para: .contrasena) == "Incluye al menos una letra y un número.")
    }

    @Test func contrasenaComun() {
        #expect(Validador.contrasenaNueva("Password123", confirmacion: "Password123", alias: "x", correo: "x@y.mx")
            .mensaje(para: .contrasena) == "Esa contraseña es muy común; elige otra.")
    }

    @Test func contrasenaConElUsuario() {
        #expect(Validador.contrasenaNueva("ana_lopez2026", confirmacion: "ana_lopez2026", alias: "ana_lopez", correo: "z@y.mx")
            .mensaje(para: .contrasena) == "La contraseña no debe contener tu usuario ni tu correo.")
    }

    @Test func confirmacionDistinta() {
        #expect(Validador.contrasenaNueva("Fraude0-Cero", confirmacion: "Fraude0-cero", alias: "x", correo: "x@y.mx")
            .mensaje(para: .confirmacion) == "Las contraseñas no coinciden.")
    }

    @Test func avisoObligatorio() {
        var d = Self.registroValido(); d.aceptaAviso = false
        #expect(Validador.registro(d).mensaje(para: .aviso) == "Acepta el aviso de privacidad para crear tu cuenta.")
    }

    @Test func reporteValido() { #expect(Validador.reporte(Self.borradorValido(), ahora: ahora).isEmpty) }

    @Test func reporteSinCiudadTituloNiDescripcion() {
        var b = Self.borradorValido()
        b.ciudad = ""; b.titulo = "corto"; b.descripcion = "poco"
        let e = Validador.reporte(b, ahora: ahora)
        #expect(e.mensaje(para: .ciudad) == "Indica la ciudad donde ocurrió (2 a 60 caracteres).")
        #expect(e.mensaje(para: .titulo) == "El título debe tener entre 10 y 120 caracteres.")
        #expect(e.mensaje(para: .descripcion) == "Describe lo ocurrido (20 a 2000 caracteres).")
    }

    @Test func otraPersonaExigeDatosYAutorizacion() {
        var b = Self.borradorValido()
        b.afectado = .otraPersona
        let e = Validador.reporte(b, ahora: ahora)
        #expect(e.mensaje(para: .personaNombre) == "Escribe el nombre de la persona afectada.")
        #expect(e.mensaje(para: .personaContacto) == "Escribe un teléfono (8 a 15 dígitos) o un correo válido.")
        #expect(e.mensaje(para: .personaAutorizo) == "Confirma que la persona te autorizó a compartir sus datos.")
        b.persona = PersonaAfectada(nombre: "Rosa Martínez", contacto: "+52 81 5555 0101", autorizo: true)
        #expect(Validador.reporte(b, ahora: ahora).isEmpty)
    }

    @Test func otroExigeEspecificar() {
        var b = Self.borradorValido(); b.tipo = .otro
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .tipoOtro) == "Especifica el tipo de fraude (3 a 50 caracteres).")
    }

    @Test func fechaFuturaOMuyVieja() {
        var b = Self.borradorValido()
        b.fechaIncidente = ahora.addingTimeInterval(3_600)
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .fecha) != nil)
        b.fechaIncidente = ahora.addingTimeInterval(-400 * 86_400)
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .fecha) == "La fecha no puede ser futura ni de hace más de un año.")
    }

    @Test(arguments: ["javascript:alert(1)", "ftp://sitio.com", "http://", "data:text/html,hola"])
    func enlacePeligroso(_ enlace: String) {
        var b = Self.borradorValido(); b.urlOTexto = enlace
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .urlOTexto) == "Solo se aceptan enlaces http:// o https:// válidos.")
    }

    @Test func textoQueNoEsEnlaceSePermite() {
        var b = Self.borradorValido(); b.urlOTexto = "+52 55 8765 4321"
        #expect(Validador.reporte(b, ahora: ahora).isEmpty)
    }

    @Test func masDeTresAdjuntos() {
        var b = Self.borradorValido()
        b.adjuntos = (0..<4).map { _ in Adjunto(id: UUID(), nombreArchivo: "x.jpg", tipoArchivo: "image/jpeg", bytes: 1) }
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .adjuntos) == "Máximo 3 archivos de evidencia.")
    }

    @Test func perfilPideContrasenaSiCambiaElCorreo() {
        var p = PerfilDatos(desde: .vacio)
        p.nombre = "Ana"; p.apellido = "López"; p.alias = "ana_lopez"; p.correo = "nuevo@comunidad.test"
        #expect(Validador.perfil(p, correoOriginal: "viejo@comunidad.test").mensaje(para: .contrasenaActual)
                == "Confirma tu contraseña para cambiar el correo.")
        p.biografia = String(repeating: "a", count: 301)
        #expect(Validador.perfil(p, correoOriginal: "nuevo@comunidad.test").mensaje(para: .biografia)
                == "La biografía admite hasta 300 caracteres.")
    }

    @Test func comentarioDeDosA500() {
        #expect(!Validador.comentario("x").isEmpty)
        #expect(Validador.comentario("ok").isEmpty)
        #expect(!Validador.comentario(String(repeating: "a", count: 501)).isEmpty)
    }

    @Test func moderacionExigeRiesgoYMotivo() {
        #expect(Validador.moderacion(nuevo: .validado, riesgo: nil, observaciones: "").mensaje(para: .riesgo)
                == "Asigna un nivel de riesgo para validar.")
        #expect(Validador.moderacion(nuevo: .rechazado, riesgo: nil, observaciones: "no").mensaje(para: .observaciones)
                == "Explica el motivo del rechazo (10 a 500 caracteres).")
        #expect(Validador.moderacion(nuevo: .enRevision, riesgo: nil, observaciones: "").isEmpty)
    }

    @Test func codigoDeSeisDigitos() {
        #expect(Validador.codigo("123456").isEmpty)
        #expect(!Validador.codigo("12345").isEmpty)
        #expect(!Validador.codigo("12345a").isEmpty)
    }

    @Test(arguments: ["+52 55 1234 5678", "5512345678", "(55) 1234-5678"])
    func telefonosValidos(_ t: String) { #expect(Validador.esTelefonoValido(t)) }

    @Test(arguments: ["123", "llámame", "+52 55 1234 5678 9999 0000"])
    func telefonosInvalidos(_ t: String) { #expect(!Validador.esTelefonoValido(t)) }

    // MARK: Bordes: nombres con unicode

    @Test(arguments: ["Ana María", "José", "Jose\u{0301}", "O'Brien", "O\u{2019}Brien", "Jean-Luc", "Müller", "李小龍",
                      "Åsa", "Ñandú", "Nguyễn Văn", "अनुराग", "Ana de la Cruz"])
    func nombresReales(_ n: String) { #expect(Validador.esNombreValido(n), "\(n)") }

    @Test(arguments: ["", " ", "A", "Ana ", " Ana", "-Ana", "Ana-", "1Ana", "Ana1", "Ana😀", "A\u{200B}na", "Ana\u{202E}",
                      "Ana\nLópez", "Ana\u{0000}", "<b>Ana</b>", "Ana_López", "O''", "’’"])
    func nombresInvalidos(_ n: String) { #expect(!Validador.esNombreValido(n), "\(n)") }

    @Test func nombreEnormeOTraiciones() {
        #expect(!Validador.esNombreValido(String(repeating: "a", count: 1_000_000)))
        #expect(!Validador.esNombreValido("a" + String(repeating: "\u{0301}", count: 100_000)))
        #expect(!Validador.esNombreValido(String(repeating: "á", count: 51)))
        #expect(Validador.esNombreValido(String(repeating: "á", count: 50)))
    }

    // MARK: Bordes: alias, correo, teléfono

    @Test(arguments: ["abc", "a.b_c", "usuario_01", "x.y.z", String(repeating: "a", count: 20)])
    func aliasValidos(_ a: String) { #expect(Validador.esAliasValido(a)) }

    @Test(arguments: ["", "ab", "a b", "AB1", "ñandú", "ad\u{200B}min", "abc\n", "abc\u{0301}", "ａｂｃ", "abc😀",
                      String(repeating: "a", count: 21), String(repeating: "a", count: 500_000)])
    func aliasInvalidosExtra(_ a: String) { #expect(!Validador.esAliasValido(a)) }

    @Test(arguments: ["a@b.co", "ana.lopez+0fraude@comunidad.test", "x_y-z%1@sub.dominio.com.mx", "A@B.MX"])
    func correosValidos(_ c: String) { #expect(Validador.esCorreoValido(c)) }

    @Test(arguments: ["", " ", "@", "@b.co", "a@", "a@b", "a@b.c", "a@b.c0m", ".a@b.co", "a.@b.co", "a@.b.co", "a@b..co",
                      "a@-b.co", "a@b-.co", "a@b.co.", "a b@c.co", "a@b.co\n", "\na@b.co", "a@b.co\u{0301}", "a\u{200B}@b.co",
                      "añ@b.co", "a@ñ.co", "a@b.co\u{202E}", "<a>@b.co", "a,b@c.co", "a@b@c.co",
                      String(repeating: "a", count: 140) + "@b.co", String(repeating: "a", count: 1_000_000) + "@b.co",
                      "a@" + String(repeating: "b.", count: 100_000) + "co"])
    func correosInvalidosExtra(_ c: String) { #expect(!Validador.esCorreoValido(c), "\(c.prefix(40))") }

    @Test(arguments: ["", "1234567", "+", "++5212345678", "5212345678+", "tel: 5512345678", "55\u{200B}12345678", "٥٥١٢٣٤٥٦٧٨",
                      "５５１２３４５６７８", "55 1234 5678\n", "1234567890123456", String(repeating: "1", count: 1_000_000)])
    func telefonosInvalidosExtra(_ t: String) { #expect(!Validador.esTelefonoValido(t)) }

    // MARK: Bordes: contraseña

    @Test func contrasenaVaciaYEnorme() {
        #expect(Validador.contrasenaNueva("", confirmacion: "", alias: "", correo: "").mensaje(para: .contrasena) != nil)
        let enorme = String(repeating: "a1", count: 500_000)
        #expect(Validador.contrasenaNueva(enorme, confirmacion: enorme, alias: "x", correo: "x@y.mx").mensaje(para: .contrasena) != nil)
        // 11 "caracteres" a la vista pero 200 mil escalares: no debe llegar al hash.
        let combinantes = String(repeating: "a" + String(repeating: "\u{0301}", count: 20_000), count: 10) + "1"
        #expect(Validador.contrasenaNueva(combinantes, confirmacion: combinantes, alias: "x", correo: "x@y.mx").mensaje(para: .contrasena) != nil)
    }

    @Test func contrasenaConEmojiYUnicodeSeAcepta() {
        let c = "Contraseña-🔐-segura-9"
        #expect(Validador.contrasenaNueva(c, confirmacion: c, alias: "x", correo: "x@y.mx").isEmpty)
        let familia = "👨\u{200D}👩\u{200D}👧-llave-77"
        #expect(Validador.contrasenaNueva(familia, confirmacion: familia, alias: "x", correo: "x@y.mx").isEmpty)
    }

    @Test func contrasenaNoSeTocaYLosEspaciosCuentan() {
        let c = "  espacios  1234  "
        #expect(Validador.contrasenaNueva(c, confirmacion: c, alias: "x", correo: "x@y.mx").isEmpty)
        #expect(Validador.contrasenaNueva(c, confirmacion: c.trimmingCharacters(in: .whitespaces), alias: "x", correo: "x@y.mx")
            .mensaje(para: .confirmacion) != nil)
    }

    @Test func contrasenaLimitesExactos() {
        let nueve = String(repeating: "a", count: 8) + "1"
        let diez = String(repeating: "a", count: 9) + "1"
        let sesentaYCuatro = String(repeating: "a", count: 63) + "1"
        let sesentaYCinco = String(repeating: "a", count: 64) + "1"
        #expect(Validador.contrasenaNueva(nueve, confirmacion: nueve, alias: "x", correo: "x@y.mx").mensaje(para: .contrasena) != nil)
        #expect(Validador.contrasenaNueva(diez, confirmacion: diez, alias: "x", correo: "x@y.mx").isEmpty)
        #expect(Validador.contrasenaNueva(sesentaYCuatro, confirmacion: sesentaYCuatro, alias: "x", correo: "x@y.mx").isEmpty)
        #expect(Validador.contrasenaNueva(sesentaYCinco, confirmacion: sesentaYCinco, alias: "x", correo: "x@y.mx").mensaje(para: .contrasena) != nil)
    }

    @Test func contrasenaConParteLocalDelCorreoPeroSinCorreoValido() {
        // "@y.mx" no tiene parte local: no debe tomarse "y.mx" como si fuera el usuario.
        #expect(Validador.contrasenaNueva("zzy.mx12345", confirmacion: "zzy.mx12345", alias: "", correo: "@y.mx").isEmpty)
        #expect(Validador.contrasenaNueva("Zeta-lopez-77", confirmacion: "Zeta-lopez-77", alias: "", correo: "lopez@y.mx")
            .mensaje(para: .contrasena) == "La contraseña no debe contener tu usuario ni tu correo.")
        #expect(Validador.contrasenaNueva("Fraude0-Cero", confirmacion: "Fraude0-Cero", alias: "", correo: "").isEmpty)
    }

    // MARK: Bordes: reporte

    @Test func reporteEnBlancoYConEspaciosNoPasa() {
        var b = Self.borradorValido()
        b.ciudad = "      "; b.titulo = String(repeating: " ", count: 20); b.descripcion = String(repeating: "\n", count: 30)
        let e = Validador.reporte(b, ahora: ahora)
        #expect(e.mensaje(para: .ciudad) != nil)
        #expect(e.mensaje(para: .titulo) != nil)
        #expect(e.mensaje(para: .descripcion) != nil)
    }

    @Test func reporteLimitesExactosDeTexto() {
        var b = Self.borradorValido()
        b.titulo = String(repeating: "t", count: 10); b.ciudad = "ab"; b.descripcion = String(repeating: "d", count: 20)
        #expect(Validador.reporte(b, ahora: ahora).isEmpty)
        b.titulo = String(repeating: "t", count: 120); b.ciudad = String(repeating: "c", count: 60); b.descripcion = String(repeating: "d", count: 2_000)
        #expect(Validador.reporte(b, ahora: ahora).isEmpty)
        b.titulo = String(repeating: "t", count: 121); b.ciudad = String(repeating: "c", count: 61); b.descripcion = String(repeating: "d", count: 2_001)
        let e = Validador.reporte(b, ahora: ahora)
        #expect(e.mensaje(para: .titulo) != nil && e.mensaje(para: .ciudad) != nil && e.mensaje(para: .descripcion) != nil)
    }

    @Test func reporteConCadenasEnormesYCombinantesNoRevientaYSeRechaza() {
        var b = Self.borradorValido()
        b.titulo = "t" + String(repeating: "\u{0301}", count: 200_000)       // pocos "caracteres", muchos escalares
        b.descripcion = String(repeating: "d", count: 3_000_000)
        b.urlOTexto = String(repeating: "u", count: 3_000_000)
        b.ciudad = String(repeating: "🙂", count: 200_000)
        let e = Validador.reporte(b, ahora: ahora)
        #expect(e.mensaje(para: .titulo) != nil)
        #expect(e.mensaje(para: .descripcion) != nil)
        #expect(e.mensaje(para: .urlOTexto) != nil)
        #expect(e.mensaje(para: .ciudad) != nil)
    }

    @Test func reporteAceptaEmojisYUnicode() {
        var b = Self.borradorValido()
        b.ciudad = "Ciudad de México 🇲🇽"
        b.titulo = "Estafa 🚨 con tarjeta falsa"
        b.descripcion = "Me escribieron por WhatsApp haciéndose pasar por el banco 🏦 y pidieron el NIP."
        #expect(Validador.reporte(b, ahora: ahora).isEmpty)
    }

    @Test func fechaNoFinitaOEnElLimite() {
        var b = Self.borradorValido()
        for f in [Date(timeIntervalSince1970: .nan), .distantFuture, .distantPast, Date(timeIntervalSince1970: .infinity)] {
            b.fechaIncidente = f
            #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .fecha) != nil)
        }
        b.fechaIncidente = ahora
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .fecha) == nil)
        b.fechaIncidente = ahora.addingTimeInterval(-365 * 86_400)
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .fecha) == nil)
        b.fechaIncidente = ahora.addingTimeInterval(-365 * 86_400 - 1)
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .fecha) != nil)
    }

    @Test func ahoraNoFinitoNoPermiteNingunaFecha() {
        let e = Validador.reporte(Self.borradorValido(), ahora: Date(timeIntervalSince1970: .nan))
        #expect(e.mensaje(para: .fecha) != nil)
    }

    @Test func enlaceDeMasDe2048Caracteres() {
        var b = Self.borradorValido()
        b.urlOTexto = "https://a.com/" + String(repeating: "x", count: 2_048)
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .urlOTexto) == "El enlace o texto admite hasta 2048 caracteres.")
    }

    @Test(arguments: ["https://a.com\u{202E}/x", "https://\u{200B}a.com", "https://a.com/\u{FEFF}", "http://a.com:99999", "https://a.com\u{2066}"])
    func enlacesConInvisiblesOControlesSeRechazan(_ enlace: String) {
        var b = Self.borradorValido(); b.urlOTexto = enlace
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .urlOTexto) != nil)
    }

    /// Cada dato mal escrito de la persona afectada dice qué le falta.
    @Test func otraPersonaExplicaQueDatoEstaMal() {
        var b = Self.borradorValido()
        b.afectado = .otraPersona
        b.persona = PersonaAfectada(nombre: "Rosa 123", contacto: "rosa@", autorizo: true)
        var e = Validador.reporte(b, ahora: ahora)
        #expect(e.mensaje(para: .personaNombre) == "El nombre solo lleva letras y espacios, sin números ni símbolos.")
        #expect(e.mensaje(para: .personaContacto) == "Ese correo no es válido. Ejemplo: nombre@dominio.com.")
        b.persona = PersonaAfectada(nombre: "Ma. Elena O'Brien-Pérez", contacto: "12345", autorizo: true)
        e = Validador.reporte(b, ahora: ahora)
        #expect(e.mensaje(para: .personaNombre) == nil)
        #expect(e.mensaje(para: .personaContacto) == "El teléfono lleva de 8 a 15 dígitos; puede empezar con + y llevar espacios o guiones.")
        b.persona.contacto = "llámame"
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .personaContacto) == "Escribe un correo (con @) o un teléfono solo con números.")
        b.persona.contacto = "+52 (55) 1234-5678"
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .personaContacto) == nil)
    }

    @Test func laCiudadLlevaLetrasYNoNumeros() {
        for ciudad in ["CDMX", "San Luis Potosí", "Mérida, Yuc.", "Ciudad de México 🇲🇽"] { #expect(Validador.esCiudadValida(ciudad), "\(ciudad)") }
        for ciudad in ["12345", "A1", "CP 06000", "5512345678", "a"] { #expect(!Validador.esCiudadValida(ciudad), "\(ciudad)") }
        var b = Self.borradorValido()
        b.ciudad = "06000"
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .ciudad) == "Escribe el nombre de la ciudad, sin números. Ejemplo: Guadalajara.")
    }

    @Test func otraPersonaConContactoCorreoOTelefono() {
        var b = Self.borradorValido()
        b.afectado = .otraPersona
        b.persona = PersonaAfectada(nombre: "Ro", contacto: "rosa@correo.mx", autorizo: true)
        #expect(Validador.reporte(b, ahora: ahora).isEmpty)
        b.persona.nombre = "R"
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .personaNombre) != nil)
        b.persona = PersonaAfectada(nombre: "Rosa", contacto: "hola", autorizo: true)
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .personaContacto) != nil)
    }

    @Test func tipoOtroConEspaciosOSoloEmojis() {
        var b = Self.borradorValido(); b.tipo = .otro
        b.tipoOtro = "   "
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .tipoOtro) != nil)
        b.tipoOtro = "ab"
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .tipoOtro) != nil)
        b.tipoOtro = "Falso técnico"
        #expect(Validador.reporte(b, ahora: ahora).isEmpty)
    }

    @Test func soloUnErrorPorCampoPorMensajeYMensajesEnOrden() {
        var d = Self.registroValido()
        d.nombre = ""; d.apellido = ""; d.aceptaAviso = false
        let e = Validador.registro(d)
        #expect(e.mensajes.count == 3)
        #expect(e.map(\.campo) == [.nombre, .apellido, .aviso])
    }

    @Test func registroConTodoVacioNoRevienta() {
        let e = Validador.registro(RegistroDatos())
        for c in [Campo.nombre, .apellido, .alias, .correo, .contrasena, .aviso] { #expect(e.mensaje(para: c) != nil) }
        #expect(e.mensaje(para: .pais) == nil)
    }

    // MARK: Bordes: perfil, comentario, moderación, código

    @Test func perfilSinCambiarCorreoNoPideContrasena() {
        var p = PerfilDatos(desde: .vacio)
        p.nombre = "Ana"; p.apellido = "López"; p.alias = "ana_lopez"; p.correo = "ana@comunidad.test"
        #expect(Validador.perfil(p, correoOriginal: "ana@comunidad.test").isEmpty)
        p.contrasenaActual = ""
        #expect(Validador.perfil(p, correoOriginal: "otro@comunidad.test").mensaje(para: .contrasenaActual) != nil)
        p.contrasenaActual = "algo"
        #expect(Validador.perfil(p, correoOriginal: "otro@comunidad.test").isEmpty)
    }

    @Test func perfilBiografiaEnLimiteYEnorme() {
        var p = PerfilDatos(desde: .vacio)
        p.nombre = "Ana"; p.apellido = "López"; p.alias = "ana_lopez"; p.correo = "ana@comunidad.test"
        p.biografia = String(repeating: "🙂", count: 300)
        #expect(Validador.perfil(p, correoOriginal: p.correo).isEmpty)
        p.biografia = "a" + String(repeating: "\u{0301}", count: 100_000)
        #expect(Validador.perfil(p, correoOriginal: p.correo).mensaje(para: .biografia) != nil)
        p.biografia = String(repeating: "b", count: 3_000_000)
        #expect(Validador.perfil(p, correoOriginal: p.correo).mensaje(para: .biografia) != nil)
    }

    @Test func comentarioBordes() {
        #expect(!Validador.comentario("").isEmpty)
        #expect(!Validador.comentario("   ").isEmpty)
        #expect(!Validador.comentario(" x ").isEmpty)
        #expect(Validador.comentario("🙂🙂").isEmpty)
        #expect(Validador.comentario(String(repeating: "a", count: 500)).isEmpty)
        #expect(!Validador.comentario("a" + String(repeating: "\u{0301}", count: 100_000)).isEmpty)
        #expect(!Validador.comentario(String(repeating: "a", count: 3_000_000)).isEmpty)
    }

    @Test func moderacionBordes() {
        let motivo10 = String(repeating: "m", count: 10)
        #expect(Validador.moderacion(nuevo: .rechazado, riesgo: nil, observaciones: motivo10).isEmpty)
        #expect(Validador.moderacion(nuevo: .rechazado, riesgo: nil, observaciones: String(repeating: "m", count: 9)).count == 1)
        #expect(Validador.moderacion(nuevo: .rechazado, riesgo: nil, observaciones: String(repeating: " ", count: 20)).count == 1)
        #expect(Validador.moderacion(nuevo: .rechazado, riesgo: nil, observaciones: String(repeating: "m", count: 501)).count == 1)
        #expect(Validador.moderacion(nuevo: .validado, riesgo: .noEvaluado, observaciones: "").mensaje(para: .riesgo) != nil)
        #expect(Validador.moderacion(nuevo: .validado, riesgo: .alto, observaciones: "").isEmpty)
        #expect(Validador.moderacion(nuevo: .canalizado, riesgo: nil, observaciones: String(repeating: "m", count: 501))
            .mensaje(para: .observaciones) == "Las observaciones admiten hasta 500 caracteres.")
        #expect(Validador.moderacion(nuevo: .rechazado, riesgo: nil, observaciones: String(repeating: "m", count: 3_000_000)).count == 1)
    }

    @Test(arguments: ["", "1234567", " 123456", "123456 ", "123456\n", "12345\u{0301}6", "123456\u{0301}", "１２３４５６", "١٢٣٤٥٦", "12 3456",
                      "12345😀", String(repeating: "1", count: 1_000_000)])
    func codigosInvalidosExtra(_ c: String) { #expect(!Validador.codigo(c).isEmpty) }

    @Test func listaDePaisesYContrasenasComunesNoTienenVaciosNiDuplicados() {
        #expect(Set(Validador.paises).count == Validador.paises.count)
        #expect(Validador.paises.contains("México"))
        #expect(Validador.contrasenasComunes.allSatisfy { $0 == $0.lowercased() && $0.count >= 10 })
    }

    @Test func listaComunesDetectaMayusculasYMinusculas() {
        #expect(Validador.contrasenaNueva("PASSWORD123", confirmacion: "PASSWORD123", alias: "x", correo: "x@y.mx")
            .mensaje(para: .contrasena) == "Esa contraseña es muy común; elige otra.")
    }
}
