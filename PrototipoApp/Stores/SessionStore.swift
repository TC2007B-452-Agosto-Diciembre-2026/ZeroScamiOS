//
//  SessionStore.swift
//  PrototipoApp
//
//  ¿Hay alguien con sesión y quién es? Guarda el token en el Keychain (SecretStore) y decide la
//  raíz de la app (antes `AppState.isLoggedIn`). Si el servidor dice que la sesión ya no sirve,
//  la cierra en un solo lugar (`expirar`).
//
//  Sin conexión: si al abrir la app el servidor no responde pero hay token y perfil guardados, se
//  entra con ese perfil y `sinConexion` queda en true (las pantallas lo avisan y los reportes nuevos
//  van a la cola). Al volver la red, `revalidar()` le pregunta al servidor si la sesión sigue viva.
//  Iniciar sesión por primera vez SIEMPRE necesita al servidor: la contraseña no se revisa aquí.
//
//  Dos cuidados que las pruebas fijan:
//  - Una respuesta que llega tarde nunca mueve la sesión de otra persona: cada cambio de sesión
//    sube `epoca` y las operaciones pendientes comparan con la que tenían al empezar.
//  - Un Keychain que no se deja leer (teléfono bloqueado) NO es una sesión vencida: no se borran
//    los tokens por eso (`DemoBackend.token` lo ve como "sin token", aquí se distingue).
//

import Foundation
import Observation

@Observable
final class SessionStore {
    enum Estado: Equatable {
        case restaurando
        case sinSesion
        case activa(Usuario)
    }

    private(set) var estado: Estado = .restaurando
    private(set) var desafio: DesafioDosPasos?
    /// La sesión se abrió con el perfil guardado porque el servidor no respondió. El servidor todavía
    /// no confirmó que el token siga vivo (pudo vencer, o la cuenta pudo suspenderse mientras tanto).
    private(set) var sinConexion = false
    /// Mensaje que Login muestra arriba: cuenta creada, sesión expirada, cuenta eliminada.
    var aviso: String?
    /// Correo que Login precarga después de registrarse.
    var correoSugerido = ""
    /// Sube cada vez que cambia la foto de perfil. Con el servidor real la ruta del avatar es
    /// siempre la misma ("avatar"), así que las vistas la usan para saber que deben volver a bajarla.
    private(set) var versionAvatar = 0

    @ObservationIgnored private let backend: any Backend
    @ObservationIgnored private let secretos: any SecretStore
    /// Sube cada vez que empieza o termina una sesión.
    @ObservationIgnored private var epoca = 0
    /// Último archivo de "Descargar mis datos": datos personales en texto claro que no deben quedar
    /// en la carpeta temporal después de cerrar sesión.
    @ObservationIgnored private(set) var archivoExportado: URL?

    static let avisoCuentaCreada = "Cuenta creada. Inicia sesión para continuar."
    static let avisoKeychainIlegible = "No se pudo leer tu sesión guardada. Inicia sesión de nuevo."
    static let avisoDemoRestablecida = "Datos de demostración restablecidos. Inicia sesión de nuevo."
    static let avisoCuentaEliminada = "Tu cuenta se eliminó. Gracias por ayudar a la comunidad."
    static let errorAlGuardarSesion = "No se pudo guardar tu sesión de forma segura. Intenta de nuevo."

    init(backend: any Backend, secretos: any SecretStore) {
        self.backend = backend
        self.secretos = secretos
    }

    var usuario: Usuario? {
        if case .activa(let u) = estado { return u }
        return nil
    }

    func restaurar() async {
        let token: String?
        do {
            token = try secretos.leer(.accessToken)
        } catch {
            // Keychain ilegible: se pide iniciar sesión, pero el token no se borra (puede ser pasajero).
            aviso = Self.avisoKeychainIlegible
            cambiarEstado(.sinSesion)
            return
        }
        guard token != nil else {
            cambiarEstado(.sinSesion)
            return
        }
        let mia = epoca
        do {
            let u = try await backend.usuarioActual()
            guard epoca == mia else { return }
            guardarPerfil(u)
            sinConexion = false
            cambiarEstado(.activa(u))
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            guard epoca == mia else { return }
            expirar(error)
        } catch AppError.sinConexion where perfilGuardado != nil {
            // Sin red, con token y perfil guardados: se entra sin conexión. El token se conserva y
            // el servidor lo revisa en cuanto vuelva la red (`revalidar`).
            guard epoca == mia, let u = perfilGuardado else { return }
            sinConexion = true
            cambiarEstado(.activa(u))
        } catch {
            // Sin perfil guardado (o un error del servidor) no se sabe con quién entrar: el token se
            // conserva para el próximo intento y mientras tanto se pide iniciar sesión.
            guard epoca == mia else { return }
            aviso = error.mensajeUsuario
            cambiarEstado(.sinSesion)
        }
    }

    /// Volvió la red: si la sesión se abrió sin conexión, el servidor confirma que sigue viva. Si la
    /// sesión venció o la cuenta se suspendió, se cierra aquí; si sigue sin red, no cambia nada.
    func revalidar() async {
        guard sinConexion, let actual = usuario else { return }
        let mia = epoca
        do {
            let u = try await backend.usuarioActual()
            guard epoca == mia else { return }
            // Otra persona con el mismo token no puede ser: si el servidor dice otro id, se sale.
            guard u.id == actual.id else { return expirar(.sesionExpirada) }
            guardarPerfil(u)
            sinConexion = false
            estado = .activa(u)
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            if epoca == mia { expirar(error) }
        } catch {
            // Sigue sin red (o el servidor falló): se queda sin conexión y se reintenta después.
        }
    }

    func iniciarSesion(correo: String, contrasena: String) async throws {
        switch try await backend.iniciarSesion(correo: Sanitizador.correo(correo), contrasena: contrasena) {
        case .sesion(let s): try abrir(s)
        case .requiereCodigo(let d): desafio = d
        }
    }

    func verificarCodigo(_ codigo: String) async throws {
        guard let desafio else { throw AppError.codigoInvalido }
        try abrir(try await backend.verificarCodigo(desafio: desafio.id, codigo: codigo))
    }

    func cancelarDesafio() { desafio = nil }

    func registrar(_ datos: RegistroDatos) async throws {
        let u = try await backend.registrar(datos)
        correoSugerido = u.correo
        aviso = Self.avisoCuentaCreada
    }

    /// Pasa a `.sinSesion` ANTES de avisar al servidor: así una respuesta "sesión expirada" que llegue
    /// mientras tanto (de un store de esta misma sesión) ya no cuenta y Login no muestra un aviso
    /// tras un cierre voluntario. El token sigue en el Keychain hasta que el servidor lo revoca.
    func cerrarSesion() async {
        desafio = nil
        aviso = nil
        correoSugerido = ""
        borrarArchivoExportado()
        cambiarEstado(.sinSesion)
        let mia = epoca
        try? await backend.cerrarSesion()
        // Si mientras esperaba entró otra persona, su token ya no es el que se está cerrando.
        if epoca == mia { try? secretos.borrarTodo() }
    }

    /// El Owner restableció los datos de demostración (cierra todas las sesiones, la suya incluida).
    /// A diferencia de `expirar`, funciona aunque un `.sesionExpirada` ya haya llegado antes: este
    /// aviso explica mejor lo que pasó y no debe perderse.
    func sesionRestablecida() {
        try? secretos.borrarTodo()
        borrarArchivoExportado()
        desafio = nil
        correoSugerido = ""
        aviso = Self.avisoDemoRestablecida
        cambiarEstado(.sinSesion)
    }

    /// La llaman todos los stores cuando el servidor responde sesión expirada o cuenta suspendida.
    /// Si ya no hay sesión (una respuesta tardía después de cerrarla) no hace nada, para no pisar
    /// el aviso de Login ni tocar la sesión siguiente.
    func expirar(_ error: AppError) {
        if case .sinSesion = estado { return }
        if error == .sesionExpirada, tokenIlegible {
            aviso = Self.avisoKeychainIlegible
        } else {
            try? secretos.borrarTodo()
            aviso = error.mensaje()
        }
        borrarArchivoExportado()
        desafio = nil
        correoSugerido = ""
        cambiarEstado(.sinSesion)
    }

    func actualizarPerfil(_ datos: PerfilDatos) async throws {
        try await actualizarUsuario { try await backend.actualizarPerfil(datos) }
    }

    func actualizarPreferencias(_ p: Preferencias, contrasena: String? = nil) async throws {
        try await actualizarUsuario { try await backend.actualizarPreferencias(p, contrasena: contrasena) }
    }

    /// El aviso de privacidad cambió desde que esta cuenta lo aceptó. Sin conexión no se pide:
    /// la aceptación no se podría registrar y sigue valiendo la versión anterior.
    var debeAceptarAviso: Bool {
        guard let u = usuario, !sinConexion else { return false }
        return u.consentimiento.versionAviso != Consentimiento.versionAvisoVigente
    }

    func aceptarAvisoVigente() async throws {
        try await actualizarUsuario { try await backend.aceptarAviso(version: Consentimiento.versionAvisoVigente) }
    }

    func actualizarAvatar(_ adjunto: Adjunto?) async throws {
        try await actualizarUsuario { try await backend.actualizarAvatar(adjunto) }
        versionAvatar &+= 1
    }

    func datosAvatar(de usuario: Usuario) async -> Data? {
        try? await backend.datosAvatar(de: usuario)
    }

    func recargarUsuario() async {
        try? await actualizarUsuario { try await backend.usuarioActual() }
    }

    func cambiarContrasena(actual: String, nueva: String) async throws {
        try await conSesion { try await backend.cambiarContrasena(actual: actual, nueva: nueva) }
    }

    /// Puede lanzar `.cuentaBloqueada(hasta:)` (demasiadas contraseñas incorrectas): la sesión
    /// sigue abierta y la vista muestra `error.mensajeUsuario`.
    func eliminarCuenta(contrasena: String) async throws {
        try await conSesion { try await backend.eliminarCuenta(contrasena: contrasena) }
        limpiarSesionLocal()
        correoSugerido = ""
        aviso = Self.avisoCuentaEliminada
        cambiarEstado(.sinSesion)
    }

    /// Escribe "Descargar mis datos" en un archivo temporal protegido para compartirlo. Vive en una
    /// carpeta propia de este store y se borra al terminar la sesión. Si la sesión cambió mientras
    /// esperaba la respuesta (cerró sesión o entró otra persona), no escribe nada y lanza
    /// `.sesionExpirada`: esos datos personales ya no son de quien está usando la app.
    func exportarDatos() async throws -> URL {
        let mia = epoca
        let datos = try await conSesion { try await backend.exportarMisDatos() }
        guard epoca == mia else { throw AppError.sesionExpirada }
        borrarArchivoExportado()
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-datos-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let url = carpeta.appending(path: "zeroscam-mis-datos.json")
        do {
            try datos.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            try? FileManager.default.removeItem(at: carpeta)
            throw error
        }
        archivoExportado = url
        return url
    }

    // MARK: Ayudantes

    private func abrir(_ s: SesionActiva) throws {
        do {
            try secretos.guardar(s.accessToken, para: .accessToken)
            if let refresh = s.refreshToken { try secretos.guardar(refresh, para: .refreshToken) }
        } catch {
            // Sin dónde guardarlo el token no sirve: no se queda a medias.
            try? secretos.borrarTodo()
            throw AppError.servidor(Self.errorAlGuardarSesion)
        }
        desafio = nil
        aviso = nil
        correoSugerido = ""
        guardarPerfil(s.usuario)
        cambiarEstado(.activa(s.usuario))
    }

    private func cambiarEstado(_ nuevo: Estado) {
        epoca &+= 1
        if case .activa = nuevo {} else { sinConexion = false }
        estado = nuevo
    }

    /// Perfil para entrar sin conexión. Si no se puede guardar, solo se pierde esa opción.
    private func guardarPerfil(_ u: Usuario) {
        guard let datos = try? Codificacion.encoder().encode(u), let texto = String(data: datos, encoding: .utf8) else { return }
        try? secretos.guardar(texto, para: .usuario)
    }

    /// El perfil guardado, solo si es del mismo formato que entiende esta versión de la app.
    private var perfilGuardado: Usuario? {
        guard let texto = try? secretos.leer(.usuario) else { return nil }
        return try? Codificacion.decoder().decode(Usuario.self, from: Data(texto.utf8))
    }

    private func limpiarSesionLocal() {
        try? secretos.borrarTodo()
        borrarArchivoExportado()
        desafio = nil
    }

    private func borrarArchivoExportado() {
        guard let url = archivoExportado else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())   // su carpeta propia
        archivoExportado = nil
    }

    private var tokenIlegible: Bool {
        do { _ = try secretos.leer(.accessToken); return false } catch { return true }
    }

    /// Ejecuta una operación con sesión; si el servidor dice que ya no sirve, la cierra aquí.
    private func conSesion<T>(_ operacion: () async throws -> T) async throws -> T {
        let mia = epoca
        do {
            return try await operacion()
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            if epoca == mia { expirar(error) }
            throw error
        }
    }

    /// Guarda el usuario que devuelve la operación, salvo que la sesión haya cambiado mientras
    /// tanto (cerró sesión o entró otra persona): una respuesta tardía no resucita la sesión.
    private func actualizarUsuario(_ operacion: () async throws -> Usuario) async throws {
        let mia = epoca
        let u = try await conSesion(operacion)
        guard epoca == mia else { return }
        guardarPerfil(u)
        // El servidor respondió con este token: la sesión ya está confirmada.
        sinConexion = false
        estado = .activa(u)
    }
}
