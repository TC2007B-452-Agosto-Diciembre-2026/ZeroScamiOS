//
//  AdminStore.swift
//  PrototipoApp
//
//  Cola de moderación (Administrador y Owner) y gestión de usuarios (solo Owner). Los permisos
//  los revisa el servidor; aquí solo se muestran sus respuestas.
//

import Foundation
import Observation

@Observable
final class AdminStore {
    private(set) var cola: Carga<[Reporte]> = .cargando
    private(set) var usuarios: Carga<[Usuario]> = .cargando
    private(set) var analiticas: [String: Int] = [:]

    @ObservationIgnored private let backend: any Backend
    @ObservationIgnored private let alExpirar: (AppError) -> Void
    /// Sube en `reiniciar()`: lo que estaba en camino ya no es de esta sesión.
    @ObservationIgnored private var epoca = 0
    /// Cambiar de filtro rápido: solo la petición más reciente de cada lista escribe su resultado.
    @ObservationIgnored private var pedidoCola = 0
    @ObservationIgnored private var pedidoUsuarios = 0

    init(backend: any Backend, alExpirar: @escaping (AppError) -> Void) {
        self.backend = backend
        self.alExpirar = alExpirar
    }

    func cargarCola(estado: EstadoReporte?) async {
        pedidoCola &+= 1
        let mio = pedidoCola
        if cola.valor == nil { cola = .cargando }
        do {
            let lista = try await ejecutar { try await backend.colaModeracion(estado: estado) }
            guard pedidoCola == mio else { return }
            cola = .listo(lista)
        } catch {
            guard pedidoCola == mio else { return }
            cola = .error(error.mensajeUsuario)
        }
    }

    /// Todos los estados, más viejos primero (filtro "TODOS" de la cola).
    func cargarColaCompleta() async {
        pedidoCola &+= 1
        let mio = pedidoCola
        if cola.valor == nil { cola = .cargando }
        do {
            var todos: [Reporte] = []
            for estado in EstadoReporte.allCases {
                todos += try await ejecutar { try await backend.colaModeracion(estado: estado) }
            }
            guard mio == pedidoCola else { return }
            cola = .listo(todos.sorted { $0.fechaCreacion != $1.fechaCreacion ? $0.fechaCreacion < $1.fechaCreacion : $0.id < $1.id })
        } catch {
            guard mio == pedidoCola else { return }
            cola = .error(error.mensajeUsuario)
        }
    }

    func cambiarEstado(id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) async throws -> Reporte {
        try await ejecutar { try await backend.cambiarEstado(id: id, a: nuevo, riesgo: riesgo, observaciones: observaciones) }
    }

    func cargarUsuarios() async {
        pedidoUsuarios &+= 1
        let mio = pedidoUsuarios
        if usuarios.valor == nil { usuarios = .cargando }
        do {
            let lista = try await ejecutar { try await backend.usuarios() }
            let conteos = (try? await ejecutar { try await backend.analiticas() }) ?? [:]
            guard pedidoUsuarios == mio else { return }
            usuarios = .listo(lista)
            analiticas = conteos
        } catch {
            guard pedidoUsuarios == mio else { return }
            usuarios = .error(error.mensajeUsuario)
        }
    }

    func cambiarRol(idUsuario: Int64, a rol: Rol) async throws {
        let mia = epoca
        let u = try await ejecutar { try await backend.cambiarRol(idUsuario: idUsuario, a: rol) }
        if epoca == mia { reemplazar(u) }
    }

    func cambiarEstadoCuenta(idUsuario: Int64, a estado: EstadoCuenta) async throws {
        let mia = epoca
        let u = try await ejecutar { try await backend.cambiarEstadoCuenta(idUsuario: idUsuario, a: estado) }
        if epoca == mia { reemplazar(u) }
    }

    func restablecerDemo() async throws {
        try await ejecutar { try await backend.restablecerDemo() }
    }

    func reiniciar() {
        epoca &+= 1
        pedidoCola &+= 1
        pedidoUsuarios &+= 1
        cola = .cargando
        usuarios = .cargando
        analiticas = [:]
    }

    private func reemplazar(_ u: Usuario) {
        guard var lista = usuarios.valor, let i = lista.firstIndex(where: { $0.id == u.id }) else { return }
        lista[i] = u
        usuarios = .listo(lista)
    }

    /// Solo avisa de sesión vencida si sigue siendo la misma sesión que la pidió.
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
