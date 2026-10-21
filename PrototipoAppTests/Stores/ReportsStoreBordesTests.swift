//
//  ReportsStoreBordesTests.swift
//  PrototipoAppTests
//
//  Casos límite del ReportsStore: doble toque, reporte que desaparece, respuestas tardías
//  después de reiniciar y sesión vencida.
//

import Foundation
import Testing
@testable import PrototipoApp

struct ReportsStoreBordesTests {
    let e: EntornoPrueba
    let secretos: MemorySecretStore
    let expiraciones: RegistroExpiraciones
    let reports: ReportsStore

    init() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        let expiraciones = RegistroExpiraciones()
        self.e = e
        self.secretos = secretos
        self.expiraciones = expiraciones
        reports = ReportsStore(backend: e.backend(secretos), archivos: e.archivos) { expiraciones.errores.append($0) }
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
    }

    // MARK: Foco 2: doble toque

    @Test func dobleToqueEnEnviarCreaUnSoloReporte() async throws {
        let antes = try await reports.crear(DemoServerReportesTests.borrador(titulo: "Primero y único")).id
        await reports.cargarMios()
        let conteoAntes = try #require(reports.mios.valor).count
        let versionAntes = reports.version
        let borrador = DemoServerReportesTests.borrador(titulo: "Tienda falsa de bocinas")
        async let uno = reports.crear(borrador)
        async let dos = reports.crear(borrador)
        let (a, b) = try await (uno, dos)
        #expect(a.id == b.id)
        #expect(a.id != antes)
        #expect(reports.version == versionAntes + 1)
        await reports.cargarMios()
        #expect(reports.mios.valor?.count == conteoAntes + 1)
    }

    @Test func dobleToqueAlComentarPublicaUnoSolo() async throws {
        let antes = try await reports.comentarios(id: 101).count
        async let uno = reports.comentar(id: 101, texto: "Yo también la vi.")
        async let dos = reports.comentar(id: 101, texto: "Yo también la vi.")
        let (a, b) = try await (uno, dos)
        #expect(a.id == b.id)
        #expect(try await reports.comentarios(id: 101).count == antes + 1)
    }

    @Test func despuesDeTerminarSePuedeCrearOtro() async throws {
        let a = try await reports.crear(DemoServerReportesTests.borrador(titulo: "Uno distinto"))
        let b = try await reports.crear(DemoServerReportesTests.borrador(titulo: "Otro distinto"))
        #expect(a.id != b.id)
    }

    // MARK: Foco 3: el reporte desaparece

    @Test func eliminarUnReporteYaNoDisponibleRefrescaLasListas() async throws {
        let antes = reports.version
        await #expect(throws: AppError.noEncontrado) { try await reports.eliminar(id: 99_999) }
        #expect(reports.version == antes + 1)
        #expect(expiraciones.errores.isEmpty)
    }

    @Test func leerUnReporteInexistenteNoSubeLaVersion() async {
        // Subirla haría que `.task(id: version)` en el detalle entrara en un ciclo.
        let antes = reports.version
        await #expect(throws: AppError.noEncontrado) { _ = try await reports.detalle(id: 99_999) }
        #expect(reports.version == antes)
    }

    @Test func unaListaConDatosMuestraElErrorSiLaRecargaFalla() async throws {
        await reports.cargarMios()
        #expect(reports.mios.valor != nil)
        try secretos.borrar(.accessToken)
        await reports.cargarMios()
        #expect(reports.mios == .error(AppError.sesionExpirada.mensaje()))
    }

    // MARK: Foco 1: sesión vencida

    @Test func tokenVencidoPorElRelojAvisaAlExpirar() async {
        e.reloj.avanzar(7 * 24 * 3_600 + 1)
        await reports.cargarGuardados()
        #expect(reports.guardados == .error(AppError.sesionExpirada.mensaje()))
        #expect(expiraciones.errores == [.sesionExpirada])
    }

    @Test func unCambioConSesionVencidaAvisaYNoSubeLaVersion() async throws {
        e.reloj.avanzar(7 * 24 * 3_600 + 1)
        let antes = reports.version
        await #expect(throws: AppError.sesionExpirada) { _ = try await reports.confirmar(id: 101) }
        #expect(expiraciones.errores == [.sesionExpirada])
        #expect(reports.version == antes)
    }

    // MARK: Cerrar sesión no deja datos ni avisos de la sesión anterior

    /// Un store con un backend que retiene la primera lectura hasta abrir la puerta.
    private func conPuerta(alExpirar: @escaping (AppError) -> Void = { _ in }) -> (ReportsStore, Puerta) {
        let puerta = Puerta()
        let backend = BackendConPuerta(base: e.backend(secretos), puerta: puerta)
        return (ReportsStore(backend: backend, archivos: e.archivos, alExpirar: alExpirar), puerta)
    }

    @Test func reiniciarDescartaLaRespuestaQueEstabaEnCamino() async {
        let (store, puerta) = conPuerta()
        let tarea = Task { await store.cargarMios() }
        await puerta.esperarLlegada()
        store.reiniciar()
        await puerta.abrir()
        await tarea.value
        #expect(store.mios == .cargando)
    }

    @Test func laSesionVencidaDeLaSesionAnteriorNoSacaALaNueva() async throws {
        let registro = RegistroExpiraciones()
        let (store, puerta) = conPuerta { registro.errores.append($0) }
        try secretos.borrar(.accessToken)
        let tarea = Task { await store.cargarMios() }
        await puerta.esperarLlegada()
        store.reiniciar()
        await puerta.abrir()
        await tarea.value
        #expect(registro.errores.isEmpty)
        #expect(store.mios == .cargando)
    }

    @Test func laRespuestaViejaDeUnaBusquedaNoPisaALaNueva() async {
        let (store, puerta) = conPuerta()
        let vieja = Task { await store.buscar(FiltroBusqueda(tipos: [.llamada])) }
        await puerta.esperarLlegada()              // la primera búsqueda queda retenida
        await store.buscar(FiltroBusqueda(tipos: [.tiendaClonada]))   // la segunda termina primero
        let nueva = store.resultados.valor?.map(\.id)
        #expect(nueva?.isEmpty == false)
        await puerta.abrir()                       // llega tarde la respuesta de "llamada"
        await vieja.value
        #expect(store.resultados.valor?.map(\.id) == nueva)
    }

    @Test func invalidarSubeLaVersionYReiniciarLaRegresaACero() {
        reports.invalidar()
        reports.invalidar()
        #expect(reports.version == 2)
        reports.reiniciar()
        #expect(reports.version == 0)
        #expect(reports.alertas == .cargando)
        #expect(reports.resultados == .cargando)
        #expect(reports.categorias == .cargando)
        #expect(reports.guardados == .cargando)
        #expect(reports.estadisticas == .cargando)
    }

    @Test func lasEstadisticasYLasCategoriasCargan() async {
        await reports.cargarEstadisticas()
        await reports.cargarCategorias()
        #expect(reports.estadisticas.valor != nil)
        #expect(reports.categorias.valor?.isEmpty == false)
    }

    // MARK: Ronda 1: borrador distinto y fuga entre sesiones

    @Test func unBorradorDistintoDuranteElVueloNoRecibeElReporteDelPrimero() async throws {
        let (store, puerta) = conPuerta()
        let primero = DemoServerReportesTests.borrador(titulo: "Primer reporte en vuelo")
        let segundo = DemoServerReportesTests.borrador(titulo: "Segundo reporte, otro borrador")
        let t1 = Task { try await store.crear(primero) }
        await puerta.esperarLlegada()                 // el primero está retenido en el "servidor"
        let abrir = Task { await puerta.abrir() }     // se abre cuando la prueba ya esté esperando
        let r2 = try await store.crear(segundo)       // ve el vuelo del primero y espera su turno
        let r1 = try await t1.value
        await abrir.value
        #expect(r1.titulo == "Primer reporte en vuelo")
        #expect(r2.titulo == "Segundo reporte, otro borrador")
        #expect(r1.id != r2.id)
        #expect(store.version == 2)
    }

    @Test func crearTrasReiniciarNoHeredaElResultadoDeLaOtraSesion() async throws {
        let (store, puerta) = conPuerta()
        let borrador = DemoServerReportesTests.borrador(titulo: "Mismo borrador de dos sesiones")
        let deA = Task { try await store.crear(borrador) }
        await puerta.esperarLlegada()                 // A tiene su creación en vuelo
        store.reiniciar()                             // A cierra sesión; entra B
        let abrir = Task { await puerta.abrir() }
        let deB = try await store.crear(borrador)     // B pide lo mismo antes de que termine A
        let reporteDeA = try? await deA.value
        await abrir.value
        #expect(reporteDeA?.id != deB.id)
        #expect(store.version == 1)                   // solo la creación de B sube la versión
    }

    @Test func comentarTrasReiniciarNoHeredaElResultadoDeLaOtraSesion() async throws {
        let (store, puerta) = conPuerta()
        let deA = Task { try await store.comentar(id: 101, texto: "Mismo texto") }
        await puerta.esperarLlegada()
        store.reiniciar()
        let abrir = Task { await puerta.abrir() }
        let deB = try await store.comentar(id: 101, texto: "Mismo texto")
        let comentarioDeA = try? await deA.value
        await abrir.value
        #expect(comentarioDeA?.id != deB.id)
        #expect(store.version == 1)
    }
}
