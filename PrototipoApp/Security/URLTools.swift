//
//  URLTools.swift
//  PrototipoApp
//
//  Los enlaces reportados son peligrosos por definición: la app nunca los abre. Aquí se decide si
//  un texto es un enlace, se normaliza (solo http/https, sin "usuario@" que esconde el host real)
//  y se "desactiva" (hxxps, [.]) para mostrarlo y compartirlo sin que sea tocable.
//
//  El análisis es manual (sin URLComponents ni conversiones que puedan fallar): cualquier texto,
//  por raro que sea, devuelve nil o un resultado seguro; nunca provoca un crash.
//

import Foundation

nonisolated enum URLTools {
    private static let esquemasPeligrosos = ["javascript:", "data:", "file:", "vbscript:"]
    // La barra invertida cuenta como "/" (así la tratan los navegadores): "https://estafa.com\@banco.com" va a estafa.com.
    private static let delimitadores: Set<Character> = ["/", "?", "#", "\\"]
    private static let maxLongitud = 2_048

    // MARK: - API pública

    static func pareceURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, !t.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.properties.generalCategory == .control })
        else { return false }
        if t.contains("://") || t.hasPrefix("www.") { return true }
        if esquemasPeligrosos.contains(where: t.hasPrefix) { return true }
        // Textos larguísimos: ni se evalúa la expresión regular (coste); ya no son un dominio simple.
        guard t.utf8.count <= maxLongitud else { return false }
        return t.wholeMatch(of: /[\p{L}\p{N}_\-]+(\.[\p{L}\p{N}_\-]+)*\.\p{L}{2,24}(\/\S*)?/) != nil
    }

    /// Devuelve "esquema://host[:puerto][ruta]" con esquema y host en minúsculas, o nil si no es un
    /// enlace http/https seguro de mostrar.
    static func normalizar(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.utf8.count <= maxLongitud,
              !t.unicodeScalars.contains(where: esCaracterProhibido) else { return nil }
        let minusculas = t.lowercased()
        if esquemasPeligrosos.contains(where: minusculas.hasPrefix) { return nil }

        let (esquemaCrudo, resto) = separarEsquema(t)
        let esquema = (esquemaCrudo ?? "https").lowercased()
        guard esquema == "http" || esquema == "https" else { return nil }

        let finAutoridad = resto.firstIndex(where: delimitadores.contains) ?? resto.endIndex
        var autoridad = String(resto[..<finAutoridad])
        let cola = String(resto[finAutoridad...])

        // "banco.com@estafa.com" se ve como banco.com pero va a estafa.com: se descarta lo anterior a la
        // última "@". Sin esquema explícito, una "@" no es un enlace (p. ej. "mailto:x@y.com").
        if let arroba = autoridad.lastIndex(of: "@") {
            guard esquemaCrudo != nil else { return nil }
            autoridad = String(autoridad[autoridad.index(after: arroba)...])
        }

        let (hostCrudo, puertoCrudo) = separarPuerto(autoridad)
        guard let hostCrudo else { return nil }
        let host = hostCrudo.lowercased()
        guard esHostValido(host) else { return nil }

        var salida = esquema + "://" + host
        if !puertoCrudo.isEmpty {
            guard puertoCrudo.count <= 5, puertoCrudo.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let puerto = Int(puertoCrudo), (1...65_535).contains(puerto) else { return nil }
            salida += ":\(puerto)"
        }
        return salida + codificarNoASCII(cola)
    }

    /// Host real del enlace (sin usuario ni puerto), en minúsculas. Exige esquema "://".
    static func host(de url: String) -> String? {
        extraerHost(url, exigirEsquema: true)
    }

    /// "https://sitio-falso.com/x" → "hxxps://sitio-falso[.]com/x".
    /// Solo debe recibir la salida de `normalizar` (o un enlace ya limpio): no es idempotente, aplicarla
    /// dos veces desactivaría de nuevo lo ya desactivado.
    static func desactivar(_ url: String) -> String {
        var prefijo = ""
        var resto = url
        let (esquemaOpcional, despues) = separarEsquema(url)
        if let esquema = esquemaOpcional {
            prefijo = esquema + "://"
            resto = despues
            let bajo = prefijo.lowercased()
            if bajo.hasPrefix("http") { prefijo = "hxxp" + bajo.dropFirst(4) }
        }
        let fin = resto.firstIndex(where: delimitadores.contains) ?? resto.endIndex
        let autoridad = resto[..<fin].replacingOccurrences(of: ".", with: "[.]")
        // Enlaces incrustados en la ruta o la consulta ("?u=https://otro.com") también pierden el esquema.
        let cola = resto[fin...]
            .replacingOccurrences(of: "https://", with: "hxxps://", options: .caseInsensitive)
            .replacingOccurrences(of: "http://", with: "hxxp://", options: .caseInsensitive)
        return prefijo + autoridad + cola
    }

    /// Lo que guarda SitioWeb_URL.estado_certificado. No se consulta la red: solo el esquema.
    static func estadoCertificado(_ url: String) -> String {
        url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("https://") ? "HTTPS" : "SIN HTTPS"
    }

    /// Dominios con letras de otros alfabetos (o su forma "xn--") que imitan a uno conocido.
    static func esPosibleHomografo(_ url: String) -> Bool {
        guard let host = extraerHost(url, exigirEsquema: false) else { return false }
        return host.unicodeScalars.contains { !$0.isASCII }
            || host.contains("%")   // codificación que no se pudo decodificar: sospechoso
            || host.split(separator: ".").contains { $0.hasPrefix("xn--") }
    }

    // MARK: - Piezas internas

    /// Separa "esquema://resto". Si "://" aparece después de una "/", "?" o "#" no es el esquema
    /// (es un enlace incrustado en la ruta) y el texto se considera sin esquema.
    private static func separarEsquema(_ t: String) -> (esquema: String?, resto: String) {
        guard let r = t.range(of: "://"), !t[..<r.lowerBound].contains(where: delimitadores.contains)
        else { return (nil, t) }
        return (String(t[..<r.lowerBound]), String(t[r.upperBound...]))
    }

    /// Separa "host:puerto". Los corchetes (IPv6) se tratan como host sin puerto reconocible.
    private static func separarPuerto(_ autoridad: String) -> (host: String?, puerto: String) {
        if autoridad.hasPrefix("[") { return (autoridad, "") }
        guard let dosPuntos = autoridad.lastIndex(of: ":") else { return (autoridad, "") }
        return (String(autoridad[..<dosPuntos]), String(autoridad[autoridad.index(after: dosPuntos)...]))
    }

    private static func extraerHost(_ url: String, exigirEsquema: Bool) -> String? {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let (esquema, resto) = separarEsquema(t)
        if exigirEsquema && esquema == nil { return nil }
        let fin = resto.firstIndex(where: delimitadores.contains) ?? resto.endIndex
        var autoridad = resto[..<fin]
        if let arroba = autoridad.lastIndex(of: "@") { autoridad = autoridad[autoridad.index(after: arroba)...] }
        var host: String
        if autoridad.hasPrefix("[") {
            host = String(autoridad.dropFirst().prefix { $0 != "]" })
        } else if let dosPuntos = autoridad.lastIndex(of: ":") {
            host = String(autoridad[..<dosPuntos])
        } else {
            host = String(autoridad)
        }
        host = (host.removingPercentEncoding ?? host).lowercased()
        return host.isEmpty ? nil : host
    }

    /// Espacios, controles, caracteres de formato (invisibles, de dirección/bidi), separadores,
    /// uso privado o sin asignar, y la barra invertida (que algunos navegadores tratan como "/").
    private static func esCaracterProhibido(_ u: Unicode.Scalar) -> Bool {
        if u == "\\" || u.properties.isWhitespace { return true }
        switch u.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator,
             .privateUse, .surrogate, .unassigned:
            return true
        default:
            return false
        }
    }

    /// Host con al menos un punto, etiquetas no vacías (≤63) y solo letras/dígitos/"-"/"_".
    /// Las letras no ASCII se aceptan (esPosibleHomografo las marca), el resto de símbolos no.
    private static func esHostValido(_ host: String) -> Bool {
        guard host.unicodeScalars.count <= 253, host.contains(".") else { return false }
        let etiquetas = host.split(separator: ".", omittingEmptySubsequences: false)
        return etiquetas.allSatisfy { etiqueta in
            !etiqueta.isEmpty && etiqueta.unicodeScalars.count <= 63 && etiqueta.unicodeScalars.allSatisfy(esCaracterDeHost)
        }
    }

    private static func esCaracterDeHost(_ u: Unicode.Scalar) -> Bool {
        if u.isASCII {
            return ("a"..."z").contains(u) || ("0"..."9").contains(u) || u == "-" || u == "_"
        }
        switch u.properties.generalCategory {
        case .lowercaseLetter, .uppercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// Ruta/consulta/fragmento en ASCII: lo que no lo es se codifica en %XX (UTF-8).
    private static func codificarNoASCII(_ s: String) -> String {
        var salida = ""
        for u in s.unicodeScalars {
            if u.isASCII {
                salida.unicodeScalars.append(u)
            } else {
                for byte in String(u).utf8 { salida += "%" + String(byte, radix: 16, uppercase: true) }
            }
        }
        return salida
    }
}
