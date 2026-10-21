//
//  Theme.swift
//  PrototipoApp
//
//  Todos los colores de ZeroScam en un solo lugar. En el original estaban repetidos en el
//  storyboard, en UITextField+OfraudeStyle y en ReportViewController. Para ajustar la
//  paleta, cambia solo este archivo.
//

import SwiftUI

extension Color {
    /// Color a partir de valores 0-255 (los mismos números que muestra Xcode en el storyboard).
    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

enum Theme {
    // Fondos
    static let background = Color(r: 10, g: 19, b: 48)
    static let card = Color(r: 18, g: 32, b: 74)
    static let field = Color(r: 15, g: 26, b: 56)
    static let selected = Color(r: 26, g: 42, b: 90)
    static let avatarBackground = Color(r: 45, g: 53, b: 81)

    // Bordes de campos y botones de selección
    static let border = Color(r: 42, g: 55, b: 104)

    // Acentos
    static let accent = Color(r: 245, g: 166, b: 35)
    static let danger = Color(r: 225, g: 29, b: 72)
    static let dangerText = Color(r: 255, g: 75, b: 75)
    static let info = Color(r: 0, g: 188, b: 212)
    static let success = Color(r: 76, g: 175, b: 80)

    // Textos
    static let textPrimary = Color(r: 248, g: 249, b: 250)
    static let textLight = Color(r: 219, g: 225, b: 255)
    static let textMuted = Color(r: 156, g: 163, b: 175)
    static let textSlate = Color(r: 148, g: 163, b: 184)
    static let textSection = Color(r: 176, g: 179, b: 185)
    static let textSubtle = Color(r: 119, g: 136, b: 179)

    // Tipografía
    /// Los tamaños del diseño original suben un 12 % y ninguno queda por debajo de 14 pt (antes
    /// había textos de 10 a 12 pt). Encima de esto, el texto crece con Dynamic Type.
    static let escalaTexto: CGFloat = 1.12
    static let tamanoMinimo: CGFloat = 14

    static func tamanoLegible(_ base: CGFloat) -> CGFloat {
        max(tamanoMinimo, (base * escalaTexto).rounded())
    }

    /// En UIKit un borde sin color se dibuja negro. El storyboard nunca les asigna color a los
    /// bordes de las tarjetas, así que se conserva igual que el original.
    static let defaultBorder = Color.black
}
