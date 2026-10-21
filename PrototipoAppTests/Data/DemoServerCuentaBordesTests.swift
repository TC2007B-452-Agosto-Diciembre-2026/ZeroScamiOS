//
//  DemoServerCuentaBordesTests.swift
//  PrototipoAppTests
//
//  Bordes de cuenta, moderación y Owner en el servidor Demo: reautenticación con límite de
//  intentos, guardado que falla (nada se pierde ni se adelanta), anonimización completa al
//  eliminar la cuenta, permisos por rol y contadores de disco en el límite.
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerCuentaBordesTests {
    let e = EntornoPrueba()

    /// Hace que guardar falle: en el lugar del archivo de la base pone un directorio con algo dentro.
    private func romperElDisco() throws {
        let archivo = DemoAlmacen(carpeta: e.carpeta).archivo
        try? FileManager.default.removeItem(at: archivo)
        try FileManager.default.createDirectory(at: archivo, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: archivo.appending(path: "x"))
    }

    private func existe(_ ruta: String) -> Bool {
        FileManager.default.fileExists(atPath: e.archivos.carpeta.appending(path: ruta).path(percentEncoded: false))
    }

    private func adjuntoJPEG() throws -> Adjunto {
        try e.archivos.guardarTemporal(Data([0xFF, 0xD8, 0xFF, 0xE0]), tipo: "image/jpeg")
    }

    private func textoDeLaBase() async throws -> String {
        String(decoding: try JSONEncoder().encode(await e.servidor.db), as: UTF8.self)
    }

    private func perfilConCorreoNuevo(_ token: String, _ correo: String = "ana.nueva@comunidad.test") async throws -> PerfilDatos {
        var d = PerfilDatos(desde: try await e.servidor.usuarioActual(token))
        d.correo = correo
        return d
    }

    // MARK: - Perfil

    @Test func contrasenaEquivocadaAlCambiarCorreoCuentaIntentosYBloquea() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = try await perfilConCorreoNuevo(token)
        d.contrasenaActual = "equivocada1"
        for _ in 1..<LimiteIntentos.intentosPermitidos {
            await #expect(throws: AppError.validacion(["La contraseña no es correcta."])) {
                _ = try await e.servidor.actualizarPerfil(token: token, d)
            }
        }
        // El quinto fallo bloquea; con el bloqueo puesto ni la contraseña buena se verifica.
        await #expect(throws: AppError.cuentaBloqueada(hasta: EntornoPrueba.inicio.addingTimeInterval(LimiteIntentos.bloqueoBase))) {
            _ = try await e.servidor.actualizarPerfil(token: token, d)
        }
        d.contrasenaActual = EntornoPrueba.usuario.contrasena
        await #expect(throws: AppError.cuentaBloqueada(hasta: EntornoPrueba.inicio.addingTimeInterval(LimiteIntentos.bloqueoBase))) {
            _ = try await e.servidor.actualizarPerfil(token: token, d)
        }
        #expect(try await e.servidor.usuarioActual(token).correo == EntornoPrueba.usuario.correo)
    }

    @Test func unaContrasenaGiganteNoSeMandaAlHash() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = try await perfilConCorreoNuevo(token)
        d.contrasenaActual = String(repeating: "a", count: DemoServer.contrasenaMaximaEscalares + 1)
        await #expect(throws: AppError.validacion(["La contraseña no es correcta."])) {
            _ = try await e.servidor.actualizarPerfil(token: token, d)
        }
    }

    @Test func elCorreoDeOtraCuentaNoSePuedeTomar() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = try await perfilConCorreoNuevo(token, "LUIS@comunidad.test ")
        d.contrasenaActual = EntornoPrueba.usuario.contrasena
        await #expect(throws: AppError.conflicto("Ese correo ya tiene una cuenta.")) {
            _ = try await e.servidor.actualizarPerfil(token: token, d)
        }
    }

    @Test func cambiarElCorreoReiniciaLosFallosPreviosYNoDejaElViejo() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = try await perfilConCorreoNuevo(token)
        d.contrasenaActual = "equivocada1"
        await #expect(throws: AppError.self) { _ = try await e.servidor.actualizarPerfil(token: token, d) }
        #expect(await e.servidor.db.intentos[EntornoPrueba.usuario.correo] != nil)
        d.contrasenaActual = EntornoPrueba.usuario.contrasena
        _ = try await e.servidor.actualizarPerfil(token: token, d)
        #expect(await e.servidor.db.intentos[EntornoPrueba.usuario.correo] == nil)
        #expect(!(try await textoDeLaBase()).contains(EntornoPrueba.usuario.correo))
    }

    @Test func elPerfilInvalidoSeRechazaYLoSanitizadoSeGuarda() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = PerfilDatos(desde: try await e.servidor.usuarioActual(token))
        d.nombre = "A"
        d.pais = "Narnia"
        d.biografia = String(repeating: "x", count: 301)
        await #expect(throws: AppError.self) { _ = try await e.servidor.actualizarPerfil(token: token, d) }
        d = PerfilDatos(desde: try await e.servidor.usuarioActual(token))
        d.nombre = "  Ana\u{0007}  María "
        d.biografia = "Línea 1\u{0000}\nLínea 2"
        let u = try await e.servidor.actualizarPerfil(token: token, d)
        #expect(u.nombre == "Ana María")
        #expect(!u.biografia.contains("\u{0000}"))
    }

    @Test func actualizarPerfilConGuardadoFallidoNoCambiaNada() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = PerfilDatos(desde: try await e.servidor.usuarioActual(token))
        d.biografia = "Esto no debe quedar"
        try romperElDisco()
        await #expect(throws: (any Error).self) { _ = try await e.servidor.actualizarPerfil(token: token, d) }
        #expect(try await e.servidor.usuarioActual(token).biografia == "Me interesa alertar sobre compras en línea.")
    }

    // MARK: - Avatar

    @Test func elAvatarSeVeSegunLaPrivacidadYSeReemplazaSinDejarArchivos() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let primero = try await e.servidor.actualizarAvatar(token: token, try adjuntoJPEG())
        let ruta1 = try #require(primero.avatarRuta)
        #expect(existe(ruta1))
        let yo = try await e.servidor.usuarioActual(token)
        #expect(try await e.servidor.datosAvatar(token: token, de: yo) != nil)
        // Perfil privado: la comunidad no lo ve; el staff sí.
        #expect(try await e.servidor.datosAvatar(token: try await e.nuevaCuenta(), de: yo) == nil)
        #expect(try await e.servidor.datosAvatar(token: try await e.token(EntornoPrueba.admin), de: yo) != nil)
        let segundo = try await e.servidor.actualizarAvatar(token: token, try adjuntoJPEG())
        let ruta2 = try #require(segundo.avatarRuta)
        #expect(ruta1 != ruta2)
        #expect(!existe(ruta1))
        #expect(existe(ruta2))
        #expect(try await e.servidor.actualizarAvatar(token: token, nil).avatarRuta == nil)
        #expect(!existe(ruta2))
    }

    @Test func elAvatarSoloAceptaJPEGConSuExtension() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let pdf = try e.archivos.guardarTemporal(Data("%PDF-1.4".utf8), tipo: "application/pdf")
        await #expect(throws: AppError.validacion(["El avatar debe ser una imagen."])) {
            _ = try await e.servidor.actualizarAvatar(token: token, pdf)
        }
        // Tipo de imagen pero nombre de PDF: el cliente miente.
        let disfrazado = Adjunto(id: pdf.id, nombreArchivo: pdf.nombreArchivo, tipoArchivo: "image/jpeg", bytes: pdf.bytes)
        await #expect(throws: AppError.validacion(["El avatar debe ser una imagen."])) {
            _ = try await e.servidor.actualizarAvatar(token: token, disfrazado)
        }
        #expect(try await e.servidor.usuarioActual(token).avatarRuta == nil)
    }

    @Test func avatarConGuardadoFallidoConservaElAnteriorYNoDejaHuerfano() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let ruta1 = try #require(try await e.servidor.actualizarAvatar(token: token, try adjuntoJPEG()).avatarRuta)
        let nuevo = try adjuntoJPEG()
        try romperElDisco()
        await #expect(throws: (any Error).self) { _ = try await e.servidor.actualizarAvatar(token: token, nuevo) }
        #expect(existe(ruta1))
        #expect(!existe(nuevo.nombreArchivo))
        #expect(try await e.servidor.usuarioActual(token).avatarRuta == ruta1)
    }

    // MARK: - Exportar

    @Test func exportarNoIncluyeDatosDeOtrasPersonas() async throws {
        let datos = try await e.servidor.exportarMisDatos(token: try await e.token(EntornoPrueba.usuario))
        let texto = String(decoding: datos, as: UTF8.self)
        _ = try JSONSerialization.jsonObject(with: datos)
        #expect(texto.contains("usuario@0fraude.mx"))
        #expect(!texto.contains("contrasenaHash"))
        #expect(!texto.contains("vecina_alerta"))     // comenta en uno de mis reportes, pero no es mío
        #expect(!texto.contains("luis@comunidad.test"))
        #expect(!texto.contains("tokenHash"))
    }

    // MARK: - Eliminar cuenta

    @Test func eliminarConContrasenaEquivocadaNoBorraNadaYCuentaIntentos() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        for _ in 1..<LimiteIntentos.intentosPermitidos {
            await #expect(throws: AppError.validacion(["La contraseña no es correcta."])) {
                try await e.servidor.eliminarCuenta(token: token, contrasena: "equivocada1")
            }
        }
        await #expect(throws: AppError.cuentaBloqueada(hasta: EntornoPrueba.inicio.addingTimeInterval(LimiteIntentos.bloqueoBase))) {
            try await e.servidor.eliminarCuenta(token: token, contrasena: "equivocada1")
        }
        // Bloqueado: ni la contraseña buena sirve hasta que pase el tiempo.
        await #expect(throws: AppError.cuentaBloqueada(hasta: EntornoPrueba.inicio.addingTimeInterval(LimiteIntentos.bloqueoBase))) {
            try await e.servidor.eliminarCuenta(token: token, contrasena: EntornoPrueba.usuario.contrasena)
        }
        #expect(try await e.servidor.usuarioActual(token).alias == "usuario_01")
        #expect(try await e.servidor.misReportes(token: token).count == 3)
        e.reloj.avanzar(LimiteIntentos.bloqueoBase + 1)
        try await e.servidor.eliminarCuenta(token: token, contrasena: EntornoPrueba.usuario.contrasena)
    }

    @Test func eliminarSinContrasenaOGigantePideConfirmarSinCrashear() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        await #expect(throws: AppError.self) {
            try await e.servidor.eliminarCuenta(token: token, contrasena: String(repeating: "z", count: 5_000))
        }
        #expect(try await e.servidor.usuarioActual(token).alias == "usuario_01")
    }

    @Test func eliminarDejaLoPublicoSinRastroYBorraEvidenciaYAvatarDeDisco() async throws {
        let token = try await e.nuevaCuenta()
        let propio = await e.servidor.db.usuarios.first { $0.usuario.alias == "prueba_01" }?.usuario.id
        let avatar = try #require(try await e.servidor.actualizarAvatar(token: token, try adjuntoJPEG()).avatarRuta)
        var publico = DemoServerReportesTests.borrador(titulo: "Reporte que se valida después", enlace: "https://sitio-publico.example/x")
        publico.afectado = .otraPersona
        publico.persona = PersonaAfectada(nombre: "Tomasa Quispe", contacto: "rosa@comunidad.test", autorizo: true)
        publico.adjuntos = [try adjuntoJPEG()]
        let creadoPublico = try await e.servidor.crear(token: token, publico)
        var privado = DemoServerReportesTests.borrador(titulo: "Reporte que se queda en revisión", enlace: "https://sitio-privado.example/y")
        privado.adjuntos = [try adjuntoJPEG()]
        let creadoPrivado = try await e.servidor.crear(token: token, privado)
        let rutaPublica = try #require(creadoPublico.evidencias.first?.rutaArchivo)
        let rutaPrivada = try #require(creadoPrivado.evidencias.first?.rutaArchivo)
        let admin = try await e.token(EntornoPrueba.admin)
        _ = try await e.servidor.cambiarEstado(token: admin, id: creadoPublico.id, a: .enRevision, riesgo: nil, observaciones: "")
        _ = try await e.servidor.cambiarEstado(token: admin, id: creadoPublico.id, a: .validado, riesgo: .medio, observaciones: "")
        _ = try await e.servidor.comentar(token: token, id: 101, texto: "Yo también vi este sitio.")
        #expect(existe(rutaPublica) && existe(rutaPrivada) && existe(avatar))

        try await e.servidor.eliminarCuenta(token: token, contrasena: "Segura#2026x")

        #expect(!existe(rutaPublica) && !existe(rutaPrivada) && !existe(avatar))
        let db = await e.servidor.db
        let fila = try #require(db.reportes.first { $0.id == creadoPublico.id })
        #expect(fila.idUsuario == nil && fila.persona == nil && fila.esAnonimo)
        #expect(!db.reportes.contains { $0.id == creadoPrivado.id })
        #expect(!db.sitios.contains { $0.url.contains("sitio-privado") })
        #expect(!db.evidencias.contains { $0.idReporte == creadoPublico.id || $0.idReporte == creadoPrivado.id })
        #expect(!db.sesiones.contains { $0.idUsuario == propio })
        #expect(!db.notificaciones.contains { $0.idUsuario == propio })
        let comentario = try #require(db.comentarios.first { $0.texto == "Yo también vi este sitio." })
        #expect(comentario.idUsuario == nil)
        // Nada que identifique a la persona queda en la base: ni correo, ni alias, ni la persona afectada.
        let texto = try await textoDeLaBase()
        for rastro in ["prueba@comunidad.test", "prueba_01", "Tomasa Quispe", "rosa@comunidad.test"] {
            #expect(!texto.contains(rastro), "Quedó rastro: \(rastro)")
        }
        // La comunidad ve el reporte como de una cuenta eliminada, sin persona afectada ni evidencia.
        let otro = try await e.nuevaCuenta(alias: "prueba_02", correo: "dos@comunidad.test")
        let visto = try await e.servidor.detalle(token: otro, id: creadoPublico.id)
        #expect(visto.autor.nombre == "Cuenta eliminada" && visto.autor.idUsuario == nil)
        #expect(visto.personaAfectada == nil && visto.evidencias.isEmpty && visto.totalEvidencias == 0)
        #expect(try await e.servidor.comentarios(token: otro, id: 101).contains { $0.autor == "Cuenta eliminada" })
        // Nadie puede entrar con esa cuenta ni con su token.
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(token) }
    }

    @Test func eliminarCierraTodasLasSesionesDeLaCuenta() async throws {
        let primera = try await e.token(EntornoPrueba.usuario)
        let segunda = try await e.token(EntornoPrueba.usuario)
        try await e.servidor.eliminarCuenta(token: primera, contrasena: EntornoPrueba.usuario.contrasena)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(segunda) }
    }

    @Test func eliminarConGuardadoFallidoNoPierdeNadaNiLaEvidencia() async throws {
        let token = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: token, b)
        let ruta = try #require(r.evidencias.first?.rutaArchivo)
        let avatar = try #require(try await e.servidor.actualizarAvatar(token: token, try adjuntoJPEG()).avatarRuta)
        try romperElDisco()
        await #expect(throws: (any Error).self) { try await e.servidor.eliminarCuenta(token: token, contrasena: "Segura#2026x") }
        #expect(existe(ruta) && existe(avatar))
        #expect(try await e.servidor.detalle(token: token, id: r.id).id == r.id)
        #expect(try await e.servidor.usuarioActual(token).avatarRuta == avatar)
    }

    @Test func unAdministradorPuedeEliminarSuCuentaYSuHistorialQuedaSinNombre() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        try await e.servidor.eliminarCuenta(token: admin, contrasena: EntornoPrueba.admin.contrasena)
        let owner = try await e.token(EntornoPrueba.owner)
        let historial = try await e.servidor.historial(token: owner, id: 121)
        #expect(historial.contains { $0.responsable == "Cuenta eliminada" })
        #expect(!(try await textoDeLaBase()).contains("admin@0fraude.mx"))
    }

    @Test func elOwnerQueFallaAlEliminarConservaSusSesiones() async throws {
        let owner = try await e.token(EntornoPrueba.owner)
        await #expect(throws: AppError.conflicto("La cuenta Owner no se puede eliminar desde la app.")) {
            try await e.servidor.eliminarCuenta(token: owner, contrasena: EntornoPrueba.owner.contrasena)
        }
        #expect(try await e.servidor.usuarioActual(owner).rol == .owner)
    }

    // MARK: - Notificaciones

    @Test func marcarLeidasIgnoraAjenasYAguantaListasGrandes() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let ajena = await e.servidor.db.notificaciones.count
        let otra = try await e.token(EntornoPrueba.admin)
        let muchas = (0..<20_000).map { Int64($0) } + [Int64.max, Int64.min, 502, 502]
        try await e.servidor.marcarLeidas(token: token, muchas)
        #expect(try await e.servidor.notificaciones(token: token).allSatisfy(\.leida))
        #expect(await e.servidor.db.notificaciones.count == ajena)
        #expect(try await e.servidor.notificaciones(token: otra).isEmpty)
    }

    @Test func marcarLeidasConGuardadoFallidoNoCambiaNada() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        try romperElDisco()
        await #expect(throws: (any Error).self) { try await e.servidor.marcarLeidas(token: token, [502]) }
        #expect(try await e.servidor.notificaciones(token: token).contains { !$0.leida })
    }

    // MARK: - Moderación

    @Test func laColaFiltraPorEstadoYElOwnerTambienModera() async throws {
        let owner = try await e.token(EntornoPrueba.owner)
        let rechazados = try await e.servidor.colaModeracion(token: owner, estado: .rechazado)
        #expect(rechazados.map(\.id) == [120])
        let validados = try await e.servidor.colaModeracion(token: owner, estado: .validado)
        #expect(validados.allSatisfy { $0.estado == .validado })
        _ = try await e.servidor.cambiarEstado(token: owner, id: 119, a: .enRevision, riesgo: nil, observaciones: "")
    }

    @Test func unUsuarioNoModeraNadaYUnIdInexistenteNoExiste() async throws {
        let usuario = try await e.token(EntornoPrueba.usuario)
        await #expect(throws: AppError.sinPermiso) {
            _ = try await e.servidor.cambiarEstado(token: usuario, id: 117, a: .enRevision, riesgo: nil, observaciones: "")
        }
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.noEncontrado) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 99_999, a: .enRevision, riesgo: nil, observaciones: "")
        }
    }

    @Test func losEstadosFinalesNoSeMuevenYValidadoSoloSeCanaliza() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.conflicto("No se puede pasar de RECHAZADO a EN REVISIÓN.")) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 120, a: .enRevision, riesgo: nil, observaciones: "")
        }
        await #expect(throws: AppError.conflicto("No se puede pasar de CANALIZADO a VALIDADO.")) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 103, a: .validado, riesgo: .alto, observaciones: "")
        }
        await #expect(throws: AppError.conflicto("No se puede pasar de VALIDADO a RECHAZADO.")) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 101, a: .rechazado, riesgo: nil, observaciones: "Motivo suficientemente largo.")
        }
        let canalizado = try await e.servidor.cambiarEstado(token: admin, id: 101, a: .canalizado, riesgo: nil, observaciones: "")
        #expect(canalizado.estado == .canalizado)
        #expect(canalizado.nivelRiesgo == .alto)   // canalizar no toca el riesgo
    }

    @Test func validarExigeUnRiesgoRealYNoDejaMediasTintas() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .enRevision, riesgo: nil, observaciones: "")
        await #expect(throws: AppError.validacion(["Asigna un nivel de riesgo para validar."])) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .validado, riesgo: .noEvaluado, observaciones: "")
        }
        #expect(await e.servidor.db.reportes.first { $0.id == 123 }?.estado == .enRevision)
    }

    @Test func lasObservacionesSeSanitizanSeAcotanYElAutorRecibeSoloSuAviso() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        let largo = "Sin enlace\u{0007} verificable. " + String(repeating: "x", count: 700)
        _ = try await e.servidor.cambiarEstado(token: admin, id: 117, a: .rechazado, riesgo: nil, observaciones: largo)
        let guardada = try #require(await e.servidor.db.historial.last { $0.idReporte == 117 }?.observaciones)
        #expect(guardada.count <= 500)
        #expect(!guardada.contains("\u{0007}"))
        // El aviso de rechazo lleva el motivo para la propia autora, y nada de otras personas.
        let aviso = try #require(await e.servidor.db.notificaciones.last { $0.idReporte == 117 }?.mensaje)
        #expect(aviso.hasPrefix("Tu reporte «Mensaje de paquetería para pagar envío» fue RECHAZADO. Motivo: "))
        #expect(!aviso.contains(EntornoPrueba.admin.correo) && !aviso.contains("admin_zs"))
        #expect(await e.servidor.db.notificaciones.last { $0.idReporte == 117 }?.idUsuario == DemoSeed.idVecina)
    }

    @Test func moderarConGuardadoFallidoNoCambiaEstadoHistorialNiAvisos() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        let historial = await e.servidor.db.historial.count
        let avisos = await e.servidor.db.notificaciones.count
        try romperElDisco()
        await #expect(throws: (any Error).self) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .enRevision, riesgo: nil, observaciones: "")
        }
        #expect(await e.servidor.db.reportes.first { $0.id == 123 }?.estado == .recibido)
        #expect(await e.servidor.db.historial.count == historial)
        #expect(await e.servidor.db.notificaciones.count == avisos)
    }

    @Test func moderarUnReporteCuyoAutorYaNoExisteNoAvisaANadie() async throws {
        let autor = try await e.nuevaCuenta()
        let r = try await e.servidor.crear(token: autor, DemoServerReportesTests.borrador())
        let admin = try await e.token(EntornoPrueba.admin)
        _ = try await e.servidor.cambiarEstado(token: admin, id: r.id, a: .enRevision, riesgo: nil, observaciones: "")
        _ = try await e.servidor.cambiarEstado(token: admin, id: r.id, a: .validado, riesgo: .bajo, observaciones: "")
        try await e.servidor.eliminarCuenta(token: autor, contrasena: "Segura#2026x")
        let avisos = await e.servidor.db.notificaciones.count
        _ = try await e.servidor.cambiarEstado(token: admin, id: r.id, a: .canalizado, riesgo: nil, observaciones: "")
        #expect(await e.servidor.db.notificaciones.count == avisos)
    }

    // MARK: - Owner

    @Test func elAdministradorNoGestionaRolesNiCuentas() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.cambiarRol(token: admin, idUsuario: 3, a: .administrador) }
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.cambiarEstadoCuenta(token: admin, idUsuario: 3, a: .suspendido) }
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.cambiarEstadoCuenta(token: admin, idUsuario: 1, a: .suspendido) }
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.analiticas(token: admin) }
        await #expect(throws: AppError.sinPermiso) { try await e.servidor.restablecerDemo(token: admin) }
        let usuario = try await e.token(EntornoPrueba.usuario)
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.usuarios(token: usuario) }
    }

    @Test func elOwnerNoAsignaPoliciaNiInventaUsuariosNiSeSuspendeASiMismo() async throws {
        let owner = try await e.token(EntornoPrueba.owner)
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.cambiarRol(token: owner, idUsuario: 3, a: .policia) }
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.cambiarRol(token: owner, idUsuario: 99_999, a: .usuario) }
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.cambiarEstadoCuenta(token: owner, idUsuario: 99_999, a: .suspendido) }
        await #expect(throws: AppError.conflicto("No puedes suspender tu propia cuenta.")) {
            _ = try await e.servidor.cambiarEstadoCuenta(token: owner, idUsuario: 1, a: .suspendido)
        }
    }

    @Test func unOwnerSembradoComoSegundoOwnerTampocoSeTocaPorOtro() async throws {
        var db = DemoSeed.base(ahora: EntornoPrueba.inicio)
        let i = try #require(db.usuarios.firstIndex { $0.usuario.id == DemoSeed.idAdmin })
        db.usuarios[i].usuario.rol = .owner
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-owner2-\(UUID().uuidString)")
        let almacen = DemoAlmacen(carpeta: carpeta)
        let inicio = EntornoPrueba.inicio
        try almacen.guardar(db)
        let s = DemoServer(almacen: almacen, archivos: ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia")),
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { inicio })
        guard case .sesion(let sesion) = try await s.iniciarSesion(correo: EntornoPrueba.owner.correo, contrasena: EntornoPrueba.owner.contrasena) else {
            Issue.record("Debió abrir sesión")
            return
        }
        await #expect(throws: AppError.sinPermiso) { _ = try await s.cambiarRol(token: sesion.accessToken, idUsuario: DemoSeed.idAdmin, a: .usuario) }
        await #expect(throws: AppError.sinPermiso) { _ = try await s.cambiarEstadoCuenta(token: sesion.accessToken, idUsuario: DemoSeed.idAdmin, a: .suspendido) }
    }

    @Test func suspenderYReactivarFuncionanYElRolCambiaDeInmediato() async throws {
        let owner = try await e.token(EntornoPrueba.owner)
        let admin = try await e.token(EntornoPrueba.admin)
        _ = try await e.servidor.cambiarRol(token: owner, idUsuario: DemoSeed.idAdmin, a: .usuario)
        await #expect(throws: AppError.sinPermiso) {
            _ = try await e.servidor.colaModeracion(token: admin, estado: nil)   // el mismo token ya no modera
        }
        _ = try await e.servidor.cambiarEstadoCuenta(token: owner, idUsuario: DemoSeed.idAdmin, a: .suspendido)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(admin) }
        #expect(await e.servidor.db.sesiones.contains { $0.idUsuario == DemoSeed.idAdmin } == false)
        let reactivado = try await e.servidor.cambiarEstadoCuenta(token: owner, idUsuario: DemoSeed.idAdmin, a: .activo)
        #expect(reactivado.estadoCuenta == .activo)
        _ = try await e.token(EntornoPrueba.admin)
    }

    @Test func suspenderTambienAnulaUnCodigoDeDosPasosPendiente() async throws {
        let usuario = try await e.token(EntornoPrueba.usuario)
        var p = try await e.servidor.usuarioActual(usuario).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: usuario, p, contrasena: nil)
        guard case .requiereCodigo(let desafio) = try await e.servidor.iniciarSesion(correo: EntornoPrueba.usuario.correo,
                                                                                        contrasena: EntornoPrueba.usuario.contrasena)
        else { Issue.record("Debió pedir código"); return }
        _ = try await e.servidor.cambiarEstadoCuenta(token: try await e.token(EntornoPrueba.owner), idUsuario: DemoSeed.idUsuario, a: .suspendido)
        await #expect(throws: AppError.codigoInvalido) {
            _ = try await e.servidor.verificarCodigo(desafio: desafio.id, codigo: desafio.codigoDemo ?? "")
        }
    }

    @Test func suspenderOCambiarRolConGuardadoFallidoNoCambiaNiRevocaNada() async throws {
        let owner = try await e.token(EntornoPrueba.owner)
        let usuario = try await e.token(EntornoPrueba.usuario)
        try romperElDisco()
        await #expect(throws: (any Error).self) { _ = try await e.servidor.cambiarEstadoCuenta(token: owner, idUsuario: 3, a: .suspendido) }
        await #expect(throws: (any Error).self) { _ = try await e.servidor.cambiarRol(token: owner, idUsuario: 3, a: .administrador) }
        let u = try await e.servidor.usuarioActual(usuario)   // la sesión sigue viva
        #expect(u.estadoCuenta == .activo && u.rol == .usuario)
    }

    @Test func lasListasYLasAnaliticasNoRevientanConDatosDeDiscoEnElLimite() async throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-analiticas-\(UUID().uuidString)")
        let almacen = DemoAlmacen(carpeta: carpeta)
        let inicio = EntornoPrueba.inicio
        var db = DemoSeed.base(ahora: EntornoPrueba.inicio)
        db.analiticas = ["maximo": Int.max, "negativo": Int.min, "normal": 4]
        try almacen.guardar(db)
        let s = DemoServer(almacen: almacen, archivos: ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia")),
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { inicio })
        guard case .sesion(let sesion) = try await s.iniciarSesion(correo: EntornoPrueba.owner.correo, contrasena: EntornoPrueba.owner.contrasena) else {
            Issue.record("Debió abrir sesión")
            return
        }
        let a = try await s.analiticas(token: sesion.accessToken)
        #expect(a["maximo"] == Int.max)
        #expect(a["negativo"] == 0)
        #expect(a["normal"] == 4)
    }

    @Test func restablecerBorraLaEvidenciaDeDiscoYPermiteEntrarConLaSemilla() async throws {
        let token = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: token, b)
        let ruta = try #require(r.evidencias.first?.rutaArchivo)
        try await e.servidor.restablecerDemo(token: try await e.token(EntornoPrueba.owner))
        #expect(!existe(ruta))
        #expect(await e.servidor.db.usuarios.count == 6)
        _ = try await e.token(EntornoPrueba.usuario)
    }

    @Test func restablecerConGuardadoFallidoNoCambiaLaBaseNiBorraArchivos() async throws {
        let token = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try adjuntoJPEG()]
        let r = try await e.servidor.crear(token: token, b)
        let ruta = try #require(r.evidencias.first?.rutaArchivo)
        let owner = try await e.token(EntornoPrueba.owner)
        try romperElDisco()
        await #expect(throws: (any Error).self) { try await e.servidor.restablecerDemo(token: owner) }
        #expect(existe(ruta))
        #expect(await e.servidor.db.reportes.contains { $0.id == r.id })
        #expect(try await e.servidor.usuarioActual(owner).rol == .owner)
    }
}
