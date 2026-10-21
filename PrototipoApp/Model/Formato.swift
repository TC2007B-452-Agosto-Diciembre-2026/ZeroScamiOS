//
//  Formato.swift
//  PrototipoApp
//
//  Fechas y números como los mostraba el storyboard ("Hace 2 horas", "1.2k", "4,302").
//

import Foundation

nonisolated enum Formato {
    static let locale = Locale(identifier: "es_MX")

    /// "Hace 2 horas", "Ayer", "Hace 3 días". Primera letra en mayúscula, como el storyboard.
    static func relativo(_ fecha: Date, ahora: Date = Date()) -> String {
        let formateador = RelativeDateTimeFormatter()
        formateador.locale = locale
        formateador.unitsStyle = .full
        formateador.dateTimeStyle = .named
        let texto = formateador.localizedString(for: fecha, relativeTo: ahora)
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }

    /// 340 → "340"; 1200 → "1.2k".
    static func conteoCorto(_ n: Int) -> String {
        guard n >= 1_000 else { return "\(n)" }
        let miles = (Double(n) / 1_000).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return miles + "k"
    }

    /// 4302 → "4,302".
    static func miles(_ n: Int) -> String {
        n.formatted(.number.locale(locale))
    }

    /// 123 → "#000123". Lo que ve la persona como número de folio.
    static func folio(_ id: Int64) -> String {
        "#" + String(format: "%06lld", id)
    }

    /// "4 oct 2026" para la fecha del incidente.
    static func fechaCorta(_ fecha: Date) -> String {
        fecha.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }
}
