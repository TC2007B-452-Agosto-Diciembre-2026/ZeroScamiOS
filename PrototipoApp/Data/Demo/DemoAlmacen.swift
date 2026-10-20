//
//  DemoAlmacen.swift
//  PrototipoApp
//
//  Lee y escribe la base del modo Demo en Application Support. El archivo queda cifrado por iOS
//  mientras el teléfono está bloqueado (`.completeFileProtection`) y fuera de los respaldos.
//  El archivo es un dato externo: vacío, gigante, de otra versión o dañado se aparta como
//  `.corrupto` y se devuelve nil (la app vuelve a sembrar); nunca debe detener la app. Un fallo
//  de lectura (E/S) devuelve nil pero NO aparta el archivo.
//

import Foundation

nonisolated struct DemoAlmacen: Sendable {
    /// Las evidencias viven en archivos aparte; un JSON mayor a esto no es nuestro y no se lee entero.
    static let tamanoMaximo = 20 * 1024 * 1024

    let carpeta: URL
    /// Cómo se leen los bytes del archivo. Se puede cambiar en pruebas para simular un fallo de E/S
    /// (por ejemplo, el teléfono bloqueado con `.completeFileProtection`).
    var leer: @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }

    var archivo: URL { carpeta.appending(path: "zeroscam-demo.json") }

    private var apartado: URL { carpeta.appending(path: "zeroscam-demo.corrupto.json") }

    /// `nil` si todavía no hay base, si no se pudo leer (el archivo se conserva intacto) o si su
    /// contenido era inválido (se aparta como `.corrupto` y se vuelve a sembrar).
    func cargar() -> DemoDatabase? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: archivo.path(percentEncoded: false)) else { return nil }
        // Fallos de lectura o de E/S: son transitorios (p. ej. teléfono bloqueado). Un archivo bueno
        // nunca se aparta por esto, solo se devuelve nil y se reintenta después.
        guard let valores = try? archivo.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              let esRegular = valores.isRegularFile, let tamano = valores.fileSize else { return nil }
        // Desde aquí el problema es del contenido: se aparta. Se mide antes de leer para no cargar a
        // memoria un archivo enorme.
        guard esRegular, tamano <= Self.tamanoMaximo else {
            apartarArchivo()
            return nil
        }
        guard let datos = try? leer(archivo) else { return nil }
        guard let db = try? Codificacion.decoder().decode(DemoDatabase.self, from: datos),
              let valida = db.validadaOReconciliada() else {
            apartarArchivo()
            return nil
        }
        return valida
    }

    func guardar(_ db: DemoDatabase) throws {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let datos = try Codificacion.encoder().encode(db)
        // Lo que no se podría volver a cargar no se escribe; el archivo bueno queda intacto.
        guard datos.count <= Self.tamanoMaximo else {
            throw AppError.limiteExcedido("Los datos locales son demasiado grandes para guardarse.")
        }
        try datos.write(to: archivo, options: [.atomic, .completeFileProtection])
        var url = archivo
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        try url.setResourceValues(valores)
    }

    func borrarTodo() throws {
        guard FileManager.default.fileExists(atPath: carpeta.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: carpeta)
    }

    static func carpetaPorDefecto(nombre: String = "ZeroScamDemo") -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: nombre, directoryHint: .isDirectory)
    }

    /// Si el archivo es un directorio o no se puede mover, se intenta quitar; si tampoco, la app
    /// sigue y el siguiente `guardar` informa el error.
    private func apartarArchivo() {
        let manager = FileManager.default
        try? manager.removeItem(at: apartado)
        if (try? manager.moveItem(at: archivo, to: apartado)) == nil {
            try? manager.removeItem(at: archivo)
        }
    }
}
