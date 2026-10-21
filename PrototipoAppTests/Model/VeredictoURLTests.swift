//
//  VeredictoURLTests.swift
//  PrototipoAppTests
//
//  "¿Es legítimo?": el veredicto nunca dice legítimo si hay una señal de riesgo o el sitio no se
//  pudo revisar.
//

import Foundation
import Testing
@testable import PrototipoApp

struct VeredictoURLTests {
    private func diagnostico(_ nivel: NivelRiesgo, senales: Int = 0, certificado: String? = "VALIDO") -> DiagnosticoURL {
        let verificaciones = (0..<4).map { i in
            VerificacionURL(tipo: [.estructura, .certificado, .antiguedad, .listaNegra][i], paso: i >= senales, detalle: "d\(i)")
        }
        return DiagnosticoURL(url: "https://ejemplo.com", dominio: "ejemplo.com", nivelRiesgo: nivel, puntaje: 10,
                              verificaciones: verificaciones, estadoCertificado: certificado, fecha: Date())
    }

    @Test func bajoSinSenalesPareceLegitimo() {
        #expect(diagnostico(.bajo).veredicto == .pareceLegitimo)
    }

    @Test func bajoConUnaSenalEsDudoso() {
        #expect(diagnostico(.bajo, senales: 1).veredicto == .dudoso)
    }

    @Test func sinCertificadoVerificableEsDudoso() {
        #expect(diagnostico(.bajo, certificado: "INACCESIBLE").veredicto == .dudoso)
    }

    @Test(arguments: ["INSEGURO", "EXPIRADO", "SIN HTTPS", "inaccesible"])
    func certificadoConProblemaEsDudoso(_ estado: String) {
        #expect(diagnostico(.bajo, certificado: estado).veredicto == .dudoso)
    }

    @Test func sinEstadoDeCertificadoEsDudoso() {
        #expect(diagnostico(.bajo, certificado: nil).veredicto == .dudoso)
    }

    @Test func sinEvaluarNuncaPareceLegitimo() {
        #expect(diagnostico(.noEvaluado).veredicto == .dudoso)
    }

    @Test func sinVerificacionesEsDudoso() {
        let d = DiagnosticoURL(url: "https://ejemplo.com", dominio: "ejemplo.com", nivelRiesgo: .bajo, puntaje: 0,
                               verificaciones: [], estadoCertificado: "VALIDO", fecha: Date())
        #expect(d.veredicto == .dudoso)
    }

    @Test func demoConHTTPSySinSenalesPareceLegitimo() {
        #expect(diagnostico(.bajo, certificado: "HTTPS").veredicto == .pareceLegitimo)
    }

    @Test func medioEsDudoso() {
        #expect(diagnostico(.medio).veredicto == .dudoso)
    }

    @Test(arguments: [NivelRiesgo.alto, .muyAlto])
    func altoNoEsLegitimo(_ nivel: NivelRiesgo) {
        #expect(diagnostico(nivel).veredicto == .noLegitimo)
    }

    @Test func elDemoDaVeredictoParaUnSitioReportado() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        let backend = e.backend(secretos)
        let session = SessionStore(backend: backend, secretos: secretos)
        try await session.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
        let d = try await backend.analizarURL("http://banco-seguro-mx.xyz/login@verificar")
        #expect(d.veredicto != .pareceLegitimo)
    }
}
