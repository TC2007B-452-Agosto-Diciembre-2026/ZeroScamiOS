//
//  MonitorRed.swift
//  PrototipoApp
//
//  ¿Hay red? Lo avisa iOS (NWPathMonitor) cada vez que cambia. RootView lo usa para revisar la
//  sesión abierta sin conexión y enviar la cola de reportes en cuanto vuelve la red. Que haya red
//  no garantiza que el servidor responda: eso lo dice cada petición.
//

import Foundation
import Network
import Observation

@Observable
final class MonitorRed {
    private(set) var conectada = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    func iniciar() {
        monitor.pathUpdateHandler = { [weak self] ruta in
            let conectada = ruta.status == .satisfied
            Task { @MainActor in self?.conectada = conectada }
        }
        monitor.start(queue: DispatchQueue(label: "zs.monitor-red"))
    }

    deinit { monitor.cancel() }
}
