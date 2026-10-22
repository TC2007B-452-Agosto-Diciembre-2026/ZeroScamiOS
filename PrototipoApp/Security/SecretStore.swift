//
//  SecretStore.swift
//  PrototipoApp
//
//  Dónde viven los tokens de sesión (y el perfil con el que se entra sin conexión). En la app, el
//  Keychain: cifrado por iOS, disponible solo con el teléfono desbloqueado y sin viajar en respaldos
//  a otro dispositivo. En pruebas, memoria.
//

import Foundation
import Security

nonisolated enum ClaveSecreta: String, Sendable, CaseIterable {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    /// El último perfil que confirmó el servidor (JSON de `Usuario`). Con él se entra sin conexión;
    /// se borra junto con los tokens.
    case usuario = "usuario"
}

nonisolated protocol SecretStore: Sendable {
    func leer(_ clave: ClaveSecreta) throws -> String?
    func guardar(_ valor: String, para clave: ClaveSecreta) throws
    func borrar(_ clave: ClaveSecreta) throws
}

nonisolated extension SecretStore {
    func borrarTodo() throws {
        for clave in ClaveSecreta.allCases { try borrar(clave) }
    }
}

nonisolated struct ErrorKeychain: Error, Equatable {
    let estado: OSStatus
}

nonisolated struct KeychainStore: SecretStore {
    let servicio: String

    private func consulta(_ clave: ClaveSecreta) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servicio,
         kSecAttrAccount as String: clave.rawValue]
    }

    func leer(_ clave: ClaveSecreta) throws -> String? {
        var q = consulta(clave)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: CFTypeRef?
        let estado = SecItemCopyMatching(q as CFDictionary, &resultado)
        if estado == errSecItemNotFound { return nil }
        guard estado == errSecSuccess, let datos = resultado as? Data else { throw ErrorKeychain(estado: estado) }
        // UTF-8 estricto: un valor corrupto es un error recuperable, no un token con caracteres de reemplazo.
        guard let texto = String(data: datos, encoding: .utf8) else { throw ErrorKeychain(estado: errSecDecode) }
        return texto
    }

    func guardar(_ valor: String, para clave: ClaveSecreta) throws {
        try borrar(clave)
        var q = consulta(clave)
        q[kSecValueData as String] = Data(valor.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let estado = SecItemAdd(q as CFDictionary, nil)
        guard estado == errSecSuccess else { throw ErrorKeychain(estado: estado) }
    }

    func borrar(_ clave: ClaveSecreta) throws {
        let estado = SecItemDelete(consulta(clave) as CFDictionary)
        guard estado == errSecSuccess || estado == errSecItemNotFound else { throw ErrorKeychain(estado: estado) }
    }
}

nonisolated final class MemorySecretStore: SecretStore {
    private let valores = Mutex<[ClaveSecreta: String]>([:])

    func leer(_ clave: ClaveSecreta) throws -> String? { valores.withLock { $0[clave] } }
    func guardar(_ valor: String, para clave: ClaveSecreta) throws { valores.withLock { $0[clave] = valor } }
    func borrar(_ clave: ClaveSecreta) throws { valores.withLock { $0[clave] = nil } }
}

nonisolated enum PrimeraEjecucion {
    /// iOS conserva el Keychain al desinstalar la app, pero no UserDefaults. Si falta la marca,
    /// los tokens que haya son de una instalación anterior y se borran.
    static func limpiarSiHaceFalta(defaults: UserDefaults, secretos: any SecretStore) {
        let marca = "zs.instalada"
        guard !defaults.bool(forKey: marca) else { return }
        // Si el borrado falla no se marca: el siguiente arranque reintenta y no quedan tokens huérfanos.
        do { try secretos.borrarTodo() } catch { return }
        defaults.set(true, forKey: marca)
    }
}
