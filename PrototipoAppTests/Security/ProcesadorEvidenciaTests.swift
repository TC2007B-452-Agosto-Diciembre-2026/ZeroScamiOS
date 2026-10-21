//
//  ProcesadorEvidenciaTests.swift
//  PrototipoAppTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import zlib
@testable import PrototipoApp

struct ProcesadorEvidenciaTests {
    /// JPEG de 2000×1000 con ubicación GPS, fecha y modelo de cámara en sus metadatos.
    static func jpegConGPS(ancho: Int = 2_000, alto: Int = 1_000, orientacion: Int? = nil) throws -> Data {
        let contexto = try #require(CGContext(data: nil, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        contexto.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        contexto.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))
        let imagen = try #require(contexto.makeImage())
        let salida = NSMutableData()
        let destino = try #require(CGImageDestinationCreateWithData(salida, UTType.jpeg.identifier as CFString, 1, nil))
        var metadatos: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 19.43, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 99.13, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:01 10:00:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone 17"],
        ]
        if let orientacion { metadatos[kCGImagePropertyOrientation] = orientacion }
        CGImageDestinationAddImage(destino, imagen, metadatos as CFDictionary)
        #expect(CGImageDestinationFinalize(destino))
        return salida as Data
    }

    /// PNG con las dimensiones dadas en la cabecera pero casi sin datos de píxeles: lo que mandaría
    /// alguien para agotar la memoria con una "bomba de descompresión".
    static func pngConDimensiones(ancho: UInt32, alto: UInt32) -> Data {
        func enBigEndian(_ n: UInt32) -> [UInt8] { [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] }
        func bloque(_ tipo: String, _ contenido: [UInt8]) -> [UInt8] {
            let cuerpo = Array(tipo.utf8) + contenido
            let crc = UInt32(cuerpo.withUnsafeBufferPointer { crc32(0, $0.baseAddress, uInt($0.count)) })
            return enBigEndian(UInt32(contenido.count)) + cuerpo + enBigEndian(crc)
        }
        let cabecera = enBigEndian(ancho) + enBigEndian(alto) + [8, 0, 0, 0, 0]   // 8 bits, escala de grises
        let zlibVacio: [UInt8] = [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(bloque("IHDR", cabecera))
            + Data(bloque("IDAT", zlibVacio)) + Data(bloque("IEND", []))
    }

    private static func propiedades(_ datos: Data) throws -> [CFString: Any] {
        let fuente = try #require(CGImageSourceCreateWithData(datos as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(fuente, 0, nil) as? [CFString: Any])
    }

    @Test func quitaUbicacionYDatosDeCamara() throws {
        let original = try Self.jpegConGPS()
        #expect(try Self.propiedades(original)[kCGImagePropertyGPSDictionary] != nil)   // la prueba sí tiene GPS
        let limpia = try ProcesadorEvidencia.limpiarImagen(original)
        let p = try Self.propiedades(limpia)
        #expect(p[kCGImagePropertyGPSDictionary] == nil)
        #expect((p[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect((p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
    }

    @Test func reduceAlLadoMaximo() throws {
        let p = try Self.propiedades(try ProcesadorEvidencia.limpiarImagen(try Self.jpegConGPS()))
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 1_600)
    }

    @Test func rechazaLoQueNoEsImagen() {
        #expect(throws: ErrorEvidencia.noEsImagen) { try ProcesadorEvidencia.limpiarImagen(Data("hola".utf8)) }
    }

    @Test func pdfPorFirmaYTamano() throws {
        try ProcesadorEvidencia.validarPDF(Data("%PDF-1.7\n…".utf8))
        #expect(throws: ErrorEvidencia.noEsPDF) { try ProcesadorEvidencia.validarPDF(Data("<html>".utf8)) }
        #expect(throws: ErrorEvidencia.muyGrande) {
            try ProcesadorEvidencia.validarPDF(Data("%PDF-".utf8) + Data(count: 10 * 1_024 * 1_024))
        }
    }

    // MARK: - Bordes: datos externos malformados

    @Test func archivoVacioNoEsImagenNiPDF() {
        #expect(throws: ErrorEvidencia.noEsImagen) { try ProcesadorEvidencia.limpiarImagen(Data()) }
        #expect(throws: ErrorEvidencia.noEsPDF) { try ProcesadorEvidencia.validarPDF(Data()) }
    }

    @Test func imagenCorruptaFallaConErrorControlado() throws {
        // Cabecera JPEG válida seguida de basura, y una imagen real cortada a la mitad.
        let basura = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data((0..<200).map { UInt8(($0 &* 37) & 0xFF) })
        #expect(throws: ErrorEvidencia.noEsImagen) { try ProcesadorEvidencia.limpiarImagen(basura) }
        let completa = try Self.jpegConGPS(ancho: 400, alto: 300)
        let cortada = completa.prefix(60)   // ni siquiera llega a los datos de la imagen
        #expect(throws: ErrorEvidencia.noEsImagen) { try ProcesadorEvidencia.limpiarImagen(Data(cortada)) }
        // PDF con otra firma o un PNG sin cuerpo tampoco pasan por imagen.
        #expect(throws: ErrorEvidencia.self) { try ProcesadorEvidencia.limpiarImagen(Data("%PDF-1.7".utf8)) }
    }

    @Test func entradaGiganteSeRechazaSinProcesar() {
        let enorme = Data(count: ProcesadorEvidencia.bytesMaximosEntrada + 1)
        #expect(throws: ErrorEvidencia.muyGrande) { try ProcesadorEvidencia.limpiarImagen(enorme) }
    }

    @Test func imagenConDemasiadosPixelesSeRechazaAntesDeDecodificar() throws {
        // PNG en gris de 10 001 × 10 001 px (100,02 MP): pesa unos KB comprimido, pero decodificarlo
        // costaría cientos de MB de memoria. Se rechaza midiendo las dimensiones declaradas.
        let contexto = try #require(CGContext(data: nil, width: 10_001, height: 10_001, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let imagen = try #require(contexto.makeImage())
        let salida = NSMutableData()
        let destino = try #require(CGImageDestinationCreateWithData(salida, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destino, imagen, nil)
        #expect(CGImageDestinationFinalize(destino))
        let bomba = salida as Data
        #expect(bomba.count < ProcesadorEvidencia.bytesMaximosEntrada)   // pasa el filtro de tamaño en bytes
        #expect(throws: ErrorEvidencia.muyGrande) { try ProcesadorEvidencia.limpiarImagen(bomba) }
    }

    @Test func dimensionesDeclaradasImposiblesFallanConErrorControlado() {
        // ImageIO ni siquiera abre estas cabeceras: debe salir un error, nunca un crash.
        for (ancho, alto) in [(60_000, 60_000), (UInt32.max, UInt32.max), (0, 0), (1, 0)] as [(UInt32, UInt32)] {
            #expect(throws: ErrorEvidencia.self) { try ProcesadorEvidencia.limpiarImagen(Self.pngConDimensiones(ancho: ancho, alto: alto)) }
        }
    }

    @Test func ladoMaximoRaroNoProvocaCrash() throws {
        let original = try Self.jpegConGPS(ancho: 400, alto: 300)
        for lado in [0, -5, Int.min, Int.max] {
            // Cualquier valor termina en imagen válida o en error controlado; lo importante es no caer.
            _ = try? ProcesadorEvidencia.limpiarImagen(original, ladoMaximo: lado)
        }
        let p = try Self.propiedades(try ProcesadorEvidencia.limpiarImagen(original, ladoMaximo: 0))
        #expect((p[kCGImagePropertyPixelWidth] as? Int ?? 0) >= 1)
    }

    @Test func imagenPequenaNoSeAgranda() throws {
        let p = try Self.propiedades(try ProcesadorEvidencia.limpiarImagen(try Self.jpegConGPS(ancho: 400, alto: 300)))
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 400)
        #expect(p[kCGImagePropertyPixelHeight] as? Int == 300)
    }

    @Test func laOrientacionSeAplicaALosPixelesYNoQuedaEnMetadatos() throws {
        // Orientación 6 = girada 90°: una foto 2000×1000 se ve de 1000×2000 y, a 1600 px, de 800×1600.
        let limpia = try ProcesadorEvidencia.limpiarImagen(try Self.jpegConGPS(orientacion: 6))
        let p = try Self.propiedades(limpia)
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 800)
        #expect(p[kCGImagePropertyPixelHeight] as? Int == 1_600)
        #expect((p[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test func salidaEsJPEG() throws {
        let limpia = try ProcesadorEvidencia.limpiarImagen(try Self.jpegConGPS())
        #expect(Array(limpia.prefix(3)) == [0xFF, 0xD8, 0xFF])
    }
}
