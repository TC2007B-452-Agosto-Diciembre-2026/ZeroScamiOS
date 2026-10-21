//
//  ArchivosEvidencia.swift
//  PrototipoApp
//
//  Archivos de evidencia y avatares en disco. Los nombres los genera la app (UUID + extensión):
//  nadie puede pedir "../" ni otra ruta. Se escriben cifrados por iOS (`.complete`) y fuera del
//  respaldo. Lo elegido y no enviado espera en "pendiente/" y se borra al arrancar. La evidencia de
//  un reporte que espera conexión se aparta en "cola/", que sí sobrevive al arranque.
//

import Foundation

nonisolated struct ArchivosEvidencia: Sendable {
    let carpeta: URL

    var temporal: URL { carpeta.appending(path: "pendiente", directoryHint: .isDirectory) }
    /// Evidencia de los reportes en la cola de envíos sin conexión (`ColaReportes`).
    var apartados: URL { carpeta.appending(path: "cola", directoryHint: .isDirectory) }

    private static func extensionPara(_ tipo: String) -> String? {
        switch tipo {
        case "image/jpeg": "jpg"
        case "application/pdf": "pdf"
        default: nil
        }
    }

    /// Solo el nombre canónico que genera la app: UUID en mayúsculas + ".jpg" o ".pdf"
    /// ("3F2504E0-4F89-11D3-9A0C-0305E82C3301.jpg"). Se compara con `uuidString` para no aceptar
    /// minúsculas ni 36 guiones que "parecen" un UUID.
    private static func nombreValido(_ nombre: String) -> Bool {
        let partes = nombre.split(separator: ".", omittingEmptySubsequences: false)
        guard partes.count == 2, partes[1] == "jpg" || partes[1] == "pdf",
              let uuid = UUID(uuidString: String(partes[0])), uuid.uuidString == partes[0]
        else { return false }
        return true
    }

    /// Ruta de disco sin codificar: `path()` devuelve "Application%20Support" y nada se encontraría.
    private static func ruta(_ url: URL) -> String { url.path(percentEncoded: false) }

    func guardarTemporal(_ datos: Data, tipo: String) throws -> Adjunto {
        guard let ext = Self.extensionPara(tipo) else { throw ErrorEvidencia.nombreInvalido }
        // El contenido ya debió pasar por ProcesadorEvidencia; aquí solo se frena lo vacío o desmedido.
        let esPDF = tipo == "application/pdf"
        guard !datos.isEmpty else { throw esPDF ? ErrorEvidencia.noEsPDF : ErrorEvidencia.noEsImagen }
        guard datos.count <= (esPDF ? ProcesadorEvidencia.bytesMaximosPDF : ProcesadorEvidencia.bytesMaximosImagen)
        else { throw ErrorEvidencia.muyGrande }
        let id = UUID()
        let nombre = "\(id.uuidString).\(ext)"
        try escribir(datos, en: temporal.appending(path: nombre))
        return Adjunto(id: id, nombreArchivo: nombre, tipoArchivo: tipo, bytes: datos.count)
    }

    /// Busca primero en "pendiente/" y después en "cola/" (un reporte que se envía desde la cola).
    func datos(de adjunto: Adjunto) throws -> Data {
        guard Self.nombreValido(adjunto.nombreArchivo) else { throw ErrorEvidencia.nombreInvalido }
        let enCola = apartados.appending(path: adjunto.nombreArchivo)
        if FileManager.default.fileExists(atPath: Self.ruta(enCola)) { return try leer(enCola) }
        return try leer(temporal.appending(path: adjunto.nombreArchivo))
    }

    /// Ya se envió (o se descartó): se borra de "pendiente/" y de "cola/".
    func borrarTemporal(_ adjunto: Adjunto) throws {
        guard Self.nombreValido(adjunto.nombreArchivo) else { throw ErrorEvidencia.nombreInvalido }
        try? FileManager.default.removeItem(at: temporal.appending(path: adjunto.nombreArchivo))
        try? FileManager.default.removeItem(at: apartados.appending(path: adjunto.nombreArchivo))
    }

    /// Pasa el archivo de "pendiente/" a "cola/" para que el arranque no lo borre mientras el reporte
    /// espera conexión. Si ya estaba en "cola/", no hace nada.
    func apartar(_ adjunto: Adjunto) throws {
        guard Self.nombreValido(adjunto.nombreArchivo) else { throw ErrorEvidencia.nombreInvalido }
        let destino = apartados.appending(path: adjunto.nombreArchivo)
        if FileManager.default.fileExists(atPath: Self.ruta(destino)) { return }
        let origen = temporal.appending(path: adjunto.nombreArchivo)
        guard FileManager.default.fileExists(atPath: Self.ruta(origen)) else { throw ErrorEvidencia.noExiste }
        try FileManager.default.createDirectory(at: apartados, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: origen, to: destino)
        do {
            try excluirDeRespaldo(destino)
        } catch {
            try? FileManager.default.removeItem(at: destino)   // sin la marca, el archivo iría al respaldo
            throw error
        }
    }

    /// Mueve el archivo de "pendiente/" (o de "cola/") a la carpeta definitiva y devuelve su ruta (solo el nombre).
    func confirmar(_ adjunto: Adjunto) throws -> String {
        guard Self.nombreValido(adjunto.nombreArchivo) else { throw ErrorEvidencia.nombreInvalido }
        let enCola = apartados.appending(path: adjunto.nombreArchivo)
        let origen = FileManager.default.fileExists(atPath: Self.ruta(enCola)) ? enCola : temporal.appending(path: adjunto.nombreArchivo)
        guard FileManager.default.fileExists(atPath: Self.ruta(origen)) else { throw ErrorEvidencia.noExiste }
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let destino = carpeta.appending(path: adjunto.nombreArchivo)
        try FileManager.default.moveItem(at: origen, to: destino)
        try excluirDeRespaldo(destino)
        return adjunto.nombreArchivo
    }

    func datos(ruta: String) throws -> Data {
        guard Self.nombreValido(ruta) else { throw ErrorEvidencia.nombreInvalido }
        return try leer(carpeta.appending(path: ruta))
    }

    func borrar(ruta: String) throws {
        guard Self.nombreValido(ruta) else { throw ErrorEvidencia.nombreInvalido }
        try? FileManager.default.removeItem(at: carpeta.appending(path: ruta))
    }

    func limpiarTemporales() throws {
        guard FileManager.default.fileExists(atPath: Self.ruta(temporal)) else { return }
        try FileManager.default.removeItem(at: temporal)
    }

    func borrarTodo() throws {
        guard FileManager.default.fileExists(atPath: Self.ruta(carpeta)) else { return }
        try FileManager.default.removeItem(at: carpeta)
    }

    private func escribir(_ datos: Data, en url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datos.write(to: url, options: [.atomic, .completeFileProtection])
        do {
            try excluirDeRespaldo(url)
        } catch {
            try? FileManager.default.removeItem(at: url)   // sin la marca, el archivo iría al respaldo
            throw error
        }
    }

    /// Lee solo archivos normales de tamaño razonable: un directorio, un enlace o un archivo
    /// gigante dejado por otro proceso no se cargan en memoria.
    private func leer(_ url: URL) throws -> Data {
        guard let valores = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              valores.isRegularFile == true
        else { throw ErrorEvidencia.noExiste }
        guard (valores.fileSize ?? 0) <= ProcesadorEvidencia.bytesMaximosPDF else { throw ErrorEvidencia.muyGrande }
        return try Data(contentsOf: url)
    }

    private func excluirDeRespaldo(_ url: URL) throws {
        var u = url
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        try u.setResourceValues(valores)
    }
}
