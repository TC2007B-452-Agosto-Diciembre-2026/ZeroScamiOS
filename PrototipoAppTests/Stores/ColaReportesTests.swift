//
//  ColaReportesTests.swift
//  PrototipoAppTests
//
//  La cola de reportes hechos sin conexión: se guarda en disco, solo la ve y la envía su dueño,
//  reintenta con la misma Idempotency-Key y no duplica cuando el servidor ya lo había creado.
//

import Foundation
import Testing
@testable import PrototipoApp

struct ColaReportesTests {
    let e: EntornoPrueba
    let secretos: MemorySecretStore
    let cable: Cable
    let reports: ReportsStore
    let almacen: AlmacenCola
    let cola: ColaReportes
    let yo: Int64

    init() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        let cable = Cable()
        let backend = BackendSinRed(base: e.backend(secretos), cable: cable)
        let reports = ReportsStore(backend: backend, archivos: e.archivos) { _ in }
        let almacen = AlmacenCola(archivo: e.carpeta.appending(path: "cola-reportes.json"))
        self.e = e
        self.secretos = secretos
        self.cable = cable
        self.reports = reports
        self.almacen = almacen
        cola = ColaReportes(almacen: almacen, archivos: e.archivos, reports: reports)
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        yo = try await backend.usuarioActual().id
        cola.usar(usuario: yo)
    }

    private func borrador(_ titulo: String = "Tienda falsa de consolas en Instagram") -> ReporteBorrador {
        DemoServerReportesTests.borrador(titulo: titulo)
    }

    private func misReportes() async -> [Reporte] {
        await reports.cargarMios()
        return reports.mios.valor ?? []
    }

    @Test func agregarLoGuardaEnDiscoYSobreviveAOtroArranque() throws {
        try cola.agregar(borrador(), clave: UUID())
        #expect(cola.pendientes.count == 1)
        let otraVez = ColaReportes(almacen: almacen, archivos: e.archivos, reports: reports)
        otraVez.usar(usuario: yo)
        #expect(otraVez.pendientes.map(\.borrador.titulo) == ["Tienda falsa de consolas en Instagram"])
    }

    @Test func soloLosVeSuDueno() throws {
        try cola.agregar(borrador(), clave: UUID())
        cola.usar(usuario: yo + 1000)
        #expect(cola.pendientes.isEmpty)
        cola.usar(usuario: nil)
        #expect(cola.pendientes.isEmpty)
        cola.usar(usuario: yo)
        #expect(cola.pendientes.count == 1)
    }

    @Test func sinSesionNoSeGuarda() {
        cola.usar(usuario: nil)
        #expect(throws: AppError.sesionExpirada) { try cola.agregar(borrador(), clave: UUID()) }
    }

    @Test func conRedSeEnviaConLaMismaClaveYSaleDeLaCola() async throws {
        let clave = UUID()
        try cola.agregar(borrador(), clave: clave)
        await cola.enviarPendientes()
        #expect(cola.pendientes.isEmpty)
        #expect(cola.enviadosRecientes == 1)
        #expect(cable.claves == [clave.uuidString])
        #expect(await misReportes().contains { $0.titulo == "Tienda falsa de consolas en Instagram" })
        #expect(almacen.leer().isEmpty)
    }

    @Test func sinRedSeQuedaEnLaCola() async throws {
        cable.conectado = false
        try cola.agregar(borrador(), clave: UUID())
        await cola.enviarPendientes()
        #expect(cola.pendientes.count == 1)
        #expect(cola.pendientes.first?.error == nil)
        #expect(cola.enviadosRecientes == 0)
    }

    /// El servidor alcanzó a crearlo pero la respuesta no llegó: el reintento de la cola usa la misma
    /// clave y recibe ese reporte, no uno nuevo.
    @Test func elCorteDespuesDeCrearNoDuplica() async throws {
        let antes = await misReportes().count
        cable.cortarDespuesDeCrear = true
        let clave = UUID()
        await #expect(throws: AppError.sinConexion) {
            _ = try await reports.crear(borrador(), clave: clave.uuidString)
        }
        try cola.agregar(borrador(), clave: clave)
        await cola.enviarPendientes()
        #expect(cola.pendientes.isEmpty)
        #expect(cable.claves == [clave.uuidString, clave.uuidString])
        #expect(await misReportes().count == antes + 1)
    }

    @Test func unRechazoDelServidorSeMarcaYNoFrenaALosDemas() async throws {
        let primero = UUID(), segundo = UUID()
        try cola.agregar(borrador("Primer reporte que el servidor rechaza"), clave: primero)
        try cola.agregar(borrador("Segundo reporte que también se intenta"), clave: segundo)
        cable.errorAlCrear = .validacion(["title es muy corto"])
        await cola.enviarPendientes()
        // El rechazo del primero no detuvo la vuelta: el segundo también se intentó.
        #expect(cable.claves == [primero.uuidString, segundo.uuidString])
        #expect(cola.pendientes.allSatisfy { $0.error == "title es muy corto" })
        #expect(cola.porEnviar == 0)

        // Un rechazo no se reintenta solo: otra vuelta no manda nada.
        await cola.enviarPendientes()
        #expect(cable.claves.count == 2)

        cable.errorAlCrear = nil
        await cola.reintentar(primero)
        #expect(cola.pendientes.map(\.id) == [segundo])
        #expect(cola.enviadosRecientes == 1)
    }

    @Test func descartarLoQuitaYBorraSuEvidencia() throws {
        var b = borrador()
        let adjunto = try e.archivos.guardarTemporal(Data([1, 2, 3]), tipo: "image/jpeg")
        b.adjuntos = [adjunto]
        let clave = UUID()
        try cola.agregar(b, clave: clave)
        #expect(throws: Never.self) { _ = try e.archivos.datos(de: adjunto) }
        cola.descartar(clave)
        #expect(cola.pendientes.isEmpty)
        #expect(throws: (any Error).self) { _ = try e.archivos.datos(de: adjunto) }
    }

    /// La evidencia de la cola no se borra al arrancar (a diferencia de la de "pendiente/") y se
    /// sube cuando vuelve la red.
    @Test func laEvidenciaSobreviveAlArranqueYSeEnvia() async throws {
        var b = borrador()
        let adjunto = try e.archivos.guardarTemporal(Data([0xFF, 0xD8, 0xFF, 0xE0]), tipo: "image/jpeg")
        b.adjuntos = [adjunto]
        cable.conectado = false
        try cola.agregar(b, clave: UUID())
        try e.archivos.limpiarTemporales()
        #expect(try e.archivos.datos(de: adjunto) == Data([0xFF, 0xD8, 0xFF, 0xE0]))

        cable.conectado = true
        await cola.enviarPendientes()
        #expect(cola.pendientes.isEmpty)
        let enviado = try #require(await misReportes().first { $0.titulo == b.titulo })
        #expect(enviado.evidencias.count == 1)
    }

    @Test func noGuardaMasDelMaximo() throws {
        for i in 0..<ColaReportes.maximo { try cola.agregar(borrador("Reporte guardado número \(i)"), clave: UUID()) }
        #expect(throws: AppError.limiteExcedido(ColaReportes.mensajeLlena)) { try cola.agregar(borrador(), clave: UUID()) }
    }

    @Test func laMismaClaveNoSeGuardaDosVeces() throws {
        let clave = UUID()
        try cola.agregar(borrador(), clave: clave)
        try cola.agregar(borrador(), clave: clave)
        #expect(cola.pendientes.count == 1)
    }

    @Test func borrarDeUnUsuarioNoTocaLosDeOtro() throws {
        try cola.agregar(borrador(), clave: UUID())
        cola.usar(usuario: yo + 1000)
        try cola.agregar(borrador("Reporte de otra persona en el teléfono"), clave: UUID())
        cola.borrar(usuario: yo)
        #expect(almacen.leer().map(\.idUsuario) == [yo + 1000])
    }

    @Test func unArchivoCorruptoCuentaComoColaVacia() throws {
        try FileManager.default.createDirectory(at: e.carpeta, withIntermediateDirectories: true)
        try Data("no es json".utf8).write(to: almacen.archivo)
        cola.usar(usuario: yo)
        #expect(cola.pendientes.isEmpty)
    }
}
