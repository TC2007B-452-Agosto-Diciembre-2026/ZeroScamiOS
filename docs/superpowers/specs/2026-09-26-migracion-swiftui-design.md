# Migración de OFraude (PrototipoApp) de storyboard a SwiftUI

Fecha: 2026-09-26
Estado: aprobado por Alex (2026-09-26). Actualizado al escribir el plan; ver los cambios en las secciones 3, 4.1, 4.3, 4.5 y 8.

## 1. Objetivo

Tener la app iOS **OFraude** funcionando igual que hoy pero construida con SwiftUI en lugar de Storyboard + UIKit. Alex quiere el resultado migrado; yo hago la migración completa y él la revisa. No es una entrega calificada.

Lo que Alex dijo explícitamente:

- Quiere la app ya migrada (no es un ejercicio para escribirlo él).
- Visualmente: "lo mismo pero con algunos ajustes". La base debe ser idéntica a la actual y los ajustes se deciden después de verla corriendo.
- Todo debe quedar en una carpeta distinta. El proyecto original no se toca.
- Por ahora no hay git: sin commits y sin repo nuevo.
- Quiere todo bien documentado.

Suposición mía, pendiente de confirmar al revisar este documento: el objetivo es la misma app con el mismo comportamiento, sin rediseño ni funciones nuevas.

## 2. Contexto del proyecto original

Ubicación: `IS Modulo Avril Swift/PrototipoApp/` (proyecto `PrototipoApp.xcodeproj`, target `PrototipoApp`).

Medido el 2026-09-26:

- `Main.storyboard`: 4,378 líneas, 18 escenas.
- 16 controllers en `Controllers/` (el de login es `ViewController.swift`, que contiene la clase `LoginViewController`) y 2 extensions en `Extensions/`.
- `App/AppDelegate.swift` (tiene `@main`) y `App/SceneDelegate.swift`.
- `Info.plist` con `UISceneStoryboardFile = Main`, ruta fija en build settings (`INFOPLIST_FILE = PrototipoApp/Info.plist`).
- Deployment target iOS 26.5, Swift 5.0, `GENERATE_INFOPLIST_FILE = YES`.
- Carpeta `database/` con el script de ZeroScam (entregable de otra parte del curso, no forma parte de la migración pero viaja en la copia).

Comportamiento actual relevante:

- Arranque en Registro (`nav-root-segue` apunta a `reg-vc`). Registro → Login por segue.
- Login con credenciales de demo `admin` / `admin`. Si son incorrectas muestra un texto de error; si son correctas empuja el `MainTabBarController` sobre el nav stack.
- Tab bar con 4 pestañas: Inicio, Buscar, Reportar, Perfil.
- Saltos entre pestañas por código:
  - Inicio, categorías Ofertas Falsas / Sorteos Falsos / Tiendas Clonadas: abren Buscar (índice 1) con `presetQuery` con ese texto.
  - Inicio, botón de reportar: abre la pestaña Reportar (índice 2).
  - Ajustes, "Reportes guardados": abre Perfil (índice 3) en el segmento Guardados vía `showGuardados()`.
- Segues "show" hacia: ReportDetail (desde Inicio, Buscar y Perfil), SecurityGuide, CommunityStats, Settings, EditProfile, Privacy, ChangePassword, SignOut, Article, Report (desde "Me too" en ReportDetail) y ReportSuccess (desde el envío en Report).
- Perfil tiene dos segmentos (Mis reportes / Guardados). Cada tarjeta de Mis reportes tiene un menú Editar / Eliminar / Cancelar (action sheet); las de Guardados se pueden quitar.
- Reportar: dos grupos de botones de selección única ("¿A quién le ocurrió?" y "Tipo de Fraude") con borde naranja en el elegido, campos de texto, un `UITextView` con placeholder, un switch de anónimo y una zona de evidencia.
- Acciones que hoy son `// TODO` y no hacen nada: crear cuenta, enviar reporte (solo navega a Éxito), agregar/quitar evidencia, "Me too", guardar, compartir y publicar comentario, y Editar en el menú de Perfil.

## 3. Decisiones tomadas

| Tema | Decisión |
|---|---|
| Ubicación | Carpeta nueva `IS Modulo Avril Swift/PrototipoApp-SwiftUI/`, hermana de la original. |
| Cómo se crea | Copia del proyecto original **sin `.git`**. El original queda intacto y sirve de referencia. |
| Enfoque | Migración completa en la copia (no híbrida con `UIHostingController`, no in-place). En la copia se borran storyboard, controllers, extensions de UIKit, `AppDelegate` y `SceneDelegate`. |
| Fidelidad visual | Misma apariencia que hoy como base. Los ajustes se hacen después. |
| Alcance funcional | Mismo comportamiento que hoy. Los `// TODO` siguen siendo botones sin lógica. |
| Git | Ninguno. No se crea repo ni se commitea. |
| Bundle id y nombre | Bundle id `Tec-CCM.PrototipoApp-SwiftUI` y nombre visible "OFraude SwiftUI". Con el mismo bundle id de la original, instalar la copia sobreescribiría a la original en el simulador y no se podrían comparar. (Cambio respecto a la primera versión de este spec.) |
| Modelo | Sonnet 5. Si aparece un bug difícil de navegación o layout, se puede cambiar a Opus con `/model` solo para esa parte. |

## 4. Arquitectura

### 4.1 Estructura de archivos (dentro de `PrototipoApp-SwiftUI/PrototipoApp/`)

```
App/
  OFraudeApp.swift        @main, App de SwiftUI, decide qué mostrar según AppState
  AppState.swift          estado compartido (@Observable)
Theme/
  Theme.swift             colores en un solo lugar
  Components.swift        estilo de campos, botones, tarjetas, barra superior, cierre de teclado
Model/
  Report.swift            modelo de las tarjetas de Perfil (Mis reportes / Guardados)
Views/
  Route+Destination.swift qué pantalla abre cada Route
  Auth/       RegisterView, LoginView
  Tabs/       MainTabView, HomeView, SearchView, ReportView, ProfileView
  Account/    SettingsView, EditProfileView, PrivacyView, ChangePasswordView, SignOutView
  Reports/    ReportDetailView, ReportSuccessView
  Learn/      SecurityGuideView, ArticleView, CommunityStatsView
Assets.xcassets (sin cambios)
Info.plist        (se quita la referencia al storyboard)
```

Una vista por escena del storyboard. Las carpetas dentro de `Views/` son solo organización; Xcode sincroniza la carpeta con el proyecto (`PBXFileSystemSynchronizedRootGroup`, confirmado: aparece 3 veces en el `project.pbxproj`), así que crear archivos en disco basta. Además de editar `Info.plist`, hay que quitar `INFOPLIST_KEY_UIMainStoryboardFile = Main` del `project.pbxproj` (aparece 2 veces). `LaunchScreen.storyboard` se conserva: es la pantalla de lanzamiento, no la interfaz de la app.

### 4.2 Estado compartido: `AppState`

Objeto `@Observable` inyectado en el entorno desde `OFraudeApp`. Guarda:

- `isLoggedIn: Bool`
- `selectedTab: Tab` (`home`, `search`, `report`, `profile`)
- `searchQuery: String` (reemplaza `presetQuery`)
- `profileSegment: ProfileSegment` (`misReportes`, `guardados`; reemplaza `showGuardados()`)

Los saltos entre pestañas de hoy (`selectedIndex`, `presetQuery`, `showGuardados()`) pasan a ser asignaciones sobre este objeto. La razón de que exista es que en UIKit esos saltos buscaban controllers dentro del tab bar; en SwiftUI basta con cambiar un valor.

### 4.3 Navegación

- Raíz de `OFraudeApp`: si `isLoggedIn` es falso, un `NavigationStack` con Registro como raíz y Login empujado desde ahí. Si es verdadero, `MainTabView`.
- `MainTabView` es un `TabView` de 4 pestañas ligado a `selectedTab`. Cada pestaña tiene su propio `NavigationStack` para los segues "show" (`NavigationLink(value:)` + `navigationDestination(for: Route.self)`). Las 4 pilas (`homePath`, `searchPath`, `reportPath`, `profilePath`) viven en `AppState`, para poder vaciarlas todas desde cualquier pantalla.
- **Las pantallas empujadas ocultan el tab bar.** En el original se empujaban sobre el navigation controller que contiene al tab bar y lo cubrían por completo; en SwiftUI se logra con `.toolbar(.hidden, for: .tabBar)` en los destinos.
- El menú Editar / Eliminar / Cancelar de Perfil usa `confirmationDialog`.
- Los segues que hoy cruzan pestañas se conservan: "Yo también" (ReportDetail) abre Reportar, y el envío de Reportar abre ReportSuccess.
- "Continuar" en ReportSuccess (hoy: pestaña 0 + `popToViewController(tabBarController)`) y "Reportes Guardados" en Ajustes (hoy: `showGuardados()` + pestaña 3 + pop) pasan a `AppState.popToTabs(selecting:)`, que vacía las 4 pilas y selecciona la pestaña.

**Cerrar sesión (verificado leyendo `SignOutViewController`):** hoy "CERRAR SESIÓN" hace `popToRootViewController`, es decir, vuelve a Registro (la raíz del stack); "CANCELAR" hace un pop simple. En SwiftUI la raíz cambia según `isLoggedIn` y `AuthFlow` se recrea desde Registro, con el mismo resultado visible. `AppState.logOut()` además deja en su estado inicial la pestaña, la búsqueda precargada, el segmento de Perfil y las pilas.

**Quirk del original que no se replica:** la pestaña Reportar muestra una barra de navegación con flecha "atrás" hacia Login (porque el tab bar está empujado sobre Login y esa pantalla no oculta la barra). En la copia esa barra aparece vacía, sin flecha. Se avisa en `docs/CAMBIOS-vs-original.md`.

### 4.4 Tema y estilos

- `Theme.swift` concentra los colores que hoy están repetidos en el storyboard y en las extensions (por ejemplo, en `UITextField+OfraudeStyle` y `ReportViewController`): fondo azul marino, tarjeta `(18,32,74)`, campo `(15,26,56)`, borde `(42,55,104)`, naranja `(245,166,35)`, texto claro `(219,225,255)`, placeholder `(156,163,175)`, seleccionado `(26,42,90)` y gris azulado de pestaña inactiva. Los valores se verifican contra el storyboard al implementar. Los ajustes visuales futuros se hacen aquí.
- `OfraudeFieldStyle` reemplaza `applyOfraudeStyle()`: mismo fondo, borde de 1 pt, radio 8, texto de 15 pt, cursor naranja, placeholder gris y padding izquierdo de 13 pt.
- El cierre del teclado al tocar fuera (`hideKeyboardOnTap`) se resuelve con `scrollDismissesKeyboard` o un gesto equivalente.

### 4.5 Datos y componentes

- Las tarjetas de Inicio, Buscar, Perfil (Mis reportes) y Perfil (Guardados) tienen contenido y tipografías distintos, así que **no hay una sola `ReportCard`** (el diseño inicial suponía que sí; se corrigió al leer el storyboard completo). Solo Perfil usa un modelo `Report`, porque necesita quitar/eliminar tarjetas. Lo demás queda literal en cada vista, con los mismos textos que tenía el storyboard. No hay `SampleData.swift`. Lo repetido de verdad (tarjeta con borde, campo, botón, barra superior) sí se comparte en `Theme/Components.swift`.
- No hay backend, red ni persistencia nueva.
- El aro del avatar (Perfil y EditProfile) se resuelve con `.overlay(Circle().stroke(...))`. Esto evita la limitación de `layer.borderColor` que se encontró con el storyboard.
- Los íconos siguen siendo los mismos SF Symbols (`Image(systemName:)`).
- La selección en Reportar ("¿A quién le ocurrió?" y "Tipo de Fraude") pasa a `@State` con la opción elegida, con borde naranja en la seleccionada, igual que el `select()` de hoy.
- El placeholder del campo de detalles usa un `TextEditor` con un texto superpuesto mientras esté vacío.
- **Bordes:** en UIKit un borde sin color se dibuja negro, y el storyboard nunca les asigna color a los de las tarjetas. Se conservan negros de 1 pt (`Theme.defaultBorder`); solo los campos de texto y los botones de selección de Reportar usan el azul `(42,55,104)`.
- **Quirks del original que se conservan a propósito** (para no cambiar comportamiento sin que lo decidas): los campos de contraseña son campos normales, con el texto visible; las credenciales `admin`/`admin` están fijas en código; "0FRAUDE" se escribe con cero; ningún formulario valida nada.

### 4.6 Mapa escena → vista

| Storyboard (id de escena / controller) | SwiftUI |
|---|---|
| `reg-vc` RegisterViewController | `RegisterView` |
| `login-vc` LoginViewController (`ViewController.swift`) | `LoginView` |
| `4WL-0z-fHl` MainTabBarController | `MainTabView` |
| `home-vc` HomeViewController | `HomeView` |
| `search-vc` SearchViewController | `SearchView` |
| `report-vc` ReportViewController | `ReportView` |
| `profile-vc` ProfileViewController | `ProfileView` |
| `settings-vc` SettingsViewController | `SettingsView` |
| `editprofile-vc` EditProfileViewController | `EditProfileView` |
| `privacy-vc` PrivacyViewController | `PrivacyView` |
| `changepw-vc` ChangePasswordViewController | `ChangePasswordView` |
| `signout-vc` SignOutViewController | `SignOutView` |
| `reportdetail-vc` ReportDetailViewController | `ReportDetailView` |
| `reportsuccess-vc` ReportSuccessViewController | `ReportSuccessView` |
| `guide-vc` SecurityGuideViewController | `SecurityGuideView` |
| `article-vc` ArticleViewController | `ArticleView` |
| `stats-vc` CommunityStatsViewController | `CommunityStatsView` |
| `nav-vc` UINavigationController (raíz) | `NavigationStack` en `OFraudeApp` |

Cada vista lleva un comentario de cabecera con la escena y el controller que reemplaza, para poder comparar contra el original.

## 5. Documentación

- Este spec queda en `docs/superpowers/specs/` dentro de la carpeta nueva.
- Comentario de cabecera en cada vista con su equivalente del storyboard.
- Comentarios en español, cortos y en el estilo del proyecto, solo donde explican el porqué (por ejemplo, para qué existe `AppState` o cómo se hace el aro del avatar).
- Al terminar, una nota en `docs/` con lo que cambió respecto al original y lo que quedó pendiente.

## 6. Verificación

1. Compilar con `xcodebuild` para el simulador iPhone 17 y arreglar lo que falle.
2. Correr el original y la copia en el simulador y comparar capturas de cada pantalla (layout, colores, textos).
3. Recorrer los flujos:
   - Login incorrecto (muestra el error) y correcto.
   - Las 3 categorías de Inicio abren Buscar con el texto precargado.
   - El botón de reportar de Inicio abre la pestaña Reportar.
   - Ajustes → Reportes guardados abre Perfil en Guardados.
   - Segmentos Mis reportes / Guardados, menú Editar/Eliminar y quitar de guardados.
   - Selección en Reportar y envío que abre ReportSuccess.
   - "Me too" abre Reportar.
   - Cerrar sesión.
4. Reportar al final lo que no se pudo comprobar (por ejemplo teclado o gestos que no se puedan automatizar).

Nota práctica: el simulador iPhone 17 se apaga solo si pasa tiempo entre comandos; hay que volver a bootearlo (`xcrun simctl boot` + `open -a Simulator`) antes de instalar y lanzar.

## 7. Fuera de alcance

- Backend, persistencia, autenticación real.
- Implementar los `// TODO` (crear cuenta, enviar reporte, evidencia, "Me too", guardar, compartir, comentarios, Editar).
- Rediseño o funciones nuevas. Los ajustes visuales que Alex mencionó se hacen después de verla corriendo.
- Cambios al proyecto original.
- Git.

## 8. Puntos por confirmar al implementar

Resueltos al escribir el plan (2026-09-26):

- `SignOutViewController` hace `popToRootViewController` al confirmar y un pop simple al cancelar (ver 4.3).
- La sincronización de carpetas del `.pbxproj` está confirmada (ver 4.1).
- `Info.plist` queda solo con el manifiesto de escena sin storyboard; además se quita `INFOPLIST_KEY_UIMainStoryboardFile` del `project.pbxproj` (ver 4.1).
- Colores, medidas, márgenes y valores iniciales de los switches se extrajeron del storyboard completo y están en el código del plan.

Siguen pendientes hasta la verificación:

- Si el aspecto del simulador (claro/oscuro) hace que las barras del sistema se vean distintas entre original y copia. Se iguala en la comparación.
- Algunas alineaciones que el storyboard no deja claras (texto centrado en las tarjetas de Inicio, filas de chips en Buscar, posición del lápiz en el avatar, botones de segmento en Perfil). El plan las resuelve con una suposición y la comparación contra el original las confirma o corrige.
- Si se pueden automatizar toques en el simulador; si no, el recorrido de flujos queda como checklist para Alex.
