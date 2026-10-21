//
//  ProcesadorEvidencia.swift
//  PrototipoApp
//
//  Las fotos traen metadatos: ubicación GPS, fecha y modelo del teléfono. Antes de guardar una
//  evidencia se vuelve a dibujar la imagen (máx. 1600 px) y se codifica a JPEG sin copiar ningún
//  metadato. Los PDF se aceptan solo si empiezan con la firma %PDF- y pesan hasta 10 MB.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ErrorEvidencia: Error, Equatable, Sendable {
    case noEsImagen, muyGrande, noEsPDF, nombreInvalido, noExiste
}

nonisolated enum ProcesadorEvidencia {
    static let ladoMaximo = 1_600
    static let bytesMaximosImagen = 5 * 1_024 * 1_024
    static let bytesMaximosPDF = 10 * 1_024 * 1_024
    /// Lo que se acepta leer antes de procesar (una foto de 48 MP en HEIC cabe).
    static let bytesMaximosEntrada = 40 * 1_024 * 1_024
    /// Un archivo pequeño puede declarar miles de millones de píxeles ("bomba de descompresión") y
    /// agotar la memoria al decodificarlo. 100 MP deja pasar cualquier cámara de teléfono (48 MP).
    static let pixelesMaximos = 100_000_000

    static func limpiarImagen(_ datos: Data, ladoMaximo: Int = ladoMaximo) throws -> Data {
        guard datos.count <= bytesMaximosEntrada else { throw ErrorEvidencia.muyGrande }
        guard let fuente = CGImageSourceCreateWithData(datos as CFData, nil), CGImageSourceGetCount(fuente) > 0,
              let propiedades = CGImageSourceCopyPropertiesAtIndex(fuente, 0, nil) as? [CFString: Any],
              let ancho = propiedades[kCGImagePropertyPixelWidth] as? Int,
              let alto = propiedades[kCGImagePropertyPixelHeight] as? Int,
              ancho > 0, alto > 0
        else { throw ErrorEvidencia.noEsImagen }
        // Se miden las dimensiones declaradas ANTES de decodificar nada.
        let (pixeles, desborda) = ancho.multipliedReportingOverflow(by: alto)
        guard !desborda, pixeles <= pixelesMaximos else { throw ErrorEvidencia.muyGrande }
        // Entre 1 y 1600 px, y nunca más que la imagen original (no se agranda).
        let lado = min(max(ladoMaximo, 1), Self.ladoMaximo, max(ancho, alto))
        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respeta la orientación antes de tirar el EXIF
            kCGImageSourceThumbnailMaxPixelSize: lado,
        ]
        guard let imagen = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary) else {
            throw ErrorEvidencia.noEsImagen
        }
        let salida = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(salida, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ErrorEvidencia.noEsImagen
        }
        // Solo la calidad: ningún diccionario de metadatos del original.
        CGImageDestinationAddImage(destino, imagen, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { throw ErrorEvidencia.noEsImagen }
        let resultado = salida as Data
        guard resultado.count <= bytesMaximosImagen else { throw ErrorEvidencia.muyGrande }
        return resultado
    }

    static func validarPDF(_ datos: Data) throws {
        guard datos.starts(with: Data("%PDF-".utf8)) else { throw ErrorEvidencia.noEsPDF }
        guard datos.count <= bytesMaximosPDF else { throw ErrorEvidencia.muyGrande }
    }
}
