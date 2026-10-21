//
//  PasswordHasherTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct PasswordHasherTests {
    let hasher = PasswordHasher(iteraciones: 1_000)

    private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    @Test func vectoresConocidosDePBKDF2SHA256() {
        let sal = Data("salt".utf8)
        #expect(hex(PasswordHasher.pbkdf2("password", sal: sal, iteraciones: 1)) ==
                "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        #expect(hex(PasswordHasher.pbkdf2("password", sal: sal, iteraciones: 4_096)) ==
                "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    @Test func formatoGuardado() {
        let partes = hasher.hash("Segura#2026x").split(separator: "$")
        #expect(partes.count == 4)
        #expect(partes[0] == "pbkdf2_sha256")
        #expect(partes[1] == "1000")
    }

    @Test func mismaContrasenaDistintoHash() {
        // La sal es aleatoria: dos hashes de la misma contraseña deben salir distintos.
        let primero = hasher.hash("Segura#2026x")
        let segundo = hasher.hash("Segura#2026x")
        #expect(primero != segundo)
    }

    @Test func verificaSoloLaCorrecta() {
        let guardado = hasher.hash("Segura#2026x")
        #expect(hasher.verificar("Segura#2026x", contra: guardado))
        #expect(!hasher.verificar("segura#2026x", contra: guardado))
        #expect(!hasher.verificar("", contra: guardado))
    }

    @Test func hashesMalformadosNuncaVerifican() {
        for malo in ["", "md5$1$a$b", "pbkdf2_sha256$10$AAAA$AAAA", "pbkdf2_sha256$1000$no-base64$AAAA", "pbkdf2_sha256$1000$AAAA"] {
            #expect(!hasher.verificar("x", contra: malo))
        }
    }

    @Test func iteracionesFueraDeRangoONoNumericasNuncaVerifican() {
        for n in ["99999999999", "10000001", "999", "abc", "-5", "99999999999999999999"] {
            #expect(!hasher.verificar("x", contra: "pbkdf2_sha256$\(n)$AAAA$AAAA"))
        }
    }

    @Test func pbkdf2ConIteracionesInvalidasFallaCerrado() {
        #expect(PasswordHasher.pbkdf2("x", sal: Data([1]), iteraciones: 5_000_000_000).isEmpty)
        #expect(PasswordHasher.pbkdf2("x", sal: Data([1]), iteraciones: -1).isEmpty)
    }

    @Test func byteNuloNoTruncaLaContrasena() {
        let guardado = hasher.hash("abc")
        #expect(hasher.verificar("abc", contra: guardado))
        #expect(!hasher.verificar("abc\u{0}def", contra: guardado))
        #expect(PasswordHasher.pbkdf2("abc\u{0}def", sal: Data([1]), iteraciones: 1) !=
                PasswordHasher.pbkdf2("abc", sal: Data([1]), iteraciones: 1))
    }

    @Test func normalizaUnicode() {
        let compuesta = "Contraseña#2026"
        let descompuesta = "Contrasen\u{0303}a#2026"
        #expect(hasher.verificar(descompuesta, contra: hasher.hash(compuesta)))
    }

    @Test func comparacionEnTiempoConstante() {
        #expect(PasswordHasher.igualesEnTiempoConstante(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(!PasswordHasher.igualesEnTiempoConstante(Data([1, 2, 3]), Data([1, 2, 4])))
        #expect(!PasswordHasher.igualesEnTiempoConstante(Data([1, 2]), Data([1, 2, 3])))
    }

    @Test func aleatoriosConFormaCorrecta() {
        #expect(Aleatorio.bytes(16).count == 16)
        let primero = Aleatorio.token()
        let segundo = Aleatorio.token()
        #expect(primero != segundo)
        #expect(Aleatorio.token().count == 43 && !Aleatorio.token().contains("="))
        #expect(!Aleatorio.token().contains("+") && !Aleatorio.token().contains("/"))
        #expect(Aleatorio.codigo().wholeMatch(of: /[0-9]{6}/) != nil)
    }
}
