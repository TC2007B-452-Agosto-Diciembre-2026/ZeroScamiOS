//
//  Components.swift
//  PrototipoApp
//
//  Piezas compartidas que en el original vivían repetidas en el storyboard o en extensions:
//  - `applyOfraudeStyle()` de UITextField      -> OfraudeTextField / LabeledTextField
//  - `hideKeyboardOnTap()` de UIViewController -> View.hideKeyboardOnTap()
//  - las barras superiores hechas a mano       -> TopBar
//

import SwiftUI

// MARK: - Texto e íconos

/// Tamaño del storyboard, ya agrandado (`Theme.tamanoLegible`), que además crece con Dynamic Type
/// (relativo al estilo "body").
private struct FuenteEscalable: ViewModifier {
    @ScaledMetric private var tamano: CGFloat
    private let peso: Font.Weight

    init(_ tamano: CGFloat, peso: Font.Weight) {
        _tamano = ScaledMetric(wrappedValue: Theme.tamanoLegible(tamano), relativeTo: .body)
        self.peso = peso
    }

    func body(content: Content) -> some View {
        content.font(.system(size: tamano, weight: peso))
    }
}

extension Text {
    /// Tamaño, peso y color en una sola llamada: los mismos tres datos que muestra el
    /// storyboard para cada label. Crece con Dynamic Type.
    func ofraude(_ size: CGFloat, _ weight: Font.Weight = .regular, color: Color) -> some View {
        foregroundStyle(color).modifier(FuenteEscalable(size, peso: weight))
    }
}

/// Un SF Symbol con tamaño fijo (los imageView del storyboard tenían alto y ancho fijos).
struct Symbol: View {
    let name: String
    let size: CGFloat
    let color: Color

    init(_ name: String, size: CGFloat, color: Color) {
        self.name = name
        self.size = size
        self.color = color
    }

    var body: some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
    }
}

// MARK: - Campos de texto

struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text).ofraude(12, .medium, color: Theme.accent)
    }
}

/// Campo de texto con el estilo de ZeroScam (antes `applyOfraudeStyle()`): fondo, borde de 1 pt,
/// radio 8, alto mínimo 48, texto de 15 pt, cursor naranja y 13 pt de margen. Borde rojo si hay error.
struct OfraudeTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contenido: UITextContentType? = nil
    var error = false
    var maximo: Int? = nil
    var foco: FocusState<Campo?>.Binding? = nil
    var campo: Campo? = nil
    var identificador: String? = nil
    /// Nombre del campo para VoiceOver (el placeholder solo no lo describe).
    var etiqueta: String? = nil

    /// Correos, usuarios y enlaces sin mayúscula automática.
    private var mayusculas: TextInputAutocapitalization {
        let sinMayuscula: [UITextContentType] = [.username, .nickname, .emailAddress, .URL, .oneTimeCode]
        if keyboard == .emailAddress || keyboard == .URL { return .never }
        if let contenido, sinMayuscula.contains(contenido) { return .never }
        return .sentences
    }

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.textMuted))
            .keyboardType(keyboard)
            .textContentType(contenido)
            .textInputAutocapitalization(mayusculas)
            .autocorrectionDisabled()
            .ofraudeFont(15)
            .foregroundStyle(Theme.textLight)
            .tint(Theme.accent)
            .enfoque(foco, campo)
            .identificador(identificador)
            .etiquetaAccesible(etiqueta)
            .padding(.horizontal, 13)
            .frame(minHeight: 48)
            .ofraudeCampo(error: error)
            .onChange(of: text) { _, nuevo in
                if let maximo, nuevo.count > maximo { text = String(nuevo.prefix(maximo)) }
            }
    }
}

/// Etiqueta naranja + campo + error, con 8 pt entre ellos (el stackView vertical del storyboard).
struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contenido: UITextContentType? = nil
    var error: String? = nil
    var maximo: Int? = nil
    var foco: FocusState<Campo?>.Binding? = nil
    var campo: Campo? = nil
    var identificador: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // La etiqueta visual se oculta a VoiceOver: el campo ya la lleva como su nombre.
            FieldLabel(label).accessibilityHidden(true)
            OfraudeTextField(placeholder: placeholder, text: $text, keyboard: keyboard, contenido: contenido,
                             error: error != nil, maximo: maximo, foco: foco, campo: campo, identificador: identificador,
                             etiqueta: label)
            FieldError(mensaje: error)
        }
    }
}

// MARK: - Botones

/// Botón de relleno. Los valores por defecto son los del botón de Login (naranja, letra blanca
/// de 15 medium, radio 8, alto 52); cada pantalla cambia solo lo que difiere.
struct OfraudeButtonStyle: ButtonStyle {
    var background: Color = Theme.accent
    var foreground: Color = .white
    var size: CGFloat = 15
    var weight: Font.Weight = .medium
    var radius: CGFloat = 8
    var height: CGFloat = 52
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ofraudeFont(size, weight)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, fullWidth ? 0 : 20)
            .padding(.vertical, 6)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: height)
            .background(background, in: RoundedRectangle(cornerRadius: radius))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Layout

/// Pastilla de 26 pt (tipo, severidad, estado). Antes estaba escrita a mano en el detalle.
struct Etiqueta: View {
    let texto: String
    let color: Color
    let fondo: Color

    var body: some View {
        Text(texto)
            .ofraude(12, .semibold, color: color)
            .padding(.horizontal, 12)
            .frame(minHeight: 26)
            .background(fondo, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Línea divisoria de 1 pt.
struct Hairline: View {
    var color: Color = Theme.border

    var body: some View {
        color.frame(height: 1)
    }
}

/// Logotipo de la app: el nombre «ZEROSCAM» y, debajo, la empresa dueña («por 0Fraude»).
struct MarcaZeroScam: View {
    var size: CGFloat = 28
    var color: Color = Theme.accent

    var body: some View {
        VStack(spacing: 4) {
            Text("ZEROSCAM").ofraude(size, .bold, color: color)
            Text("por 0Fraude").ofraude(max(12, size * 0.45), .medium, color: Theme.textMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ZeroScam, por 0Fraude")
    }
}

/// Barra superior hecha a mano (64 pt, título "ZEROSCAM" centrado, ícono a la derecha) de
/// Inicio, Buscar y Perfil. Esas pantallas ocultan la barra de navegación del sistema.
struct TopBar<Trailing: View>: View {
    var background: Color
    var titleSize: CGFloat = 20
    var titleColor: Color = Theme.textPrimary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text("ZEROSCAM").ofraude(titleSize, .bold, color: titleColor)
            HStack {
                Spacer()
                trailing().frame(width: 24, height: 24)
            }
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
        .background(background)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

extension View {
    /// Fondo azul marino de todas las pantallas (el `backgroundColor` de la vista raíz).
    func ofraudeScreen() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// Cierra el teclado al tocar fuera de un campo (equivale a `cancelsTouchesInView = false`
    /// del original). Gesto normal, no simultáneo: así un toque sobre un campo o un botón lo
    /// atiende ese control primero y este gesto de fondo no le gana el toque (con
    /// `simultaneousGesture` sí se lo ganaba, y el teclado se cerraba al tocar el siguiente campo).
    func hideKeyboardOnTap() -> some View {
        gesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }

    /// Tarjeta: fondo, radio y borde de 1 pt en negro (ver `Theme.defaultBorder`).
    func ofraudeCard(radius: CGFloat = 0, borderWidth: CGFloat = 1, fill: Color = Theme.card) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                if borderWidth > 0 {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Theme.defaultBorder, lineWidth: borderWidth)
                }
            }
    }
}

extension View {
    /// Fuente del sistema con el tamaño y peso del storyboard, agrandada y con Dynamic Type.
    func ofraudeFont(_ tamano: CGFloat, _ peso: Font.Weight = .regular) -> some View {
        modifier(FuenteEscalable(tamano, peso: peso))
    }

    /// Fondo, borde y radio de un campo; borde rojo si hay error.
    func ofraudeCampo(error: Bool = false) -> some View {
        background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(error ? Theme.danger : Theme.border, lineWidth: 1))
    }

    /// `.focused` solo si la pantalla maneja el foco; los campos sin foco funcionan igual que antes.
    @ViewBuilder func enfoque(_ foco: FocusState<Campo?>.Binding?, _ campo: Campo?) -> some View {
        if let foco, let campo { focused(foco, equals: campo) } else { self }
    }

    /// Nombre accesible solo si se da uno; sin él el campo conserva su comportamiento.
    @ViewBuilder func etiquetaAccesible(_ etiqueta: String?) -> some View {
        if let etiqueta { accessibilityLabel(etiqueta) } else { self }
    }

    /// Identificador para XCUITest (sin efecto visible).
    @ViewBuilder func identificador(_ id: String?) -> some View {
        if let id { accessibilityIdentifier(id) } else { self }
    }
}
