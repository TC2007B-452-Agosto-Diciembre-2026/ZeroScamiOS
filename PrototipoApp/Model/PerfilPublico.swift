//
//  PerfilPublico.swift
//  PrototipoApp
//
//  Lo que una persona deja ver de sí misma a la comunidad: alias, biografía, foto y sus reportes
//  públicos no anónimos. Nunca el correo, el nombre real ni el país. Solo existe para quien
//  activó "perfil público" (el staff y la propia persona lo ven siempre).
//

import Foundation

nonisolated struct PerfilPublico: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    let alias: String
    let biografia: String
    let tieneAvatar: Bool
    let miembroDesde: Date
    /// Públicos (VALIDADO o CANALIZADO) y no anónimos, del más nuevo al más antiguo.
    let reportes: [Reporte]
}
