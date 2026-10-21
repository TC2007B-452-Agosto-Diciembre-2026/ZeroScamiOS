//
//  DemoServer.swift
//  PrototipoApp
//
//  "Servidor" del modo Demo: hace dentro de la app lo que hará el backend NestJS del Equipo
//  ZeroScam. Es un actor para que dos operaciones nunca se pisen, y cada método recibe el token
//  como el servidor lo recibe en el encabezado Authorization. Esconder un botón no es
//  seguridad: los permisos se revisan aquí.
//  Este archivo: núcleo, sesión y la vista de un reporte según quién lo pide. Reportes en
//  DemoServer+Reportes.swift; cuenta, moderación y Owner en DemoServer+Cuenta.swift.
//

import CryptoKit
import Foundation

actor DemoServer {
    // Los `static` van marcados `nonisolated`: con MainActor por defecto, si no, el actor no
    // podría usarlos sin `await`.
    nonisolated static let duracionSesion: TimeInterval = 7 * 24 * 3_600
    nonisolated static let duracionCodigo: TimeInterval = 5 * 60
    /// Códigos para cambiar o recuperar la contraseña (los mismos 10 minutos que el API).
    nonisolated static let duracionCodigoCorreo: TimeInterval = 10 * 60
    /// Mismo tope que `Validador.contrasenaNueva`: una contraseña más larga no puede ser válida y no
    /// se manda al hash (el login es entrada externa y no debe poder encarecer el trabajo).
    nonisolated static let contrasenaMaximaEscalares = 256

    var db: DemoDatabase
    let almacen: DemoAlmacen
    let archivos: ArchivosEvidencia
    let hasher: PasswordHasher
    let reloj: @Sendable () -> Date
    /// El archivo existe pero no se pudo leer (por ejemplo, teléfono bloqueado). Mientras sea cierto,
    /// `db` es solo una semilla en memoria y NADA se escribe: el archivo bueno no se pisa.
    private var lecturaPendiente = false
    /// Envíos recientes de códigos por correo, por "usuario|propósito". En memoria, como en el API:
    /// sin este límite, pedir un código nuevo cada 3 intentos permitiría adivinarlo sin fin.
    private var enviosCodigo: [String: [Date]] = [:]
    nonisolated static let enviosCodigoMaximos = 3
    nonisolated static let ventanaEnviosCodigo: TimeInterval = 15 * 60

    init(almacen: DemoAlmacen, archivos: ArchivosEvidencia, hasher: PasswordHasher,
         reloj: @escaping @Sendable () -> Date = { Date() }) {
        self.almacen = almacen
        self.archivos = archivos
        self.hasher = hasher
        self.reloj = reloj
        if let guardada = almacen.cargar(), guardada.version == DemoDatabase.versionActual {
            db = guardada
        } else if FileManager.default.fileExists(atPath: almacen.archivo.path(percentEncoded: false)) {
            // `cargar()` devuelve nil sin apartar el archivo cuando falla la lectura: sembrar y guardar
            // aquí borraría los datos buenos. Se trabaja con la semilla en memoria hasta poder leer.
            db = DemoSeed.base(ahora: reloj())
            lecturaPendiente = true
        } else {
            db = DemoSeed.base(ahora: reloj())
            try? almacen.guardar(db)
        }
    }

    var ahora: Date { reloj() }

    /// Se llama después de cada cambio (como un COMMIT).
    func persistir() throws {
        if lecturaPendiente {
            // Si ya se pudo leer, `db` acaba de ser reemplazada por la real y el cambio de esta operación
            // se perdió: se avisa para que se repita. Mientras no se pueda leer, tampoco se escribe.
            let recargada = recuperarLectura()
            if recargada || lecturaPendiente { throw AppError.servidor(Self.mensajeDatosNoDisponibles) }
        }
        try almacen.guardar(db)
    }

    nonisolated static let mensajeDatosNoDisponibles = "Los datos de la app no están disponibles ahora. Desbloquea el teléfono e inténtalo de nuevo."

    /// Si la base no se puede leer todavía, la operación falla con un error de servidor: con la semilla en
    /// memoria un token válido parecería vencido y la app borraría la sesión del Keychain por error.
    private func exigirLecturaDisponible() throws {
        recuperarLectura()
        if lecturaPendiente { throw AppError.servidor(Self.mensajeDatosNoDisponibles) }
    }

    /// Reintenta leer la base si el arranque no pudo. Devuelve true si `db` se reemplazó por la del disco.
    /// Si el archivo ya no existe (o se apartó por dañado) se sigue con la semilla y se podrá guardar.
    @discardableResult
    private func recuperarLectura() -> Bool {
        guard lecturaPendiente else { return false }
        if let guardada = almacen.cargar() {
            db = guardada
            lecturaPendiente = false
            return true
        }
        if !FileManager.default.fileExists(atPath: almacen.archivo.path(percentEncoded: false)) {
            lecturaPendiente = false
        }
        return false
    }

    /// SHA-256 en hexadecimal: así se guardan tokens y códigos.
    nonisolated static func huella(_ texto: String) -> String {
        SHA256.hash(data: Data(texto.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// "usuario@0fraude.mx" → "u••••••@0fraude.mx" (tantos puntos como letras tiene el nombre menos una, mínimo 3).
    nonisolated static func enmascarar(_ correo: String) -> String {
        let partes = correo.split(separator: "@", maxSplits: 1)
        guard partes.count == 2, let inicial = partes[0].first else { return "tu correo" }
        return "\(inicial)\(String(repeating: "•", count: max(3, partes[0].count - 1)))@\(partes[1])"
    }

    // MARK: - Identidad

    /// Como un middleware de autenticación: token → usuario activo.
    func usuarioActual(_ token: String?) throws -> Usuario {
        try exigirLecturaDisponible()
        guard let token else { throw AppError.sesionExpirada }
        let huella = Self.huella(token)
        guard let sesion = db.sesiones.first(where: { $0.tokenHash == huella }),
              sesion.expira > ahora,
              let fila = db.usuarios.first(where: { $0.usuario.id == sesion.idUsuario })
        else { throw AppError.sesionExpirada }
        guard fila.usuario.estadoCuenta == .activo else { throw AppError.cuentaSuspendida }
        return fila.usuario
    }

    func exigirStaff(_ u: Usuario) throws {
        guard u.rol.esStaff else { throw AppError.sinPermiso }
    }

    func exigirOwner(_ u: Usuario) throws {
        guard u.rol == .owner else { throw AppError.sinPermiso }
    }

    func indiceUsuario(_ id: Int64) -> Int? { db.usuarios.firstIndex { $0.usuario.id == id } }
    func indiceReporte(_ id: Int64) -> Int? { db.reportes.firstIndex { $0.id == id } }

    /// Analíticas anónimas: un contador por evento, sin id de usuario, y solo si la persona lo permite.
    func registrarEvento(_ nombre: String, de usuario: Usuario) {
        guard usuario.preferencias.analiticas else { return }
        // El contador viene de disco: saturado en vez de `+= 1`, que detendría la app en Int.max.
        let (suma, desbordo) = db.analiticas[nombre, default: 0].addingReportingOverflow(1)
        db.analiticas[nombre] = desbordo ? Int.max : suma
    }

    /// Fila de Notificacion_Alerta para alguien (la usan comentarios y moderación).
    func notificar(_ idUsuario: Int64, reporte: Int64?, _ mensaje: String) {
        db.notificaciones.append(NotificacionFila(id: db.siguienteID(), idUsuario: idUsuario, idReporte: reporte,
                                                  mensaje: mensaje, leida: false, fecha: ahora))
    }

    // MARK: - Registro y sesión

    func registrar(_ entrada: RegistroDatos) throws -> Usuario {
        try exigirLecturaDisponible()
        var d = entrada
        d.nombre = Sanitizador.texto(d.nombre, maximo: 50)
        d.apellido = Sanitizador.texto(d.apellido, maximo: 50)
        d.pais = Sanitizador.texto(d.pais, maximo: 60)
        d.alias = Sanitizador.alias(d.alias)
        d.correo = Sanitizador.correo(d.correo)
        let errores = Validador.registro(d)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        guard !db.usuarios.contains(where: { $0.usuario.correo == d.correo }) else {
            throw AppError.conflicto("Ese correo ya tiene una cuenta. Inicia sesión.")
        }
        guard !db.usuarios.contains(where: { $0.usuario.alias == d.alias }) else {
            throw AppError.conflicto("Ese nombre de usuario ya está en uso.")
        }
        let usuario = Usuario(id: db.siguienteID(), rol: .usuario, nombre: d.nombre, apellido: d.apellido,
                              pais: d.pais, alias: d.alias, correo: d.correo, biografia: "", avatarRuta: nil,
                              estadoCuenta: .activo, fechaRegistro: ahora, preferencias: Preferencias(),
                              consentimiento: Consentimiento(versionAviso: Consentimiento.versionAvisoVigente, fecha: ahora))
        db.usuarios.append(UsuarioFila(usuario: usuario, contrasenaHash: hasher.hash(d.contrasena)))
        try persistir()
        return usuario
    }

    func iniciarSesion(correo: String, contrasena: String) throws -> ResultadoLogin {
        try exigirLecturaDisponible()
        let clave = Sanitizador.correo(correo)
        var intentos = db.intentos[clave] ?? RegistroIntentos()
        if let hasta = LimiteIntentos.bloqueadoHasta(intentos, ahora: ahora) {
            throw AppError.cuentaBloqueada(hasta: hasta)
        }
        let fila = db.usuarios.first { $0.usuario.correo == clave }
        // Si el correo no existe se verifica contra un hash señuelo: tarda lo mismo y no delata qué correos existen.
        let correcta = contrasenaCoincide(contrasena, con: fila?.contrasenaHash ?? DemoSeed.hashSenuelo)
        guard let fila, correcta else {
            LimiteIntentos.registrarFallo(&intentos, ahora: ahora)
            db.intentos[clave] = intentos
            try persistir()
            if let hasta = LimiteIntentos.bloqueadoHasta(intentos, ahora: ahora) {
                throw AppError.cuentaBloqueada(hasta: hasta)
            }
            throw AppError.credencialesInvalidas
        }
        db.intentos[clave] = nil
        guard fila.usuario.estadoCuenta == .activo else {
            try persistir()
            throw AppError.cuentaSuspendida
        }
        if fila.usuario.preferencias.dosPasos {
            let desafio = crearDesafio(para: fila.usuario)
            try persistir()
            return .requiereCodigo(desafio)
        }
        let sesion = abrirSesion(para: fila.usuario)
        try persistir()
        return .sesion(sesion)
    }

    /// Verifica una contraseña venida de fuera. Una demasiado larga nunca coincide y no se manda al hash
    /// (se hace igual el trabajo de un hash para que no cambie el tiempo de respuesta).
    func contrasenaCoincide(_ contrasena: String, con hash: String) -> Bool {
        guard contrasena.unicodeScalars.count <= Self.contrasenaMaximaEscalares else {
            _ = hasher.verificar("", contra: hash)
            return false
        }
        return hasher.verificar(contrasena, contra: hash)
    }

    /// Pide la contraseña otra vez para una acción delicada (cambiar contraseña, apagar dos pasos...).
    /// Cuenta los fallos igual que el login (misma clave: el correo) para que un token robado no sirva
    /// para adivinar la contraseña: revisa el bloqueo ANTES de verificar y un acierto reinicia el contador.
    /// D7 debe usarlo en actualizarPerfil (cambio de correo) y eliminarCuenta.
    func reautenticar(_ yo: Usuario, contrasena: String?) throws {
        let clave = Sanitizador.correo(yo.correo)
        var intentos = db.intentos[clave] ?? RegistroIntentos()
        if let hasta = LimiteIntentos.bloqueadoHasta(intentos, ahora: ahora) {
            throw AppError.cuentaBloqueada(hasta: hasta)
        }
        guard let contrasena else { throw AppError.validacion(["Confirma tu contraseña para continuar."]) }
        guard let i = indiceUsuario(yo.id), contrasenaCoincide(contrasena, con: db.usuarios[i].contrasenaHash) else {
            LimiteIntentos.registrarFallo(&intentos, ahora: ahora)
            db.intentos[clave] = intentos
            try persistir()
            if let hasta = LimiteIntentos.bloqueadoHasta(intentos, ahora: ahora) {
                throw AppError.cuentaBloqueada(hasta: hasta)
            }
            throw AppError.credencialesInvalidas
        }
        db.intentos[clave] = nil
    }

    func abrirSesion(para usuario: Usuario) -> SesionActiva {
        let token = Aleatorio.token()
        db.sesiones.removeAll { $0.expira <= ahora }
        db.sesiones.append(SesionFila(tokenHash: Self.huella(token), idUsuario: usuario.id, creada: ahora,
                                      expira: ahora.addingTimeInterval(Self.duracionSesion)))
        registrarEvento("inicio_sesion", de: usuario)
        return SesionActiva(accessToken: token, refreshToken: nil, usuario: usuario)
    }

    /// Un código nuevo anula los anteriores del mismo propósito (un código de login no anula uno
    /// para cambiar la contraseña, ni al revés).
    func crearDesafio(para usuario: Usuario, proposito: PropositoCodigo? = nil) -> DesafioDosPasos {
        let codigo = Aleatorio.codigo()
        let duracion = proposito == nil ? Self.duracionCodigo : Self.duracionCodigoCorreo
        let fila = DesafioFila(id: Aleatorio.token(), idUsuario: usuario.id, codigoHash: Self.huella(codigo),
                               expira: ahora.addingTimeInterval(duracion), intentos: 0, proposito: proposito)
        db.desafios.removeAll { ($0.idUsuario == usuario.id && $0.proposito == proposito) || $0.expira <= ahora }
        db.desafios.append(fila)
        return DesafioDosPasos(id: fila.id, destino: Self.enmascarar(usuario.correo), expira: fila.expira, codigoDemo: codigo)
    }

    /// Desafío vigente con ese id y propósito, sin gastar intento.
    func desafioVigente(_ id: String, proposito: PropositoCodigo?) -> DesafioFila? {
        db.desafios.first { $0.id == id && $0.proposito == proposito && $0.expira > ahora }
    }

    /// Canjea un código: si coincide, el desafío se borra y regresa de quién era. Si no, gasta un
    /// intento (al tercero el desafío se borra) y lanza `.codigoInvalido`.
    func canjearCodigo(_ id: String, _ codigo: String, proposito: PropositoCodigo?) throws -> Int64 {
        guard let i = db.desafios.firstIndex(where: { $0.id == id && $0.proposito == proposito }),
              db.desafios[i].expira > ahora else {
            throw AppError.codigoInvalido
        }
        let esperado = Data(db.desafios[i].codigoHash.utf8)
        guard PasswordHasher.igualesEnTiempoConstante(Data(Self.huella(codigo).utf8), esperado) else {
            // `intentos` viene de disco: un negativo no da intentos extra y Int.max no desborda.
            let previos = max(0, db.desafios[i].intentos)
            db.desafios[i].intentos = previos == Int.max ? previos : previos + 1
            if db.desafios[i].intentos >= 3 { db.desafios.remove(at: i) }
            try persistir()
            throw AppError.codigoInvalido
        }
        let idUsuario = db.desafios[i].idUsuario
        db.desafios.remove(at: i)
        return idUsuario
    }

    func verificarCodigo(desafio id: String, codigo: String) throws -> SesionActiva {
        try exigirLecturaDisponible()
        let idUsuario = try canjearCodigo(id, codigo, proposito: nil)
        guard let fila = db.usuarios.first(where: { $0.usuario.id == idUsuario }),
              fila.usuario.estadoCuenta == .activo else { throw AppError.codigoInvalido }
        let sesion = abrirSesion(para: fila.usuario)
        try persistir()
        return sesion
    }

    func cerrarSesion(token: String?) throws {
        guard let token else { return }
        try exigirLecturaDisponible()
        let huella = Self.huella(token)
        db.sesiones.removeAll { $0.tokenHash == huella }
        try persistir()
    }

    /// Aparta un envío de código por correo, o dice que ya se pidieron demasiados.
    private func tomarCupoDeEnvio(_ idUsuario: Int64, _ proposito: PropositoCodigo) -> Bool {
        let clave = "\(idUsuario)|\(proposito.rawValue)"
        let recientes = (enviosCodigo[clave] ?? []).filter { ahora.timeIntervalSince($0) < Self.ventanaEnviosCodigo }
        guard recientes.count < Self.enviosCodigoMaximos else {
            enviosCodigo[clave] = recientes
            return false
        }
        enviosCodigo[clave] = recientes + [ahora]
        return true
    }

    nonisolated static let mensajeDemasiadosCodigos = "Pediste varios códigos seguidos. Espera unos minutos e inténtalo de nuevo."

    /// En el API el código sale por correo; aquí regresa en `codigoDemo` para mostrarlo en pantalla.
    func pedirCodigoContrasena(token: String?) throws -> DesafioDosPasos {
        let yo = try usuarioActual(token)
        guard tomarCupoDeEnvio(yo.id, .cambiar) else { throw AppError.limiteExcedido(Self.mensajeDemasiadosCodigos) }
        let desafio = crearDesafio(para: yo, proposito: .cambiar)
        try persistir()
        return desafio
    }

    /// Pide el código de `pedirCodigoContrasena` y la contraseña actual, en ese orden (como el API):
    /// sin un código bueno no se revisa la contraseña, así que un token robado no sirve para
    /// adivinarla. Si la actual está mal, el código ya se gastó. Un código que no es de esta cuenta
    /// es inválido aunque exista.
    func cambiarContrasena(token: String?, actual: String, nueva: String, desafio: String, codigo: String) throws {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id) else { throw AppError.sesionExpirada }
        let errores = Validador.contrasenaNueva(nueva, confirmacion: nueva, alias: yo.alias, correo: yo.correo)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        guard actual != nueva else { throw AppError.validacion(["La nueva contraseña debe ser distinta de la actual."]) }
        // Solo se busca entre los códigos de esta cuenta: el de otra persona no gasta sus intentos.
        guard let fila = desafioVigente(desafio, proposito: .cambiar), fila.idUsuario == yo.id else {
            throw AppError.codigoInvalido
        }
        _ = try canjearCodigo(fila.id, codigo, proposito: .cambiar)
        // El canje ya se hizo: aunque la actual esté mal, el código no se puede reusar.
        do {
            try reautenticar(yo, contrasena: actual)
        } catch {
            try persistir()
            throw error
        }
        db.usuarios[i].contrasenaHash = hasher.hash(nueva)
        // Las demás sesiones se cierran: si alguien más tenía acceso, lo pierde.
        let mia = token.map(Self.huella)
        db.sesiones.removeAll { $0.idUsuario == yo.id && $0.tokenHash != mia }
        db.desafios.removeAll { $0.idUsuario == yo.id }
        try persistir()
    }

    /// "Olvidé mi contraseña". Exista o no la cuenta responde un desafío con la misma forma; solo
    /// trae `codigoDemo` si de verdad se "mandó" un correo.
    func olvideContrasena(correo: String) throws -> DesafioDosPasos {
        try exigirLecturaDisponible()
        let clave = Sanitizador.correo(correo)
        // Sin cupo responde igual que si la cuenta no existiera (el API tampoco lo dice aquí).
        guard let fila = db.usuarios.first(where: { $0.usuario.correo == clave }),
              fila.usuario.estadoCuenta == .activo, tomarCupoDeEnvio(fila.usuario.id, .recuperar) else {
            return DesafioDosPasos(id: Aleatorio.token(), destino: Self.enmascarar(clave),
                                   expira: ahora.addingTimeInterval(Self.duracionCodigoCorreo), codigoDemo: nil)
        }
        let desafio = crearDesafio(para: fila.usuario, proposito: .recuperar)
        try persistir()
        return desafio
    }

    /// La contraseña nueva se revisa ANTES de canjear el código: una regla incumplida no gasta
    /// intento. Cierra todas las sesiones de la cuenta y quita el bloqueo por intentos fallidos
    /// (quien tiene el correo ya demostró ser la dueña de la cuenta).
    func restablecerContrasena(desafio: String, codigo: String, nueva: String) throws {
        try exigirLecturaDisponible()
        guard let fila = desafioVigente(desafio, proposito: .recuperar), let i = indiceUsuario(fila.idUsuario),
              db.usuarios[i].usuario.estadoCuenta == .activo else {
            throw AppError.codigoInvalido
        }
        let yo = db.usuarios[i].usuario
        let errores = Validador.contrasenaNueva(nueva, confirmacion: nueva, alias: yo.alias, correo: yo.correo)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        _ = try canjearCodigo(fila.id, codigo, proposito: .recuperar)
        db.usuarios[i].contrasenaHash = hasher.hash(nueva)
        db.sesiones.removeAll { $0.idUsuario == yo.id }
        db.desafios.removeAll { $0.idUsuario == yo.id }
        db.intentos[Sanitizador.correo(yo.correo)] = nil
        try persistir()
    }

    func actualizarPreferencias(token: String?, _ nuevas: Preferencias, contrasena: String?) throws -> Usuario {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id) else { throw AppError.sesionExpirada }
        if yo.preferencias.dosPasos && !nuevas.dosPasos {
            try reautenticar(yo, contrasena: contrasena)
        }
        db.usuarios[i].usuario.preferencias = nuevas
        try persistir()
        return db.usuarios[i].usuario
    }

    func aceptarAviso(token: String?, version: String) throws -> Usuario {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id) else { throw AppError.sesionExpirada }
        db.usuarios[i].usuario.consentimiento = Consentimiento(versionAviso: version, fecha: Date())
        try persistir()
        return db.usuarios[i].usuario
    }

    // MARK: - Lo que cada quien puede ver

    func puedeVer(_ f: ReporteFila, _ yo: Usuario) -> Bool {
        f.estado.esPublico || f.idUsuario == yo.id || yo.rol.esStaff
    }

    /// Arma el reporte para `yo`: autor anónimo o privado oculto, persona afectada y evidencia
    /// solo para el autor y el staff, contadores y marcas personales.
    func vista(_ f: ReporteFila, para yo: Usuario) -> Reporte {
        let esMio = f.idUsuario == yo.id
        let privilegiado = esMio || yo.rol.esStaff
        let autor = f.idUsuario.flatMap { id in db.usuarios.first { $0.usuario.id == id }?.usuario }
        let nombre: String
        if let autor {
            if f.esAnonimo {
                nombre = esMio ? "Tú (anónimo)" : (yo.rol.esStaff ? "\(autor.alias) (anónimo)" : "Anónimo")
            } else {
                nombre = esMio ? "Tú" : (autor.preferencias.perfilPublico || yo.rol.esStaff ? autor.alias : "Miembro de la comunidad")
            }
        } else {
            nombre = "Cuenta eliminada"
        }
        let muestraId = privilegiado || (!f.esAnonimo && (autor?.preferencias.perfilPublico ?? false))
        let evidencias = db.evidencias.filter { $0.idReporte == f.id }
        return Reporte(
            id: f.id,
            autor: AutorVisible(idUsuario: muestraId ? f.idUsuario : nil, nombre: nombre),
            tipo: f.tipo, tipoOtro: f.tipoOtro, estado: f.estado,
            titulo: f.titulo, descripcion: f.descripcion, fechaIncidente: f.fechaIncidente,
            nivelRiesgo: f.nivelRiesgo, fechaCreacion: f.fechaCreacion,
            esAnonimo: f.esAnonimo, afectado: f.afectado, ciudad: f.ciudad,
            personaAfectada: privilegiado ? f.persona : nil,
            sitio: f.idSitio.flatMap { id in db.sitios.first { $0.id == id } },
            textoSospechoso: f.textoSospechoso,
            evidencias: privilegiado ? evidencias.map(\.evidencia) : [],
            totalEvidencias: evidencias.count,
            confirmaciones: Self.sumaSaturada(f.confirmacionesPrevias, db.confirmaciones.filter { $0.idReporte == f.id }.count),
            comentarios: db.comentarios.filter { $0.idReporte == f.id }.count,
            confirmadoPorMi: db.confirmaciones.contains { $0.idReporte == f.id && $0.idUsuario == yo.id },
            guardadoPorMi: db.guardados.contains { $0.idReporte == f.id && $0.idUsuario == yo.id },
            esMio: esMio)
    }

    /// Los contadores previos vienen de disco: una suma que desbordaría se queda en el máximo, y un negativo cuenta 0.
    nonisolated static func sumaSaturada(_ a: Int, _ b: Int) -> Int {
        let (suma, desbordo) = max(0, a).addingReportingOverflow(max(0, b))
        return desbordo ? Int.max : suma
    }

    /// Nombre de quien comenta, con la misma regla de perfil público.
    func nombreVisible(de idUsuario: Int64?, para yo: Usuario) -> String {
        guard let idUsuario, let u = db.usuarios.first(where: { $0.usuario.id == idUsuario })?.usuario else {
            return "Cuenta eliminada"
        }
        if idUsuario == yo.id { return "Tú" }
        return u.preferencias.perfilPublico || yo.rol.esStaff ? u.alias : "Miembro de la comunidad"
    }
}
