//
//  Aleatorio.swift
//  PrototipoApp
//
//  Bytes, tokens y códigos con el generador criptográfico del sistema (nunca `random()`).
//

import Foundation
import Security

nonisolated enum Aleatorio {
    static func bytes(_ cantidad: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: cantidad)
        let estado = SecRandomCopyBytes(kSecRandomDefault, cantidad, &bytes)
        // Si el generador del sistema falla no hay forma segura de seguir (única excepción documentada).
        precondition(estado == errSecSuccess, "SecRandomCopyBytes falló")
        return Data(bytes)
    }

    /// 32 bytes en base64url (sin `+`, `/` ni `=`): token de sesión o id de desafío.
    static func token() -> String {
        bytes(32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Código de 6 dígitos. `Int.random` usa el generador seguro del sistema.
    static func codigo() -> String {
        String(format: "%06ld", Int.random(in: 0...999_999))
    }
}
