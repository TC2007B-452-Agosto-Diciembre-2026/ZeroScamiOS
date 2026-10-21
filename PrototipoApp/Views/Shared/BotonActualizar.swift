//
//  BotonActualizar.swift
//  PrototipoApp
//
//  "Actualizar" de las listas de reportes: vuelve a pedirlas al servidor sin salir de la pantalla.
//  Mientras trabaja muestra un indicador y no acepta otro toque.
//

import SwiftUI

struct BotonActualizar: View {
    var identificador: String
    let accion: () async -> Void

    @State private var trabajando = false

    var body: some View {
        Button {
            guard !trabajando else { return }
            Task {
                trabajando = true
                await accion()
                trabajando = false
            }
        } label: {
            HStack(spacing: 6) {
                if trabajando {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                } else {
                    Symbol("arrow.clockwise", size: 13, color: Theme.accent)
                }
                Text(trabajando ? "Actualizando…" : "Actualizar").ofraude(13, .semibold, color: Theme.accent)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(trabajando)
        .accessibilityLabel(trabajando ? "Actualizando reportes" : "Actualizar reportes")
        .accessibilityIdentifier(identificador)
    }
}
