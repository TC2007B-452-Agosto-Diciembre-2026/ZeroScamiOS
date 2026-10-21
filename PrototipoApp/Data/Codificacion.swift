//
//  Codificacion.swift
//  PrototipoApp
//
//  JSON con fechas ISO-8601, igual para el archivo del modo Demo y para la API. Se aceptan
//  fechas con milisegundos porque así las manda `Date.toISOString()` en NestJS.
//

import Foundation

nonisolated enum Codificacion {
    private static let conMilisegundos = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let sinMilisegundos = Date.ISO8601FormatStyle()

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { fecha, encoder in
            var contenedor = encoder.singleValueContainer()
            try contenedor.encode(fecha.formatted(conMilisegundos))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let contenedor = try decoder.singleValueContainer()
            let texto = try contenedor.decode(String.self)
            if let fecha = try? conMilisegundos.parse(texto) { return fecha }
            if let fecha = try? sinMilisegundos.parse(texto) { return fecha }
            throw DecodingError.dataCorruptedError(in: contenedor, debugDescription: "Fecha no ISO-8601")
        }
        return decoder
    }
}
