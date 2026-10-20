//
//  ColaReportes.swift
//  PrototipoApp
//
//  Reportes hechos sin conexión que esperan a la red. ReportView los agrega cuando el envío falla
//  por `sinConexion`; RootView llama a `enviarPendientes()` al abrir la app, al volver a primer plano
//  y cuando regresa la red.
//
//  Cuidados:
//  - Cada reporte guarda la clave con la que se intentó la primera vez y siempre se reintenta con
//    esa misma (`Idempotency-Key`): si el servidor alcanzó a crearlo antes de que se cortara la red,
//    el reintento recibe ese reporte en vez de duplicarlo.
//  - Cada reporte es de una persona (`idUsuario`). Solo se envía con la sesión de esa persona; si
//    entra otra, sus reportes no se ven ni se mandan con el token equivocado.
//  - El archivo vive en disco cifrado por iOS (`.completeFileProtection`) y fuera del respaldo. La
//    evidencia ya va sin metadatos (ProcesadorEvidencia) y se aparta en "cola/" (ArchivosEvidencia).
//  - Cerrar sesión o eliminar la cuenta borra los reportes de esa persona del teléfono (SignOutView
//    lo avisa antes). Que la sesión venza NO los borra: se envían al volver a entrar.
//

import Foundation
import Observation

nonisolated struct PendienteEnvio: Codable, Sendable, Hashable, Identifiable {
    /// También es la `Idempotency-Key` (36 caracteres, cumple el formato que pide la API).
    let id: UUID
    let idUsuario: Int64
    let borrador: ReporteBorrador
    let guardado: Date
    /// Error que reintentar no arregla (datos que el servidor rechaza): no se reintenta solo y la
    /// persona decide si lo descarta.
    var error: String?

    var clave: String { id.uuidString }
}

/// Lee y escribe la cola en un solo archivo JSON.
nonisolated struct AlmacenCola: Sendable {
    let archivo: URL

    func leer() -> [PendienteEnvio] {
        guard let datos = try? Data(contentsOf: archivo) else { return [] }
        // Un archivo corrupto no debe tumbar la app: cuenta como cola vacía.
        return (try? Codificacion.decoder().decode([PendienteEnvio].self, from: datos)) ?? []
    }

    func guardar(_ pendientes: [PendienteEnvio]) throws {
        if pendientes.isEmpty {
            try? FileManager.default.removeItem(at: archivo)
            return
        }
        let datos = try Codificacion.encoder().encode(pendientes)
        try FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datos.write(to: archivo, options: [.atomic, .completeFileProtection])
        var url = archivo
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        try url.setResourceValues(valores)
    }
}

@Observable
final class ColaReportes {
    /// Los de la persona con sesión, del más antiguo al más reciente.
    private(set) var pendientes: [PendienteEnvio] = []
    private(set) var enviando = false
    /// Cuántos se enviaron en la última vuelta (para avisarlo en pantalla).
    private(set) var enviadosRecientes = 0

    /// Lo más que se guarda por persona; la API además permite 10 reportes al día.
    static let maximo = 10
    static let mensajeLlena = "Ya tienes \(maximo) reportes esperando conexión. Espera a que se envíen para guardar otro."
    static let mensajeSinGuardar = "No se pudo guardar el reporte en el teléfono. Intenta de nuevo."

    @ObservationIgnored private let almacen: AlmacenCola
    @ObservationIgnored private let archivos: ArchivosEvidencia
    @ObservationIgnored private let reports: ReportsStore
    @ObservationIgnored private var idUsuario: Int64?

    init(almacen: AlmacenCola, archivos: ArchivosEvidencia, reports: ReportsStore) {
        self.almacen = almacen
        self.archivos = archivos
        self.reports = reports
    }

    var porEnviar: Int { pendientes.filter { $0.error == nil }.count }

    /// Cambió la sesión: muestra solo los de esa persona (`nil` = nadie).
    func usar(usuario: Int64?) {
        idUsuario = usuario
        enviadosRecientes = 0
        recargar()
    }

    /// Guarda el reporte para enviarlo cuando vuelva la red. `clave` es la del intento que falló.
    func agregar(_ borrador: ReporteBorrador, clave: UUID) throws {
        guard let idUsuario else { throw AppError.sesionExpirada }
        var todos = almacen.leer()
        guard !todos.contains(where: { $0.id == clave }) else { return }
        guard todos.filter({ $0.idUsuario == idUsuario }).count < Self.maximo else {
            throw AppError.limiteExcedido(Self.mensajeLlena)
        }
        do {
            for adjunto in borrador.adjuntos { try archivos.apartar(adjunto) }
            todos.append(PendienteEnvio(id: clave, idUsuario: idUsuario, borrador: borrador, guardado: Date(), error: nil))
            try almacen.guardar(todos)
        } catch {
            // Sin cola no hay a dónde ir: la evidencia apartada vuelve a ser temporal y se borra al arrancar.
            throw AppError.servidor(Self.mensajeSinGuardar)
        }
        recargar()
    }

    /// Envía en orden los que no tienen error. Se detiene en el primero que falla por algo pasajero
    /// (sin red, sesión vencida, límite por minuto o día, servidor caído) y lo deja para después.
    func enviarPendientes() async {
        guard !enviando, let quien = idUsuario else { return }
        enviando = true
        defer { enviando = false }
        for pendiente in pendientes where pendiente.error == nil {
            // Cerró sesión o entró otra persona mientras se enviaba: lo demás ya no es de esta sesión.
            guard idUsuario == quien else { return }
            do {
                _ = try await reports.crear(pendiente.borrador, clave: pendiente.clave)
                quitar(pendiente.id, borrarEvidencia: true)
                enviadosRecientes += 1
            } catch let error as AppError {
                switch error {
                case .sinConexion, .sesionExpirada, .cuentaSuspendida, .limiteExcedido, .servidor:
                    return
                case .validacion, .sinPermiso, .noEncontrado, .conflicto, .credencialesInvalidas,
                     .cuentaBloqueada, .codigoInvalido:
                    marcarError(pendiente.id, error.mensaje())
                }
            } catch {
                return   // Cancelado (la sesión cambió antes de salir al servidor).
            }
        }
    }

    /// Le quita el error y lo vuelve a intentar.
    func reintentar(_ id: UUID) async {
        cambiar(id) { $0.error = nil }
        await enviarPendientes()
    }

    func descartar(_ id: UUID) {
        quitar(id, borrarEvidencia: true)
    }

    /// Cerró sesión o eliminó su cuenta: nada de esa persona se queda en el teléfono.
    func borrar(usuario: Int64) {
        let todos = almacen.leer()
        for p in todos where p.idUsuario == usuario { borrarEvidencia(de: p) }
        try? almacen.guardar(todos.filter { $0.idUsuario != usuario })
        recargar()
    }

    func olvidarEnviados() { enviadosRecientes = 0 }

    // MARK: Ayudantes

    private func recargar() {
        guard let idUsuario else { pendientes = []; return }
        pendientes = almacen.leer().filter { $0.idUsuario == idUsuario }.sorted { $0.guardado < $1.guardado }
    }

    private func quitar(_ id: UUID, borrarEvidencia borrar: Bool) {
        let todos = almacen.leer()
        if borrar, let p = todos.first(where: { $0.id == id }) { borrarEvidencia(de: p) }
        try? almacen.guardar(todos.filter { $0.id != id })
        recargar()
    }

    private func marcarError(_ id: UUID, _ mensaje: String) {
        cambiar(id) { $0.error = mensaje }
    }

    private func cambiar(_ id: UUID, _ cambio: (inout PendienteEnvio) -> Void) {
        var todos = almacen.leer()
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        cambio(&todos[i])
        try? almacen.guardar(todos)
        recargar()
    }

    private func borrarEvidencia(de p: PendienteEnvio) {
        for adjunto in p.borrador.adjuntos { try? archivos.borrarTemporal(adjunto) }
    }
}
