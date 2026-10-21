//
//  DemoServer+Cuenta.swift
//  PrototipoApp
//
//  Perfil, derechos ARCO (exportar y eliminar), notificaciones, moderación y lo que solo puede
//  hacer el Owner. La moderación sigue la máquina de estados de `EstadoReporte.siguientes`.
//  Como en DemoServer+Reportes.swift, cada operación empieza con `usuarioActual` y las que cambian
//  datos se guardan con `transaccion`; los archivos de disco se borran hasta que el cambio ya quedó
//  guardado (si el guardado falla, nada se pierde).
//

import Foundation

/// Lo que recibe la persona al pedir "Descargar mis datos" (derecho de acceso).
nonisolated struct ExportacionDatos: Encodable, Sendable {
    let generado: Date
    let usuario: Usuario
    let reportes: [Reporte]
    let comentarios: [Comentario]
    let guardados: [Int64]
    let confirmaciones: [Int64]
    let notificaciones: [Notificacion]
}

extension DemoServer {
    nonisolated static let mensajeContrasenaIncorrecta = "La contraseña no es correcta."

    /// Pide la contraseña para una acción delicada con el límite de intentos de `reautenticar`. Una
    /// contraseña equivocada se dice con el texto de esta pantalla (no con "Correo o contraseña
    /// incorrectos", que es del login); el bloqueo se informa tal cual.
    private func reautenticarParaAccion(_ yo: Usuario, contrasena: String?) throws {
        do {
            try reautenticar(yo, contrasena: contrasena)
        } catch AppError.credencialesInvalidas {
            throw AppError.validacion([Self.mensajeContrasenaIncorrecta])
        }
    }

    // MARK: - Perfil

    func actualizarPerfil(token: String?, _ entrada: PerfilDatos) throws -> Usuario {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id) else { throw AppError.sesionExpirada }
        var d = entrada
        d.nombre = Sanitizador.texto(d.nombre, maximo: 50)
        d.apellido = Sanitizador.texto(d.apellido, maximo: 50)
        d.pais = Sanitizador.texto(d.pais, maximo: 60)
        d.alias = Sanitizador.alias(d.alias)
        d.correo = Sanitizador.correo(d.correo)
        d.biografia = Sanitizador.texto(d.biografia, maximo: 300, multilinea: true)
        let errores = Validador.perfil(d, correoOriginal: yo.correo)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        if d.correo != yo.correo {
            // Antes de decir si el correo ya existe: quien no sabe la contraseña no averigua nada.
            try reautenticarParaAccion(yo, contrasena: d.contrasenaActual)
            guard !db.usuarios.contains(where: { $0.usuario.correo == d.correo }) else {
                throw AppError.conflicto("Ese correo ya tiene una cuenta.")
            }
        }
        if d.alias != yo.alias, db.usuarios.contains(where: { $0.usuario.alias == d.alias }) {
            throw AppError.conflicto("Ese nombre de usuario ya está en uso.")
        }
        return try transaccion {
            db.usuarios[i].usuario.nombre = d.nombre
            db.usuarios[i].usuario.apellido = d.apellido
            db.usuarios[i].usuario.pais = d.pais
            db.usuarios[i].usuario.alias = d.alias
            db.usuarios[i].usuario.correo = d.correo
            db.usuarios[i].usuario.biografia = d.biografia
            return db.usuarios[i].usuario
        }
    }

    /// `nil` quita el avatar. El archivo nuevo se confirma antes de guardar y el anterior se borra hasta
    /// después: si el guardado falla, queda el avatar de antes y no sobra ningún archivo.
    func actualizarAvatar(token: String?, _ adjunto: Adjunto?) throws -> Usuario {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id) else { throw AppError.sesionExpirada }
        if let adjunto, adjunto.tipoArchivo != "image/jpeg" || !adjunto.nombreArchivo.hasSuffix(".jpg") {
            throw AppError.validacion(["El avatar debe ser una imagen."])
        }
        var nueva: String?
        if let adjunto {
            do {
                nueva = try archivos.confirmar(adjunto)
            } catch {
                throw AppError.validacion(["No se pudo usar la imagen. Vuelve a elegirla."])
            }
        }
        let anterior = db.usuarios[i].usuario.avatarRuta
        let usuario: Usuario
        do {
            usuario = try transaccion {
                db.usuarios[i].usuario.avatarRuta = nueva
                return db.usuarios[i].usuario
            }
        } catch {
            borrarArchivos(nueva.map { [$0] } ?? [])
            throw error
        }
        borrarArchivos(anterior.map { [$0] } ?? [])
        return usuario
    }

    /// El avatar se ve si es tuyo, si eres staff o si esa persona tiene perfil público. Un archivo
    /// ausente o ilegible es lo mismo que no tener avatar.
    func datosAvatar(token: String?, de usuario: Usuario) throws -> Data? {
        let yo = try usuarioActual(token)
        guard let fila = db.usuarios.first(where: { $0.usuario.id == usuario.id }),
              let ruta = fila.usuario.avatarRuta,
              fila.usuario.id == yo.id || yo.rol.esStaff || fila.usuario.preferencias.perfilPublico
        else { return nil }
        return try? archivos.datos(ruta: ruta)
    }

    func exportarMisDatos(token: String?) throws -> Data {
        let yo = try usuarioActual(token)
        let exportacion = ExportacionDatos(
            generado: ahora,
            usuario: yo,
            reportes: try misReportes(token: token),
            comentarios: db.comentarios.filter { $0.idUsuario == yo.id }.map {
                Comentario(id: $0.id, idReporte: $0.idReporte, autor: "Tú", esMio: true, texto: $0.texto, fecha: $0.fecha)
            },
            guardados: db.guardados.filter { $0.idUsuario == yo.id }.map(\.idReporte),
            confirmaciones: db.confirmaciones.filter { $0.idUsuario == yo.id }.map(\.idReporte),
            notificaciones: try notificaciones(token: token))
        let encoder = Codificacion.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exportacion)
    }

    /// Derecho de cancelación: lo público sigue ayudando a la comunidad pero sin rastro de la persona
    /// (sin autor, sin persona afectada, sin evidencia); lo demás se borra, incluido el correo. Todo se
    /// guarda de una vez; los archivos (evidencia y avatar) se borran solo si el guardado tuvo éxito.
    func eliminarCuenta(token: String?, contrasena: String) throws {
        let yo = try usuarioActual(token)
        guard yo.rol != .owner else { throw AppError.conflicto("La cuenta Owner no se puede eliminar desde la app.") }
        try reautenticarParaAccion(yo, contrasena: contrasena)
        let rutas: [String] = try transaccion {
            var rutas: [String] = []
            for r in db.reportes.filter({ $0.idUsuario == yo.id }) {
                if r.estado.esPublico, let j = indiceReporte(r.id) {
                    db.reportes[j].idUsuario = nil
                    db.reportes[j].persona = nil
                    db.reportes[j].esAnonimo = true
                    rutas += db.evidencias.filter { $0.idReporte == r.id }.map(\.rutaArchivo)
                    db.evidencias.removeAll { $0.idReporte == r.id }
                } else {
                    rutas += borrarReporte(r.id, archivos: false)
                }
            }
            for j in db.comentarios.indices where db.comentarios[j].idUsuario == yo.id { db.comentarios[j].idUsuario = nil }
            db.guardados.removeAll { $0.idUsuario == yo.id }
            db.confirmaciones.removeAll { $0.idUsuario == yo.id }
            db.notificaciones.removeAll { $0.idUsuario == yo.id }
            db.sesiones.removeAll { $0.idUsuario == yo.id }
            db.desafios.removeAll { $0.idUsuario == yo.id }
            // Los intentos de login se guardan por correo: el correo no debe sobrevivir a la cuenta.
            db.intentos[Sanitizador.correo(yo.correo)] = nil
            if let avatar = db.usuarios.first(where: { $0.usuario.id == yo.id })?.usuario.avatarRuta { rutas.append(avatar) }
            db.usuarios.removeAll { $0.usuario.id == yo.id }
            return rutas
        }
        borrarArchivos(rutas)
    }

    // MARK: - Notificaciones

    func notificaciones(token: String?) throws -> [Notificacion] {
        let yo = try usuarioActual(token)
        return db.notificaciones.filter { $0.idUsuario == yo.id }
            .sorted { $0.fecha != $1.fecha ? $0.fecha > $1.fecha : $0.id > $1.id }
            .map { Notificacion(id: $0.id, idReporte: $0.idReporte, mensaje: $0.mensaje, leida: $0.leida, fecha: $0.fecha) }
    }

    /// Ids ajenos se ignoran: nadie marca las notificaciones de otra persona. Si no hay nada por marcar
    /// no se escribe nada.
    func marcarLeidas(token: String?, _ ids: [Int64]) throws {
        let yo = try usuarioActual(token)
        let pedidas = Set(ids)   // la lista viene del cliente: se busca en un conjunto, no en el arreglo
        guard db.notificaciones.contains(where: { $0.idUsuario == yo.id && !$0.leida && pedidas.contains($0.id) }) else { return }
        try transaccion {
            for i in db.notificaciones.indices where db.notificaciones[i].idUsuario == yo.id && pedidas.contains(db.notificaciones[i].id) {
                db.notificaciones[i].leida = true
            }
        }
    }

    // MARK: - Moderación (Administrador y Owner)

    func colaModeracion(token: String?, estado: EstadoReporte?) throws -> [Reporte] {
        let yo = try usuarioActual(token)
        try exigirStaff(yo)
        let estados: Set<EstadoReporte> = estado.map { [$0] } ?? [.recibido, .enRevision]
        return db.reportes.filter { estados.contains($0.estado) }
            .sorted { $0.fechaCreacion != $1.fechaCreacion ? $0.fechaCreacion < $1.fechaCreacion : $0.id < $1.id }
            .map { vista($0, para: yo) }
    }

    func cambiarEstado(token: String?, id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?,
                       observaciones entrada: String) throws -> Reporte {
        let yo = try usuarioActual(token)
        try exigirStaff(yo)
        guard let i = indiceReporte(id) else { throw AppError.noEncontrado }
        // Separación de funciones: quien reporta no valida su propio reporte.
        guard db.reportes[i].idUsuario != yo.id else { throw AppError.conflicto("No puedes moderar tu propio reporte.") }
        let anterior = db.reportes[i].estado
        guard anterior.siguientes.contains(nuevo) else {
            throw AppError.conflicto("No se puede pasar de \(anterior.titulo) a \(nuevo.titulo).")
        }
        let observaciones = Sanitizador.texto(entrada, maximo: 500, multilinea: true)
        let errores = Validador.moderacion(nuevo: nuevo, riesgo: riesgo, observaciones: observaciones)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        let fila = try transaccion { () -> ReporteFila in
            db.reportes[i].estado = nuevo
            if nuevo == .validado, let riesgo { db.reportes[i].nivelRiesgo = riesgo }
            db.historial.append(HistorialFila(id: db.siguienteID(), idReporte: id, idResponsable: yo.id, anterior: anterior,
                                              nuevo: nuevo, observaciones: observaciones.isEmpty ? nil : observaciones, fecha: ahora))
            if nuevo.esPublico, let idSitio = db.reportes[i].idSitio, let s = db.sitios.firstIndex(where: { $0.id == idSitio }) {
                let riesgos = db.reportes.filter { $0.idSitio == idSitio && $0.estado.esPublico }.map(\.nivelRiesgo)
                db.sitios[s].nivelRiesgoGlobal = riesgos.max() ?? .bajo
                db.sitios[s].fechaUltimaEvaluacion = ahora
            }
            // El aviso solo lleva el título y el estado de SU reporte (y el motivo, si lo rechazaron).
            if let autor = db.reportes[i].idUsuario, indiceUsuario(autor) != nil {
                notificar(autor, reporte: id, Self.mensajeCambio(titulo: db.reportes[i].titulo, nuevo: nuevo, observaciones: observaciones))
            }
            return db.reportes[i]
        }
        return vista(fila, para: yo)
    }

    nonisolated static func mensajeCambio(titulo: String, nuevo: EstadoReporte, observaciones: String) -> String {
        switch nuevo {
        case .recibido: "Tu reporte «\(titulo)» fue RECIBIDO."
        case .enRevision: "Tu reporte «\(titulo)» está EN REVISIÓN."
        case .validado: "Tu reporte «\(titulo)» fue VALIDADO y ya es visible para la comunidad."
        case .rechazado: "Tu reporte «\(titulo)» fue RECHAZADO. Motivo: \(observaciones)"
        case .canalizado: "Tu reporte «\(titulo)» fue CANALIZADO a las autoridades."
        }
    }

    // MARK: - Owner

    func usuarios(token: String?) throws -> [Usuario] {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        return db.usuarios.map(\.usuario).sorted { $0.fechaRegistro != $1.fechaRegistro ? $0.fechaRegistro < $1.fechaRegistro : $0.id < $1.id }
    }

    /// Desde la app solo se asigna Usuario o Administrador; Owner y Policía se dan en la base. Nadie
    /// (ni el propio Owner) cambia el rol de un Owner.
    func cambiarRol(token: String?, idUsuario: Int64, a rol: Rol) throws -> Usuario {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        guard idUsuario != yo.id else { throw AppError.conflicto("No puedes cambiar tu propio rol.") }
        guard rol == .usuario || rol == .administrador else { throw AppError.sinPermiso }
        guard let i = indiceUsuario(idUsuario) else { throw AppError.noEncontrado }
        guard db.usuarios[i].usuario.rol != .owner else { throw AppError.sinPermiso }
        return try transaccion {
            db.usuarios[i].usuario.rol = rol
            return db.usuarios[i].usuario
        }
    }

    /// Suspender cierra de inmediato todas las sesiones y anula códigos de dos pasos pendientes.
    func cambiarEstadoCuenta(token: String?, idUsuario: Int64, a estado: EstadoCuenta) throws -> Usuario {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        guard idUsuario != yo.id else { throw AppError.conflicto("No puedes suspender tu propia cuenta.") }
        guard let i = indiceUsuario(idUsuario) else { throw AppError.noEncontrado }
        guard db.usuarios[i].usuario.rol != .owner else { throw AppError.sinPermiso }
        return try transaccion {
            db.usuarios[i].usuario.estadoCuenta = estado
            if estado == .suspendido {
                db.sesiones.removeAll { $0.idUsuario == idUsuario }
                db.desafios.removeAll { $0.idUsuario == idUsuario }
            }
            return db.usuarios[i].usuario
        }
    }

    /// Los contadores vienen de disco: un negativo se muestra como 0.
    func analiticas(token: String?) throws -> [String: Int] {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        return db.analiticas.mapValues { max(0, $0) }
    }

    /// Vuelve a la semilla (para repetir la demo). Cierra todas las sesiones, incluida la del Owner.
    /// La evidencia de disco se borra hasta que la base ya quedó restablecida.
    func restablecerDemo(token: String?) throws {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        try transaccion { db = DemoSeed.base(ahora: ahora) }
        try? archivos.borrarTodo()
    }
}
