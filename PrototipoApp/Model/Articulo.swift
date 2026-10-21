//
//  Articulo.swift
//  PrototipoApp
//
//  Los tres artículos de la Guía de seguridad. El primero conserva el texto del artículo
//  original del storyboard.
//

import Foundation

nonisolated enum Articulo: String, Hashable, CaseIterable, Sendable {
    case ofertasFalsas, contrasenas, respuesta

    var etiqueta: String {
        switch self {
        case .ofertasFalsas: "CAPÍTULO 01 · MANUAL OPERATIVO"
        case .contrasenas: "CAPÍTULO 02 · PROTOCOLO"
        case .respuesta: "CAPÍTULO 03 · MANUAL DE RESPUESTA"
        }
    }

    var titulo: String {
        switch self {
        case .ofertasFalsas: "Cómo identificar ofertas falsas"
        case .contrasenas: "Protegiendo tus contraseñas"
        case .respuesta: "Qué hacer tras un fraude"
        }
    }

    var intro: String {
        switch self {
        case .ofertasFalsas:
            "Los estafadores cambian de táctica constantemente, pero casi siempre buscan generar urgencia, miedo o una oportunidad demasiado buena para dejarla pasar. Reconocer esas señales a tiempo es tu primera línea de defensa."
        case .contrasenas:
            "La reutilización de contraseñas es el vector de ataque más común: cuando se filtra un sitio, los atacantes prueban esa misma contraseña en tu correo, tu banco y tus redes."
        case .respuesta:
            "Actuar en las primeras horas reduce el daño. Sigue estos pasos en orden y guarda todo lo que pueda servir como evidencia."
        }
    }

    var puntos: [String] {
        switch self {
        case .ofertasFalsas: [
            "Compara el precio con otras tiendas: un descuento de 70 % o más en productos nuevos casi siempre es falso.",
            "Revisa el dominio letra por letra: «n1ke-outlet» o «mercadolibre-ofertas.store» no son las tiendas oficiales.",
            "Desconfía de los contadores de «solo por hoy» y de las existencias que «se agotan» mientras miras.",
            "Paga con métodos que tengan protección al comprador; evita transferencias y depósitos en tiendas de conveniencia.",
        ]
        case .contrasenas: [
            "Usa una contraseña distinta en cada servicio; un gestor de contraseñas las recuerda por ti.",
            "Prefiere frases largas (más de 12 caracteres) a palabras cortas con símbolos.",
            "Activa la verificación en dos pasos en tu correo y tu banco: aunque roben tu contraseña, no podrán entrar.",
            "Nunca compartas códigos de verificación: ningún banco ni tienda te los pedirá por llamada o mensaje.",
        ]
        case .respuesta: [
            "Llama a tu banco para bloquear la tarjeta o la cuenta y pide la aclaración del cargo.",
            "Cambia las contraseñas de las cuentas afectadas y cierra las sesiones abiertas.",
            "Guarda capturas, correos, números y enlaces del fraude antes de que desaparezcan.",
            "Denuncia ante la autoridad que corresponda y repórtalo en ZeroScam para alertar a otros.",
        ]
        }
    }

    var recuerda: String {
        switch self {
        case .ofertasFalsas:
            "Ninguna institución legítima te pedirá tu contraseña completa o el código de tu tarjeta por teléfono, SMS o WhatsApp."
        case .contrasenas:
            "ZeroScam guarda tu contraseña como un hash con sal: ni el equipo puede leerla."
        case .respuesta:
            "Al reportar en ZeroScam puedes adjuntar tus capturas: la app les quita la ubicación antes de guardarlas."
        }
    }
}
