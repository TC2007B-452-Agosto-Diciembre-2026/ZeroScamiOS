//
//  NotificationsStore.swift
//  PrototipoApp
//
//  Notificaciones de la persona (Notificacion_Alerta) y el número de la campana. Si activó
//  "Notificaciones" en Ajustes, avisa con una notificación del sistema solo por lo nuevo.
//

import Foundation
import Observation

@Observable
final class NotificationsStore {
    private(set) var lista: Carga<[Notificacion]> = .cargando

    var sinLeer: Int { lista.valor?.filter { !$0.leida }.count ?? 0 }

    @ObservationIgnored private var ultimaAvisada: Int64 = 0
    @ObservationIgnored private let backend: any Backend
    @ObservationIgnored private let notificador: any NotificadorLocal
    @ObservationIgnored private let alExpirar: (AppError) -> Void
    /// Sube en `reiniciar()`: lo que estaba en camino ya no es de esta sesión.
    @ObservationIgnored private var epoca = 0
    /// La petición de `cargar` más reciente es la única que puede escribir la lista.
    @ObservationIgnored private var secuencia = 0

    init(backend: any Backend, notificador: any NotificadorLocal, alExpirar: @escaping (AppError) -> Void) {
        self.backend = backend
        self.notificador = notificador
        self.alExpirar = alExpirar
    }

    func cargar(avisar: Bool) async {
        let mia = epoca
        secuencia &+= 1
        let pedido = secuencia
        do {
            let nuevas = try await backend.notificaciones()
            guard epoca == mia, secuencia == pedido else { return }
            lista = .listo(nuevas)
            let sinAvisar = nuevas.filter { !$0.leida && $0.id > ultimaAvisada }
            // Se anota antes de avisar: dos cargas simultáneas no deben avisar lo mismo dos veces.
            ultimaAvisada = max(ultimaAvisada, nuevas.map(\.id).max() ?? 0)
            if avisar && !sinAvisar.isEmpty {
                let cuerpo = sinAvisar.count == 1 ? "Tienes 1 notificación nueva." : "Tienes \(sinAvisar.count) notificaciones nuevas."
                await notificador.avisar(titulo: "ZeroScam", cuerpo: cuerpo)
            }
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            if epoca == mia { alExpirar(error) }
        } catch {
            if epoca == mia, secuencia == pedido, lista.valor == nil { lista = .error(error.mensajeUsuario) }
        }
    }

    /// Marca en el servidor y, solo si salió bien, en la lista (si falló, el contador no miente).
    func marcarLeidas(_ ids: [Int64]) async {
        guard !ids.isEmpty else { return }
        let mia = epoca
        do {
            try await backend.marcarLeidas(ids)
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            if epoca == mia { alExpirar(error) }
            return
        } catch {
            return
        }
        guard epoca == mia, var actuales = lista.valor else { return }
        for i in actuales.indices where ids.contains(actuales[i].id) { actuales[i].leida = true }
        lista = .listo(actuales)
    }

    func pedirPermiso() async -> Bool { await notificador.pedirPermiso() }

    func reiniciar() {
        epoca &+= 1
        lista = .cargando
        ultimaAvisada = 0
    }
}
