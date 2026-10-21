//
//  DemoServerReportesBordesTests.swift
//  PrototipoAppTests
//
//  Bordes de los reportes del servidor Demo: guardado que falla (la memoria no se adelanta al
//  disco), reportes que no se pueden ver, enlaces peligrosos, evidencia huérfana, contadores de
//  disco en el límite y doble toque.
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerReportesBordesTests {
    let e = EntornoPrueba()

    /// Resumen comparable de la base: si una operación falla, esto no debe cambiar.
    struct Foto: Equatable {
        let reportes, sitios, evidencias, historial, notificaciones, comentarios, guardados, confirmaciones: Int
        let ultimoID: Int64
        let analiticas: [String: Int]
    }

    private func foto(_ s: DemoServer) async -> Foto {
        let db = await s.db
        return Foto(reportes: db.reportes.count, sitios: db.sitios.count, evidencias: db.evidencias.count,
                    historial: db.historial.count, notificaciones: db.notificaciones.count,
                    comentarios: db.comentarios.count, guardados: db.guardados.count,
                    confirmaciones: db.confirmaciones.count, ultimoID: db.ultimoID, analiticas: db.analiticas)
    }

    /// Hace que guardar falle: en el lugar del archivo de la base pone un directorio con algo dentro.
    private func romperElDisco() throws {
        let archivo = DemoAlmacen(carpeta: e.carpeta).archivo
        try? FileManager.default.removeItem(at: archivo)
        try FileManager.default.createDirectory(at: archivo, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: archivo.appending(path: "x"))
    }

    private func existe(_ ruta: String) -> Bool {
        FileManager.default.fileExists(atPath: e.archivos.carpeta.appending(path: ruta).path(percentEncoded: false))
    }

    private func adjuntoJPEG() throws -> Adjunto {
        try e.archivos.guardarTemporal(Data([0xFF, 0xD8, 0xFF, 0xE0]), tipo: "image/jpeg")
    }

    /// Servidor armado a mano (como si el archivo en disco viniera manipulado) y su sesión de staff/usuario.
    private func servidor(modificando cambio: (inout DemoDatabase) -> Void) throws -> (DemoServer, URL) {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-reportes-\(UUID().uuidString)")
        let almacen = DemoAlmacen(carpeta: carpeta)
        let inicio = EntornoPrueba.inicio
        var db = DemoSeed.base(ahora: inicio)
        cambio(&db)
        try almacen.guardar(db)
        let s = DemoServer(almacen: almacen, archivos: ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia")),
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { inicio })
        return (s, carpeta)
    }

    private func token(_ s: DemoServer, _ cuenta: (correo: String, contrasena: String)) async throws -> String {
        guard case .sesion(let sesion) = try await s.iniciarSesion(correo: cuenta.correo, contrasena: cuenta.contrasena) else {
            throw AppError.codigoInvalido
        }
        return sesion.accessToken
    }

    // MARK: - Si guardar falla, la memoria no se adelanta al disco

    @Test func crearConGuardadoFallidoNoDejaNadaNiArchivos() async throws {
        let token = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador(enlace: "https://sitio-nuevo.example/x")
        b.adjuntos = [try adjuntoJPEG()]
        let antes = await foto(e.servidor)
        try romperElDisco()
        await #expect(throws: (any Error).self) { _ = try await e.servidor.crear(token: token, b) }
        #expect(await foto(e.servidor) == antes)
        let sueltos = (try? FileManager.default.contentsOfDirectory(atPath: e.archivos.carpeta.path(percentEncoded: false))) ?? []
        #expect(!sueltos.contains { $0.hasSuffix(".jpg") })
    }

    @Test func comentarConfirmarGuardarYEliminarConGuardadoFallidoNoCambianNada() async throws {
        let token = try await e.nuevaCuenta()
        let autor = try await e.token(EntornoPrueba.usuario)
        let admin = try await e.token(EntornoPrueba.admin)   // las sesiones se abren antes de romper el disco
        let antes = await foto(e.servidor)
        try romperElDisco()
        await #expect(throws: (any Error).self) { _ = try await e.servidor.comentar(token: token, id: 101, texto: "Comentario que no se guarda") }
        await #expect(throws: (any Error).self) { _ = try await e.servidor.confirmar(token: token, id: 101) }
        await #expect(throws: (any Error).self) { try await e.servidor.marcarGuardado(token: token, id: 103, true) }
        await #expect(throws: (any Error).self) { try await e.servidor.eliminarComentario(token: admin, id: 301) }
        await #expect(throws: (any Error).self) { try await e.servidor.eliminar(token: autor, id: 122) }
        #expect(await foto(e.servidor) == antes)
    }

    @Test func eliminarConGuardadoFallidoConservaLaEvidencia() async throws {
        let token = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: token, b)
        let ruta = try #require(r.evidencias.first?.rutaArchivo)
        try romperElDisco()
        await #expect(throws: (any Error).self) { try await e.servidor.eliminar(token: token, id: r.id) }
        #expect(existe(ruta))
        #expect(try await e.servidor.detalle(token: token, id: r.id).id == r.id)
    }

    @Test func actualizarConGuardadoFallidoNoCambiaNiBorraEvidencia() async throws {
        let token = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: token, b)
        let evidencia = try #require(r.evidencias.first)
        var cambio = ReporteBorrador(desde: r)
        cambio.titulo = "Título nuevo que no debe guardarse"
        cambio.quitarEvidencias = [evidencia.id]
        let antes = await foto(e.servidor)
        try romperElDisco()
        await #expect(throws: (any Error).self) { _ = try await e.servidor.actualizar(token: token, id: r.id, cambio) }
        #expect(await foto(e.servidor) == antes)
        #expect(await e.servidor.db.reportes.first { $0.id == r.id }?.titulo == r.titulo)
        #expect(existe(evidencia.rutaArchivo))
    }

    // MARK: - Lo que no se ve, no existe

    @Test func unReporteNoPublicoAjenoNoSePuedeVerNiTocar() async throws {
        let token = try await e.nuevaCuenta()
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.comentarios(token: token, id: 117) }
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.historial(token: token, id: 117) }
        await #expect(throws: AppError.noEncontrado) { try await e.servidor.marcarGuardado(token: token, id: 117, true) }
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.comentar(token: token, id: 117, texto: "Hola, ¿es real?") }
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.confirmar(token: token, id: 117) }
        await #expect(throws: AppError.noEncontrado) { try await e.servidor.eliminar(token: token, id: 117) }
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.confirmar(token: token, id: 99_999) }
    }

    @Test func elStaffNoPuedeConfirmarNiComentarLoQueNoEsPublico() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.confirmar(token: admin, id: 117) }
        await #expect(throws: AppError.conflicto("Solo se puede comentar en reportes validados.")) {
            _ = try await e.servidor.comentar(token: admin, id: 117, texto: "Comentario del staff")
        }
        // Pero sí lo ve.
        #expect(try await e.servidor.detalle(token: admin, id: 117).id == 117)
    }

    @Test func sinSesionNadaResponde() async throws {
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.feed(token: nil, filtro: FiltroBusqueda()) }
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.estadisticas(token: "token-inventado") }
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.categorias(token: nil) }
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.crear(token: nil, DemoServerReportesTests.borrador()) }
    }

    @Test func unEnlaceDeUnReportePrivadoNoApareceEnLaBusquedaDeOtros() async throws {
        let autor = try await e.nuevaCuenta()
        let r = try await e.servidor.crear(token: autor, DemoServerReportesTests.borrador(enlace: "https://estafa-secreta.example/pago"))
        let otro = try await e.nuevaCuenta(alias: "prueba_02", correo: "dos@comunidad.test")
        #expect(try await e.servidor.feed(token: otro, filtro: FiltroBusqueda(texto: "estafa-secreta")).isEmpty)
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.detalle(token: otro, id: r.id) }
        let admin = try await e.token(EntornoPrueba.admin)
        #expect(try await e.servidor.feed(token: admin, filtro: FiltroBusqueda(texto: "estafa-secreta")).isEmpty)
        // Las categorías y estadísticas solo cuentan lo público.
        let categorias = try await e.servidor.categorias(token: otro)
        #expect(categorias.map(\.total).reduce(0, +) == 17)
    }

    // MARK: - Crear y editar

    @Test func crearRechazaEnlacesPeligrosos() async throws {
        let token = try await e.nuevaCuenta()
        for peligroso in ["javascript:alert(1)", "data:text/html,hola", "ftp://archivos.example/x", "file:///etc/passwd"] {
            await #expect(throws: AppError.validacion(["Solo se aceptan enlaces http:// o https:// válidos."])) {
                _ = try await e.servidor.crear(token: token, DemoServerReportesTests.borrador(enlace: peligroso))
            }
        }
        #expect(try await e.servidor.misReportes(token: token).isEmpty)
    }

    @Test func asociarEnlaceNuncaGuardaUnEnlaceInseguroComoTexto() async throws {
        let (id1, texto1) = await e.servidor.asociarEnlace("javascript:alert(1)")
        #expect(id1 == nil && texto1 == nil)
        let (id2, texto2) = await e.servidor.asociarEnlace("")
        #expect(id2 == nil && texto2 == nil)
        let (id3, texto3) = await e.servidor.asociarEnlace("Me escribió Juan Pérez")
        #expect(id3 == nil && texto3 == "Me escribió Juan Pérez")
    }

    @Test func crearQuitaLaIdentidadEscondidaEnElEnlace() async throws {
        let r = try await e.servidor.crear(token: try await e.nuevaCuenta(),
                                           DemoServerReportesTests.borrador(enlace: "https://mi-banco.com@estafa.example/login"))
        #expect(r.sitio?.url == "https://estafa.example/login")
    }

    @Test func crearLimpiaTextosAntesDeGuardar() async throws {
        var b = DemoServerReportesTests.borrador(titulo: "  Tienda\u{202E} falsa   de consolas  ")
        b.ciudad = "  CDMX\u{200B}  "
        let r = try await e.servidor.crear(token: try await e.nuevaCuenta(), b)
        #expect(r.titulo == "Tienda falsa de consolas")
        #expect(r.ciudad == "CDMX")
    }

    @Test func crearConAdjuntosInvalidosNoDejaReporteNiArchivos() async throws {
        let token = try await e.nuevaCuenta()
        let bueno = try adjuntoJPEG()
        let rutaBuena = bueno.nombreArchivo
        // Un adjunto cuyo tipo no coincide con su archivo, otro con un tipo no permitido y otro que no existe.
        let engaño = Adjunto(id: bueno.id, nombreArchivo: bueno.nombreArchivo, tipoArchivo: "application/pdf", bytes: 4)
        let raro = Adjunto(id: UUID(), nombreArchivo: "x.exe", tipoArchivo: "application/x-msdownload", bytes: 4)
        let fantasma = Adjunto(id: UUID(), nombreArchivo: "\(UUID().uuidString).jpg", tipoArchivo: "image/jpeg", bytes: 4)
        let antes = await foto(e.servidor)
        for malo in [engaño, raro, fantasma] {
            var b = DemoServerReportesTests.borrador()
            b.adjuntos = [bueno, malo]
            await #expect(throws: AppError.self) { _ = try await e.servidor.crear(token: token, b) }
        }
        #expect(await foto(e.servidor) == antes)
        // El bueno nunca se confirmó (o se borró): no hay archivo definitivo huérfano.
        #expect(!existe(rutaBuena))
    }

    @Test func editarQuitaYAgregaEvidenciaSinTocarLaDeOtrosReportes() async throws {
        let token = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG(), try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: token, b)
        // Evidencia de otra persona: su id en `quitarEvidencias` no debe borrarla.
        let otra = try await e.nuevaCuenta(alias: "prueba_02", correo: "dos@comunidad.test")
        var ajeno = DemoServerReportesTests.borrador()
        ajeno.adjuntos = [try adjuntoJPEG()]
        let reporteAjeno = try await e.servidor.crear(token: otra, ajeno)
        let evidenciaAjena = try #require(reporteAjeno.evidencias.first)
        let (quitada, queda) = (r.evidencias[0], r.evidencias[1])
        var cambio = ReporteBorrador(desde: r)
        cambio.quitarEvidencias = [quitada.id, evidenciaAjena.id, 424_242]
        cambio.adjuntos = [try adjuntoJPEG()]
        let editado = try await e.servidor.actualizar(token: token, id: r.id, cambio)
        #expect(editado.evidencias.count == 2)
        #expect(!editado.evidencias.contains { $0.id == quitada.id })
        #expect(editado.evidencias.contains { $0.id == queda.id })
        #expect(!existe(quitada.rutaArchivo))
        #expect(existe(queda.rutaArchivo))
        #expect(existe(evidenciaAjena.rutaArchivo))
        #expect(try await e.servidor.detalle(token: otra, id: reporteAjeno.id).evidencias.count == 1)
    }

    @Test func editarNoPasaDeTresArchivos() async throws {
        let token = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG(), try adjuntoJPEG(), try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: token, b)
        var cambio = ReporteBorrador(desde: r)
        cambio.adjuntos = [try adjuntoJPEG()]
        await #expect(throws: AppError.validacion(["Máximo 3 archivos de evidencia."])) {
            _ = try await e.servidor.actualizar(token: token, id: r.id, cambio)
        }
        #expect(try await e.servidor.detalle(token: token, id: r.id).evidencias.count == 3)
    }

    @Test func editarCambiaElEnlaceYBorraElSitioQueQuedaSinUso() async throws {
        let token = try await e.nuevaCuenta()
        let r = try await e.servidor.crear(token: token, DemoServerReportesTests.borrador(enlace: "https://primero.example"))
        var cambio = ReporteBorrador(desde: r)
        cambio.urlOTexto = "https://segundo.example"
        let editado = try await e.servidor.actualizar(token: token, id: r.id, cambio)
        #expect(editado.sitio?.url == "https://segundo.example")
        let urls = await e.servidor.db.sitios.map(\.url)
        #expect(!urls.contains("https://primero.example"))
        #expect(urls.contains("https://segundo.example"))
    }

    @Test func eliminarBorraArchivosYSitiosPeroConservaLosCompartidos() async throws {
        let token = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador(enlace: "https://compartido.example")
        b.adjuntos = [try adjuntoJPEG()]
        let a = try await e.servidor.crear(token: token, b)
        let otro = try await e.servidor.crear(token: token, DemoServerReportesTests.borrador(titulo: "Segundo reporte del mismo sitio", enlace: "https://compartido.example"))
        let ruta = try #require(a.evidencias.first?.rutaArchivo)
        try await e.servidor.eliminar(token: token, id: a.id)
        #expect(!existe(ruta))
        #expect(await e.servidor.db.sitios.contains { $0.url == "https://compartido.example" })   // otro reporte lo usa
        try await e.servidor.eliminar(token: token, id: otro.id)
        #expect(!(await e.servidor.db.sitios.contains { $0.url == "https://compartido.example" }))
    }

    @Test func eliminarConservaLosSitiosYaEvaluados() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        let antes = await e.servidor.db.sitios.count
        try await e.servidor.eliminar(token: admin, id: 101)
        #expect(await e.servidor.db.sitios.count == antes)   // el sitio del 101 tiene evaluación: se queda
    }

    @Test func elLimiteDiarioSeLiberaAlPasarUnDia() async throws {
        let token = try await e.nuevaCuenta()
        for n in 1...10 { _ = try await e.servidor.crear(token: token, DemoServerReportesTests.borrador(titulo: "Reporte de prueba número \(n)")) }
        await #expect(throws: AppError.limiteExcedido("Llegaste al límite de 10 reportes por día. Intenta mañana.")) {
            _ = try await e.servidor.crear(token: token, DemoServerReportesTests.borrador())
        }
        e.reloj.avanzar(86_401)
        var b = DemoServerReportesTests.borrador()
        b.fechaIncidente = e.reloj.ahora.addingTimeInterval(-3_600)
        _ = try await e.servidor.crear(token: token, b)
    }

    // MARK: - Doble toque

    @Test func guardarYConfirmarDosVecesNoDuplican() async throws {
        let token = try await e.nuevaCuenta()
        for _ in 1...3 {
            _ = try await e.servidor.confirmar(token: token, id: 105)
            try await e.servidor.marcarGuardado(token: token, id: 105, true)
        }
        let db = await e.servidor.db
        #expect(db.confirmaciones.filter { $0.idReporte == 105 }.count == 1)
        #expect(db.guardados.filter { $0.idReporte == 105 }.count == 1)
        try await e.servidor.marcarGuardado(token: token, id: 105, false)
        try await e.servidor.marcarGuardado(token: token, id: 105, false)
        #expect(await e.servidor.db.guardados.filter { $0.idReporte == 105 }.isEmpty)
    }

    @Test func guardarDeNuevoNoCambiaLaFechaOriginal() async throws {
        let token = try await e.nuevaCuenta()
        try await e.servidor.marcarGuardado(token: token, id: 105, true)
        let primera = try #require(await e.servidor.db.guardados.first { $0.idReporte == 105 }?.fecha)
        e.reloj.avanzar(600)
        try await e.servidor.marcarGuardado(token: token, id: 105, true)
        #expect(await e.servidor.db.guardados.first { $0.idReporte == 105 }?.fecha == primera)
    }

    @Test func guardadosIgnoraParesRepetidosDelArchivo() async throws {
        let (s, _) = try servidor { db in
            db.guardados.append(ParUsuarioReporte(idUsuario: DemoSeed.idUsuario, idReporte: 101, fecha: EntornoPrueba.inicio))
        }
        let g = try await s.guardados(token: try await token(s, EntornoPrueba.usuario))
        #expect(g.map(\.id) == [101, 102])
    }

    // MARK: - Comentarios

    @Test func elAutorNoSeAvisaASiMismoAlComentar() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let antes = await e.servidor.db.notificaciones.count
        _ = try await e.servidor.comentar(token: token, id: 122, texto: "Aclaración del autor del reporte")
        #expect(await e.servidor.db.notificaciones.count == antes)
    }

    @Test func comentarioLargoSeCortaA500() async throws {
        let token = try await e.nuevaCuenta()
        let c = try await e.servidor.comentar(token: token, id: 101, texto: String(repeating: "a", count: 5_000))
        #expect(c.texto.count == 500)
    }

    @Test func comentariosSeListanDelMasNuevoAlMasViejoConAutorSegunPrivacidad() async throws {
        let token = try await e.nuevaCuenta()
        let lista = try await e.servidor.comentarios(token: token, id: 101)
        #expect(lista.map(\.id) == [301, 302])
        #expect(lista.map(\.autor) == ["Miembro de la comunidad", "compras_seguras"])   // vecina_alerta tiene perfil privado
        #expect(lista.allSatisfy { !$0.esMio })
    }

    @Test func elAutorDelComentarioPuedeBorrarloYUnComentarioInexistenteNoExiste() async throws {
        let token = try await e.nuevaCuenta()
        let c = try await e.servidor.comentar(token: token, id: 101, texto: "Comentario que luego borro")
        try await e.servidor.eliminarComentario(token: token, id: c.id)
        #expect(!(try await e.servidor.comentarios(token: token, id: 101)).contains { $0.id == c.id })
        await #expect(throws: AppError.noEncontrado) { try await e.servidor.eliminarComentario(token: token, id: c.id) }
        await #expect(throws: AppError.noEncontrado) { try await e.servidor.eliminarComentario(token: token, id: 99_999) }
    }

    // MARK: - Estadísticas con contadores de disco

    @Test func estadisticasConContadoresEnElMaximoSeSaturan() async throws {
        let (s, _) = try servidor { db in
            for i in db.reportes.indices where db.reportes[i].id == 101 || db.reportes[i].id == 102 {
                db.reportes[i].confirmacionesPrevias = .max
            }
        }
        let est = try await s.estadisticas(token: try await token(s, EntornoPrueba.usuario))
        #expect(est.personasAyudadas == .max)
        #expect(est.reportesVerificados == 17)
    }

    @Test func estadisticasConContadoresNegativosCuentanCero() async throws {
        let (s, _) = try servidor { db in
            if let i = db.reportes.firstIndex(where: { $0.id == 101 }) { db.reportes[i].confirmacionesPrevias = -5_000 }
        }
        let est = try await s.estadisticas(token: try await token(s, EntornoPrueba.usuario))
        #expect(est.personasAyudadas == 5_362 - 1_200)
    }

    @Test func estadisticasCambianConLaActividad() async throws {
        let token = try await e.nuevaCuenta()
        let antes = try await e.servidor.estadisticas(token: token)
        _ = try await e.servidor.confirmar(token: token, id: 101)
        try await e.servidor.marcarGuardado(token: token, id: 101, true)
        await #expect(throws: AppError.noEncontrado) { try await e.servidor.marcarGuardado(token: token, id: 117, true) }
        let despues = try await e.servidor.estadisticas(token: token)
        #expect(despues.personasAyudadas == antes.personasAyudadas + 2)
    }

    // MARK: - Búsqueda y evidencia

    @Test func busquedaConTextoGiganteORaroNoTruena() async throws {
        let token = try await e.nuevaCuenta()
        let enorme = String(repeating: "estafa ", count: 200_000)
        #expect(try await e.servidor.feed(token: token, filtro: FiltroBusqueda(texto: enorme)).isEmpty)
        _ = try await e.servidor.feed(token: token, filtro: FiltroBusqueda(texto: "\u{202E}\u{0000}\n\t  "))
    }

    @Test func buscarRegistraUnEventoAnonimoSoloSiSePermite() async throws {
        let token = try await e.nuevaCuenta()
        _ = try await e.servidor.feed(token: token, filtro: FiltroBusqueda())
        #expect(await e.servidor.db.analiticas["busqueda"] == nil)   // sin filtro no es una búsqueda
        _ = try await e.servidor.feed(token: token, filtro: FiltroBusqueda(texto: "consolas"))
        #expect(await e.servidor.db.analiticas["busqueda"] == 1)
    }

    @Test func elStaffVeLaEvidenciaYUnaInexistenteNoSeEncuentra() async throws {
        let autor = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: autor, b)
        let evidencia = try #require(r.evidencias.first)
        #expect(try await e.servidor.datosEvidencia(token: try await e.token(EntornoPrueba.admin), evidencia).count == 4)
        let inventada = Evidencia(id: 777_777, rutaArchivo: "../../etc/passwd", tipoArchivo: "image/jpeg", fechaCarga: EntornoPrueba.inicio)
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.datosEvidencia(token: autor, inventada) }
        // Aunque la ruta que mande el cliente sea otra, se usa la guardada en la base.
        let manipulada = Evidencia(id: evidencia.id, rutaArchivo: "../../etc/passwd", tipoArchivo: "image/jpeg", fechaCarga: EntornoPrueba.inicio)
        #expect(try await e.servidor.datosEvidencia(token: autor, manipulada).count == 4)
    }

    @Test func siElArchivoDeEvidenciaDesaparecioEsNoEncontrado() async throws {
        let autor = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: autor, b)
        let evidencia = try #require(r.evidencias.first)
        try FileManager.default.removeItem(at: e.archivos.carpeta.appending(path: evidencia.rutaArchivo))
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.datosEvidencia(token: autor, evidencia) }
    }

    @Test func evidenciaNoLlegaAOtrosEnElDetalle() async throws {
        let autor = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: autor, b)
        #expect(r.evidencias.count == 1 && r.totalEvidencias == 1)
        #expect(try await e.servidor.detalle(token: try await e.token(EntornoPrueba.admin), id: r.id).evidencias.count == 1)
    }

    // MARK: - Lectura que falla: nada se escribe

    @Test func conLaBaseSinLeerLasOperacionesFallanSinTocarElArchivo() async throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-reportes-\(UUID().uuidString)")
        let inicio = EntornoPrueba.inicio
        let bueno = DemoAlmacen(carpeta: carpeta)
        try bueno.guardar(DemoSeed.base(ahora: inicio))
        let antes = try Data(contentsOf: bueno.archivo)
        var almacen = bueno
        almacen.leer = { _ in throw CocoaError(.fileReadNoPermission) }
        let s = DemoServer(almacen: almacen, archivos: ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia")),
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { inicio })
        let esperado = AppError.servidor(DemoServer.mensajeDatosNoDisponibles)
        await #expect(throws: esperado) { _ = try await s.feed(token: "cualquiera", filtro: FiltroBusqueda(texto: "a")) }
        await #expect(throws: esperado) { _ = try await s.crear(token: "cualquiera", DemoServerReportesTests.borrador()) }
        await #expect(throws: esperado) { _ = try await s.comentar(token: "cualquiera", id: 101, texto: "Hola a todos") }
        #expect(try Data(contentsOf: bueno.archivo) == antes)
    }
}
