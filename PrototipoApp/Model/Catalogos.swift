//
//  Catalogos.swift
//  PrototipoApp
//
//  Catálogos de la base ZeroScam (tablas Rol, Estado y TipoFraude) y los valores fijos de
//  `Usuario.estado_cuenta` y del nivel de riesgo. El `rawValue` es el texto exacto que guarda
//  MySQL, para que el JSON del backend se lea sin traducir.
//

import Foundation

nonisolated enum Rol: String, Codable, Sendable, CaseIterable {
    case usuario = "Usuario"
    case administrador = "Administrador"
    case policia = "Policia"
    case owner = "Owner"

    /// Administrador y Owner moderan. Policía existe en la base pero no tiene interfaz.
    var esStaff: Bool { self == .administrador || self == .owner }

    var titulo: String {
        switch self {
        case .usuario: "Usuario"
        case .administrador: "Administrador"
        case .policia: "Policía"
        case .owner: "Owner"
        }
    }
}

nonisolated enum EstadoReporte: String, Codable, Sendable, CaseIterable {
    case recibido = "RECIBIDO"
    case enRevision = "EN_REVISION"
    case validado = "VALIDADO"
    case rechazado = "RECHAZADO"
    case canalizado = "CANALIZADO"

    /// Como se muestra en pantalla.
    var titulo: String {
        switch self {
        case .recibido: "RECIBIDO"
        case .enRevision: "EN REVISIÓN"
        case .validado: "VALIDADO"
        case .rechazado: "RECHAZADO"
        case .canalizado: "CANALIZADO"
        }
    }

    /// Columna `Estado.orden`.
    var orden: Int {
        switch self {
        case .recibido: 1
        case .enRevision: 2
        case .validado: 3
        case .rechazado: 4
        case .canalizado: 5
        }
    }

    /// Columna `Estado.es_final`: de aquí ya no se mueve.
    var esFinal: Bool { self == .rechazado || self == .canalizado }

    /// Solo estos aparecen en Inicio, Buscar y Estadísticas.
    var esPublico: Bool { self == .validado || self == .canalizado }

    /// A qué estados puede moverlo un Administrador.
    var siguientes: [EstadoReporte] {
        switch self {
        case .recibido: [.enRevision, .rechazado]
        case .enRevision: [.validado, .rechazado]
        case .validado: [.canalizado]
        case .rechazado, .canalizado: []
        }
    }

    /// El autor puede editar mientras nadie lo haya validado ni cerrado.
    var permiteEdicion: Bool { self == .recibido || self == .enRevision }
}

nonisolated enum TipoFraude: String, Codable, Sendable, CaseIterable, Identifiable {
    case ofertaFalsa = "Oferta Falsa"
    case sorteoFalso = "Sorteo Falso"
    case tiendaClonada = "Tienda Clonada"
    case marketplace = "Marketplace"
    case llamada = "Llamada"
    case otro = "Otro"

    var id: String { rawValue }

    /// Nombre en plural de las tarjetas de Buscar (los 4 primeros son los del storyboard).
    var categoria: String {
        switch self {
        case .ofertaFalsa: "Ofertas Falsas"
        case .sorteoFalso: "Sorteos Falsos"
        case .tiendaClonada: "Tiendas Clonadas"
        case .marketplace: "Marketplace Fraudulento"
        case .llamada: "Llamadas Fraudulentas"
        case .otro: "Otros Fraudes"
        }
    }

    var resumen: String {
        switch self {
        case .ofertaFalsa: "Descuentos irreales y liquidaciones que nunca llegan."
        case .sorteoFalso: "Concursos y premios falsos que piden tus datos o dinero."
        case .tiendaClonada: "Sitios web que imitan marcas conocidas para robar tu pago."
        case .marketplace: "Vendedores falsos en redes que cobran y no entregan."
        case .llamada: "Llamadas y mensajes que se hacen pasar por bancos o autoridades."
        case .otro: "Phishing, empleos y préstamos falsos, y otros engaños."
        }
    }

    /// Pasos típicos; alimentan la sección "Modus Operandi" del detalle (antes fija).
    var modusOperandi: [String] {
        switch self {
        case .ofertaFalsa: [
            "1. El Anuncio: ves publicidad en redes con precios absurdamente bajos y 'solo por hoy'.",
            "2. El Sitio Clonado: el link lleva a una página que imita a una tienda real, casi idéntica.",
            "3. Pago sin Entrega: después de pagar, el sitio deja de responder y el producto nunca llega.",
        ]
        case .sorteoFalso: [
            "1. El Premio: te avisan por redes que ganaste un sorteo en el que nunca participaste.",
            "2. Los Datos: para 'reclamarlo' piden tus datos personales, de tarjeta o un pago de envío.",
            "3. El Silencio: después del pago o de entregar tus datos, la cuenta desaparece.",
        ]
        case .tiendaClonada: [
            "1. La Copia: un sitio imita el diseño y el nombre de una marca real, con un dominio parecido.",
            "2. El Pago: solo acepta transferencia o pide los datos completos de tu tarjeta.",
            "3. La Desaparición: el pedido nunca llega y el sitio cambia de dominio.",
        ]
        case .marketplace: [
            "1. La Publicación: un vendedor ofrece un producto muy por debajo de su precio.",
            "2. El Anticipo: pide un depósito o un pago fuera de la plataforma para 'apartarlo'.",
            "3. Sin Entrega: tras el pago, el vendedor deja de responder o borra el perfil.",
        ]
        case .llamada: [
            "1. La Suplantación: alguien llama diciendo ser del banco, del SAT o un familiar en problemas.",
            "2. La Urgencia: inventa una emergencia para que actúes sin verificar.",
            "3. La Petición: pide códigos, contraseñas o una transferencia inmediata.",
        ]
        case .otro: [
            "1. El Gancho: una oferta de empleo, préstamo o apoyo que parece fácil de obtener.",
            "2. El Cobro: piden un pago por adelantado o tus datos personales.",
            "3. El Engaño: el beneficio nunca llega y tus datos pueden usarse para otros fraudes.",
        ]
        }
    }
}

nonisolated enum NivelRiesgo: String, Codable, Sendable, CaseIterable, Comparable {
    case noEvaluado = "NO_EVALUADO"
    case bajo = "BAJO"
    case medio = "MEDIO"
    case alto = "ALTO"
    case muyAlto = "MUY_ALTO"

    var titulo: String {
        switch self {
        case .noEvaluado: "SIN EVALUAR"
        case .bajo: "BAJO"
        case .medio: "MEDIO"
        case .alto: "ALTO"
        case .muyAlto: "MUY ALTO"
        }
    }

    /// Los que puede asignar un Administrador al validar.
    static let asignables: [NivelRiesgo] = [.bajo, .medio, .alto, .muyAlto]

    private var rango: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (a: NivelRiesgo, b: NivelRiesgo) -> Bool { a.rango < b.rango }
}

/// Columna `Usuario.estado_cuenta`.
nonisolated enum EstadoCuenta: String, Codable, Sendable {
    case activo = "ACTIVO"
    case suspendido = "SUSPENDIDO"
}

/// "¿A quién le ocurrió el fraude?" (columna nueva `Reporte.afectado`).
nonisolated enum Afectado: String, Codable, Sendable, CaseIterable {
    case yo = "YO"
    case otraPersona = "OTRA_PERSONA"

    var titulo: String { self == .yo ? "A mí" : "A otra persona" }
}
