//
//  DemoServer+Reportes.swift
//  PrototipoApp
//
//  Reportes, guardados, "Yo también", comentarios, historial, estadísticas y archivos de
//  evidencia del modo Demo. Lo que alguien no puede ver responde igual que lo que no existe
//  (`noEncontrado`), para no confirmar que existe.
//  Cada operación empieza con `usuarioActual` (que exige lectura disponible) y las que cambian
//  datos se guardan con `transaccion`: si el guardado falla, la memoria vuelve a como estaba.
//

import Foundation

extension DemoServer {
    nonisolated static let limiteReportesPorDia = 10
    nonisolated static let limiteComentariosPorMinuto = 5
    /// El texto de búsqueda se corta: es entrada externa y se compara contra todos los reportes.
    nonisolated static let maximoTextoBusqueda = 100

    // MARK: - Transacción

    /// Aplica un cambio y lo guarda. Si el cambio o el guardado fallan, `db` vuelve a su estado previo
    /// (sin esto, la memoria quedaría adelantada al disco hasta reiniciar la app). El actor no tiene
    /// puntos de suspensión aquí y cada operación ya pasó por `usuarioActual`, así que la base no puede
    /// ser reemplazada por la del disco a mitad del cambio.
    func transaccion<T>(_ cambio: () throws -> T) throws -> T {
        let respaldo = db
        do {
            let resultado = try cambio()
            try persistir()
            return resultado
        } catch {
            db = respaldo
            throw error
        }
    }

    func borrarArchivos(_ rutas: [String]) {
        for ruta in rutas { try? archivos.borrar(ruta: ruta) }
    }

    // MARK: - Listas

    func feed(token: String?, filtro entrada: FiltroBusqueda) throws -> [Reporte] {
        let yo = try usuarioActual(token)
        var filtro = entrada
        filtro.texto = Sanitizador.texto(entrada.texto, maximo: Self.maximoTextoBusqueda)
        if !filtro.estaVacio {
            registrarEvento("busqueda", de: yo)
            try? persistir()   // solo un contador anónimo: si no se guarda, no pasa nada
        }
        return db.reportes.filter(\.estado.esPublico)
            .map { vista($0, para: yo) }
            .filter { filtro.coincide($0) }
            .sorted(by: Self.masNuevoPrimero)
    }

    func misReportes(token: String?) throws -> [Reporte] {
        let yo = try usuarioActual(token)
        return db.reportes.filter { $0.idUsuario == yo.id }
            .map { vista($0, para: yo) }
            .sorted(by: Self.masNuevoPrimero)
    }

    func guardados(token: String?) throws -> [Reporte] {
        let yo = try usuarioActual(token)
        var vistos = Set<Int64>()   // el archivo es externo: un par repetido no debe duplicar la tarjeta
        return db.guardados.filter { $0.idUsuario == yo.id }
            .sorted { $0.fecha > $1.fecha }
            .compactMap { par in
                guard !vistos.contains(par.idReporte),
                      let fila = db.reportes.first(where: { $0.id == par.idReporte }), puedeVer(fila, yo)
                else { return nil }
                vistos.insert(par.idReporte)
                return vista(fila, para: yo)
            }
    }

    func detalle(token: String?, id: Int64) throws -> Reporte {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        return vista(fila, para: yo)
    }

    /// Más reciente primero; a igual fecha, el id mayor (así el orden no depende del algoritmo de `sorted`).
    private nonisolated static func masNuevoPrimero(_ a: Reporte, _ b: Reporte) -> Bool {
        a.fechaCreacion != b.fechaCreacion ? a.fechaCreacion > b.fechaCreacion : a.id > b.id
    }

    // MARK: - Crear, editar, eliminar

    func crear(token: String?, _ entrada: ReporteBorrador) throws -> Reporte {
        let yo = try usuarioActual(token)
        let b = entrada.limpio
        let errores = Validador.reporte(b, ahora: ahora)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        let recientes = db.reportes.filter { $0.idUsuario == yo.id && $0.fechaCreacion > ahora.addingTimeInterval(-86_400) }
        guard recientes.count < Self.limiteReportesPorDia else {
            throw AppError.limiteExcedido("Llegaste al límite de \(Self.limiteReportesPorDia) reportes por día. Intenta mañana.")
        }
        var confirmadas: [String] = []
        do {
            let fila = try transaccion { () -> ReporteFila in
                let id = db.siguienteID()
                let (idSitio, texto) = asociarEnlace(b.urlOTexto)
                let nueva = ReporteFila(id: id, idUsuario: yo.id, tipo: b.tipo, tipoOtro: b.tipo == .otro ? b.tipoOtro : nil,
                                        estado: .recibido, titulo: b.titulo, descripcion: b.descripcion,
                                        fechaIncidente: b.fechaIncidente, nivelRiesgo: .noEvaluado, fechaCreacion: ahora,
                                        esAnonimo: b.esAnonimo, afectado: b.afectado, ciudad: b.ciudad,
                                        persona: b.afectado == .otraPersona ? b.persona : nil,
                                        idSitio: idSitio, textoSospechoso: texto)
                db.reportes.append(nueva)
                for adjunto in b.adjuntos { confirmadas.append(try adjuntar(adjunto, a: id)) }
                db.historial.append(HistorialFila(id: db.siguienteID(), idReporte: id, idResponsable: yo.id, anterior: nil,
                                                  nuevo: .recibido, observaciones: "Reporte creado", fecha: ahora))
                registrarEvento("reporte_enviado", de: yo)
                return nueva
            }
            return vista(fila, para: yo)
        } catch {
            // Los archivos ya movidos a la carpeta definitiva no tienen dueño si el reporte no se guardó.
            borrarArchivos(confirmadas)
            throw error
        }
    }

    func actualizar(token: String?, id: Int64, _ entrada: ReporteBorrador) throws -> Reporte {
        let yo = try usuarioActual(token)
        guard let i = indiceReporte(id), db.reportes[i].idUsuario == yo.id else { throw AppError.noEncontrado }
        guard db.reportes[i].estado.permiteEdicion else {
            throw AppError.conflicto("Este reporte ya fue revisado y no se puede editar.")
        }
        let b = entrada.limpio
        let errores = Validador.reporte(b, ahora: ahora)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        let quedan = db.evidencias.filter { $0.idReporte == id && !b.quitarEvidencias.contains($0.id) }
        guard quedan.count + b.adjuntos.count <= 3 else { throw AppError.validacion(["Máximo 3 archivos de evidencia."]) }
        let quitadas = db.evidencias.filter { $0.idReporte == id && b.quitarEvidencias.contains($0.id) }.map(\.rutaArchivo)
        var confirmadas: [String] = []
        do {
            let fila = try transaccion { () -> ReporteFila in
                let (idSitio, texto) = asociarEnlace(b.urlOTexto)
                db.reportes[i].tipo = b.tipo
                db.reportes[i].tipoOtro = b.tipo == .otro ? b.tipoOtro : nil
                db.reportes[i].titulo = b.titulo
                db.reportes[i].descripcion = b.descripcion
                db.reportes[i].fechaIncidente = b.fechaIncidente
                db.reportes[i].esAnonimo = b.esAnonimo
                db.reportes[i].afectado = b.afectado
                db.reportes[i].ciudad = b.ciudad
                db.reportes[i].persona = b.afectado == .otraPersona ? b.persona : nil
                db.reportes[i].idSitio = idSitio
                db.reportes[i].textoSospechoso = texto
                db.evidencias.removeAll { $0.idReporte == id && b.quitarEvidencias.contains($0.id) }
                for adjunto in b.adjuntos { confirmadas.append(try adjuntar(adjunto, a: id)) }
                limpiarSitiosHuerfanos()
                return db.reportes[i]
            }
            // Los archivos quitados se borran hasta que el cambio ya quedó guardado.
            borrarArchivos(quitadas)
            return vista(fila, para: yo)
        } catch {
            borrarArchivos(confirmadas)
            throw error
        }
    }

    func eliminar(token: String?, id: Int64) throws {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        guard fila.idUsuario == yo.id || yo.rol.esStaff else { throw AppError.sinPermiso }
        let rutas = try transaccion { borrarReporte(id, archivos: false) }
        borrarArchivos(rutas)
    }

    /// Borra el reporte y todo lo que cuelga de él. Con `archivos: true` (lo normal) también borra la
    /// evidencia en disco; `eliminar` pasa `false` para borrarla solo cuando el cambio ya se guardó.
    /// Devuelve las rutas de la evidencia que tenía.
    @discardableResult
    func borrarReporte(_ id: Int64, archivos borrar: Bool = true) -> [String] {
        let rutas = db.evidencias.filter { $0.idReporte == id }.map(\.rutaArchivo)
        if borrar { borrarArchivos(rutas) }
        db.evidencias.removeAll { $0.idReporte == id }
        db.historial.removeAll { $0.idReporte == id }
        db.comentarios.removeAll { $0.idReporte == id }
        db.guardados.removeAll { $0.idReporte == id }
        db.confirmaciones.removeAll { $0.idReporte == id }
        for i in db.notificaciones.indices where db.notificaciones[i].idReporte == id {
            db.notificaciones[i].idReporte = nil
        }
        db.reportes.removeAll { $0.id == id }
        limpiarSitiosHuerfanos()
        return rutas
    }

    /// URL válida → fila de SitioWeb_URL (se reutiliza si ya existe). Texto → `texto_sospechoso`.
    /// Un enlace que parece URL pero no es http/https seguro (p. ej. `javascript:`) no se guarda: la
    /// validación ya lo rechaza antes, esto es la segunda barrera.
    func asociarEnlace(_ s: String) -> (Int64?, String?) {
        guard !s.isEmpty else { return (nil, nil) }
        guard URLTools.pareceURL(s) else { return (nil, s) }
        guard let url = URLTools.normalizar(s) else { return (nil, nil) }
        if let sitio = db.sitios.first(where: { $0.url == url }) { return (sitio.id, nil) }
        let sitio = SitioWeb(id: db.siguienteID(), url: url, nivelRiesgoGlobal: .bajo,
                             estadoCertificado: URLTools.estadoCertificado(url), fechaUltimaEvaluacion: nil)
        db.sitios.append(sitio)
        return (sitio.id, nil)
    }

    /// Un sitio que ningún reporte usa y que nadie evaluó solo existe porque alguien lo escribió en un
    /// reporte que ya no está: se borra junto con él (el enlace era dato de esa persona).
    private func limpiarSitiosHuerfanos() {
        let usados = Set(db.reportes.compactMap(\.idSitio))
        db.sitios.removeAll { !usados.contains($0.id) && $0.fechaUltimaEvaluacion == nil }
    }

    /// Mueve el archivo de "pendiente/" a la carpeta definitiva y lo registra. Devuelve la ruta para que
    /// quien llama pueda borrarla si el reporte no llega a guardarse. El tipo debe coincidir con la
    /// extensión del archivo (el adjunto viene del cliente).
    @discardableResult
    func adjuntar(_ adjunto: Adjunto, a idReporte: Int64) throws -> String {
        let extensiones = ["image/jpeg": ".jpg", "application/pdf": ".pdf"]
        guard let extensionEsperada = extensiones[adjunto.tipoArchivo],
              adjunto.nombreArchivo.hasSuffix(extensionEsperada) else {
            throw AppError.validacion(["Tipo de archivo no permitido."])
        }
        let ruta: String
        do {
            ruta = try archivos.confirmar(adjunto)
        } catch {
            throw AppError.validacion(["No se pudo adjuntar uno de los archivos. Vuelve a elegirlo."])
        }
        db.evidencias.append(EvidenciaFila(id: db.siguienteID(), idReporte: idReporte, rutaArchivo: ruta,
                                           tipoArchivo: adjunto.tipoArchivo, fechaCarga: ahora))
        return ruta
    }

    // MARK: - Guardar y "Yo también"

    func marcarGuardado(token: String?, id: Int64, _ guardado: Bool) throws {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        let yaGuardado = db.guardados.contains { $0.idUsuario == yo.id && $0.idReporte == id }
        guard yaGuardado != guardado else { return }   // idempotente: nada que cambiar ni que escribir
        try transaccion {
            db.guardados.removeAll { $0.idUsuario == yo.id && $0.idReporte == id }
            if guardado { db.guardados.append(ParUsuarioReporte(idUsuario: yo.id, idReporte: id, fecha: ahora)) }
        }
    }

    func confirmar(token: String?, id: Int64) throws -> Reporte {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), fila.estado.esPublico else { throw AppError.noEncontrado }
        guard fila.idUsuario != yo.id else { throw AppError.conflicto("No puedes confirmar tu propio reporte.") }
        if !db.confirmaciones.contains(where: { $0.idUsuario == yo.id && $0.idReporte == id }) {
            try transaccion {
                db.confirmaciones.append(ParUsuarioReporte(idUsuario: yo.id, idReporte: id, fecha: ahora))
            }
        }
        return vista(fila, para: yo)
    }

    // MARK: - Comentarios

    func comentarios(token: String?, id: Int64) throws -> [Comentario] {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        return db.comentarios.filter { $0.idReporte == id }
            .sorted { $0.fecha != $1.fecha ? $0.fecha > $1.fecha : $0.id > $1.id }
            .map { Comentario(id: $0.id, idReporte: id, autor: nombreVisible(de: $0.idUsuario, para: yo),
                              esMio: $0.idUsuario == yo.id, texto: $0.texto, fecha: $0.fecha) }
    }

    func comentar(token: String?, id: Int64, texto entrada: String) throws -> Comentario {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        guard fila.estado.esPublico else { throw AppError.conflicto("Solo se puede comentar en reportes validados.") }
        let texto = Sanitizador.texto(entrada, maximo: 500, multilinea: true)
        let errores = Validador.comentario(texto)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        let momento = ahora
        let ultimoMinuto = db.comentarios.filter { $0.idUsuario == yo.id && $0.fecha > momento.addingTimeInterval(-60) }
        guard ultimoMinuto.count < Self.limiteComentariosPorMinuto else {
            throw AppError.limiteExcedido("Espera un momento antes de volver a comentar.")
        }
        let nuevo = try transaccion { () -> ComentarioFila in
            let nuevo = ComentarioFila(id: db.siguienteID(), idReporte: id, idUsuario: yo.id, texto: texto, fecha: momento)
            db.comentarios.append(nuevo)
            if let autor = fila.idUsuario, autor != yo.id {
                notificar(autor, reporte: id, "Nuevo comentario en tu reporte «\(fila.titulo)».")
            }
            return nuevo
        }
        return Comentario(id: nuevo.id, idReporte: id, autor: "Tú", esMio: true, texto: texto, fecha: momento)
    }

    func eliminarComentario(token: String?, id: Int64) throws {
        let yo = try usuarioActual(token)
        guard let c = db.comentarios.first(where: { $0.id == id }),
              let fila = db.reportes.first(where: { $0.id == c.idReporte }), puedeVer(fila, yo)
        else { throw AppError.noEncontrado }
        guard c.idUsuario == yo.id || yo.rol.esStaff else { throw AppError.sinPermiso }
        try transaccion { db.comentarios.removeAll { $0.id == id } }
    }

    // MARK: - Historial, estadísticas y archivos

    /// El autor ve "Equipo de moderación" en lugar del alias de quien moderó (lo protege de acoso).
    func historial(token: String?, id: Int64) throws -> [HistorialEstado] {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        guard fila.idUsuario == yo.id || yo.rol.esStaff else { throw AppError.sinPermiso }
        return db.historial.filter { $0.idReporte == id }
            .sorted { $0.fecha != $1.fecha ? $0.fecha < $1.fecha : $0.id < $1.id }
            .map { h in
                let responsable = h.anterior == nil || yo.rol.esStaff
                    ? nombreVisible(de: h.idResponsable, para: yo)
                    : "Equipo de moderación"
                return HistorialEstado(id: h.id, idReporte: id, responsable: responsable, anterior: h.anterior,
                                       nuevo: h.nuevo, observaciones: h.observaciones, fecha: h.fecha)
            }
    }

    /// Solo cuenta reportes públicos. Los contadores previos vienen de disco: suma saturada.
    func estadisticas(token: String?) throws -> EstadisticasComunidad {
        _ = try usuarioActual(token)
        let publicos = db.reportes.filter(\.estado.esPublico)
        let ids = Set(publicos.map(\.id))
        let confirmaciones = Self.sumaSaturada(
            publicos.reduce(0) { Self.sumaSaturada($0, $1.confirmacionesPrevias) },
            db.confirmaciones.filter { ids.contains($0.idReporte) }.count)
        return EstadisticasComunidad(
            personasAyudadas: Self.sumaSaturada(confirmaciones, db.guardados.filter { ids.contains($0.idReporte) }.count),
            reportesVerificados: publicos.count,
            estafasDetenidas: publicos.filter { $0.estado == .canalizado }.count,
            zonasCubiertas: Set(publicos.map { FiltroBusqueda.normalizar($0.ciudad) }).count)
    }

    func categorias(token: String?) throws -> [ConteoCategoria] {
        _ = try usuarioActual(token)
        let publicos = db.reportes.filter(\.estado.esPublico)
        return TipoFraude.allCases.map { tipo in
            let deTipo = publicos.filter { $0.tipo == tipo }
            return ConteoCategoria(tipo: tipo, total: deTipo.count, riesgoMaximo: deTipo.map(\.nivelRiesgo).max() ?? .noEvaluado)
        }
    }

    // MARK: - Perfil público

    /// Una persona se ve a sí misma y el staff ve a cualquiera; los demás solo a quien activó
    /// "perfil público". Lo que no se puede ver responde igual que lo que no existe.
    private func usuarioVisible(_ id: Int64, para yo: Usuario) throws -> Usuario {
        guard let u = db.usuarios.first(where: { $0.usuario.id == id })?.usuario,
              u.id == yo.id || yo.rol.esStaff || u.preferencias.perfilPublico
        else { throw AppError.noEncontrado }
        return u
    }

    /// Solo lo que la persona firmó con su nombre: reportes públicos y no anónimos.
    func perfilPublico(token: String?, id: Int64) throws -> PerfilPublico {
        let yo = try usuarioActual(token)
        let u = try usuarioVisible(id, para: yo)
        let reportes = db.reportes.filter { $0.idUsuario == id && $0.estado.esPublico && !$0.esAnonimo }
            .map { vista($0, para: yo) }
            .sorted(by: Self.masNuevoPrimero)
        return PerfilPublico(id: u.id, alias: u.alias, biografia: u.biografia, tieneAvatar: u.avatarRuta != nil,
                             miembroDesde: u.fechaRegistro, reportes: reportes)
    }

    func avatarPublico(token: String?, idUsuario: Int64) throws -> Data? {
        let yo = try usuarioActual(token)
        guard let u = try? usuarioVisible(idUsuario, para: yo), let ruta = u.avatarRuta else { return nil }
        return try? archivos.datos(ruta: ruta)
    }

    /// Diagnóstico del modo Demo: sin red, solo con lo que se puede saber del propio enlace y de los
    /// reportes públicos guardados. El backend real agrega certificado, antigüedad y listas negras.
    func analizarURL(token: String?, _ entrada: String) throws -> DiagnosticoURL {
        let yo = try usuarioActual(token)
        guard let url = URLTools.normalizar(entrada), let dominio = URLTools.host(de: url) else {
            throw AppError.validacion(["Solo se aceptan enlaces http:// o https:// válidos."])
        }
        var puntos = 0
        var piso = NivelRiesgo.bajo
        var verificaciones: [VerificacionURL] = []

        let homografo = URLTools.esPosibleHomografo(url)
        if homografo { puntos += 30 }
        verificaciones.append(VerificacionURL(tipo: .estructura, paso: !homografo, detalle: homografo
            ? "El dominio usa caracteres que imitan a otros (posible homógrafo)."
            : "Sin señales sospechosas en la estructura del enlace."))

        let seguro = url.lowercased().hasPrefix("https://")
        if !seguro { puntos += 20 }
        verificaciones.append(VerificacionURL(tipo: .certificado, paso: seguro, detalle: seguro
            ? "Usa HTTPS. El modo Demo no revisa el certificado en línea."
            : "El sitio no usa HTTPS: lo que escribas viaja sin cifrar."))

        let relacionados = db.reportes.filter { fila in
            guard fila.estado.esPublico, let idSitio = fila.idSitio,
                  let sitio = db.sitios.first(where: { $0.id == idSitio }) else { return false }
            return URLTools.host(de: sitio.url) == dominio
        }
        if let peor = relacionados.map(\.nivelRiesgo).max() {
            puntos += 25
            piso = max(piso, peor == .noEvaluado ? .bajo : peor)
            verificaciones.append(VerificacionURL(tipo: .comunidad, paso: false, detalle:
                "\(relacionados.count) reporte\(relacionados.count == 1 ? "" : "s") validado\(relacionados.count == 1 ? "" : "s") de la comunidad; riesgo más alto: \(peor.titulo)."))
        } else {
            verificaciones.append(VerificacionURL(tipo: .comunidad, paso: true, detalle: "Sin reportes validados de la comunidad."))
        }

        let niveles: [NivelRiesgo] = [.bajo, .medio, .alto, .muyAlto]
        let porPuntos = niveles[min(puntos / 25, niveles.count - 1)]
        registrarEvento("consulta_url", de: yo)
        try? persistir()   // solo un contador anónimo
        return DiagnosticoURL(url: url, dominio: dominio, nivelRiesgo: max(porPuntos, piso), puntaje: min(puntos, 100),
                              verificaciones: verificaciones, estadoCertificado: URLTools.estadoCertificado(url), fecha: ahora)
    }

    /// La ruta sale de la base, nunca del cliente: no hay forma de pedir otro archivo del disco.
    func datosEvidencia(token: String?, _ evidencia: Evidencia) throws -> Data {
        let yo = try usuarioActual(token)
        guard let fila = db.evidencias.first(where: { $0.id == evidencia.id }),
              let reporte = db.reportes.first(where: { $0.id == fila.idReporte }),
              reporte.idUsuario == yo.id || yo.rol.esStaff
        else { throw AppError.noEncontrado }
        do {
            return try archivos.datos(ruta: fila.rutaArchivo)
        } catch {
            // Archivo ausente o ilegible: para quien lo pide es lo mismo que no existir.
            throw AppError.noEncontrado
        }
    }
}
