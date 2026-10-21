//
//  DemoServerReportesTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerReportesTests {
    let e = EntornoPrueba()

    static func borrador(titulo: String = "Tienda falsa de consolas en Instagram",
                         enlace: String = "https://consolas-baratas.store") -> ReporteBorrador {
        var b = ReporteBorrador()
        b.ciudad = "CDMX"
        b.tipo = .tiendaClonada
        b.titulo = titulo
        b.urlOTexto = enlace
        b.descripcion = "Ofrecen consolas a mitad de precio y piden transferencia; nunca entregan."
        b.fechaIncidente = EntornoPrueba.inicio.addingTimeInterval(-3_600)
        return b
    }

    @Test func feedSoloTraePublicos() async throws {
        let feed = try await e.servidor.feed(token: try await e.token(EntornoPrueba.usuario), filtro: FiltroBusqueda())
        #expect(feed.count == 17)
        #expect(feed.allSatisfy { $0.estado.esPublico })
        #expect(feed.first?.id == 101)
    }

    @Test func feedFiltraPorTexto() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let r = try await e.servidor.feed(token: token, filtro: FiltroBusqueda(texto: "mercado libre"))
        #expect(r.map(\.id) == [113])
    }

    @Test func misReportesTraeTodosSusEstados() async throws {
        let mios = try await e.servidor.misReportes(token: try await e.token(EntornoPrueba.usuario))
        #expect(Set(mios.map(\.estado)) == [.enRevision, .validado, .recibido])
    }

    @Test func guardadosDelUsuarioDemo() async throws {
        let g = try await e.servidor.guardados(token: try await e.token(EntornoPrueba.usuario))
        #expect(g.map(\.id) == [101, 102])
    }

    @Test func detalleDeReporteAjenoNoPublicoEsNoEncontrado() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.detalle(token: token, id: 117) }
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.detalle(token: token, id: 99_999) }
    }

    @Test func crearQuedaRecibidoPrivadoYConHistorial() async throws {
        let token = try await e.nuevaCuenta()
        let r = try await e.servidor.crear(token: token, Self.borrador())
        #expect(r.estado == .recibido)
        #expect(r.esMio)
        #expect(try await e.servidor.historial(token: token, id: r.id).map(\.nuevo) == [.recibido])
        #expect(try await e.servidor.misReportes(token: token).map(\.id) == [r.id])
        let feed = try await e.servidor.feed(token: token, filtro: FiltroBusqueda())
        #expect(!feed.contains { $0.id == r.id })
    }

    @Test func crearNormalizaLaURLYReutilizaElSitio() async throws {
        let token = try await e.nuevaCuenta()
        let a = try await e.servidor.crear(token: token, Self.borrador(enlace: "HTTPS://Consolas-Baratas.STORE/oferta"))
        let b = try await e.servidor.crear(token: token, Self.borrador(titulo: "Otra vez la tienda de consolas", enlace: "https://consolas-baratas.store/oferta"))
        #expect(a.sitio?.url == "https://consolas-baratas.store/oferta")
        #expect(a.sitio?.id == b.sitio?.id)
        #expect(a.sitio?.estadoCertificado == "HTTPS")
    }

    @Test func crearGuardaTextoCuandoNoEsURL() async throws {
        let r = try await e.servidor.crear(token: try await e.nuevaCuenta(), Self.borrador(enlace: "+52 55 1111 2222"))
        #expect(r.sitio == nil)
        #expect(r.textoSospechoso == "+52 55 1111 2222")
    }

    @Test func crearRechazaDatosInvalidos() async throws {
        var b = Self.borrador()
        b.titulo = "corto"
        let token = try await e.nuevaCuenta()
        await #expect(throws: AppError.validacion(["El título debe tener entre 10 y 120 caracteres."])) {
            _ = try await e.servidor.crear(token: token, b)
        }
    }

    @Test func limiteDeDiezReportesPorDia() async throws {
        let token = try await e.nuevaCuenta()
        for n in 1...10 { _ = try await e.servidor.crear(token: token, Self.borrador(titulo: "Reporte de prueba número \(n)")) }
        await #expect(throws: AppError.self) { _ = try await e.servidor.crear(token: token, Self.borrador()) }
    }

    @Test func editarSoloElAutorYAntesDeValidar() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var b = ReporteBorrador(desde: try await e.servidor.detalle(token: token, id: 123))
        b.titulo = "Llamada de supuesto banco pidiendo el código SMS"
        let editado = try await e.servidor.actualizar(token: token, id: 123, b)
        #expect(editado.titulo == "Llamada de supuesto banco pidiendo el código SMS")
        let validado = ReporteBorrador(desde: try await e.servidor.detalle(token: token, id: 122))
        await #expect(throws: AppError.conflicto("Este reporte ya fue revisado y no se puede editar.")) {
            _ = try await e.servidor.actualizar(token: token, id: 122, validado)
        }
        let otro = try await e.nuevaCuenta()
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.actualizar(token: otro, id: 123, b) }
    }

    @Test func eliminarSoloAutorOStaffYBorraTodoLoRelacionado() async throws {
        let otro = try await e.nuevaCuenta()
        await #expect(throws: AppError.sinPermiso) { try await e.servidor.eliminar(token: otro, id: 101) }
        let token = try await e.token(EntornoPrueba.usuario)
        try await e.servidor.eliminar(token: token, id: 122)
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.detalle(token: token, id: 122) }
        #expect(await e.servidor.db.comentarios.filter { $0.idReporte == 122 }.isEmpty)
        #expect(await e.servidor.db.historial.filter { $0.idReporte == 122 }.isEmpty)
    }

    @Test func marcarGuardadoEsIdempotente() async throws {
        let token = try await e.nuevaCuenta()
        try await e.servidor.marcarGuardado(token: token, id: 103, true)
        try await e.servidor.marcarGuardado(token: token, id: 103, true)
        #expect(try await e.servidor.guardados(token: token).map(\.id) == [103])
        try await e.servidor.marcarGuardado(token: token, id: 103, false)
        #expect(try await e.servidor.guardados(token: token).isEmpty)
    }

    @Test func confirmarEsIdempotente() async throws {
        let token = try await e.nuevaCuenta()
        _ = try await e.servidor.confirmar(token: token, id: 101)
        let r = try await e.servidor.confirmar(token: token, id: 101)
        #expect(r.confirmaciones == 1_201)
        #expect(r.confirmadoPorMi)
    }

    @Test func noSePuedeConfirmarElPropio() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        await #expect(throws: AppError.conflicto("No puedes confirmar tu propio reporte.")) {
            _ = try await e.servidor.confirmar(token: token, id: 122)
        }
    }

    @Test func comentarSoloEnPublicosYAvisaAlAutor() async throws {
        let otro = try await e.nuevaCuenta()
        let c = try await e.servidor.comentar(token: otro, id: 122, texto: "Me pasó lo mismo con esa cuenta.")
        #expect(c.autor == "Tú")
        let avisos = await e.servidor.db.notificaciones.filter { $0.idUsuario == DemoSeed.idUsuario && $0.idReporte == 122 }
        #expect(avisos.contains { $0.mensaje.hasPrefix("Nuevo comentario") })
        let autor = try await e.token(EntornoPrueba.usuario)
        await #expect(throws: AppError.conflicto("Solo se puede comentar en reportes validados.")) {
            _ = try await e.servidor.comentar(token: autor, id: 123, texto: "Comentario en mi propio reporte")
        }
    }

    @Test func comentarioSeLimpiaYSeValida() async throws {
        let token = try await e.nuevaCuenta()
        let c = try await e.servidor.comentar(token: token, id: 101, texto: "  hola\u{202E}   mundo  ")
        #expect(c.texto == "hola mundo")
        await #expect(throws: AppError.self) { _ = try await e.servidor.comentar(token: token, id: 101, texto: "x") }
    }

    @Test func limiteDeCincoComentariosPorMinuto() async throws {
        let token = try await e.nuevaCuenta()
        for n in 1...5 { _ = try await e.servidor.comentar(token: token, id: 101, texto: "Comentario número \(n)") }
        await #expect(throws: AppError.limiteExcedido("Espera un momento antes de volver a comentar.")) {
            _ = try await e.servidor.comentar(token: token, id: 101, texto: "Uno más")
        }
        e.reloj.avanzar(61)
        _ = try await e.servidor.comentar(token: token, id: 101, texto: "Ya pasó un minuto")
    }

    @Test func soloElAutorOStaffBorranComentarios() async throws {
        let otro = try await e.nuevaCuenta()
        await #expect(throws: AppError.sinPermiso) { try await e.servidor.eliminarComentario(token: otro, id: 301) }
        try await e.servidor.eliminarComentario(token: try await e.token(EntornoPrueba.admin), id: 301)
    }

    @Test func historialOcultaAQuienModeraAnteElAutor() async throws {
        let autor = try await e.servidor.historial(token: try await e.token(EntornoPrueba.usuario), id: 122)
        #expect(autor.map(\.responsable) == ["Tú", "Equipo de moderación", "Equipo de moderación"])
        // El Administrador que moderó se ve a sí mismo como "Tú"; el autor aparece con su alias.
        let staff = try await e.servidor.historial(token: try await e.token(EntornoPrueba.admin), id: 122)
        #expect(staff.map(\.responsable) == ["usuario_01", "Tú", "Tú"])
        let otro = try await e.nuevaCuenta()
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.historial(token: otro, id: 101) }
    }

    @Test func estadisticasSeCalculanDeLosPublicos() async throws {
        let s = try await e.servidor.estadisticas(token: try await e.token(EntornoPrueba.usuario))
        #expect(s == EstadisticasComunidad(personasAyudadas: 5_362, reportesVerificados: 17, estafasDetenidas: 4, zonasCubiertas: 10))
    }

    @Test func categoriasCuentanSoloPublicos() async throws {
        let c = try await e.servidor.categorias(token: try await e.token(EntornoPrueba.usuario))
        #expect(c.map(\.tipo) == TipoFraude.allCases)
        #expect(c.first { $0.tipo == .ofertaFalsa }?.total == 5)
        #expect(c.first { $0.tipo == .tiendaClonada }?.riesgoMaximo == .muyAlto)
    }

    @Test func evidenciaSoloParaElAutor() async throws {
        let token = try await e.nuevaCuenta()
        var b = Self.borrador()
        b.adjuntos = [try e.archivos.guardarTemporal(Data([0xFF, 0xD8, 0xFF, 0xE0]), tipo: "image/jpeg")]
        let r = try await e.servidor.crear(token: token, b)
        let evidencia = try #require(r.evidencias.first)
        #expect(try await e.servidor.datosEvidencia(token: token, evidencia).count == 4)
        let otro = try await e.nuevaCuenta(alias: "prueba_02", correo: "dos@comunidad.test")
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.datosEvidencia(token: otro, evidencia) }
    }
}
