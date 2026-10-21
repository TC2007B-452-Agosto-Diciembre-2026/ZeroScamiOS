//
//  Usuario.swift
//  PrototipoApp
//
//  Tabla Usuario tal como la ve la propia persona. El hash de la contraseña nunca sale del
//  servidor: no existe en este tipo.
//

import Foundation

nonisolated struct Preferencias: Codable, Sendable, Hashable {
    var notificaciones = false
    var modoOscuro = true
    var dosPasos = false
    var perfilPublico = false
    var analiticas = true
}

/// Qué versión del aviso de privacidad aceptó y cuándo (consentimiento, LFPDPPP).
nonisolated struct Consentimiento: Codable, Sendable, Hashable {
    var versionAviso: String
    var fecha: Date
}

nonisolated struct Usuario: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    var rol: Rol
    var nombre: String
    var apellido: String
    var pais: String
    var alias: String
    var correo: String
    var biografia: String
    var avatarRuta: String?
    var estadoCuenta: EstadoCuenta
    var fechaRegistro: Date
    var preferencias: Preferencias
    var consentimiento: Consentimiento
}

/// Lo que llena la pantalla de Registro. No es `Codable` a propósito: lleva la contraseña.
nonisolated struct RegistroDatos: Sendable, Hashable {
    var nombre = ""
    var apellido = ""
    var pais = "México"
    var alias = ""
    var correo = ""
    var contrasena = ""
    var confirmacion = ""
    var aceptaAviso = false
}

/// Lo que llena Editar perfil. La contraseña actual solo se pide si cambia el correo.
nonisolated struct PerfilDatos: Sendable, Hashable {
    var nombre: String
    var apellido: String
    var pais: String
    var alias: String
    var correo: String
    var biografia: String
    var contrasenaActual: String?

    init(desde u: Usuario) {
        nombre = u.nombre
        apellido = u.apellido
        pais = u.pais
        alias = u.alias
        correo = u.correo
        biografia = u.biografia
        contrasenaActual = nil
    }
}

nonisolated extension Usuario {
    /// Solo para estados iniciales de pantalla y pruebas; nunca se envía.
    static let vacio = Usuario(id: 0, rol: .usuario, nombre: "", apellido: "", pais: "México", alias: "", correo: "",
                               biografia: "", avatarRuta: nil, estadoCuenta: .activo, fechaRegistro: .distantPast,
                               preferencias: Preferencias(),
                               consentimiento: Consentimiento(versionAviso: "2026-10", fecha: .distantPast))
}
nonisolated extension Consentimiento {
    /// Versión del aviso de privacidad que muestra PrivacyNoticeView.
    static let versionAvisoVigente = "2026-10c"
}
