//
//  Sanitizador.swift
//  PrototipoApp
//
//  Limpia lo que escribe la persona antes de validarlo y guardarlo: recorta, quita caracteres de
//  control e invisibles (los que se usan para disfrazar texto, como el cambio de dirección
//  "Trojan Source" o espacios de ancho cero en un alias) y corta a la longitud de la columna SQL.
//  Las contraseñas NO pasan por aquí: se respetan tal cual.
//
//  Se recorre una sola vez, sin expresiones regulares ni índices manuales: cualquier texto, por
//  enorme o raro que sea, termina en tiempo lineal y nunca provoca un crash.
//

import Foundation

nonisolated enum Sanitizador {
    /// Invisibles que no son de categoría "control" ni "formato" pero se usan para fingir un nombre vacío.
    private static let invisiblesExtra: Set<UInt32> = [0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x2800, 0x3164, 0xFFA0]

    private enum Clase { case descartar, espacio, salto, union, normal }

    private static func clasificar(_ e: Unicode.Scalar) -> Clase {
        switch e.value {
        case 0x0A, 0x0B, 0x0C, 0x85, 0x2028, 0x2029: return .salto
        case 0x09, 0x0D: return .espacio
        case 0x200C, 0x200D: return .union
        default: break
        }
        if invisiblesExtra.contains(e.value) { return .descartar }
        switch e.properties.generalCategory {
        case .control, .format, .privateUse, .surrogate: return .descartar
        case .spaceSeparator: return .espacio
        default: return .normal
        }
    }

    /// - Parameters:
    ///   - maximo: tope en escalares Unicode (lo que cuenta una columna SQL utf8mb4) y en caracteres;
    ///     nunca parte un carácter a la mitad. Un valor ≤ 0 devuelve "".
    ///   - multilinea: conserva saltos de línea (máximo dos seguidos); si no, los vuelve espacio.
    static func texto(_ s: String, maximo: Int, multilinea: Bool = false) -> String {
        guard maximo > 0 else { return "" }
        // Tras normalizar (NFC) el texto solo se acorta, así que basta con leer un múltiplo del máximo.
        let tope = maximo > (Int.max - 16) / 4 ? Int.max : maximo * 4 + 16
        let vista = s.unicodeScalars
        var salida = String.UnicodeScalarView()
        var cuenta = 0
        var espacioPendiente = false
        var saltosPendientes = 0
        var ultimoNoASCII = false   // el último escalar escrito no es ASCII y no hay espacio pendiente

        var i = vista.startIndex
        while i < vista.endIndex, cuenta < tope {
            let e = vista[i]
            i = vista.index(after: i)
            switch clasificar(e) {
            case .descartar:
                continue
            case .espacio:
                espacioPendiente = true
            case .salto:
                if multilinea { saltosPendientes += 1 } else { espacioPendiente = true }
            case .union:
                // Unir/no unir de ancho cero solo tiene sentido entre símbolos no ASCII (emoji, escrituras
                // que lo usan); entre letras latinas solo sirve para disfrazar una palabra.
                guard ultimoNoASCII && !espacioPendiente && saltosPendientes == 0,
                      i < vista.endIndex, !vista[i].isASCII, clasificar(vista[i]) == .normal else { continue }
                salida.append(e)
                cuenta += 1
                ultimoNoASCII = false
            case .normal:
                if cuenta > 0 {
                    if saltosPendientes > 0 {
                        salida.append("\n")
                        if saltosPendientes > 1 { salida.append("\n"); cuenta += 1 }
                        cuenta += 1
                    } else if espacioPendiente {
                        salida.append(" ")
                        cuenta += 1
                    }
                }
                espacioPendiente = false
                saltosPendientes = 0
                salida.append(e)
                cuenta += 1
                ultimoNoASCII = !e.isASCII
            }
        }

        // Se corta por caracteres completos (un emoji compuesto o una letra con acentos no se parten).
        var resultado = ""
        var escalares = 0
        var caracteres = 0
        for c in String(salida).precomposedStringWithCanonicalMapping {
            let n = c.unicodeScalars.count
            if caracteres + 1 > maximo || escalares + n > maximo { break }
            resultado.append(c)
            escalares += n
            caracteres += 1
        }
        // Si el corte quedó justo después de un espacio o salto, ese espacio sobra.
        return resultado.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Se pasa a minúsculas antes de cortar: algunas letras ("İ") ocupan más escalares en minúscula.
    static func correo(_ s: String) -> String { texto(s.lowercased(), maximo: 150) }
    static func alias(_ s: String) -> String { texto(s.lowercased(), maximo: 20) }
}

nonisolated extension ReporteBorrador {
    /// El borrador listo para validar y enviar (la interfaz y el servidor usan el mismo).
    var limpio: ReporteBorrador {
        var b = self
        b.ciudad = Sanitizador.texto(ciudad, maximo: 60)
        b.persona.nombre = Sanitizador.texto(persona.nombre, maximo: 100)
        b.persona.contacto = Sanitizador.texto(persona.contacto, maximo: 150)
        b.tipoOtro = Sanitizador.texto(tipoOtro, maximo: 50)
        b.titulo = Sanitizador.texto(titulo, maximo: 120)
        b.urlOTexto = Sanitizador.texto(urlOTexto, maximo: 2048)
        b.descripcion = Sanitizador.texto(descripcion, maximo: 2000, multilinea: true)
        return b
    }
}
