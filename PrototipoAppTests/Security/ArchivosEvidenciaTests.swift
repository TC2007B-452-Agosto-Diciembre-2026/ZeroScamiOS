//
//  ArchivosEvidenciaTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct ArchivosEvidenciaTests {
    let archivos = ArchivosEvidencia(carpeta: FileManager.default.temporaryDirectory.appending(path: "zs-ev-\(UUID().uuidString)"))

    @Test func temporalYConfirmado() throws {
        let adjunto = try archivos.guardarTemporal(Data([1, 2, 3]), tipo: "image/jpeg")
        #expect(adjunto.nombreArchivo.hasSuffix(".jpg"))
        #expect(try archivos.datos(de: adjunto) == Data([1, 2, 3]))
        let ruta = try archivos.confirmar(adjunto)
        #expect(try archivos.datos(ruta: ruta) == Data([1, 2, 3]))
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.datos(de: adjunto) }
    }

    @Test func rutasArbitrariasNoSeLeen() {
        for ruta in ["../zeroscam-demo.json", "/etc/passwd", "a/b.jpg", "foto.exe", ""] {
            #expect(throws: ErrorEvidencia.nombreInvalido) { try archivos.datos(ruta: ruta) }
        }
    }

    @Test func fueraDeRespaldos() throws {
        let ruta = try archivos.confirmar(try archivos.guardarTemporal(Data([9]), tipo: "application/pdf"))
        let url = archivos.carpeta.appending(path: ruta)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func limpiarTemporalesBorraLoNoEnviado() throws {
        let adjunto = try archivos.guardarTemporal(Data([1]), tipo: "image/jpeg")
        try archivos.limpiarTemporales()
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.datos(de: adjunto) }
    }

    // MARK: - Bordes

    @Test func funcionaConCarpetaConEspaciosComoApplicationSupport() throws {
        // "Application Support" lleva un espacio: la ruta no debe quedar con "%20".
        let conEspacio = ArchivosEvidencia(
            carpeta: FileManager.default.temporaryDirectory.appending(path: "zs ev \(UUID().uuidString)/Application Support"))
        defer { try? conEspacio.borrarTodo() }
        let adjunto = try conEspacio.guardarTemporal(Data([7, 7]), tipo: "image/jpeg")
        #expect(try conEspacio.datos(de: adjunto) == Data([7, 7]))
        let ruta = try conEspacio.confirmar(adjunto)
        #expect(try conEspacio.datos(ruta: ruta) == Data([7, 7]))
        try conEspacio.borrar(ruta: ruta)
        #expect(throws: ErrorEvidencia.noExiste) { try conEspacio.datos(ruta: ruta) }
        try conEspacio.limpiarTemporales()
        try conEspacio.borrarTodo()
        #expect(!FileManager.default.fileExists(atPath: conEspacio.carpeta.path(percentEncoded: false)))
    }

    @Test func rechazaTiposDesconocidos() {
        for tipo in ["text/html", "image/png", "image/jpeg; charset=x", "", "../jpg"] {
            #expect(throws: ErrorEvidencia.nombreInvalido) { try archivos.guardarTemporal(Data([1]), tipo: tipo) }
        }
    }

    @Test func rechazaVacioYDemasiadoGrande() {
        #expect(throws: ErrorEvidencia.noEsImagen) { try archivos.guardarTemporal(Data(), tipo: "image/jpeg") }
        #expect(throws: ErrorEvidencia.noEsPDF) { try archivos.guardarTemporal(Data(), tipo: "application/pdf") }
        #expect(throws: ErrorEvidencia.muyGrande) {
            try archivos.guardarTemporal(Data(count: ProcesadorEvidencia.bytesMaximosImagen + 1), tipo: "image/jpeg")
        }
        #expect(throws: ErrorEvidencia.muyGrande) {
            try archivos.guardarTemporal(Data(count: ProcesadorEvidencia.bytesMaximosPDF + 1), tipo: "application/pdf")
        }
    }

    @Test func unAdjuntoConNombreManipuladoNoTocaDisco() throws {
        // Un Adjunto viene de JSON (Codable): su nombre puede ser cualquier cosa.
        let malos = ["../x.jpg", "/etc/passwd", "a/b.jpg", "x.exe", "",
                     "00000000-0000-0000-0000-00000000000.jpg",           // un carácter de menos
                     "------------------------------------.jpg",         // 36 guiones: no es un UUID
                     "3f2504e0-4f89-11d3-9a0c-0305e82c3301.jpg",         // minúsculas: no es el nombre canónico
                     "3F2504E0-4F89-11D3-9A0C-0305E82C3301.jpg/"]
        for nombre in malos {
            let adjunto = Adjunto(id: UUID(), nombreArchivo: nombre, tipoArchivo: "image/jpeg", bytes: 1)
            #expect(throws: ErrorEvidencia.nombreInvalido) { try archivos.datos(de: adjunto) }
            #expect(throws: ErrorEvidencia.nombreInvalido) { try archivos.confirmar(adjunto) }
            #expect(throws: ErrorEvidencia.nombreInvalido) { try archivos.borrarTemporal(adjunto) }
            #expect(throws: ErrorEvidencia.nombreInvalido) { try archivos.borrar(ruta: nombre) }
        }
    }

    @Test func confirmarDosVecesOUnaInexistenteDaNoExiste() throws {
        let adjunto = try archivos.guardarTemporal(Data([1]), tipo: "application/pdf")
        _ = try archivos.confirmar(adjunto)
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.confirmar(adjunto) }
        let fantasma = Adjunto(id: UUID(), nombreArchivo: "\(UUID().uuidString).jpg", tipoArchivo: "image/jpeg", bytes: 1)
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.confirmar(fantasma) }
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.datos(ruta: "\(UUID().uuidString).pdf") }
    }

    @Test func borrarEsIdempotenteYQuitaElArchivo() throws {
        let adjunto = try archivos.guardarTemporal(Data([1]), tipo: "image/jpeg")
        try archivos.borrarTemporal(adjunto)
        try archivos.borrarTemporal(adjunto)   // ya no está: no es error
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.datos(de: adjunto) }
        let ruta = try archivos.confirmar(try archivos.guardarTemporal(Data([2]), tipo: "image/jpeg"))
        try archivos.borrar(ruta: ruta)
        try archivos.borrar(ruta: ruta)
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.datos(ruta: ruta) }
    }

    @Test func limpiarYBorrarTodoSinCarpetaNoFallan() throws {
        try archivos.limpiarTemporales()
        try archivos.borrarTodo()
        let ruta = try archivos.confirmar(try archivos.guardarTemporal(Data([3]), tipo: "image/jpeg"))
        try archivos.borrarTodo()
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.datos(ruta: ruta) }
    }

    @Test func unArchivoGiganteEnDiscoNoSeCargaEnMemoria() throws {
        // Algo ajeno a la app dejó un archivo con nombre válido pero enorme: se rechaza sin leerlo.
        let nombre = "\(UUID().uuidString).pdf"
        try FileManager.default.createDirectory(at: archivos.carpeta, withIntermediateDirectories: true)
        let url = archivos.carpeta.appending(path: nombre)
        #expect(FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil))
        let manejador = try FileHandle(forWritingTo: url)
        try manejador.truncate(atOffset: UInt64(ProcesadorEvidencia.bytesMaximosPDF) + 1)   // archivo "hueco": no ocupa disco
        try manejador.close()
        #expect(throws: ErrorEvidencia.muyGrande) { try archivos.datos(ruta: nombre) }
    }

    @Test func unDirectorioConNombreValidoNoSeLeeComoArchivo() throws {
        let nombre = "\(UUID().uuidString).jpg"
        try FileManager.default.createDirectory(at: archivos.carpeta.appending(path: nombre), withIntermediateDirectories: true)
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.datos(ruta: nombre) }
    }
}
