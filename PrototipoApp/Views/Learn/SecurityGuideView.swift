//
//  SecurityGuideView.swift
//  PrototipoApp
//
//  Reemplaza: escena `guide-vc` / SecurityGuideViewController.
//  Los tres capítulos abren el mismo artículo (igual que el original).
//

import SwiftUI

struct SecurityGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Centrado en el storyboard (textAlignment="center").
                Text("Tácticas de evasión, identificación de amenazas y protocolos de respuesta ante el fraude digital.")
                    .ofraude(15, color: Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                chapter("CAPÍTULO 01", Theme.accent, "Cómo identificar ofertas falsas", titleSize: 24, titleWeight: .bold,
                        "Los estafadores usan descuentos irreales y urgencia fabricada ('solo por hoy') para que compres sin pensar.",
                        "Leer el informe completo ›", articulo: .ofertasFalsas, numero: 1)
                chapter("CAPÍTULO 02", Theme.accent, "Protegiendo tus contraseñas", titleSize: 20, titleWeight: .semibold,
                        "La reutilización de contraseñas es el vector de ataque más común.",
                        "Ver Protocolo ›", articulo: .contrasenas, numero: 2)
                chapter("CAPÍTULO 03", Theme.danger, "Qué hacer tras un fraude", titleSize: 20, titleWeight: .semibold,
                        "Acción inmediata: congele activos, reporte a las autoridades y documente la evidencia.",
                        "Manual de respuesta ›", articulo: .respuesta, numero: 3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chapter(_ label: String, _ labelColor: Color, _ title: String, titleSize: CGFloat,
                         titleWeight: Font.Weight, _ summary: String, _ link: String,
                         articulo: Articulo, numero: Int) -> some View {
        NavigationLink(value: Route.article(articulo)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).ofraude(13, .bold, color: labelColor)
                Text(title).ofraude(titleSize, titleWeight, color: .white)
                Text(summary).ofraude(15, color: Theme.textMuted)
                Text(link).ofraude(14, .semibold, color: .white)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ofraudeCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("guia.capitulo.\(numero)")
    }
}

#Preview {
    NavigationStack { SecurityGuideView() }
        .entornoDePrueba()
}
