//
//  RemoteBackend.swift
//  PrototipoApp
//
//  La API NestJS del Equipo ZeroScam detrás de los mismos protocolos que DemoBackend: las
//  pantallas no saben cuál se usa. Sesión y perfil en /auth y /account; reportes, guardados,
//  comentarios y estadísticas en /community; moderación y cuentas en /reports y /users (las
//  mismas rutas del panel web). Los permisos los decide el servidor.
//

import Foundation

nonisolated struct RemoteBackend: Backend {
    let http: ClienteHTTP
    let archivos: ArchivosEvidencia

    init(base: URL, secretos: any SecretStore, archivos: ArchivosEvidencia,
         sesion: URLSession = ClienteHTTP.sesionPorDefecto()) {
        http = ClienteHTTP(base: base, secretos: secretos, sesion: sesion)
        self.archivos = archivos
    }

    static let mensajeSoloDemo = "Esta opción solo existe en el modo Demo."
    static let mensajeCaracterEspecial = "La contraseña debe incluir al menos un carácter especial, por ejemplo ! # o $."

    /// La API exige, además de las reglas de la app, un carácter que no sea letra ni número. Se
    /// revisa aquí para decirlo en claro antes de mandar nada (el aviso del servidor es más críptico).
    private static func exigirCaracterEspecial(_ contrasena: String) throws {
        let tiene = contrasena.unicodeScalars.contains { e in
            !(e.isASCII && (("0"..."9").contains(e) || ("a"..."z").contains(e) || ("A"..."Z").contains(e)))
        }
        guard tiene else { throw AppError.validacion([mensajeCaracterEspecial]) }
    }

    // MARK: - AuthRepository

    func registrar(_ datos: RegistroDatos) async throws -> Usuario {
        try Self.exigirCaracterEspecial(datos.contrasena)
        let envio = RegistroEnvio(
            name: Sanitizador.texto(datos.nombre, maximo: 50), lastName: Sanitizador.texto(datos.apellido, maximo: 50),
            country: Sanitizador.texto(datos.pais, maximo: 30), email: Sanitizador.correo(datos.correo),
            password: datos.contrasena, acceptsPrivacy: datos.aceptaAviso, alias: Sanitizador.alias(datos.alias),
            privacyVersion: Consentimiento.versionAvisoVigente)
        return try leerUsuario(await http.enviar("POST", "account/register", cuerpo: try CuerpoHTTP.json(envio), token: .ninguno))
    }

    func iniciarSesion(correo: String, contrasena: String) async throws -> ResultadoLogin {
        let cuerpo = try CuerpoHTTP.json(["email": Sanitizador.correo(correo), "password": contrasena])
        let datos = try await http.enviar("POST", "auth/login", cuerpo: cuerpo, token: .ninguno, contexto: .login)
        let respuesta = try http.decodificar(LoginDTO.self, datos)
        if respuesta.twoFactorRequired == true {
            guard let id = respuesta.challengeId, let destino = respuesta.destination, let expira = respuesta.expiresAt else {
                throw AppError.servidor(ClienteHTTP.mensajeServidor)
            }
            // El código lo entrega el servidor por su canal; aquí nunca viaja.
            return .requiereCodigo(DesafioDosPasos(id: id, destino: Sanitizador.texto(destino, maximo: 160), expira: expira, codigoDemo: nil))
        }
        return .sesion(try await abrirSesion(access: respuesta.accessToken, refresh: respuesta.refreshToken))
    }

    func verificarCodigo(desafio: String, codigo: String) async throws -> SesionActiva {
        let cuerpo = try CuerpoHTTP.json(["challengeId": desafio, "code": codigo])
        let datos: Data
        do {
            datos = try await http.enviar("POST", "auth/two-factor/verify", cuerpo: cuerpo, token: .ninguno, contexto: .codigo)
        } catch AppError.validacion {
            // Un código o un desafío con mal formato es, para quien lo escribe, un código inválido.
            throw AppError.codigoInvalido
        }
        let tokens = try http.decodificar(TokensDTO.self, datos)
        return try await abrirSesion(access: tokens.accessToken, refresh: tokens.refreshToken)
    }

    /// Los tokens aún no están en el Keychain (los guarda SessionStore): el perfil se pide con el recién emitido.
    private func abrirSesion(access: String?, refresh: String?) async throws -> SesionActiva {
        guard let access, !access.isEmpty else { throw AppError.servidor(ClienteHTTP.mensajeServidor) }
        let usuario = try leerUsuario(await http.enviar("GET", "account", token: .fijo(access)))
        return SesionActiva(accessToken: access, refreshToken: refresh, usuario: usuario)
    }

    func usuarioActual() async throws -> Usuario {
        try leerUsuario(await http.enviar("GET", "account"))
    }

    /// El servidor no guarda sesiones: avisa por cortesía y SessionStore borra los tokens del Keychain.
    func cerrarSesion() async throws {
        do {
            try await http.enviar("POST", "auth/logout")
        } catch AppError.sesionExpirada {
            // Ya no había sesión que cerrar.
        }
    }

    func pedirCodigoContrasena() async throws -> DesafioDosPasos {
        let respuesta = try http.decodificar(CodigoCorreoDTO.self, await http.enviar("POST", "auth/password/code"))
        return DesafioDosPasos(id: respuesta.challengeId, destino: Sanitizador.texto(respuesta.destination ?? "", maximo: 160),
                               expira: respuesta.expiresAt, codigoDemo: nil)
    }

    /// El servidor deja de renovar los refresh tokens de antes del cambio: regresa unos nuevos.
    func cambiarContrasena(actual: String, nueva: String, desafio: String, codigo: String) async throws -> TokensSesion? {
        try Self.exigirCaracterEspecial(nueva)
        let cuerpo = try CuerpoHTTP.json(["currentPassword": actual, "newPassword": nueva, "challengeId": desafio, "code": codigo])
        let datos: Data
        do {
            datos = try await http.enviar("PATCH", "auth/password", cuerpo: cuerpo)
        } catch let error as AppError {
            throw Self.errorDeContrasena(error)
        }
        let tokens = try http.decodificar(TokensDTO.self, datos)
        return TokensSesion(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
    }

    /// La respuesta no dice a qué correo se mandó (ni si existe la cuenta): el destino es el que se escribió.
    func olvideContrasena(correo: String) async throws -> DesafioDosPasos {
        let limpio = Sanitizador.correo(correo)
        let datos = try await http.enviar("POST", "auth/password/forgot", cuerpo: try CuerpoHTTP.json(["email": limpio]), token: .ninguno)
        let respuesta = try http.decodificar(CodigoCorreoDTO.self, datos)
        return DesafioDosPasos(id: respuesta.challengeId, destino: limpio, expira: respuesta.expiresAt, codigoDemo: nil)
    }

    func restablecerContrasena(desafio: String, codigo: String, nueva: String) async throws {
        try Self.exigirCaracterEspecial(nueva)
        let cuerpo = try CuerpoHTTP.json(["challengeId": desafio, "code": codigo, "newPassword": nueva])
        do {
            try await http.enviar("POST", "auth/password/reset", cuerpo: cuerpo, token: .ninguno, contexto: .codigo)
        } catch let error as AppError {
            throw Self.errorDeContrasena(error)
        }
    }

    /// El API responde 400 lo mismo por un código malo que por la contraseña actual equivocada. Se
    /// separan para que la pantalla cuente los intentos del código y hable en español.
    static func errorDeContrasena(_ error: AppError) -> AppError {
        guard case .validacion(let mensajes) = error else { return error }
        func dice(_ texto: String) -> Bool { mensajes.contains { $0.localizedCaseInsensitiveContains(texto) } }
        // Primero: este mensaje también dice "pide un código nuevo".
        if dice("actual es incorrect") { return .credencialesInvalidas }
        if dice("código") || dice("code ") || dice("challengeId") { return .codigoInvalido }
        if dice("distint") { return .validacion(["La nueva contraseña debe ser distinta de la actual."]) }
        return error
    }

    func eliminarCuenta(contrasena: String) async throws {
        try await http.enviar("DELETE", "account", cuerpo: try CuerpoHTTP.json(["password": contrasena]))
    }

    // MARK: - ReportRepository

    func feed(_ filtro: FiltroBusqueda) async throws -> [Reporte] {
        var consulta = [URLQueryItem(name: "scope", value: "feed")]
        let texto = Sanitizador.texto(filtro.texto, maximo: 100)
        if !texto.isEmpty { consulta.append(URLQueryItem(name: "q", value: texto)) }
        // El servidor filtra por texto; tipos y riesgo se aplican aquí con la misma regla de siempre
        // (los tipos que la app no conoce se agrupan en "Otro" y el servidor no sabe de ese grupo).
        return try await reportes(consulta).filter { filtro.coincide($0) }
    }

    func misReportes() async throws -> [Reporte] {
        try await reportes([URLQueryItem(name: "scope", value: "mine")])
    }

    func guardados() async throws -> [Reporte] {
        try await reportes([URLQueryItem(name: "scope", value: "saved")])
    }

    func detalle(id: Int64) async throws -> Reporte {
        try leerReporte(await http.enviar("GET", "community/reports/\(id)"))
    }

    /// El reporte se crea primero y la evidencia se sube después, archivo por archivo. Si una subida
    /// falla, el reporte recién creado se retira: no queda publicado sin la evidencia que la persona eligió.
    ///
    /// `clave` va en `Idempotency-Key`. Si la red se cortó después de que el servidor creó el reporte
    /// (o mientras se retiraba), el reintento con la misma clave recibe ese mismo reporte con la
    /// evidencia que alcanzó a subir, y solo se suben los archivos que faltan.
    func crear(_ borrador: ReporteBorrador, clave: String) async throws -> Reporte {
        let b = borrador.limpio
        var creado = try leerReporte(await http.enviar("POST", "community/reports", cuerpo: try CuerpoHTTP.json(ReporteEnvio(b, quitar: nil)),
                                                      cabeceras: ["Idempotency-Key": clave]))
        do {
            for adjunto in b.adjuntos.dropFirst(creado.evidencias.count) { creado = try await subirEvidencia(adjunto, a: creado.id) }
        } catch {
            _ = try? await http.enviar("DELETE", "community/reports/\(creado.id)")
            throw error
        }
        return creado
    }

    func actualizar(id: Int64, _ borrador: ReporteBorrador) async throws -> Reporte {
        let b = borrador.limpio
        let envio = ReporteEnvio(b, quitar: b.quitarEvidencias.sorted())
        var actualizado = try leerReporte(await http.enviar("PATCH", "community/reports/\(id)", cuerpo: try CuerpoHTTP.json(envio)))
        for adjunto in b.adjuntos { actualizado = try await subirEvidencia(adjunto, a: id) }
        return actualizado
    }

    private func subirEvidencia(_ adjunto: Adjunto, a id: Int64) async throws -> Reporte {
        let contenido: Data
        do {
            contenido = try archivos.datos(de: adjunto)
        } catch {
            throw AppError.validacion(["No se pudo adjuntar uno de los archivos. Vuelve a elegirlo."])
        }
        let cuerpo = CuerpoHTTP.archivo(contenido, nombre: adjunto.nombreArchivo, tipo: adjunto.tipoArchivo)
        let resultado = try leerReporte(await http.enviar("POST", "community/reports/\(id)/evidence", cuerpo: cuerpo))
        // Ya está en el servidor: la copia en "pendiente/" sobra.
        try? archivos.borrarTemporal(adjunto)
        return resultado
    }

    func eliminar(id: Int64) async throws {
        try await http.enviar("DELETE", "community/reports/\(id)")
    }

    func marcarGuardado(id: Int64, _ guardado: Bool) async throws {
        try await http.enviar(guardado ? "PUT" : "DELETE", "community/reports/\(id)/saved")
    }

    func confirmar(id: Int64) async throws -> Reporte {
        try leerReporte(await http.enviar("POST", "community/reports/\(id)/confirmations"))
    }

    func comentarios(id: Int64) async throws -> [Comentario] {
        let datos = try await http.enviar("GET", "community/reports/\(id)/comments")
        return try http.decodificar([ComentarioDTO].self, datos).map(\.comentario)
    }

    func comentar(id: Int64, texto: String) async throws -> Comentario {
        let cuerpo = try CuerpoHTTP.json(["text": Sanitizador.texto(texto, maximo: 500, multilinea: true)])
        let datos = try await http.enviar("POST", "community/reports/\(id)/comments", cuerpo: cuerpo)
        return try http.decodificar(ComentarioDTO.self, datos).comentario
    }

    func eliminarComentario(id: Int64) async throws {
        try await http.enviar("DELETE", "community/comments/\(id)")
    }

    func historial(id: Int64) async throws -> [HistorialEstado] {
        let datos = try await http.enviar("GET", "community/reports/\(id)/history")
        return try http.decodificar([HistorialDTO].self, datos).map { try $0.historial() }
    }

    func estadisticas() async throws -> EstadisticasComunidad {
        try http.decodificar(EstadisticasDTO.self, await http.enviar("GET", "community/stats")).estadisticas
    }

    /// Una tarjeta por tipo de la app; los tipos del servidor que la app no conoce cuentan en "Otro".
    func categorias() async throws -> [ConteoCategoria] {
        let filas = try http.decodificar([CategoriaDTO].self, await http.enviar("GET", "community/categories"))
        return TipoFraude.allCases.map { tipo in
            let deTipo = filas.filter { (TipoFraude(rawValue: $0.fraudType) ?? .otro) == tipo }
            // Los totales vienen de fuera: se acotan para que la suma no pueda desbordar.
            let total = deTipo.reduce(0) { $0 + min(max(0, $1.total), 1_000_000_000) }
            return ConteoCategoria(tipo: tipo, total: total,
                                   riesgoMaximo: deTipo.compactMap { NivelRiesgo(rawValue: $0.maxRisk) }.max() ?? .noEvaluado)
        }
    }

    /// El archivo se pide por el id de la evidencia; el servidor revisa el permiso de quien lo pide.
    func datosEvidencia(_ evidencia: Evidencia) async throws -> Data {
        try await http.enviar("GET", "community/evidence/\(evidencia.id)")
    }

    /// El servidor hace las verificaciones (certificado, antigüedad, listas negras) y anota la consulta:
    /// si el riesgo del enlace sube después, quien lo consultó recibe una notificación.
    func analizarURL(_ url: String) async throws -> DiagnosticoURL {
        let datos = try await http.enviar("POST", "risk/analyze", cuerpo: try CuerpoHTTP.json(["url": url]))
        return try http.decodificar(DiagnosticoDTO.self, datos).diagnostico()
    }

    func perfilPublico(id: Int64) async throws -> PerfilPublico {
        try http.decodificar(PerfilPublicoDTO.self, await http.enviar("GET", "community/users/\(id)")).perfil()
    }

    func avatarPublico(idUsuario: Int64) async throws -> Data? {
        do {
            return try await http.enviar("GET", "account/avatar/\(idUsuario)")
        } catch AppError.noEncontrado {
            return nil
        }
    }

    // MARK: - ProfileRepository

    func actualizarPerfil(_ datos: PerfilDatos) async throws -> Usuario {
        let envio = PerfilEnvio(
            name: Sanitizador.texto(datos.nombre, maximo: 50), lastName: Sanitizador.texto(datos.apellido, maximo: 50),
            country: Sanitizador.texto(datos.pais, maximo: 30), alias: Sanitizador.alias(datos.alias),
            email: Sanitizador.correo(datos.correo), bio: Sanitizador.texto(datos.biografia, maximo: 300, multilinea: true),
            currentPassword: datos.contrasenaActual)
        return try leerUsuario(await http.enviar("PATCH", "account", cuerpo: try CuerpoHTTP.json(envio)))
    }

    func actualizarPreferencias(_ preferencias: Preferencias, contrasena: String?) async throws -> Usuario {
        let envio = PreferenciasDTO(preferencias, contrasena: contrasena)
        return try leerUsuario(await http.enviar("PATCH", "account/preferences", cuerpo: try CuerpoHTTP.json(envio)))
    }

    func aceptarAviso(version: String) async throws -> Usuario {
        try leerUsuario(await http.enviar("PATCH", "account/privacy", cuerpo: try CuerpoHTTP.json(["version": version])))
    }

    func actualizarAvatar(_ adjunto: Adjunto?) async throws -> Usuario {
        guard let adjunto else { return try leerUsuario(await http.enviar("DELETE", "account/avatar")) }
        guard adjunto.tipoArchivo == "image/jpeg" else { throw AppError.validacion(["El avatar debe ser una imagen."]) }
        let contenido: Data
        do {
            contenido = try archivos.datos(de: adjunto)
        } catch {
            throw AppError.validacion(["No se pudo usar la imagen. Vuelve a elegirla."])
        }
        let cuerpo = CuerpoHTTP.archivo(contenido, nombre: adjunto.nombreArchivo, tipo: adjunto.tipoArchivo)
        let actualizado = try leerUsuario(await http.enviar("POST", "account/avatar", cuerpo: cuerpo))
        try? archivos.borrarTemporal(adjunto)
        return actualizado
    }

    /// Sin avatar, o si el servidor no deja verlo, es lo mismo: no hay imagen que mostrar.
    func datosAvatar(de usuario: Usuario) async throws -> Data? {
        guard usuario.avatarRuta != nil else { return nil }
        do {
            return try await http.enviar("GET", "account/avatar/\(usuario.id)")
        } catch AppError.noEncontrado {
            return nil
        }
    }

    func exportarMisDatos() async throws -> Data {
        let datos = try await http.enviar("GET", "account/export")
        // Con sangría, para que el archivo que la persona comparte se pueda leer.
        guard let objeto = try? JSONSerialization.jsonObject(with: datos),
              let legible = try? JSONSerialization.data(withJSONObject: objeto, options: [.prettyPrinted, .sortedKeys])
        else { return datos }
        return legible
    }

    // MARK: - NotificationRepository

    func notificaciones() async throws -> [Notificacion] {
        try http.decodificar([NotificacionDTO].self, await http.enviar("GET", "notifications")).map(\.notificacion)
    }

    /// El servidor marca de una en una. Un id ajeno o que ya no existe se ignora, como en el modo Demo.
    func marcarLeidas(_ ids: [Int64]) async throws {
        for id in Set(ids).sorted() {
            do {
                try await http.enviar("PATCH", "notifications/\(id)/read")
            } catch AppError.noEncontrado {
                continue
            }
        }
    }

    // MARK: - AdminRepository

    func colaModeracion(estado: EstadoReporte?) async throws -> [Reporte] {
        var consulta = [URLQueryItem(name: "scope", value: "queue")]
        if let estado { consulta.append(URLQueryItem(name: "status", value: estado.rawValue)) }
        return try await reportes(consulta)
    }

    /// El riesgo se asigna antes de validar, con las mismas rutas que usa el panel web.
    func cambiarEstado(id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) async throws -> Reporte {
        if nuevo == .validado, let riesgo {
            try await http.enviar("PATCH", "reports/\(id)/risk", cuerpo: try CuerpoHTTP.json(["riskLevel": riesgo.rawValue]))
        }
        var cambio = ["status": nuevo.rawValue]
        let texto = Sanitizador.texto(observaciones, maximo: 500, multilinea: true)
        if !texto.isEmpty { cambio["observations"] = texto }
        try await http.enviar("PATCH", "reports/\(id)/status", cuerpo: try CuerpoHTTP.json(cambio))
        return try await detalle(id: id)
    }

    func usuarios() async throws -> [Usuario] {
        try http.decodificar([CuentaDTO].self, await http.enviar("GET", "account/users")).map { try $0.usuario() }
    }

    func cambiarRol(idUsuario: Int64, a rol: Rol) async throws -> Usuario {
        try await cambiarCuenta(idUsuario, ["role": rol.rawValue])
    }

    func cambiarEstadoCuenta(idUsuario: Int64, a estado: EstadoCuenta) async throws -> Usuario {
        try await cambiarCuenta(idUsuario, ["accountStatus": estado.rawValue])
    }

    /// `PATCH /users/:id` responde sin alias ni preferencias: la cuenta completa se relee de la lista.
    private func cambiarCuenta(_ id: Int64, _ cambio: [String: String]) async throws -> Usuario {
        try await http.enviar("PATCH", "users/\(id)", cuerpo: try CuerpoHTTP.json(cambio))
        guard let cuenta = try await usuarios().first(where: { $0.id == id }) else { throw AppError.noEncontrado }
        return cuenta
    }

    func analiticas() async throws -> [String: Int] {
        try http.decodificar([String: Int].self, await http.enviar("GET", "account/analytics")).mapValues { max(0, $0) }
    }

    /// Los datos del servidor real no se restablecen desde la app.
    func restablecerDemo() async throws {
        throw AppError.conflicto(Self.mensajeSoloDemo)
    }

    // MARK: - Ayudantes

    private func leerUsuario(_ datos: Data) throws -> Usuario {
        try http.decodificar(CuentaDTO.self, datos).usuario()
    }

    private func leerReporte(_ datos: Data) throws -> Reporte {
        try http.decodificar(ReporteDTO.self, datos).reporte()
    }

    private func reportes(_ consulta: [URLQueryItem]) async throws -> [Reporte] {
        let datos = try await http.enviar("GET", "community/reports", consulta: consulta)
        return try http.decodificar([ReporteDTO].self, datos).map { try $0.reporte() }
    }
}
