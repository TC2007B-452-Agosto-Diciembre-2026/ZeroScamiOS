//
//  LimiteIntentosTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct LimiteIntentosTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func cuatroFallosNoBloquean() {
        var r = RegistroIntentos()
        for _ in 1...4 { LimiteIntentos.registrarFallo(&r, ahora: t0) }
        #expect(LimiteIntentos.bloqueadoHasta(r, ahora: t0) == nil)
    }

    @Test func elQuintoBloqueaUnMinuto() {
        var r = RegistroIntentos()
        for _ in 1...5 { LimiteIntentos.registrarFallo(&r, ahora: t0) }
        #expect(LimiteIntentos.bloqueadoHasta(r, ahora: t0) == t0.addingTimeInterval(60))
        #expect(LimiteIntentos.bloqueadoHasta(r, ahora: t0.addingTimeInterval(61)) == nil)
    }

    @Test func cadaFalloDespuesDuplicaHastaQuinceMinutos() {
        var r = RegistroIntentos()
        var t = t0
        for _ in 1...5 { LimiteIntentos.registrarFallo(&r, ahora: t) }
        var esperados: [TimeInterval] = [120, 240, 480, 900, 900]
        while let duracion = esperados.first {
            t = (r.bloqueadoHasta ?? t).addingTimeInterval(1)
            LimiteIntentos.registrarFallo(&r, ahora: t)
            #expect(r.bloqueadoHasta == t.addingTimeInterval(duracion))
            esperados.removeFirst()
        }
    }

    // MARK: - Bordes: datos extremos o corruptos no deben tumbar la app

    @Test func contadorEnElMaximoNoDesbordaYQuedaEnElTope() {
        var r = RegistroIntentos(fallidos: Int.max, bloqueadoHasta: nil)
        LimiteIntentos.registrarFallo(&r, ahora: t0)
        #expect(r.fallidos == Int.max)
        #expect(r.bloqueadoHasta == t0.addingTimeInterval(LimiteIntentos.bloqueoMaximo))
    }

    @Test func contadoresGrandesSiempreDanElTope() {
        for inicial in [100, 1_000, 1_000_000, Int.max - 1] {
            var r = RegistroIntentos(fallidos: inicial, bloqueadoHasta: nil)
            LimiteIntentos.registrarFallo(&r, ahora: t0)
            #expect(r.bloqueadoHasta == t0.addingTimeInterval(900))
        }
    }

    @Test func contadorNegativoCorruptoNoCrasheaNiBloquea() {
        for inicial in [-1, -1_000, Int.min] {
            var r = RegistroIntentos(fallidos: inicial, bloqueadoHasta: nil)
            LimiteIntentos.registrarFallo(&r, ahora: t0)
            #expect(r.fallidos == 1)
            #expect(r.bloqueadoHasta == nil)
        }
    }

    @Test func relojQueRetrocedeNoExtiendeElBloqueoMasDelMaximo() {
        var r = RegistroIntentos()
        for _ in 1...9 { LimiteIntentos.registrarFallo(&r, ahora: t0) }
        let atras = t0.addingTimeInterval(-10_000_000)
        let hasta = LimiteIntentos.bloqueadoHasta(r, ahora: atras)
        #expect(hasta == atras.addingTimeInterval(LimiteIntentos.bloqueoMaximo))
    }

    @Test func fechaDeBloqueoManipuladaEnElFuturoSeAcota() {
        let r = RegistroIntentos(fallidos: 5, bloqueadoHasta: .distantFuture)
        let hasta = LimiteIntentos.bloqueadoHasta(r, ahora: t0)
        #expect(hasta == t0.addingTimeInterval(LimiteIntentos.bloqueoMaximo))
    }

    @Test func relojEnLosExtremosOConNaNNoCrashea() {
        let nan = Date(timeIntervalSinceReferenceDate: .nan)
        for ahora in [Date.distantPast, Date.distantFuture, nan] {
            var r = RegistroIntentos(fallidos: 4, bloqueadoHasta: nil)
            LimiteIntentos.registrarFallo(&r, ahora: ahora)
            _ = LimiteIntentos.bloqueadoHasta(r, ahora: ahora)
            _ = LimiteIntentos.bloqueadoHasta(r, ahora: t0)
        }
    }

    @Test func registroCorruptoDecodificadoNoCrashea() throws {
        let json = Data(#"{"fallidos":9223372036854775807,"bloqueadoHasta":1e300}"#.utf8)
        var r = try JSONDecoder().decode(RegistroIntentos.self, from: json)
        LimiteIntentos.registrarFallo(&r, ahora: t0)
        let hasta = LimiteIntentos.bloqueadoHasta(r, ahora: t0)
        #expect(hasta == t0.addingTimeInterval(900))
    }

    @Test func viajeDeIdaYVueltaPorCodableConservaElRegistro() throws {
        var r = RegistroIntentos()
        for _ in 1...6 { LimiteIntentos.registrarFallo(&r, ahora: t0) }
        let otro = try JSONDecoder().decode(RegistroIntentos.self, from: JSONEncoder().encode(r))
        #expect(otro == r)
    }
}
