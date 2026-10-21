//
//  AppError.swift
//  PrototipoApp
//
//  Errores que la persona puede ver. Mensajes en español, cortos, y sin revelar detalles útiles
//  para un atacante (por ejemplo, no se dice si falló el correo o la contraseña).
//

import Foundation

nonisolated enum AppError: Error, Equatable, Sendable {
    case credencialesInvalidas
    case cuentaBloqueada(hasta: Date)
    case cuentaSuspendida
    case sesionExpirada
    case codigoInvalido
    case sinPermiso
    case noEncontrado
    case conflicto(String)
    case validacion([String])
    case limiteExcedido(String)
    case sinConexion
    case servidor(String)

    func mensaje(ahora: Date = Date()) -> String {
        switch self {
        case .credencialesInvalidas:
            "Correo o contraseña incorrectos."
        case .cuentaBloqueada(let hasta):
            "Demasiados intentos. Intenta de nuevo en \(Self.minutosRestantes(hasta: hasta, ahora: ahora)) min."
        case .cuentaSuspendida:
            "Tu cuenta está suspendida. Escríbenos para revisarla."
        case .sesionExpirada:
            "Tu sesión expiró. Inicia sesión de nuevo."
        case .codigoInvalido:
            "El código no es válido o ya expiró."
        case .sinPermiso:
            "No tienes permiso para hacer esto."
        case .noEncontrado:
            "Este contenido ya no está disponible."
        case .conflicto(let texto), .limiteExcedido(let texto), .servidor(let texto):
            texto
        case .validacion(let errores):
            errores.joined(separator: "\n")
        case .sinConexion:
            "No se pudo conectar con el servidor. Revisa tu conexión."
        }
    }

    /// Minutos que faltan, redondeados hacia arriba y nunca menos de 1. Una fecha corrupta (NaN,
    /// infinita o gigantesca) no puede tronar la conversión a entero: se acota a un año.
    private static func minutosRestantes(hasta: Date, ahora: Date) -> Int {
        let minutos = (hasta.timeIntervalSince(ahora) / 60).rounded(.up)
        guard minutos.isFinite else { return minutos == .infinity ? tope : 1 }
        guard minutos >= 1 else { return 1 }
        guard minutos < Double(tope), let entero = Int(exactly: minutos) else { return tope }
        return entero
    }

    private static let tope = 525_600
}

nonisolated extension Error {
    /// Mensaje listo para pantalla, venga de donde venga el error.
    var mensajeUsuario: String {
        (self as? AppError)?.mensaje() ?? "Ocurrió un error inesperado."
    }
}
