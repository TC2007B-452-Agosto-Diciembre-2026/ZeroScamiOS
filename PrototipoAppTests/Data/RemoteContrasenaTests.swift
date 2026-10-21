//
//  RemoteContrasenaTests.swift
//  PrototipoAppTests
//
//  El API responde 400 por un código malo y por la contraseña actual equivocada: la app los separa
//  para contar intentos del código y hablar en español. Los textos son los del API
//  (src/auth/auth.service.ts y dto/change-password.dto.ts).
//

import Foundation
import Testing
@testable import PrototipoApp

struct RemoteContrasenaTests {
    private func traducir(_ mensajes: [String]) -> AppError {
        RemoteBackend.errorDeContrasena(.validacion(mensajes))
    }

    @Test func unCodigoMaloEsCodigoInvalido() {
        #expect(traducir(["El código no es válido o ya expiró"]) == .codigoInvalido)
        #expect(traducir(["code debe tener 6 dígitos"]) == .codigoInvalido)
        #expect(traducir(["challengeId must be longer than or equal to 64 characters"]) == .codigoInvalido)
    }

    @Test func laActualEquivocadaEsCredencialesInvalidas() {
        #expect(traducir(["El password actual es incorrecto"]) == .credencialesInvalidas)
        #expect(traducir(["El password actual es incorrecto. Pide un código nuevo para intentarlo otra vez."])
                == .credencialesInvalidas)
    }

    @Test func laMismaContrasenaSeDiceEnEspanol() {
        #expect(traducir(["El password nuevo debe ser distinto al actual"])
                == .validacion(["La nueva contraseña debe ser distinta de la actual."]))
    }

    @Test func lasDemasRespuestasPasanIgual() {
        #expect(traducir(["newPassword debe tener al menos un carácter especial"])
                == .validacion(["newPassword debe tener al menos un carácter especial"]))
        #expect(RemoteBackend.errorDeContrasena(.sesionExpirada) == .sesionExpirada)
        #expect(RemoteBackend.errorDeContrasena(.limiteExcedido("x")) == .limiteExcedido("x"))
    }
}
