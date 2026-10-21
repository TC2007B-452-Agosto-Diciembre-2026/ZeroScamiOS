//
//  VerificarEnlaceView.swift
//  PrototipoApp
//
//  "¿Es legítimo este enlace?" (RF07): la persona pega o escribe un enlace y el motor del servidor
//  le dice si parece legítimo, dudoso o no legítimo, con el porqué. El enlace nunca se abre en el
//  teléfono y solo se analiza al tocar el botón (cada análisis queda anotado para avisar si su
//  riesgo sube después).
//

import SwiftUI

struct VerificarEnlaceView: View {
    @State private var texto = ""
    @FocusState private var foco: Campo?

    /// El enlace listo para analizar, o `nil` si lo escrito no es un enlace http(s) válido.
    private var enlace: String? {
        URLTools.pareceURL(texto) ? URLTools.normalizar(texto) : nil
    }

    private var aviso: String? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, enlace == nil else { return nil }
        return URLTools.pareceURL(t)
            ? "Solo se pueden revisar enlaces web (http o https)."
            : "Escribe un enlace completo, por ejemplo tienda-ejemplo.com o https://sitio.com/oferta."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("¿Es legítimo este enlace?").ofraude(24, .bold, color: Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Pega el enlace que te llegó por mensaje, correo o redes. Lo revisamos sin abrirlo en tu teléfono y te decimos si parece legítimo.")
                    .ofraude(14, color: Theme.textSlate)

                VStack(alignment: .leading, spacing: 8) {
                    OfraudeTextField(placeholder: "https://sitio-dudoso.com/oferta", text: $texto, keyboard: .URL,
                                     contenido: .URL, error: aviso != nil, maximo: 300, foco: $foco, campo: .urlOTexto,
                                     identificador: "verificar.campo")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    HStack {
                        PasteButton(payloadType: String.self) { valores in
                            guard let primero = valores.first else { return }
                            texto = String(primero.prefix(300))
                        }
                        .buttonBorderShape(.capsule)
                        .tint(Theme.accent)
                        .labelStyle(.titleAndIcon)
                        .accessibilityIdentifier("verificar.pegar")
                        Spacer()
                        if !texto.isEmpty {
                            Button { texto = "" } label: {
                                Text("Borrar").ofraude(13, .semibold, color: Theme.textSlate)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("verificar.borrar")
                        }
                    }
                    FieldError(mensaje: aviso)
                }

                if let enlace {
                    DiagnosticoURLView(url: enlace)
                } else {
                    consejos
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .hideKeyboardOnTap()
        .ofraudeScreen()
        .navigationTitle("Verificar enlace")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var consejos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUÉ REVISAMOS").ofraude(12, .bold, color: Theme.accent)
            ForEach(["Si el enlace imita a otra marca o esconde su destino.",
                     "Si su certificado de seguridad es válido.",
                     "Hace cuánto existe el dominio.",
                     "Si aparece en listas de sitios peligrosos.",
                     "Si la comunidad ya lo reportó y se validó."], id: \.self) { linea in
                HStack(alignment: .top, spacing: 8) {
                    Symbol("checkmark", size: 12, color: Theme.textSlate).accessibilityHidden(true)
                    Text(linea).ofraude(13, color: Theme.textSlate)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8, fill: Theme.field)
    }
}

#Preview {
    NavigationStack { VerificarEnlaceView() }
        .entornoDePrueba()
}
