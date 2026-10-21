//
//  DemoSeedTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoSeedTests {
    let ahora = Date(timeIntervalSince1970: 1_791_072_000)
    var db: DemoDatabase { DemoSeed.base(ahora: ahora) }

    @Test func seisUsuariosConSusRoles() {
        let roles = db.usuarios.map(\.usuario.rol)
        #expect(roles.count == 6)
        #expect(roles.filter { $0 == .owner }.count == 1)
        #expect(roles.filter { $0 == .administrador }.count == 1)
        #expect(roles.filter { $0 == .usuario }.count == 4)
    }

    @Test func aliasYCorreosValidosYUnicos() {
        let usuarios = db.usuarios.map(\.usuario)
        #expect(Set(usuarios.map(\.alias)).count == usuarios.count)
        #expect(Set(usuarios.map(\.correo)).count == usuarios.count)
        for u in usuarios {
            #expect(Validador.esAliasValido(u.alias))
            #expect(Validador.esCorreoValido(u.correo))
        }
    }

    @Test func veintitresReportesYDiecisietePublicos() {
        #expect(db.reportes.count == 23)
        #expect(db.reportes.filter { $0.estado.esPublico }.count == 17)
        #expect(db.reportes.filter { $0.idUsuario == DemoSeed.idUsuario }.count == 3)
    }

    @Test func lasAlertasCriticasSonLasDelStoryboard() {
        let criticas = db.reportes
            .filter { $0.estado.esPublico && $0.nivelRiesgo >= .alto }
            .sorted { $0.fechaCreacion > $1.fechaCreacion }
            .prefix(2)
            .map(\.titulo)
        #expect(criticas == ["Falsa liquidación de tienda de electrónica", "Sorteo falso de iPhone 17 en Instagram"])
    }

    @Test func nadaOcurreEnElFuturo() {
        let base = db
        #expect(base.reportes.allSatisfy { $0.fechaCreacion <= ahora && $0.fechaIncidente <= $0.fechaCreacion })
        #expect(base.historial.allSatisfy { $0.fecha <= ahora })
        #expect(base.comentarios.allSatisfy { $0.fecha <= ahora })
        #expect(base.notificaciones.allSatisfy { $0.fecha <= ahora })
    }

    @Test func cadaReporteTieneSuRegistroInicial() {
        let base = db
        for r in base.reportes {
            #expect(base.historial.contains { $0.idReporte == r.id && $0.anterior == nil && $0.nuevo == .recibido })
            #expect(base.historial.filter { $0.idReporte == r.id }.last?.nuevo == r.estado)
        }
    }

    @Test func idsUnicosYMenoresAlContador() {
        let base = db
        let ids = base.reportes.map(\.id) + base.sitios.map(\.id) + base.comentarios.map(\.id)
            + base.historial.map(\.id) + base.notificaciones.map(\.id) + base.usuarios.map(\.usuario.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0 < base.ultimoID })
    }

    @Test func elUsuarioDemoTieneDosGuardadosYUnaNotificacionSinLeer() {
        let base = db
        #expect(base.guardados.filter { $0.idUsuario == DemoSeed.idUsuario }.map(\.idReporte).sorted() == [101, 102])
        #expect(base.notificaciones.filter { $0.idUsuario == DemoSeed.idUsuario && !$0.leida }.count == 1)
    }

    @Test func lasContrasenasDemoCoincidenConSusHashes() {
        let hasher = PasswordHasher()
        let porCorreo = Dictionary(uniqueKeysWithValues: db.usuarios.map { ($0.usuario.correo, $0.contrasenaHash) })
        #expect(hasher.verificar("Alerta#2026mx", contra: porCorreo["usuario@0fraude.mx"] ?? ""))
        #expect(hasher.verificar("Revisa#2026zs", contra: porCorreo["admin@0fraude.mx"] ?? ""))
        #expect(hasher.verificar("Equipo#2026zs", contra: porCorreo["owner@0fraude.mx"] ?? ""))
    }

    // MARK: - Bordes y contratos extra (D4)

    @Test func todosLosHashesTienenFormatoValidoYSonDistintos() {
        let hashes = db.usuarios.map(\.contrasenaHash) + [DemoSeed.hashSenuelo]
        #expect(Set(hashes).count == hashes.count)
        for h in hashes {
            let partes = h.split(separator: "$", omittingEmptySubsequences: false)
            #expect(partes.count == 4)
            #expect(partes[0] == "pbkdf2_sha256")
            #expect(partes[1] == "600000")
            #expect(Data(base64Encoded: String(partes[2]))?.count == 16)
            #expect(Data(base64Encoded: String(partes[3]))?.count == 32)
        }
    }

    @Test func elSenueloNoVerificaConLasContrasenasDemo() {
        let hasher = PasswordHasher()
        for clave in ["Alerta#2026mx", "Revisa#2026zs", "Equipo#2026zs", ""] {
            #expect(!hasher.verificar(clave, contra: DemoSeed.hashSenuelo))
        }
    }

    @Test func lasCuentasDemoNoVerificanConUnaContrasenaIncorrecta() {
        let hasher = PasswordHasher()
        #expect(!hasher.verificar("Alerta#2026mx", contra: DemoSeed.hashAdmin))
        #expect(!hasher.verificar("incorrecta", contra: DemoSeed.hashUsuario))
    }

    @Test func idsYCorreosDeLasCuentasDemoSonElContrato() {
        let porId = Dictionary(uniqueKeysWithValues: db.usuarios.map { ($0.usuario.id, $0.usuario) })
        #expect(porId[DemoSeed.idOwner]?.correo == "owner@0fraude.mx")
        #expect(porId[DemoSeed.idAdmin]?.alias == "admin_zs")
        #expect(porId[DemoSeed.idUsuario]?.alias == "usuario_01")
        #expect(porId[DemoSeed.idTecno]?.alias == "tecno_mx")
        #expect(porId[DemoSeed.idCompras]?.alias == "compras_seguras")
        #expect(porId[DemoSeed.idVecina]?.alias == "vecina_alerta")
        #expect(db.usuarios.allSatisfy { $0.usuario.consentimiento.versionAviso == Consentimiento.versionAvisoVigente })
        #expect(Consentimiento.versionAvisoVigente == "2026-10c")
    }

    @Test func cadaSitioEstaEnlazadoYSuCertificadoCorrespondeAlEsquema() {
        let base = db
        for r in base.reportes {
            guard let id = r.idSitio else { continue }
            let sitio = base.sitios.first { $0.id == id }
            #expect(sitio != nil)
            #expect(sitio?.estadoCertificado == URLTools.estadoCertificado(sitio?.url ?? ""))
        }
        #expect(base.sitios.count == base.reportes.filter { $0.idSitio != nil }.count)
        #expect(base.sitios.first { $0.url == "http://cupones-supermercado-mx.info" }?.estadoCertificado == "SIN HTTPS")
    }

    @Test func laColaDeModeracionYLosEstadosNoPublicosNoTienenRiesgoEvaluado() {
        let base = db
        let noPublicos = base.reportes.filter { !$0.estado.esPublico }
        #expect(noPublicos.count == 6)
        #expect(noPublicos.allSatisfy { $0.nivelRiesgo == .noEvaluado })
        #expect(base.reportes.filter { $0.estado == .rechazado }.count == 1)
        #expect(base.reportes.first { $0.id == 117 }?.esAnonimo == true)
        #expect(base.reportes.first { $0.id == 118 }?.persona?.nombre == "Rosa Martínez")
    }

    @Test func laSemillaEsDeterministaYSeDesplazaConAhora() {
        let a = DemoSeed.base(ahora: ahora)
        let b = DemoSeed.base(ahora: ahora.addingTimeInterval(86_400))
        #expect(a.reportes.map(\.id) == b.reportes.map(\.id))
        #expect(b.reportes[0].fechaCreacion.timeIntervalSince(a.reportes[0].fechaCreacion) == 86_400)
    }

    @Test func laSemillaSobreviveACodificarYDecodificar() throws {
        let base = db
        let datos = try JSONEncoder().encode(base)
        let vuelta = try JSONDecoder().decode(DemoDatabase.self, from: datos)
        #expect(vuelta.validadaOReconciliada() != nil)
        #expect(vuelta.reportes.count == base.reportes.count)
    }
}
