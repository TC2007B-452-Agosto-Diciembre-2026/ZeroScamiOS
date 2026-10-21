//
//  SecretStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Security
import Synchronization
import Testing
@testable import PrototipoApp

struct SecretStoreTests {
    @Test func keychainGuardaLeeYBorra() throws {
        let keychain = KeychainStore(servicio: "zs.pruebas.\(UUID().uuidString)")
        #expect(try keychain.leer(.accessToken) == nil)
        try keychain.guardar("uno", para: .accessToken)
        try keychain.guardar("dos", para: .accessToken)   // reemplaza, no duplica
        #expect(try keychain.leer(.accessToken) == "dos")
        try keychain.borrarTodo()
        #expect(try keychain.leer(.accessToken) == nil)
        try keychain.borrar(.refreshToken)                  // borrar algo que no existe no falla
    }

    @Test func memoriaSeComportaIgual() throws {
        let memoria = MemorySecretStore()
        try memoria.guardar("abc", para: .refreshToken)
        #expect(try memoria.leer(.refreshToken) == "abc")
        try memoria.borrarTodo()
        #expect(try memoria.leer(.refreshToken) == nil)
    }

    @Test func limpiaTokensEnPrimeraEjecucion() throws {
        let defaults = try #require(UserDefaults(suiteName: "zs.pruebas.\(UUID().uuidString)"))
        let secretos = MemorySecretStore()
        try secretos.guardar("de-una-instalacion-anterior", para: .accessToken)
        PrimeraEjecucion.limpiarSiHaceFalta(defaults: defaults, secretos: secretos)
        #expect(try secretos.leer(.accessToken) == nil)
        try secretos.guardar("vigente", para: .accessToken)
        PrimeraEjecucion.limpiarSiHaceFalta(defaults: defaults, secretos: secretos)
        #expect(try secretos.leer(.accessToken) == "vigente")
    }

    // Un valor que no es UTF-8 válido (corrupto o escrito por otro) debe dar error, nunca crash.
    @Test func keychainConValorCorruptoLanzaErrorSinCrash() throws {
        let servicio = "zs.pruebas.\(UUID().uuidString)"
        let keychain = KeychainStore(servicio: servicio)
        defer { try? keychain.borrarTodo() }
        let invalido = Data([0xFF, 0xFE, 0xC0])
        let alta: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: servicio,
                                   kSecAttrAccount as String: ClaveSecreta.accessToken.rawValue,
                                   kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                   kSecValueData as String: invalido]
        #expect(SecItemAdd(alta as CFDictionary, nil) == errSecSuccess)
        #expect(throws: ErrorKeychain.self) { try keychain.leer(.accessToken) }
    }

    @Test func serviciosDistintosNoSeMezclan() throws {
        let a = KeychainStore(servicio: "zs.pruebas.\(UUID().uuidString)")
        let b = KeychainStore(servicio: "zs.pruebas.\(UUID().uuidString)")
        defer { try? a.borrarTodo(); try? b.borrarTodo() }
        try a.guardar("solo-de-a", para: .refreshToken)
        #expect(try b.leer(.refreshToken) == nil)
        #expect(try a.leer(.refreshToken) == "solo-de-a")
    }

    @Test func tokensConUnicodeYVacioSobrevivenAlIdaYVuelta() throws {
        let keychain = KeychainStore(servicio: "zs.pruebas.\(UUID().uuidString)")
        defer { try? keychain.borrarTodo() }
        try keychain.guardar("tókén-ñ-🔐", para: .accessToken)
        #expect(try keychain.leer(.accessToken) == "tókén-ñ-🔐")
        try keychain.guardar("", para: .refreshToken)
        #expect(try keychain.leer(.refreshToken) == "")
    }

    // Si el borrado falla, la marca no se escribe: el siguiente arranque reintenta la limpieza.
    @Test func siElBorradoFallaNoMarcaYReintentaDespues() throws {
        let defaults = try #require(UserDefaults(suiteName: "zs.pruebas.\(UUID().uuidString)"))
        let secretos = SecretStoreQueFalla()
        try secretos.guardar("huerfano", para: .accessToken)

        PrimeraEjecucion.limpiarSiHaceFalta(defaults: defaults, secretos: secretos)
        #expect(!defaults.bool(forKey: "zs.instalada"))
        #expect(try secretos.leer(.accessToken) == "huerfano")

        secretos.falla.withLock { $0 = false }
        PrimeraEjecucion.limpiarSiHaceFalta(defaults: defaults, secretos: secretos)
        #expect(try secretos.leer(.accessToken) == nil)
        #expect(defaults.bool(forKey: "zs.instalada"))
    }
}

/// Almacén falso cuyo `borrar` lanza mientras `falla` sea verdadero.
nonisolated final class SecretStoreQueFalla: SecretStore {
    let falla = Mutex(true)
    private let base = MemorySecretStore()

    func leer(_ clave: ClaveSecreta) throws -> String? { try base.leer(clave) }
    func guardar(_ valor: String, para clave: ClaveSecreta) throws { try base.guardar(valor, para: clave) }
    func borrar(_ clave: ClaveSecreta) throws {
        if falla.withLock({ $0 }) { throw ErrorKeychain(estado: errSecInteractionNotAllowed) }
        try base.borrar(clave)
    }
}
