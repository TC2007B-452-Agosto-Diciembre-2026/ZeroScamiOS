//
//  CommunityStatsView.swift
//  PrototipoApp
//
//  Reemplaza: escena `stats-vc` / CommunityStatsViewController. Antes las cifras eran fijas;
//  ahora se calculan con los reportes validados y canalizados.
//

import SwiftUI

struct CommunityStatsView: View {
    @Environment(ReportsStore.self) private var reports

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("El impacto colectivo de ZeroScam en números, calculado con los reportes validados de la comunidad.")
                    .ofraude(14, color: Theme.textMuted)

                CargaView(carga: reports.estadisticas, reintentar: { await reports.cargarEstadisticas() }) { e in
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            statCard(Formato.miles(e.personasAyudadas), "PERSONAS AYUDADAS")
                            statCard(Formato.miles(e.reportesVerificados), "REPORTES VERIFICADOS")
                        }
                        HStack(spacing: 12) {
                            statCard(Formato.miles(e.estafasDetenidas), "ESTAFAS DETENIDAS")
                            statCard(Formato.miles(e.zonasCubiertas), "ZONAS CUBIERTAS")
                        }
                    }
                }

                Text("Cada reporte que envías fortalece esta red. Gracias por mantener alerta a tu comunidad.")
                    .ofraude(13, color: Theme.textMuted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationTitle("Estadísticas")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reports.version) { await reports.cargarEstadisticas() }
    }

    private func statCard(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).ofraude(26, .bold, color: Theme.accent).contentTransition(.numericText())
            Text(label).ofraude(11, .medium, color: Theme.textMuted)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 90)
        .ofraudeCard(radius: 10, fill: Theme.field)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { CommunityStatsView() }
        .entornoDePrueba()
}
