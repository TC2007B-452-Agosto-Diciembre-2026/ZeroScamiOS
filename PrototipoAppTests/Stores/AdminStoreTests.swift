//
//  AdminStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct AdminStoreTests {
    @Test func unUsuarioNormalVeElErrorDePermiso() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        let admin = AdminStore(backend: e.backend(secretos)) { _ in }
        await admin.cargarCola(estado: nil)
        #expect(admin.cola == .error("No tienes permiso para hacer esto."))
    }

    @Test func elAdministradorVeLaColaYModera() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        try secretos.guardar(try await e.token(EntornoPrueba.admin), para: .accessToken)
        let admin = AdminStore(backend: e.backend(secretos)) { _ in }
        await admin.cargarCola(estado: nil)
        #expect(admin.cola.valor?.count == 5)
        let r = try await admin.cambiarEstado(id: 117, a: .enRevision, riesgo: nil, observaciones: "")
        #expect(r.estado == .enRevision)
    }
}
