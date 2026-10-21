//
//  DemoServerCuentaTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerCuentaTests {
    let e = EntornoPrueba()

    // MARK: Perfil

    @Test func perfilSeActualizaYNoRepiteAlias() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = PerfilDatos(desde: try await e.servidor.usuarioActual(token))
        d.biografia = "Reviso tiendas en línea."
        #expect(try await e.servidor.actualizarPerfil(token: token, d).biografia == "Reviso tiendas en línea.")
        d.alias = "tecno_mx"
        await #expect(throws: AppError.conflicto("Ese nombre de usuario ya está en uso.")) {
            _ = try await e.servidor.actualizarPerfil(token: token, d)
        }
    }

    @Test func cambiarCorreoPideLaContrasena() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = PerfilDatos(desde: try await e.servidor.usuarioActual(token))
        d.correo = "ana.nueva@comunidad.test"
        await #expect(throws: AppError.self) { _ = try await e.servidor.actualizarPerfil(token: token, d) }
        d.contrasenaActual = "equivocada1"
        await #expect(throws: AppError.validacion(["La contraseña no es correcta."])) {
            _ = try await e.servidor.actualizarPerfil(token: token, d)
        }
        d.contrasenaActual = EntornoPrueba.usuario.contrasena
        #expect(try await e.servidor.actualizarPerfil(token: token, d).correo == "ana.nueva@comunidad.test")
    }

    @Test func exportarIncluyeMisDatosPeroNoElHash() async throws {
        let datos = try await e.servidor.exportarMisDatos(token: try await e.token(EntornoPrueba.usuario))
        let texto = String(decoding: datos, as: UTF8.self)
        #expect(texto.contains("usuario_01"))
        #expect(texto.contains("Llamada de supuesto banco pidiendo código"))
        #expect(!texto.contains("pbkdf2"))
    }

    @Test func eliminarCuentaAnonimizaLoPublicoYBorraLoDemas() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        try await e.servidor.eliminarCuenta(token: token, contrasena: EntornoPrueba.usuario.contrasena)
        let otro = try await e.nuevaCuenta()
        let publico = try await e.servidor.detalle(token: otro, id: 122)
        #expect(publico.autor.nombre == "Cuenta eliminada")
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.detalle(token: admin, id: 123) }
        await #expect(throws: AppError.credencialesInvalidas) { _ = try await e.token(EntornoPrueba.usuario) }
        #expect(await e.servidor.db.guardados.filter { $0.idUsuario == DemoSeed.idUsuario }.isEmpty)
    }

    @Test func elOwnerNoSePuedeEliminar() async throws {
        let token = try await e.token(EntornoPrueba.owner)
        await #expect(throws: AppError.self) { try await e.servidor.eliminarCuenta(token: token, contrasena: EntornoPrueba.owner.contrasena) }
    }

    // MARK: Notificaciones

    @Test func notificacionesSoloLasMiasYSeMarcanLeidas() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        #expect(try await e.servidor.notificaciones(token: token).map(\.id) == [502, 501])
        try await e.servidor.marcarLeidas(token: token, [502, 999])
        #expect(try await e.servidor.notificaciones(token: token).allSatisfy(\.leida))
        #expect(try await e.servidor.notificaciones(token: try await e.nuevaCuenta()).isEmpty)
    }

    // MARK: Moderación

    @Test func laColaEsSoloParaStaffYEmpiezaPorLoMasViejo() async throws {
        await #expect(throws: AppError.sinPermiso) {
            _ = try await e.servidor.colaModeracion(token: try await e.token(EntornoPrueba.usuario), estado: nil)
        }
        let cola = try await e.servidor.colaModeracion(token: try await e.token(EntornoPrueba.admin), estado: nil)
        #expect(cola.map(\.id) == [118, 119, 121, 117, 123])
    }

    @Test func moderarSigueLaMaquinaDeEstadosYAvisaAlAutor() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.conflicto("No se puede pasar de RECIBIDO a VALIDADO.")) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .validado, riesgo: .alto, observaciones: "")
        }
        _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .enRevision, riesgo: nil, observaciones: "")
        await #expect(throws: AppError.validacion(["Asigna un nivel de riesgo para validar."])) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .validado, riesgo: nil, observaciones: "")
        }
        let r = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .validado, riesgo: .alto, observaciones: "Número confirmado por otros reportes.")
        #expect(r.estado == .validado)
        #expect(r.nivelRiesgo == .alto)
        let usuario = try await e.token(EntornoPrueba.usuario)
        #expect(try await e.servidor.feed(token: usuario, filtro: FiltroBusqueda()).contains { $0.id == 123 })
        let avisos = try await e.servidor.notificaciones(token: usuario).map(\.mensaje)
        #expect(avisos.contains("Tu reporte «Llamada de supuesto banco pidiendo código» fue VALIDADO y ya es visible para la comunidad."))
    }

    @Test func rechazarExigeMotivo() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.validacion(["Explica el motivo del rechazo (10 a 500 caracteres)."])) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 117, a: .rechazado, riesgo: nil, observaciones: "no")
        }
        _ = try await e.servidor.cambiarEstado(token: admin, id: 117, a: .rechazado, riesgo: nil, observaciones: "El enlace ya no existe y no hay captura.")
    }

    @Test func nadieModeraSuPropioReporte() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        let r = try await e.servidor.crear(token: admin, DemoServerReportesTests.borrador())
        await #expect(throws: AppError.conflicto("No puedes moderar tu propio reporte.")) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: r.id, a: .enRevision, riesgo: nil, observaciones: "")
        }
    }

    @Test func validarActualizaElRiesgoDelSitio() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        let r = try await e.servidor.cambiarEstado(token: admin, id: 121, a: .validado, riesgo: .muyAlto, observaciones: "")
        #expect(r.sitio?.nivelRiesgoGlobal == .muyAlto)
        #expect(r.sitio?.fechaUltimaEvaluacion == EntornoPrueba.inicio)
    }

    @Test func staffVeLaEvidenciaYLaComunidadSoloElConteo() async throws {
        let autor = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try e.archivos.guardarTemporal(Data([0xFF, 0xD8, 0xFF, 0xE0]), tipo: "image/jpeg")]
        let creado = try await e.servidor.crear(token: autor, b)
        let admin = try await e.token(EntornoPrueba.admin)
        _ = try await e.servidor.cambiarEstado(token: admin, id: creado.id, a: .enRevision, riesgo: nil, observaciones: "")
        _ = try await e.servidor.cambiarEstado(token: admin, id: creado.id, a: .validado, riesgo: .medio, observaciones: "")
        let comunidad = try await e.servidor.detalle(token: try await e.nuevaCuenta(alias: "prueba_02", correo: "dos@comunidad.test"), id: creado.id)
        #expect(comunidad.evidencias.isEmpty)
        #expect(comunidad.totalEvidencias == 1)
        #expect(try await e.servidor.detalle(token: admin, id: creado.id).evidencias.count == 1)
    }

    // MARK: Owner

    @Test func soloElOwnerVeUsuarios() async throws {
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.usuarios(token: try await e.token(EntornoPrueba.admin)) }
        #expect(try await e.servidor.usuarios(token: try await e.token(EntornoPrueba.owner)).count == 6)
    }

    @Test func elOwnerNoCreaOtroOwnerNiSeTocaASiMismo() async throws {
        let owner = try await e.token(EntornoPrueba.owner)
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.cambiarRol(token: owner, idUsuario: 3, a: .owner) }
        await #expect(throws: AppError.self) { _ = try await e.servidor.cambiarRol(token: owner, idUsuario: 1, a: .usuario) }
        #expect(try await e.servidor.cambiarRol(token: owner, idUsuario: 3, a: .administrador).rol == .administrador)
    }

    @Test func suspenderRevocaLasSesiones() async throws {
        let usuario = try await e.token(EntornoPrueba.usuario)
        _ = try await e.servidor.cambiarEstadoCuenta(token: try await e.token(EntornoPrueba.owner), idUsuario: 3, a: .suspendido)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(usuario) }
        await #expect(throws: AppError.cuentaSuspendida) { _ = try await e.token(EntornoPrueba.usuario) }
    }

    @Test func analiticasSonContadoresYRespetanLaPreferencia() async throws {
        let usuario = try await e.token(EntornoPrueba.usuario)
        _ = try await e.servidor.feed(token: usuario, filtro: FiltroBusqueda(texto: "banco"))
        var p = try await e.servidor.usuarioActual(usuario).preferencias
        p.analiticas = false
        _ = try await e.servidor.actualizarPreferencias(token: usuario, p, contrasena: nil)
        _ = try await e.servidor.feed(token: usuario, filtro: FiltroBusqueda(texto: "sat"))
        let a = try await e.servidor.analiticas(token: try await e.token(EntornoPrueba.owner))
        #expect(a["busqueda"] == 1)
    }

    @Test func restablecerVuelveALaSemillaYCierraSesiones() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .enRevision, riesgo: nil, observaciones: "")
        let owner = try await e.token(EntornoPrueba.owner)
        try await e.servidor.restablecerDemo(token: owner)
        #expect(await e.servidor.db.reportes.first { $0.id == 123 }?.estado == .recibido)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(owner) }
    }
}
