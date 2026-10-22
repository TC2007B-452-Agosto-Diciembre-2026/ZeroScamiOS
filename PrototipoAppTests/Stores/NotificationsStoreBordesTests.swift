//
//  NotificationsStoreBordesTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct NotificationsStoreBordesTests {
    let e = EntornoPrueba()
    let secretos = MemorySecretStore()
    let notificador = NotificadorPrueba()
    let expiraciones = RegistroExpiraciones()
    let store: NotificationsStore

    init() async throws {
        let e = self.e
        let secretos = self.secretos
        let expiraciones = self.expiraciones
        store = NotificationsStore(backend: e.backend(secretos), notificador: notificador) { expiraciones.errores.append($0) }
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
    }

    @Test func dosCargasSimultaneasAvisanUnaSolaVez() async {
        async let a: Void = store.cargar(avisar: true)
        async let b: Void = store.cargar(avisar: true)
        _ = await (a, b)
        #expect(notificador.avisos.withLock { $0 }.count == 1)
    }

    @Test func sesionVencidaAvisaAlExpirar() async throws {
        try secretos.borrar(.accessToken)
        await store.cargar(avisar: true)
        #expect(expiraciones.errores == [.sesionExpirada])
        #expect(notificador.avisos.withLock { $0 }.isEmpty)
    }

    @Test func marcarLeidasConSesionVencidaAvisaYNoToca() async throws {
        await store.cargar(avisar: false)
        try secretos.borrar(.accessToken)
        await store.marcarLeidas([502])
        #expect(expiraciones.errores == [.sesionExpirada])
        #expect(store.sinLeer == 1)
    }

    @Test func marcarLeidasSinIdsNoHaceNada() async {
        await store.cargar(avisar: false)
        await store.marcarLeidas([])
        #expect(store.sinLeer == 1)
    }

    @Test func reiniciarLimpiaLaListaYVuelveAAvisar() async {
        await store.cargar(avisar: true)
        store.reiniciar()
        #expect(store.lista == .cargando)
        #expect(store.sinLeer == 0)
        await store.cargar(avisar: true)   // otra persona en el mismo teléfono
        #expect(notificador.avisos.withLock { $0 }.count == 2)
    }

    @Test func reiniciarDescartaLaRespuestaQueEstabaEnCamino() async {
        let puerta = Puerta()
        let retenido = NotificationsStore(backend: BackendConPuerta(base: e.backend(secretos), puerta: puerta),
                                          notificador: notificador) { _ in }
        let tarea = Task { await retenido.cargar(avisar: true) }
        await puerta.esperarLlegada()
        retenido.reiniciar()
        await puerta.abrir()
        await tarea.value
        #expect(retenido.lista == .cargando)
        #expect(notificador.avisos.withLock { $0 }.isEmpty)
    }

    @Test func pedirPermisoUsaElNotificador() async {
        #expect(await store.pedirPermiso())
    }
}
