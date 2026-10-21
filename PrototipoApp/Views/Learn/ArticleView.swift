//
//  ArticleView.swift
//  PrototipoApp
//
//  Reemplaza: escena `article-vc` / ArticleViewController. Antes un solo artículo fijo para los
//  tres capítulos; ahora muestra el del capítulo tocado.
//

import SwiftUI

struct ArticleView: View {
    let articulo: Articulo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(articulo.etiqueta).ofraude(12, .medium, color: Theme.accent)
                Text(articulo.titulo).ofraude(26, .bold, color: Theme.textLight).accessibilityAddTraits(.isHeader)
                Text(articulo.intro).ofraude(15, color: Theme.textMuted)

                Text("Puntos clave").ofraude(17, .bold, color: Theme.textLight).accessibilityAddTraits(.isHeader)
                ForEach(articulo.puntos, id: \.self) { punto in
                    Text(verbatim: "•  \(punto)").ofraude(14, color: Theme.textMuted)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("RECUERDA").ofraude(12, .medium, color: Theme.accent)
                    Text(articulo.recuerda).ofraude(14, color: Theme.textLight)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard(radius: 10, fill: Theme.field)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationTitle("Guía")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { ArticleView(articulo: .contrasenas) }
}
