//
//  AppConfig.swift
//  PrototipoApp
//
//  De dónde salen los datos (Demo o la API del equipo) y los interruptores para las pruebas de
//  interfaz. La fuente se elige con los ajustes ZS_FUENTE_DATOS y ZS_URL_BASE del target.
//

import Foundation

nonisolated struct AppConfig: Sendable, Equatable {
    nonisolated enum Fuente: Sendable, Equatable {
        case demo
        case remote(URL)
    }

    let fuente: Fuente
    let esUITest: Bool
    let reiniciarDemo: Bool
    let evidenciaDePrueba: Bool

    static let porDefecto = AppConfig(fuente: .demo, esUITest: false, reiniciarDemo: false, evidenciaDePrueba: false)

    static func actual(info: [String: Any] = Bundle.main.infoDictionary ?? [:],
                       argumentos: [String] = ProcessInfo.processInfo.arguments) -> AppConfig {
        let esUITest = argumentos.contains("-uiTesting")
        var fuente = Fuente.demo
        if !esUITest, (info["ZSFuenteDatos"] as? String) == "remote",
           let texto = info["ZSURLBase"] as? String, let url = URL(string: texto), esURLPermitida(url) {
            fuente = .remote(url)
        }
        #if DEBUG
        let reiniciar = argumentos.contains("-reiniciarDemo")
        #else
        let reiniciar = false
        #endif
        return AppConfig(fuente: fuente, esUITest: esUITest, reiniciarDemo: reiniciar,
                         evidenciaDePrueba: esUITest && argumentos.contains("-evidenciaDePrueba"))
    }

    /// HTTPS siempre. HTTP solo contra la propia Mac o una dirección IPv4 privada (la red local del
    /// equipo, donde vive el backend): nunca contra un nombre de dominio ni una IP pública. Exige un
    /// servidor y rechaza usuario/contraseña en la URL (`http://localhost@otro.com` apunta a otro.com).
    static func esURLPermitida(_ url: URL) -> Bool {
        guard let esquema = url.scheme?.lowercased(),
              let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty,
              url.user(percentEncoded: false) == nil, url.password(percentEncoded: false) == nil
        else { return false }
        if esquema == "https" { return true }
        return esquema == "http" && (["localhost", "127.0.0.1", "::1"].contains(host) || esIPv4Privada(host))
    }

    /// 10.0.0.0/8, 172.16.0.0/12 y 192.168.0.0/16, escritas como cuatro números decimales. Un nombre
    /// que solo empieza igual ("10.0.0.1.evil.test") no pasa: deben ser exactamente cuatro partes.
    static func esIPv4Privada(_ host: String) -> Bool {
        let partes = host.split(separator: ".", omittingEmptySubsequences: false)
        guard partes.count == 4 else { return false }
        let octetos = partes.compactMap { parte -> Int? in
            guard (1...3).contains(parte.utf8.count), parte.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
                  let valor = Int(parte), valor <= 255 else { return nil }
            return valor
        }
        guard octetos.count == 4 else { return false }
        return octetos[0] == 10 || (octetos[0] == 172 && (16...31).contains(octetos[1])) || (octetos[0] == 192 && octetos[1] == 168)
    }
}
