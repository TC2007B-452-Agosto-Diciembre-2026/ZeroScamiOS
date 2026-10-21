//
//  DemoAlmacenTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoAlmacenTests {
    let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-almacen-\(UUID().uuidString)")

    @Test func sinArchivoDevuelveNil() {
        #expect(DemoAlmacen(carpeta: carpeta).cargar() == nil)
    }

    @Test func guardarYCargarConservaLosDatos() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        var db = DemoDatabase()
        let id = db.siguienteID()
        db.analiticas["busqueda"] = 3
        db.intentos["a@b.mx"] = RegistroIntentos(fallidos: 2, bloqueadoHasta: nil)
        try almacen.guardar(db)
        let leida = try #require(almacen.cargar())
        #expect(id == 1_001)
        #expect(leida.ultimoID == 1_001)
        #expect(leida.analiticas["busqueda"] == 3)
        #expect(leida.intentos["a@b.mx"]?.fallidos == 2)
    }

    @Test func elArchivoNoViajaEnRespaldos() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        try almacen.guardar(DemoDatabase())
        let valores = try almacen.archivo.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(valores.isExcludedFromBackup == true)
    }

    @Test func archivoDanadoSeAparteYDevuelveNil() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try Data("{no es json".utf8).write(to: almacen.archivo)
        #expect(almacen.cargar() == nil)
        #expect(FileManager.default.fileExists(atPath: carpeta.appending(path: "zeroscam-demo.corrupto.json").path()))
    }

    @Test func fechasConMilisegundosSeLeen() throws {
        let json = Data(#""2026-10-07T12:00:00.123Z""#.utf8)
        let fecha = try Codificacion.decoder().decode(Date.self, from: json)
        #expect(fecha.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) > 0.1)
        let sinMilis = try Codificacion.decoder().decode(Date.self, from: Data(#""2026-10-07T12:00:00Z""#.utf8))
        #expect(sinMilis < fecha)
    }

    // MARK: - Bordes: el archivo es un dato externo y nunca debe tumbar la app

    private var corrupto: URL { carpeta.appending(path: "zeroscam-demo.corrupto.json") }

    private func escribirCrudo(_ datos: Data, en almacen: DemoAlmacen) throws {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try datos.write(to: almacen.archivo)
    }

    /// Un archivo válido al que se le cambian campos sueltos a mano.
    private func archivoValido(modificando cambios: [String: Any]) throws -> Data {
        let base = try Codificacion.encoder().encode(DemoDatabase())
        var objeto = try #require(try JSONSerialization.jsonObject(with: base) as? [String: Any])
        for (clave, valor) in cambios { objeto[clave] = valor }
        return try JSONSerialization.data(withJSONObject: objeto)
    }

    private func cargarApartando(_ datos: Data) throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        try escribirCrudo(datos, en: almacen)
        #expect(almacen.cargar() == nil)
        #expect(FileManager.default.fileExists(atPath: corrupto.path()))
        #expect(!FileManager.default.fileExists(atPath: almacen.archivo.path()))
    }

    @Test func archivoVacioSeApartaYDevuelveNil() throws {
        try cargarApartando(Data())
    }

    @Test func jsonValidoPeroDeOtraFormaSeApartaYDevuelveNil() throws {
        for texto in ["[]", "null", "{}", "42", #""texto""#, #"{"version":1}"#] {
            try cargarApartando(Data(texto.utf8))
            try? FileManager.default.removeItem(at: carpeta)
        }
    }

    @Test func versionFuturaSeApartaYDevuelveNil() throws {
        try cargarApartando(try archivoValido(modificando: ["version": DemoDatabase.versionActual + 1]))
    }

    @Test func versionAnteriorOInvalidaSeApartaYDevuelveNil() throws {
        try cargarApartando(try archivoValido(modificando: ["version": 0]))
        try? FileManager.default.removeItem(at: carpeta)
        try cargarApartando(try archivoValido(modificando: ["version": -5]))
    }

    @Test func archivoGiganteSeApartaSinLeerloYDevuelveNil() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: almacen.archivo.path(), contents: nil)
        let manejador = try FileHandle(forWritingTo: almacen.archivo)
        // Archivo disperso: ocupa casi nada en disco pero mide más que el máximo permitido.
        try manejador.truncate(atOffset: UInt64(DemoAlmacen.tamanoMaximo) + 1)
        try manejador.close()
        #expect(almacen.cargar() == nil)
        #expect(FileManager.default.fileExists(atPath: corrupto.path()))
        #expect(!FileManager.default.fileExists(atPath: almacen.archivo.path()))
    }

    @Test func anidamientoExageradoNoTumbaLaCarga() throws {
        let profundo = String(repeating: "[", count: 200_000) + String(repeating: "]", count: 200_000)
        try cargarApartando(Data(profundo.utf8))
    }

    @Test func fechaInvalidaSeApartaYDevuelveNil() throws {
        let datos = try archivoValido(modificando: [
            "analiticas": ["a": 1],
            "intentos": ["a@b.mx": ["fallidos": 1, "bloqueadoHasta": "2026-13-45T99:99:99Z"]],
        ])
        try cargarApartando(datos)
    }

    @Test func contadorDeIdsFueraDeRangoSeApartaYDevuelveNil() throws {
        try cargarApartando(try archivoValido(modificando: ["ultimoID": Int64.max]))
        try? FileManager.default.removeItem(at: carpeta)
        try cargarApartando(try archivoValido(modificando: ["ultimoID": -1]))
    }

    @Test func siguienteIDNoTruenaEnElLimite() {
        var db = DemoDatabase()
        db.ultimoID = Int64.max
        _ = db.siguienteID()
        #expect(db.ultimoID == Int64.max)
        db.ultimoID = Int64.max - 1
        #expect(db.siguienteID() == Int64.max)
    }

    @Test func alCargarElContadorAlcanzaElIdMasAltoDeLasFilas() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        var db = DemoDatabase()
        db.comentarios.append(ComentarioFila(id: 5_000, idReporte: 1, idUsuario: nil, texto: "hola", fecha: Date(timeIntervalSince1970: 1_790_000_000)))
        db.sitios.append(SitioWeb(id: 7_000, url: "https://x.mx", nivelRiesgoGlobal: .alto, estadoCertificado: nil, fechaUltimaEvaluacion: nil))
        #expect(db.ultimoID == 1_000)
        try almacen.guardar(db)
        var leida = try #require(almacen.cargar())
        #expect(leida.ultimoID == 7_000)
        // El siguiente id no puede repetir uno que ya existe.
        #expect(leida.siguienteID() == 7_001)
    }

    @Test func elArchivoEsUnDirectorioNoTumbaLaCarga() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        try FileManager.default.createDirectory(at: almacen.archivo, withIntermediateDirectories: true)
        #expect(almacen.cargar() == nil)
    }

    @Test func guardarDosVecesSobreescribeYSigueLegible() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        var db = DemoDatabase()
        db.analiticas["a"] = 1
        try almacen.guardar(db)
        db.analiticas["a"] = 2
        try almacen.guardar(db)
        #expect(try #require(almacen.cargar()).analiticas["a"] == 2)
    }

    @Test func unCorruptoAnteriorSeReemplazaSinFallar() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        try cargarApartando(Data("{mal".utf8))
        try escribirCrudo(Data("{otro mal".utf8), en: almacen)
        #expect(almacen.cargar() == nil)
        #expect(try Data(contentsOf: corrupto) == Data("{otro mal".utf8))
    }

    @Test func borrarTodoQuitaLaCarpeta() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        try almacen.guardar(DemoDatabase())
        try almacen.borrarTodo()
        #expect(!FileManager.default.fileExists(atPath: carpeta.path()))
        #expect(almacen.cargar() == nil)
    }

    @Test func borrarTodoSinCarpetaNoFalla() throws {
        try DemoAlmacen(carpeta: carpeta).borrarTodo()
    }

    @Test func idaYVueltaConservaTodasLasTablas() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        let t = Date(timeIntervalSince1970: 1_790_000_000.5)
        var db = DemoDatabase()
        db.sesiones = [SesionFila(tokenHash: "h", idUsuario: 1, creada: t, expira: t.addingTimeInterval(60))]
        db.desafios = [DesafioFila(id: "d", idUsuario: 1, codigoHash: "c", expira: t, intentos: 0)]
        db.historial = [HistorialFila(id: 2, idReporte: 1, idResponsable: 3, anterior: nil, nuevo: .validado, observaciones: nil, fecha: t)]
        db.notificaciones = [NotificacionFila(id: 3, idUsuario: 1, idReporte: nil, mensaje: "m", leida: false, fecha: t)]
        db.guardados = [ParUsuarioReporte(idUsuario: 1, idReporte: 2, fecha: t)]
        db.confirmaciones = [ParUsuarioReporte(idUsuario: 1, idReporte: 2, fecha: t)]
        db.evidencias = [EvidenciaFila(id: 4, idReporte: 1, rutaArchivo: "a.jpg", tipoArchivo: "imagen", fechaCarga: t)]
        try almacen.guardar(db)
        let leida = try #require(almacen.cargar())
        #expect(leida.sesiones.first?.expira == t.addingTimeInterval(60))
        #expect(leida.desafios.first?.id == "d")
        #expect(leida.historial.first?.nuevo == .validado)
        #expect(leida.notificaciones.first?.leida == false)
        #expect(leida.guardados == db.guardados)
        #expect(leida.confirmaciones == db.confirmaciones)
        #expect(leida.evidencias.first?.evidencia.rutaArchivo == "a.jpg")
        #expect(leida.version == DemoDatabase.versionActual)
    }

    private struct FalloDeLectura: Error {}

    @Test func unFalloDeLecturaNoApartaElArchivoBueno() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        var db = DemoDatabase()
        db.analiticas["a"] = 7
        try almacen.guardar(db)
        let antes = try Data(contentsOf: almacen.archivo)

        // Simula el teléfono bloqueado: la lectura falla aunque el archivo es válido.
        var bloqueado = almacen
        bloqueado.leer = { _ in throw FalloDeLectura() }
        #expect(bloqueado.cargar() == nil)
        #expect(try Data(contentsOf: almacen.archivo) == antes)
        #expect(!FileManager.default.fileExists(atPath: corrupto.path()))

        // Al desbloquear, los datos siguen ahí.
        #expect(try #require(almacen.cargar()).analiticas["a"] == 7)
    }

    @Test func guardarRechazaLoQueNoSePodriaCargarYConservaElArchivoBueno() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        var db = DemoDatabase()
        db.analiticas["a"] = 1
        try almacen.guardar(db)
        let antes = try Data(contentsOf: almacen.archivo)

        var enorme = db
        let texto = String(repeating: "x", count: DemoAlmacen.tamanoMaximo + 1)
        enorme.comentarios = [ComentarioFila(id: 2, idReporte: 1, idUsuario: nil, texto: texto, fecha: Date(timeIntervalSince1970: 1_790_000_000))]
        #expect(throws: AppError.self) { try almacen.guardar(enorme) }
        #expect(try Data(contentsOf: almacen.archivo) == antes)
        #expect(try #require(almacen.cargar()).analiticas["a"] == 1)
    }

    @Test func carpetaPorDefectoUsaElNombreDado() {
        #expect(DemoAlmacen.carpetaPorDefecto(nombre: "PruebaZS").lastPathComponent == "PruebaZS")
    }

    /// "Application Support" lleva un espacio: con `path()` (codificado) el archivo nunca se encontraba.
    @Test func unaCarpetaConEspaciosSeLeeYSeBorra() throws {
        let conEspacios = FileManager.default.temporaryDirectory.appending(path: "Application Support \(UUID().uuidString)")
        let almacen = DemoAlmacen(carpeta: conEspacios)
        var db = DemoDatabase()
        db.analiticas["a"] = 5
        try almacen.guardar(db)
        #expect(try #require(almacen.cargar()).analiticas["a"] == 5)
        try almacen.borrarTodo()
        #expect(!FileManager.default.fileExists(atPath: conEspacios.path(percentEncoded: false)))
    }
}
