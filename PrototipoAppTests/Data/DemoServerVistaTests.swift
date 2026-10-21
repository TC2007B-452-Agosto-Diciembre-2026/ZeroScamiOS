//
//  DemoServerVistaTests.swift
//  PrototipoAppTests
//
//  Lo que cada quien ve de un mismo reporte (privacidad por diseño).
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerVistaTests {
    let e = EntornoPrueba()

    private func vista(_ idReporte: Int64, comoToken token: String) async throws -> Reporte {
        let yo = try await e.servidor.usuarioActual(token)
        let fila = try #require(await e.servidor.db.reportes.first { $0.id == idReporte })
        return await e.servidor.vista(fila, para: yo)
    }

    @Test func anonimoSeOcultaALaComunidadPeroNoAlStaff() async throws {
        let comunidad = try await vista(117, comoToken: try await e.nuevaCuenta())
        #expect(comunidad.autor.nombre == "Anónimo")
        #expect(comunidad.autor.idUsuario == nil)
        let staff = try await vista(117, comoToken: try await e.token(EntornoPrueba.admin))
        #expect(staff.autor.nombre == "vecina_alerta (anónimo)")
    }

    @Test func perfilPrivadoSeMuestraComoMiembro() async throws {
        let r = try await vista(106, comoToken: try await e.nuevaCuenta())
        #expect(r.autor.nombre == "Miembro de la comunidad")
        #expect(r.autor.idUsuario == nil)
        let publico = try await vista(101, comoToken: try await e.nuevaCuenta(alias: "prueba_02", correo: "dos@comunidad.test"))
        #expect(publico.autor.nombre == "tecno_mx")
    }

    @Test func personaAfectadaSoloParaAutorYStaff() async throws {
        #expect(try await vista(118, comoToken: try await e.nuevaCuenta()).personaAfectada == nil)
        #expect(try await vista(118, comoToken: try await e.token(EntornoPrueba.admin)).personaAfectada?.nombre == "Rosa Martínez")
    }

    @Test func elAutorSeVeComoTu() async throws {
        let r = try await vista(122, comoToken: try await e.token(EntornoPrueba.usuario))
        #expect(r.autor.nombre == "Tú")
        #expect(r.esMio)
    }

    @Test func confirmacionesSumanLasPrevias() async throws {
        let r = try await vista(101, comoToken: try await e.token(EntornoPrueba.usuario))
        #expect(r.confirmaciones == 1_200)
        #expect(r.comentarios == 2)
        #expect(r.guardadoPorMi)
    }

    @Test func soloStaffYAutorVenLoNoPublico() async throws {
        let yo = try await e.servidor.usuarioActual(try await e.nuevaCuenta())
        let fila = try #require(await e.servidor.db.reportes.first { $0.id == 117 })
        let puede = await e.servidor.puedeVer(fila, yo)
        #expect(!puede)
    }
}
