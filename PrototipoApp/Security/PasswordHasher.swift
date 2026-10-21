//
//  PasswordHasher.swift
//  PrototipoApp
//
//  Contraseñas con PBKDF2-HMAC-SHA256 (CommonCrypto) y sal aleatoria. Se guarda
//  "pbkdf2_sha256$<iteraciones>$<sal>$<hash>" (cabe en Usuario.contrasena_hash VARCHAR(255)).
//  Las iteraciones viajan dentro del texto: se pueden subir después sin romper los hashes viejos.
//

import CommonCrypto
import Foundation

nonisolated struct PasswordHasher: Sendable {
    /// Recomendación de OWASP para PBKDF2-HMAC-SHA256.
    static let iteracionesRecomendadas = 600_000

    /// Límites al verificar: el texto guardado es dato externo y no debe poder colgar ni abortar la app.
    static let iteracionesMinimas = 1_000
    static let iteracionesMaximas = 10_000_000

    let iteraciones: Int

    init(iteraciones: Int = PasswordHasher.iteracionesRecomendadas) {
        self.iteraciones = iteraciones
    }

    func hash(_ contrasena: String) -> String {
        let sal = Aleatorio.bytes(16)
        let derivada = Self.pbkdf2(contrasena, sal: sal, iteraciones: iteraciones)
        return "pbkdf2_sha256$\(iteraciones)$\(sal.base64EncodedString())$\(derivada.base64EncodedString())"
    }

    func verificar(_ contrasena: String, contra guardado: String) -> Bool {
        let partes = guardado.split(separator: "$", omittingEmptySubsequences: false)
        guard partes.count == 4, partes[0] == "pbkdf2_sha256",
              let n = Int(partes[1]), n >= Self.iteracionesMinimas, n <= Self.iteracionesMaximas,
              let sal = Data(base64Encoded: String(partes[2])),
              let esperado = Data(base64Encoded: String(partes[3])), !esperado.isEmpty
        else { return false }
        return Self.igualesEnTiempoConstante(Self.pbkdf2(contrasena, sal: sal, iteraciones: n), esperado)
    }

    static func pbkdf2(_ contrasena: String, sal: Data, iteraciones: Int, longitud: Int = 32) -> Data {
        // Misma contraseña escrita con "ñ" compuesta o descompuesta debe dar el mismo hash.
        let normalizada = contrasena.precomposedStringWithCanonicalMapping
        // `UInt32(exactly:)` evita abortar con iteraciones fuera de rango: falla cerrado.
        guard let rondas = UInt32(exactly: iteraciones), rondas > 0 else { return Data() }
        // Bytes UTF-8 con su longitud real (con `strlen` un NUL dentro de la contraseña la truncaría).
        let bytesContrasena = Array(normalizada.utf8)
        var derivada = [UInt8](repeating: 0, count: longitud)
        let estado = bytesContrasena.withUnsafeBytes { texto in
            sal.withUnsafeBytes { bytesSal in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     texto.bindMemory(to: CChar.self).baseAddress, bytesContrasena.count,
                                     bytesSal.bindMemory(to: UInt8.self).baseAddress, sal.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rondas,
                                     &derivada, longitud)
            }
        }
        guard estado == kCCSuccess else { return Data() }
        return Data(derivada)
    }

    /// Recorre todos los bytes aunque haya diferencia al principio: no filtra información por el tiempo.
    static func igualesEnTiempoConstante(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var diferencia: UInt8 = 0
        for (x, y) in zip(a, b) { diferencia |= x ^ y }
        return diferencia == 0
    }
}
