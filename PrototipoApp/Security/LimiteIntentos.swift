//
//  LimiteIntentos.swift
//  PrototipoApp
//
//  Contra adivinar contraseñas: 5 fallos seguidos bloquean ese correo 1 minuto, y cada fallo
//  después del bloqueo duplica el tiempo hasta 15 minutos. Se cuenta por correo exista o no la
//  cuenta, para no revelar cuáles existen. Un acierto lo reinicia (lo hace el servidor).
//

import Foundation

nonisolated struct RegistroIntentos: Codable, Sendable, Hashable {
    var fallidos = 0
    var bloqueadoHasta: Date?
}

nonisolated enum LimiteIntentos {
    static let intentosPermitidos = 5
    static let bloqueoBase: TimeInterval = 60
    static let bloqueoMaximo: TimeInterval = 15 * 60

    /// Hasta cuándo sigue bloqueado el correo, o nil si ya puede intentar. El resultado nunca pasa
    /// de `ahora + bloqueoMaximo`: si el reloj retrocede o el registro viene corrupto o manipulado
    /// (fecha lejana), no se deja a nadie bloqueado más del máximo.
    static func bloqueadoHasta(_ r: RegistroIntentos, ahora: Date) -> Date? {
        guard let hasta = r.bloqueadoHasta, hasta > ahora else { return nil }
        return min(hasta, ahora.addingTimeInterval(bloqueoMaximo))
    }

    static func registrarFallo(_ r: inout RegistroIntentos, ahora: Date) {
        // Un contador negativo (dato corrupto) se trata como 0, y al llegar al tope ya no sube:
        // `+= 1` sobre Int.max detendría la app.
        let previos = max(0, r.fallidos)
        r.fallidos = previos == Int.max ? previos : previos + 1
        guard r.fallidos >= intentosPermitidos else { return }
        // Más de 20 duplicaciones ya superan el máximo; limitar el exponente evita números enormes.
        let exceso = min(r.fallidos - intentosPermitidos, 20)
        r.bloqueadoHasta = ahora.addingTimeInterval(min(bloqueoBase * pow(2, Double(exceso)), bloqueoMaximo))
    }
}
