//
//  DemoServerBordesTests.swift
//  PrototipoAppTests
//
//  Bordes del servidor Demo: el archivo en disco es un dato externo (contadores en el límite,
//  fila ausente, lectura que falla) y nunca debe detener la app ni borrar datos buenos.
//

import Foundation
import Testing
@testable import PrototipoApp

nonisolated final class InterruptorPrueba: Sendable {
    private let valor: Mutex<Bool>
    init(_ inicial: Bool) { valor = Mutex(inicial) }
    var encendido: Bool { valor.withLock { $0 } }
    func poner(_ nuevo: Bool) { valor.withLock { $0 = nuevo } }
}

struct DemoServerBordesTests {
    /// Servidor que arranca desde un archivo armado a mano (como si viniera de disco manipulado).
    private func servidor(modificando cambio: (inout DemoDatabase) -> Void,
                          hasher: PasswordHasher = PasswordHasher(iteraciones: 1_000))
        throws -> (servidor: DemoServer, carpeta: URL, almacen: DemoAlmacen) {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-bordes-\(UUID().uuidString)")
        let almacen = DemoAlmacen(carpeta: carpeta)
        var db = DemoSeed.base(ahora: EntornoPrueba.inicio)
        cambio(&db)
        try almacen.guardar(db)
        let s = DemoServer(almacen: almacen, archivos: ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia")),
                           hasher: hasher, reloj: { EntornoPrueba.inicio })
        return (s, carpeta, almacen)
    }

    private func conDosPasos(_ e: EntornoPrueba) async throws -> DesafioDosPasos {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        guard case .requiereCodigo(let d) = try await e.servidor.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x") else {
            throw AppError.codigoInvalido
        }
        return d
    }

    // MARK: - Lectura que falla (teléfono bloqueado): no se pisa la base buena

    @Test func unaLecturaFallidaNoSobrescribeLaBaseGuardada() async throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-bordes-\(UUID().uuidString)")
        var db = DemoSeed.base(ahora: EntornoPrueba.inicio)
        db.analiticas["marca"] = 7
        let bueno = DemoAlmacen(carpeta: carpeta)
        try bueno.guardar(db)
        let antes = try Data(contentsOf: bueno.archivo)

        let disponible = InterruptorPrueba(false)
        var almacen = DemoAlmacen(carpeta: carpeta)
        almacen.leer = { url in
            guard disponible.encendido else { throw CocoaError(.fileReadNoPermission) }
            return try Data(contentsOf: url)
        }
        let s = DemoServer(almacen: almacen, archivos: ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia")),
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { EntornoPrueba.inicio })

        // Bloqueado: la operación falla con un error legible y el archivo queda intacto.
        await #expect(throws: AppError.self) { _ = try await s.registrar(EntornoPrueba.datosNuevos()) }
        #expect(try Data(contentsOf: bueno.archivo) == antes)
        #expect(!FileManager.default.fileExists(atPath: carpeta.appending(path: "zeroscam-demo.corrupto.json").path(percentEncoded: false)))

        // Ya desbloqueado: se recupera la base real (con la marca) y la operación sí se guarda.
        disponible.poner(true)
        _ = try await s.registrar(EntornoPrueba.datosNuevos())
        #expect(await s.db.analiticas["marca"] == 7)
        let guardada = try #require(bueno.cargar())
        #expect(guardada.usuarios.contains { $0.usuario.correo == "prueba@comunidad.test" })
        #expect(guardada.analiticas["marca"] == 7)
    }

    @Test func lecturaFallidaSinOperacionesTampocoEscribeAlArrancar() async throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-bordes-\(UUID().uuidString)")
        let bueno = DemoAlmacen(carpeta: carpeta)
        var db = DemoSeed.base(ahora: EntornoPrueba.inicio)
        db.analiticas["marca"] = 7
        try bueno.guardar(db)
        let antes = try Data(contentsOf: bueno.archivo)
        var almacen = DemoAlmacen(carpeta: carpeta)
        almacen.leer = { _ in throw CocoaError(.fileReadNoPermission) }
        _ = DemoServer(almacen: almacen, archivos: ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia")),
                       hasher: PasswordHasher(iteraciones: 1_000), reloj: { EntornoPrueba.inicio })
        #expect(try Data(contentsOf: bueno.archivo) == antes)
    }

    @Test func archivoDanadoSeApartaYElServidorSiembraDeNuevo() async throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-bordes-\(UUID().uuidString)")
        let almacen = DemoAlmacen(carpeta: carpeta)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try Data("{no es json".utf8).write(to: almacen.archivo)
        let s = DemoServer(almacen: almacen, archivos: ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia")),
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { EntornoPrueba.inicio })
        #expect(await s.db.usuarios.count == 6)
        _ = try await s.registrar(EntornoPrueba.datosNuevos())   // y se puede guardar
        #expect(almacen.cargar() != nil)
    }

    @Test func laBaseSobreviveAUnServidorNuevo() async throws {
        let e = EntornoPrueba()
        _ = try await e.nuevaCuenta()
        let otro = DemoServer(almacen: DemoAlmacen(carpeta: e.carpeta), archivos: e.archivos,
                              hasher: PasswordHasher(iteraciones: 1_000), reloj: { EntornoPrueba.inicio })
        #expect(await otro.db.usuarios.contains { $0.usuario.alias == "prueba_01" })
    }

    // MARK: - Contadores en el límite (nada de `+= 1` sobre un Int.max venido de disco)

    @Test func desafioConIntentosEnElMaximoNoTumbaLaApp() async throws {
        let e = EntornoPrueba()
        let d = try await conDosPasos(e)
        // Se arma el mismo archivo con el contador de intentos en Int.max.
        var db = await e.servidor.db
        db.desafios[0].intentos = .max
        try DemoAlmacen(carpeta: e.carpeta).guardar(db)
        let s = DemoServer(almacen: DemoAlmacen(carpeta: e.carpeta), archivos: e.archivos,
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { EntornoPrueba.inicio })
        await #expect(throws: AppError.codigoInvalido) { _ = try await s.verificarCodigo(desafio: d.id, codigo: "000000") }
        #expect(await s.db.desafios.isEmpty)
    }

    @Test func desafioConIntentosNegativosNoDaIntentosDeMas() async throws {
        let e = EntornoPrueba()
        let d = try await conDosPasos(e)
        var db = await e.servidor.db
        db.desafios[0].intentos = -1_000_000
        try DemoAlmacen(carpeta: e.carpeta).guardar(db)
        let s = DemoServer(almacen: DemoAlmacen(carpeta: e.carpeta), archivos: e.archivos,
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { EntornoPrueba.inicio })
        for _ in 1...3 {
            await #expect(throws: AppError.codigoInvalido) { _ = try await s.verificarCodigo(desafio: d.id, codigo: "000000") }
        }
        #expect(await s.db.desafios.isEmpty)
    }

    @Test func analiticaEnElMaximoNoTumbaElLogin() async throws {
        let (s, _, _) = try servidor { $0.analiticas["inicio_sesion"] = .max }
        guard case .sesion = try await s.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena) else {
            Issue.record("Debía iniciar sesión"); return
        }
        #expect(await s.db.analiticas["inicio_sesion"] == .max)
    }

    @Test func intentosFallidosEnElMaximoSoloBloquean() async throws {
        let (s, _, _) = try servidor { $0.intentos["usuario@0fraude.mx"] = RegistroIntentos(fallidos: .max, bloqueadoHasta: nil) }
        await #expect(throws: AppError.self) {
            _ = try await s.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: "malamala123")
        }
        await #expect(throws: AppError.cuentaBloqueada(hasta: EntornoPrueba.inicio.addingTimeInterval(LimiteIntentos.bloqueoMaximo))) {
            _ = try await s.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: EntornoPrueba.usuario.contrasena)
        }
    }

    @Test func bloqueoGuardadoLejanoNoPasaDelMaximo() async throws {
        let lejos = Date(timeIntervalSince1970: 4_000_000_000_000)
        let (s, _, _) = try servidor { $0.intentos["usuario@0fraude.mx"] = RegistroIntentos(fallidos: 9, bloqueadoHasta: lejos) }
        await #expect(throws: AppError.cuentaBloqueada(hasta: EntornoPrueba.inicio.addingTimeInterval(LimiteIntentos.bloqueoMaximo))) {
            _ = try await s.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: EntornoPrueba.usuario.contrasena)
        }
    }

    @Test func confirmacionesPreviasEnElMaximoSeSaturan() async throws {
        let (s, _, _) = try servidor { db in
            if let i = db.reportes.firstIndex(where: { $0.id == 101 }) { db.reportes[i].confirmacionesPrevias = .max }
            db.confirmaciones.append(ParUsuarioReporte(idUsuario: DemoSeed.idTecno, idReporte: 101, fecha: EntornoPrueba.inicio))
        }
        let admin = try await s.usuarioActual(try await sesionAdmin(s))
        let fila = try #require(await s.db.reportes.first { $0.id == 101 })
        #expect(await s.vista(fila, para: admin).confirmaciones == .max)
    }

    private func sesionAdmin(_ s: DemoServer) async throws -> String {
        guard case .sesion(let sesion) = try await s.iniciarSesion(correo: EntornoPrueba.admin.correo, contrasena: EntornoPrueba.admin.contrasena) else {
            throw AppError.codigoInvalido
        }
        return sesion.accessToken
    }

    // MARK: - Sesión y cuentas

    @Test func cuentaSuspendidaNoEntraNiConservaLaSesion() async throws {
        let e = EntornoPrueba()
        let token = try await e.nuevaCuenta()
        var db = await e.servidor.db
        let i = try #require(db.usuarios.firstIndex { $0.usuario.alias == "prueba_01" })
        db.usuarios[i].usuario.estadoCuenta = .suspendido
        try DemoAlmacen(carpeta: e.carpeta).guardar(db)
        let s = DemoServer(almacen: DemoAlmacen(carpeta: e.carpeta), archivos: e.archivos,
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { EntornoPrueba.inicio })
        await #expect(throws: AppError.cuentaSuspendida) { _ = try await s.usuarioActual(token) }
        await #expect(throws: AppError.cuentaSuspendida) {
            _ = try await s.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x")
        }
    }

    @Test func sesionDeUnaCuentaQueYaNoExisteEsExpirada() async throws {
        let e = EntornoPrueba()
        let token = try await e.token(EntornoPrueba.usuario)
        var db = await e.servidor.db
        db.usuarios.removeAll { $0.usuario.id == DemoSeed.idUsuario }
        try DemoAlmacen(carpeta: e.carpeta).guardar(db)
        let s = DemoServer(almacen: DemoAlmacen(carpeta: e.carpeta), archivos: e.archivos,
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { EntornoPrueba.inicio })
        await #expect(throws: AppError.sesionExpirada) { _ = try await s.usuarioActual(token) }
    }

    @Test func contrasenaGiganteEsSoloUnFallo() async {
        let e = EntornoPrueba()
        let enorme = String(repeating: "a", count: 200_000)
        await #expect(throws: AppError.credencialesInvalidas) {
            _ = try await e.servidor.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: enorme)
        }
        await #expect(throws: AppError.credencialesInvalidas) {
            _ = try await e.servidor.iniciarSesion(correo: "nadie@0fraude.mx", contrasena: enorme)
        }
    }

    @Test func correoGiganteEsSoloUnFallo() async {
        let e = EntornoPrueba()
        let enorme = String(repeating: "a", count: 100_000) + "@x.mx"
        await #expect(throws: AppError.credencialesInvalidas) {
            _ = try await e.servidor.iniciarSesion(correo: enorme, contrasena: "malamala123")
        }
    }

    @Test func registrarRechazaAliasRepetido() async {
        let e = EntornoPrueba()
        await #expect(throws: AppError.conflicto("Ese nombre de usuario ya está en uso.")) {
            _ = try await e.servidor.registrar(EntornoPrueba.datosNuevos(alias: "Usuario_01"))
        }
    }

    @Test func cambiarContrasenaRechazaLaMismaYLaDebil() async throws {
        let e = EntornoPrueba()
        let token = try await e.nuevaCuenta()
        await #expect(throws: AppError.self) {
            try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Segura#2026x")
        }
        await #expect(throws: AppError.self) {
            try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "corta1")
        }
        _ = try await e.token(("prueba@comunidad.test", "Segura#2026x"))
    }

    @Test func cambiarContrasenaSinSesionEsSesionExpirada() async {
        let e = EntornoPrueba()
        await #expect(throws: AppError.sesionExpirada) {
            try await e.servidor.cambiarContrasena(token: nil, actual: "x", nueva: "y")
        }
    }

    @Test func cerrarSesionSinTokenNoHaceNada() async throws {
        let e = EntornoPrueba()
        try await e.servidor.cerrarSesion(token: nil)
    }

    @Test func permisosPorRol() async throws {
        let e = EntornoPrueba()
        let usuario = try await e.servidor.usuarioActual(try await e.token(EntornoPrueba.usuario))
        let admin = try await e.servidor.usuarioActual(try await e.token(EntornoPrueba.admin))
        let owner = try await e.servidor.usuarioActual(try await e.token(EntornoPrueba.owner))
        await #expect(throws: AppError.sinPermiso) { try await e.servidor.exigirStaff(usuario) }
        try await e.servidor.exigirStaff(admin)
        try await e.servidor.exigirStaff(owner)
        await #expect(throws: AppError.sinPermiso) { try await e.servidor.exigirOwner(admin) }
        try await e.servidor.exigirOwner(owner)
    }

    @Test func desafioConUsuarioSuspendidoNoAbreSesion() async throws {
        let e = EntornoPrueba()
        let d = try await conDosPasos(e)
        var db = await e.servidor.db
        let i = try #require(db.usuarios.firstIndex { $0.usuario.alias == "prueba_01" })
        db.usuarios[i].usuario.estadoCuenta = .suspendido
        try DemoAlmacen(carpeta: e.carpeta).guardar(db)
        let s = DemoServer(almacen: DemoAlmacen(carpeta: e.carpeta), archivos: e.archivos,
                           hasher: PasswordHasher(iteraciones: 1_000), reloj: { EntornoPrueba.inicio })
        await #expect(throws: AppError.codigoInvalido) { _ = try await s.verificarCodigo(desafio: d.id, codigo: d.codigoDemo ?? "") }
    }

    // MARK: - Utilidades

    @Test func enmascararCubreCorreosRaros() {
        #expect(DemoServer.enmascarar("usuario@0fraude.mx") == "u••••••@0fraude.mx")
        #expect(DemoServer.enmascarar("a@b.mx") == "a•••@b.mx")
        #expect(DemoServer.enmascarar("sin-arroba") == "tu correo")
        #expect(DemoServer.enmascarar("@b.mx") == "tu correo")
        #expect(DemoServer.enmascarar("a@") == "tu correo")
        #expect(DemoServer.enmascarar("") == "tu correo")
    }

    @Test func huellaEsSha256Hexadecimal() {
        #expect(DemoServer.huella("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(DemoServer.huella("").count == 64)
    }

    @Test func nombreVisibleSigueLaReglaDePerfilPublico() async throws {
        let e = EntornoPrueba()
        let yo = try await e.servidor.usuarioActual(try await e.nuevaCuenta())
        let admin = try await e.servidor.usuarioActual(try await e.token(EntornoPrueba.admin))
        #expect(await e.servidor.nombreVisible(de: DemoSeed.idTecno, para: yo) == "tecno_mx")
        #expect(await e.servidor.nombreVisible(de: DemoSeed.idVecina, para: yo) == "Miembro de la comunidad")
        #expect(await e.servidor.nombreVisible(de: DemoSeed.idVecina, para: admin) == "vecina_alerta")
        #expect(await e.servidor.nombreVisible(de: yo.id, para: yo) == "Tú")
        #expect(await e.servidor.nombreVisible(de: nil, para: yo) == "Cuenta eliminada")
        #expect(await e.servidor.nombreVisible(de: 999_999, para: yo) == "Cuenta eliminada")
    }

    @Test func puedeVerLoPublicoLoPropioYTodoSiEsStaff() async throws {
        let e = EntornoPrueba()
        let usuario = try await e.servidor.usuarioActual(try await e.token(EntornoPrueba.usuario))
        let admin = try await e.servidor.usuarioActual(try await e.token(EntornoPrueba.admin))
        let noPublico = try #require(await e.servidor.db.reportes.first { $0.id == 117 })
        let publico = try #require(await e.servidor.db.reportes.first { $0.id == 101 })
        #expect(await e.servidor.puedeVer(publico, usuario))
        #expect(!(await e.servidor.puedeVer(noPublico, usuario)))
        #expect(await e.servidor.puedeVer(noPublico, admin))
    }

    @Test func registrarEventoRespetaLaPreferenciaDeAnaliticas() async throws {
        let e = EntornoPrueba()
        let token = try await e.nuevaCuenta()
        var yo = try await e.servidor.usuarioActual(token)
        let antes = await e.servidor.db.analiticas["prueba_evento"] ?? 0
        await e.servidor.registrarEvento("prueba_evento", de: yo)
        #expect(await e.servidor.db.analiticas["prueba_evento"] == antes + 1)
        yo.preferencias.analiticas = false
        await e.servidor.registrarEvento("prueba_evento", de: yo)
        #expect(await e.servidor.db.analiticas["prueba_evento"] == antes + 1)
    }

    @Test func notificarAgregaUnaFilaSinLeer() async throws {
        let e = EntornoPrueba()
        let antes = await e.servidor.db.notificaciones.count
        await e.servidor.notificar(DemoSeed.idUsuario, reporte: 101, "Hola")
        let filas = await e.servidor.db.notificaciones
        #expect(filas.count == antes + 1)
        #expect(filas.last?.leida == false)
        #expect(filas.last?.idReporte == 101)
    }

    // MARK: - Reautenticación con límite de intentos (cambiar contraseña, apagar dos pasos)

    @Test func cincoFallosAlCambiarContrasenaBloqueanYElBloqueoVence() async throws {
        let e = EntornoPrueba()
        let token = try await e.nuevaCuenta()
        for _ in 1...4 {
            await #expect(throws: AppError.credencialesInvalidas) {
                try await e.servidor.cambiarContrasena(token: token, actual: "equivocada1", nueva: "Distinta#2026y")
            }
        }
        let hasta = EntornoPrueba.inicio.addingTimeInterval(60)
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) {
            try await e.servidor.cambiarContrasena(token: token, actual: "equivocada1", nueva: "Distinta#2026y")
        }
        // Bloqueado: ni la contraseña correcta cambia nada.
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) {
            try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y")
        }
        e.reloj.avanzar(61)
        try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y")
    }

    @Test func unAciertoAlReautenticarLimpiaElContador() async throws {
        let e = EntornoPrueba()
        let token = try await e.nuevaCuenta()
        for _ in 1...3 {
            await #expect(throws: AppError.credencialesInvalidas) {
                try await e.servidor.cambiarContrasena(token: token, actual: "equivocada1", nueva: "Distinta#2026y")
            }
        }
        #expect(await e.servidor.db.intentos["prueba@comunidad.test"]?.fallidos == 3)
        try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y")
        #expect(await e.servidor.db.intentos["prueba@comunidad.test"] == nil)
    }

    @Test func apagarDosPasosConContrasenaMalaTambienCuentaYBloquea() async throws {
        let e = EntornoPrueba()
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        p.dosPasos = false
        for _ in 1...4 {
            await #expect(throws: AppError.credencialesInvalidas) {
                _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: "equivocada1")
            }
        }
        let hasta = EntornoPrueba.inicio.addingTimeInterval(60)
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) {
            _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: "equivocada1")
        }
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) {
            _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: "Segura#2026x")
        }
    }

    @Test func reautenticarSinContrasenaPideConfirmarYNoCuenta() async throws {
        let e = EntornoPrueba()
        let yo = try await e.servidor.usuarioActual(try await e.nuevaCuenta())
        await #expect(throws: AppError.self) { try await e.servidor.reautenticar(yo, contrasena: nil) }
        #expect(await e.servidor.db.intentos["prueba@comunidad.test"] == nil)
    }

    @Test func contrasenaGiganteAlCambiarContrasenaEsSoloUnFallo() async throws {
        let e = EntornoPrueba()
        let token = try await e.nuevaCuenta()
        let enorme = String(repeating: "a", count: 200_000)
        await #expect(throws: AppError.credencialesInvalidas) {
            try await e.servidor.cambiarContrasena(token: token, actual: enorme, nueva: "Distinta#2026y")
        }
        #expect(await e.servidor.db.intentos["prueba@comunidad.test"]?.fallidos == 1)
        try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y")
    }

    // MARK: - Lectura pendiente: un token válido no parece vencido

    @Test func conLecturaPendienteUnTokenValidNoDaSesionExpirada() async throws {
        let e = EntornoPrueba()
        let token = try await e.nuevaCuenta()
        let disponible = InterruptorPrueba(false)
        var almacen = DemoAlmacen(carpeta: e.carpeta)
        almacen.leer = { url in
            guard disponible.encendido else { throw CocoaError(.fileReadNoPermission) }
            return try Data(contentsOf: url)
        }
        let s = DemoServer(almacen: almacen, archivos: e.archivos, hasher: PasswordHasher(iteraciones: 1_000),
                           reloj: { EntornoPrueba.inicio })
        await #expect(throws: AppError.servidor(DemoServer.mensajeDatosNoDisponibles)) { _ = try await s.usuarioActual(token) }
        await #expect(throws: AppError.servidor(DemoServer.mensajeDatosNoDisponibles)) {
            _ = try await s.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
        }
        await #expect(throws: AppError.servidor(DemoServer.mensajeDatosNoDisponibles)) {
            _ = try await s.verificarCodigo(desafio: "x", codigo: "000000")
        }
        await #expect(throws: AppError.servidor(DemoServer.mensajeDatosNoDisponibles)) { _ = try await s.registrar(EntornoPrueba.datosNuevos(alias: "otra_01", correo: "otra@comunidad.test")) }
        // Al recuperarse la lectura, la MISMA sesión vuelve a funcionar.
        disponible.poner(true)
        #expect(try await s.usuarioActual(token).alias == "prueba_01")
    }
}
