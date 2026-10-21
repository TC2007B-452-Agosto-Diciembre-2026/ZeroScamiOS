//
//  Validador.swift
//  PrototipoApp
//
//  Reglas de todos los formularios, con mensajes en español. Mismo patrón que la práctica
//  Demo-RetoSwiftUI452 (reglas con nombre y una lista de errores), pero cada error dice a qué
//  campo pertenece para mostrarlo debajo. Las usa la interfaz y también el servidor: nunca se
//  confía en lo que valida el cliente.
//
//  Las reglas esperan texto ya pasado por `Sanitizador`, pero no dependen de ello para ser seguras:
//  no usan índices ni conversiones que puedan fallar, y los topes de longitud cuentan también
//  escalares Unicode (una letra con 100 mil acentos es "un carácter" a la vista).
//

import Foundation

nonisolated enum Campo: String, Sendable, Hashable {
    case nombre, apellido, pais, alias, correo, contrasena, confirmacion, aviso
    case contrasenaActual, ciudad, personaNombre, personaContacto, personaAutorizo
    case tipoOtro, titulo, fecha, urlOTexto, descripcion, adjuntos, biografia
    case comentario, observaciones, riesgo, codigo
}

nonisolated struct ErrorCampo: Sendable, Hashable {
    let campo: Campo
    let mensaje: String
}

nonisolated extension Array where Element == ErrorCampo {
    func mensaje(para campo: Campo) -> String? { first { $0.campo == campo }?.mensaje }
    var mensajes: [String] { map(\.mensaje) }
}

nonisolated enum Validador {
    static let paises = ["México", "Argentina", "Chile", "Colombia", "España", "Estados Unidos", "Perú", "Otro"]

    /// Contraseñas que pasan la longitud y la mezcla de letras y números pero aparecen en todas las filtraciones.
    static let contrasenasComunes: Set<String> = [
        "password123", "password1234", "contrasena123", "contraseña123", "qwerty12345", "qwerty123456",
        "abc123456789", "admin123456", "usuario12345", "mexico12345", "iloveyou123", "123456789abc",
        "1q2w3e4r5t", "1qaz2wsx3edc", "a1234567890", "q1w2e3r4t5", "superman123", "football123",
        "monkey12345", "dragon12345", "letmein12345", "welcome123", "teamo123456", "hola123456",
        "fraude12345", "0fraude123", "0fraude2026", "zeroscam123", "zeroscam2026",
    ]

    // MARK: Piezas internas

    /// Dentro del rango, contando caracteres sin los espacios de los extremos, y sin pasar del tope
    /// superior en escalares Unicode (que es lo que mide la columna SQL).
    private static func enRango(_ s: String, _ rango: ClosedRange<Int>) -> Bool {
        guard s.utf8.count <= rango.upperBound * 4, s.unicodeScalars.count <= rango.upperBound else { return false }
        return rango.contains(s.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    private static func esLetra(_ e: Unicode.Scalar) -> Bool {
        switch e.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    private static func esMarca(_ e: Unicode.Scalar) -> Bool {
        switch e.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    private static func esLetraOCifraASCII(_ b: UInt8) -> Bool {
        (0x30...0x39).contains(b) || (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b)
    }

    // MARK: Reglas sueltas

    /// Correo ASCII de hasta 150 caracteres: parte local de 1 a 64, dominio con etiquetas que empiezan y
    /// terminan en letra o dígito, y una extensión de 2 a 64 letras.
    static func esCorreoValido(_ s: String) -> Bool {
        guard s.utf8.count <= 150 else { return false }
        let bytes = Array(s.utf8)
        guard let arroba = bytes.firstIndex(of: 0x40), bytes.lastIndex(of: 0x40) == arroba else { return false }
        let local = bytes[..<arroba]
        let dominio = bytes[(arroba + 1)...]
        guard (1...64).contains(local.count), local.first != 0x2E, local.last != 0x2E else { return false }
        var anteriorPunto = false
        for b in local {
            guard esLetraOCifraASCII(b) || [0x2E, 0x5F, 0x25, 0x2B, 0x2D].contains(b) else { return false }
            if b == 0x2E && anteriorPunto { return false }
            anteriorPunto = b == 0x2E
        }
        let etiquetas = dominio.split(separator: 0x2E, omittingEmptySubsequences: false)
        guard etiquetas.count >= 2 else { return false }
        for etiqueta in etiquetas {
            guard (1...63).contains(etiqueta.count), let primero = etiqueta.first, let ultimo = etiqueta.last,
                  esLetraOCifraASCII(primero), esLetraOCifraASCII(ultimo),
                  etiqueta.allSatisfy({ esLetraOCifraASCII($0) || $0 == 0x2D }) else { return false }
        }
        guard let extension_ = etiquetas.last, (2...64).contains(extension_.count),
              extension_.allSatisfy({ ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }) else { return false }
        return true
    }

    /// De 2 a 50 caracteres: letras de cualquier alfabeto (con sus acentos), espacio, apóstrofo y guion.
    /// Empieza y termina en letra.
    static func esNombreValido(_ s: String) -> Bool {
        let escalares = s.unicodeScalars
        guard s.utf8.count <= 400, escalares.count <= 100, (2...50).contains(s.count),
              let primero = escalares.first, let ultimo = escalares.last,
              esLetra(primero), esLetra(ultimo) || esMarca(ultimo) else { return false }
        return escalares.allSatisfy { esLetra($0) || esMarca($0) || $0 == " " || $0 == "'" || $0 == "\u{2019}" || $0 == "-" }
    }

    /// Nombre completo de un tercero (persona afectada): de 2 a 100 caracteres con las mismas letras
    /// que `esNombreValido`, más el punto de las abreviaturas ("Ma. Elena"). Sin cifras ni símbolos.
    static func esNombreCompletoValido(_ s: String) -> Bool {
        let escalares = s.unicodeScalars
        guard s.utf8.count <= 800, escalares.count <= 200, (2...100).contains(s.count),
              let primero = escalares.first, let ultimo = escalares.last,
              esLetra(primero), esLetra(ultimo) || esMarca(ultimo) || ultimo == "." else { return false }
        return escalares.allSatisfy {
            esLetra($0) || esMarca($0) || $0 == " " || $0 == "'" || $0 == "\u{2019}" || $0 == "-" || $0 == "."
        }
    }

    /// Una ciudad lleva letras y no números: "CDMX", "San Luis Potosí", "Mérida, Yuc.". Un código
    /// postal o un teléfono escritos ahí no pasan.
    static func esCiudadValida(_ s: String) -> Bool {
        guard enRango(s, 2...60) else { return false }
        let escalares = s.unicodeScalars
        return escalares.filter(esLetra).count >= 2 && !escalares.contains { $0.properties.numericType != nil }
    }

    /// De 3 a 20 caracteres entre a-z, 0-9, "_" y ".".
    static func esAliasValido(_ s: String) -> Bool {
        guard (3...20).contains(s.utf8.count) else { return false }
        return s.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || (0x30...0x39).contains($0) || $0 == 0x5F || $0 == 0x2E }
    }

    /// De 8 a 15 dígitos, con "+" solo al inicio y separadores " ", "(", ")" y "-".
    static func esTelefonoValido(_ s: String) -> Bool {
        guard (8...20).contains(s.utf8.count) else { return false }
        var digitos = 0
        for (i, b) in s.utf8.enumerated() {
            if (0x30...0x39).contains(b) { digitos += 1 }
            else if b == 0x2B { if i != 0 { return false } }
            else if ![0x20, 0x28, 0x29, 0x2D].contains(b) { return false }
        }
        return (8...15).contains(digitos)
    }

    // MARK: Formularios

    static func registro(_ d: RegistroDatos) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        if !esNombreValido(d.nombre) { e.append(.init(campo: .nombre, mensaje: "Escribe tu nombre (2 a 50 letras).")) }
        if !esNombreValido(d.apellido) { e.append(.init(campo: .apellido, mensaje: "Escribe tu apellido (2 a 50 letras).")) }
        if !paises.contains(d.pais) { e.append(.init(campo: .pais, mensaje: "Elige un país de la lista.")) }
        if !esAliasValido(d.alias) {
            e.append(.init(campo: .alias, mensaje: "El usuario lleva de 3 a 20 caracteres: minúsculas, números, punto o guion bajo."))
        }
        if !esCorreoValido(d.correo) { e.append(.init(campo: .correo, mensaje: "Escribe un correo válido, por ejemplo nombre@dominio.com.")) }
        e += contrasenaNueva(d.contrasena, confirmacion: d.confirmacion, alias: d.alias, correo: d.correo)
        if !d.aceptaAviso { e.append(.init(campo: .aviso, mensaje: "Acepta el aviso de privacidad para crear tu cuenta.")) }
        return e
    }

    /// Un mensaje por campo (la primera regla que falla), para que el error debajo del campo sea claro.
    /// La contraseña no se recorta ni se limpia; el tope de escalares evita mandar al hash un texto enorme.
    static func contrasenaNueva(_ c: String, confirmacion: String, alias: String, correo: String) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        let usuarioCorreo = correo.firstIndex(of: "@").map { String(correo[..<$0]).lowercased() } ?? ""
        if !(10...64).contains(c.count) || c.unicodeScalars.count > 256 {
            e.append(.init(campo: .contrasena, mensaje: "La contraseña debe tener entre 10 y 64 caracteres."))
        } else if !c.contains(where: \.isLetter) || !c.contains(where: \.isNumber) {
            e.append(.init(campo: .contrasena, mensaje: "Incluye al menos una letra y un número."))
        } else if contrasenasComunes.contains(c.lowercased()) {
            e.append(.init(campo: .contrasena, mensaje: "Esa contraseña es muy común; elige otra."))
        } else if (alias.count >= 3 && c.lowercased().contains(alias.lowercased()))
                    || (usuarioCorreo.count >= 3 && c.lowercased().contains(usuarioCorreo)) {
            e.append(.init(campo: .contrasena, mensaje: "La contraseña no debe contener tu usuario ni tu correo."))
        }
        if c != confirmacion { e.append(.init(campo: .confirmacion, mensaje: "Las contraseñas no coinciden.")) }
        return e
    }

    static func reporte(_ b: ReporteBorrador, ahora: Date) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        if !enRango(b.ciudad, 2...60) {
            e.append(.init(campo: .ciudad, mensaje: "Indica la ciudad donde ocurrió (2 a 60 caracteres)."))
        } else if !esCiudadValida(b.ciudad) {
            e.append(.init(campo: .ciudad, mensaje: "Escribe el nombre de la ciudad, sin números. Ejemplo: Guadalajara."))
        }
        if b.afectado == .otraPersona {
            // Cada dato dice qué le falta: no es lo mismo no haber escrito nada que haberlo escrito mal.
            if !enRango(b.persona.nombre, 2...100) {
                e.append(.init(campo: .personaNombre, mensaje: "Escribe el nombre de la persona afectada."))
            } else if !esNombreCompletoValido(b.persona.nombre) {
                e.append(.init(campo: .personaNombre, mensaje: "El nombre solo lleva letras y espacios, sin números ni símbolos."))
            }
            let contacto = b.persona.contacto
            if !(esCorreoValido(contacto) || esTelefonoValido(contacto)) {
                let mensaje: String
                if contacto.isEmpty {
                    mensaje = "Escribe un teléfono (8 a 15 dígitos) o un correo válido."
                } else if contacto.contains("@") {
                    mensaje = "Ese correo no es válido. Ejemplo: nombre@dominio.com."
                } else if contacto.contains(where: \.isLetter) {
                    mensaje = "Escribe un correo (con @) o un teléfono solo con números."
                } else {
                    mensaje = "El teléfono lleva de 8 a 15 dígitos; puede empezar con + y llevar espacios o guiones."
                }
                e.append(.init(campo: .personaContacto, mensaje: mensaje))
            }
            if !b.persona.autorizo {
                e.append(.init(campo: .personaAutorizo, mensaje: "Confirma que la persona te autorizó a compartir sus datos."))
            }
        }
        if b.tipo == .otro && !enRango(b.tipoOtro, 3...50) {
            e.append(.init(campo: .tipoOtro, mensaje: "Especifica el tipo de fraude (3 a 50 caracteres)."))
        }
        if !enRango(b.titulo, 10...120) { e.append(.init(campo: .titulo, mensaje: "El título debe tener entre 10 y 120 caracteres.")) }
        // Una fecha NaN no es mayor ni menor que nada (y Date la compara como "igual"): se exige que sea finita.
        let limiteInferior = ahora.addingTimeInterval(-365 * 86_400)
        if !(b.fechaIncidente.timeIntervalSince1970.isFinite && ahora.timeIntervalSince1970.isFinite)
            || b.fechaIncidente > ahora || b.fechaIncidente < limiteInferior {
            e.append(.init(campo: .fecha, mensaje: "La fecha no puede ser futura ni de hace más de un año."))
        }
        if b.urlOTexto.utf8.count > 2_048 * 4 || b.urlOTexto.unicodeScalars.count > 2_048 {
            e.append(.init(campo: .urlOTexto, mensaje: "El enlace o texto admite hasta 2048 caracteres."))
        } else if URLTools.pareceURL(b.urlOTexto) && URLTools.normalizar(b.urlOTexto) == nil {
            e.append(.init(campo: .urlOTexto, mensaje: "Solo se aceptan enlaces http:// o https:// válidos."))
        }
        if !enRango(b.descripcion, 20...2_000) {
            e.append(.init(campo: .descripcion, mensaje: "Describe lo ocurrido (20 a 2000 caracteres)."))
        }
        if b.adjuntos.count > 3 { e.append(.init(campo: .adjuntos, mensaje: "Máximo 3 archivos de evidencia.")) }
        return e
    }

    static func perfil(_ p: PerfilDatos, correoOriginal: String) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        if !esNombreValido(p.nombre) { e.append(.init(campo: .nombre, mensaje: "Escribe tu nombre (2 a 50 letras).")) }
        if !esNombreValido(p.apellido) { e.append(.init(campo: .apellido, mensaje: "Escribe tu apellido (2 a 50 letras).")) }
        if !paises.contains(p.pais) { e.append(.init(campo: .pais, mensaje: "Elige un país de la lista.")) }
        if !esAliasValido(p.alias) {
            e.append(.init(campo: .alias, mensaje: "El usuario lleva de 3 a 20 caracteres: minúsculas, números, punto o guion bajo."))
        }
        if !esCorreoValido(p.correo) { e.append(.init(campo: .correo, mensaje: "Escribe un correo válido, por ejemplo nombre@dominio.com.")) }
        if !enRango(p.biografia, 0...300) { e.append(.init(campo: .biografia, mensaje: "La biografía admite hasta 300 caracteres.")) }
        if p.correo != correoOriginal && (p.contrasenaActual ?? "").isEmpty {
            e.append(.init(campo: .contrasenaActual, mensaje: "Confirma tu contraseña para cambiar el correo."))
        }
        return e
    }

    static func comentario(_ t: String) -> [ErrorCampo] {
        enRango(t, 2...500) ? [] : [.init(campo: .comentario, mensaje: "El comentario debe tener entre 2 y 500 caracteres.")]
    }

    static func moderacion(nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        if nuevo == .validado && (riesgo == nil || riesgo == .noEvaluado) {
            e.append(.init(campo: .riesgo, mensaje: "Asigna un nivel de riesgo para validar."))
        }
        if nuevo == .rechazado && !enRango(observaciones, 10...500) {
            e.append(.init(campo: .observaciones, mensaje: "Explica el motivo del rechazo (10 a 500 caracteres)."))
        } else if !enRango(observaciones, 0...500) {
            e.append(.init(campo: .observaciones, mensaje: "Las observaciones admiten hasta 500 caracteres."))
        }
        return e
    }

    static func codigo(_ c: String) -> [ErrorCampo] {
        let valido = c.utf8.count == 6 && c.utf8.allSatisfy { (0x30...0x39).contains($0) }
        return valido ? [] : [.init(campo: .codigo, mensaje: "El código tiene 6 dígitos.")]
    }
}
