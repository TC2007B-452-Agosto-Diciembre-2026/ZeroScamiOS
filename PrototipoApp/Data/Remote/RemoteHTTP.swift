//
//  RemoteHTTP.swift
//  PrototipoApp
//
//  Transporte del RemoteBackend: arma la petición, agrega el Bearer, renueva el access token
//  cuando el servidor contesta 401 y traduce los códigos HTTP a `AppError`. Es el equivalente a
//  los interceptores de `api.ts` del panel web.
//

import Foundation

/// Cuerpo de una petición con su Content-Type.
nonisolated struct CuerpoHTTP: Sendable {
    let datos: Data
    let tipo: String

    static func json(_ valor: some Encodable) throws -> CuerpoHTTP {
        do {
            return CuerpoHTTP(datos: try Codificacion.encoder().encode(valor), tipo: "application/json")
        } catch {
            throw AppError.servidor(ClienteHTTP.mensajeServidor)
        }
    }

    /// multipart/form-data con un solo campo `file`. El nombre lo genera la app (UUID + extensión).
    static func archivo(_ contenido: Data, nombre: String, tipo: String) -> CuerpoHTTP {
        let limite = "zs-\(UUID().uuidString)"
        var datos = Data()
        datos.append(Data("--\(limite)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(nombre)\"\r\nContent-Type: \(tipo)\r\n\r\n".utf8))
        datos.append(contenido)
        datos.append(Data("\r\n--\(limite)--\r\n".utf8))
        return CuerpoHTTP(datos: datos, tipo: "multipart/form-data; boundary=\(limite)")
    }
}

/// Una sola renovación a la vez: si diez peticiones reciben 401 juntas, se pide un token y las diez lo usan.
private actor RenovadorToken {
    private var enCurso: Task<String, Error>?

    func renovar(_ trabajo: @escaping @Sendable () async throws -> String) async throws -> String {
        if let enCurso { return try await enCurso.value }
        let tarea = Task { try await trabajo() }
        enCurso = tarea
        defer { enCurso = nil }
        return try await tarea.value
    }
}

nonisolated struct ClienteHTTP: Sendable {
    /// Con qué token sale la petición.
    nonisolated enum Token: Sendable {
        case ninguno
        /// El del Keychain; si el servidor lo rechaza se renueva y se reintenta una vez.
        case guardado
        /// Uno recién emitido que todavía no está en el Keychain (justo después del login).
        case fijo(String)
    }

    /// Qué significa un 401 según a quién se le preguntó.
    nonisolated enum Contexto: Sendable {
        case general, login, codigo
    }

    static let mensajeServidor = "El servidor no pudo completar la operación. Intenta más tarde."

    let base: URL
    let secretos: any SecretStore
    let sesion: URLSession
    private let renovador = RenovadorToken()

    init(base: URL, secretos: any SecretStore, sesion: URLSession) {
        self.base = base
        self.secretos = secretos
        self.sesion = sesion
    }

    /// Sin caché ni cookies en disco y con un tiempo de espera corto: las respuestas llevan datos personales.
    static func sesionPorDefecto() -> URLSession {
        let configuracion = URLSessionConfiguration.ephemeral
        configuracion.timeoutIntervalForRequest = 20
        configuracion.waitsForConnectivity = false
        return URLSession(configuration: configuracion)
    }

    // MARK: - Enviar

    @discardableResult
    func enviar(_ metodo: String, _ ruta: String, consulta: [URLQueryItem] = [], cuerpo: CuerpoHTTP? = nil,
                token: Token = .guardado, contexto: Contexto = .general,
                cabeceras: [String: String] = [:]) async throws -> Data {
        let bearer: String?
        switch token {
        case .ninguno: bearer = nil
        case .fijo(let t): bearer = t
        case .guardado:
            // Sin token, o con un Keychain que no se deja leer, no hay sesión que mandar.
            guard let t = try? secretos.leer(.accessToken) else { throw AppError.sesionExpirada }
            bearer = t
        }
        var (datos, estado) = try await transportar(try peticion(metodo, ruta, consulta, cuerpo, bearer, cabeceras))
        if estado == 401, case .guardado = token, let usado = bearer {
            let nuevo = try await renovar(usado: usado)
            (datos, estado) = try await transportar(try peticion(metodo, ruta, consulta, cuerpo, nuevo, cabeceras))
        }
        guard (200..<300).contains(estado) else { throw Self.error(estado: estado, datos: datos, contexto: contexto) }
        return datos
    }

    func decodificar<T: Decodable>(_ tipo: T.Type, _ datos: Data) throws -> T {
        do {
            return try Codificacion.decoder().decode(tipo, from: datos)
        } catch {
            throw AppError.servidor("El servidor respondió algo que la app no entiende. Actualiza la app o intenta más tarde.")
        }
    }

    private func peticion(_ metodo: String, _ ruta: String, _ consulta: [URLQueryItem], _ cuerpo: CuerpoHTTP?,
                          _ bearer: String?, _ cabeceras: [String: String] = [:]) throws -> URLRequest {
        guard var partes = URLComponents(url: base.appending(path: ruta), resolvingAgainstBaseURL: false) else {
            throw AppError.servidor(Self.mensajeServidor)
        }
        if !consulta.isEmpty { partes.queryItems = consulta }
        guard let url = partes.url else { throw AppError.servidor(Self.mensajeServidor) }
        var peticion = URLRequest(url: url)
        peticion.httpMethod = metodo
        peticion.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cuerpo {
            peticion.httpBody = cuerpo.datos
            peticion.setValue(cuerpo.tipo, forHTTPHeaderField: "Content-Type")
        }
        if let bearer { peticion.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        for (nombre, valor) in cabeceras { peticion.setValue(valor, forHTTPHeaderField: nombre) }
        return peticion
    }

    /// Cualquier fallo de red (sin conexión, servidor apagado, tiempo agotado) es `sinConexion`: no se sabe
    /// si la sesión sirve, así que nadie la cierra por esto.
    private func transportar(_ peticion: URLRequest) async throws -> (Data, Int) {
        do {
            let (datos, respuesta) = try await sesion.data(for: peticion)
            guard let http = respuesta as? HTTPURLResponse else { throw AppError.servidor(Self.mensajeServidor) }
            return (datos, http.statusCode)
        } catch let error as AppError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw AppError.sinConexion
        }
    }

    // MARK: - Renovar el access token

    private func renovar(usado: String) async throws -> String {
        // Otra petición pudo renovarlo mientras esta esperaba su 401.
        if let actual = try? secretos.leer(.accessToken), actual != usado { return actual }
        return try await renovador.renovar { try await pedirTokenNuevo() }
    }

    private func pedirTokenNuevo() async throws -> String {
        guard let refresh = try? secretos.leer(.refreshToken) else { throw AppError.sesionExpirada }
        let cuerpo = try CuerpoHTTP.json(["refreshToken": refresh])
        let (datos, estado) = try await transportar(try peticion("POST", "auth/refresh", [], cuerpo, nil))
        // El servidor rechazó el refresh: la sesión terminó de verdad.
        if estado == 400 || estado == 401 { throw AppError.sesionExpirada }
        guard estado == 200 else { throw Self.error(estado: estado, datos: datos, contexto: .general) }
        let nuevo = try decodificar(TokensDTO.self, datos).accessToken
        // Si mientras tanto cerraron sesión (o entró otra persona), este token ya no es de nadie: no se guarda.
        guard let vigente = try? secretos.leer(.refreshToken), vigente == refresh else { throw AppError.sesionExpirada }
        do {
            try secretos.guardar(nuevo, para: .accessToken)
        } catch {
            throw AppError.servidor("No se pudo guardar tu sesión de forma segura. Intenta de nuevo.")
        }
        return nuevo
    }

    // MARK: - Errores

    /// `{ "message": "..." }` o `{ "message": ["...", "..."] }`, como responde NestJS.
    private nonisolated struct ErrorServidor: Decodable {
        let mensajes: [String]

        nonisolated enum Llaves: String, CodingKey { case message }

        init(from decoder: Decoder) throws {
            let contenedor = try decoder.container(keyedBy: Llaves.self)
            if let uno = try? contenedor.decode(String.self, forKey: .message) {
                mensajes = [uno]
            } else {
                mensajes = (try? contenedor.decode([String].self, forKey: .message)) ?? []
            }
        }
    }

    static func error(estado: Int, datos: Data, contexto: Contexto) -> AppError {
        // El texto viene de fuera: se limpia y se acota antes de mostrarlo.
        let mensajes = ((try? JSONDecoder().decode(ErrorServidor.self, from: datos))?.mensajes ?? [])
            .prefix(10).map { Sanitizador.texto($0, maximo: 300) }.filter { !$0.isEmpty }
        let primero = mensajes.first
        switch estado {
        case 400, 422:
            return .validacion(mensajes.isEmpty ? ["Revisa los datos e inténtalo de nuevo."] : mensajes)
        case 401:
            switch contexto {
            case .login: return .credencialesInvalidas
            case .codigo: return .codigoInvalido
            case .general: return .sesionExpirada
            }
        case 403:
            return (primero ?? "").localizedCaseInsensitiveContains("suspendida") ? .cuentaSuspendida : .sinPermiso
        case 404:
            return .noEncontrado
        case 409:
            return .conflicto(primero ?? "No se pudo completar: los datos cambiaron mientras tanto.")
        case 413:
            return .validacion(["El archivo es demasiado grande."])
        case 429:
            return .limiteExcedido(primero ?? "Demasiadas solicitudes. Intenta de nuevo en un momento.")
        default:
            return .servidor(mensajeServidor)
        }
    }
}
