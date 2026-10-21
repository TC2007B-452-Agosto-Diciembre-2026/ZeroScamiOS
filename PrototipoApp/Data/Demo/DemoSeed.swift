//
//  DemoSeed.swift
//  PrototipoApp
//
//  Datos de la demo. Los textos de los dos primeros reportes, los comentarios y las tarjetas de
//  Perfil son los que tenía el storyboard. Las fechas se calculan desde `ahora` para que
//  "Hace 2 horas" sea cierto el día de la presentación.
//
//  Las contraseñas de las cuentas demo NO están aquí: solo sus hashes PBKDF2-SHA256
//  (600,000 iteraciones, sal aleatoria), calculados fuera de la app. Las contraseñas en claro
//  viven en docs/guion-demo.md.
//

import Foundation

nonisolated enum DemoSeed {
    static let idOwner: Int64 = 1
    static let idAdmin: Int64 = 2
    static let idUsuario: Int64 = 3
    static let idTecno: Int64 = 4
    static let idCompras: Int64 = 5
    static let idVecina: Int64 = 6

    static let hashOwner = "pbkdf2_sha256$600000$jLfdF7XXpo7+yGzj7AP+qA==$kv1QRnSEaFGTrdbt+sICBDJDIb+0z35QnAt69dKwbh0="
    static let hashAdmin = "pbkdf2_sha256$600000$tRxYQ70uziOMJwbsrjhnyg==$90si70ftfbUHLNKqU8LixNK+wQQKvTY817tpFZI9tlM="
    static let hashUsuario = "pbkdf2_sha256$600000$YG0lXKYMt2EqBJS/FHKHdw==$MX8+gfnIAvPJ7MMHppcuP9k71czuGFuOnc/dX95FdEA="
    /// Miembros de la comunidad: contraseñas aleatorias que nadie conoce (no pueden iniciar sesión).
    static let hashesComunidad = [
        "pbkdf2_sha256$600000$7I7k7QoVpZg4IrcQWkRzOQ==$S26efn3ok0EY0W7gcb1VYNE8lBfkHjVMKsJFJ9FBu9I=",
        "pbkdf2_sha256$600000$htRIMk5PZLK/c32QgxLraA==$IzY0HGgLN975YBO4Rpk2mvKWSy8JzRnzx8ziBbLS4UA=",
        "pbkdf2_sha256$600000$QravxlxFw9LjLTNZSsJQBQ==$mTZLYwS46p2RPMJtMRl1eFtuWfx52658NfYNxpP8QjM=",
    ]
    /// Si el correo no existe, el login verifica contra este hash para tardar lo mismo.
    static let hashSenuelo = "pbkdf2_sha256$600000$G0qVo7uOEw/iUwAp8cOd9Q==$Up9fhb3Z6ZQB+wKO7OabOJUFnrFtECznXvopyUTlyhg="

    private nonisolated struct Semilla {
        let id: Int64
        let autor: Int64
        let tipo: TipoFraude
        var tipoOtro: String? = nil
        let estado: EstadoReporte
        let riesgo: NivelRiesgo
        let ciudad: String
        /// Antigüedad en horas.
        let horas: Double
        let titulo: String
        let descripcion: String
        var url: String? = nil
        var texto: String? = nil
        var anonimo = false
        var persona: PersonaAfectada? = nil
        var previas = 0
        var motivoRechazo: String? = nil
    }

    static func base(ahora: Date) -> DemoDatabase {
        var db = DemoDatabase()
        func hace(_ horas: Double) -> Date { ahora.addingTimeInterval(-horas * 3_600) }

        db.usuarios = [
            fila(idOwner, .owner, "Equipo", "ZeroScam", "owner_zs", "owner@0fraude.mx", publico: true, dias: 120, hashOwner, ahora),
            fila(idAdmin, .administrador, "Carlos", "Méndez", "admin_zs", "admin@0fraude.mx", publico: true, dias: 90, hashAdmin, ahora),
            fila(idUsuario, .usuario, "Ana", "López", "usuario_01", "usuario@0fraude.mx", publico: false, dias: 30, hashUsuario, ahora,
                 biografia: "Me interesa alertar sobre compras en línea."),
            fila(idTecno, .usuario, "Luis", "Herrera", "tecno_mx", "luis@comunidad.test", publico: true, dias: 60, hashesComunidad[0], ahora),
            fila(idCompras, .usuario, "Marta", "Ruiz", "compras_seguras", "marta@comunidad.test", publico: true, dias: 45, hashesComunidad[1], ahora),
            fila(idVecina, .usuario, "Sofía", "Ramírez", "vecina_alerta", "sofia@comunidad.test", publico: false, dias: 20, hashesComunidad[2], ahora),
        ]

        var idSitio: Int64 = 200
        var idHistorial: Int64 = 400
        for s in semillas {
            var sitio: Int64?
            if let url = s.url {
                idSitio += 1
                sitio = idSitio
                db.sitios.append(SitioWeb(id: idSitio, url: url,
                                          nivelRiesgoGlobal: s.estado.esPublico ? s.riesgo : .bajo,
                                          estadoCertificado: URLTools.estadoCertificado(url),
                                          fechaUltimaEvaluacion: s.estado.esPublico ? hace(max(0, s.horas - 1)) : nil))
            }
            let creado = hace(s.horas)
            db.reportes.append(ReporteFila(id: s.id, idUsuario: s.autor, tipo: s.tipo, tipoOtro: s.tipoOtro,
                                           estado: s.estado, titulo: s.titulo, descripcion: s.descripcion,
                                           fechaIncidente: creado.addingTimeInterval(-6 * 3_600),
                                           nivelRiesgo: s.riesgo, fechaCreacion: creado, esAnonimo: s.anonimo,
                                           afectado: s.persona == nil ? .yo : .otraPersona, ciudad: s.ciudad,
                                           persona: s.persona, idSitio: sitio,
                                           textoSospechoso: s.texto, confirmacionesPrevias: s.previas))
            // Historial: RECIBIDO al crearse y luego cada paso hasta su estado actual, repartido en su antigüedad.
            let ruta = rutaDeEstados(hasta: s.estado)
            let paso = min(3_600, s.horas * 3_600 / Double(max(ruta.count, 1)))
            var anterior: EstadoReporte?
            for (i, estado) in ruta.enumerated() {
                idHistorial += 1
                db.historial.append(HistorialFila(
                    id: idHistorial, idReporte: s.id,
                    idResponsable: i == 0 ? s.autor : idAdmin,
                    anterior: anterior, nuevo: estado,
                    observaciones: i == 0 ? "Reporte creado" : (estado == .rechazado ? s.motivoRechazo : nil),
                    fecha: creado.addingTimeInterval(Double(i) * paso)))
                anterior = estado
            }
        }

        db.comentarios = [
            ComentarioFila(id: 301, idReporte: 101, idUsuario: idVecina, texto: "Casi compro ahí, los precios se veían muy reales. Por suerte busqué reseñas antes.", fecha: hace(0.25)),
            ComentarioFila(id: 302, idReporte: 101, idUsuario: idCompras, texto: "A mi papá casi le cae, vio el anuncio en Facebook y ya iba a pagar.", fecha: hace(1)),
            ComentarioFila(id: 303, idReporte: 102, idUsuario: idTecno, texto: "Igual me escribieron a mí; la cuenta tiene muy pocos seguidores.", fecha: hace(3)),
            ComentarioFila(id: 304, idReporte: 122, idUsuario: idVecina, texto: "Gracias por avisar, vi la misma cuenta ayer.", fecha: hace(20)),
            ComentarioFila(id: 305, idReporte: 113, idUsuario: idCompras, texto: "El dominio termina en .store; la tienda real no usa ese.", fecha: hace(200)),
        ]
        db.guardados = [
            ParUsuarioReporte(idUsuario: idUsuario, idReporte: 101, fecha: hace(1)),
            ParUsuarioReporte(idUsuario: idUsuario, idReporte: 102, fecha: hace(2)),
        ]
        db.notificaciones = [
            NotificacionFila(id: 501, idUsuario: idUsuario, idReporte: 122,
                             mensaje: "Tu reporte «Oferta falsa 2x1 en boletos de concierto por Instagram» fue VALIDADO y ya es visible para la comunidad.",
                             leida: true, fecha: hace(28)),
            NotificacionFila(id: 502, idUsuario: idUsuario, idReporte: 121,
                             mensaje: "Tu reporte «Descuento falso de laptop en tienda clonada» está EN REVISIÓN.",
                             leida: false, fecha: hace(2)),
        ]
        return db
    }

    private static func fila(_ id: Int64, _ rol: Rol, _ nombre: String, _ apellido: String, _ alias: String,
                             _ correo: String, publico: Bool, dias: Double, _ hash: String, _ ahora: Date,
                             biografia: String = "") -> UsuarioFila {
        let registro = ahora.addingTimeInterval(-dias * 86_400)
        let usuario = Usuario(id: id, rol: rol, nombre: nombre, apellido: apellido, pais: "México", alias: alias,
                              correo: correo, biografia: biografia, avatarRuta: nil, estadoCuenta: .activo,
                              fechaRegistro: registro, preferencias: Preferencias(perfilPublico: publico),
                              consentimiento: Consentimiento(versionAviso: Consentimiento.versionAvisoVigente, fecha: registro))
        return UsuarioFila(usuario: usuario, contrasenaHash: hash)
    }

    private static func rutaDeEstados(hasta estado: EstadoReporte) -> [EstadoReporte] {
        switch estado {
        case .recibido: [.recibido]
        case .enRevision: [.recibido, .enRevision]
        case .validado: [.recibido, .enRevision, .validado]
        case .rechazado: [.recibido, .enRevision, .rechazado]
        case .canalizado: [.recibido, .enRevision, .validado, .canalizado]
        }
    }

    // Tabla completa con justificación en el apéndice A del plan.
    private static let semillas: [Semilla] = [
        Semilla(id: 101, autor: idTecno, tipo: .ofertaFalsa, estado: .validado, riesgo: .alto, ciudad: "CDMX", horas: 2,
                titulo: "Falsa liquidación de tienda de electrónica",
                descripcion: "Una tienda online clonada está ofreciendo laptops y celulares con descuentos de hasta el 80%. Los usuarios pagan pero nunca reciben el producto, y el sitio desaparece días después.",
                url: "https://liquidacion-electronica-mx.shop", previas: 1_200),
        Semilla(id: 102, autor: idCompras, tipo: .sorteoFalso, estado: .validado, riesgo: .alto, ciudad: "Guadalajara", horas: 5,
                titulo: "Sorteo falso de iPhone 17 en Instagram",
                descripcion: "Cuentas falsas piden tus datos para 'reclamar' un premio que no existe. Después piden un pago de envío.",
                url: "https://instagram.com/iphone17.sorteo.oficial", previas: 450),
        Semilla(id: 103, autor: idTecno, tipo: .tiendaClonada, estado: .canalizado, riesgo: .muyAlto, ciudad: "Monterrey", horas: 26,
                titulo: "Tienda clonada de tenis deportivos",
                descripcion: "El sitio copia el diseño de una marca deportiva y vende tenis a mitad de precio. Solo acepta transferencia y nunca entrega.",
                url: "https://n1ke-outlet-mexico.com", previas: 610),
        Semilla(id: 104, autor: idVecina, tipo: .marketplace, estado: .validado, riesgo: .bajo, ciudad: "Puebla", horas: 30,
                titulo: "Vendedor de consolas que no entrega",
                descripcion: "Un perfil en Facebook Marketplace pide anticipo para apartar consolas y luego deja de responder.",
                texto: "Perfil 'Gamer Store MX' en Facebook Marketplace", previas: 85),
        Semilla(id: 105, autor: idCompras, tipo: .llamada, estado: .validado, riesgo: .alto, ciudad: "CDMX", horas: 50,
                titulo: "Llamada falsa del SAT pidiendo pago de multa",
                descripcion: "Llaman diciendo ser del SAT y exigen pagar una multa por transferencia ese mismo día para evitar una auditoría.",
                texto: "+52 55 8765 4321", previas: 390),
        Semilla(id: 106, autor: idVecina, tipo: .ofertaFalsa, estado: .validado, riesgo: .medio, ciudad: "Querétaro", horas: 72,
                titulo: "Cupón falso de supermercado por WhatsApp",
                descripcion: "Circula un mensaje con un cupón de $1,500 que pide llenar una encuesta con datos personales y de tarjeta.",
                url: "http://cupones-supermercado-mx.info", previas: 270),
        Semilla(id: 107, autor: idTecno, tipo: .sorteoFalso, estado: .canalizado, riesgo: .alto, ciudad: "Mérida", horas: 96,
                titulo: "Rifa falsa de automóvil en TikTok",
                descripcion: "Una cuenta vende boletos para rifar un auto; el sorteo nunca ocurre y la cuenta cambia de nombre.",
                url: "https://tiktok.com/@rifas.autos.mx", previas: 180),
        Semilla(id: 108, autor: idCompras, tipo: .otro, tipoOtro: "Phishing bancario", estado: .validado, riesgo: .muyAlto, ciudad: "CDMX", horas: 120,
                titulo: "Página clonada de banco para 'actualizar datos'",
                descripcion: "Un SMS lleva a una página idéntica a la de un banco que pide usuario, contraseña y el código que llega por mensaje.",
                url: "http://banco-actualiza-datos.com", previas: 520),
        Semilla(id: 109, autor: idVecina, tipo: .marketplace, estado: .validado, riesgo: .medio, ciudad: "Guadalajara", horas: 144,
                titulo: "Renta de departamento inexistente",
                descripcion: "Publican un departamento con fotos robadas y piden depósito y primer mes antes de mostrarlo.",
                texto: "Anuncio en Marketplace con depósito por adelantado", previas: 95),
        Semilla(id: 110, autor: idTecno, tipo: .otro, tipoOtro: "Empleo falso", estado: .validado, riesgo: .medio, ciudad: "Tijuana", horas: 168,
                titulo: "Ofertas de empleo falsas por WhatsApp",
                descripcion: "Ofrecen trabajo desde casa dando 'likes' y luego piden una inversión para seguir cobrando.",
                texto: "+52 664 000 1122", previas: 140),
        Semilla(id: 111, autor: idCompras, tipo: .ofertaFalsa, estado: .canalizado, riesgo: .alto, ciudad: "Monterrey", horas: 216,
                titulo: "Boletos de concierto en preventa falsa",
                descripcion: "Un sitio vende boletos en 'preventa exclusiva'; los códigos QR son falsos y no permiten entrar.",
                url: "https://boletos-preventa-mx.com", previas: 230),
        Semilla(id: 112, autor: idVecina, tipo: .llamada, estado: .validado, riesgo: .alto, ciudad: "Puebla", horas: 240,
                titulo: "Llamada de falso familiar detenido",
                descripcion: "Llaman haciéndose pasar por un familiar detenido y piden dinero urgente para 'arreglar' la situación.",
                texto: "Extorsión telefónica desde número desconocido", previas: 160),
        Semilla(id: 113, autor: idTecno, tipo: .tiendaClonada, estado: .validado, riesgo: .alto, ciudad: "CDMX", horas: 288,
                titulo: "Tienda clonada de Mercado Libre",
                descripcion: "Un dominio parecido al de Mercado Libre muestra ofertas falsas y pide pagar fuera de la plataforma.",
                url: "https://mercadolibre-ofertas.store", previas: 300),
        Semilla(id: 114, autor: idCompras, tipo: .sorteoFalso, estado: .validado, riesgo: .bajo, ciudad: "León", horas: 336,
                titulo: "Sorteo falso de despensa por aniversario",
                descripcion: "Una página promete despensas gratis a quien comparta la publicación y registre su CURP.",
                url: "https://facebook.com/despensas.gratis.mx", previas: 60),
        Semilla(id: 115, autor: idVecina, tipo: .otro, tipoOtro: "Préstamo falso", estado: .canalizado, riesgo: .alto, ciudad: "Oaxaca", horas: 384,
                titulo: "Préstamo falso con anticipo",
                descripcion: "Prometen un préstamo sin buró si primero pagas una 'comisión de apertura'; después desaparecen.",
                url: "https://prestamos-rapidos-mx.net", previas: 210),
        Semilla(id: 116, autor: idTecno, tipo: .ofertaFalsa, estado: .validado, riesgo: .medio, ciudad: "Toluca", horas: 480,
                titulo: "Descuentos de 90% en perfumes por Instagram",
                descripcion: "Una cuenta vende perfumes de marca al 90% de descuento y solo acepta depósitos en tiendas de conveniencia.",
                url: "https://instagram.com/perfumes.outlet.90", previas: 120),
        // Cola de moderación (no públicos)
        Semilla(id: 117, autor: idVecina, tipo: .otro, tipoOtro: "Smishing", estado: .recibido, riesgo: .noEvaluado, ciudad: "CDMX", horas: 1,
                titulo: "Mensaje de paquetería para pagar envío",
                descripcion: "Llega un SMS diciendo que un paquete está retenido y pide pagar $35 de envío en un enlace.",
                url: "http://paqueteria-entregas-mx.co", anonimo: true),
        Semilla(id: 118, autor: idCompras, tipo: .marketplace, estado: .enRevision, riesgo: .noEvaluado, ciudad: "Monterrey", horas: 20,
                titulo: "Venta de mascotas con depósito",
                descripcion: "Venden cachorros de raza a buen precio y piden depósito para apartar; luego piden más pagos de vacunas y envío.",
                texto: "Perfil 'Criadero Norte' en redes",
                persona: PersonaAfectada(nombre: "Rosa Martínez", contacto: "+52 81 5555 0101", autorizo: true)),
        Semilla(id: 119, autor: idTecno, tipo: .otro, tipoOtro: "Phishing de programa social", estado: .recibido, riesgo: .noEvaluado, ciudad: "Puebla", horas: 8,
                titulo: "Supuesta beca del gobierno pide CURP",
                descripcion: "Un mensaje promete una beca y pide CURP, INE y datos bancarios en un formulario.",
                url: "https://becas-bienestar-registro.com"),
        Semilla(id: 120, autor: idVecina, tipo: .otro, tipoOtro: "Cadena", estado: .rechazado, riesgo: .noEvaluado, ciudad: "León", horas: 72,
                titulo: "Mensaje de cadena sin datos",
                descripcion: "Me llegó una cadena diciendo que hay fraudes, pero no trae enlace ni número.",
                motivoRechazo: "No incluye datos verificables (enlace, número o captura)."),
        // Reportes del usuario demo (Perfil → Mis reportes)
        Semilla(id: 121, autor: idUsuario, tipo: .tiendaClonada, estado: .enRevision, riesgo: .noEvaluado, ciudad: "CDMX", horas: 3,
                titulo: "Descuento falso de laptop en tienda clonada",
                descripcion: "Reporté una tienda que ofrecía una laptop a precio irrisorio y nunca la recibí.",
                url: "https://laptops-liquidacion.store"),
        Semilla(id: 122, autor: idUsuario, tipo: .ofertaFalsa, estado: .validado, riesgo: .medio, ciudad: "CDMX", horas: 30,
                titulo: "Oferta falsa 2x1 en boletos de concierto por Instagram",
                descripcion: "Una cuenta falsa ofrecía boletos 2x1 pidiendo pago por transferencia.",
                url: "https://instagram.com/boletos2x1.oficial", previas: 340),
        Semilla(id: 123, autor: idUsuario, tipo: .llamada, estado: .recibido, riesgo: .noEvaluado, ciudad: "CDMX", horas: 0.5,
                titulo: "Llamada de supuesto banco pidiendo código",
                descripcion: "Me llamaron diciendo ser de mi banco y pidieron el código que me llegó por SMS para 'cancelar un cargo'.",
                texto: "+52 55 1234 5678"),
    ]
}
