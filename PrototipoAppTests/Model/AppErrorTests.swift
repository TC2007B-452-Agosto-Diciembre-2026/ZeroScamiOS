//
//  AppErrorTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct AppErrorTests {
    let ahora = Date(timeIntervalSince1970: 1_000)

    @Test func bloqueoRedondeaMinutosHaciaArriba() {
        #expect(AppError.cuentaBloqueada(hasta: ahora.addingTimeInterval(61)).mensaje(ahora: ahora)
                == "Demasiados intentos. Intenta de nuevo en 2 min.")
        #expect(AppError.cuentaBloqueada(hasta: ahora.addingTimeInterval(5)).mensaje(ahora: ahora)
                == "Demasiados intentos. Intenta de nuevo en 1 min.")
    }

    @Test func credencialesNoDicenCualFallo() {
        #expect(AppError.credencialesInvalidas.mensaje() == "Correo o contraseña incorrectos.")
    }

    @Test func errorDesconocidoTieneMensajeGenerico() {
        struct Otro: Error {}
        #expect(Otro().mensajeUsuario == "Ocurrió un error inesperado.")
        #expect(AppError.noEncontrado.mensajeUsuario == "Este contenido ya no está disponible.")
        #expect(AppError.validacion(["Uno.", "Dos."]).mensajeUsuario == "Uno.\nDos.")
    }

    @Test func cargaDevuelveValorSoloSiEstaLista() {
        #expect(Carga<Int>.listo(3).valor == 3)
        #expect(Carga<Int>.cargando.valor == nil)
        #expect(Carga<Int>.error("x").valor == nil)
    }

    // Bordes: una fecha de bloqueo corrupta (NaN, infinito, enorme o ya pasada) no debe tronar la app.
    @Test func bloqueoConFechasExtremasNoTruena() {
        let extremos: [Date] = [
            Date(timeIntervalSinceReferenceDate: .nan),
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: -.infinity),
            Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude),
            Date(timeIntervalSinceReferenceDate: -.greatestFiniteMagnitude),
            .distantFuture, .distantPast
        ]
        for fecha in extremos {
            let texto = AppError.cuentaBloqueada(hasta: fecha).mensaje(ahora: ahora)
            #expect(texto.hasPrefix("Demasiados intentos. Intenta de nuevo en "))
            #expect(texto.hasSuffix(" min."))
        }
        let nanAhora = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(AppError.cuentaBloqueada(hasta: ahora).mensaje(ahora: nanAhora).hasSuffix(" min."))
    }

    @Test func bloqueoYaVencidoMuestraAlMenosUnMinuto() {
        #expect(AppError.cuentaBloqueada(hasta: ahora.addingTimeInterval(-500)).mensaje(ahora: ahora)
                == "Demasiados intentos. Intenta de nuevo en 1 min.")
        #expect(AppError.cuentaBloqueada(hasta: ahora.addingTimeInterval(120)).mensaje(ahora: ahora)
                == "Demasiados intentos. Intenta de nuevo en 2 min.")
    }

    @Test func mensajesFijosYTextosDelServidor() {
        #expect(AppError.conflicto("Ya existe.").mensajeUsuario == "Ya existe.")
        #expect(AppError.sinConexion.mensajeUsuario == "No se pudo conectar con el servidor. Revisa tu conexión.")
        #expect(AppError.validacion([]).mensajeUsuario == "")
    }

    @Test func cargaEsEquatableYSendable() {
        #expect(Carga<Int>.listo(1) == .listo(1))
        #expect(Carga<Int>.listo(1) != .listo(2))
        #expect(Carga<Int>.cargando != .error("x"))
        func requiereSendable<T: Sendable>(_: T) {}
        requiereSendable(Carga<Int>.cargando)
    }
}
