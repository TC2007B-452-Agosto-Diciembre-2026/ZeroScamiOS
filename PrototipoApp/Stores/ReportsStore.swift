//
//  ReportsStore.swift
//  PrototipoApp
//
//  Listas y acciones de reportes para todas las pestañas. Cada cambio sube `version`, y las
//  vistas recargan con `.task(id: reports.version)`: así una tarjeta borrada en Perfil
//  desaparece también de Buscar sin que las vistas se hablen entre sí.
//
//  Respuestas tardías: cada lista solo acepta la respuesta de su petición más reciente (teclear en
//  Buscar no deja que una respuesta vieja pise a la nueva) y `reiniciar()` descarta todo lo que
//  estuviera en camino, para que al cerrar sesión no reaparezcan datos de la sesión anterior.
//

import Foundation
import Observation

@Observable
final class ReportsStore {
    private(set) var alertas: Carga<[Reporte]> = .cargando
    private(set) var resultados: Carga<[Reporte]> = .cargando
    private(set) var categorias: Carga<[ConteoCategoria]> = .cargando
    private(set) var mios: Carga<[Reporte]> = .cargando
    private(set) var guardados: Carga<[Reporte]> = .cargando
    private(set) var estadisticas: Carga<EstadisticasComunidad> = .cargando
    private(set) var version = 0

    /// Carpeta donde el formulario deja la evidencia ya limpia antes de enviar.
    @ObservationIgnored let archivos: ArchivosEvidencia
    @ObservationIgnored private let backend: any Backend
    @ObservationIgnored private let alExpirar: (AppError) -> Void
    /// Sube en `reiniciar()`: lo que empezó antes ya no pertenece a esta sesión.
    @ObservationIgnored private var epoca = 0
    /// Contador que nunca baja y la petición vigente de cada lista.
    @ObservationIgnored private var secuencia = 0
    @ObservationIgnored private var vigentes: [AnyKeyPath: Int] = [:]
    /// Doble toque: mientras una creación está en curso, quien pida EXACTAMENTE el mismo borrador recibe
    /// la misma; uno distinto espera a que termine. `id` distingue una tarea de la siguiente.
    @ObservationIgnored private var creacion: (id: Int, borrador: ReporteBorrador, tarea: Task<Reporte, Error>)?
    @ObservationIgnored private var comentando: [String: (id: Int, tarea: Task<Comentario, Error>)] = [:]

    init(backend: any Backend, archivos: ArchivosEvidencia, alExpirar: @escaping (AppError) -> Void) {
        self.backend = backend
        self.archivos = archivos
        self.alExpirar = alExpirar
    }

    // MARK: Listas

    /// Las 2 más recientes con riesgo ALTO o MUY ALTO ("Alertas críticas" de Inicio).
    func cargarAlertas() async {
        await cargar(\.alertas) { Array(try await self.backend.feed(FiltroBusqueda(riesgoMinimo: .alto)).prefix(2)) }
    }

    func buscar(_ filtro: FiltroBusqueda) async { await cargar(\.resultados) { try await self.backend.feed(filtro) } }
    func cargarCategorias() async { await cargar(\.categorias) { try await self.backend.categorias() } }
    func cargarMios() async { await cargar(\.mios) { try await self.backend.misReportes() } }
    func cargarGuardados() async { await cargar(\.guardados) { try await self.backend.guardados() } }
    func cargarEstadisticas() async { await cargar(\.estadisticas) { try await self.backend.estadisticas() } }

    // MARK: Un reporte

    /// Las lecturas NO suben `version`: una vista que recarga con `.task(id: version)` se
    /// quedaría en un ciclo si un "no encontrado" la hiciera recargar.
    func detalle(id: Int64) async throws -> Reporte { try await ejecutar { try await backend.detalle(id: id) } }
    func historial(id: Int64) async throws -> [HistorialEstado] { try await ejecutar { try await backend.historial(id: id) } }
    func comentarios(id: Int64) async throws -> [Comentario] { try await ejecutar { try await backend.comentarios(id: id) } }
    func datosEvidencia(_ e: Evidencia) async throws -> Data { try await ejecutar { try await backend.datosEvidencia(e) } }
    func perfilPublico(id: Int64) async throws -> PerfilPublico { try await ejecutar { try await backend.perfilPublico(id: id) } }
    func analizarURL(_ url: String) async throws -> DiagnosticoURL { try await ejecutar { try await backend.analizarURL(url) } }
    func avatarPublico(idUsuario: Int64) async -> Data? { try? await ejecutar { try await backend.avatarPublico(idUsuario: idUsuario) } }

    // MARK: Cambios (suben `version`)

    /// Dos llamadas seguidas con el mismo borrador (doble toque en ENVIAR REPORTE) crean un solo
    /// reporte. Con un borrador distinto mientras otro sigue en vuelo, espera a que termine y luego
    /// crea el suyo: nunca se descarta en silencio ni se le entrega el reporte de otro.
    ///
    /// `clave` es la `Idempotency-Key`: la cola de envíos sin conexión reintenta con la misma.
    func crear(_ b: ReporteBorrador, clave: String = UUID().uuidString) async throws -> Reporte {
        while let vuelo = creacion {
            if vuelo.borrador == b { return try await vuelo.tarea.value }
            _ = await vuelo.tarea.result
        }
        secuencia &+= 1
        let id = secuencia
        let mia = epoca
        let tarea = Task { [self] in
            // Solo se borra a sí misma: `reiniciar()` pudo vaciarla y otra sesión pudo poner la suya.
            defer { if creacion?.id == id { creacion = nil } }
            // Si la sesión cambió antes de salir al servidor, no se crea con el token de la nueva.
            guard epoca == mia else { throw CancellationError() }
            return try await cambiar { try await backend.crear(b, clave: clave) }
        }
        creacion = (id, b, tarea)
        return try await tarea.value
    }

    func actualizar(id: Int64, _ b: ReporteBorrador) async throws -> Reporte { try await cambiar { try await backend.actualizar(id: id, b) } }
    func eliminar(id: Int64) async throws { try await cambiar { try await backend.eliminar(id: id) } }
    func marcarGuardado(id: Int64, _ guardado: Bool) async throws { try await cambiar { try await backend.marcarGuardado(id: id, guardado) } }
    func confirmar(id: Int64) async throws -> Reporte { try await cambiar { try await backend.confirmar(id: id) } }

    /// Igual que `crear`: publicar dos veces el mismo comentario con doble toque deja uno solo.
    func comentar(id: Int64, texto: String) async throws -> Comentario {
        let clave = "\(id)|\(texto)"
        if let vuelo = comentando[clave] { return try await vuelo.tarea.value }
        secuencia &+= 1
        let numero = secuencia
        let mia = epoca
        let tarea = Task { [self] in
            defer { if comentando[clave]?.id == numero { comentando[clave] = nil } }
            guard epoca == mia else { throw CancellationError() }
            return try await cambiar { try await backend.comentar(id: id, texto: texto) }
        }
        comentando[clave] = (numero, tarea)
        return try await tarea.value
    }

    func eliminarComentario(id: Int64) async throws { try await cambiar { try await backend.eliminarComentario(id: id) } }

    /// Para cambios hechos en otro store (moderación) que también afectan estas listas.
    func invalidar() { version &+= 1 }

    func reiniciar() {
        epoca &+= 1
        vigentes = [:]
        creacion = nil
        comentando = [:]
        alertas = .cargando
        resultados = .cargando
        categorias = .cargando
        mios = .cargando
        guardados = .cargando
        estadisticas = .cargando
        version = 0
    }

    // MARK: Ayudantes

    /// Si ya había datos se conservan mientras recarga (sin parpadeo); si falla, se muestra el error.
    private func cargar<T>(_ destino: ReferenceWritableKeyPath<ReportsStore, Carga<T>>,
                           _ operacion: () async throws -> T) async {
        secuencia &+= 1
        let mia = secuencia
        vigentes[destino] = mia
        if self[keyPath: destino].valor == nil { self[keyPath: destino] = .cargando }
        do {
            let valor = try await ejecutar(operacion)
            guard vigentes[destino] == mia else { return }
            self[keyPath: destino] = .listo(valor)
        } catch {
            guard vigentes[destino] == mia else { return }
            self[keyPath: destino] = .error(error.mensajeUsuario)
        }
    }

    /// Ejecuta un cambio y sube `version`. Si el reporte ya no existe (lo borraron en otro lado)
    /// también sube: las listas que lo mostraban deben recargar y quitarlo.
    private func cambiar<T>(_ operacion: () async throws -> T) async throws -> T {
        let mia = epoca
        do {
            let resultado = try await ejecutar(operacion)
            if epoca == mia { version &+= 1 }
            return resultado
        } catch AppError.noEncontrado {
            if epoca == mia { version &+= 1 }
            throw AppError.noEncontrado
        }
    }

    /// Una sesión vencida avisa a `alExpirar`, pero solo si sigue siendo la misma sesión: la
    /// respuesta tardía de la persona anterior no debe sacar a la que acaba de entrar.
    private func ejecutar<T>(_ operacion: () async throws -> T) async throws -> T {
        let mia = epoca
        do {
            return try await operacion()
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            if epoca == mia { alExpirar(error) }
            throw error
        }
    }
}
