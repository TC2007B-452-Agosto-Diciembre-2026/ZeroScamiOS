//
//  NotificationsStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Synchronization
import Testing
@testable import PrototipoApp

/// `nonisolated`: el protocolo no es de MainActor y el target de pruebas sí lo es por defecto.
nonisolated final class NotificadorPrueba: NotificadorLocal {
    let avisos = Mutex<[String]>([])
    func pedirPermiso() async -> Bool { true }
    func avisar(titulo: String, cuerpo: String) async { avisos.withLock { $0.append(cuerpo) } }
}

struct NotificationsStoreTests {
    let notificador = NotificadorPrueba()
    let store: NotificationsStore

    init() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        store = NotificationsStore(backend: e.backend(secretos), notificador: notificador) { _ in }
    }

    @Test func cuentaLasNoLeidas() async {
        await store.cargar(avisar: false)
        #expect(store.sinLeer == 1)
    }

    @Test func avisaUnaSolaVezSinDetalles() async {
        await store.cargar(avisar: true)
        await store.cargar(avisar: true)
        #expect(notificador.avisos.withLock { $0 } == ["Tienes 1 notificación nueva."])
    }

    @Test func noAvisaSiLaPersonaNoQuiere() async {
        await store.cargar(avisar: false)
        #expect(notificador.avisos.withLock { $0 }.isEmpty)
    }

    @Test func marcarLeidasBajaElContador() async {
        await store.cargar(avisar: false)
        await store.marcarLeidas([502])
        #expect(store.sinLeer == 0)
    }
}
