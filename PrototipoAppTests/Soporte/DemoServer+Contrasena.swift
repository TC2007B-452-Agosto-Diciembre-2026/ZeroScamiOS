//
//  DemoServer+Contrasena.swift
//  PrototipoAppTests
//
//  Las pruebas que solo revisan la contraseña actual, la política o el bloqueo no necesitan
//  repetir el paso del código: este atajo crea uno y lo usa. No pasa por `pedirCodigoContrasena`
//  para no gastar el cupo de envíos (3 cada 15 minutos), que tiene sus propias pruebas.
//

import Foundation
@testable import PrototipoApp

extension DemoServer {
    func cambiarContrasena(token: String?, actual: String, nueva: String) throws {
        let yo = try usuarioActual(token)
        let desafio = crearDesafio(para: yo, proposito: .cambiar)
        try cambiarContrasena(token: token, actual: actual, nueva: nueva, desafio: desafio.id, codigo: desafio.codigoDemo ?? "")
    }
}
