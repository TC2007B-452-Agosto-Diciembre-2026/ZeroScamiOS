//
//  AdminStoreBordesTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct AdminStoreBordesTests {
    let e = EntornoPrueba()
    let secretos = MemorySecretStore()
    let expiraciones = RegistroExpiraciones()

    private func tienda(_ cuenta: (correo: String, contrasena: String)) async throws -> AdminStore {
        try secretos.guardar(try await e.token(cuenta), para: .accessToken)
        let expiraciones = self.expiraciones
        return AdminStore(backend: e.backend(secretos)) { expiraciones.errores.append($0) }
    }

    @Test func elOwnerVeLosUsuariosYCambiaRolesYEstados() async throws {
        let admin = try await tienda(EntornoPrueba.owner)
        await admin.cargarUsuarios()
        #expect(admin.usuarios.valor?.count == 6)
        try await admin.cambiarRol(idUsuario: DemoSeed.idUsuario, a: .administrador)
        #expect(admin.usuarios.valor?.first { $0.id == DemoSeed.idUsuario }?.rol == .administrador)
        try await admin.cambiarEstadoCuenta(idUsuario: DemoSeed.idTecno, a: .suspendido)
        #expect(admin.usuarios.valor?.first { $0.id == DemoSeed.idTecno }?.estadoCuenta == .suspendido)
    }

    @Test func unAdministradorNoVeLosUsuarios() async throws {
        let admin = try await tienda(EntornoPrueba.admin)
        await admin.cargarUsuarios()
        #expect(admin.usuarios == .error("No tienes permiso para hacer esto."))
        await #expect(throws: AppError.sinPermiso) { try await admin.cambiarRol(idUsuario: DemoSeed.idUsuario, a: .administrador) }
        #expect(expiraciones.errores.isEmpty)
    }

    @Test func sesionVencidaAvisaAlExpirar() async throws {
        let admin = try await tienda(EntornoPrueba.admin)
        e.reloj.avanzar(7 * 24 * 3_600 + 1)
        await admin.cargarCola(estado: nil)
        #expect(admin.cola == .error(AppError.sesionExpirada.mensaje()))
        #expect(expiraciones.errores == [.sesionExpirada])
    }

    @Test func moderarUnReporteQueYaNoExisteNoCierraLaSesion() async throws {
        let admin = try await tienda(EntornoPrueba.admin)
        await #expect(throws: AppError.noEncontrado) {
            _ = try await admin.cambiarEstado(id: 99_999, a: .enRevision, riesgo: nil, observaciones: "")
        }
        #expect(expiraciones.errores.isEmpty)
    }

    @Test func reiniciarLimpiaTodo() async throws {
        let admin = try await tienda(EntornoPrueba.owner)
        await admin.cargarCola(estado: nil)
        await admin.cargarUsuarios()
        admin.reiniciar()
        #expect(admin.cola == .cargando)
        #expect(admin.usuarios == .cargando)
        #expect(admin.analiticas.isEmpty)
    }

    @Test func reiniciarDescartaLaRespuestaQueEstabaEnCamino() async throws {
        try secretos.guardar(try await e.token(EntornoPrueba.admin), para: .accessToken)
        let puerta = Puerta()
        let admin = AdminStore(backend: BackendConPuerta(base: e.backend(secretos), puerta: puerta)) { _ in }
        let tarea = Task { await admin.cargarCola(estado: nil) }
        await puerta.esperarLlegada()
        admin.reiniciar()
        await puerta.abrir()
        await tarea.value
        #expect(admin.cola == .cargando)
    }

    @Test func restablecerDemoVuelveALaSemillaYCierraLaSesionDelOwner() async throws {
        let admin = try await tienda(EntornoPrueba.owner)
        try await admin.restablecerDemo()
        await admin.cargarUsuarios()
        #expect(admin.usuarios == .error(AppError.sesionExpirada.mensaje()))
        #expect(expiraciones.errores == [.sesionExpirada])
    }
}
