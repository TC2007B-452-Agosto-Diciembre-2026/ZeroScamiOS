# Migración de OFraude a SwiftUI: plan de implementación

> **Para quien ejecute este plan:** usar `superpowers:subagent-driven-development` (recomendado) o `superpowers:executing-plans`. Los pasos usan casillas `- [ ]`.

**Objetivo:** tener OFraude funcionando igual que hoy, pero en SwiftUI, en una carpeta nueva (`PrototipoApp-SwiftUI`) y sin tocar el proyecto original.

**Arquitectura:** un solo `AppState` (`@Observable`) guarda login, pestaña activa, texto de búsqueda precargado, segmento de Perfil y una ruta de navegación por pestaña. `TabView` de 4 pestañas, cada una con su `NavigationStack` ligado a su ruta. Colores, estilo de campos y botones viven en `Theme/`. Una vista por escena del storyboard.

**Tecnologías:** Swift 5, SwiftUI, Observation (`@Observable`), iOS 26.5 (target del original), Xcode 16+ con carpetas sincronizadas (`PBXFileSystemSynchronizedRootGroup`).

**Spec:** `docs/superpowers/specs/2026-09-26-migracion-swiftui-design.md`

## Cambios respecto al spec (descubiertos al leer el storyboard completo)

Estos puntos corrigen o precisan el spec. El spec ya está actualizado con ellos.

1. **No hay una sola `ReportCard`.** Las tarjetas de Inicio, Buscar, Perfil (Mis reportes) y Perfil (Guardados) tienen contenido y tipografías distintos. Un modelo `Report` solo se usa en Perfil (necesita quitar/eliminar tarjetas). El resto del contenido queda literal en cada vista, como estaba en el storyboard. No hay `SampleData.swift`.
2. **Bundle id y nombre distintos en la copia.** Con el mismo bundle id, instalar la copia sobreescribe al original en el simulador y no se pueden comparar. La copia usa `Tec-CCM.PrototipoApp-SwiftUI` y el nombre visible "OFraude SwiftUI".
3. **Build setting extra.** `INFOPLIST_KEY_UIMainStoryboardFile = Main` está en `project.pbxproj` (2 veces) y hay que quitarlo, además de editar `Info.plist`. `LaunchScreen.storyboard` se conserva (es la pantalla de lanzamiento, no la UI).
4. **La barra de pestañas se oculta en las pantallas empujadas.** En el original los "show" segues se empujan sobre el `UINavigationController` que contiene al tab bar, así que cubren toda la pantalla. En SwiftUI: `.toolbar(.hidden, for: .tabBar)` en los destinos.
5. **Rutas por pestaña en `AppState`** (`homePath`, `searchPath`, `reportPath`, `profilePath`). Es lo que permite replicar `popToViewController(tabBarController)` de "Continuar" (ReportSuccess) y de "Reportes Guardados" (Ajustes).
6. **Quirk del original que NO se replica:** la pestaña Reportar muestra la barra de navegación con una flecha "atrás" hacia Login, porque el tab bar está empujado sobre Login. En la copia esa barra aparece vacía, sin flecha.
7. **Quirks del original que SÍ se conservan** (para el análisis de RNF y para que decidas después): los campos de contraseña **no** son seguros (texto visible), las credenciales `admin`/`admin` están fijas en código, "0FRAUDE" se escribe con cero, y ningún formulario valida nada.

## Restricciones globales

- iOS 26.5, Swift 5.0, SwiftUI puro. Sin dependencias externas.
- Sin git: no crear repo ni hacer commits. No copiar `.git`.
- El proyecto original `PrototipoApp/` **no se modifica**.
- Bundle id `Tec-CCM.PrototipoApp-SwiftUI`, nombre visible "OFraude SwiftUI".
- Textos y colores **literales del storyboard original** (ya están en el código de cada tarea). Incluye "0FRAUDE" con cero.
- Los `// TODO` del original siguen siendo botones sin lógica. No agregar funciones, validaciones ni persistencia.
- Los campos de contraseña siguen siendo campos normales (no `SecureField`), igual que el original.
- Comentarios en español, cortos, y solo donde explican el porqué. Cada vista lleva una cabecera `Reemplaza: escena X / XController`.
- Bordes: en UIKit un borde sin color es **negro**. El storyboard nunca les asigna color, así que las tarjetas llevan borde negro de 1 pt (`Theme.defaultBorder`). Solo los campos de texto y los botones de selección de Reportar usan `Theme.border`.
- Cada tarea termina con el build en verde (Receta BUILD).

## Puntos a revisar con cuidado (Review Focus)

1. **Teclado tapando campos** en Registro y Reportar en pantallas chicas. Esperado: se puede hacer scroll hasta el campo y el botón. Se comprueba en Task 11.
2. **Estado viejo tras cerrar sesión y volver a entrar** (pestaña, búsqueda precargada, segmento de Perfil, pilas de navegación). Esperado: todo vuelve a como estaba al abrir la app. Lo cubre la prueba de `AppState` (Task 3).
3. **"Continuar" en ReportSuccess** desde una pila profunda (por ejemplo Inicio → Detalle → "Yo también" → Reportar → Éxito). Esperado: vuelve a la pestaña Inicio con **todas** las pilas vacías. Lo cubre la prueba de `AppState` (Task 3).
4. **Búsqueda precargada cuando Buscar ya es la pestaña visible o ya tenía texto.** Esperado: el campo muestra el texto de la categoría tocada y el valor precargado se consume (no reaparece). Task 5 y Task 11.
5. **Login con campos vacíos, con mayúsculas (`Admin`) o con espacios.** Esperado (igual que el original): solo `admin`/`admin` exactos entran; lo demás muestra "Credenciales inválidas" y no navega. Task 4.
6. **Texto grande (Dynamic Type) y orientación horizontal.** El original permite horizontal en iPhone y usa alturas fijas. Esperado: nada queda inaccesible (todo dentro de `ScrollView` cuando el original ya tenía scroll). Task 11 lo revisa y lo reporta como diferencia si aparece.

## Recetas (se reutilizan en varias tareas)

**Receta BUILD** (desde cualquier carpeta):

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI" && \
xcodebuild -project PrototipoApp.xcodeproj -scheme PrototipoApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath "$TMPDIR/ofraude-dd" build 2>&1 | grep -E "error:|warning: unused|BUILD (SUCCEEDED|FAILED)"
```

Esperado: solo la línea `** BUILD SUCCEEDED **`. Si aparece `error:`, corregir antes de seguir.

**Receta RUN** (instala y abre la app en el simulador; el iPhone 17 puede estar apagado):

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator; sleep 3
xcrun simctl install booted "$TMPDIR/ofraude-dd/Build/Products/Debug-iphonesimulator/PrototipoApp.app"
xcrun simctl terminate booted Tec-CCM.PrototipoApp-SwiftUI 2>/dev/null
xcrun simctl launch booted Tec-CCM.PrototipoApp-SwiftUI
mkdir -p "$TMPDIR/ofraude-shots" && sleep 2 && xcrun simctl io booted screenshot "$TMPDIR/ofraude-shots/${SHOT:-screen}.png"
```

Después abrir el PNG con la herramienta Read para verlo.

## Estructura de archivos

Todo dentro de `PrototipoApp-SwiftUI/PrototipoApp/`:

| Archivo | Responsabilidad |
|---|---|
| `App/OFraudeApp.swift` | `@main`, `RootView` (login o tabs) y `AuthFlow` (Registro → Login) |
| `App/AppState.swift` | Estado compartido, enums `AppTab`, `ProfileSegment`, `Route`. Sin SwiftUI, para poder probarlo solo |
| `Theme/Theme.swift` | Todos los colores |
| `Theme/Components.swift` | `ofraude()` de Text, `Symbol`, `FieldLabel`, `OfraudeTextField`, `LabeledTextField`, `OfraudeButtonStyle`, `Hairline`, `TopBar`, `ofraudeCard`, `ofraudeScreen`, `hideKeyboardOnTap` |
| `Model/Report.swift` | Modelo de tarjetas de Perfil |
| `Views/Route+Destination.swift` | Qué vista abre cada `Route` |
| `Views/Tabs/MainTabView.swift` | `TabView` + `TabStack` |
| `Views/Auth/…`, `Views/Tabs/…`, `Views/Account/…`, `Views/Reports/…`, `Views/Learn/…` | Una vista por escena (ver spec 4.6) |

---

### Task 1: Copiar el proyecto y dejar una app SwiftUI vacía que compile

**Files:**
- Create (copia): `PrototipoApp-SwiftUI/PrototipoApp.xcodeproj`, `PrototipoApp-SwiftUI/PrototipoApp/…`, `PrototipoApp-SwiftUI/database/…`
- Delete (solo en la copia): `Base.lproj/Main.storyboard`, `Controllers/`, `Extensions/`, `App/AppDelegate.swift`, `App/SceneDelegate.swift`
- Modify (solo en la copia): `PrototipoApp/Info.plist`, `PrototipoApp.xcodeproj/project.pbxproj`
- Create: `PrototipoApp/App/OFraudeApp.swift`

**Interfaces:**
- Produces: `struct OFraudeApp: App` con `@main`. Los tasks siguientes agregan archivos en carpetas nuevas y Xcode los detecta solos.

- [ ] **Step 1: Confirmar que el original está limpio y que la carpeta nueva solo tiene `docs/`**

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift" && \
git -C PrototipoApp status --short && ls PrototipoApp-SwiftUI && find PrototipoApp-SwiftUI -type f | head
```

Esperado: `git status` no imprime nada; `ls` muestra solo `docs`; los archivos son el spec y este plan.

- [ ] **Step 2: Copiar el proyecto sin `.git`, sin datos de usuario de Xcode y sin `.gitignore`**

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift" && \
rsync -a --exclude '.git' --exclude '.gitignore' --exclude 'xcuserdata' --exclude '.DS_Store' PrototipoApp/ PrototipoApp-SwiftUI/ && \
ls -A PrototipoApp-SwiftUI && ls PrototipoApp-SwiftUI/PrototipoApp
```

Esperado: aparecen `PrototipoApp`, `PrototipoApp.xcodeproj`, `database` y `docs`; **no** aparece `.git`. Dentro de `PrototipoApp/`: `App Assets.xcassets Base.lproj Controllers Extensions Info.plist`.

- [ ] **Step 3: Borrar en la copia todo el código de UIKit y el storyboard principal**

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI/PrototipoApp" && \
rm Base.lproj/Main.storyboard App/AppDelegate.swift App/SceneDelegate.swift && rm -r Controllers Extensions && \
find . -type f | sort
```

Esperado: quedan `Info.plist`, `Assets.xcassets/…` y `Base.lproj/LaunchScreen.storyboard`.

- [ ] **Step 4: Ajustar `project.pbxproj`: quitar el storyboard principal, cambiar bundle id y nombre visible**

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI" && \
P=PrototipoApp.xcodeproj/project.pbxproj && \
sed -i '' '/INFOPLIST_KEY_UIMainStoryboardFile/d' "$P" && \
sed -i '' 's/"Tec-CCM.PrototipoApp"/"Tec-CCM.PrototipoApp-SwiftUI"/g' "$P" && \
perl -0pi -e 's/(\t+)GENERATE_INFOPLIST_FILE = YES;/$1GENERATE_INFOPLIST_FILE = YES;\n$1INFOPLIST_KEY_CFBundleDisplayName = "OFraude SwiftUI";/g' "$P" && \
grep -n "UIMainStoryboardFile\|PRODUCT_BUNDLE_IDENTIFIER\|CFBundleDisplayName" "$P"
```

Esperado: ninguna línea con `UIMainStoryboardFile`; dos con `PRODUCT_BUNDLE_IDENTIFIER = "Tec-CCM.PrototipoApp-SwiftUI";`; dos con `INFOPLIST_KEY_CFBundleDisplayName = "OFraude SwiftUI";`.

- [ ] **Step 5: Reescribir `Info.plist` sin la referencia al storyboard ni al `SceneDelegate`**

Reemplazar todo el contenido de `PrototipoApp/Info.plist` por:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<false/>
	</dict>
</dict>
</plist>
```

- [ ] **Step 6: Crear la app mínima**

Crear `PrototipoApp/App/OFraudeApp.swift`:

```swift
//
//  OFraudeApp.swift
//  PrototipoApp
//
//  Reemplaza: AppDelegate.swift + SceneDelegate.swift + el storyboard principal (Main.storyboard).
//  En SwiftUI el punto de entrada es un `App` con `@main`.
//

import SwiftUI

@main
struct OFraudeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("OFraude")
        }
    }
}
```

- [ ] **Step 7: Compilar y correr**

Ejecutar la Receta BUILD. Esperado: `** BUILD SUCCEEDED **`. Si falla con "no such scheme", ejecutar `xcodebuild -project PrototipoApp.xcodeproj -list` dentro de `PrototipoApp-SwiftUI` y usar el nombre de scheme que aparezca en la Receta.

Después la Receta RUN con `SHOT=t1`. Esperado: el simulador abre "OFraude SwiftUI" y muestra el texto "OFraude".

- [ ] **Step 8: Confirmar que el original sigue intacto**

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp" && git status --short && ls PrototipoApp/Controllers | wc -l
```

Esperado: `git status` sin salida y 16 controllers.

---

### Task 2: Tema y componentes compartidos

**Files:**
- Create: `PrototipoApp/Theme/Theme.swift`
- Create: `PrototipoApp/Theme/Components.swift`

**Interfaces:**
- Produces (todo lo usan los tasks siguientes, los nombres son exactos):
  - `Color(r:g:b:a:)`, `Theme.background/card/field/selected/border/avatarBackground/accent/danger/dangerText/info/success/textPrimary/textLight/textMuted/textSlate/textSection/textSubtle/defaultBorder`
  - `Text.ofraude(_ size: CGFloat, _ weight: Font.Weight = .regular, color: Color) -> Text`
  - `Symbol(_ name: String, size: CGFloat, color: Color)`
  - `FieldLabel(_ text: String)`
  - `OfraudeTextField(placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default)`
  - `LabeledTextField(label:placeholder:text:keyboard:)`
  - `OfraudeButtonStyle(background:foreground:size:weight:radius:height:fullWidth:)`
  - `Hairline(color: Color = Theme.border)`
  - `TopBar(background:titleSize:titleColor:trailing:)`
  - `View.ofraudeCard(radius:borderWidth:fill:)`, `View.ofraudeScreen()`, `View.hideKeyboardOnTap()`

- [ ] **Step 1: Crear `Theme/Theme.swift`**

```swift
//
//  Theme.swift
//  PrototipoApp
//
//  Todos los colores de OFraude en un solo lugar. En el original estaban repetidos en el
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

    /// En UIKit un borde sin color se dibuja negro. El storyboard nunca les asigna color a los
    /// bordes de las tarjetas, así que se conserva igual que el original.
    static let defaultBorder = Color.black
}
```

- [ ] **Step 2: Crear `Theme/Components.swift`**

```swift
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

extension Text {
    /// Tamaño, peso y color en una sola llamada: los mismos tres datos que muestra el
    /// storyboard para cada label.
    func ofraude(_ size: CGFloat, _ weight: Font.Weight = .regular, color: Color) -> Text {
        font(.system(size: size, weight: weight)).foregroundStyle(color)
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

/// Campo de texto con el estilo de OFraude (antes `applyOfraudeStyle()`): fondo, borde de 1 pt,
/// radio 8, alto 48, texto de 15 pt, cursor naranja y 13 pt de margen a la izquierda.
struct OfraudeTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.textMuted))
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .font(.system(size: 15))
            .foregroundStyle(Theme.textLight)
            .tint(Theme.accent)
            .padding(.horizontal, 13)
            .frame(height: 48)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Etiqueta naranja + campo, con 8 pt entre ambos (el stackView vertical del storyboard).
struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(label)
            OfraudeTextField(placeholder: placeholder, text: $text, keyboard: keyboard)
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
            .font(.system(size: size, weight: weight))
            .foregroundStyle(foreground)
            .padding(.horizontal, fullWidth ? 0 : 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(background, in: RoundedRectangle(cornerRadius: radius))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Layout

/// Línea divisoria de 1 pt.
struct Hairline: View {
    var color: Color = Theme.border

    var body: some View {
        color.frame(height: 1)
    }
}

/// Barra superior hecha a mano (64 pt, título "0FRAUDE" centrado, ícono a la derecha) de
/// Inicio, Buscar y Perfil. Esas pantallas ocultan la barra de navegación del sistema.
struct TopBar<Trailing: View>: View {
    var background: Color
    var titleSize: CGFloat = 20
    var titleColor: Color = Theme.textPrimary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text("0FRAUDE").ofraude(titleSize, .bold, color: titleColor)
            HStack {
                Spacer()
                trailing.frame(width: 24, height: 24)
            }
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(background)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

extension View {
    /// Fondo azul marino de todas las pantallas (el `backgroundColor` de la vista raíz).
    func ofraudeScreen() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// Cierra el teclado al tocar fuera de un campo. Es un gesto simultáneo para no bloquear
    /// los botones (equivale a `cancelsTouchesInView = false` del original).
    func hideKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
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
```

- [ ] **Step 3: Compilar**

Receta BUILD. Esperado: `** BUILD SUCCEEDED **`. (Aún no se usa nada; solo comprueba que compila. Si `@ViewBuilder var trailing` no genera el inicializador esperado, escribir el `init` explícito en `TopBar`.)

---

### Task 3: Estado, rutas y estructura de la app (con prueba de `AppState`)

**Files:**
- Create: `PrototipoApp/App/AppState.swift`
- Create: `PrototipoApp/Views/Route+Destination.swift`
- Create: `PrototipoApp/Views/Tabs/MainTabView.swift`
- Create (temporales, luego se sobrescriben en tasks 4 a 10): un archivo por vista, con un `Text` como marcador
- Modify: `PrototipoApp/App/OFraudeApp.swift`
- Test (fuera del proyecto): `$TMPDIR/appstate_check/main.swift`

**Interfaces:**
- Produces:
  - `enum AppTab: Hashable { case home, search, report, profile }`
  - `enum ProfileSegment { case misReportes, guardados }`
  - `enum Route: Hashable { case reportDetail, settings, editProfile, privacy, changePassword, signOut, guide, article, stats, report, reportSuccess }`
  - `@Observable final class AppState` con `isLoggedIn`, `selectedTab`, `searchQuery`, `profileSegment`, `homePath`, `searchPath`, `reportPath`, `profilePath` (todos `[Route]`), `push(_:)`, `popToTabs(selecting:)`, `logOut()`
  - `Route.destination` (vista) y `TabStack(path:root:)`

- [ ] **Step 1: Escribir la prueba que falla**

```bash
mkdir -p "$TMPDIR/appstate_check" && cat > "$TMPDIR/appstate_check/main.swift" <<'EOF'
import Foundation

func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); exit(1) }
}

// push agrega a la pila de la pestaña activa y a ninguna otra
let s = AppState()
s.isLoggedIn = true
s.selectedTab = .search
s.push(.reportDetail)
check(s.searchPath == [.reportDetail], "push debe agregar a la pila de la pestaña activa")
check(s.homePath.isEmpty && s.reportPath.isEmpty && s.profilePath.isEmpty, "push no debe tocar otras pilas")

// Continuar en ReportSuccess desde una pila profunda: Inicio > Detalle > Yo también > Reportar > Éxito
let deep = AppState()
deep.selectedTab = .home
deep.push(.reportDetail)
deep.push(.report)
deep.push(.reportSuccess)
deep.searchPath = [.reportDetail]
deep.popToTabs(selecting: .home)
check(deep.homePath.isEmpty && deep.searchPath.isEmpty && deep.reportPath.isEmpty && deep.profilePath.isEmpty,
      "popToTabs debe vaciar todas las pilas")
check(deep.selectedTab == .home, "popToTabs debe seleccionar la pestaña pedida")

// Ajustes > Reportes guardados: abre Perfil en el segmento Guardados
let saved = AppState()
saved.selectedTab = .profile
saved.push(.settings)
saved.profileSegment = .guardados
saved.popToTabs(selecting: .profile)
check(saved.profilePath.isEmpty && saved.selectedTab == .profile && saved.profileSegment == .guardados,
      "popToTabs no debe reiniciar el segmento de Perfil")

// Cerrar sesión deja todo como al abrir la app
let out = AppState()
out.isLoggedIn = true
out.selectedTab = .report
out.searchQuery = "Ofertas Falsas"
out.profileSegment = .guardados
out.push(.reportSuccess)
out.logOut()
check(!out.isLoggedIn, "logOut debe cerrar la sesión")
check(out.selectedTab == .home, "logOut debe volver a Inicio")
check(out.searchQuery.isEmpty, "logOut debe limpiar la búsqueda precargada")
check(out.profileSegment == .misReportes, "logOut debe volver a Mis reportes")
check(out.homePath.isEmpty && out.searchPath.isEmpty && out.reportPath.isEmpty && out.profilePath.isEmpty,
      "logOut debe vaciar todas las pilas")

print("OK")
EOF
cd "$TMPDIR/appstate_check" && xcrun swiftc "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI/PrototipoApp/App/AppState.swift" main.swift -o check 2>&1 | head -5
```

Esperado: falla al compilar porque `AppState.swift` no existe (`error: no such file` o `cannot find 'AppState' in scope`).

- [ ] **Step 2: Implementar `App/AppState.swift`**

```swift
//
//  AppState.swift
//  PrototipoApp
//
//  Estado compartido de la app. En el original, los saltos entre pestañas se hacían buscando
//  controllers dentro del tab bar (`selectedIndex`, `presetQuery`, `showGuardados()`); en SwiftUI
//  basta con cambiar un valor aquí. No importa SwiftUI a propósito, para poder probarlo solo.
//

import Observation

enum AppTab: Hashable {
    case home, search, report, profile
}

enum ProfileSegment {
    case misReportes, guardados
}

/// Pantallas a las que se llega con un segue "show" en el storyboard.
enum Route: Hashable {
    case reportDetail, settings, editProfile, privacy, changePassword, signOut
    case guide, article, stats, report, reportSuccess
}

@Observable
final class AppState {
    var isLoggedIn = false
    var selectedTab: AppTab = .home

    /// Texto que Inicio le deja a Buscar (antes `presetQuery`). Buscar lo consume y lo vacía.
    var searchQuery = ""

    /// Segmento de Perfil (antes `showGuardados()`).
    var profileSegment: ProfileSegment = .misReportes

    /// Una pila de navegación por pestaña. Guardarlas aquí permite volver a la raíz desde
    /// cualquier pantalla (antes `popToViewController(tabBarController)`).
    var homePath: [Route] = []
    var searchPath: [Route] = []
    var reportPath: [Route] = []
    var profilePath: [Route] = []

    /// Empuja una pantalla en la pila de la pestaña que está a la vista.
    func push(_ route: Route) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .search: searchPath.append(route)
        case .report: reportPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    /// Vuelve a la raíz de todas las pestañas y selecciona una.
    func popToTabs(selecting tab: AppTab) {
        homePath = []
        searchPath = []
        reportPath = []
        profilePath = []
        selectedTab = tab
    }

    /// Deja todo como al abrir la app. Con `isLoggedIn` en falso, la raíz vuelve a Registro.
    func logOut() {
        popToTabs(selecting: .home)
        searchQuery = ""
        profileSegment = .misReportes
        isLoggedIn = false
    }
}
```

- [ ] **Step 3: Correr la prueba**

```bash
cd "$TMPDIR/appstate_check" && xcrun swiftc "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI/PrototipoApp/App/AppState.swift" main.swift -o check && ./check
```

Esperado: `OK`. Si el macro `@Observable` no compila con `swiftc` suelto, agregar `-parse-as-library` no aplica (hay `main.swift`); en ese caso compilar con `xcrun --sdk macosx swiftc -target arm64-apple-macos14.0 …`.

- [ ] **Step 4: Crear los marcadores de las 17 vistas**

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI/PrototipoApp/Views" && \
mkdir -p Auth Tabs Account Reports Learn && \
mk() { printf 'import SwiftUI\n\nstruct %s: View {\n    var body: some View { Text("%s") }\n}\n' "$2" "$2" > "$1/$2.swift"; } && \
mk Auth RegisterView; mk Auth LoginView; \
mk Tabs HomeView; mk Tabs SearchView; mk Tabs ReportView; mk Tabs ProfileView; \
mk Account SettingsView; mk Account EditProfileView; mk Account PrivacyView; mk Account ChangePasswordView; mk Account SignOutView; \
mk Reports ReportDetailView; mk Reports ReportSuccessView; \
mk Learn SecurityGuideView; mk Learn ArticleView; mk Learn CommunityStatsView; \
find . -name "*.swift" | sort
```

Esperado: 16 archivos listados (los 16 de arriba; `MainTabView` y `Route+Destination` se crean a mano).

- [ ] **Step 5: Crear `Views/Route+Destination.swift`**

```swift
//
//  Route+Destination.swift
//  PrototipoApp
//
//  Qué pantalla abre cada `Route`. Reemplaza los segues "show" del storyboard.
//

import SwiftUI

extension Route {
    @ViewBuilder var destination: some View {
        switch self {
        case .reportDetail: ReportDetailView()
        case .settings: SettingsView()
        case .editProfile: EditProfileView()
        case .privacy: PrivacyView()
        case .changePassword: ChangePasswordView()
        case .signOut: SignOutView()
        case .guide: SecurityGuideView()
        case .article: ArticleView()
        case .stats: CommunityStatsView()
        case .report: ReportView()
        case .reportSuccess: ReportSuccessView()
        }
    }
}
```

- [ ] **Step 6: Crear `Views/Tabs/MainTabView.swift`**

```swift
//
//  MainTabView.swift
//  PrototipoApp
//
//  Reemplaza: escena `Nxu-re-6aT` / MainTabBarController (Main.storyboard).
//  Pestañas: Inicio, Buscar, Reportar, Perfil (mismos títulos e íconos que el original).
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            Tab("Inicio", systemImage: "house.fill", value: AppTab.home) {
                TabStack(path: $appState.homePath) { HomeView() }
            }
            Tab("Buscar", systemImage: "magnifyingglass", value: AppTab.search) {
                TabStack(path: $appState.searchPath) { SearchView() }
            }
            Tab("Reportar", systemImage: "megaphone.fill", value: AppTab.report) {
                TabStack(path: $appState.reportPath) { ReportView() }
            }
            Tab("Perfil", systemImage: "person.fill", value: AppTab.profile) {
                TabStack(path: $appState.profilePath) { ProfileView() }
            }
        }
    }
}

/// Un `NavigationStack` por pestaña. Las pantallas empujadas ocultan el tab bar: en el original
/// se empujaban sobre el navigation controller que contiene al tab bar y lo cubrían por completo.
struct TabStack<Root: View>: View {
    @Binding var path: [Route]
    let root: Root

    init(path: Binding<[Route]>, @ViewBuilder root: () -> Root) {
        _path = path
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: $path) {
            root.navigationDestination(for: Route.self) { route in
                route.destination.toolbar(.hidden, for: .tabBar)
            }
        }
    }
}
```

- [ ] **Step 7: Reescribir `App/OFraudeApp.swift`**

```swift
//
//  OFraudeApp.swift
//  PrototipoApp
//
//  Reemplaza: AppDelegate.swift + SceneDelegate.swift + el storyboard principal (Main.storyboard).
//  En SwiftUI el punto de entrada es un `App` con `@main`.
//

import SwiftUI

@main
struct OFraudeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}

/// Con sesión iniciada muestra las pestañas; sin sesión, Registro → Login. Al cerrar sesión la
/// raíz cambia y `AuthFlow` se crea de nuevo desde Registro (antes `popToRootViewController`).
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.isLoggedIn {
            MainTabView()
        } else {
            AuthFlow()
        }
    }
}

/// Escena `nav-scene` del storyboard: navigation controller con Registro como raíz.
struct AuthFlow: View {
    var body: some View {
        NavigationStack {
            RegisterView()
        }
    }
}
```

- [ ] **Step 8: Compilar**

Receta BUILD. Esperado: `** BUILD SUCCEEDED **`.

---

### Task 4: Registro y Login

**Files:**
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Auth/RegisterView.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Auth/LoginView.swift`

**Interfaces:**
- Consumes: `LabeledTextField`, `OfraudeButtonStyle`, `Text.ofraude`, `Theme`, `ofraudeScreen()`, `hideKeyboardOnTap()`, `AppState.isLoggedIn`.
- Produces: `RegisterView()`, `LoginView()`.

Datos del storyboard: Registro (`reg-vc`): márgenes 28 en horizontal y 26 arriba, separación 18, barra de navegación visible y vacía. Login (`login-vc`): márgenes 28 y 90 arriba, separación 20, barra oculta.

- [ ] **Step 1: Sobrescribir `RegisterView.swift`**

```swift
//
//  RegisterView.swift
//  PrototipoApp
//
//  Reemplaza: escena `reg-vc` / RegisterViewController. Es la pantalla de arranque.
//

import SwiftUI

struct RegisterView: View {
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Únete a la comunidad y ayuda a prevenir fraudes.")
                    .ofraude(14, color: Theme.textMuted)

                LabeledTextField(label: "NOMBRE DE USUARIO", placeholder: "usuario_01", text: $username)
                LabeledTextField(label: "CORREO ELECTRÓNICO", placeholder: "tucorreo@ejemplo.com",
                                 text: $email, keyboard: .emailAddress)
                LabeledTextField(label: "CONTRASEÑA", placeholder: "••••••••", text: $password)
                LabeledTextField(label: "CONFIRMAR CONTRASEÑA", placeholder: "••••••••", text: $confirmPassword)

                // Igual que el original: crear la cuenta no hace nada (era un TODO), solo navega a Login.
                NavigationLink {
                    LoginView()
                } label: {
                    Text("CREAR CUENTA")
                }
                .buttonStyle(OfraudeButtonStyle())

                NavigationLink {
                    LoginView()
                } label: {
                    Text("¿Ya tienes cuenta? Inicia sesión")
                        .ofraude(14, color: Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { RegisterView() }
        .environment(AppState())
}
```

- [ ] **Step 2: Sobrescribir `LoginView.swift`**

```swift
//
//  LoginView.swift
//  PrototipoApp
//
//  Reemplaza: escena `login-vc` / LoginViewController (archivo ViewController.swift).
//  Las credenciales de demo son las del original: admin / admin.
//

import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showError = false

    private let demoEmail = "admin"
    private let demoPassword = "admin"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("0FRAUDE").ofraude(28, .bold, color: Theme.accent)
                Text("Bienvenido de nuevo").ofraude(22, .bold, color: Theme.textLight)
                Text("Inicia sesión para seguir protegiendo a tu comunidad.")
                    .ofraude(14, color: Theme.textMuted)

                VStack(alignment: .leading, spacing: 18) {
                    LabeledTextField(label: "CORREO ELECTRÓNICO", placeholder: "tucorreo@ejemplo.com",
                                     text: $email, keyboard: .emailAddress)
                    LabeledTextField(label: "CONTRASEÑA", placeholder: "••••••••", text: $password)
                }

                if showError {
                    Text("Credenciales inválidas").ofraude(13, .medium, color: Theme.danger)
                }

                Button("INICIAR SESIÓN", action: submit)
                    .buttonStyle(OfraudeButtonStyle())

                Button {
                    dismiss()
                } label: {
                    Text("¿No tienes cuenta? Crear cuenta")
                        .ofraude(14, color: Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 90)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func submit() {
        let isCorrect = email == demoEmail && password == demoPassword
        showError = !isCorrect
        if isCorrect { appState.isLoggedIn = true }
    }
}

#Preview {
    NavigationStack { LoginView() }
        .environment(AppState())
}
```

- [ ] **Step 3: Compilar y revisar**

Receta BUILD → `** BUILD SUCCEEDED **`. Receta RUN con `SHOT=t4`; abrir el PNG. Esperado: Registro sobre fondo azul marino, título gris pequeño, 4 campos con etiqueta naranja, botón naranja "CREAR CUENTA" y enlace gris.

---

### Task 5: Inicio y Buscar

**Files:**
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Tabs/HomeView.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Tabs/SearchView.swift`

**Interfaces:**
- Consumes: `TopBar`, `Hairline`, `Symbol`, `ofraudeCard`, `OfraudeButtonStyle`, `OfraudeTextField`, `AppState.selectedTab/searchQuery`, `Route` (`.reportDetail`, `.guide`, `.stats`).
- Produces: `HomeView()`, `SearchView()`.

Datos del storyboard: ambas ocultan la barra de navegación. Inicio: barra superior con fondo `Theme.background`; contenido con márgenes 16, 20 arriba, separación 24. Buscar: barra con fondo `Theme.card`; márgenes 16, 24 arriba.

- [ ] **Step 1: Sobrescribir `HomeView.swift`**

```swift
//
//  HomeView.swift
//  PrototipoApp
//
//  Reemplaza: escena `home-vc` / HomeViewController.
//  Las tres categorías abren Buscar con un texto precargado (antes `openSearchTab(withQuery:)`)
//  y el botón naranja abre la pestaña Reportar (antes `selectedIndex = 2`).
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            TopBar(background: Theme.background) {
                Symbol("checkmark.seal.fill", size: 24, color: Theme.accent)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    welcomeRow
                    reportBanner
                    Hairline()

                    Text("CATEGORÍAS COMUNES").ofraude(18, .bold, color: Theme.textPrimary)
                    HStack(spacing: 16) {
                        categoryCard("OFERTAS FALSAS", "Descuentos y liquidaciones falsas",
                                     query: "Ofertas Falsas", height: 90)
                        categoryCard("SORTEOS FALSOS", "Premios y regalos que no existen",
                                     query: "Sorteos Falsos", height: 90)
                    }
                    categoryCard("TIENDAS CLONADAS", "Sitios que imitan marcas reales", query: "Tiendas Clonadas")

                    Hairline(color: Theme.danger)
                    Text("ALERTAS CRÍTICAS").ofraude(18, .bold, color: Theme.danger)
                    alertCard("Falsa liquidación de tienda de electrónica",
                              "Sitio clonado ofrece laptops y celulares a 80% de descuento y no entrega nada.",
                              "Hace 2 horas · VER DETALLES ›")
                    alertCard("Sorteo falso de iPhone 17 en Instagram",
                              "Cuentas falsas piden tus datos para 'reclamar' un premio que no existe.",
                              "Hace 5 horas · VER DETALLES ›")

                    linkCard("RECURSOS Y CONSEJOS",
                             "Aprende a identificar las señales de un fraude antes de que ocurra.",
                             button: "CONSULTAR GUÍA", route: .guide)
                    linkCard("ESTADÍSTICAS DE LA COMUNIDAD",
                             "El impacto colectivo de 0Fraude en números.",
                             button: "VER ESTADÍSTICAS", route: .stats)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .ofraudeScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var welcomeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bienvenido, Usuario.").ofraude(20, .bold, color: Theme.textPrimary)
                Text("Tu vigilancia mantiene la comunidad segura.").ofraude(16, color: Theme.textSlate)
            }
            Spacer()
            Symbol("person.fill", size: 20, color: .white)
                .frame(width: 48, height: 48)
                .background(Theme.avatarBackground, in: Circle())
        }
    }

    private var reportBanner: some View {
        Button {
            appState.selectedTab = .report
        } label: {
            HStack(spacing: 12) {
                Symbol("megaphone.fill", size: 28, color: Theme.background)
                VStack(alignment: .leading, spacing: 2) {
                    Text("REPORTAR INCIDENTE").ofraude(20, .bold, color: Theme.background)
                    Text("Registra actividad sospechosa inmediatamente.")
                        .ofraude(14, .medium, color: Theme.background.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            .padding(17)
            .frame(maxWidth: .infinity)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func categoryCard(_ title: String, _ subtitle: String, query: String, height: CGFloat? = nil) -> some View {
        Button {
            appState.searchQuery = query
            appState.selectedTab = .search
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).ofraude(15, .semibold, color: Theme.textPrimary)
                Text(subtitle).ofraude(12, color: Theme.textSlate)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height)
            .ofraudeCard(radius: 4)
        }
        .buttonStyle(.plain)
    }

    private func alertCard(_ title: String, _ summary: String, _ footer: String) -> some View {
        NavigationLink(value: Route.reportDetail) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).ofraude(15, .semibold, color: Theme.textPrimary)
                Text(summary).ofraude(14, color: Theme.textSlate)
                Text(footer).ofraude(12, .bold, color: Theme.textSlate)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ofraudeCard(radius: 4)
        }
        .buttonStyle(.plain)
    }

    private func linkCard(_ title: String, _ text: String, button: String, route: Route) -> some View {
        VStack(spacing: 8) {
            Text(title).ofraude(18, .bold, color: Theme.textPrimary)
            Text(text).ofraude(14, color: Theme.textSlate).multilineTextAlignment(.center)
            NavigationLink(value: route) {
                Text(button)
            }
            .buttonStyle(OfraudeButtonStyle(background: Theme.background, foreground: Theme.textPrimary,
                                            size: 14, weight: .semibold, radius: 4, height: 36, fullWidth: false))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.defaultBorder, lineWidth: 1))
        }
        .padding(25)
        .frame(maxWidth: .infinity)
        .ofraudeCard(radius: 4)
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppState())
}
```

- [ ] **Step 2: Sobrescribir `SearchView.swift`**

```swift
//
//  SearchView.swift
//  PrototipoApp
//
//  Reemplaza: escena `search-vc` / SearchViewController.
//  Recibe el texto que dejó Inicio en `AppState.searchQuery` (antes `presetQuery`), lo muestra
//  en el campo y lo vacía para que no reaparezca.
//

import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""

    private let chips = [["#Descuentos", "#TiendaClonada"], ["#SorteoFalso", "#MercadoLibre"]]

    private struct Category {
        let level: String
        let levelColor: Color
        let name: String
        let summary: String
    }

    private let categories = [
        Category(level: "ALTO · 42 reportes", levelColor: Theme.danger, name: "Ofertas Falsas",
                 summary: "Descuentos irreales y liquidaciones que nunca llegan."),
        Category(level: "MEDIO · 18 reportes", levelColor: Theme.accent, name: "Sorteos Falsos",
                 summary: "Concursos y premios falsos que piden tus datos o dinero."),
        Category(level: "ALTO · 94 reportes", levelColor: Theme.danger, name: "Tiendas Clonadas",
                 summary: "Sitios web que imitan marcas conocidas para robar tu pago."),
        Category(level: "BAJO · 7 reportes", levelColor: Theme.info, name: "Marketplace Fraudulento",
                 summary: "Vendedores falsos en redes que cobran y no entregan."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TopBar(background: Theme.card) {
                Symbol("checkmark.seal.fill", size: 24, color: Theme.accent)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Buscar Reportes").ofraude(24, .bold, color: Theme.textPrimary)
                    OfraudeTextField(placeholder: "Ej. WhatsApp, Banco, Phishing...", text: $query)

                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(chips, id: \.self) { row in
                            HStack(spacing: 8) {
                                ForEach(row, id: \.self) { chip in
                                    Text(chip)
                                        .ofraude(12, color: Theme.textPrimary)
                                        .padding(.horizontal, 12)
                                        .frame(height: 28)
                                        .ofraudeCard()
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    Text("CATEGORÍAS PRINCIPALES").ofraude(18, .bold, color: Theme.textPrimary)
                    ForEach(categories, id: \.name) { category in
                        NavigationLink(value: Route.reportDetail) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category.level).ofraude(12, .bold, color: category.levelColor)
                                Text(category.name).ofraude(20, .bold, color: Theme.textPrimary)
                                Text(category.summary).ofraude(14, color: Theme.textSlate)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ofraudeCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: takePresetQuery)
        .onChange(of: appState.searchQuery) { takePresetQuery() }
    }

    private func takePresetQuery() {
        guard !appState.searchQuery.isEmpty else { return }
        query = appState.searchQuery
        appState.searchQuery = ""
    }
}

#Preview {
    NavigationStack { SearchView() }
        .environment(AppState())
}
```

**Nota para el ejecutor:** las dos filas de chips usan separación 24 entre sí (suposición: el storyboard las dejó como hijos del stack principal, que tiene 24, pero las dos filas comparten un contenedor aquí). Task 11 lo confirma contra el original.

- [ ] **Step 3: Compilar y revisar**

Receta BUILD. Para verlas sin pasar por Login, ejecutar una vez y usar el simulador: iniciar sesión con `admin` / `admin` y tocar las pestañas (si no se puede automatizar, se revisa en Task 11). Esperado del build: `** BUILD SUCCEEDED **`.

---

### Task 6: Perfil y Ajustes

**Files:**
- Create: `PrototipoApp/Model/Report.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Tabs/ProfileView.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Account/SettingsView.swift`

**Interfaces:**
- Consumes: `AppState.profileSegment/popToTabs`, `Route.settings/.editProfile/.reportDetail/.signOut/.guide/.privacy`, componentes del Task 2.
- Produces: `struct Report: Identifiable`, `Report.sampleMine`, `Report.sampleSaved`, `ProfileView()`, `SettingsView()`.

- [ ] **Step 1: Crear `Model/Report.swift`**

```swift
//
//  Report.swift
//  PrototipoApp
//
//  Tarjetas de Perfil (Mis reportes y Guardados). Los textos son los mismos que estaban
//  escritos a mano en el storyboard; no hay backend ni persistencia.
//

import SwiftUI

struct Report: Identifiable {
    let id: String
    let header: String
    let headerColor: Color
    let title: String
    let summary: String?
    let footer: String?
}

extension Report {
    static let sampleMine = [
        Report(id: "mine-1", header: "EN REVISIÓN · HOY, 10:42 AM", headerColor: Theme.accent,
               title: "Descuento falso de laptop en tienda clonada",
               summary: "Reporté una tienda que ofrecía una laptop a precio irrisorio y nunca la recibí.",
               footer: nil),
        Report(id: "mine-2", header: "RIESGO MEDIO · AYER, 16:15 PM", headerColor: Theme.accent,
               title: "Oferta falsa 2x1 en boletos de concierto por Instagram",
               summary: "Una cuenta falsa ofrecía boletos 2x1 pidiendo pago por transferencia.",
               footer: "CONFIRMADO · 340 · 12"),
    ]

    static let sampleSaved = [
        Report(id: "saved-1", header: "ALTO · Hace 2 horas", headerColor: Theme.danger,
               title: "Falsa liquidación de tienda de electrónica",
               summary: nil, footer: "CONFIRMADO · 1.2k · 24"),
        Report(id: "saved-2", header: "MEDIO · Hace 1 hora", headerColor: Theme.accent,
               title: "Sorteo falso de iPhone 17 en Instagram",
               summary: nil, footer: "CONFIRMADO · 450 · 8"),
    ]
}
```

- [ ] **Step 2: Sobrescribir `ProfileView.swift`**

```swift
//
//  ProfileView.swift
//  PrototipoApp
//
//  Reemplaza: escena `profile-vc` / ProfileViewController.
//  - Los dos segmentos (Mis reportes / Guardados) usan `AppState.profileSegment`.
//  - El menú Editar / Eliminar / Cancelar es un `confirmationDialog` (antes UIAlertController).
//  - El aro del avatar es un `strokeBorder`: en el storyboard no se podía dar color a
//    `layer.borderColor`, por eso quedó negro por defecto y aquí se conserva negro.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState

    @State private var mine = Report.sampleMine
    @State private var saved = Report.sampleSaved
    @State private var optionsFor: Report?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(background: Theme.card, titleSize: 16, titleColor: .white) {
                NavigationLink(value: Route.settings) {
                    Symbol("gearshape.fill", size: 24, color: .white)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    avatar
                    Text("Usuario").ofraude(28, .bold, color: .white).frame(maxWidth: .infinity)

                    HStack(spacing: 16) {
                        statCard("REPORTES ENVIADOS", "12", labelColor: Theme.textSlate)
                        statCard("PERSONAS AYUDADAS", "4,302", labelColor: Theme.accent)
                    }

                    NavigationLink(value: Route.editProfile) {
                        Text("EDITAR PERFIL")
                    }
                    .buttonStyle(OfraudeButtonStyle(background: Theme.card, size: 15, weight: .semibold,
                                                    radius: 0, height: 48))

                    segments

                    if appState.profileSegment == .misReportes {
                        ForEach(mine) { report in
                            reportCard(report, titleSize: 20, icon: "ellipsis.circle", iconColor: Theme.textSlate) {
                                optionsFor = report
                            }
                        }
                    } else {
                        ForEach(saved) { report in
                            reportCard(report, titleSize: 18, icon: "bookmark.fill", iconColor: Theme.accent) {
                                saved.removeAll { $0.id == report.id }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 20)
            }
        }
        .ofraudeScreen()
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(optionsFor?.title ?? "", isPresented: optionsBinding, titleVisibility: .visible,
                            presenting: optionsFor) { report in
            Button("Editar") { }   // En el original "Editar" tampoco hacía nada.
            Button("Eliminar", role: .destructive) { mine.removeAll { $0.id == report.id } }
            Button("Cancelar", role: .cancel) { }
        }
    }

    private var optionsBinding: Binding<Bool> {
        Binding(get: { optionsFor != nil }, set: { if !$0 { optionsFor = nil } })
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Symbol("person.fill", size: 40, color: .white)
                .frame(width: 128, height: 128)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.defaultBorder, lineWidth: 4))
            Symbol("pencil", size: 16, color: Theme.background)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: Circle())
        }
        .frame(maxWidth: .infinity)
    }

    private func statCard(_ title: String, _ value: String, labelColor: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).ofraude(12, color: labelColor)
            Text(value).ofraude(22, .bold, color: .white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 90)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var segments: some View {
        HStack(spacing: 24) {
            segmentButton("MIS REPORTES", .misReportes)
            segmentButton("GUARDADOS", .guardados)
            Spacer(minLength: 0)
        }
    }

    private func segmentButton(_ title: String, _ segment: ProfileSegment) -> some View {
        Button {
            appState.profileSegment = segment
        } label: {
            Text(title).ofraude(15, .semibold,
                                color: appState.profileSegment == segment ? .white : Theme.textSlate)
        }
        .buttonStyle(.plain)
    }

    /// Tarjeta tocable (abre el detalle) con un botón de 24 pt arriba a la derecha.
    private func reportCard(_ report: Report, titleSize: CGFloat, icon: String, iconColor: Color,
                            action: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: Route.reportDetail) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(report.header).ofraude(12, .bold, color: report.headerColor)
                    Text(report.title).ofraude(titleSize, .semibold, color: .white)
                    if let summary = report.summary {
                        Text(summary).ofraude(16, color: Theme.textSlate)
                    }
                    if let footer = report.footer {
                        Text(footer).ofraude(13, .semibold, color: Theme.accent)
                    }
                }
                .padding(.leading, 21)
                .padding(.trailing, 45)
                .padding(.vertical, 21)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard()
            }
            .buttonStyle(.plain)

            Button(action: action) {
                Symbol(icon, size: 24, color: iconColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 21)
            .padding(.trailing, 21)
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environment(AppState())
}
```

- [ ] **Step 3: Sobrescribir `SettingsView.swift`**

```swift
//
//  SettingsView.swift
//  PrototipoApp
//
//  Reemplaza: escena `settings-vc` / SettingsViewController.
//  "Reportes Guardados" vuelve a Perfil en el segmento Guardados (antes `savedReportsTapped`).
//  Los switches arrancan como en el storyboard: Notificaciones apagado, Modo Oscuro encendido.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var notifications = false
    @State private var darkMode = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("CUENTA") {
                    NavigationLink(value: Route.editProfile) { rowLabel("Editar Perfil", height: 47) }
                        .buttonStyle(.plain)
                    Hairline()
                    NavigationLink(value: Route.privacy) { rowLabel("Seguridad y Privacidad", height: 46) }
                        .buttonStyle(.plain)
                }

                section("PREFERENCIAS") {
                    toggleRow("Notificaciones", isOn: $notifications)
                    Hairline()
                    toggleRow("Modo Oscuro", isOn: $darkMode)
                    Hairline()
                    HStack {
                        Text("Idioma").ofraude(16, color: .white)
                        Spacer()
                        Text("Español").ofraude(14, color: Theme.textSection)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 47)
                }

                section("COMUNIDAD") {
                    Button {
                        appState.profileSegment = .guardados
                        appState.popToTabs(selecting: .profile)
                    } label: {
                        rowLabel("Reportes Guardados  (12)", height: 47)
                    }
                    .buttonStyle(.plain)
                    Hairline()
                    NavigationLink(value: Route.guide) { rowLabel("Guía de Seguridad", height: 46) }
                        .buttonStyle(.plain)
                }

                NavigationLink(value: Route.signOut) {
                    Text("CERRAR SESIÓN")
                }
                .buttonStyle(OfraudeButtonStyle(background: Theme.card, foreground: Theme.dangerText,
                                                size: 15, weight: .semibold, radius: 16, height: 52))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).ofraude(13, color: Theme.textSection)
            VStack(spacing: 0) { content() }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func rowLabel(_ title: String, height: CGFloat) -> some View {
        Text(title)
            .ofraude(16, color: .white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .contentShape(Rectangle())
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).ofraude(16, color: .white)
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .frame(height: 47)
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppState())
}
```

- [ ] **Step 4: Compilar**

Receta BUILD. Esperado: `** BUILD SUCCEEDED **`.

---

### Task 7: Editar perfil, Privacidad, Cambiar contraseña y Cerrar sesión

**Files:**
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Account/EditProfileView.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Account/PrivacyView.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Account/ChangePasswordView.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Account/SignOutView.swift`

**Interfaces:**
- Consumes: componentes del Task 2, `AppState.logOut()`, `Route.changePassword`.
- Produces: `EditProfileView()`, `PrivacyView()`, `ChangePasswordView()`, `SignOutView()`.

- [ ] **Step 1: Sobrescribir `EditProfileView.swift`**

```swift
//
//  EditProfileView.swift
//  PrototipoApp
//
//  Reemplaza: escena `editprofile-vc` / EditProfileViewController.
//  "Guardar cambios" solo regresa a la pantalla anterior, igual que el original.
//

import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var username = "usuario_01"
    @State private var email = "contacto@secure.com"
    @State private var bio = "Breve descripción de tus áreas de investigación..."

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Symbol("person.fill", size: 40, color: .white)
                    .frame(width: 128, height: 128)
                    .background(Theme.avatarBackground, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.defaultBorder, lineWidth: 4))

                Text("Cambiar Avatar").ofraude(15, color: Theme.accent)

                LabeledTextField(label: "NOMBRE DE USUARIO", placeholder: "", text: $username)
                LabeledTextField(label: "CORREO ELECTRÓNICO (PRIVADO)", placeholder: "", text: $email,
                                 keyboard: .emailAddress)

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("BIOGRAFÍA / ESPECIALIDAD")
                    TextEditor(text: $bio)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSlate)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(height: 120)
                        .ofraudeCard()
                }

                Button("GUARDAR CAMBIOS") { dismiss() }
                    .buttonStyle(OfraudeButtonStyle(size: 15, weight: .semibold, radius: 4))
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { EditProfileView() }
        .environment(AppState())
}
```

- [ ] **Step 2: Sobrescribir `PrivacyView.swift`**

```swift
//
//  PrivacyView.swift
//  PrototipoApp
//
//  Reemplaza: escena `privacy-vc` / PrivacyViewController.
//  Estado inicial de los switches (storyboard): 2 pasos encendido, Perfil Público apagado,
//  Analíticas Anónimas encendido. Las tarjetas tienen borde de 2 pt.
//

import SwiftUI

struct PrivacyView: View {
    @State private var twoStep = true
    @State private var publicProfile = false
    @State private var analytics = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                section("SEGURIDAD") {
                    NavigationLink(value: Route.changePassword) {
                        Text("CAMBIAR CONTRASEÑA")
                            .ofraude(15, .semibold, color: Theme.textLight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline()
                    toggleRow("Autenticación en 2 pasos", "Capa extra de protección", isOn: $twoStep)
                }

                section("PRIVACIDAD") {
                    toggleRow("Perfil Público", "Hacer visible mi historial", isOn: $publicProfile)
                    Hairline()
                    toggleRow("Analíticas Anónimas", "Ayudar a mejorar la plataforma", isOn: $analytics)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).ofraude(18, .bold, color: Theme.accent)
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard(borderWidth: 2)
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).ofraude(14, .semibold, color: Theme.textLight)
                Text(subtitle).ofraude(13, color: Theme.textSubtle)
            }
        }
        .tint(Theme.accent)
    }
}

#Preview {
    NavigationStack { PrivacyView() }
        .environment(AppState())
}
```

- [ ] **Step 3: Sobrescribir `ChangePasswordView.swift`**

```swift
//
//  ChangePasswordView.swift
//  PrototipoApp
//
//  Reemplaza: escena `changepw-vc` / ChangePasswordViewController.
//  "Guardar contraseña" solo regresa (no cambia nada), igual que el original.
//

import SwiftUI

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Actualiza tu clave de acceso para mantener tu cuenta segura.")
                    .ofraude(14, color: Theme.textMuted)

                LabeledTextField(label: "CONTRASEÑA ACTUAL", placeholder: "••••••••", text: $current)
                LabeledTextField(label: "NUEVA CONTRASEÑA", placeholder: "••••••••", text: $new)
                LabeledTextField(label: "CONFIRMAR NUEVA CONTRASEÑA", placeholder: "••••••••", text: $confirm)

                Button("GUARDAR CONTRASEÑA") { dismiss() }
                    .buttonStyle(OfraudeButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { ChangePasswordView() }
        .environment(AppState())
}
```

- [ ] **Step 4: Sobrescribir `SignOutView.swift`**

```swift
//
//  SignOutView.swift
//  PrototipoApp
//
//  Reemplaza: escena `signout-vc` / SignOutViewController.
//  "Cerrar sesión" vuelve a Registro (antes `popToRootViewController`); "Cancelar" regresa.
//

import SwiftUI

struct SignOutView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Symbol("rectangle.portrait.and.arrow.right", size: 28, color: Theme.danger)
                .frame(width: 56, height: 56)
                .background(Theme.danger.opacity(0.2), in: Circle())

            Text("¿Cerrar sesión?").ofraude(22, .bold, color: Theme.textLight)
            Text("Tendrás que iniciar sesión de nuevo para volver a acceder a tu cuenta.")
                .ofraude(14, color: Theme.textMuted)
                .multilineTextAlignment(.center)

            Button("CERRAR SESIÓN") { appState.logOut() }
                .buttonStyle(OfraudeButtonStyle(background: Theme.danger))

            Button("CANCELAR") { dismiss() }
                .buttonStyle(OfraudeButtonStyle(background: .clear, foreground: Theme.textLight))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.defaultBorder, lineWidth: 1))
        }
        .padding(.horizontal, 32)
        .padding(.top, 64)
        .frame(maxHeight: .infinity, alignment: .top)
        .ofraudeScreen()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { SignOutView() }
        .environment(AppState())
}
```

- [ ] **Step 5: Compilar**

Receta BUILD. Esperado: `** BUILD SUCCEEDED **`.

---

### Task 8: Detalle de reporte y Reporte enviado

**Files:**
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Reports/ReportDetailView.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Reports/ReportSuccessView.swift`

**Interfaces:**
- Consumes: `AppState.push(.report)`, `AppState.popToTabs(selecting:)`, componentes del Task 2.
- Produces: `ReportDetailView()`, `ReportSuccessView()`.

El detalle del original es **estático**: siempre muestra este mismo contenido, sin importar qué tarjeta se tocó. Se conserva así.

- [ ] **Step 1: Sobrescribir `ReportDetailView.swift`**

```swift
//
//  ReportDetailView.swift
//  PrototipoApp
//
//  Reemplaza: escena `reportdetail-vc` / ReportDetailViewController.
//  El contenido es fijo (igual que el original). Guardar, compartir y publicar comentario eran
//  TODO y siguen sin hacer nada. "Yo también" abre Reportar (segue `reportdetail-metoo`).
//

import SwiftUI

struct ReportDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var comment = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Text("Alerta: Falsa liquidación de tienda de electrónica con 80% de descuento")
                    .ofraude(28, .bold, color: .white)

                reporter

                Text("Una tienda online clonada está ofreciendo laptops y celulares con descuentos de hasta el 80%. Los usuarios pagan pero nunca reciben el producto, y el sitio desaparece días después.")
                    .ofraude(16, color: .white)

                Text("Modus Operandi").ofraude(24, .bold, color: .white)
                VStack(alignment: .leading, spacing: 16) {
                    Text("1. El Anuncio: ves publicidad en redes con precios absurdamente bajos y 'solo por hoy'.")
                    Text("2. El Sitio Clonado: el link lleva a una página que imita a una tienda real, casi idéntica.")
                    Text("3. Pago sin Entrega: después de pagar, el sitio deja de responder y el producto nunca llega.")
                }
                .font(.system(size: 16))
                .foregroundStyle(.white)

                meTooCard
                commentRow
                Hairline()

                Text("Comentarios de la comunidad (42)").ofraude(20, .bold, color: .white)
                commentCard("Usuario · hace 15 min",
                            "Casi compro ahí, los precios se veían muy reales. Por suerte busqué reseñas antes.")
                commentCard("Usuario · hace 1 hora",
                            "A mi papá casi le cae, vio el anuncio en Facebook y ya iba a pagar.")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Oferta Falsa")
                .ofraude(12, color: .white.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            Text("SEVERIDAD ALTA")
                .ofraude(12, .semibold, color: Theme.danger)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Theme.danger.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            Spacer()
            Button { } label: { Symbol("bookmark", size: 24, color: .white) }   // TODO original: guardar
            Button { } label: { Symbol("square.and.arrow.up", size: 24, color: .white) }   // TODO original: compartir
        }
        .buttonStyle(.plain)
    }

    private var reporter: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reportado por Usuario").ofraude(14, .semibold, color: .white)
                Text("hace 2 horas · CDMX").ofraude(12, color: .white)
            }
        }
    }

    private var meTooCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("¿Has recibido esto?").ofraude(16, .bold, color: .white)
                Text("Ayuda a alertar a otros.").ofraude(14, color: .white)
            }
            Spacer(minLength: 0)
            Button("Yo también") { appState.push(.report) }
                .buttonStyle(OfraudeButtonStyle(foreground: Theme.background, size: 14, weight: .bold,
                                                radius: 4, height: 40, fullWidth: false))
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8)
    }

    private var commentRow: some View {
        HStack(spacing: 8) {
            OfraudeTextField(placeholder: "Escribe un comentario...", text: $comment)
            Button { } label: {   // TODO original: publicar comentario
                Symbol("arrow.up", size: 20, color: .white)
                    .frame(width: 56, height: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private func commentCard(_ author: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(author).ofraude(13, .bold, color: .white)
            Text(text).ofraude(14, color: .white)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8)
    }
}

#Preview {
    NavigationStack { ReportDetailView() }
        .environment(AppState())
}
```

- [ ] **Step 2: Sobrescribir `ReportSuccessView.swift`**

```swift
//
//  ReportSuccessView.swift
//  PrototipoApp
//
//  Reemplaza: escena `reportsuccess-vc` / ReportSuccessViewController.
//  "Continuar" vuelve a la pestaña Inicio con todas las pilas vacías
//  (antes `selectedIndex = 0` + `popToViewController(tabBarController)`).
//

import SwiftUI

struct ReportSuccessView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 14) {
            Symbol("checkmark.circle.fill", size: 28, color: Theme.success)
                .frame(width: 56, height: 56)
                .background(Theme.success.opacity(0.2), in: Circle())

            Text("¡Reporte enviado con éxito!").ofraude(22, .bold, color: Theme.textLight)
            Text("Gracias por ayudar a mantener segura a la comunidad. Revisaremos tu reporte lo antes posible.")
                .ofraude(14, color: Theme.textMuted)
                .multilineTextAlignment(.center)

            Button("CONTINUAR") { appState.popToTabs(selecting: .home) }
                .buttonStyle(OfraudeButtonStyle())
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
        .ofraudeScreen()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { ReportSuccessView() }
        .environment(AppState())
}
```

- [ ] **Step 3: Compilar**

Receta BUILD. Esperado: `** BUILD SUCCEEDED **`.

---

### Task 9: Guía de seguridad, Artículo y Estadísticas

**Files:**
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Learn/SecurityGuideView.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Learn/ArticleView.swift`
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Learn/CommunityStatsView.swift`

**Interfaces:**
- Consumes: `Route.article`, componentes del Task 2.
- Produces: `SecurityGuideView()`, `ArticleView()`, `CommunityStatsView()`.

- [ ] **Step 1: Sobrescribir `SecurityGuideView.swift`**

```swift
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
                Text("Tácticas de evasión, identificación de amenazas y protocolos de respuesta ante el fraude digital.")
                    .ofraude(15, color: Theme.textMuted)

                chapter("CAPÍTULO 01", Theme.accent, "Cómo identificar ofertas falsas", titleSize: 24, titleWeight: .bold,
                        "Los estafadores usan descuentos irreales y urgencia fabricada ('solo por hoy') para que compres sin pensar.",
                        "Leer el informe completo ›")
                chapter("CAPÍTULO 02", Theme.accent, "Protegiendo tus contraseñas", titleSize: 20, titleWeight: .semibold,
                        "La reutilización de contraseñas es el vector de ataque más común.",
                        "Ver Protocolo ›")
                chapter("CAPÍTULO 03", Theme.danger, "Qué hacer tras un fraude", titleSize: 20, titleWeight: .semibold,
                        "Acción inmediata: congele activos, reporte a las autoridades y documente la evidencia.",
                        "Manual de respuesta ›")
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chapter(_ label: String, _ labelColor: Color, _ title: String, titleSize: CGFloat,
                         titleWeight: Font.Weight, _ summary: String, _ link: String) -> some View {
        NavigationLink(value: Route.article) {
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
    }
}

#Preview {
    NavigationStack { SecurityGuideView() }
        .environment(AppState())
}
```

- [ ] **Step 2: Sobrescribir `ArticleView.swift`**

```swift
//
//  ArticleView.swift
//  PrototipoApp
//
//  Reemplaza: escena `article-vc` / ArticleViewController. Contenido fijo.
//

import SwiftUI

struct ArticleView: View {
    private let keyPoints = [
        "•  Verifica siempre la fuente por un canal oficial antes de actuar.",
        "•  Nunca compartas contraseñas, códigos 2FA ni datos de tarjeta por mensaje.",
        "•  Desconfía de cualquier mensaje que te presione a decidir \"ahora mismo\".",
        "•  Si algo se siente mal, repórtalo en 0Fraude para alertar a la comunidad.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("MANUAL OPERATIVO").ofraude(12, .medium, color: Theme.accent)
                Text("Cómo protegerte del fraude").ofraude(26, .bold, color: Theme.textLight)
                Text("Los estafadores cambian de táctica constantemente, pero casi siempre buscan generar urgencia, miedo o una oportunidad demasiado buena para dejarla pasar. Reconocer esas señales a tiempo es tu primera línea de defensa.")
                    .ofraude(15, color: Theme.textMuted)

                Text("Puntos clave").ofraude(17, .bold, color: Theme.textLight)
                ForEach(keyPoints, id: \.self) { point in
                    Text(point).ofraude(14, color: Theme.textMuted)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("RECUERDA").ofraude(12, .medium, color: Theme.accent)
                    Text("Ninguna institución legítima te pedirá tu contraseña completa o el código de tu tarjeta por teléfono, SMS o WhatsApp.")
                        .ofraude(14, color: Theme.textLight)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard(radius: 10, fill: Theme.field)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { ArticleView() }
        .environment(AppState())
}
```

- [ ] **Step 3: Sobrescribir `CommunityStatsView.swift`**

```swift
//
//  CommunityStatsView.swift
//  PrototipoApp
//
//  Reemplaza: escena `stats-vc` / CommunityStatsViewController. Cifras fijas.
//

import SwiftUI

struct CommunityStatsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("El impacto colectivo de 0Fraude en números, actualizado en tiempo real.")
                    .ofraude(14, color: Theme.textMuted)

                HStack(spacing: 12) {
                    statCard("4,302", "PERSONAS AYUDADAS")
                    statCard("1,204", "REPORTES VERIFICADOS")
                }
                HStack(spacing: 12) {
                    statCard("892", "ESTAFAS DETENIDAS")
                    statCard("32", "ZONAS CUBIERTAS")
                }

                Text("Cada reporte que envías fortalece esta red. Gracias por mantener alerta a tu comunidad.")
                    .ofraude(13, color: Theme.textMuted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statCard(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).ofraude(26, .bold, color: Theme.accent)
            Text(label).ofraude(11, .medium, color: Theme.textMuted)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 90)
        .ofraudeCard(radius: 10, fill: Theme.field)
    }
}

#Preview {
    NavigationStack { CommunityStatsView() }
        .environment(AppState())
}
```

- [ ] **Step 4: Compilar**

Receta BUILD. Esperado: `** BUILD SUCCEEDED **`.

---

### Task 10: Reportar

**Files:**
- Modify (sobrescribir el marcador): `PrototipoApp/Views/Tabs/ReportView.swift`

**Interfaces:**
- Consumes: `AppState.push(.reportSuccess)`, componentes del Task 2.
- Produces: `ReportView()` (se usa como pestaña y también empujada por "Yo también").

Notas del original que se conservan: los campos de "Datos de la persona afectada" se muestran siempre (no dependen de "A otra persona"); enviar solo navega a Éxito; agregar/quitar evidencia eran TODO. La vista previa de evidencia y el botón de quitar estaban ocultos y sin lógica, así que no se recrean.

- [ ] **Step 1: Sobrescribir `ReportView.swift`**

```swift
//
//  ReportView.swift
//  PrototipoApp
//
//  Reemplaza: escena `report-vc` / ReportViewController.
//  - La selección (borde naranja) de "¿A quién le ocurrió?" y "Tipo de Fraude" es un @State
//    con la opción elegida (antes `select(_:in:)`); arrancan con la primera opción elegida.
//  - El placeholder de "Detalles adicionales" se dibuja encima del TextEditor mientras esté vacío.
//  - Enviar solo abre la pantalla de éxito; agregar evidencia sigue siendo un TODO.
//

import SwiftUI

struct ReportView: View {
    @Environment(AppState.self) private var appState

    @State private var anonymous = false
    @State private var who = "A mí"
    @State private var fraudType = "Oferta Falsa"
    @State private var personName = ""
    @State private var personContact = ""
    @State private var personCity = ""
    @State private var customType = ""
    @State private var url = ""
    @State private var details = ""

    private let whoOptions = ["A mí", "A otra persona"]
    private let fraudRows = [["Oferta Falsa", "Sorteo Falso"], ["Tienda Clonada", "Marketplace"], ["Llamada", "Otro"]]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Emitir Reporte").ofraude(28, .bold, color: .white)
                Text("Ayuda a la comunidad reportando actividades sospechosas o fraudulentas.")
                    .ofraude(16, color: Theme.textMuted)

                anonymousCard

                Text("¿A quién le ocurrió el fraude?").ofraude(18, .semibold, color: .white)
                HStack(spacing: 16) {
                    ForEach(whoOptions, id: \.self) { option in
                        choiceButton(option, isSelected: who == option) { who = option }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("DATOS DE LA PERSONA AFECTADA")
                    OfraudeTextField(placeholder: "Nombre completo", text: $personName)
                    OfraudeTextField(placeholder: "Teléfono o correo de contacto", text: $personContact)
                    OfraudeTextField(placeholder: "Ciudad", text: $personCity)
                }

                Text("Tipo de Fraude").ofraude(18, .semibold, color: .white)
                ForEach(fraudRows, id: \.self) { row in
                    HStack(spacing: 16) {
                        ForEach(row, id: \.self) { option in
                            choiceButton(option, isSelected: fraudType == option) { fraudType = option }
                        }
                    }
                }

                LabeledTextField(label: "(OPCIONAL)", placeholder: "Ej: Fraude piramidal, préstamo falso...",
                                 text: $customType)
                LabeledTextField(label: "URL O TEXTO SOSPECHOSO", placeholder: "Ej: http://sitio-falso.com",
                                 text: $url)

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("DETALLES ADICIONALES")
                    detailsEditor
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("EVIDENCIA (OPCIONAL)")
                    evidenceBox
                }

                Button("ENVIAR REPORTE") { appState.push(.reportSuccess) }
                    .buttonStyle(OfraudeButtonStyle(foreground: Theme.background, size: 15, weight: .bold,
                                                    radius: 4, height: 56))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var anonymousCard: some View {
        Toggle(isOn: $anonymous) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reportar de forma anónima").ofraude(15, .semibold, color: .white)
                Text("Tu nombre no se compartirá con la comunidad.").ofraude(13, color: Theme.textMuted)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .ofraudeCard(radius: 8)
    }

    private func choiceButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .ofraude(14, .bold, color: .white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isSelected ? Theme.selected : Theme.card, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var detailsEditor: some View {
        TextEditor(text: $details)
            .font(.system(size: 16))
            .foregroundStyle(Theme.textLight)
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(height: 120)
            .overlay(alignment: .topLeading) {
                if details.isEmpty {
                    Text("Describe cómo ocurrió el intento de fraude...")
                        .ofraude(16, color: Theme.textMuted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .ofraudeCard()
    }

    private var evidenceBox: some View {
        Button { } label: {   // TODO original: agregar foto de evidencia
            VStack(spacing: 8) {
                Symbol("photo.badge.plus", size: 24, color: Theme.textSlate)
                Text("Agregar foto de evidencia").ofraude(13, color: Theme.textSlate)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .ofraudeCard(radius: 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { ReportView() }
        .environment(AppState())
}
```

- [ ] **Step 2: Compilar**

Receta BUILD. Esperado: `** BUILD SUCCEEDED **`.

---

### Task 11: Comparar contra el original y recorrer los flujos

**Files:**
- Modify: cualquier vista que difiera del original (solo lo que la comparación demuestre distinto).
- Create: `docs/verificacion-2026-09-26.md` (resultados)

- [ ] **Step 1: Comprobar qué herramientas hay para tocar la pantalla del simulador**

```bash
which idb cliclick 2>&1; osascript -e 'tell application "System Events" to get name of every process whose name is "Simulator"' 2>&1 | head -3
```

- Si `System Events` responde sin error de permisos, se pueden simular toques con `osascript` sobre la ventana del Simulator.
- Si no hay forma de tocar la pantalla desde la terminal, **no instalar nada sin preguntarle a Alex**. En ese caso: tomar capturas de las pantallas alcanzables (Registro y Login), y entregarle a Alex la lista de flujos del paso 4 como checklist para que los recorra él en Xcode, indicando en el reporte final qué no se pudo comprobar.

- [ ] **Step 2: Fijar la apariencia del simulador para que ambas apps se comparen igual**

```bash
xcrun simctl ui booted appearance 2>&1
```

Anotar el modo (light/dark). Ambas apps se capturan en el mismo modo. Si el original se ve claro en la barra de navegación y la copia oscura (o al revés), ajustar la copia con `.toolbarColorScheme(...)` / `.preferredColorScheme(...)` hasta que coincida con el original en el mismo modo.

- [ ] **Step 3: Capturas lado a lado**

Compilar e instalar el original (`Tec-CCM.PrototipoApp`) desde `IS Modulo Avril Swift/PrototipoApp` con `xcodebuild -derivedDataPath "$TMPDIR/ofraude-old-dd"`, y la copia con la Receta RUN. Con la misma pantalla en cada una, capturar (`xcrun simctl io booted screenshot`) y abrir ambos PNG con Read. Pantallas: Registro, Login, Inicio, Buscar, Reportar, Perfil (ambos segmentos), Ajustes, Editar perfil, Privacidad, Cambiar contraseña, Cerrar sesión, Detalle, Guía, Artículo, Estadísticas, Éxito. Registrar cada diferencia visible (espaciado, tamaños, colores, textos) y corregirla en la vista correspondiente. Puntos que el plan dejó como suposición y hay que mirar con cuidado: alineación de textos en tarjetas centradas de Inicio, separación de filas de chips en Buscar, posición de la insignia del lápiz en el avatar, alineación de los botones de segmento en Perfil, ancho de los botones de "Yo también" y de las guías.

- [ ] **Step 4: Recorrer los flujos (Review Focus 1 a 6)**

Marcar cada uno como OK, diferencia o no comprobado:

1. Registro → "CREAR CUENTA" abre Login; en Login, "¿No tienes cuenta?" regresa a Registro.
2. Login vacío, `Admin`/`admin`, `admin ` (con espacio): muestra "Credenciales inválidas" y no navega. `admin`/`admin` entra a las pestañas.
3. Inicio → cada categoría abre Buscar con el texto correcto en el campo; volver a Inicio y tocar otra categoría con Buscar ya visitada sustituye el texto; el texto no reaparece al cambiar de pestaña y volver.
4. Inicio → botón naranja abre Reportar.
5. Inicio → alerta / Buscar → categoría / Perfil → tarjeta abren el detalle, **sin tab bar**, y "atrás" regresa.
6. Perfil: segmentos, menú de una tarjeta de Mis reportes (Editar no hace nada, Eliminar la quita, Cancelar cierra), quitar de Guardados.
7. Perfil → engrane → Ajustes → "Reportes Guardados" abre Perfil en Guardados con la pila vacía.
8. Detalle → "Yo también" abre Reportar; ahí, elegir opciones (borde naranja) y "ENVIAR REPORTE" abre Éxito; "CONTINUAR" vuelve a Inicio con todas las pilas vacías (revisar también desde Perfil y desde Buscar).
9. Ajustes → Cerrar sesión → "CANCELAR" regresa; "CERRAR SESIÓN" vuelve a Registro; volver a entrar muestra Inicio limpio (sin búsqueda ni segmento anterior).
10. Teclado: en Registro y Reportar se puede llegar a cada campo y botón con el teclado abierto; tocar fuera cierra el teclado.
11. Texto grande (`xcrun simctl ui booted content_size extra-extra-large`) y horizontal: anotar si algo queda cortado o inalcanzable (el original usa alturas fijas, así que puede fallar igual). Restaurar con `content_size large`.

- [ ] **Step 5: Guardar el resultado**

Escribir `docs/verificacion-2026-09-26.md` con la tabla de pantallas (igual / ajustada / diferencia conocida) y la de flujos (OK / diferencia / no comprobado), sin adornos.

- [ ] **Step 6: Build final**

Receta BUILD. Esperado: `** BUILD SUCCEEDED **` y sin advertencias nuevas (`grep -c "warning:"` debe ser 0 en el resumen de la receta).

---

### Task 12: Documentación final

**Files:**
- Create: `docs/CAMBIOS-vs-original.md`
- Modify: `docs/superpowers/specs/2026-09-26-migracion-swiftui-design.md` (si quedó algo sin actualizar en Task 1 Step 9)

- [ ] **Step 1: Comprobar que cada vista lleva su cabecera y que no quedó UIKit**

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI/PrototipoApp" && \
echo "--- vistas sin 'Reemplaza:' (esperado: ninguna, salvo Components/Theme/AppState/Model)" && \
grep -L "Reemplaza:" $(find Views App -name "*.swift") ; \
echo "--- referencias a UIKit/storyboard (esperado: solo UIApplication/UIKeyboardType/UIResponder en Components.swift)" && \
grep -rn "UIViewController\|UIView\b\|@IBOutlet\|@IBAction\|storyboard" --include=*.swift . ; \
echo "--- textos con marcador que sobran" && grep -rn 'Text("[A-Za-z]*View")' --include=*.swift .
```

Esperado: nada en la primera lista (o solo archivos que no son vistas), nada en la segunda y nada en la tercera. Corregir lo que aparezca.

- [ ] **Step 2: Escribir `docs/CAMBIOS-vs-original.md`**

Contenido: (1) tabla escena → vista (la del spec 4.6, ya real); (2) qué se conservó igual (textos, colores, quirks del punto 7 de "Cambios respecto al spec"); (3) qué cambió y por qué (bundle id, nombre visible, tab bar oculto en pantallas empujadas, flecha "atrás" de Reportar, `AppState`); (4) qué no se pudo comprobar (del Task 11); (5) cómo ajustar el aspecto (`Theme/Theme.swift` para colores, `Theme/Components.swift` para campos/botones). Máximo una página.

- [ ] **Step 3: Build final**

Receta BUILD → `** BUILD SUCCEEDED **`.

---

### Task 13: RF que salen del prototipo

Alex pidió que, al terminar la migración, se identifiquen los requisitos funcionales (RF) que se desprenden del prototipo. No los no funcionales. Es un análisis, no código.

**Files:**
- Lee: el proyecto original (`PrototipoApp/`), la copia SwiftUI, `docs/verificacion-2026-09-26.md`, `database/zeroscam_base_datos.sql`.
- No crea archivos. La salida es un borrador en el chat.

- [ ] **Step 1: Reunir la evidencia del prototipo**

Para cada RF candidato, anotar la pantalla/flujo concreto de donde sale. Recorrer las 17 vistas y sus acciones: Registro, Login (con credenciales fijas), las 4 pestañas, cada segue "show", los segmentos de Perfil, el menú Editar/Eliminar/Cancelar, los dos grupos de selección de Reportar, los switches de Ajustes/Privacidad, y los botones que hoy son `// TODO` (crear cuenta, enviar reporte, evidencia, guardar, compartir, comentar, editar) — estos también son RF, aunque el prototipo no los implemente todavía. Revisar también `database/zeroscam_base_datos.sql` por si expone funciones que la UI del prototipo no muestra (por ejemplo historial de estados o notificaciones).

- [ ] **Step 2: Redactar cada RF**

Uno por función identificada: identificador (RF-01…), enunciado ("El sistema debe permitir…"), actor, y la pantalla/flujo del prototipo que lo origina. Agrupar por módulo (cuenta, reportes, comunidad/exploración, ajustes/perfil) en vez de por pantalla suelta, para no listar 17 RF triviales de "navegar a X".

- [ ] **Step 3: Separar lo implementado de lo pendiente**

Marcar cada RF como **implementado** (el prototipo ya lo hace, aunque sea con datos fijos) o **pendiente** (el botón existe pero es un `// TODO`, o se infiere del modelo de datos sin que haya pantalla). No mezclar ambos sin marcarlos.

- [ ] **Step 4: Presentar el borrador**

Entregar en el chat la tabla completa de RF, sin generar un archivo a menos que Alex lo pida.
