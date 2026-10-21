# Plan de implementación: completar el prototipo de 0Fraude

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Objetivo:** convertir la migración fiel de 0Fraude (storyboard → SwiftUI) en un prototipo completo: cada control visible hace algo real, los datos sobreviven al cerrar la app, todo formulario valida, cada lista tiene estados de carga/vacío/error, hay tres roles con interfaz y la app se puede demostrar de punta a punta en el simulador sin crashes.

**Arquitectura:** las vistas leen y escriben a través de *stores* `@Observable` (`SessionStore`, `ReportsStore`, `NotificationsStore`, `AdminStore`). Los stores llaman a protocolos de repositorio con dos implementaciones: `DemoBackend` (un `actor DemoServer` dentro de la app que guarda JSON en disco y aplica las mismas reglas que tendrá el servidor) y `RemoteBackend` (API NestJS del Equipo ZeroScam). `AppState` se queda solo con la navegación. La seguridad (hash de contraseñas, Keychain, validación, límite de intentos, evidencia sin metadatos) vive en `Security/` y se prueba con TDD.

**Tech stack:** SwiftUI (iOS 26.5), Swift 5 con aislamiento por defecto `MainActor`, Observation, CommonCrypto (PBKDF2), CryptoKit (SHA-256), Security (Keychain), ImageIO, PhotosUI, UserNotifications, URLSession, Swift Testing (unitarias) y XCTest/XCUITest (interfaz). Sin dependencias externas.

**Spec:** `docs/superpowers/specs/2026-10-06-completar-prototipo-design.md` (leerlo antes de empezar; este plan argumenta desde ahí).

**Autor:** Equipo ZeroScam (Alex) con Claude · Fecha: 2026-10-07 · Fecha límite del prototipo: martes 2026-10-20.

## Restricciones globales

Aplican a todas las tareas aunque la tarea no las repita.

- **No tocar** `IS Modulo Avril Swift/PrototipoApp/` (el original). Todo ocurre en `IS Modulo Avril Swift/PrototipoApp-SwiftUI/`.
- **Nombre:** la app es **0Fraude** (con el dígito cero) en todo texto visible, nombre del ícono y documentos. **Equipo ZeroScam** firma como autor; la base de datos se llama ZeroScam por el equipo. Los identificadores de Swift conservan la letra (`OFraudeApp`, `OfraudeTextField`, `ofraude()`) porque un tipo no puede empezar con un dígito.
- **Git:** una rama por fase (`fase-0-base`, `fase-1-dominio`, …) creada desde `main`; se fusiona a `main` solo con build y tests en verde. Nunca `push` a un remoto. Los commits NO llevan trailer `Co-Authored-By` ni ninguna atribución a Claude: el autor es solo Alex (decisión de Alex, 2026-10-08).
- **Plataforma:** iOS 26.5, Xcode 26.5, `SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Por ese aislamiento por defecto, **todo tipo (incluidos los anidados), extensión y protocolo de `Model/`, `Security/` y `Data/` se declara `nonisolated`**, igual que los miembros `static` de los actores; el servidor Demo y el cliente HTTP son `actor`; los stores y las vistas quedan en `MainActor` (por defecto). En el target de pruebas unitarias también es `MainActor` por defecto; las clases de prueba que cumplen protocolos de la app se marcan `nonisolated`.
- **Sin dependencias externas** (ni SPM, ni CocoaPods).
- **Estilos:** colores y fuentes solo desde `Theme/`. Ninguna vista crea colores (`Color(r:…)`) ni fuentes sueltas; las vistas usan `Theme.*`, `.ofraude(…)`, `OfraudeButtonStyle` y los componentes de `Theme/Components.swift` y `Theme/Formularios.swift`.
- **Textos y comentarios:** en español. Comentarios cortos que explican el porqué, igual que el código actual. Cada archivo nuevo lleva la cabecera del proyecto:
  ```swift
  //
  //  Nombre.swift
  //  PrototipoApp
  //
  //  Para qué existe, en una o dos líneas.
  //
  ```
- **Datos del usuario en `Text`:** siempre como `String` (inicializador *verbatim*). Nunca construir un `LocalizedStringKey` con datos del usuario: SwiftUI interpretaría Markdown escrito por un atacante.
- **Sin crashes:** prohibido `try!`, `fatalError`, `precondition` y `!` forzado sobre datos externos o de disco. Única excepción documentada: `precondition` en `Aleatorio.bytes` si el generador del sistema falla (no hay forma segura de continuar).
- **Sin datos personales en logs:** ningún `print`, `NSLog` ni `Logger` con correos, nombres, contraseñas o tokens.
- **Comandos de verificación** (definidos completos en el apéndice D; se usan por nombre en las tareas):
  - `BUILD` = `xcodebuild -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd build 2>&1 | tail -3`
  - `UNIT` = `xcodebuild test -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd -only-testing:PrototipoAppTests 2>&1 | tail -8`
  - `UI` = `xcodebuild test -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd -resultBundlePath build/ui.xcresult -only-testing:PrototipoAppUITests 2>&1 | tail -8`
  - Para una sola suite: `UNIT` cambiando `-only-testing:PrototipoAppTests` por `-only-testing:PrototipoAppTests/<Suite>`.
- **Simulador:** iPhone 17 (`901BB67A-AD2D-425C-9FD4-6F928526F485`). Si se apagó entre comandos: `xcrun simctl boot "iPhone 17"; open -a Simulator`.
- **Cuentas demo** (las contraseñas en claro solo existen en este plan, en `docs/guion-demo.md` y en las pruebas; la app guarda únicamente sus hashes):

  | Rol | Correo | Contraseña | Alias |
  |---|---|---|---|
  | Usuario | `usuario@0fraude.mx` | `Alerta#2026mx` | `usuario_01` |
  | Administrador | `admin@0fraude.mx` | `Revisa#2026zs` | `admin_zs` |
  | Owner | `owner@0fraude.mx` | `Equipo#2026zs` | `owner_zs` |

## Foco de revisión

Cinco situaciones que el spec implica pero que ningún flujo feliz ejercita, ordenadas de la más probable a la menos. Cada una tiene su prueba en la tarea dueña del código.

1. **La sesión deja de servir a mitad de uso** (token vencido a los 7 días, cuenta suspendida por el Owner o datos demo restablecidos). Se espera: volver a Login con el aviso correspondiente, sin pantallas en blanco ni crash. Pruebas: D9 `ReportsStoreTests/sesionVencidaAvisaAlExpirar`, D7 `DemoServerCuentaTests/suspenderRevocaLasSesiones`.
2. **Doble toque en botones que crean algo** (ENVIAR REPORTE, publicar comentario, Yo también). Se espera: una sola creación. Pruebas: V1 `BotonAccion` se deshabilita mientras trabaja, D6 `DemoServerReportesTests/confirmarEsIdempotente`, Q2 `FlujoReporteUITests/testEnviarDosVecesCreaUnSoloReporte`.
3. **Un reporte desaparece (se elimina, deja de ser público o el Owner restablece los datos) mientras otra pestaña lo muestra en una lista o en un detalle.** Se espera: la lista lo quita al volver, y abrirlo o actuar sobre él responde "Este contenido ya no está disponible." en lugar de datos viejos o un crash. Pruebas: D6 `DemoServerReportesTests/detalleDeReporteAjenoNoPublicoEsNoEncontrado`, Q2 `PerfilUITests/testListasSeActualizanTrasEliminar`.
4. **Reinstalar la app con tokens viejos en el Keychain** (iOS conserva el Keychain al desinstalar). Se espera: arranque limpio en Registro, sin entrar con una sesión huérfana. Prueba: S2 `SecretStoreTests/limpiaTokensEnPrimeraEjecucion`.
5. **Texto engañoso en entradas:** URL con credenciales (`https://banco.com@estafa.com`), dominio homógrafo (`xn--pple-43d.com`) y caracteres invisibles o de dirección (bidi) en alias y comentarios. Se espera: mostrar el host real, advertir el homógrafo y limpiar el texto. Pruebas: S4 `URLToolsTests/normalizarQuitaCredenciales` y `detectaHomografo`, S3 `SanitizadorTests/quitaCaracteresInvisibles`.

---

## Tabla de contenido

- [0. Auditoría inicial](#0-auditoría-inicial) — build, inventario, hallazgos, flujos sin probar, tareas P1–P2
- [1. Definición de terminado y alcance](#1-definición-de-terminado-y-alcance)
- [2. Arquitectura de datos](#2-arquitectura-de-datos) — modelos ↔ SQL, repositorios, Demo vs Remote, semilla, `AppState`; tareas D1–D10 y R1–R3
- [3. Funcionalidad](#3-funcionalidad) — tareas F1–F21 (una por cada `// TODO` y cada pantalla nueva)
- [4. Seguridad](#4-seguridad) — controles, STRIDE; tareas S1–S7
- [5. Validación y estados de UI](#5-validación-y-estados-de-ui) — tareas V1–V3
- [6. Pulido de UX y accesibilidad](#6-pulido-de-ux-y-accesibilidad) — tareas U1–U6
- [7. Calidad y pruebas](#7-calidad-y-pruebas) — tareas Q1–Q3
- [8. Documentación y demo](#8-documentación-y-demo) — tareas M1–M3 y guion
- [9. Orden, dependencias y esfuerzo](#9-orden-dependencias-y-esfuerzo)
- [10. Riesgos y plan B](#10-riesgos-y-plan-b)
- [Apéndice A. Datos semilla](#apéndice-a-datos-semilla)
- [Apéndice B. Cobertura de controles](#apéndice-b-cobertura-de-controles)
- [Apéndice C. Cobertura del esquema SQL](#apéndice-c-cobertura-del-esquema-sql)
- [Apéndice D. Comandos](#apéndice-d-comandos)

**Cómo leer las tareas.** Las tareas están agrupadas por tema (sección 2, 3, 4…) para que cada sección del pedido esté completa. **El orden de ejecución no es el orden de lectura:** está en la sección 9. Por ejemplo, Q1 (crear los targets de pruebas) está en la sección 7 pero se ejecuta en la fase 0, antes de cualquier código. Cada tarea indica sus dependencias.

**Esfuerzo:** S ≈ hasta 1 h, M ≈ 1–3 h, L ≈ 3–6 h de implementación con pruebas (sin contar la revisión de Alex).

---

## 0. Auditoría inicial

### 0.1 Build

Ejecutado el 2026-10-07 sobre el código actual:

```bash
xcodebuild -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath <scratch>/dd clean build
```

- Resultado: `** BUILD SUCCEEDED **`.
- Advertencias del compilador: **0**.
- Único aviso: `appintentsmetadataprocessor: warning: Metadata extraction skipped. No AppIntents.framework dependency found.` Es un mensaje de la herramienta de Xcode, no del código (la app no usa App Intents). No requiere acción.
- `xcodebuild -list`: un solo target (`PrototipoApp`), un solo scheme **autogenerado** (no existe `PrototipoApp.xcodeproj/xcshareddata/`), **ningún target de pruebas**.
- Proyecto: Xcode 26.5 (17F42), `objectVersion = 77`, carpetas sincronizadas (`PBXFileSystemSynchronizedRootGroup`): crear un archivo dentro de `PrototipoApp/` basta para que compile.

### 0.2 Inventario pantalla por pantalla

Leído archivo por archivo el 2026-10-07. "Stub" = el control existe pero no hace nada (o hace solo la navegación). "Roto/inconsistente" = hace algo incorrecto o contradictorio.

| # | Pantalla (archivo) | Funciona | Stub | Roto / inconsistente | Tareas |
|---|---|---|---|---|---|
| 1 | Registro (`Views/Auth/RegisterView.swift`) | "¿Ya tienes cuenta?" abre Login | "CREAR CUENTA" solo navega a Login (no crea nada); 4 campos sin validar | Contraseñas en texto visible (`LabeledTextField`); faltan nombre, apellido y país que exige `Usuario` en el SQL | F1, V1 |
| 2 | Login (`Views/Auth/LoginView.swift`) | Error "Credenciales inválidas"; enlace a Registro | — | `admin`/`admin` fijo en código (líneas 19–20); contraseña visible; sin límite de intentos; sesión no sobrevive al reinicio | F2, F3, S1, S2, S5 |
| 3 | Pestañas (`Views/Tabs/MainTabView.swift`) | 4 pestañas con su pila | — | — | D10 |
| 4 | Inicio (`Views/Tabs/HomeView.swift`) | Botón naranja abre Reportar; Guía y Estadísticas abren su pantalla | "Bienvenido, Usuario." fijo; 2 alertas fijas | Las categorías abren Buscar con texto pero **nada filtra**; las alertas abren siempre el mismo detalle; el sello de la barra parece botón y no lo es | F4, F12, F16 |
| 5 | Buscar (`Views/Tabs/SearchView.swift`) | Recibe el texto de Inicio | Campo de búsqueda no filtra; chips son `Text` (no se pueden tocar) | Las 4 tarjetas de categoría abren el **mismo detalle fijo** en vez de resultados; conteos ("42 reportes") inventados | F12 |
| 6 | Reportar (`Views/Tabs/ReportView.swift`) | Selección con borde naranja; switch anónimo se mueve | "ENVIAR REPORTE" solo navega a Éxito; caja de evidencia vacía (`Button { }`) | Nada se guarda; el formulario no se limpia tras enviar; "(OPCIONAL)" aparece aunque no se elija "Otro"; sin título ni fecha (el SQL exige `fecha_incidente`) | F9, F10 |
| 7 | Perfil (`Views/Tabs/ProfileView.swift`) | Engrane → Ajustes; Editar perfil; segmentos; menú Editar/Eliminar/Cancelar | "Editar" no hace nada (línea 70) | Eliminar y quitar de guardados solo cambian `@State`: vuelve todo al recrear la vista; "12" reportes y "4,302" personas fijos con solo 2 tarjetas; nombre "Usuario" fijo | F11, F18 |
| 8 | Ajustes (`Views/Account/SettingsView.swift`) | Editar perfil, Privacidad, Guía, "Reportes guardados" abre Perfil en Guardados, Cerrar sesión | Switches Notificaciones y Modo oscuro no guardan ni hacen nada | "(12)" fijo con 2 guardados | F11, F16, U3 |
| 9 | Editar perfil (`Views/Account/EditProfileView.swift`) | — | "GUARDAR CAMBIOS" solo regresa | "Cambiar Avatar" se ve como enlace pero es `Text`; datos de ejemplo fijos | F18 |
| 10 | Seguridad y privacidad (`Views/Account/PrivacyView.swift`) | Abre Cambiar contraseña | 3 switches sin efecto ni persistencia | 2 pasos arranca encendido sin existir | F20, F21 |
| 11 | Cambiar contraseña (`Views/Account/ChangePasswordView.swift`) | — | "GUARDAR CONTRASEÑA" solo regresa | 3 campos de contraseña visibles | F19 |
| 12 | Cerrar sesión (`Views/Account/SignOutView.swift`) | Confirmar vuelve a Registro; Cancelar regresa | — | No revoca nada (no hay sesión real) | F3 |
| 13 | Detalle (`Views/Reports/ReportDetailView.swift`) | "Yo también" abre Reportar | Guardar, compartir y publicar comentario (`Button { }`) | Contenido fijo sin importar la tarjeta; "(42)" comentarios con 2 visibles | F5–F8 |
| 14 | Éxito (`Views/Reports/ReportSuccessView.swift`) | "CONTINUAR" vacía las pilas y va a Inicio | — | No muestra folio ni estado | F9 |
| 15 | Guía (`Views/Learn/SecurityGuideView.swift`) | Los 3 capítulos abren el artículo | — | Los 3 abren el **mismo** artículo | F14 |
| 16 | Artículo (`Views/Learn/ArticleView.swift`) | Contenido fijo | — | Un solo artículo para 3 capítulos | F14 |
| 17 | Estadísticas (`Views/Learn/CommunityStatsView.swift`) | Contenido fijo | — | Cifras inventadas ("actualizado en tiempo real" no es cierto) | F13 |

### 0.3 Otros hallazgos (comprobados en el código)

1. **Barra de estado ilegible en modo claro.** Ninguna vista usa `preferredColorScheme` (`grep -rn preferredColorScheme PrototipoApp` no devuelve nada). Con el simulador en modo claro, el texto de la barra de estado es negro sobre el fondo azul marino. → D10.
2. **Textos del sistema en inglés.** `developmentRegion = en` (`project.pbxproj:102`) y ninguna pantalla tiene `navigationTitle` (`grep -rn navigationTitle` vacío). La flecha de regreso dirá "Back" y el menú de compartir y el selector de fotos saldrán en inglés. *Por confirmar visualmente; es el comportamiento estándar de iOS.* → P2, U6.
3. **Cero accesibilidad.** No hay ningún `accessibilityLabel`, `accessibilityIdentifier`, `FocusState`, `submitLabel`, `textContentType` ni `SecureField` en todo `PrototipoApp/`. VoiceOver leerá "bookmark", "square and arrow up", "arrow up". → U2, V3, V1.
4. **Sin Dynamic Type.** `Text.ofraude()` usa `.system(size:)` fijo (88 llamadas). Hay 18 `frame(height:)` y 9 `frame(width:height:)` fijos que cortarán texto grande. → U1.
5. **Bloqueo para modo claro.** 34 usos de `.white` literal en 7 vistas (`ProfileView`, `ReportView`, `HomeView`, `SecurityGuideView`, `SettingsView`, `EditProfileView`, `ReportDetailView`). → U3.
6. **Contraste (aproximado con la fórmula WCAG).** Texto blanco sobre el naranja `(245,166,35)` ≈ 2.0:1 (botones INICIAR SESIÓN, CREAR CUENTA, CONTINUAR): falla AA. Texto de error en `Theme.danger (225,29,72)` sobre el fondo ≈ 3.9:1 a 13 pt: falla AA; `Theme.dangerText (255,75,75)` ≈ 5.6:1 sí pasa. → U6, V1.
7. **Modelo mezclado con interfaz.** `Model/Report.swift` importa SwiftUI para guardar un `Color`. → D1 lo reemplaza por `Model/Reporte.swift` sin SwiftUI; F11 borra `Report.swift`.
8. **Sin ícono ni color de acento.** `Assets.xcassets/AppIcon.appiconset` solo tiene `Contents.json` (ninguna imagen: el ícono sale en blanco) y `AccentColor.colorset` no define color (alertas, selector de fecha y de fotos salen en azul del sistema). → U6.

### 0.4 Flujos del checklist del 2026-09-27 que nunca se recorrieron

Todos los de `docs/verificacion-2026-09-26.md` (solo se comparó Registro). Cada uno queda automatizado con XCUITest en Q2 (XCUITest corre desde la terminal y **no** necesita el permiso de Accesibilidad de macOS que bloqueó la verificación anterior):

| # | Flujo | Prueba en Q2 |
|---|---|---|
| 1 | Registro → CREAR CUENTA abre Login; Login → "¿No tienes cuenta?" regresa | `AutenticacionUITests/testRegistroValidaYLlevaALogin` |
| 2 | Login incorrecto no navega; correcto entra | `AutenticacionUITests/testLoginIncorrectoYBloqueo`, `testLoginCorrectoPersisteSesion` |
| 3 | Categorías de Inicio abren Buscar con el filtro correcto | `NavegacionUITests/testCategoriaDeInicioFiltraBuscar` |
| 4 | Botón naranja de Inicio abre Reportar | `NavegacionUITests/testBotonReportarAbrePestana` |
| 5 | Alerta / categoría / tarjeta abren el detalle sin tab bar | `NavegacionUITests/testDetalleOcultaTabBar` |
| 6 | Perfil: segmentos, menú Editar/Eliminar/Cancelar, quitar guardado | `PerfilUITests/testEliminarYQuitarGuardado` |
| 7 | Ajustes → Reportes guardados abre Perfil en Guardados con pila vacía | `NavegacionUITests/testAjustesGuardadosAbrePerfil` |
| 8 | Detalle → Yo también → Reportar → Enviar → Éxito → Continuar vacía pilas | `FlujoReporteUITests/testYoTambienYEnvio` |
| 9 | Cerrar sesión: cancelar regresa; confirmar vuelve a Registro limpio | `AutenticacionUITests/testCerrarSesion` |
| 10 | Teclado: llegar a cada campo; tocar fuera cierra | Q3 checklist manual (el teclado del simulador depende de la configuración de hardware) |
| 11 | Texto grande y pantalla horizontal | `AccesibilidadUITests/testTextoGrandeYHorizontal` + Q3 |

### 0.5 Tareas de arranque

### Tarea P1: Línea base en git

**Objetivo:** guardar en `main` el estado actual (la migración que compila) y abrir la rama de la fase 0, para poder volver atrás si algo se rompe.

**Archivos:**
- Crear: `.gitignore`

**Interfaces:**
- Consume: nada.
- Produce: repositorio con `main` = migración del 2026-09-27; rama `fase-0-base`.

- [ ] **Paso 1: Confirmar que no hay repositorio todavía**

Run: `git -C "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI" status`
Expected: `fatal: not a git repository`. Si ya existe un repo, detenerse y preguntar a Alex.

- [ ] **Paso 2: Crear `.gitignore`**

```gitignore
# Xcode
xcuserdata/
DerivedData/
build/
*.xcresult

# macOS
.DS_Store
```

- [ ] **Paso 3: Commit inicial en `main`**

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI"
git init -b main
git add -A
git commit -m "chore: línea base de la migración de 0Fraude a SwiftUI"
```

- [ ] **Paso 4: Comprobar que la base compila**

Run: `BUILD`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Paso 5: Abrir la rama de la fase**

Run: `git switch -c fase-0-base`

**Criterios de aceptación:** `git log --oneline` muestra 1 commit; `git status` sin cambios; `git ls-files | grep -c xcuserdata` devuelve 0.
**Dependencias:** ninguna. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea P2: Nombre "0Fraude" y textos del sistema en español

**Objetivo:** que el ícono diga "0Fraude" y que iOS muestre sus propios textos (regresar, compartir, selector de fotos) en español.

**Archivos:**
- Modificar: `PrototipoApp.xcodeproj/project.pbxproj:102-107` (`developmentRegion`, `knownRegions`) y líneas 150 y 182 (`INFOPLIST_KEY_CFBundleDisplayName`)
- Modificar: `PrototipoApp/Info.plist` (agregar `CFBundleLocalizations`)
- Modificar: `PrototipoApp/Theme/Theme.swift:5` y `PrototipoApp/Theme/Components.swift:58` (comentarios que dicen "OFraude")

**Interfaces:**
- Consume: P1.
- Produce: `CFBundleDisplayName = 0Fraude`, `CFBundleDevelopmentRegion = es`, `CFBundleLocalizations = [es]`.

- [ ] **Paso 1: Nombre visible.** En `project.pbxproj`, en las dos configuraciones del target (líneas 150 y 182), cambiar:

```
INFOPLIST_KEY_CFBundleDisplayName = "OFraude SwiftUI";
```
por
```
INFOPLIST_KEY_CFBundleDisplayName = 0Fraude;
```

- [ ] **Paso 2: Idioma de desarrollo.** En `project.pbxproj` (sección `PBXProject`), cambiar:

```
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
```
por
```
			developmentRegion = es;
			hasScannedForEncodings = 0;
			knownRegions = (
				es,
				Base,
			);
```

- [ ] **Paso 3: Declarar español en `Info.plist`.** Dentro del `<dict>` raíz, antes de `UIApplicationSceneManifest`:

```xml
	<key>CFBundleLocalizations</key>
	<array>
		<string>es</string>
	</array>
```

- [ ] **Paso 4: Comentarios.** `Theme.swift:5`: "Todos los colores de OFraude…" → "Todos los colores de 0Fraude…". `Components.swift:58`: "con el estilo de OFraude" → "con el estilo de 0Fraude".

- [ ] **Paso 5: Verificar**

Run: `BUILD` y luego
`plutil -p $HOME/Library/Caches/0fraude-dd/Build/Products/Debug-iphonesimulator/PrototipoApp.app/Info.plist | grep -E "CFBundleDisplayName|CFBundleDevelopmentRegion|CFBundleLocalizations" -A2`
Expected: `"CFBundleDisplayName" => "0Fraude"`, `"CFBundleDevelopmentRegion" => "es"`, `"CFBundleLocalizations" => [ 0 => "es" ]`.

- [ ] **Paso 6: Verificación visual rápida.** Instalar y abrir; en Registro, tocar "¿Ya tienes cuenta?": la flecha de regreso de Login debe decir "Atrás" o solo mostrar la flecha (no "Back").

```bash
xcrun simctl install "iPhone 17" $HOME/Library/Caches/0fraude-dd/Build/Products/Debug-iphonesimulator/PrototipoApp.app
xcrun simctl launch "iPhone 17" Tec-CCM.PrototipoApp-SwiftUI
```

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp.xcodeproj/project.pbxproj PrototipoApp/Info.plist PrototipoApp/Theme/Theme.swift PrototipoApp/Theme/Components.swift
git commit -m "chore: nombre visible 0Fraude y textos del sistema en español"
```

**Criterios de aceptación:** el ícono en el simulador dice "0Fraude"; los textos del sistema salen en español.
**Dependencias:** P1. **Esfuerzo:** S. **Riesgo:** bajo (si Xcode reescribe el pbxproj al abrirlo, los valores se conservan).

---

## 1. Definición de terminado y alcance

### 1.1 Criterios de aceptación medibles

| ID | Criterio | Cómo se mide |
|---|---|---|
| AC1 | Todo control visible hace algo real y coherente | Apéndice B: cada fila con su tarea marcada como hecha; revisión en M3 |
| AC2 | Los datos sobreviven al cerrar la app | Q2 `testLoginCorrectoPersisteSesion` y `testReporteSobreviveReinicio` (terminan y relanzan la app) |
| AC3 | Ningún formulario acepta datos inválidos | Cada regla de `Validador` con al menos una prueba en `ValidadorTests` (S3); Q2 comprueba botones deshabilitados en Registro y Reportar |
| AC4 | Cada lista tiene estado cargando, vacío y error | `grep -rn "CargaView(" PrototipoApp/Views | wc -l` ≥ 9 (Inicio, Buscar ×2, Perfil ×2, Detalle, Comentarios, Notificaciones, Moderación, Usuarios, Estadísticas); revisión V2 |
| AC5 | Sin credenciales ni contraseñas en el código de la app | `grep -rn -e '"admin"' -e 'Alerta#2026' -e 'Revisa#2026' -e 'Equipo#2026' PrototipoApp` vacío |
| AC6 | Contraseñas con hash y sal, token en Keychain | `PasswordHasherTests` con vectores RFC; `SecretStoreTests` con Keychain real (target anfitrión) |
| AC7 | Permisos revisados en el "servidor" | Al menos 8 pruebas en D5–D7 donde un usuario sin rol intenta una acción de staff/owner y recibe `.sinPermiso` |
| AC8 | Build limpio | `BUILD` con 0 líneas `warning:` del compilador (`grep -c "warning:"` excluyendo `appintentsmetadataprocessor`) |
| AC9 | Pruebas en verde | `UNIT` y `UI` terminan en `** TEST SUCCEEDED **` |
| AC10 | Sin crashes en la demo | Guion de `docs/guion-demo.md` recorrido 2 veces seguidas sin cierre inesperado (Q3) |
| AC11 | Accesible | Todo botón de solo ícono con `accessibilityLabel` (`grep` en U2); texto en `accessibility2` sin cortar botones principales (`AccesibilidadUITests`) |
| AC12 | Documentado | Existen `README.md`, `docs/seguridad.md`, `docs/api-contrato.md`, `docs/guion-demo.md`, `docs/verificacion-2026-10-*.md`, `docs/capturas/` (≥ 12 capturas) y `docs/CAMBIOS-vs-original.md` actualizado |

### 1.2 Dentro del alcance

- Registro, login, sesión persistente, cierre de sesión, sesión expirada, verificación en dos pasos simulada (modo Demo).
- Reportes: crear (con título, fecha, ciudad, persona afectada, tipo, URL o texto, descripción, anónimo, evidencia), ver detalle dinámico, editar y eliminar los propios, guardar, "Yo también", compartir, comentar.
- Búsqueda con filtros reales (texto, tipo, riesgo); estadísticas calculadas; guía con 3 artículos distintos.
- Roles: Usuario, Administrador (cola de moderación, cambio de estado con historial, nivel de riesgo) y Owner (usuarios, roles, suspensión, analíticas anónimas, restablecer la demo).
- Notificaciones dentro de la app y avisos locales del sistema.
- Perfil, avatar, preferencias, aviso de privacidad, exportar mis datos, eliminar cuenta.
- Capa Remote completa contra un contrato (`docs/api-contrato.md`) y migración SQL propuesta para el equipo.
- Pruebas unitarias y de interfaz, accesibilidad, modo claro/oscuro, documentación y guion de demo.

### 1.3 Fuera del alcance (y por qué)

| Fuera | Por qué |
|---|---|
| Construir el backend NestJS y montar MySQL | Lo hace el Equipo ZeroScam; la app entrega el contrato y la capa Remote |
| Push real (APNs) | Requiere cuenta de pago de Apple y servidor; se usan avisos locales |
| 2 pasos real por SMS/correo/TOTP | Requiere proveedor externo; se simula en Demo con un código de un solo uso |
| Interfaz para el rol Policía | Decisión del 2026-10-07; el rol existe en el catálogo |
| Abrir enlaces sospechosos dentro de la app | Riesgo de seguridad; solo se muestran "desactivados" |
| Reputación automática de URLs (servicios externos) | Dependencia externa; el riesgo lo asigna un Administrador |
| iPad con diseño propio, otros idiomas, deep links, widgets | No aportan a la demo |
| Comparación pixel a pixel contra el original | Ya se hizo para Registro; los cambios visuales ahora son intencionales (U6) |

### 1.4 Decisión sobre los quirks que la migración conservó a propósito

| Quirk | Decisión | Por qué |
|---|---|---|
| `admin`/`admin` fijo en `LoginView` | **Se elimina.** Se reemplaza por 3 cuentas demo sembradas con hash PBKDF2 (tabla de Restricciones globales) | Credenciales en el código son la primera falla de cualquier auditoría (CWE-798) |
| Contraseñas visibles | **Se corrige:** `SecureField` con botón mostrar/ocultar (V1) | Evita lectura por encima del hombro y en grabaciones de pantalla |
| Ningún formulario valida | **Se corrige** en todos (S3, V1, F1–F21) | Requisito explícito del prototipo |
| "0FRAUDE" con cero | **Se conserva:** es el nombre de la app | No es un error |
| Bordes negros de tarjetas | Se conservan en modo oscuro; en modo claro usan `Theme.border` (U3) | Fidelidad al original en el modo que se presenta |
| Contenido fijo del detalle | **Se corrige:** el detalle depende de la tarjeta (F5) | Requisito |
| Los 3 capítulos abren el mismo artículo | **Se corrige** (F14) | "Todo botón hace algo coherente" |

### 1.5 0Fraude y ZeroScam

No hay que resolver un desajuste: **0Fraude** es el producto y **ZeroScam** es el equipo (y por eso la base se llama ZeroScam). El plan solo corrige lo que estaba mal escrito: el nombre visible "OFraude SwiftUI" con letra O pasa a "0Fraude" (P2), los documentos que dicen "OFraude" pasan a "0Fraude" (M1), y la documentación nueva firma "Equipo ZeroScam". Los identificadores de Swift se quedan con letra.

### 1.6 Supuestos

1. Se presenta en modo Demo; Remote queda probado con respuestas simuladas.
2. Alex revisa cada fase al fusionarla a `main`; los ajustes visuales de U6 se aplican con los valores propuestos salvo que Alex diga otra cosa.
3. El simulador iPhone 17 tiene fotos de ejemplo en su galería (comprobado: existe `data/Media/DCIM/100APPLE`).
4. Alex puede correr comandos interactivos con `!` (por ejemplo, `mysql -u root -p`) cuando una verificación necesite su contraseña.

### 1.7 Riesgos principales

Resumen; tabla completa con plan B en la sección 10: editar `project.pbxproj` a mano (Q1), Keychain en pruebas sin app anfitriona (S2), tiempo de 13 días frente a 58 tareas (sección 9 define la línea de corte), autocompletado de contraseñas que interfiere con XCUITest (Q2), y diferencias de nombres con el backend real (R3).

---

## 2. Arquitectura de datos

### 2.1 Tablas del SQL → modelos de Swift

Los nombres del dominio repiten los del SQL (en español) para que el mapeo se lea sin diccionario. Las vistas siguen en inglés (`ReportView`, `Route`), como hoy.

| Tabla (`database/zeroscam_base_datos.sql`) | Modelo Swift (archivo) | Fila del modo Demo | Notas |
|---|---|---|---|
| `Rol` | `enum Rol` (`Model/Catalogos.swift`) | — | `rawValue` = `nombre_rol`. `esStaff` = Administrador u Owner |
| `Estado` | `enum EstadoReporte` | — | `orden`, `esFinal`, `esPublico`, `siguientes` (máquina de estados) |
| `TipoFraude` | `enum TipoFraude` | — | 6 tipos de la pantalla Reportar; "Otro" usa `tipo_otro` (columna nueva) |
| `Usuario` | `struct Usuario` (`Model/Usuario.swift`) | `UsuarioFila` (+ `contrasenaHash`) | El hash **nunca** sale del servidor; columnas nuevas: `alias`, `biografia`, `avatar_ruta`, `preferencias`, consentimiento |
| `SitioWeb_URL` | `struct SitioWeb` (`Model/Reporte.swift`) | `SitioWeb` | `nivel_riesgo_global` = máximo de los reportes públicos que lo citan |
| `Reporte` | `struct Reporte` (vista por usuario) | `ReporteFila` | `Reporte` ya trae lo que *ese* usuario puede ver (ver 4.2) |
| `Evidencia` | `struct Evidencia` | `EvidenciaFila` | Archivo en disco; acceso con permiso (`datosEvidencia`) |
| `Reporte_URL` | `Reporte.sitio` | `ReporteFila.idSitio` | El SQL permite N:M; la app asocia como máximo un sitio por reporte |
| `Historial_Estado` | `struct HistorialEstado` (`Model/Actividad.swift`) | `HistorialFila` | Fila inicial con `anterior = nil` y el autor como responsable |
| `Notificacion_Alerta` | `struct Notificacion` | `NotificacionFila` | Se crea al cambiar de estado y al recibir un comentario |
| *(nueva)* `PersonaAfectada` | `struct PersonaAfectada` | dentro de `ReporteFila` | Solo autor y staff la ven |
| *(nueva)* `Comentario` | `struct Comentario` | `ComentarioFila` | |
| *(nueva)* `Reporte_Guardado` | `Reporte.guardadoPorMi` | `ParUsuarioReporte` | |
| *(nueva, propuesta)* `Reporte_Confirmacion` | `Reporte.confirmaciones`, `confirmadoPorMi` | `ParUsuarioReporte` | "Yo también" |
| *(nueva)* `Sesion` | `SesionActiva` (lado app) | `SesionFila` (hash del token) | |
| *(nueva, propuesta)* `Desafio_DosPasos` | `DesafioDosPasos` | `DesafioFila` | |

El detalle de columnas nuevas y el `ALTER TABLE` está en R1 (`database/zeroscam_migracion_0fraude.sql`). El apéndice C confirma que cada tabla tiene destino.

### 2.2 Capa de repositorio

Cinco protocolos, uno por área, en `Data/Repositories.swift`: `AuthRepository`, `ReportRepository`, `ProfileRepository`, `NotificationRepository` y `AdminRepository`. `typealias Backend` es la suma de los cinco. Ningún método recibe el token: cada implementación lo lee del `SecretStore`, igual que el interceptor de `api.ts` del profesor pone el `Bearer` sin que la pantalla se entere.

Por qué protocolos: las vistas (y los stores) quedan iguales si mañana se cambia Demo por Remote. Y en las pruebas se usa el Demo con una carpeta temporal.

### 2.3 Opciones comparadas

| Criterio | En memoria | SwiftData | **JSON local en un `actor` (elegida para Demo)** | API (Remote) |
|---|---|---|---|---|
| Sobrevive al cerrar la app | No | Sí | Sí | Sí (en el servidor) |
| Mismos tipos que el contrato de la API | Sí | No: clases `@Model` aparte y traducción | Sí: los mismos `Codable` | Sí |
| Riesgo con Swift 5 + `MainActor` por defecto | Bajo | Medio: `ModelContext` ligado a un actor, `@Model` no es `Sendable` | Bajo: `actor` serializa todo | Bajo |
| Reglas del servidor (permisos, límites) | Habría que escribirlas igual | Igual | Se escriben una vez en `DemoServer` y sirven de especificación para el equipo | Las aplica el backend |
| Inspeccionar y reiniciar para la demo | Trivial | Difícil (SQLite) | Fácil (un archivo) | Depende del equipo |
| Disponible hoy | Sí | Sí | Sí | **No** (backend en construcción) |
| Uso en el plan | No se implementa aparte: las pruebas usan el Demo con carpeta temporal | Descartado | `DemoBackend` | `RemoteBackend` (R2–R3) |

**Recomendación:** JSON con `Codable` dentro de `actor DemoServer` para el modo Demo, y `RemoteBackend` detrás del mismo protocolo. Con decenas de reportes no hace falta un motor de consultas, y el `actor` se comporta como un servidor real (una operación a la vez).

### 2.4 Datos semilla

`Data/Demo/DemoSeed.swift` (D4) arma la base de la demo a partir de la fecha actual, para que "Hace 2 horas" sea verdad el día de la presentación. Contenido (detalle en el apéndice A):

- 6 usuarios: Owner, Administrador, Usuario demo y 3 miembros de la comunidad (`tecno_mx`, `compras_seguras`, `vecina_alerta`) con contraseñas aleatorias desconocidas (no pueden iniciar sesión).
- 23 reportes: 17 públicos (VALIDADO o CANALIZADO, los 2 de "Alertas críticas" son los del storyboard), 4 en cola (RECIBIDO o EN_REVISION), 1 RECHAZADO y los 3 del usuario demo (EN_REVISION, VALIDADO y RECIBIDO, este último editable).
- Comentarios, guardados (los 2 del storyboard), historial de estados y 2 notificaciones del usuario demo (una sin leer, para que la campana tenga número).
- `confirmacionesPrevias`: solo en Demo, un conteo histórico por reporte (1.2k, 450, 340…) para que las cifras parezcan una comunidad real. En la base real ese número es `COUNT(*)` de `Reporte_Confirmacion`; se documenta en `docs/api-contrato.md`.

### 2.5 Cómo conviven `AppState`, las 4 pilas y el estado nuevo

Hoy `AppState` hace dos trabajos: navegación y "¿hay sesión?" (`isLoggedIn`). Se separan:

```
OFraudeApp
 ├─ AppState            (solo navegación: pestaña, 4 pilas, búsqueda pendiente, segmento de Perfil)
 ├─ SessionStore        (¿quién soy?: restaurando / sin sesión / activa(Usuario), aviso para Login)
 ├─ ReportsStore        (alertas, resultados, mis reportes, guardados, estadísticas, `version`)
 ├─ NotificationsStore  (lista y contador de no leídas)
 └─ AdminStore          (cola de moderación, usuarios)
```

- `RootView` decide la raíz con `session.estado` (antes `appState.isLoggedIn`).
- Las 4 pilas (`homePath`, `searchPath`, `reportPath`, `profilePath`) no cambian. Lo que cambia es `Route`, que ahora lleva datos: `.reportDetail(Int64)` sabe qué reporte abrir.
- Al cerrar sesión (o expirar), `RootView` ve que `session.usuario` pasó a `nil` y llama `appState.resetNavigation()`, `reports.reiniciar()` y `notifications.reiniciar()`. Nadie tiene que acordarse de limpiar a mano.
- Cuando algo cambia datos (crear, editar, borrar, moderar), `ReportsStore.version` sube en 1. Las listas recargan con `.task(id: reports.version)`, así una tarjeta borrada en Perfil desaparece también de Buscar sin que las vistas se hablen entre sí.

Antes y después en `SignOutView`:

```swift
// Antes
Button("CERRAR SESIÓN") { appState.logOut() }

// Después
BotonAccion(titulo: "CERRAR SESIÓN", estilo: OfraudeButtonStyle(background: Theme.danger)) {
    await session.cerrarSesion()   // revoca el token en el servidor y lo borra del Keychain
}
// RootView detecta el cambio y deja la navegación como al abrir la app.
```

### 2.6 Migración sin romper las vistas

1. **Primero lo puro (fase 1):** modelos, validadores y seguridad se agregan en archivos nuevos. Ninguna vista cambia; el build sigue verde.
2. **Después el servidor y los stores (fase 2):** también archivos nuevos. `Report` (el modelo viejo de Perfil) convive con `Reporte` hasta F11.
3. **Integración (D10):** se cambia `AppState`, `Route` y `RootView`. Las vistas que hoy usan `.reportDetail` sin id pasan a usar un id de la semilla (`101`) para seguir compilando; cada tarea F las conecta a datos reales.
4. **Pantalla por pantalla (fases 3–6):** cada tarea F reemplaza los textos fijos de una vista por datos del store. Al terminar F11 se borra `Model/Report.swift`.
5. En cada paso: `BUILD` y `UNIT` en verde antes del commit.

### 2.7 Tareas de la capa de datos

### Tarea D1: Modelos del dominio

**Objetivo:** tener los tipos de Swift que corresponden a las tablas del SQL, más el filtro de búsqueda y los formatos de fecha y conteo, sin depender de SwiftUI.

**Archivos:**
- Crear: `PrototipoApp/Model/Catalogos.swift`
- Crear: `PrototipoApp/Model/Usuario.swift`
- Crear: `PrototipoApp/Model/Reporte.swift`
- Crear: `PrototipoApp/Model/Actividad.swift`
- Crear: `PrototipoApp/Model/FiltroBusqueda.swift`
- Crear: `PrototipoApp/Model/Formato.swift`
- Test: `PrototipoAppTests/Model/CatalogosTests.swift`, `PrototipoAppTests/Model/FiltroBusquedaTests.swift`, `PrototipoAppTests/Model/FormatoTests.swift`, `PrototipoAppTests/Soporte/Fixtures.swift`

**Interfaces:**
- Consume: Q1 (target de pruebas).
- Produce: `Rol`, `EstadoReporte`, `TipoFraude`, `NivelRiesgo`, `EstadoCuenta`, `Afectado`, `Preferencias`, `Consentimiento`, `Usuario`, `RegistroDatos`, `PerfilDatos`, `AutorVisible`, `PersonaAfectada`, `SitioWeb`, `Evidencia`, `Adjunto`, `Reporte`, `ReporteBorrador` (con `init(desde:)`), `ReportePrefill`, `Comentario`, `HistorialEstado`, `Notificacion`, `EstadisticasComunidad`, `ConteoCategoria`, `FiltroBusqueda` (`coincide(_:)`, `estaVacio`, `normalizar(_:)`), `Formato` (`relativo(_:ahora:)`, `conteoCorto(_:)`, `miles(_:)`, `folio(_:)`, `fechaCorta(_:)`).

- [ ] **Paso 1: Escribir las pruebas que fallan**

`PrototipoAppTests/Soporte/Fixtures.swift`:

```swift
//
//  Fixtures.swift
//  PrototipoAppTests
//
//  Reportes de ejemplo para las pruebas.
//

import Foundation
@testable import PrototipoApp

extension Reporte {
    static func ejemplo(id: Int64 = 1,
                        titulo: String = "Tienda clonada de tenis deportivos",
                        descripcion: String = "Venden tenis a mitad de precio y nunca entregan.",
                        tipo: TipoFraude = .tiendaClonada,
                        riesgo: NivelRiesgo = .alto,
                        estado: EstadoReporte = .validado,
                        ciudad: String = "Monterrey",
                        url: String? = "https://n1ke-outlet-mexico.com",
                        texto: String? = nil) -> Reporte {
        Reporte(id: id,
                autor: AutorVisible(idUsuario: nil, nombre: "Anónimo"),
                tipo: tipo, tipoOtro: nil, estado: estado,
                titulo: titulo, descripcion: descripcion,
                fechaIncidente: Date(timeIntervalSince1970: 1_790_000_000),
                nivelRiesgo: riesgo,
                fechaCreacion: Date(timeIntervalSince1970: 1_790_000_000),
                esAnonimo: true, afectado: .yo, ciudad: ciudad, personaAfectada: nil,
                sitio: url.map { SitioWeb(id: 9, url: $0, nivelRiesgoGlobal: riesgo, estadoCertificado: "HTTPS", fechaUltimaEvaluacion: nil) },
                textoSospechoso: texto, evidencias: [], totalEvidencias: 0,
                confirmaciones: 0, comentarios: 0,
                confirmadoPorMi: false, guardadoPorMi: false, esMio: false)
    }
}
```

`PrototipoAppTests/Model/CatalogosTests.swift`:

```swift
//
//  CatalogosTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct CatalogosTests {
    @Test func rawValuesIgualesAlSQL() {
        #expect(Rol.allCases.map(\.rawValue) == ["Usuario", "Administrador", "Policia", "Owner"])
        #expect(EstadoReporte.allCases.map(\.rawValue) == ["RECIBIDO", "EN_REVISION", "VALIDADO", "RECHAZADO", "CANALIZADO"])
        #expect(NivelRiesgo.allCases.map(\.rawValue) == ["NO_EVALUADO", "BAJO", "MEDIO", "ALTO", "MUY_ALTO"])
        #expect(TipoFraude.allCases.map(\.rawValue) == ["Oferta Falsa", "Sorteo Falso", "Tienda Clonada", "Marketplace", "Llamada", "Otro"])
    }

    @Test func soloValidadoYCanalizadoSonPublicos() {
        #expect(EstadoReporte.allCases.filter(\.esPublico) == [.validado, .canalizado])
    }

    @Test func transicionesPermitidas() {
        #expect(EstadoReporte.recibido.siguientes == [.enRevision, .rechazado])
        #expect(EstadoReporte.enRevision.siguientes == [.validado, .rechazado])
        #expect(EstadoReporte.validado.siguientes == [.canalizado])
        #expect(EstadoReporte.rechazado.siguientes.isEmpty)
        #expect(EstadoReporte.canalizado.siguientes.isEmpty)
    }

    @Test func finalesYOrdenComoElCatalogo() {
        #expect(EstadoReporte.allCases.filter(\.esFinal) == [.rechazado, .canalizado])
        #expect(EstadoReporte.allCases.map(\.orden) == [1, 2, 3, 4, 5])
    }

    @Test func soloSeEditaAntesDeValidar() {
        #expect(EstadoReporte.allCases.filter(\.permiteEdicion) == [.recibido, .enRevision])
    }

    @Test func riesgoSeOrdena() {
        #expect(NivelRiesgo.bajo < .alto)
        #expect([NivelRiesgo.muyAlto, .bajo, .medio].max() == .muyAlto)
        #expect(!NivelRiesgo.asignables.contains(.noEvaluado))
    }

    @Test func soloAdministradorYOwnerSonStaff() {
        #expect(Rol.allCases.filter(\.esStaff) == [.administrador, .owner])
    }

    @Test func cadaTipoTieneCategoriaResumenYTresPasos() {
        for tipo in TipoFraude.allCases {
            #expect(!tipo.categoria.isEmpty)
            #expect(!tipo.resumen.isEmpty)
            #expect(tipo.modusOperandi.count == 3)
        }
    }
}
```

`PrototipoAppTests/Model/FiltroBusquedaTests.swift`:

```swift
//
//  FiltroBusquedaTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct FiltroBusquedaTests {
    let reporte = Reporte.ejemplo()

    @Test func filtroVacioCoincideConTodo() {
        #expect(FiltroBusqueda().estaVacio)
        #expect(FiltroBusqueda().coincide(reporte))
    }

    @Test func ignoraMayusculasYAcentos() {
        #expect(FiltroBusqueda(texto: "TENIS").coincide(reporte))
        #expect(FiltroBusqueda(texto: "clonáda").coincide(reporte))
    }

    @Test func todasLasPalabrasDebenAparecer() {
        #expect(FiltroBusqueda(texto: "tenis monterrey").coincide(reporte))
        #expect(!FiltroBusqueda(texto: "tenis cdmx").coincide(reporte))
    }

    @Test func buscaTambienEnLaURLYElTextoSospechoso() {
        #expect(FiltroBusqueda(texto: "n1ke").coincide(reporte))
        let llamada = Reporte.ejemplo(tipo: .llamada, url: nil, texto: "+52 55 8765 4321")
        #expect(FiltroBusqueda(texto: "8765").coincide(llamada))
    }

    @Test func filtraPorTipoYRiesgoMinimo() {
        #expect(FiltroBusqueda(tipos: [.tiendaClonada]).coincide(reporte))
        #expect(!FiltroBusqueda(tipos: [.llamada]).coincide(reporte))
        #expect(FiltroBusqueda(riesgoMinimo: .alto).coincide(reporte))
        #expect(!FiltroBusqueda(riesgoMinimo: .muyAlto).coincide(reporte))
        #expect(!FiltroBusqueda(riesgoMinimo: .medio).estaVacio)
    }

    @Test func espaciosNoCuentanComoTexto() {
        #expect(FiltroBusqueda(texto: "   ").estaVacio)
    }
}
```

`PrototipoAppTests/Model/FormatoTests.swift`:

```swift
//
//  FormatoTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct FormatoTests {
    let ahora = Date(timeIntervalSince1970: 1_791_072_000)   // 2026-10-04 00:00 UTC

    @Test func relativoEnEspanolConMayuscula() {
        let texto = Formato.relativo(ahora.addingTimeInterval(-7_200), ahora: ahora)
        #expect(texto.lowercased().contains("2 horas"))
        #expect(texto.first?.isUppercase == true)
    }

    @Test func relativoDeAyer() {
        #expect(Formato.relativo(ahora.addingTimeInterval(-86_400), ahora: ahora).lowercased().contains("ayer"))
    }

    @Test func conteoCortoComoElStoryboard() {
        #expect(Formato.conteoCorto(340) == "340")
        #expect(Formato.conteoCorto(1_000) == "1k")
        #expect(Formato.conteoCorto(1_200) == "1.2k")
    }

    @Test func milesConComa() {
        #expect(Formato.miles(4_302) == "4,302")
    }

    @Test func folioConSeisDigitos() {
        #expect(Formato.folio(123) == "#000123")
    }

    @Test func borradorDesdeReporteCopiaLosCampos() {
        let r = Reporte.ejemplo(texto: nil)
        let b = ReporteBorrador(desde: r)
        #expect(b.titulo == r.titulo)
        #expect(b.urlOTexto == "https://n1ke-outlet-mexico.com")
        #expect(b.tipo == .tiendaClonada)
        #expect(b.adjuntos.isEmpty)
    }
}
```

- [ ] **Paso 2: Correr y ver que fallan**

Run: `UNIT`
Expected: FAIL de compilación con `cannot find type 'Reporte' in scope` (y similares).

- [ ] **Paso 3: Implementar `Model/Catalogos.swift`**

```swift
//
//  Catalogos.swift
//  PrototipoApp
//
//  Catálogos de la base ZeroScam (tablas Rol, Estado y TipoFraude) y los valores fijos de
//  `Usuario.estado_cuenta` y del nivel de riesgo. El `rawValue` es el texto exacto que guarda
//  MySQL, para que el JSON del backend se lea sin traducir.
//

import Foundation

nonisolated enum Rol: String, Codable, Sendable, CaseIterable {
    case usuario = "Usuario"
    case administrador = "Administrador"
    case policia = "Policia"
    case owner = "Owner"

    /// Administrador y Owner moderan. Policía existe en la base pero no tiene interfaz.
    var esStaff: Bool { self == .administrador || self == .owner }

    var titulo: String {
        switch self {
        case .usuario: "Usuario"
        case .administrador: "Administrador"
        case .policia: "Policía"
        case .owner: "Owner"
        }
    }
}

nonisolated enum EstadoReporte: String, Codable, Sendable, CaseIterable {
    case recibido = "RECIBIDO"
    case enRevision = "EN_REVISION"
    case validado = "VALIDADO"
    case rechazado = "RECHAZADO"
    case canalizado = "CANALIZADO"

    /// Como se muestra en pantalla.
    var titulo: String {
        switch self {
        case .recibido: "RECIBIDO"
        case .enRevision: "EN REVISIÓN"
        case .validado: "VALIDADO"
        case .rechazado: "RECHAZADO"
        case .canalizado: "CANALIZADO"
        }
    }

    /// Columna `Estado.orden`.
    var orden: Int {
        switch self {
        case .recibido: 1
        case .enRevision: 2
        case .validado: 3
        case .rechazado: 4
        case .canalizado: 5
        }
    }

    /// Columna `Estado.es_final`: de aquí ya no se mueve.
    var esFinal: Bool { self == .rechazado || self == .canalizado }

    /// Solo estos aparecen en Inicio, Buscar y Estadísticas.
    var esPublico: Bool { self == .validado || self == .canalizado }

    /// A qué estados puede moverlo un Administrador.
    var siguientes: [EstadoReporte] {
        switch self {
        case .recibido: [.enRevision, .rechazado]
        case .enRevision: [.validado, .rechazado]
        case .validado: [.canalizado]
        case .rechazado, .canalizado: []
        }
    }

    /// El autor puede editar mientras nadie lo haya validado ni cerrado.
    var permiteEdicion: Bool { self == .recibido || self == .enRevision }
}

nonisolated enum TipoFraude: String, Codable, Sendable, CaseIterable, Identifiable {
    case ofertaFalsa = "Oferta Falsa"
    case sorteoFalso = "Sorteo Falso"
    case tiendaClonada = "Tienda Clonada"
    case marketplace = "Marketplace"
    case llamada = "Llamada"
    case otro = "Otro"

    var id: String { rawValue }

    /// Nombre en plural de las tarjetas de Buscar (los 4 primeros son los del storyboard).
    var categoria: String {
        switch self {
        case .ofertaFalsa: "Ofertas Falsas"
        case .sorteoFalso: "Sorteos Falsos"
        case .tiendaClonada: "Tiendas Clonadas"
        case .marketplace: "Marketplace Fraudulento"
        case .llamada: "Llamadas Fraudulentas"
        case .otro: "Otros Fraudes"
        }
    }

    var resumen: String {
        switch self {
        case .ofertaFalsa: "Descuentos irreales y liquidaciones que nunca llegan."
        case .sorteoFalso: "Concursos y premios falsos que piden tus datos o dinero."
        case .tiendaClonada: "Sitios web que imitan marcas conocidas para robar tu pago."
        case .marketplace: "Vendedores falsos en redes que cobran y no entregan."
        case .llamada: "Llamadas y mensajes que se hacen pasar por bancos o autoridades."
        case .otro: "Phishing, empleos y préstamos falsos, y otros engaños."
        }
    }

    /// Pasos típicos; alimentan la sección "Modus Operandi" del detalle (antes fija).
    var modusOperandi: [String] {
        switch self {
        case .ofertaFalsa: [
            "1. El Anuncio: ves publicidad en redes con precios absurdamente bajos y 'solo por hoy'.",
            "2. El Sitio Clonado: el link lleva a una página que imita a una tienda real, casi idéntica.",
            "3. Pago sin Entrega: después de pagar, el sitio deja de responder y el producto nunca llega.",
        ]
        case .sorteoFalso: [
            "1. El Premio: te avisan por redes que ganaste un sorteo en el que nunca participaste.",
            "2. Los Datos: para 'reclamarlo' piden tus datos personales, de tarjeta o un pago de envío.",
            "3. El Silencio: después del pago o de entregar tus datos, la cuenta desaparece.",
        ]
        case .tiendaClonada: [
            "1. La Copia: un sitio imita el diseño y el nombre de una marca real, con un dominio parecido.",
            "2. El Pago: solo acepta transferencia o pide los datos completos de tu tarjeta.",
            "3. La Desaparición: el pedido nunca llega y el sitio cambia de dominio.",
        ]
        case .marketplace: [
            "1. La Publicación: un vendedor ofrece un producto muy por debajo de su precio.",
            "2. El Anticipo: pide un depósito o un pago fuera de la plataforma para 'apartarlo'.",
            "3. Sin Entrega: tras el pago, el vendedor deja de responder o borra el perfil.",
        ]
        case .llamada: [
            "1. La Suplantación: alguien llama diciendo ser del banco, del SAT o un familiar en problemas.",
            "2. La Urgencia: inventa una emergencia para que actúes sin verificar.",
            "3. La Petición: pide códigos, contraseñas o una transferencia inmediata.",
        ]
        case .otro: [
            "1. El Gancho: una oferta de empleo, préstamo o apoyo que parece fácil de obtener.",
            "2. El Cobro: piden un pago por adelantado o tus datos personales.",
            "3. El Engaño: el beneficio nunca llega y tus datos pueden usarse para otros fraudes.",
        ]
        }
    }
}

nonisolated enum NivelRiesgo: String, Codable, Sendable, CaseIterable, Comparable {
    case noEvaluado = "NO_EVALUADO"
    case bajo = "BAJO"
    case medio = "MEDIO"
    case alto = "ALTO"
    case muyAlto = "MUY_ALTO"

    var titulo: String {
        switch self {
        case .noEvaluado: "SIN EVALUAR"
        case .bajo: "BAJO"
        case .medio: "MEDIO"
        case .alto: "ALTO"
        case .muyAlto: "MUY ALTO"
        }
    }

    /// Los que puede asignar un Administrador al validar.
    static let asignables: [NivelRiesgo] = [.bajo, .medio, .alto, .muyAlto]

    private var rango: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (a: NivelRiesgo, b: NivelRiesgo) -> Bool { a.rango < b.rango }
}

/// Columna `Usuario.estado_cuenta`.
nonisolated enum EstadoCuenta: String, Codable, Sendable {
    case activo = "ACTIVO"
    case suspendido = "SUSPENDIDO"
}

/// "¿A quién le ocurrió el fraude?" (columna nueva `Reporte.afectado`).
nonisolated enum Afectado: String, Codable, Sendable, CaseIterable {
    case yo = "YO"
    case otraPersona = "OTRA_PERSONA"

    var titulo: String { self == .yo ? "A mí" : "A otra persona" }
}
```

- [ ] **Paso 4: Implementar `Model/Usuario.swift`**

```swift
//
//  Usuario.swift
//  PrototipoApp
//
//  Tabla Usuario tal como la ve la propia persona. El hash de la contraseña nunca sale del
//  servidor: no existe en este tipo.
//

import Foundation

nonisolated struct Preferencias: Codable, Sendable, Hashable {
    var notificaciones = false
    var modoOscuro = true
    var dosPasos = false
    var perfilPublico = false
    var analiticas = true
}

/// Qué versión del aviso de privacidad aceptó y cuándo (consentimiento, LFPDPPP).
nonisolated struct Consentimiento: Codable, Sendable, Hashable {
    var versionAviso: String
    var fecha: Date
}

nonisolated struct Usuario: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    var rol: Rol
    var nombre: String
    var apellido: String
    var pais: String
    var alias: String
    var correo: String
    var biografia: String
    var avatarRuta: String?
    var estadoCuenta: EstadoCuenta
    var fechaRegistro: Date
    var preferencias: Preferencias
    var consentimiento: Consentimiento
}

/// Lo que llena la pantalla de Registro. No es `Codable` a propósito: lleva la contraseña.
nonisolated struct RegistroDatos: Sendable, Hashable {
    var nombre = ""
    var apellido = ""
    var pais = "México"
    var alias = ""
    var correo = ""
    var contrasena = ""
    var confirmacion = ""
    var aceptaAviso = false
}

/// Lo que llena Editar perfil. La contraseña actual solo se pide si cambia el correo.
nonisolated struct PerfilDatos: Sendable, Hashable {
    var nombre: String
    var apellido: String
    var pais: String
    var alias: String
    var correo: String
    var biografia: String
    var contrasenaActual: String?

    init(desde u: Usuario) {
        nombre = u.nombre
        apellido = u.apellido
        pais = u.pais
        alias = u.alias
        correo = u.correo
        biografia = u.biografia
        contrasenaActual = nil
    }
}
```

- [ ] **Paso 5: Implementar `Model/Reporte.swift`**

```swift
//
//  Reporte.swift
//  PrototipoApp
//
//  Un reporte tal como lo puede ver quien lo pide: el servidor ya quitó lo que esa persona no
//  debe ver (persona afectada, evidencia, autor anónimo). Mapea Reporte, SitioWeb_URL,
//  Evidencia y las tablas nuevas PersonaAfectada, Reporte_Guardado y Reporte_Confirmacion.
//

import Foundation

nonisolated struct AutorVisible: Codable, Sendable, Hashable {
    /// `nil` cuando quien mira no debe saber quién fue (anónimo o perfil privado).
    let idUsuario: Int64?
    /// Alias, "Anónimo", "Miembro de la comunidad", "Tú" o "Cuenta eliminada".
    let nombre: String
}

nonisolated struct PersonaAfectada: Codable, Sendable, Hashable {
    var nombre: String
    var contacto: String
    /// El reportante confirma que la persona le autorizó compartir sus datos.
    var autorizo: Bool
}

nonisolated struct SitioWeb: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    var url: String
    var nivelRiesgoGlobal: NivelRiesgo
    var estadoCertificado: String?
    var fechaUltimaEvaluacion: Date?
}

nonisolated struct Evidencia: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    var rutaArchivo: String
    var tipoArchivo: String
    var fechaCarga: Date

    var esPDF: Bool { tipoArchivo == "application/pdf" }
}

/// Archivo ya limpio (sin metadatos) en la carpeta temporal, esperando a que se envíe el reporte.
nonisolated struct Adjunto: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let nombreArchivo: String
    let tipoArchivo: String
    let bytes: Int

    var esPDF: Bool { tipoArchivo == "application/pdf" }
}

nonisolated struct Reporte: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    var autor: AutorVisible
    var tipo: TipoFraude
    var tipoOtro: String?
    var estado: EstadoReporte
    var titulo: String
    var descripcion: String
    var fechaIncidente: Date
    var nivelRiesgo: NivelRiesgo
    var fechaCreacion: Date
    var esAnonimo: Bool
    var afectado: Afectado
    var ciudad: String
    /// Solo llega al autor y al staff.
    var personaAfectada: PersonaAfectada?
    var sitio: SitioWeb?
    var textoSospechoso: String?
    /// Solo llega al autor y al staff; los demás ven `totalEvidencias`.
    var evidencias: [Evidencia]
    var totalEvidencias: Int
    var confirmaciones: Int
    var comentarios: Int
    var confirmadoPorMi: Bool
    var guardadoPorMi: Bool
    var esMio: Bool

    /// "Oferta Falsa", o lo que escribió en "Otro".
    var tipoVisible: String { tipo == .otro ? (tipoOtro ?? TipoFraude.otro.rawValue) : tipo.rawValue }
}

/// El formulario de Reportar. `limpio` (Security/Sanitizador.swift) lo deja listo para validar.
nonisolated struct ReporteBorrador: Sendable, Hashable {
    var esAnonimo = false
    var afectado: Afectado = .yo
    var persona = PersonaAfectada(nombre: "", contacto: "", autorizo: false)
    var ciudad = ""
    var tipo: TipoFraude = .ofertaFalsa
    var tipoOtro = ""
    var titulo = ""
    var fechaIncidente = Date()
    var urlOTexto = ""
    var descripcion = ""
    var adjuntos: [Adjunto] = []
    /// Al editar: evidencias ya guardadas que el autor quitó.
    var quitarEvidencias: Set<Int64> = []

    init() {}

    /// Para editar un reporte existente.
    init(desde r: Reporte) {
        esAnonimo = r.esAnonimo
        afectado = r.afectado
        persona = r.personaAfectada ?? PersonaAfectada(nombre: "", contacto: "", autorizo: false)
        ciudad = r.ciudad
        tipo = r.tipo
        tipoOtro = r.tipoOtro ?? ""
        titulo = r.titulo
        fechaIncidente = r.fechaIncidente
        urlOTexto = r.sitio?.url ?? r.textoSospechoso ?? ""
        descripcion = r.descripcion
    }
}

/// Lo que "Yo también" le pasa al formulario.
nonisolated struct ReportePrefill: Sendable, Hashable {
    var tipo: TipoFraude
    var tipoOtro: String?
    var urlOTexto: String
}
```

- [ ] **Paso 6: Implementar `Model/Actividad.swift`**

```swift
//
//  Actividad.swift
//  PrototipoApp
//
//  Lo que pasa alrededor de un reporte: comentarios, historial de estados (Historial_Estado),
//  notificaciones (Notificacion_Alerta) y los números de la comunidad.
//

import Foundation

nonisolated struct Comentario: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    let idReporte: Int64
    /// Alias, "Miembro de la comunidad", "Tú" o "Cuenta eliminada".
    let autor: String
    let esMio: Bool
    let texto: String
    let fecha: Date
}

nonisolated struct HistorialEstado: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    let idReporte: Int64
    /// Alias para el staff; "Equipo de moderación" para el autor (protege a quien modera).
    let responsable: String
    let anterior: EstadoReporte?
    let nuevo: EstadoReporte
    let observaciones: String?
    let fecha: Date
}

nonisolated struct Notificacion: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    let idReporte: Int64?
    let mensaje: String
    var leida: Bool
    let fecha: Date
}

nonisolated struct EstadisticasComunidad: Codable, Sendable, Hashable {
    var personasAyudadas: Int
    var reportesVerificados: Int
    var estafasDetenidas: Int
    var zonasCubiertas: Int
}

/// Una tarjeta de "Categorías principales" en Buscar.
nonisolated struct ConteoCategoria: Codable, Sendable, Hashable, Identifiable {
    let tipo: TipoFraude
    let total: Int
    let riesgoMaximo: NivelRiesgo

    var id: TipoFraude { tipo }
}
```

- [ ] **Paso 7: Implementar `Model/FiltroBusqueda.swift`**

```swift
//
//  FiltroBusqueda.swift
//  PrototipoApp
//
//  Qué busca la persona en Buscar: texto libre, tipos y riesgo mínimo. La misma regla se usa
//  en el servidor Demo y se documenta para el backend.
//

import Foundation

nonisolated struct FiltroBusqueda: Sendable, Hashable {
    var texto = ""
    var tipos: Set<TipoFraude> = []
    var riesgoMinimo: NivelRiesgo?

    var estaVacio: Bool {
        texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tipos.isEmpty && riesgoMinimo == nil
    }

    /// Todas las palabras del texto deben aparecer (sin importar mayúsculas ni acentos) en el
    /// título, la descripción, el tipo, la ciudad, la URL o el texto sospechoso.
    func coincide(_ r: Reporte) -> Bool {
        if !tipos.isEmpty && !tipos.contains(r.tipo) { return false }
        if let riesgoMinimo, r.nivelRiesgo < riesgoMinimo { return false }
        let palabras = Self.normalizar(texto).split(separator: " ")
        guard !palabras.isEmpty else { return true }
        let campos = [r.titulo, r.descripcion, r.tipoVisible, r.ciudad, r.sitio?.url ?? "", r.textoSospechoso ?? ""]
        let pajar = Self.normalizar(campos.joined(separator: " "))
        return palabras.allSatisfy { pajar.contains($0) }
    }

    static func normalizar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Formato.locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Paso 8: Implementar `Model/Formato.swift`**

```swift
//
//  Formato.swift
//  PrototipoApp
//
//  Fechas y números como los mostraba el storyboard ("Hace 2 horas", "1.2k", "4,302").
//

import Foundation

nonisolated enum Formato {
    static let locale = Locale(identifier: "es_MX")

    /// "Hace 2 horas", "Ayer", "Hace 3 días". Primera letra en mayúscula, como el storyboard.
    static func relativo(_ fecha: Date, ahora: Date = Date()) -> String {
        let formateador = RelativeDateTimeFormatter()
        formateador.locale = locale
        formateador.unitsStyle = .full
        formateador.dateTimeStyle = .named
        let texto = formateador.localizedString(for: fecha, relativeTo: ahora)
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }

    /// 340 → "340"; 1200 → "1.2k".
    static func conteoCorto(_ n: Int) -> String {
        guard n >= 1_000 else { return "\(n)" }
        let miles = (Double(n) / 1_000).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return miles + "k"
    }

    /// 4302 → "4,302".
    static func miles(_ n: Int) -> String {
        n.formatted(.number.locale(locale))
    }

    /// 123 → "#000123". Lo que ve la persona como número de folio.
    static func folio(_ id: Int64) -> String {
        "#" + String(format: "%06lld", id)
    }

    /// "4 oct 2026" para la fecha del incidente.
    static func fechaCorta(_ fecha: Date) -> String {
        fecha.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }
}
```

- [ ] **Paso 9: Correr las pruebas**

Run: `UNIT`
Expected: `** TEST SUCCEEDED **` (incluye `CatalogosTests`, `FiltroBusquedaTests`, `FormatoTests`). Si `relativoEnEspanolConMayuscula` falla por redacción distinta del sistema, revisar el texto real con un `#expect` que imprima `texto` y ajustar la prueba (no el formateador): lo importante es español y mayúscula inicial.

- [ ] **Paso 10: Build y commit**

Run: `BUILD` → `** BUILD SUCCEEDED **`

```bash
git add PrototipoApp/Model PrototipoAppTests
git commit -m "feat: modelos del dominio mapeados al esquema ZeroScam"
```

**Criterios de aceptación:** los `rawValue` coinciden con el SQL; la máquina de estados y el filtro tienen pruebas; ningún archivo de `Model/` nuevo importa SwiftUI (`grep -l "import SwiftUI" PrototipoApp/Model/*.swift` solo lista `Report.swift`, que se borra en F11).
**Dependencias:** Q1. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea D2: Contratos — errores, repositorios y estado de carga

**Objetivo:** fijar los protocolos que separan las vistas de la fuente de datos, el tipo de error con mensajes en español y el estado de carga que pintan las listas.

**Archivos:**
- Crear: `PrototipoApp/Model/AppError.swift`
- Crear: `PrototipoApp/Data/Repositories.swift`
- Crear: `PrototipoApp/Stores/Carga.swift`
- Test: `PrototipoAppTests/Model/AppErrorTests.swift`

**Interfaces:**
- Consume: D1.
- Produce: `AppError` (con `mensaje(ahora:)`), `Error.mensajeUsuario`, `ResultadoLogin`, `DesafioDosPasos`, `SesionActiva`, `AuthRepository`, `ReportRepository`, `ProfileRepository`, `NotificationRepository`, `AdminRepository`, `typealias Backend`, `Carga<Valor>` (`.cargando`, `.listo`, `.error`, `valor`).

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppTests/Model/AppErrorTests.swift`:

```swift
//
//  AppErrorTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct AppErrorTests {
    let ahora = Date(timeIntervalSince1970: 1_000)

    @Test func bloqueoRedondeaMinutosHaciaArriba() {
        #expect(AppError.cuentaBloqueada(hasta: ahora.addingTimeInterval(61)).mensaje(ahora: ahora)
                == "Demasiados intentos. Intenta de nuevo en 2 min.")
        #expect(AppError.cuentaBloqueada(hasta: ahora.addingTimeInterval(5)).mensaje(ahora: ahora)
                == "Demasiados intentos. Intenta de nuevo en 1 min.")
    }

    @Test func credencialesNoDicenCualFallo() {
        #expect(AppError.credencialesInvalidas.mensaje() == "Correo o contraseña incorrectos.")
    }

    @Test func errorDesconocidoTieneMensajeGenerico() {
        struct Otro: Error {}
        #expect(Otro().mensajeUsuario == "Ocurrió un error inesperado.")
        #expect(AppError.noEncontrado.mensajeUsuario == "Este contenido ya no está disponible.")
        #expect(AppError.validacion(["Uno.", "Dos."]).mensajeUsuario == "Uno.\nDos.")
    }

    @Test func cargaDevuelveValorSoloSiEstaLista() {
        #expect(Carga<Int>.listo(3).valor == 3)
        #expect(Carga<Int>.cargando.valor == nil)
        #expect(Carga<Int>.error("x").valor == nil)
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → Expected: FAIL `cannot find 'AppError' in scope`.

- [ ] **Paso 3: Implementar `Model/AppError.swift`**

```swift
//
//  AppError.swift
//  PrototipoApp
//
//  Errores que la persona puede ver. Mensajes en español, cortos, y sin revelar detalles útiles
//  para un atacante (por ejemplo, no se dice si falló el correo o la contraseña).
//

import Foundation

nonisolated enum AppError: Error, Equatable, Sendable {
    case credencialesInvalidas
    case cuentaBloqueada(hasta: Date)
    case cuentaSuspendida
    case sesionExpirada
    case codigoInvalido
    case sinPermiso
    case noEncontrado
    case conflicto(String)
    case validacion([String])
    case limiteExcedido(String)
    case sinConexion
    case servidor(String)

    func mensaje(ahora: Date = Date()) -> String {
        switch self {
        case .credencialesInvalidas:
            "Correo o contraseña incorrectos."
        case .cuentaBloqueada(let hasta):
            "Demasiados intentos. Intenta de nuevo en \(max(1, Int((hasta.timeIntervalSince(ahora) / 60).rounded(.up)))) min."
        case .cuentaSuspendida:
            "Tu cuenta está suspendida. Escríbenos para revisarla."
        case .sesionExpirada:
            "Tu sesión expiró. Inicia sesión de nuevo."
        case .codigoInvalido:
            "El código no es válido o ya expiró."
        case .sinPermiso:
            "No tienes permiso para hacer esto."
        case .noEncontrado:
            "Este contenido ya no está disponible."
        case .conflicto(let texto), .limiteExcedido(let texto), .servidor(let texto):
            texto
        case .validacion(let errores):
            errores.joined(separator: "\n")
        case .sinConexion:
            "No se pudo conectar con el servidor. Revisa tu conexión."
        }
    }
}

nonisolated extension Error {
    /// Mensaje listo para pantalla, venga de donde venga el error.
    var mensajeUsuario: String {
        (self as? AppError)?.mensaje() ?? "Ocurrió un error inesperado."
    }
}
```

- [ ] **Paso 4: Implementar `Data/Repositories.swift`**

```swift
//
//  Repositories.swift
//  PrototipoApp
//
//  El "enchufe" entre la app y sus datos. DemoBackend (servidor dentro de la app) y
//  RemoteBackend (API NestJS del Equipo ZeroScam) cumplen los mismos protocolos, así que las
//  pantallas no saben cuál se usa. Ningún método recibe el token: cada implementación lo lee
//  del SecretStore, como el interceptor de `api.ts` del demo del profesor.
//

import Foundation

nonisolated struct SesionActiva: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let usuario: Usuario
}

/// Verificación en dos pasos pendiente. `codigoDemo` solo existe en el modo Demo: es lo que en
/// producción llegaría por correo.
nonisolated struct DesafioDosPasos: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let destino: String
    let expira: Date
    let codigoDemo: String?
}

nonisolated enum ResultadoLogin: Sendable, Equatable {
    case sesion(SesionActiva)
    case requiereCodigo(DesafioDosPasos)
}

nonisolated protocol AuthRepository: Sendable {
    func registrar(_ datos: RegistroDatos) async throws -> Usuario
    func iniciarSesion(correo: String, contrasena: String) async throws -> ResultadoLogin
    func verificarCodigo(desafio: String, codigo: String) async throws -> SesionActiva
    func usuarioActual() async throws -> Usuario
    func cerrarSesion() async throws
    func cambiarContrasena(actual: String, nueva: String) async throws
    func eliminarCuenta(contrasena: String) async throws
}

nonisolated protocol ReportRepository: Sendable {
    /// Solo reportes VALIDADO y CANALIZADO.
    func feed(_ filtro: FiltroBusqueda) async throws -> [Reporte]
    func misReportes() async throws -> [Reporte]
    func guardados() async throws -> [Reporte]
    func detalle(id: Int64) async throws -> Reporte
    func crear(_ borrador: ReporteBorrador) async throws -> Reporte
    func actualizar(id: Int64, _ borrador: ReporteBorrador) async throws -> Reporte
    func eliminar(id: Int64) async throws
    /// Idempotente: marcar dos veces deja un solo guardado.
    func marcarGuardado(id: Int64, _ guardado: Bool) async throws
    /// "Yo también". Idempotente por usuario.
    func confirmar(id: Int64) async throws -> Reporte
    func comentarios(id: Int64) async throws -> [Comentario]
    func comentar(id: Int64, texto: String) async throws -> Comentario
    func eliminarComentario(id: Int64) async throws
    func historial(id: Int64) async throws -> [HistorialEstado]
    func estadisticas() async throws -> EstadisticasComunidad
    func categorias() async throws -> [ConteoCategoria]
    /// El archivo pasa por el servidor para revisar el permiso de quien lo pide.
    func datosEvidencia(_ evidencia: Evidencia) async throws -> Data
}

nonisolated protocol ProfileRepository: Sendable {
    func actualizarPerfil(_ datos: PerfilDatos) async throws -> Usuario
    /// `contrasena` es obligatoria para apagar la verificación en dos pasos.
    func actualizarPreferencias(_ preferencias: Preferencias, contrasena: String?) async throws -> Usuario
    func actualizarAvatar(_ adjunto: Adjunto?) async throws -> Usuario
    func datosAvatar(de usuario: Usuario) async throws -> Data?
    func exportarMisDatos() async throws -> Data
}

nonisolated protocol NotificationRepository: Sendable {
    func notificaciones() async throws -> [Notificacion]
    func marcarLeidas(_ ids: [Int64]) async throws
}

nonisolated protocol AdminRepository: Sendable {
    /// `nil` = pendientes (RECIBIDO y EN_REVISION).
    func colaModeracion(estado: EstadoReporte?) async throws -> [Reporte]
    func cambiarEstado(id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) async throws -> Reporte
    func usuarios() async throws -> [Usuario]
    func cambiarRol(idUsuario: Int64, a rol: Rol) async throws -> Usuario
    func cambiarEstadoCuenta(idUsuario: Int64, a estado: EstadoCuenta) async throws -> Usuario
    func analiticas() async throws -> [String: Int]
    /// Solo existe en el modo Demo.
    func restablecerDemo() async throws
}

typealias Backend = AuthRepository & ReportRepository & ProfileRepository & NotificationRepository & AdminRepository
```

- [ ] **Paso 5: Implementar `Stores/Carga.swift`**

```swift
//
//  Carga.swift
//  PrototipoApp
//
//  Estado de algo que se pide al backend. Las vistas lo pintan con `CargaView`
//  (Theme/EstadosVista.swift): indicador, contenido, vacío o error con "Reintentar".
//

import Foundation

nonisolated enum Carga<Valor> {
    case cargando
    case listo(Valor)
    case error(String)

    var valor: Valor? {
        if case .listo(let valor) = self { return valor }
        return nil
    }
}

nonisolated extension Carga: Equatable where Valor: Equatable {}
nonisolated extension Carga: Sendable where Valor: Sendable {}
```

- [ ] **Paso 6: Correr pruebas y build** — Run: `UNIT` → `** TEST SUCCEEDED **`; `BUILD` → `** BUILD SUCCEEDED **`.

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp/Model/AppError.swift PrototipoApp/Data/Repositories.swift PrototipoApp/Stores/Carga.swift PrototipoAppTests/Model/AppErrorTests.swift
git commit -m "feat: protocolos de repositorio, errores y estado de carga"
```

**Criterios de aceptación:** compilan los 5 protocolos y `Backend`; mensajes en español probados.
**Dependencias:** D1. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea D3: Base de datos del modo Demo y su archivo

**Objetivo:** definir las "filas" que guarda el servidor Demo (espejo de las tablas) y guardarlas en un JSON protegido que se puede reiniciar.

**Archivos:**
- Crear: `PrototipoApp/Data/Codificacion.swift`
- Crear: `PrototipoApp/Data/Demo/DemoDatabase.swift`
- Crear: `PrototipoApp/Data/Demo/DemoAlmacen.swift`
- Test: `PrototipoAppTests/Data/DemoAlmacenTests.swift`

**Interfaces:**
- Consume: D1 (modelos), S5 (`RegistroIntentos`).
- Produce: `Codificacion.encoder()`, `Codificacion.decoder()` (ISO-8601 con y sin milisegundos), `DemoDatabase` (con `siguienteID()` y `versionActual`), `UsuarioFila`, `SesionFila`, `DesafioFila`, `ReporteFila`, `EvidenciaFila` (con `evidencia`), `HistorialFila`, `NotificacionFila`, `ComentarioFila`, `ParUsuarioReporte`, `DemoAlmacen` (`cargar()`, `guardar(_:)`, `borrarTodo()`, `carpetaPorDefecto(nombre:)`).

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppTests/Data/DemoAlmacenTests.swift`:

```swift
//
//  DemoAlmacenTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoAlmacenTests {
    let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-almacen-\(UUID().uuidString)")

    @Test func sinArchivoDevuelveNil() {
        #expect(DemoAlmacen(carpeta: carpeta).cargar() == nil)
    }

    @Test func guardarYCargarConservaLosDatos() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        var db = DemoDatabase()
        let id = db.siguienteID()
        db.analiticas["busqueda"] = 3
        db.intentos["a@b.mx"] = RegistroIntentos(fallidos: 2, bloqueadoHasta: nil)
        try almacen.guardar(db)
        let leida = try #require(almacen.cargar())
        #expect(id == 1_001)
        #expect(leida.ultimoID == 1_001)
        #expect(leida.analiticas["busqueda"] == 3)
        #expect(leida.intentos["a@b.mx"]?.fallidos == 2)
    }

    @Test func elArchivoNoViajaEnRespaldos() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        try almacen.guardar(DemoDatabase())
        let valores = try almacen.archivo.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(valores.isExcludedFromBackup == true)
    }

    @Test func archivoDanadoSeAparteYDevuelveNil() throws {
        let almacen = DemoAlmacen(carpeta: carpeta)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try Data("{no es json".utf8).write(to: almacen.archivo)
        #expect(almacen.cargar() == nil)
        #expect(FileManager.default.fileExists(atPath: carpeta.appending(path: "zeroscam-demo.corrupto.json").path()))
    }

    @Test func fechasConMilisegundosSeLeen() throws {
        let json = Data(#""2026-10-07T12:00:00.123Z""#.utf8)
        let fecha = try Codificacion.decoder().decode(Date.self, from: json)
        #expect(fecha.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) > 0.1)
        let sinMilis = try Codificacion.decoder().decode(Date.self, from: Data(#""2026-10-07T12:00:00Z""#.utf8))
        #expect(sinMilis < fecha)
    }
}
```

`DemoDatabase` no es `Equatable`; las pruebas comparan campos. Para `#expect(... == nil)` con un opcional de un tipo no `Equatable`, usar `#expect(almacen.cargar() == nil)` funciona porque Swift compara `Optional` con `nil` sin `Equatable`.

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → FAIL `cannot find 'DemoAlmacen' in scope`.

- [ ] **Paso 3: Implementar `Data/Codificacion.swift`**

```swift
//
//  Codificacion.swift
//  PrototipoApp
//
//  JSON con fechas ISO-8601, igual para el archivo del modo Demo y para la API. Se aceptan
//  fechas con milisegundos porque así las manda `Date.toISOString()` en NestJS.
//

import Foundation

nonisolated enum Codificacion {
    private static let conMilisegundos = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let sinMilisegundos = Date.ISO8601FormatStyle()

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { fecha, encoder in
            var contenedor = encoder.singleValueContainer()
            try contenedor.encode(fecha.formatted(conMilisegundos))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let contenedor = try decoder.singleValueContainer()
            let texto = try contenedor.decode(String.self)
            if let fecha = try? conMilisegundos.parse(texto) { return fecha }
            if let fecha = try? sinMilisegundos.parse(texto) { return fecha }
            throw DecodingError.dataCorruptedError(in: contenedor, debugDescription: "Fecha no ISO-8601")
        }
        return decoder
    }
}
```

- [ ] **Paso 4: Implementar `Data/Demo/DemoDatabase.swift`**

```swift
//
//  DemoDatabase.swift
//  PrototipoApp
//
//  Las "tablas" del modo Demo. Cada fila es el espejo de una tabla de ZeroScam (o de las
//  propuestas en database/zeroscam_migracion_0fraude.sql). A diferencia de los modelos de
//  Model/, las filas guardan todo: el hash de la contraseña, el autor real de un anónimo.
//

import Foundation

nonisolated struct UsuarioFila: Codable, Sendable {
    var usuario: Usuario
    var contrasenaHash: String
}

/// Tabla `Sesion`: solo el SHA-256 del token, nunca el token.
nonisolated struct SesionFila: Codable, Sendable {
    let tokenHash: String
    let idUsuario: Int64
    let creada: Date
    let expira: Date
}

/// Tabla `Desafio_DosPasos`: el código de 6 dígitos también se guarda como SHA-256.
nonisolated struct DesafioFila: Codable, Sendable {
    let id: String
    let idUsuario: Int64
    let codigoHash: String
    let expira: Date
    var intentos: Int
}

nonisolated struct ReporteFila: Codable, Sendable {
    let id: Int64
    /// `nil` cuando la cuenta se eliminó y el reporte público se anonimizó.
    var idUsuario: Int64?
    var tipo: TipoFraude
    var tipoOtro: String?
    var estado: EstadoReporte
    var titulo: String
    var descripcion: String
    var fechaIncidente: Date
    var nivelRiesgo: NivelRiesgo
    let fechaCreacion: Date
    var esAnonimo: Bool
    var afectado: Afectado
    var ciudad: String
    var persona: PersonaAfectada?
    /// Tabla `Reporte_URL` (la app usa un sitio por reporte).
    var idSitio: Int64?
    var textoSospechoso: String?
    /// Solo datos semilla: conteo histórico de "Yo también". En MySQL es COUNT(*) de Reporte_Confirmacion.
    var confirmacionesPrevias: Int = 0
}

nonisolated struct EvidenciaFila: Codable, Sendable {
    let id: Int64
    let idReporte: Int64
    let rutaArchivo: String
    let tipoArchivo: String
    let fechaCarga: Date

    var evidencia: Evidencia {
        Evidencia(id: id, rutaArchivo: rutaArchivo, tipoArchivo: tipoArchivo, fechaCarga: fechaCarga)
    }
}

nonisolated struct HistorialFila: Codable, Sendable {
    let id: Int64
    let idReporte: Int64
    let idResponsable: Int64
    let anterior: EstadoReporte?
    let nuevo: EstadoReporte
    let observaciones: String?
    let fecha: Date
}

nonisolated struct NotificacionFila: Codable, Sendable {
    let id: Int64
    let idUsuario: Int64
    var idReporte: Int64?
    let mensaje: String
    var leida: Bool
    let fecha: Date
}

nonisolated struct ComentarioFila: Codable, Sendable {
    let id: Int64
    let idReporte: Int64
    var idUsuario: Int64?
    let texto: String
    let fecha: Date
}

/// Tablas `Reporte_Guardado` y `Reporte_Confirmacion`.
nonisolated struct ParUsuarioReporte: Codable, Sendable, Hashable {
    let idUsuario: Int64
    let idReporte: Int64
    let fecha: Date
}

nonisolated struct DemoDatabase: Codable, Sendable {
    /// Si cambia la forma del archivo, se sube y la app vuelve a sembrar.
    static let versionActual = 1

    var version = DemoDatabase.versionActual
    var ultimoID: Int64 = 1_000
    var usuarios: [UsuarioFila] = []
    /// Intentos de login por correo normalizado (exista o no la cuenta).
    var intentos: [String: RegistroIntentos] = [:]
    var sesiones: [SesionFila] = []
    var desafios: [DesafioFila] = []
    var reportes: [ReporteFila] = []
    var sitios: [SitioWeb] = []
    var evidencias: [EvidenciaFila] = []
    var historial: [HistorialFila] = []
    var notificaciones: [NotificacionFila] = []
    var comentarios: [ComentarioFila] = []
    var guardados: [ParUsuarioReporte] = []
    var confirmaciones: [ParUsuarioReporte] = []
    /// Contadores anónimos (sin id de usuario).
    var analiticas: [String: Int] = [:]

    mutating func siguienteID() -> Int64 {
        ultimoID += 1
        return ultimoID
    }
}
```

- [ ] **Paso 5: Implementar `Data/Demo/DemoAlmacen.swift`**

```swift
//
//  DemoAlmacen.swift
//  PrototipoApp
//
//  Lee y escribe la base del modo Demo en Application Support. El archivo queda cifrado por iOS
//  mientras el teléfono está bloqueado (`.completeFileProtection`) y fuera de los respaldos.
//

import Foundation

nonisolated struct DemoAlmacen: Sendable {
    let carpeta: URL

    var archivo: URL { carpeta.appending(path: "zeroscam-demo.json") }

    /// `nil` si todavía no hay base, o si estaba dañada (se aparta como `.corrupto` y se vuelve a sembrar).
    func cargar() -> DemoDatabase? {
        guard let datos = try? Data(contentsOf: archivo) else { return nil }
        do {
            return try Codificacion.decoder().decode(DemoDatabase.self, from: datos)
        } catch {
            let apartado = carpeta.appending(path: "zeroscam-demo.corrupto.json")
            try? FileManager.default.removeItem(at: apartado)
            try? FileManager.default.moveItem(at: archivo, to: apartado)
            return nil
        }
    }

    func guardar(_ db: DemoDatabase) throws {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let datos = try Codificacion.encoder().encode(db)
        try datos.write(to: archivo, options: [.atomic, .completeFileProtection])
        var url = archivo
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        try url.setResourceValues(valores)
    }

    func borrarTodo() throws {
        guard FileManager.default.fileExists(atPath: carpeta.path()) else { return }
        try FileManager.default.removeItem(at: carpeta)
    }

    static func carpetaPorDefecto(nombre: String = "ZeroScamDemo") -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: nombre, directoryHint: .isDirectory)
    }
}
```

- [ ] **Paso 6: Pruebas y build** — Run: `UNIT` → `** TEST SUCCEEDED **`; `BUILD` → `** BUILD SUCCEEDED **`.

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp/Data PrototipoAppTests/Data
git commit -m "feat: base y almacenamiento del modo Demo"
```

**Criterios de aceptación:** ida y vuelta al disco sin pérdida; archivo dañado no tumba la app; excluido de respaldos.
**Dependencias:** D1, S5. **Esfuerzo:** S. **Riesgo:** bajo. (La protección de datos no se aplica de verdad en el simulador; ver sección 10.)

### Tarea D4: Datos semilla

**Objetivo:** sembrar la base de la demo con usuarios, reportes, comentarios, guardados, historial y notificaciones coherentes con los textos del storyboard, con fechas relativas al día en que corre la app.

**Archivos:**
- Crear: `PrototipoApp/Data/Demo/DemoSeed.swift`
- Modificar: `PrototipoApp/Model/Usuario.swift` (agregar `Consentimiento.versionAvisoVigente`)
- Test: `PrototipoAppTests/Data/DemoSeedTests.swift`

**Interfaces:**
- Consume: D3, S1 (formato de hash), S3 (`Validador` en la prueba), S4 (`URLTools.estadoCertificado`).
- Produce: `DemoSeed.base(ahora:) -> DemoDatabase`, `DemoSeed.hashSenuelo`, ids `DemoSeed.idOwner` (1), `idAdmin` (2), `idUsuario` (3), `idTecno` (4), `idCompras` (5), `idVecina` (6); `Consentimiento.versionAvisoVigente = "2026-10"`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppTests/Data/DemoSeedTests.swift`:

```swift
//
//  DemoSeedTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoSeedTests {
    let ahora = Date(timeIntervalSince1970: 1_791_072_000)
    var db: DemoDatabase { DemoSeed.base(ahora: ahora) }

    @Test func seisUsuariosConSusRoles() {
        let roles = db.usuarios.map(\.usuario.rol)
        #expect(roles.count == 6)
        #expect(roles.filter { $0 == .owner }.count == 1)
        #expect(roles.filter { $0 == .administrador }.count == 1)
        #expect(roles.filter { $0 == .usuario }.count == 4)
    }

    @Test func aliasYCorreosValidosYUnicos() {
        let usuarios = db.usuarios.map(\.usuario)
        #expect(Set(usuarios.map(\.alias)).count == usuarios.count)
        #expect(Set(usuarios.map(\.correo)).count == usuarios.count)
        for u in usuarios {
            #expect(Validador.esAliasValido(u.alias))
            #expect(Validador.esCorreoValido(u.correo))
        }
    }

    @Test func veintitresReportesYDiecisietePublicos() {
        #expect(db.reportes.count == 23)
        #expect(db.reportes.filter { $0.estado.esPublico }.count == 17)
        #expect(db.reportes.filter { $0.idUsuario == DemoSeed.idUsuario }.count == 3)
    }

    @Test func lasAlertasCriticasSonLasDelStoryboard() {
        let criticas = db.reportes
            .filter { $0.estado.esPublico && $0.nivelRiesgo >= .alto }
            .sorted { $0.fechaCreacion > $1.fechaCreacion }
            .prefix(2)
            .map(\.titulo)
        #expect(criticas == ["Falsa liquidación de tienda de electrónica", "Sorteo falso de iPhone 17 en Instagram"])
    }

    @Test func nadaOcurreEnElFuturo() {
        let base = db
        #expect(base.reportes.allSatisfy { $0.fechaCreacion <= ahora && $0.fechaIncidente <= $0.fechaCreacion })
        #expect(base.historial.allSatisfy { $0.fecha <= ahora })
        #expect(base.comentarios.allSatisfy { $0.fecha <= ahora })
        #expect(base.notificaciones.allSatisfy { $0.fecha <= ahora })
    }

    @Test func cadaReporteTieneSuRegistroInicial() {
        let base = db
        for r in base.reportes {
            #expect(base.historial.contains { $0.idReporte == r.id && $0.anterior == nil && $0.nuevo == .recibido })
            #expect(base.historial.filter { $0.idReporte == r.id }.last?.nuevo == r.estado)
        }
    }

    @Test func idsUnicosYMenoresAlContador() {
        let base = db
        let ids = base.reportes.map(\.id) + base.sitios.map(\.id) + base.comentarios.map(\.id)
            + base.historial.map(\.id) + base.notificaciones.map(\.id) + base.usuarios.map(\.usuario.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0 < base.ultimoID })
    }

    @Test func elUsuarioDemoTieneDosGuardadosYUnaNotificacionSinLeer() {
        let base = db
        #expect(base.guardados.filter { $0.idUsuario == DemoSeed.idUsuario }.map(\.idReporte).sorted() == [101, 102])
        #expect(base.notificaciones.filter { $0.idUsuario == DemoSeed.idUsuario && !$0.leida }.count == 1)
    }

    @Test func lasContrasenasDemoCoincidenConSusHashes() {
        let hasher = PasswordHasher()
        let porCorreo = Dictionary(uniqueKeysWithValues: db.usuarios.map { ($0.usuario.correo, $0.contrasenaHash) })
        #expect(hasher.verificar("Alerta#2026mx", contra: porCorreo["usuario@0fraude.mx"] ?? ""))
        #expect(hasher.verificar("Revisa#2026zs", contra: porCorreo["admin@0fraude.mx"] ?? ""))
        #expect(hasher.verificar("Equipo#2026zs", contra: porCorreo["owner@0fraude.mx"] ?? ""))
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → FAIL `cannot find 'DemoSeed' in scope`.

- [ ] **Paso 3: Agregar la versión del aviso** al final de `Model/Usuario.swift`:

```swift
nonisolated extension Consentimiento {
    /// Versión del aviso de privacidad que muestra PrivacyNoticeView.
    static let versionAvisoVigente = "2026-10"
}
```

- [ ] **Paso 4: Implementar `Data/Demo/DemoSeed.swift`**

```swift
//
//  DemoSeed.swift
//  PrototipoApp
//
//  Datos de la demo. Los textos de los dos primeros reportes, los comentarios y las tarjetas de
//  Perfil son los que tenía el storyboard. Las fechas se calculan desde `ahora` para que
//  "Hace 2 horas" sea cierto el día de la presentación.
//
//  Las contraseñas de las cuentas demo NO están aquí: solo sus hashes PBKDF2-SHA256
//  (600,000 iteraciones, sal aleatoria), calculados fuera de la app. Las contraseñas en claro
//  viven en docs/guion-demo.md.
//

import Foundation

nonisolated enum DemoSeed {
    static let idOwner: Int64 = 1
    static let idAdmin: Int64 = 2
    static let idUsuario: Int64 = 3
    static let idTecno: Int64 = 4
    static let idCompras: Int64 = 5
    static let idVecina: Int64 = 6

    static let hashOwner = "pbkdf2_sha256$600000$jLfdF7XXpo7+yGzj7AP+qA==$kv1QRnSEaFGTrdbt+sICBDJDIb+0z35QnAt69dKwbh0="
    static let hashAdmin = "pbkdf2_sha256$600000$tRxYQ70uziOMJwbsrjhnyg==$90si70ftfbUHLNKqU8LixNK+wQQKvTY817tpFZI9tlM="
    static let hashUsuario = "pbkdf2_sha256$600000$YG0lXKYMt2EqBJS/FHKHdw==$MX8+gfnIAvPJ7MMHppcuP9k71czuGFuOnc/dX95FdEA="
    /// Miembros de la comunidad: contraseñas aleatorias que nadie conoce (no pueden iniciar sesión).
    static let hashesComunidad = [
        "pbkdf2_sha256$600000$7I7k7QoVpZg4IrcQWkRzOQ==$S26efn3ok0EY0W7gcb1VYNE8lBfkHjVMKsJFJ9FBu9I=",
        "pbkdf2_sha256$600000$htRIMk5PZLK/c32QgxLraA==$IzY0HGgLN975YBO4Rpk2mvKWSy8JzRnzx8ziBbLS4UA=",
        "pbkdf2_sha256$600000$QravxlxFw9LjLTNZSsJQBQ==$mTZLYwS46p2RPMJtMRl1eFtuWfx52658NfYNxpP8QjM=",
    ]
    /// Si el correo no existe, el login verifica contra este hash para tardar lo mismo.
    static let hashSenuelo = "pbkdf2_sha256$600000$G0qVo7uOEw/iUwAp8cOd9Q==$Up9fhb3Z6ZQB+wKO7OabOJUFnrFtECznXvopyUTlyhg="

    private nonisolated struct Semilla {
        let id: Int64
        let autor: Int64
        let tipo: TipoFraude
        var tipoOtro: String? = nil
        let estado: EstadoReporte
        let riesgo: NivelRiesgo
        let ciudad: String
        /// Antigüedad en horas.
        let horas: Double
        let titulo: String
        let descripcion: String
        var url: String? = nil
        var texto: String? = nil
        var anonimo = false
        var persona: PersonaAfectada? = nil
        var previas = 0
        var motivoRechazo: String? = nil
    }

    static func base(ahora: Date) -> DemoDatabase {
        var db = DemoDatabase()
        func hace(_ horas: Double) -> Date { ahora.addingTimeInterval(-horas * 3_600) }

        db.usuarios = [
            fila(idOwner, .owner, "Equipo", "ZeroScam", "owner_zs", "owner@0fraude.mx", publico: true, dias: 120, hashOwner, ahora),
            fila(idAdmin, .administrador, "Carlos", "Méndez", "admin_zs", "admin@0fraude.mx", publico: true, dias: 90, hashAdmin, ahora),
            fila(idUsuario, .usuario, "Ana", "López", "usuario_01", "usuario@0fraude.mx", publico: false, dias: 30, hashUsuario, ahora),
            fila(idTecno, .usuario, "Luis", "Herrera", "tecno_mx", "luis@comunidad.test", publico: true, dias: 60, hashesComunidad[0], ahora),
            fila(idCompras, .usuario, "Marta", "Ruiz", "compras_seguras", "marta@comunidad.test", publico: true, dias: 45, hashesComunidad[1], ahora),
            fila(idVecina, .usuario, "Sofía", "Ramírez", "vecina_alerta", "sofia@comunidad.test", publico: false, dias: 20, hashesComunidad[2], ahora),
        ]
        db.usuarios[2].usuario.biografia = "Me interesa alertar sobre compras en línea."

        var idSitio: Int64 = 200
        var idHistorial: Int64 = 400
        for s in semillas {
            var sitio: Int64?
            if let url = s.url {
                idSitio += 1
                sitio = idSitio
                db.sitios.append(SitioWeb(id: idSitio, url: url,
                                          nivelRiesgoGlobal: s.estado.esPublico ? s.riesgo : .bajo,
                                          estadoCertificado: URLTools.estadoCertificado(url),
                                          fechaUltimaEvaluacion: s.estado.esPublico ? hace(max(0, s.horas - 1)) : nil))
            }
            let creado = hace(s.horas)
            db.reportes.append(ReporteFila(id: s.id, idUsuario: s.autor, tipo: s.tipo, tipoOtro: s.tipoOtro,
                                           estado: s.estado, titulo: s.titulo, descripcion: s.descripcion,
                                           fechaIncidente: creado.addingTimeInterval(-6 * 3_600),
                                           nivelRiesgo: s.riesgo, fechaCreacion: creado, esAnonimo: s.anonimo,
                                           afectado: s.persona == nil ? .yo : .otraPersona, ciudad: s.ciudad,
                                           persona: s.persona, idSitio: sitio,
                                           textoSospechoso: s.texto, confirmacionesPrevias: s.previas))
            // Historial: RECIBIDO al crearse y luego cada paso hasta su estado actual, repartido en su antigüedad.
            let ruta = rutaDeEstados(hasta: s.estado)
            let paso = min(3_600, s.horas * 3_600 / Double(max(ruta.count, 1)))
            var anterior: EstadoReporte?
            for (i, estado) in ruta.enumerated() {
                idHistorial += 1
                db.historial.append(HistorialFila(
                    id: idHistorial, idReporte: s.id,
                    idResponsable: i == 0 ? s.autor : idAdmin,
                    anterior: anterior, nuevo: estado,
                    observaciones: i == 0 ? "Reporte creado" : (estado == .rechazado ? s.motivoRechazo : nil),
                    fecha: creado.addingTimeInterval(Double(i) * paso)))
                anterior = estado
            }
        }

        db.comentarios = [
            ComentarioFila(id: 301, idReporte: 101, idUsuario: idVecina, texto: "Casi compro ahí, los precios se veían muy reales. Por suerte busqué reseñas antes.", fecha: hace(0.25)),
            ComentarioFila(id: 302, idReporte: 101, idUsuario: idCompras, texto: "A mi papá casi le cae, vio el anuncio en Facebook y ya iba a pagar.", fecha: hace(1)),
            ComentarioFila(id: 303, idReporte: 102, idUsuario: idTecno, texto: "Igual me escribieron a mí; la cuenta tiene muy pocos seguidores.", fecha: hace(3)),
            ComentarioFila(id: 304, idReporte: 122, idUsuario: idVecina, texto: "Gracias por avisar, vi la misma cuenta ayer.", fecha: hace(20)),
            ComentarioFila(id: 305, idReporte: 113, idUsuario: idCompras, texto: "El dominio termina en .store; la tienda real no usa ese.", fecha: hace(200)),
        ]
        db.guardados = [
            ParUsuarioReporte(idUsuario: idUsuario, idReporte: 101, fecha: hace(1)),
            ParUsuarioReporte(idUsuario: idUsuario, idReporte: 102, fecha: hace(2)),
        ]
        db.notificaciones = [
            NotificacionFila(id: 501, idUsuario: idUsuario, idReporte: 122,
                             mensaje: "Tu reporte «Oferta falsa 2x1 en boletos de concierto por Instagram» fue VALIDADO y ya es visible para la comunidad.",
                             leida: true, fecha: hace(28)),
            NotificacionFila(id: 502, idUsuario: idUsuario, idReporte: 121,
                             mensaje: "Tu reporte «Descuento falso de laptop en tienda clonada» está EN REVISIÓN.",
                             leida: false, fecha: hace(2)),
        ]
        return db
    }

    private static func fila(_ id: Int64, _ rol: Rol, _ nombre: String, _ apellido: String, _ alias: String,
                             _ correo: String, publico: Bool, dias: Double, _ hash: String, _ ahora: Date) -> UsuarioFila {
        let registro = ahora.addingTimeInterval(-dias * 86_400)
        let usuario = Usuario(id: id, rol: rol, nombre: nombre, apellido: apellido, pais: "México", alias: alias,
                              correo: correo, biografia: "", avatarRuta: nil, estadoCuenta: .activo,
                              fechaRegistro: registro, preferencias: Preferencias(perfilPublico: publico),
                              consentimiento: Consentimiento(versionAviso: Consentimiento.versionAvisoVigente, fecha: registro))
        return UsuarioFila(usuario: usuario, contrasenaHash: hash)
    }

    private static func rutaDeEstados(hasta estado: EstadoReporte) -> [EstadoReporte] {
        switch estado {
        case .recibido: [.recibido]
        case .enRevision: [.recibido, .enRevision]
        case .validado: [.recibido, .enRevision, .validado]
        case .rechazado: [.recibido, .enRevision, .rechazado]
        case .canalizado: [.recibido, .enRevision, .validado, .canalizado]
        }
    }

    // Tabla completa con justificación en el apéndice A del plan.
    private static let semillas: [Semilla] = [
        Semilla(id: 101, autor: idTecno, tipo: .ofertaFalsa, estado: .validado, riesgo: .alto, ciudad: "CDMX", horas: 2,
                titulo: "Falsa liquidación de tienda de electrónica",
                descripcion: "Una tienda online clonada está ofreciendo laptops y celulares con descuentos de hasta el 80%. Los usuarios pagan pero nunca reciben el producto, y el sitio desaparece días después.",
                url: "https://liquidacion-electronica-mx.shop", previas: 1_200),
        Semilla(id: 102, autor: idCompras, tipo: .sorteoFalso, estado: .validado, riesgo: .alto, ciudad: "Guadalajara", horas: 5,
                titulo: "Sorteo falso de iPhone 17 en Instagram",
                descripcion: "Cuentas falsas piden tus datos para 'reclamar' un premio que no existe. Después piden un pago de envío.",
                url: "https://instagram.com/iphone17.sorteo.oficial", previas: 450),
        Semilla(id: 103, autor: idTecno, tipo: .tiendaClonada, estado: .canalizado, riesgo: .muyAlto, ciudad: "Monterrey", horas: 26,
                titulo: "Tienda clonada de tenis deportivos",
                descripcion: "El sitio copia el diseño de una marca deportiva y vende tenis a mitad de precio. Solo acepta transferencia y nunca entrega.",
                url: "https://n1ke-outlet-mexico.com", previas: 610),
        Semilla(id: 104, autor: idVecina, tipo: .marketplace, estado: .validado, riesgo: .bajo, ciudad: "Puebla", horas: 30,
                titulo: "Vendedor de consolas que no entrega",
                descripcion: "Un perfil en Facebook Marketplace pide anticipo para apartar consolas y luego deja de responder.",
                texto: "Perfil 'Gamer Store MX' en Facebook Marketplace", previas: 85),
        Semilla(id: 105, autor: idCompras, tipo: .llamada, estado: .validado, riesgo: .alto, ciudad: "CDMX", horas: 50,
                titulo: "Llamada falsa del SAT pidiendo pago de multa",
                descripcion: "Llaman diciendo ser del SAT y exigen pagar una multa por transferencia ese mismo día para evitar una auditoría.",
                texto: "+52 55 8765 4321", previas: 390),
        Semilla(id: 106, autor: idVecina, tipo: .ofertaFalsa, estado: .validado, riesgo: .medio, ciudad: "Querétaro", horas: 72,
                titulo: "Cupón falso de supermercado por WhatsApp",
                descripcion: "Circula un mensaje con un cupón de $1,500 que pide llenar una encuesta con datos personales y de tarjeta.",
                url: "http://cupones-supermercado-mx.info", previas: 270),
        Semilla(id: 107, autor: idTecno, tipo: .sorteoFalso, estado: .canalizado, riesgo: .alto, ciudad: "Mérida", horas: 96,
                titulo: "Rifa falsa de automóvil en TikTok",
                descripcion: "Una cuenta vende boletos para rifar un auto; el sorteo nunca ocurre y la cuenta cambia de nombre.",
                url: "https://tiktok.com/@rifas.autos.mx", previas: 180),
        Semilla(id: 108, autor: idCompras, tipo: .otro, tipoOtro: "Phishing bancario", estado: .validado, riesgo: .muyAlto, ciudad: "CDMX", horas: 120,
                titulo: "Página clonada de banco para 'actualizar datos'",
                descripcion: "Un SMS lleva a una página idéntica a la de un banco que pide usuario, contraseña y el código que llega por mensaje.",
                url: "http://banco-actualiza-datos.com", previas: 520),
        Semilla(id: 109, autor: idVecina, tipo: .marketplace, estado: .validado, riesgo: .medio, ciudad: "Guadalajara", horas: 144,
                titulo: "Renta de departamento inexistente",
                descripcion: "Publican un departamento con fotos robadas y piden depósito y primer mes antes de mostrarlo.",
                texto: "Anuncio en Marketplace con depósito por adelantado", previas: 95),
        Semilla(id: 110, autor: idTecno, tipo: .otro, tipoOtro: "Empleo falso", estado: .validado, riesgo: .medio, ciudad: "Tijuana", horas: 168,
                titulo: "Ofertas de empleo falsas por WhatsApp",
                descripcion: "Ofrecen trabajo desde casa dando 'likes' y luego piden una inversión para seguir cobrando.",
                texto: "+52 664 000 1122", previas: 140),
        Semilla(id: 111, autor: idCompras, tipo: .ofertaFalsa, estado: .canalizado, riesgo: .alto, ciudad: "Monterrey", horas: 216,
                titulo: "Boletos de concierto en preventa falsa",
                descripcion: "Un sitio vende boletos en 'preventa exclusiva'; los códigos QR son falsos y no permiten entrar.",
                url: "https://boletos-preventa-mx.com", previas: 230),
        Semilla(id: 112, autor: idVecina, tipo: .llamada, estado: .validado, riesgo: .alto, ciudad: "Puebla", horas: 240,
                titulo: "Llamada de falso familiar detenido",
                descripcion: "Llaman haciéndose pasar por un familiar detenido y piden dinero urgente para 'arreglar' la situación.",
                texto: "Extorsión telefónica desde número desconocido", previas: 160),
        Semilla(id: 113, autor: idTecno, tipo: .tiendaClonada, estado: .validado, riesgo: .alto, ciudad: "CDMX", horas: 288,
                titulo: "Tienda clonada de Mercado Libre",
                descripcion: "Un dominio parecido al de Mercado Libre muestra ofertas falsas y pide pagar fuera de la plataforma.",
                url: "https://mercadolibre-ofertas.store", previas: 300),
        Semilla(id: 114, autor: idCompras, tipo: .sorteoFalso, estado: .validado, riesgo: .bajo, ciudad: "León", horas: 336,
                titulo: "Sorteo falso de despensa por aniversario",
                descripcion: "Una página promete despensas gratis a quien comparta la publicación y registre su CURP.",
                url: "https://facebook.com/despensas.gratis.mx", previas: 60),
        Semilla(id: 115, autor: idVecina, tipo: .otro, tipoOtro: "Préstamo falso", estado: .canalizado, riesgo: .alto, ciudad: "Oaxaca", horas: 384,
                titulo: "Préstamo falso con anticipo",
                descripcion: "Prometen un préstamo sin buró si primero pagas una 'comisión de apertura'; después desaparecen.",
                url: "https://prestamos-rapidos-mx.net", previas: 210),
        Semilla(id: 116, autor: idTecno, tipo: .ofertaFalsa, estado: .validado, riesgo: .medio, ciudad: "Toluca", horas: 480,
                titulo: "Descuentos de 90% en perfumes por Instagram",
                descripcion: "Una cuenta vende perfumes de marca al 90% de descuento y solo acepta depósitos en tiendas de conveniencia.",
                url: "https://instagram.com/perfumes.outlet.90", previas: 120),
        // Cola de moderación (no públicos)
        Semilla(id: 117, autor: idVecina, tipo: .otro, tipoOtro: "Smishing", estado: .recibido, riesgo: .noEvaluado, ciudad: "CDMX", horas: 1,
                titulo: "Mensaje de paquetería para pagar envío",
                descripcion: "Llega un SMS diciendo que un paquete está retenido y pide pagar $35 de envío en un enlace.",
                url: "http://paqueteria-entregas-mx.co", anonimo: true),
        Semilla(id: 118, autor: idCompras, tipo: .marketplace, estado: .enRevision, riesgo: .noEvaluado, ciudad: "Monterrey", horas: 20,
                titulo: "Venta de mascotas con depósito",
                descripcion: "Venden cachorros de raza a buen precio y piden depósito para apartar; luego piden más pagos de vacunas y envío.",
                texto: "Perfil 'Criadero Norte' en redes",
                persona: PersonaAfectada(nombre: "Rosa Martínez", contacto: "+52 81 5555 0101", autorizo: true)),
        Semilla(id: 119, autor: idTecno, tipo: .otro, tipoOtro: "Phishing de programa social", estado: .recibido, riesgo: .noEvaluado, ciudad: "Puebla", horas: 8,
                titulo: "Supuesta beca del gobierno pide CURP",
                descripcion: "Un mensaje promete una beca y pide CURP, INE y datos bancarios en un formulario.",
                url: "https://becas-bienestar-registro.com"),
        Semilla(id: 120, autor: idVecina, tipo: .otro, tipoOtro: "Cadena", estado: .rechazado, riesgo: .noEvaluado, ciudad: "León", horas: 72,
                titulo: "Mensaje de cadena sin datos",
                descripcion: "Me llegó una cadena diciendo que hay fraudes, pero no trae enlace ni número.",
                motivoRechazo: "No incluye datos verificables (enlace, número o captura)."),
        // Reportes del usuario demo (Perfil → Mis reportes)
        Semilla(id: 121, autor: idUsuario, tipo: .tiendaClonada, estado: .enRevision, riesgo: .noEvaluado, ciudad: "CDMX", horas: 3,
                titulo: "Descuento falso de laptop en tienda clonada",
                descripcion: "Reporté una tienda que ofrecía una laptop a precio irrisorio y nunca la recibí.",
                url: "https://laptops-liquidacion.store"),
        Semilla(id: 122, autor: idUsuario, tipo: .ofertaFalsa, estado: .validado, riesgo: .medio, ciudad: "CDMX", horas: 30,
                titulo: "Oferta falsa 2x1 en boletos de concierto por Instagram",
                descripcion: "Una cuenta falsa ofrecía boletos 2x1 pidiendo pago por transferencia.",
                url: "https://instagram.com/boletos2x1.oficial", previas: 340),
        Semilla(id: 123, autor: idUsuario, tipo: .llamada, estado: .recibido, riesgo: .noEvaluado, ciudad: "CDMX", horas: 0.5,
                titulo: "Llamada de supuesto banco pidiendo código",
                descripcion: "Me llamaron diciendo ser de mi banco y pidieron el código que me llegó por SMS para 'cancelar un cargo'.",
                texto: "+52 55 1234 5678"),
    ]
}
```

- [ ] **Paso 5: Pruebas** — Run: `UNIT` → `** TEST SUCCEEDED **`. `lasContrasenasDemoCoincidenConSusHashes` tarda ~1 s (3 × 600,000 iteraciones); es esperado.

- [ ] **Paso 6: Revisar que no haya contraseñas en claro en la app**

Run: `grep -rn -e 'Alerta#2026' -e 'Revisa#2026' -e 'Equipo#2026' PrototipoApp`
Expected: sin resultados.

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp/Data/Demo/DemoSeed.swift PrototipoApp/Model/Usuario.swift PrototipoAppTests/Data/DemoSeedTests.swift
git commit -m "feat: datos semilla de la demo con contraseñas solo como hash"
```

**Criterios de aceptación:** 6 usuarios, 23 reportes (17 públicos), las 2 alertas críticas del storyboard, ninguna fecha futura, contraseñas demo solo como hash.
**Dependencias:** D3, S1, S3, S4. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea D5: Servidor Demo — núcleo, sesión y lo que cada quien puede ver

**Objetivo:** el `actor DemoServer` con registro, login (con límite de intentos, hash señuelo y dos pasos), sesiones con caducidad, cambio de contraseña, preferencias, y la función que arma la vista de un reporte según quién lo pide.

**Archivos:**
- Crear: `PrototipoApp/Data/Demo/DemoServer.swift`
- Test: `PrototipoAppTests/Soporte/EntornoPrueba.swift`, `PrototipoAppTests/Data/DemoServerAuthTests.swift`, `PrototipoAppTests/Data/DemoServerVistaTests.swift`

**Interfaces:**
- Consume: D2, D3, D4, S1 (`PasswordHasher`, `Aleatorio`), S3 (`Sanitizador`, `Validador`), S5 (`LimiteIntentos`), S6 (`ArchivosEvidencia`).
- Produce (todo `internal` para que D6 y D7 lo usen desde sus extensiones):
  - `actor DemoServer` con `init(almacen:archivos:hasher:reloj:)`, `var db`, `ahora`, `persistir()`, `static huella(_:)`, `static enmascarar(_:)`
  - `usuarioActual(_ token: String?) throws -> Usuario`, `exigirStaff(_:)`, `exigirOwner(_:)`, `indiceUsuario(_:)`, `indiceReporte(_:)`
  - `registrar(_:) -> Usuario`, `iniciarSesion(correo:contrasena:) -> ResultadoLogin`, `verificarCodigo(desafio:codigo:) -> SesionActiva`, `cerrarSesion(token:)`, `cambiarContrasena(token:actual:nueva:)`, `actualizarPreferencias(token:_:contrasena:) -> Usuario`
  - `abrirSesion(para:) -> SesionActiva`, `registrarEvento(_:de:)`, `notificar(_:reporte:_:)`
  - `puedeVer(_ fila: ReporteFila, _ yo: Usuario) -> Bool`, `vista(_ fila: ReporteFila, para yo: Usuario) -> Reporte`, `nombreVisible(de:para:) -> String`

- [ ] **Paso 1: Soporte de pruebas** — `PrototipoAppTests/Soporte/EntornoPrueba.swift`:

```swift
//
//  EntornoPrueba.swift
//  PrototipoAppTests
//
//  Servidor Demo con carpeta temporal, semilla fresca y un reloj que la prueba puede adelantar.
//

import Foundation
import Synchronization
@testable import PrototipoApp

nonisolated final class RelojPrueba: Sendable {
    private let actual: Mutex<Date>

    init(_ inicio: Date) { actual = Mutex(inicio) }

    var ahora: Date { actual.withLock { $0 } }

    func avanzar(_ segundos: TimeInterval) {
        actual.withLock { $0 = $0.addingTimeInterval(segundos) }
    }
}

struct EntornoPrueba {
    static let inicio = Date(timeIntervalSince1970: 1_791_072_000)
    static let usuario = (correo: "usuario@0fraude.mx", contrasena: "Alerta#2026mx")
    static let admin = (correo: "admin@0fraude.mx", contrasena: "Revisa#2026zs")
    static let owner = (correo: "owner@0fraude.mx", contrasena: "Equipo#2026zs")

    let carpeta: URL
    let reloj: RelojPrueba
    /// La misma carpeta de evidencia que usa el servidor (para preparar adjuntos).
    let archivos: ArchivosEvidencia
    let servidor: DemoServer

    init() {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-prueba-\(UUID().uuidString)")
        let reloj = RelojPrueba(Self.inicio)
        let archivos = ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia"))
        self.carpeta = carpeta
        self.reloj = reloj
        self.archivos = archivos
        servidor = DemoServer(almacen: DemoAlmacen(carpeta: carpeta), archivos: archivos,
                              hasher: PasswordHasher(iteraciones: 1_000),
                              reloj: { reloj.ahora })
    }

    /// Inicia sesión y devuelve el token, como la app lo guardaría en el Keychain.
    func token(_ cuenta: (correo: String, contrasena: String)) async throws -> String {
        guard case .sesion(let sesion) = try await servidor.iniciarSesion(correo: cuenta.correo, contrasena: cuenta.contrasena) else {
            throw AppError.codigoInvalido
        }
        return sesion.accessToken
    }

    static func datosNuevos(alias: String = "prueba_01", correo: String = "prueba@comunidad.test") -> RegistroDatos {
        var d = RegistroDatos()
        d.nombre = "Prueba"
        d.apellido = "Uno"
        d.alias = alias
        d.correo = correo
        d.contrasena = "Segura#2026x"
        d.confirmacion = "Segura#2026x"
        d.aceptaAviso = true
        return d
    }

    /// Registra a alguien nuevo (hash rápido de 1,000 iteraciones) y devuelve su token.
    func nuevaCuenta(alias: String = "prueba_01", correo: String = "prueba@comunidad.test") async throws -> String {
        _ = try await servidor.registrar(Self.datosNuevos(alias: alias, correo: correo))
        return try await token((correo, "Segura#2026x"))
    }
}
```

- [ ] **Paso 2: Pruebas que fallan** — `PrototipoAppTests/Data/DemoServerAuthTests.swift`:

```swift
//
//  DemoServerAuthTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerAuthTests {
    let e = EntornoPrueba()

    @Test func registrarCreaUsuarioConRolYConsentimiento() async throws {
        let u = try await e.servidor.registrar(EntornoPrueba.datosNuevos())
        #expect(u.rol == .usuario)
        #expect(u.estadoCuenta == .activo)
        #expect(u.consentimiento.versionAviso == Consentimiento.versionAvisoVigente)
        #expect(u.correo == "prueba@comunidad.test")
    }

    @Test func registrarNormalizaCorreoYAlias() async throws {
        let u = try await e.servidor.registrar(EntornoPrueba.datosNuevos(alias: "  Prueba_01 ", correo: " PRUEBA@Comunidad.TEST "))
        #expect(u.alias == "prueba_01")
        #expect(u.correo == "prueba@comunidad.test")
    }

    @Test func registrarRechazaCorreoRepetido() async throws {
        await #expect(throws: AppError.conflicto("Ese correo ya tiene una cuenta. Inicia sesión.")) {
            _ = try await e.servidor.registrar(EntornoPrueba.datosNuevos(correo: "usuario@0fraude.mx"))
        }
    }

    @Test func registrarRechazaDatosInvalidos() async throws {
        var d = EntornoPrueba.datosNuevos()
        d.contrasena = "123"
        d.confirmacion = "123"
        await #expect(throws: AppError.self) { _ = try await e.servidor.registrar(d) }
    }

    @Test func laContrasenaNoQuedaEnClaroEnDisco() async throws {
        _ = try await e.nuevaCuenta()
        let texto = try String(contentsOf: e.carpeta.appending(path: "zeroscam-demo.json"), encoding: .utf8)
        #expect(!texto.contains("Segura#2026x"))
        #expect(texto.contains("pbkdf2_sha256$1000$"))
    }

    @Test func loginCorrectoAbreSesion() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let yo = try await e.servidor.usuarioActual(token)
        #expect(yo.alias == "usuario_01")
        #expect(!token.isEmpty)
    }

    @Test func elTokenNoSeGuardaEnClaro() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let texto = try String(contentsOf: e.carpeta.appending(path: "zeroscam-demo.json"), encoding: .utf8)
        #expect(!texto.contains(token))
        #expect(texto.contains(DemoServer.huella(token)))
    }

    @Test func errorGenericoConCorreoInexistenteOContrasenaMala() async {
        await #expect(throws: AppError.credencialesInvalidas) {
            _ = try await e.servidor.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: "malamala123")
        }
        await #expect(throws: AppError.credencialesInvalidas) {
            _ = try await e.servidor.iniciarSesion(correo: "nadie@0fraude.mx", contrasena: "malamala123")
        }
    }

    @Test func cincoFallosBloqueanYElBloqueoVence() async throws {
        for _ in 1...4 {
            await #expect(throws: AppError.credencialesInvalidas) {
                _ = try await e.servidor.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: "malamala123")
            }
        }
        let hasta = EntornoPrueba.inicio.addingTimeInterval(60)
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) {
            _ = try await e.servidor.iniciarSesion(correo: "usuario@0fraude.mx", contrasena: "malamala123")
        }
        // Bloqueado: ni la contraseña correcta entra.
        await #expect(throws: AppError.cuentaBloqueada(hasta: hasta)) {
            _ = try await e.token(EntornoPrueba.usuario)
        }
        e.reloj.avanzar(61)
        _ = try await e.token(EntornoPrueba.usuario)
    }

    @Test func elBloqueoTambienAplicaAUnCorreoQueNoExiste() async {
        for _ in 1...4 { _ = try? await e.servidor.iniciarSesion(correo: "nadie@0fraude.mx", contrasena: "x") }
        await #expect(throws: AppError.cuentaBloqueada(hasta: EntornoPrueba.inicio.addingTimeInterval(60))) {
            _ = try await e.servidor.iniciarSesion(correo: "nadie@0fraude.mx", contrasena: "x")
        }
    }

    @Test func laSesionCaducaALosSieteDias() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        e.reloj.avanzar(7 * 24 * 3_600 + 1)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(token) }
    }

    @Test func cerrarSesionRevocaElToken() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        try await e.servidor.cerrarSesion(token: token)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(token) }
    }

    @Test func tokenInventadoNoSirve() async {
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual("inventado") }
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(nil) }
    }

    @Test func cambiarContrasenaPideLaActualYCierraLasOtrasSesiones() async throws {
        let token = try await e.nuevaCuenta()
        let otro = try await e.token(("prueba@comunidad.test", "Segura#2026x"))
        await #expect(throws: AppError.self) {
            try await e.servidor.cambiarContrasena(token: token, actual: "equivocada1", nueva: "Distinta#2026y")
        }
        try await e.servidor.cambiarContrasena(token: token, actual: "Segura#2026x", nueva: "Distinta#2026y")
        _ = try await e.servidor.usuarioActual(token)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(otro) }
        _ = try await e.token(("prueba@comunidad.test", "Distinta#2026y"))
    }

    @Test func dosPasosPideCodigoYLoVerifica() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        guard case .requiereCodigo(let desafio) = try await e.servidor.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x") else {
            Issue.record("Debía pedir código"); return
        }
        #expect(desafio.destino == "p•••••@comunidad.test")
        let codigo = try #require(desafio.codigoDemo)
        let sesion = try await e.servidor.verificarCodigo(desafio: desafio.id, codigo: codigo)
        #expect(sesion.usuario.alias == "prueba_01")
    }

    @Test func codigoMalTresVecesAnulaElDesafio() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        guard case .requiereCodigo(let d) = try await e.servidor.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x") else { return }
        for _ in 1...3 {
            await #expect(throws: AppError.codigoInvalido) { _ = try await e.servidor.verificarCodigo(desafio: d.id, codigo: "000000") }
        }
        await #expect(throws: AppError.codigoInvalido) { _ = try await e.servidor.verificarCodigo(desafio: d.id, codigo: d.codigoDemo ?? "") }
    }

    @Test func elCodigoVenceACincoMinutos() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        guard case .requiereCodigo(let d) = try await e.servidor.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x") else { return }
        e.reloj.avanzar(301)
        await #expect(throws: AppError.codigoInvalido) { _ = try await e.servidor.verificarCodigo(desafio: d.id, codigo: d.codigoDemo ?? "") }
    }

    @Test func apagarDosPasosExigeContrasena() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        p.dosPasos = false
        await #expect(throws: AppError.self) { _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil) }
        let u = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: "Segura#2026x")
        #expect(!u.preferencias.dosPasos)
    }
}
```

`PrototipoAppTests/Data/DemoServerVistaTests.swift`:

```swift
//
//  DemoServerVistaTests.swift
//  PrototipoAppTests
//
//  Lo que cada quien ve de un mismo reporte (privacidad por diseño).
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerVistaTests {
    let e = EntornoPrueba()

    private func vista(_ idReporte: Int64, comoToken token: String) async throws -> Reporte {
        let yo = try await e.servidor.usuarioActual(token)
        let fila = try #require(await e.servidor.db.reportes.first { $0.id == idReporte })
        return await e.servidor.vista(fila, para: yo)
    }

    @Test func anonimoSeOcultaALaComunidadPeroNoAlStaff() async throws {
        let comunidad = try await vista(117, comoToken: try await e.nuevaCuenta())
        #expect(comunidad.autor.nombre == "Anónimo")
        #expect(comunidad.autor.idUsuario == nil)
        let staff = try await vista(117, comoToken: try await e.token(EntornoPrueba.admin))
        #expect(staff.autor.nombre == "vecina_alerta (anónimo)")
    }

    @Test func perfilPrivadoSeMuestraComoMiembro() async throws {
        let r = try await vista(106, comoToken: try await e.nuevaCuenta())
        #expect(r.autor.nombre == "Miembro de la comunidad")
        #expect(r.autor.idUsuario == nil)
        let publico = try await vista(101, comoToken: try await e.nuevaCuenta(alias: "prueba_02", correo: "dos@comunidad.test"))
        #expect(publico.autor.nombre == "tecno_mx")
    }

    @Test func personaAfectadaSoloParaAutorYStaff() async throws {
        #expect(try await vista(118, comoToken: try await e.nuevaCuenta()).personaAfectada == nil)
        #expect(try await vista(118, comoToken: try await e.token(EntornoPrueba.admin)).personaAfectada?.nombre == "Rosa Martínez")
    }

    @Test func elAutorSeVeComoTu() async throws {
        let r = try await vista(122, comoToken: try await e.token(EntornoPrueba.usuario))
        #expect(r.autor.nombre == "Tú")
        #expect(r.esMio)
    }

    @Test func confirmacionesSumanLasPrevias() async throws {
        let r = try await vista(101, comoToken: try await e.token(EntornoPrueba.usuario))
        #expect(r.confirmaciones == 1_200)
        #expect(r.comentarios == 2)
        #expect(r.guardadoPorMi)
    }

    @Test func soloStaffYAutorVenLoNoPublico() async throws {
        let yo = try await e.servidor.usuarioActual(try await e.nuevaCuenta())
        let fila = try #require(await e.servidor.db.reportes.first { $0.id == 117 })
        let puede = await e.servidor.puedeVer(fila, yo)
        #expect(!puede)
    }
}
```

- [ ] **Paso 3: Ver que fallan** — Run: `UNIT` → FAIL `cannot find 'DemoServer' in scope`.

- [ ] **Paso 4: Implementar `Data/Demo/DemoServer.swift`**

```swift
//
//  DemoServer.swift
//  PrototipoApp
//
//  "Servidor" del modo Demo: hace dentro de la app lo que hará el backend NestJS del Equipo
//  ZeroScam. Es un actor para que dos operaciones nunca se pisen, y cada método recibe el token
//  como el servidor lo recibe en el encabezado Authorization. Esconder un botón no es
//  seguridad: los permisos se revisan aquí.
//  Este archivo: núcleo, sesión y la vista de un reporte según quién lo pide. Reportes en
//  DemoServer+Reportes.swift; cuenta, moderación y Owner en DemoServer+Cuenta.swift.
//

import CryptoKit
import Foundation

actor DemoServer {
    // Los `static` van marcados `nonisolated`: con MainActor por defecto, si no, el actor no
    // podría usarlos sin `await`.
    nonisolated static let duracionSesion: TimeInterval = 7 * 24 * 3_600
    nonisolated static let duracionCodigo: TimeInterval = 5 * 60

    var db: DemoDatabase
    let almacen: DemoAlmacen
    let archivos: ArchivosEvidencia
    let hasher: PasswordHasher
    let reloj: @Sendable () -> Date

    init(almacen: DemoAlmacen, archivos: ArchivosEvidencia, hasher: PasswordHasher,
         reloj: @escaping @Sendable () -> Date = { Date() }) {
        self.almacen = almacen
        self.archivos = archivos
        self.hasher = hasher
        self.reloj = reloj
        if let guardada = almacen.cargar(), guardada.version == DemoDatabase.versionActual {
            db = guardada
        } else {
            db = DemoSeed.base(ahora: reloj())
            try? almacen.guardar(db)
        }
    }

    var ahora: Date { reloj() }

    /// Se llama después de cada cambio (como un COMMIT).
    func persistir() throws {
        try almacen.guardar(db)
    }

    /// SHA-256 en hexadecimal: así se guardan tokens y códigos.
    nonisolated static func huella(_ texto: String) -> String {
        SHA256.hash(data: Data(texto.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// "usuario@0fraude.mx" → "u•••••@0fraude.mx".
    nonisolated static func enmascarar(_ correo: String) -> String {
        let partes = correo.split(separator: "@", maxSplits: 1)
        guard partes.count == 2, let inicial = partes[0].first else { return "tu correo" }
        return "\(inicial)\(String(repeating: "•", count: max(3, partes[0].count - 1)))@\(partes[1])"
    }

    // MARK: - Identidad

    /// Como un middleware de autenticación: token → usuario activo.
    func usuarioActual(_ token: String?) throws -> Usuario {
        guard let token,
              let sesion = db.sesiones.first(where: { $0.tokenHash == Self.huella(token) }),
              sesion.expira > ahora,
              let fila = db.usuarios.first(where: { $0.usuario.id == sesion.idUsuario })
        else { throw AppError.sesionExpirada }
        guard fila.usuario.estadoCuenta == .activo else { throw AppError.cuentaSuspendida }
        return fila.usuario
    }

    func exigirStaff(_ u: Usuario) throws {
        guard u.rol.esStaff else { throw AppError.sinPermiso }
    }

    func exigirOwner(_ u: Usuario) throws {
        guard u.rol == .owner else { throw AppError.sinPermiso }
    }

    func indiceUsuario(_ id: Int64) -> Int? { db.usuarios.firstIndex { $0.usuario.id == id } }
    func indiceReporte(_ id: Int64) -> Int? { db.reportes.firstIndex { $0.id == id } }

    /// Analíticas anónimas: un contador por evento, sin id de usuario, y solo si la persona lo permite.
    func registrarEvento(_ nombre: String, de usuario: Usuario) {
        guard usuario.preferencias.analiticas else { return }
        db.analiticas[nombre, default: 0] += 1
    }

    /// Fila de Notificacion_Alerta para alguien (la usan comentarios y moderación).
    func notificar(_ idUsuario: Int64, reporte: Int64?, _ mensaje: String) {
        db.notificaciones.append(NotificacionFila(id: db.siguienteID(), idUsuario: idUsuario, idReporte: reporte,
                                                  mensaje: mensaje, leida: false, fecha: ahora))
    }

    // MARK: - Registro y sesión

    func registrar(_ entrada: RegistroDatos) throws -> Usuario {
        var d = entrada
        d.nombre = Sanitizador.texto(d.nombre, maximo: 50)
        d.apellido = Sanitizador.texto(d.apellido, maximo: 50)
        d.alias = Sanitizador.alias(d.alias)
        d.correo = Sanitizador.correo(d.correo)
        let errores = Validador.registro(d)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        guard !db.usuarios.contains(where: { $0.usuario.correo == d.correo }) else {
            throw AppError.conflicto("Ese correo ya tiene una cuenta. Inicia sesión.")
        }
        guard !db.usuarios.contains(where: { $0.usuario.alias == d.alias }) else {
            throw AppError.conflicto("Ese nombre de usuario ya está en uso.")
        }
        let usuario = Usuario(id: db.siguienteID(), rol: .usuario, nombre: d.nombre, apellido: d.apellido,
                              pais: d.pais, alias: d.alias, correo: d.correo, biografia: "", avatarRuta: nil,
                              estadoCuenta: .activo, fechaRegistro: ahora, preferencias: Preferencias(),
                              consentimiento: Consentimiento(versionAviso: Consentimiento.versionAvisoVigente, fecha: ahora))
        db.usuarios.append(UsuarioFila(usuario: usuario, contrasenaHash: hasher.hash(d.contrasena)))
        try persistir()
        return usuario
    }

    func iniciarSesion(correo: String, contrasena: String) throws -> ResultadoLogin {
        let clave = Sanitizador.correo(correo)
        var intentos = db.intentos[clave] ?? RegistroIntentos()
        if let hasta = LimiteIntentos.bloqueadoHasta(intentos, ahora: ahora) {
            throw AppError.cuentaBloqueada(hasta: hasta)
        }
        let fila = db.usuarios.first { $0.usuario.correo == clave }
        // Si el correo no existe se verifica contra un hash señuelo: tarda lo mismo y no delata qué correos existen.
        let correcta = hasher.verificar(contrasena, contra: fila?.contrasenaHash ?? DemoSeed.hashSenuelo)
        guard let fila, correcta else {
            LimiteIntentos.registrarFallo(&intentos, ahora: ahora)
            db.intentos[clave] = intentos
            try persistir()
            if let hasta = LimiteIntentos.bloqueadoHasta(intentos, ahora: ahora) {
                throw AppError.cuentaBloqueada(hasta: hasta)
            }
            throw AppError.credencialesInvalidas
        }
        db.intentos[clave] = nil
        guard fila.usuario.estadoCuenta == .activo else {
            try persistir()
            throw AppError.cuentaSuspendida
        }
        if fila.usuario.preferencias.dosPasos {
            let desafio = crearDesafio(para: fila.usuario)
            try persistir()
            return .requiereCodigo(desafio)
        }
        let sesion = abrirSesion(para: fila.usuario)
        try persistir()
        return .sesion(sesion)
    }

    func abrirSesion(para usuario: Usuario) -> SesionActiva {
        let token = Aleatorio.token()
        db.sesiones.removeAll { $0.expira <= ahora }
        db.sesiones.append(SesionFila(tokenHash: Self.huella(token), idUsuario: usuario.id, creada: ahora,
                                      expira: ahora.addingTimeInterval(Self.duracionSesion)))
        registrarEvento("inicio_sesion", de: usuario)
        return SesionActiva(accessToken: token, refreshToken: nil, usuario: usuario)
    }

    private func crearDesafio(para usuario: Usuario) -> DesafioDosPasos {
        let codigo = Aleatorio.codigo()
        let fila = DesafioFila(id: Aleatorio.token(), idUsuario: usuario.id, codigoHash: Self.huella(codigo),
                               expira: ahora.addingTimeInterval(Self.duracionCodigo), intentos: 0)
        db.desafios.removeAll { $0.idUsuario == usuario.id || $0.expira <= ahora }
        db.desafios.append(fila)
        return DesafioDosPasos(id: fila.id, destino: Self.enmascarar(usuario.correo), expira: fila.expira, codigoDemo: codigo)
    }

    func verificarCodigo(desafio id: String, codigo: String) throws -> SesionActiva {
        guard let i = db.desafios.firstIndex(where: { $0.id == id }), db.desafios[i].expira > ahora else {
            throw AppError.codigoInvalido
        }
        let esperado = Data(db.desafios[i].codigoHash.utf8)
        guard PasswordHasher.igualesEnTiempoConstante(Data(Self.huella(codigo).utf8), esperado) else {
            db.desafios[i].intentos += 1
            if db.desafios[i].intentos >= 3 { db.desafios.remove(at: i) }
            try persistir()
            throw AppError.codigoInvalido
        }
        let idUsuario = db.desafios[i].idUsuario
        db.desafios.remove(at: i)
        guard let fila = db.usuarios.first(where: { $0.usuario.id == idUsuario }),
              fila.usuario.estadoCuenta == .activo else { throw AppError.codigoInvalido }
        let sesion = abrirSesion(para: fila.usuario)
        try persistir()
        return sesion
    }

    func cerrarSesion(token: String?) throws {
        guard let token else { return }
        db.sesiones.removeAll { $0.tokenHash == Self.huella(token) }
        try persistir()
    }

    func cambiarContrasena(token: String?, actual: String, nueva: String) throws {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id), hasher.verificar(actual, contra: db.usuarios[i].contrasenaHash) else {
            throw AppError.validacion(["La contraseña actual no es correcta."])
        }
        let errores = Validador.contrasenaNueva(nueva, confirmacion: nueva, alias: yo.alias, correo: yo.correo)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        guard actual != nueva else { throw AppError.validacion(["La nueva contraseña debe ser distinta de la actual."]) }
        db.usuarios[i].contrasenaHash = hasher.hash(nueva)
        // Las demás sesiones se cierran: si alguien más tenía acceso, lo pierde.
        let mia = token.map(Self.huella)
        db.sesiones.removeAll { $0.idUsuario == yo.id && $0.tokenHash != mia }
        try persistir()
    }

    func actualizarPreferencias(token: String?, _ nuevas: Preferencias, contrasena: String?) throws -> Usuario {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id) else { throw AppError.sesionExpirada }
        if yo.preferencias.dosPasos && !nuevas.dosPasos {
            guard let contrasena, hasher.verificar(contrasena, contra: db.usuarios[i].contrasenaHash) else {
                throw AppError.validacion(["Confirma tu contraseña para apagar la verificación en dos pasos."])
            }
        }
        db.usuarios[i].usuario.preferencias = nuevas
        try persistir()
        return db.usuarios[i].usuario
    }

    // MARK: - Lo que cada quien puede ver

    func puedeVer(_ f: ReporteFila, _ yo: Usuario) -> Bool {
        f.estado.esPublico || f.idUsuario == yo.id || yo.rol.esStaff
    }

    /// Arma el reporte para `yo`: autor anónimo o privado oculto, persona afectada y evidencia
    /// solo para el autor y el staff, contadores y marcas personales.
    func vista(_ f: ReporteFila, para yo: Usuario) -> Reporte {
        let esMio = f.idUsuario == yo.id
        let privilegiado = esMio || yo.rol.esStaff
        let autor = f.idUsuario.flatMap { id in db.usuarios.first { $0.usuario.id == id }?.usuario }
        let nombre: String
        if let autor {
            if f.esAnonimo {
                nombre = esMio ? "Tú (anónimo)" : (yo.rol.esStaff ? "\(autor.alias) (anónimo)" : "Anónimo")
            } else {
                nombre = esMio ? "Tú" : (autor.preferencias.perfilPublico || yo.rol.esStaff ? autor.alias : "Miembro de la comunidad")
            }
        } else {
            nombre = "Cuenta eliminada"
        }
        let muestraId = privilegiado || (!f.esAnonimo && (autor?.preferencias.perfilPublico ?? false))
        let evidencias = db.evidencias.filter { $0.idReporte == f.id }
        return Reporte(
            id: f.id,
            autor: AutorVisible(idUsuario: muestraId ? f.idUsuario : nil, nombre: nombre),
            tipo: f.tipo, tipoOtro: f.tipoOtro, estado: f.estado,
            titulo: f.titulo, descripcion: f.descripcion, fechaIncidente: f.fechaIncidente,
            nivelRiesgo: f.nivelRiesgo, fechaCreacion: f.fechaCreacion,
            esAnonimo: f.esAnonimo, afectado: f.afectado, ciudad: f.ciudad,
            personaAfectada: privilegiado ? f.persona : nil,
            sitio: f.idSitio.flatMap { id in db.sitios.first { $0.id == id } },
            textoSospechoso: f.textoSospechoso,
            evidencias: privilegiado ? evidencias.map(\.evidencia) : [],
            totalEvidencias: evidencias.count,
            confirmaciones: f.confirmacionesPrevias + db.confirmaciones.filter { $0.idReporte == f.id }.count,
            comentarios: db.comentarios.filter { $0.idReporte == f.id }.count,
            confirmadoPorMi: db.confirmaciones.contains { $0.idReporte == f.id && $0.idUsuario == yo.id },
            guardadoPorMi: db.guardados.contains { $0.idReporte == f.id && $0.idUsuario == yo.id },
            esMio: esMio)
    }

    /// Nombre de quien comenta, con la misma regla de perfil público.
    func nombreVisible(de idUsuario: Int64?, para yo: Usuario) -> String {
        guard let idUsuario, let u = db.usuarios.first(where: { $0.usuario.id == idUsuario })?.usuario else {
            return "Cuenta eliminada"
        }
        if idUsuario == yo.id { return "Tú" }
        return u.preferencias.perfilPublico || yo.rol.esStaff ? u.alias : "Miembro de la comunidad"
    }
}
```

- [ ] **Paso 5: Pruebas** — Run: `UNIT` → `** TEST SUCCEEDED **`. Las pruebas con cuentas sembradas tardan ~0.4 s cada login (600,000 iteraciones); es esperado.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Data/Demo/DemoServer.swift PrototipoAppTests/Soporte PrototipoAppTests/Data/DemoServerAuthTests.swift PrototipoAppTests/Data/DemoServerVistaTests.swift
git commit -m "feat: servidor demo con sesiones, límite de intentos y dos pasos"
```

**Criterios de aceptación:** las 17 pruebas de autenticación y las 6 de vista pasan; ni tokens ni contraseñas en claro en el archivo.
**Dependencias:** D2, D3, D4, S1, S3, S5, S6. **Esfuerzo:** L. **Riesgo:** medio (es la pieza central; por eso va con tantas pruebas).

### Tarea D6: Servidor Demo — reportes, comentarios y estadísticas

**Objetivo:** todas las operaciones de `ReportRepository` del lado del servidor, con sus reglas de permiso, límites contra abuso y la asociación de URLs a `SitioWeb_URL`.

**Archivos:**
- Crear: `PrototipoApp/Data/Demo/DemoServer+Reportes.swift`
- Test: `PrototipoAppTests/Data/DemoServerReportesTests.swift`

**Interfaces:**
- Consume: D5 (`usuarioActual`, `vista`, `puedeVer`, `nombreVisible`, `notificar`, `registrarEvento`, `persistir`, `indiceReporte`), S3 (`ReporteBorrador.limpio`, `Validador.reporte`, `Validador.comentario`), S4 (`URLTools`), S6 (`ArchivosEvidencia.confirmar`, `datos(ruta:)`, `borrar(ruta:)`).
- Produce: en `DemoServer`: `feed(token:filtro:)`, `misReportes(token:)`, `guardados(token:)`, `detalle(token:id:)`, `crear(token:_:)`, `actualizar(token:id:_:)`, `eliminar(token:id:)`, `borrarReporte(_:)`, `marcarGuardado(token:id:_:)`, `confirmar(token:id:)`, `comentarios(token:id:)`, `comentar(token:id:texto:)`, `eliminarComentario(token:id:)`, `historial(token:id:)`, `estadisticas(token:)`, `categorias(token:)`, `datosEvidencia(token:_:)`, `asociarEnlace(_:)`, `adjuntar(_:a:)`; constantes `limiteReportesPorDia = 10`, `limiteComentariosPorMinuto = 5`.

- [ ] **Paso 1: Pruebas que fallan** — `PrototipoAppTests/Data/DemoServerReportesTests.swift`:

```swift
//
//  DemoServerReportesTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerReportesTests {
    let e = EntornoPrueba()

    static func borrador(titulo: String = "Tienda falsa de consolas en Instagram",
                         enlace: String = "https://consolas-baratas.store") -> ReporteBorrador {
        var b = ReporteBorrador()
        b.ciudad = "CDMX"
        b.tipo = .tiendaClonada
        b.titulo = titulo
        b.urlOTexto = enlace
        b.descripcion = "Ofrecen consolas a mitad de precio y piden transferencia; nunca entregan."
        b.fechaIncidente = EntornoPrueba.inicio.addingTimeInterval(-3_600)
        return b
    }

    @Test func feedSoloTraePublicos() async throws {
        let feed = try await e.servidor.feed(token: try await e.token(EntornoPrueba.usuario), filtro: FiltroBusqueda())
        #expect(feed.count == 17)
        #expect(feed.allSatisfy(\.estado.esPublico))
        #expect(feed.first?.id == 101)
    }

    @Test func feedFiltraPorTexto() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        let r = try await e.servidor.feed(token: token, filtro: FiltroBusqueda(texto: "mercado libre"))
        #expect(r.map(\.id) == [113])
    }

    @Test func misReportesTraeTodosSusEstados() async throws {
        let mios = try await e.servidor.misReportes(token: try await e.token(EntornoPrueba.usuario))
        #expect(Set(mios.map(\.estado)) == [.enRevision, .validado, .recibido])
    }

    @Test func guardadosDelUsuarioDemo() async throws {
        let g = try await e.servidor.guardados(token: try await e.token(EntornoPrueba.usuario))
        #expect(g.map(\.id) == [101, 102])
    }

    @Test func detalleDeReporteAjenoNoPublicoEsNoEncontrado() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.detalle(token: token, id: 117) }
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.detalle(token: token, id: 99_999) }
    }

    @Test func crearQuedaRecibidoPrivadoYConHistorial() async throws {
        let token = try await e.nuevaCuenta()
        let r = try await e.servidor.crear(token: token, Self.borrador())
        #expect(r.estado == .recibido)
        #expect(r.esMio)
        #expect(try await e.servidor.historial(token: token, id: r.id).map(\.nuevo) == [.recibido])
        #expect(try await e.servidor.misReportes(token: token).map(\.id) == [r.id])
        let feed = try await e.servidor.feed(token: token, filtro: FiltroBusqueda())
        #expect(!feed.contains { $0.id == r.id })
    }

    @Test func crearNormalizaLaURLYReutilizaElSitio() async throws {
        let token = try await e.nuevaCuenta()
        let a = try await e.servidor.crear(token: token, Self.borrador(enlace: "HTTPS://Consolas-Baratas.STORE/oferta"))
        let b = try await e.servidor.crear(token: token, Self.borrador(titulo: "Otra vez la tienda de consolas", enlace: "https://consolas-baratas.store/oferta"))
        #expect(a.sitio?.url == "https://consolas-baratas.store/oferta")
        #expect(a.sitio?.id == b.sitio?.id)
        #expect(a.sitio?.estadoCertificado == "HTTPS")
    }

    @Test func crearGuardaTextoCuandoNoEsURL() async throws {
        let r = try await e.servidor.crear(token: try await e.nuevaCuenta(), Self.borrador(enlace: "+52 55 1111 2222"))
        #expect(r.sitio == nil)
        #expect(r.textoSospechoso == "+52 55 1111 2222")
    }

    @Test func crearRechazaDatosInvalidos() async throws {
        var b = Self.borrador()
        b.titulo = "corto"
        let token = try await e.nuevaCuenta()
        await #expect(throws: AppError.validacion(["El título debe tener entre 10 y 120 caracteres."])) {
            _ = try await e.servidor.crear(token: token, b)
        }
    }

    @Test func limiteDeDiezReportesPorDia() async throws {
        let token = try await e.nuevaCuenta()
        for n in 1...10 { _ = try await e.servidor.crear(token: token, Self.borrador(titulo: "Reporte de prueba número \(n)")) }
        await #expect(throws: AppError.self) { _ = try await e.servidor.crear(token: token, Self.borrador()) }
    }

    @Test func editarSoloElAutorYAntesDeValidar() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var b = ReporteBorrador(desde: try await e.servidor.detalle(token: token, id: 123))
        b.titulo = "Llamada de supuesto banco pidiendo el código SMS"
        let editado = try await e.servidor.actualizar(token: token, id: 123, b)
        #expect(editado.titulo == "Llamada de supuesto banco pidiendo el código SMS")
        let validado = ReporteBorrador(desde: try await e.servidor.detalle(token: token, id: 122))
        await #expect(throws: AppError.conflicto("Este reporte ya fue revisado y no se puede editar.")) {
            _ = try await e.servidor.actualizar(token: token, id: 122, validado)
        }
        let otro = try await e.nuevaCuenta()
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.actualizar(token: otro, id: 123, b) }
    }

    @Test func eliminarSoloAutorOStaffYBorraTodoLoRelacionado() async throws {
        let otro = try await e.nuevaCuenta()
        await #expect(throws: AppError.sinPermiso) { try await e.servidor.eliminar(token: otro, id: 101) }
        let token = try await e.token(EntornoPrueba.usuario)
        try await e.servidor.eliminar(token: token, id: 122)
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.detalle(token: token, id: 122) }
        #expect(await e.servidor.db.comentarios.filter { $0.idReporte == 122 }.isEmpty)
        #expect(await e.servidor.db.historial.filter { $0.idReporte == 122 }.isEmpty)
    }

    @Test func marcarGuardadoEsIdempotente() async throws {
        let token = try await e.nuevaCuenta()
        try await e.servidor.marcarGuardado(token: token, id: 103, true)
        try await e.servidor.marcarGuardado(token: token, id: 103, true)
        #expect(try await e.servidor.guardados(token: token).map(\.id) == [103])
        try await e.servidor.marcarGuardado(token: token, id: 103, false)
        #expect(try await e.servidor.guardados(token: token).isEmpty)
    }

    @Test func confirmarEsIdempotente() async throws {
        let token = try await e.nuevaCuenta()
        _ = try await e.servidor.confirmar(token: token, id: 101)
        let r = try await e.servidor.confirmar(token: token, id: 101)
        #expect(r.confirmaciones == 1_201)
        #expect(r.confirmadoPorMi)
    }

    @Test func noSePuedeConfirmarElPropio() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        await #expect(throws: AppError.conflicto("No puedes confirmar tu propio reporte.")) {
            _ = try await e.servidor.confirmar(token: token, id: 122)
        }
    }

    @Test func comentarSoloEnPublicosYAvisaAlAutor() async throws {
        let otro = try await e.nuevaCuenta()
        let c = try await e.servidor.comentar(token: otro, id: 122, texto: "Me pasó lo mismo con esa cuenta.")
        #expect(c.autor == "Tú")
        let avisos = await e.servidor.db.notificaciones.filter { $0.idUsuario == DemoSeed.idUsuario && $0.idReporte == 122 }
        #expect(avisos.contains { $0.mensaje.hasPrefix("Nuevo comentario") })
        let autor = try await e.token(EntornoPrueba.usuario)
        await #expect(throws: AppError.conflicto("Solo se puede comentar en reportes validados.")) {
            _ = try await e.servidor.comentar(token: autor, id: 123, texto: "Comentario en mi propio reporte")
        }
    }

    @Test func comentarioSeLimpiaYSeValida() async throws {
        let token = try await e.nuevaCuenta()
        let c = try await e.servidor.comentar(token: token, id: 101, texto: "  hola\u{202E}   mundo  ")
        #expect(c.texto == "hola mundo")
        await #expect(throws: AppError.self) { _ = try await e.servidor.comentar(token: token, id: 101, texto: "x") }
    }

    @Test func limiteDeCincoComentariosPorMinuto() async throws {
        let token = try await e.nuevaCuenta()
        for n in 1...5 { _ = try await e.servidor.comentar(token: token, id: 101, texto: "Comentario número \(n)") }
        await #expect(throws: AppError.limiteExcedido("Espera un momento antes de volver a comentar.")) {
            _ = try await e.servidor.comentar(token: token, id: 101, texto: "Uno más")
        }
        e.reloj.avanzar(61)
        _ = try await e.servidor.comentar(token: token, id: 101, texto: "Ya pasó un minuto")
    }

    @Test func soloElAutorOStaffBorranComentarios() async throws {
        let otro = try await e.nuevaCuenta()
        await #expect(throws: AppError.sinPermiso) { try await e.servidor.eliminarComentario(token: otro, id: 301) }
        try await e.servidor.eliminarComentario(token: try await e.token(EntornoPrueba.admin), id: 301)
    }

    @Test func historialOcultaAQuienModeraAnteElAutor() async throws {
        let autor = try await e.servidor.historial(token: try await e.token(EntornoPrueba.usuario), id: 122)
        #expect(autor.map(\.responsable) == ["Tú", "Equipo de moderación", "Equipo de moderación"])
        // El Administrador que moderó se ve a sí mismo como "Tú"; el autor aparece con su alias.
        let staff = try await e.servidor.historial(token: try await e.token(EntornoPrueba.admin), id: 122)
        #expect(staff.map(\.responsable) == ["usuario_01", "Tú", "Tú"])
        let otro = try await e.nuevaCuenta()
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.historial(token: otro, id: 101) }
    }

    @Test func estadisticasSeCalculanDeLosPublicos() async throws {
        let s = try await e.servidor.estadisticas(token: try await e.token(EntornoPrueba.usuario))
        #expect(s == EstadisticasComunidad(personasAyudadas: 5_362, reportesVerificados: 17, estafasDetenidas: 4, zonasCubiertas: 10))
    }

    @Test func categoriasCuentanSoloPublicos() async throws {
        let c = try await e.servidor.categorias(token: try await e.token(EntornoPrueba.usuario))
        #expect(c.map(\.tipo) == TipoFraude.allCases)
        #expect(c.first { $0.tipo == .ofertaFalsa }?.total == 5)
        #expect(c.first { $0.tipo == .tiendaClonada }?.riesgoMaximo == .muyAlto)
    }

    @Test func evidenciaSoloParaElAutor() async throws {
        let token = try await e.nuevaCuenta()
        var b = Self.borrador()
        b.adjuntos = [try e.archivos.guardarTemporal(Data([0xFF, 0xD8, 0xFF, 0xE0]), tipo: "image/jpeg")]
        let r = try await e.servidor.crear(token: token, b)
        let evidencia = try #require(r.evidencias.first)
        #expect(try await e.servidor.datosEvidencia(token: token, evidencia).count == 4)
        let otro = try await e.nuevaCuenta(alias: "prueba_02", correo: "dos@comunidad.test")
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.datosEvidencia(token: otro, evidencia) }
    }
}
```

- [ ] **Paso 2: Ver que fallan** — Run: `UNIT` → FAIL `value of type 'DemoServer' has no member 'feed'`.

- [ ] **Paso 3: Implementar `Data/Demo/DemoServer+Reportes.swift`**

```swift
//
//  DemoServer+Reportes.swift
//  PrototipoApp
//
//  Reportes, guardados, "Yo también", comentarios, historial, estadísticas y archivos de
//  evidencia del modo Demo. Lo que alguien no puede ver responde igual que lo que no existe
//  (`noEncontrado`), para no confirmar que existe.
//

import Foundation

extension DemoServer {
    nonisolated static let limiteReportesPorDia = 10
    nonisolated static let limiteComentariosPorMinuto = 5

    // MARK: - Listas

    func feed(token: String?, filtro: FiltroBusqueda) throws -> [Reporte] {
        let yo = try usuarioActual(token)
        if !filtro.estaVacio {
            registrarEvento("busqueda", de: yo)
            try? persistir()
        }
        return db.reportes.filter(\.estado.esPublico)
            .map { vista($0, para: yo) }
            .filter { filtro.coincide($0) }
            .sorted { $0.fechaCreacion > $1.fechaCreacion }
    }

    func misReportes(token: String?) throws -> [Reporte] {
        let yo = try usuarioActual(token)
        return db.reportes.filter { $0.idUsuario == yo.id }
            .map { vista($0, para: yo) }
            .sorted { $0.fechaCreacion > $1.fechaCreacion }
    }

    func guardados(token: String?) throws -> [Reporte] {
        let yo = try usuarioActual(token)
        return db.guardados.filter { $0.idUsuario == yo.id }
            .sorted { $0.fecha > $1.fecha }
            .compactMap { par in
                db.reportes.first { $0.id == par.idReporte && puedeVer($0, yo) }.map { vista($0, para: yo) }
            }
    }

    func detalle(token: String?, id: Int64) throws -> Reporte {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        return vista(fila, para: yo)
    }

    // MARK: - Crear, editar, eliminar

    func crear(token: String?, _ entrada: ReporteBorrador) throws -> Reporte {
        let yo = try usuarioActual(token)
        let b = entrada.limpio
        let errores = Validador.reporte(b, ahora: ahora)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        let recientes = db.reportes.filter { $0.idUsuario == yo.id && $0.fechaCreacion > ahora.addingTimeInterval(-86_400) }
        guard recientes.count < Self.limiteReportesPorDia else {
            throw AppError.limiteExcedido("Llegaste al límite de \(Self.limiteReportesPorDia) reportes por día. Intenta mañana.")
        }
        let id = db.siguienteID()
        let (idSitio, texto) = asociarEnlace(b.urlOTexto)
        db.reportes.append(ReporteFila(id: id, idUsuario: yo.id, tipo: b.tipo, tipoOtro: b.tipo == .otro ? b.tipoOtro : nil,
                                       estado: .recibido, titulo: b.titulo, descripcion: b.descripcion,
                                       fechaIncidente: b.fechaIncidente, nivelRiesgo: .noEvaluado, fechaCreacion: ahora,
                                       esAnonimo: b.esAnonimo, afectado: b.afectado, ciudad: b.ciudad,
                                       persona: b.afectado == .otraPersona ? b.persona : nil,
                                       idSitio: idSitio, textoSospechoso: texto))
        for adjunto in b.adjuntos { try adjuntar(adjunto, a: id) }
        db.historial.append(HistorialFila(id: db.siguienteID(), idReporte: id, idResponsable: yo.id, anterior: nil,
                                          nuevo: .recibido, observaciones: "Reporte creado", fecha: ahora))
        registrarEvento("reporte_enviado", de: yo)
        try persistir()
        return try detalle(token: token, id: id)
    }

    func actualizar(token: String?, id: Int64, _ entrada: ReporteBorrador) throws -> Reporte {
        let yo = try usuarioActual(token)
        guard let i = indiceReporte(id), db.reportes[i].idUsuario == yo.id else { throw AppError.noEncontrado }
        guard db.reportes[i].estado.permiteEdicion else {
            throw AppError.conflicto("Este reporte ya fue revisado y no se puede editar.")
        }
        let b = entrada.limpio
        let errores = Validador.reporte(b, ahora: ahora)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        let quedan = db.evidencias.filter { $0.idReporte == id && !b.quitarEvidencias.contains($0.id) }
        guard quedan.count + b.adjuntos.count <= 3 else { throw AppError.validacion(["Máximo 3 archivos de evidencia."]) }
        let (idSitio, texto) = asociarEnlace(b.urlOTexto)
        db.reportes[i].tipo = b.tipo
        db.reportes[i].tipoOtro = b.tipo == .otro ? b.tipoOtro : nil
        db.reportes[i].titulo = b.titulo
        db.reportes[i].descripcion = b.descripcion
        db.reportes[i].fechaIncidente = b.fechaIncidente
        db.reportes[i].esAnonimo = b.esAnonimo
        db.reportes[i].afectado = b.afectado
        db.reportes[i].ciudad = b.ciudad
        db.reportes[i].persona = b.afectado == .otraPersona ? b.persona : nil
        db.reportes[i].idSitio = idSitio
        db.reportes[i].textoSospechoso = texto
        for quitada in db.evidencias where quitada.idReporte == id && b.quitarEvidencias.contains(quitada.id) {
            try? archivos.borrar(ruta: quitada.rutaArchivo)
        }
        db.evidencias.removeAll { $0.idReporte == id && b.quitarEvidencias.contains($0.id) }
        for adjunto in b.adjuntos { try adjuntar(adjunto, a: id) }
        try persistir()
        return vista(db.reportes[i], para: yo)
    }

    func eliminar(token: String?, id: Int64) throws {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        guard fila.idUsuario == yo.id || yo.rol.esStaff else { throw AppError.sinPermiso }
        borrarReporte(id)
        try persistir()
    }

    /// Borra el reporte y todo lo que cuelga de él, incluida la evidencia en disco.
    func borrarReporte(_ id: Int64) {
        for e in db.evidencias where e.idReporte == id { try? archivos.borrar(ruta: e.rutaArchivo) }
        db.evidencias.removeAll { $0.idReporte == id }
        db.historial.removeAll { $0.idReporte == id }
        db.comentarios.removeAll { $0.idReporte == id }
        db.guardados.removeAll { $0.idReporte == id }
        db.confirmaciones.removeAll { $0.idReporte == id }
        for i in db.notificaciones.indices where db.notificaciones[i].idReporte == id {
            db.notificaciones[i].idReporte = nil
        }
        db.reportes.removeAll { $0.id == id }
    }

    /// URL válida → fila de SitioWeb_URL (se reutiliza si ya existe). Texto → `texto_sospechoso`.
    func asociarEnlace(_ s: String) -> (Int64?, String?) {
        guard !s.isEmpty else { return (nil, nil) }
        guard URLTools.pareceURL(s), let url = URLTools.normalizar(s) else { return (nil, s) }
        if let sitio = db.sitios.first(where: { $0.url == url }) { return (sitio.id, nil) }
        let sitio = SitioWeb(id: db.siguienteID(), url: url, nivelRiesgoGlobal: .bajo,
                             estadoCertificado: URLTools.estadoCertificado(url), fechaUltimaEvaluacion: nil)
        db.sitios.append(sitio)
        return (sitio.id, nil)
    }

    func adjuntar(_ adjunto: Adjunto, a idReporte: Int64) throws {
        guard ["image/jpeg", "application/pdf"].contains(adjunto.tipoArchivo) else {
            throw AppError.validacion(["Tipo de archivo no permitido."])
        }
        let ruta = try archivos.confirmar(adjunto)
        db.evidencias.append(EvidenciaFila(id: db.siguienteID(), idReporte: idReporte, rutaArchivo: ruta,
                                           tipoArchivo: adjunto.tipoArchivo, fechaCarga: ahora))
    }

    // MARK: - Guardar y "Yo también"

    func marcarGuardado(token: String?, id: Int64, _ guardado: Bool) throws {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        db.guardados.removeAll { $0.idUsuario == yo.id && $0.idReporte == id }
        if guardado { db.guardados.append(ParUsuarioReporte(idUsuario: yo.id, idReporte: id, fecha: ahora)) }
        try persistir()
    }

    func confirmar(token: String?, id: Int64) throws -> Reporte {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), fila.estado.esPublico else { throw AppError.noEncontrado }
        guard fila.idUsuario != yo.id else { throw AppError.conflicto("No puedes confirmar tu propio reporte.") }
        if !db.confirmaciones.contains(where: { $0.idUsuario == yo.id && $0.idReporte == id }) {
            db.confirmaciones.append(ParUsuarioReporte(idUsuario: yo.id, idReporte: id, fecha: ahora))
            try persistir()
        }
        return vista(fila, para: yo)
    }

    // MARK: - Comentarios

    func comentarios(token: String?, id: Int64) throws -> [Comentario] {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        return db.comentarios.filter { $0.idReporte == id }
            .sorted { $0.fecha > $1.fecha }
            .map { Comentario(id: $0.id, idReporte: id, autor: nombreVisible(de: $0.idUsuario, para: yo),
                              esMio: $0.idUsuario == yo.id, texto: $0.texto, fecha: $0.fecha) }
    }

    func comentar(token: String?, id: Int64, texto entrada: String) throws -> Comentario {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        guard fila.estado.esPublico else { throw AppError.conflicto("Solo se puede comentar en reportes validados.") }
        let texto = Sanitizador.texto(entrada, maximo: 500, multilinea: true)
        let errores = Validador.comentario(texto)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        let ultimoMinuto = db.comentarios.filter { $0.idUsuario == yo.id && $0.fecha > ahora.addingTimeInterval(-60) }
        guard ultimoMinuto.count < Self.limiteComentariosPorMinuto else {
            throw AppError.limiteExcedido("Espera un momento antes de volver a comentar.")
        }
        let nuevo = ComentarioFila(id: db.siguienteID(), idReporte: id, idUsuario: yo.id, texto: texto, fecha: ahora)
        db.comentarios.append(nuevo)
        if let autor = fila.idUsuario, autor != yo.id {
            notificar(autor, reporte: id, "Nuevo comentario en tu reporte «\(fila.titulo)».")
        }
        try persistir()
        return Comentario(id: nuevo.id, idReporte: id, autor: "Tú", esMio: true, texto: texto, fecha: ahora)
    }

    func eliminarComentario(token: String?, id: Int64) throws {
        let yo = try usuarioActual(token)
        guard let c = db.comentarios.first(where: { $0.id == id }) else { throw AppError.noEncontrado }
        guard c.idUsuario == yo.id || yo.rol.esStaff else { throw AppError.sinPermiso }
        db.comentarios.removeAll { $0.id == id }
        try persistir()
    }

    // MARK: - Historial, estadísticas y archivos

    /// El autor ve "Equipo de moderación" en lugar del alias de quien moderó (lo protege de acoso).
    func historial(token: String?, id: Int64) throws -> [HistorialEstado] {
        let yo = try usuarioActual(token)
        guard let fila = db.reportes.first(where: { $0.id == id }), puedeVer(fila, yo) else { throw AppError.noEncontrado }
        guard fila.idUsuario == yo.id || yo.rol.esStaff else { throw AppError.sinPermiso }
        return db.historial.filter { $0.idReporte == id }
            .sorted { $0.fecha < $1.fecha }
            .map { h in
                let responsable = h.anterior == nil || yo.rol.esStaff
                    ? nombreVisible(de: h.idResponsable, para: yo)
                    : "Equipo de moderación"
                return HistorialEstado(id: h.id, idReporte: id, responsable: responsable, anterior: h.anterior,
                                       nuevo: h.nuevo, observaciones: h.observaciones, fecha: h.fecha)
            }
    }

    func estadisticas(token: String?) throws -> EstadisticasComunidad {
        _ = try usuarioActual(token)
        let publicos = db.reportes.filter(\.estado.esPublico)
        let ids = Set(publicos.map(\.id))
        let confirmaciones = publicos.reduce(0) { $0 + $1.confirmacionesPrevias }
            + db.confirmaciones.filter { ids.contains($0.idReporte) }.count
        return EstadisticasComunidad(
            personasAyudadas: confirmaciones + db.guardados.filter { ids.contains($0.idReporte) }.count,
            reportesVerificados: publicos.count,
            estafasDetenidas: publicos.filter { $0.estado == .canalizado }.count,
            zonasCubiertas: Set(publicos.map { FiltroBusqueda.normalizar($0.ciudad) }).count)
    }

    func categorias(token: String?) throws -> [ConteoCategoria] {
        _ = try usuarioActual(token)
        let publicos = db.reportes.filter(\.estado.esPublico)
        return TipoFraude.allCases.map { tipo in
            let deTipo = publicos.filter { $0.tipo == tipo }
            return ConteoCategoria(tipo: tipo, total: deTipo.count, riesgoMaximo: deTipo.map(\.nivelRiesgo).max() ?? .noEvaluado)
        }
    }

    /// La ruta sale de la base, nunca del cliente: no hay forma de pedir otro archivo del disco.
    func datosEvidencia(token: String?, _ evidencia: Evidencia) throws -> Data {
        let yo = try usuarioActual(token)
        guard let fila = db.evidencias.first(where: { $0.id == evidencia.id }),
              let reporte = db.reportes.first(where: { $0.id == fila.idReporte }),
              reporte.idUsuario == yo.id || yo.rol.esStaff
        else { throw AppError.noEncontrado }
        return try archivos.datos(ruta: fila.rutaArchivo)
    }
}
```

- [ ] **Paso 4: Pruebas** — Run: `UNIT` → `** TEST SUCCEEDED **`.

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp/Data/Demo/DemoServer+Reportes.swift PrototipoAppTests/Data/DemoServerReportesTests.swift
git commit -m "feat: reportes, comentarios y estadísticas en el servidor demo"
```

**Criterios de aceptación:** 22 pruebas en verde; permisos (`sinPermiso`/`noEncontrado`) probados para editar, eliminar, historial, comentarios y evidencia.
**Dependencias:** D5, S3, S4, S6. Puede ir en paralelo con D7. **Esfuerzo:** L. **Riesgo:** medio.

### Tarea D7: Servidor Demo — cuenta, notificaciones, moderación y Owner

**Objetivo:** perfil, avatar, exportar datos, eliminar cuenta, notificaciones, la cola de moderación con su máquina de estados, y la gestión de usuarios del Owner.

**Archivos:**
- Crear: `PrototipoApp/Data/Demo/DemoServer+Cuenta.swift`
- Test: `PrototipoAppTests/Data/DemoServerCuentaTests.swift`

**Interfaces:**
- Consume: D5, S3 (`Validador.perfil`, `Validador.moderacion`, `Sanitizador`), S6. Usa `misReportes(token:)` y `borrarReporte(_:)` de D6: si D7 se hace en paralelo con D6, fusionar D6 primero.
- Produce: en `DemoServer`: `actualizarPerfil(token:_:)`, `actualizarAvatar(token:_:)`, `datosAvatar(token:de:)`, `exportarMisDatos(token:)`, `eliminarCuenta(token:contrasena:)`, `notificaciones(token:)`, `marcarLeidas(token:_:)`, `colaModeracion(token:estado:)`, `cambiarEstado(token:id:a:riesgo:observaciones:)`, `mensajeCambio(titulo:nuevo:observaciones:)`, `usuarios(token:)`, `cambiarRol(token:idUsuario:a:)`, `cambiarEstadoCuenta(token:idUsuario:a:)`, `analiticas(token:)`, `restablecerDemo(token:)`; tipo `ExportacionDatos`.

- [ ] **Paso 1: Pruebas que fallan** — `PrototipoAppTests/Data/DemoServerCuentaTests.swift`:

```swift
//
//  DemoServerCuentaTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoServerCuentaTests {
    let e = EntornoPrueba()

    // MARK: Perfil

    @Test func perfilSeActualizaYNoRepiteAlias() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = PerfilDatos(desde: try await e.servidor.usuarioActual(token))
        d.biografia = "Reviso tiendas en línea."
        #expect(try await e.servidor.actualizarPerfil(token: token, d).biografia == "Reviso tiendas en línea.")
        d.alias = "tecno_mx"
        await #expect(throws: AppError.conflicto("Ese nombre de usuario ya está en uso.")) {
            _ = try await e.servidor.actualizarPerfil(token: token, d)
        }
    }

    @Test func cambiarCorreoPideLaContrasena() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        var d = PerfilDatos(desde: try await e.servidor.usuarioActual(token))
        d.correo = "ana.nueva@comunidad.test"
        await #expect(throws: AppError.self) { _ = try await e.servidor.actualizarPerfil(token: token, d) }
        d.contrasenaActual = "equivocada1"
        await #expect(throws: AppError.validacion(["La contraseña no es correcta."])) {
            _ = try await e.servidor.actualizarPerfil(token: token, d)
        }
        d.contrasenaActual = EntornoPrueba.usuario.contrasena
        #expect(try await e.servidor.actualizarPerfil(token: token, d).correo == "ana.nueva@comunidad.test")
    }

    @Test func exportarIncluyeMisDatosPeroNoElHash() async throws {
        let datos = try await e.servidor.exportarMisDatos(token: try await e.token(EntornoPrueba.usuario))
        let texto = String(decoding: datos, as: UTF8.self)
        #expect(texto.contains("usuario_01"))
        #expect(texto.contains("Llamada de supuesto banco pidiendo código"))
        #expect(!texto.contains("pbkdf2"))
    }

    @Test func eliminarCuentaAnonimizaLoPublicoYBorraLoDemas() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        try await e.servidor.eliminarCuenta(token: token, contrasena: EntornoPrueba.usuario.contrasena)
        let otro = try await e.nuevaCuenta()
        let publico = try await e.servidor.detalle(token: otro, id: 122)
        #expect(publico.autor.nombre == "Cuenta eliminada")
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.noEncontrado) { _ = try await e.servidor.detalle(token: admin, id: 123) }
        await #expect(throws: AppError.credencialesInvalidas) { _ = try await e.token(EntornoPrueba.usuario) }
        #expect(await e.servidor.db.guardados.filter { $0.idUsuario == DemoSeed.idUsuario }.isEmpty)
    }

    @Test func elOwnerNoSePuedeEliminar() async throws {
        let token = try await e.token(EntornoPrueba.owner)
        await #expect(throws: AppError.self) { try await e.servidor.eliminarCuenta(token: token, contrasena: EntornoPrueba.owner.contrasena) }
    }

    // MARK: Notificaciones

    @Test func notificacionesSoloLasMiasYSeMarcanLeidas() async throws {
        let token = try await e.token(EntornoPrueba.usuario)
        #expect(try await e.servidor.notificaciones(token: token).map(\.id) == [502, 501])
        try await e.servidor.marcarLeidas(token: token, [502, 999])
        #expect(try await e.servidor.notificaciones(token: token).allSatisfy(\.leida))
        #expect(try await e.servidor.notificaciones(token: try await e.nuevaCuenta()).isEmpty)
    }

    // MARK: Moderación

    @Test func laColaEsSoloParaStaffYEmpiezaPorLoMasViejo() async throws {
        await #expect(throws: AppError.sinPermiso) {
            _ = try await e.servidor.colaModeracion(token: try await e.token(EntornoPrueba.usuario), estado: nil)
        }
        let cola = try await e.servidor.colaModeracion(token: try await e.token(EntornoPrueba.admin), estado: nil)
        #expect(cola.map(\.id) == [118, 119, 121, 117, 123])
    }

    @Test func moderarSigueLaMaquinaDeEstadosYAvisaAlAutor() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.conflicto("No se puede pasar de RECIBIDO a VALIDADO.")) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .validado, riesgo: .alto, observaciones: "")
        }
        _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .enRevision, riesgo: nil, observaciones: "")
        await #expect(throws: AppError.validacion(["Asigna un nivel de riesgo para validar."])) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .validado, riesgo: nil, observaciones: "")
        }
        let r = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .validado, riesgo: .alto, observaciones: "Número confirmado por otros reportes.")
        #expect(r.estado == .validado)
        #expect(r.nivelRiesgo == .alto)
        let usuario = try await e.token(EntornoPrueba.usuario)
        #expect(try await e.servidor.feed(token: usuario, filtro: FiltroBusqueda()).contains { $0.id == 123 })
        let avisos = try await e.servidor.notificaciones(token: usuario).map(\.mensaje)
        #expect(avisos.contains("Tu reporte «Llamada de supuesto banco pidiendo código» fue VALIDADO y ya es visible para la comunidad."))
    }

    @Test func rechazarExigeMotivo() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        await #expect(throws: AppError.validacion(["Explica el motivo del rechazo (10 a 500 caracteres)."])) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: 117, a: .rechazado, riesgo: nil, observaciones: "no")
        }
        _ = try await e.servidor.cambiarEstado(token: admin, id: 117, a: .rechazado, riesgo: nil, observaciones: "El enlace ya no existe y no hay captura.")
    }

    @Test func nadieModeraSuPropioReporte() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        let r = try await e.servidor.crear(token: admin, DemoServerReportesTests.borrador())
        await #expect(throws: AppError.conflicto("No puedes moderar tu propio reporte.")) {
            _ = try await e.servidor.cambiarEstado(token: admin, id: r.id, a: .enRevision, riesgo: nil, observaciones: "")
        }
    }

    @Test func validarActualizaElRiesgoDelSitio() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        let r = try await e.servidor.cambiarEstado(token: admin, id: 121, a: .validado, riesgo: .muyAlto, observaciones: "")
        #expect(r.sitio?.nivelRiesgoGlobal == .muyAlto)
        #expect(r.sitio?.fechaUltimaEvaluacion == EntornoPrueba.inicio)
    }

    @Test func staffVeLaEvidenciaYLaComunidadSoloElConteo() async throws {
        let autor = try await e.nuevaCuenta()
        var b = DemoServerReportesTests.borrador()
        b.adjuntos = [try e.archivos.guardarTemporal(Data([0xFF, 0xD8, 0xFF, 0xE0]), tipo: "image/jpeg")]
        let creado = try await e.servidor.crear(token: autor, b)
        let admin = try await e.token(EntornoPrueba.admin)
        _ = try await e.servidor.cambiarEstado(token: admin, id: creado.id, a: .enRevision, riesgo: nil, observaciones: "")
        _ = try await e.servidor.cambiarEstado(token: admin, id: creado.id, a: .validado, riesgo: .medio, observaciones: "")
        let comunidad = try await e.servidor.detalle(token: try await e.nuevaCuenta(alias: "prueba_02", correo: "dos@comunidad.test"), id: creado.id)
        #expect(comunidad.evidencias.isEmpty)
        #expect(comunidad.totalEvidencias == 1)
        #expect(try await e.servidor.detalle(token: admin, id: creado.id).evidencias.count == 1)
    }

    // MARK: Owner

    @Test func soloElOwnerVeUsuarios() async throws {
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.usuarios(token: try await e.token(EntornoPrueba.admin)) }
        #expect(try await e.servidor.usuarios(token: try await e.token(EntornoPrueba.owner)).count == 6)
    }

    @Test func elOwnerNoCreaOtroOwnerNiSeTocaASiMismo() async throws {
        let owner = try await e.token(EntornoPrueba.owner)
        await #expect(throws: AppError.sinPermiso) { _ = try await e.servidor.cambiarRol(token: owner, idUsuario: 3, a: .owner) }
        await #expect(throws: AppError.self) { _ = try await e.servidor.cambiarRol(token: owner, idUsuario: 1, a: .usuario) }
        #expect(try await e.servidor.cambiarRol(token: owner, idUsuario: 3, a: .administrador).rol == .administrador)
    }

    @Test func suspenderRevocaLasSesiones() async throws {
        let usuario = try await e.token(EntornoPrueba.usuario)
        _ = try await e.servidor.cambiarEstadoCuenta(token: try await e.token(EntornoPrueba.owner), idUsuario: 3, a: .suspendido)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(usuario) }
        await #expect(throws: AppError.cuentaSuspendida) { _ = try await e.token(EntornoPrueba.usuario) }
    }

    @Test func analiticasSonContadoresYRespetanLaPreferencia() async throws {
        let usuario = try await e.token(EntornoPrueba.usuario)
        _ = try await e.servidor.feed(token: usuario, filtro: FiltroBusqueda(texto: "banco"))
        var p = try await e.servidor.usuarioActual(usuario).preferencias
        p.analiticas = false
        _ = try await e.servidor.actualizarPreferencias(token: usuario, p, contrasena: nil)
        _ = try await e.servidor.feed(token: usuario, filtro: FiltroBusqueda(texto: "sat"))
        let a = try await e.servidor.analiticas(token: try await e.token(EntornoPrueba.owner))
        #expect(a["busqueda"] == 1)
    }

    @Test func restablecerVuelveALaSemillaYCierraSesiones() async throws {
        let admin = try await e.token(EntornoPrueba.admin)
        _ = try await e.servidor.cambiarEstado(token: admin, id: 123, a: .enRevision, riesgo: nil, observaciones: "")
        let owner = try await e.token(EntornoPrueba.owner)
        try await e.servidor.restablecerDemo(token: owner)
        #expect(await e.servidor.db.reportes.first { $0.id == 123 }?.estado == .recibido)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(owner) }
    }
}
```

- [ ] **Paso 2: Ver que fallan** — Run: `UNIT` → FAIL `value of type 'DemoServer' has no member 'actualizarPerfil'`.

- [ ] **Paso 3: Implementar `Data/Demo/DemoServer+Cuenta.swift`**

```swift
//
//  DemoServer+Cuenta.swift
//  PrototipoApp
//
//  Perfil, derechos ARCO (exportar y eliminar), notificaciones, moderación y lo que solo puede
//  hacer el Owner. La moderación sigue la máquina de estados de `EstadoReporte.siguientes`.
//

import Foundation

/// Lo que recibe la persona al pedir "Descargar mis datos" (derecho de acceso).
nonisolated struct ExportacionDatos: Encodable, Sendable {
    let generado: Date
    let usuario: Usuario
    let reportes: [Reporte]
    let comentarios: [Comentario]
    let guardados: [Int64]
    let confirmaciones: [Int64]
    let notificaciones: [Notificacion]
}

extension DemoServer {
    // MARK: - Perfil

    func actualizarPerfil(token: String?, _ entrada: PerfilDatos) throws -> Usuario {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id) else { throw AppError.sesionExpirada }
        var d = entrada
        d.nombre = Sanitizador.texto(d.nombre, maximo: 50)
        d.apellido = Sanitizador.texto(d.apellido, maximo: 50)
        d.alias = Sanitizador.alias(d.alias)
        d.correo = Sanitizador.correo(d.correo)
        d.biografia = Sanitizador.texto(d.biografia, maximo: 300, multilinea: true)
        let errores = Validador.perfil(d, correoOriginal: yo.correo)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        if d.correo != yo.correo {
            guard let actual = d.contrasenaActual, hasher.verificar(actual, contra: db.usuarios[i].contrasenaHash) else {
                throw AppError.validacion(["La contraseña no es correcta."])
            }
            guard !db.usuarios.contains(where: { $0.usuario.correo == d.correo }) else {
                throw AppError.conflicto("Ese correo ya tiene una cuenta.")
            }
        }
        if d.alias != yo.alias, db.usuarios.contains(where: { $0.usuario.alias == d.alias }) {
            throw AppError.conflicto("Ese nombre de usuario ya está en uso.")
        }
        db.usuarios[i].usuario.nombre = d.nombre
        db.usuarios[i].usuario.apellido = d.apellido
        db.usuarios[i].usuario.pais = d.pais
        db.usuarios[i].usuario.alias = d.alias
        db.usuarios[i].usuario.correo = d.correo
        db.usuarios[i].usuario.biografia = d.biografia
        try persistir()
        return db.usuarios[i].usuario
    }

    func actualizarAvatar(token: String?, _ adjunto: Adjunto?) throws -> Usuario {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id) else { throw AppError.sesionExpirada }
        if let adjunto, adjunto.tipoArchivo != "image/jpeg" {
            throw AppError.validacion(["El avatar debe ser una imagen."])
        }
        if let anterior = db.usuarios[i].usuario.avatarRuta { try? archivos.borrar(ruta: anterior) }
        db.usuarios[i].usuario.avatarRuta = try adjunto.map { try archivos.confirmar($0) }
        try persistir()
        return db.usuarios[i].usuario
    }

    /// El avatar se ve si es tuyo, si eres staff o si esa persona tiene perfil público.
    func datosAvatar(token: String?, de usuario: Usuario) throws -> Data? {
        let yo = try usuarioActual(token)
        guard let fila = db.usuarios.first(where: { $0.usuario.id == usuario.id }),
              let ruta = fila.usuario.avatarRuta,
              fila.usuario.id == yo.id || yo.rol.esStaff || fila.usuario.preferencias.perfilPublico
        else { return nil }
        return try archivos.datos(ruta: ruta)
    }

    func exportarMisDatos(token: String?) throws -> Data {
        let yo = try usuarioActual(token)
        let exportacion = ExportacionDatos(
            generado: ahora,
            usuario: yo,
            reportes: try misReportes(token: token),
            comentarios: db.comentarios.filter { $0.idUsuario == yo.id }.map {
                Comentario(id: $0.id, idReporte: $0.idReporte, autor: "Tú", esMio: true, texto: $0.texto, fecha: $0.fecha)
            },
            guardados: db.guardados.filter { $0.idUsuario == yo.id }.map(\.idReporte),
            confirmaciones: db.confirmaciones.filter { $0.idUsuario == yo.id }.map(\.idReporte),
            notificaciones: try notificaciones(token: token))
        let encoder = Codificacion.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exportacion)
    }

    /// Derecho de cancelación: lo validado sigue ayudando a la comunidad pero sin rastro de la
    /// persona (sin autor, sin persona afectada, sin evidencia); lo demás se borra.
    func eliminarCuenta(token: String?, contrasena: String) throws {
        let yo = try usuarioActual(token)
        guard let i = indiceUsuario(yo.id), hasher.verificar(contrasena, contra: db.usuarios[i].contrasenaHash) else {
            throw AppError.validacion(["La contraseña no es correcta."])
        }
        guard yo.rol != .owner else { throw AppError.conflicto("La cuenta Owner no se puede eliminar desde la app.") }
        for r in db.reportes where r.idUsuario == yo.id {
            if r.estado.esPublico, let j = indiceReporte(r.id) {
                db.reportes[j].idUsuario = nil
                db.reportes[j].persona = nil
                db.reportes[j].esAnonimo = true
                for e in db.evidencias where e.idReporte == r.id { try? archivos.borrar(ruta: e.rutaArchivo) }
                db.evidencias.removeAll { $0.idReporte == r.id }
            } else {
                borrarReporte(r.id)
            }
        }
        for j in db.comentarios.indices where db.comentarios[j].idUsuario == yo.id { db.comentarios[j].idUsuario = nil }
        db.guardados.removeAll { $0.idUsuario == yo.id }
        db.confirmaciones.removeAll { $0.idUsuario == yo.id }
        db.notificaciones.removeAll { $0.idUsuario == yo.id }
        db.sesiones.removeAll { $0.idUsuario == yo.id }
        db.desafios.removeAll { $0.idUsuario == yo.id }
        if let avatar = db.usuarios[i].usuario.avatarRuta { try? archivos.borrar(ruta: avatar) }
        db.usuarios.removeAll { $0.usuario.id == yo.id }
        try persistir()
    }

    // MARK: - Notificaciones

    func notificaciones(token: String?) throws -> [Notificacion] {
        let yo = try usuarioActual(token)
        return db.notificaciones.filter { $0.idUsuario == yo.id }
            .sorted { $0.fecha > $1.fecha }
            .map { Notificacion(id: $0.id, idReporte: $0.idReporte, mensaje: $0.mensaje, leida: $0.leida, fecha: $0.fecha) }
    }

    /// Ids ajenos se ignoran: nadie marca las notificaciones de otra persona.
    func marcarLeidas(token: String?, _ ids: [Int64]) throws {
        let yo = try usuarioActual(token)
        for i in db.notificaciones.indices where db.notificaciones[i].idUsuario == yo.id && ids.contains(db.notificaciones[i].id) {
            db.notificaciones[i].leida = true
        }
        try persistir()
    }

    // MARK: - Moderación (Administrador y Owner)

    func colaModeracion(token: String?, estado: EstadoReporte?) throws -> [Reporte] {
        let yo = try usuarioActual(token)
        try exigirStaff(yo)
        let estados: Set<EstadoReporte> = estado.map { [$0] } ?? [.recibido, .enRevision]
        return db.reportes.filter { estados.contains($0.estado) }
            .sorted { $0.fechaCreacion < $1.fechaCreacion }
            .map { vista($0, para: yo) }
    }

    func cambiarEstado(token: String?, id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?,
                       observaciones entrada: String) throws -> Reporte {
        let yo = try usuarioActual(token)
        try exigirStaff(yo)
        guard let i = indiceReporte(id) else { throw AppError.noEncontrado }
        // Separación de funciones: quien reporta no valida su propio reporte.
        guard db.reportes[i].idUsuario != yo.id else { throw AppError.conflicto("No puedes moderar tu propio reporte.") }
        let anterior = db.reportes[i].estado
        guard anterior.siguientes.contains(nuevo) else {
            throw AppError.conflicto("No se puede pasar de \(anterior.titulo) a \(nuevo.titulo).")
        }
        let observaciones = Sanitizador.texto(entrada, maximo: 500, multilinea: true)
        let errores = Validador.moderacion(nuevo: nuevo, riesgo: riesgo, observaciones: observaciones)
        guard errores.isEmpty else { throw AppError.validacion(errores.mensajes) }
        db.reportes[i].estado = nuevo
        if nuevo == .validado, let riesgo { db.reportes[i].nivelRiesgo = riesgo }
        db.historial.append(HistorialFila(id: db.siguienteID(), idReporte: id, idResponsable: yo.id, anterior: anterior,
                                          nuevo: nuevo, observaciones: observaciones.isEmpty ? nil : observaciones, fecha: ahora))
        if nuevo.esPublico, let idSitio = db.reportes[i].idSitio, let s = db.sitios.firstIndex(where: { $0.id == idSitio }) {
            let riesgos = db.reportes.filter { $0.idSitio == idSitio && $0.estado.esPublico }.map(\.nivelRiesgo)
            db.sitios[s].nivelRiesgoGlobal = riesgos.max() ?? .bajo
            db.sitios[s].fechaUltimaEvaluacion = ahora
        }
        if let autor = db.reportes[i].idUsuario {
            notificar(autor, reporte: id, Self.mensajeCambio(titulo: db.reportes[i].titulo, nuevo: nuevo, observaciones: observaciones))
        }
        try persistir()
        return vista(db.reportes[i], para: yo)
    }

    nonisolated static func mensajeCambio(titulo: String, nuevo: EstadoReporte, observaciones: String) -> String {
        switch nuevo {
        case .recibido: "Tu reporte «\(titulo)» fue RECIBIDO."
        case .enRevision: "Tu reporte «\(titulo)» está EN REVISIÓN."
        case .validado: "Tu reporte «\(titulo)» fue VALIDADO y ya es visible para la comunidad."
        case .rechazado: "Tu reporte «\(titulo)» fue RECHAZADO. Motivo: \(observaciones)"
        case .canalizado: "Tu reporte «\(titulo)» fue CANALIZADO a las autoridades."
        }
    }

    // MARK: - Owner

    func usuarios(token: String?) throws -> [Usuario] {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        return db.usuarios.map(\.usuario).sorted { $0.fechaRegistro < $1.fechaRegistro }
    }

    /// Desde la app solo se asigna Usuario o Administrador; Owner y Policía se dan en la base.
    func cambiarRol(token: String?, idUsuario: Int64, a rol: Rol) throws -> Usuario {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        guard idUsuario != yo.id else { throw AppError.conflicto("No puedes cambiar tu propio rol.") }
        guard rol == .usuario || rol == .administrador else { throw AppError.sinPermiso }
        guard let i = indiceUsuario(idUsuario) else { throw AppError.noEncontrado }
        guard db.usuarios[i].usuario.rol != .owner else { throw AppError.sinPermiso }
        db.usuarios[i].usuario.rol = rol
        try persistir()
        return db.usuarios[i].usuario
    }

    func cambiarEstadoCuenta(token: String?, idUsuario: Int64, a estado: EstadoCuenta) throws -> Usuario {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        guard idUsuario != yo.id else { throw AppError.conflicto("No puedes suspender tu propia cuenta.") }
        guard let i = indiceUsuario(idUsuario) else { throw AppError.noEncontrado }
        guard db.usuarios[i].usuario.rol != .owner else { throw AppError.sinPermiso }
        db.usuarios[i].usuario.estadoCuenta = estado
        if estado == .suspendido { db.sesiones.removeAll { $0.idUsuario == idUsuario } }
        try persistir()
        return db.usuarios[i].usuario
    }

    func analiticas(token: String?) throws -> [String: Int] {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        return db.analiticas
    }

    /// Vuelve a la semilla (para repetir la demo). Cierra todas las sesiones, incluida la del Owner.
    func restablecerDemo(token: String?) throws {
        let yo = try usuarioActual(token)
        try exigirOwner(yo)
        try? archivos.borrarTodo()
        db = DemoSeed.base(ahora: ahora)
        try persistir()
    }
}
```

- [ ] **Paso 4: Pruebas** — Run: `UNIT` → `** TEST SUCCEEDED **`.

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp/Data/Demo/DemoServer+Cuenta.swift PrototipoAppTests/Data/DemoServerCuentaTests.swift
git commit -m "feat: moderación, notificaciones, cuenta y Owner en el servidor demo"
```

**Criterios de aceptación:** 18 pruebas en verde; la máquina de estados, la separación de funciones (nadie modera lo suyo) y la anonimización al borrar la cuenta están probadas.
**Dependencias:** D5, D6 (usa `misReportes` y `borrarReporte`), S3, S6. **Esfuerzo:** M. **Riesgo:** medio.

### Tarea D8: `DemoBackend`, configuración y dependencias

**Objetivo:** conectar el servidor Demo a los protocolos (leyendo el token del `SecretStore`, como un encabezado `Authorization`), y decidir al arrancar qué fuente de datos usar.

**Archivos:**
- Crear: `PrototipoApp/Data/Demo/DemoBackend.swift`
- Crear: `PrototipoApp/App/AppConfig.swift`
- Crear: `PrototipoApp/App/Dependencies.swift`
- Modificar: `PrototipoApp/Info.plist` (claves `ZSFuenteDatos`, `ZSURLBase`)
- Modificar: `PrototipoApp.xcodeproj/project.pbxproj` (ajustes `ZS_FUENTE_DATOS`, `ZS_URL_BASE` en Debug y Release del target)
- Test: `PrototipoAppTests/Data/DemoBackendTests.swift`, `PrototipoAppTests/App/AppConfigTests.swift`

**Interfaces:**
- Consume: D5–D7, S2 (`SecretStore`, `KeychainStore`, `PrimeraEjecucion`), S6.
- Produce: `struct DemoBackend: Backend` (`init(servidor:secretos:)`); `AppConfig` (`fuente: Fuente` = `.demo | .remote(URL)`, `esUITest`, `reiniciarDemo`, `evidenciaDePrueba`, `static actual(info:argumentos:)`, `static esURLPermitida(_:)`, `static porDefecto`); `Dependencies` (`backend`, `secretos`, `archivos`, `config`, `static crear(_:)`); en pruebas, `EntornoPrueba.backend(_:)`.

- [ ] **Paso 1: Pruebas que fallan**

`PrototipoAppTests/App/AppConfigTests.swift`:

```swift
//
//  AppConfigTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct AppConfigTests {
    @Test func porDefectoEsDemo() {
        #expect(AppConfig.actual(info: [:], argumentos: []).fuente == .demo)
    }

    @Test func remotoSoloConHTTPSoLocalhost() {
        let https = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": "https://api.zeroscam.test"], argumentos: [])
        #expect(https.fuente == .remote(URL(string: "https://api.zeroscam.test")!))
        let local = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": "http://localhost:3000"], argumentos: [])
        #expect(local.fuente == .remote(URL(string: "http://localhost:3000")!))
        let inseguro = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": "http://api.zeroscam.test"], argumentos: [])
        #expect(inseguro.fuente == .demo)
    }

    @Test func lasPruebasDeInterfazSiempreUsanDemo() {
        let c = AppConfig.actual(info: ["ZSFuenteDatos": "remote", "ZSURLBase": "https://api.zeroscam.test"],
                                 argumentos: ["-uiTesting", "-reiniciarDemo", "-evidenciaDePrueba"])
        #expect(c.fuente == .demo)
        #expect(c.esUITest && c.reiniciarDemo && c.evidenciaDePrueba)
    }

    @Test func laEvidenciaDePruebaSoloExisteEnPruebasDeInterfaz() {
        #expect(!AppConfig.actual(info: [:], argumentos: ["-evidenciaDePrueba"]).evidenciaDePrueba)
    }
}
```

`PrototipoAppTests/Data/DemoBackendTests.swift`:

```swift
//
//  DemoBackendTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct DemoBackendTests {
    let e = EntornoPrueba()

    @Test func sinTokenNoHaySesion() async {
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.backend(MemorySecretStore()).misReportes() }
    }

    @Test func conTokenEnElSecretStoreFunciona() async throws {
        let secretos = MemorySecretStore()
        let backend = e.backend(secretos)
        guard case .sesion(let s) = try await backend.iniciarSesion(correo: EntornoPrueba.usuario.correo,
                                                                    contrasena: EntornoPrueba.usuario.contrasena) else { return }
        try secretos.guardar(s.accessToken, para: .accessToken)
        #expect(try await backend.misReportes().count == 3)
        #expect(try await backend.usuarioActual().alias == "usuario_01")
    }
}
```

Agregar al final de `PrototipoAppTests/Soporte/EntornoPrueba.swift`:

```swift
extension EntornoPrueba {
    /// El backend que usarían los stores, leyendo el token de `secretos`.
    func backend(_ secretos: any SecretStore) -> DemoBackend {
        DemoBackend(servidor: servidor, secretos: secretos)
    }
}
```

- [ ] **Paso 2: Ver que fallan** — Run: `UNIT` → FAIL `cannot find 'AppConfig' in scope`.

- [ ] **Paso 3: Implementar `Data/Demo/DemoBackend.swift`**

```swift
//
//  DemoBackend.swift
//  PrototipoApp
//
//  Adaptador entre los protocolos de repositorio y el DemoServer. Lee el token del Keychain en
//  cada llamada y se lo pasa al servidor, igual que el interceptor de `api.ts` agrega el Bearer.
//

import Foundation

nonisolated struct DemoBackend: Backend {
    let servidor: DemoServer
    let secretos: any SecretStore

    private var token: String? { try? secretos.leer(.accessToken) }

    // MARK: AuthRepository
    func registrar(_ datos: RegistroDatos) async throws -> Usuario { try await servidor.registrar(datos) }
    func iniciarSesion(correo: String, contrasena: String) async throws -> ResultadoLogin {
        try await servidor.iniciarSesion(correo: correo, contrasena: contrasena)
    }
    func verificarCodigo(desafio: String, codigo: String) async throws -> SesionActiva {
        try await servidor.verificarCodigo(desafio: desafio, codigo: codigo)
    }
    func usuarioActual() async throws -> Usuario { try await servidor.usuarioActual(token) }
    func cerrarSesion() async throws { try await servidor.cerrarSesion(token: token) }
    func cambiarContrasena(actual: String, nueva: String) async throws {
        try await servidor.cambiarContrasena(token: token, actual: actual, nueva: nueva)
    }
    func eliminarCuenta(contrasena: String) async throws { try await servidor.eliminarCuenta(token: token, contrasena: contrasena) }

    // MARK: ReportRepository
    func feed(_ filtro: FiltroBusqueda) async throws -> [Reporte] { try await servidor.feed(token: token, filtro: filtro) }
    func misReportes() async throws -> [Reporte] { try await servidor.misReportes(token: token) }
    func guardados() async throws -> [Reporte] { try await servidor.guardados(token: token) }
    func detalle(id: Int64) async throws -> Reporte { try await servidor.detalle(token: token, id: id) }
    func crear(_ borrador: ReporteBorrador) async throws -> Reporte { try await servidor.crear(token: token, borrador) }
    func actualizar(id: Int64, _ borrador: ReporteBorrador) async throws -> Reporte {
        try await servidor.actualizar(token: token, id: id, borrador)
    }
    func eliminar(id: Int64) async throws { try await servidor.eliminar(token: token, id: id) }
    func marcarGuardado(id: Int64, _ guardado: Bool) async throws { try await servidor.marcarGuardado(token: token, id: id, guardado) }
    func confirmar(id: Int64) async throws -> Reporte { try await servidor.confirmar(token: token, id: id) }
    func comentarios(id: Int64) async throws -> [Comentario] { try await servidor.comentarios(token: token, id: id) }
    func comentar(id: Int64, texto: String) async throws -> Comentario { try await servidor.comentar(token: token, id: id, texto: texto) }
    func eliminarComentario(id: Int64) async throws { try await servidor.eliminarComentario(token: token, id: id) }
    func historial(id: Int64) async throws -> [HistorialEstado] { try await servidor.historial(token: token, id: id) }
    func estadisticas() async throws -> EstadisticasComunidad { try await servidor.estadisticas(token: token) }
    func categorias() async throws -> [ConteoCategoria] { try await servidor.categorias(token: token) }
    func datosEvidencia(_ evidencia: Evidencia) async throws -> Data { try await servidor.datosEvidencia(token: token, evidencia) }

    // MARK: ProfileRepository
    func actualizarPerfil(_ datos: PerfilDatos) async throws -> Usuario { try await servidor.actualizarPerfil(token: token, datos) }
    func actualizarPreferencias(_ preferencias: Preferencias, contrasena: String?) async throws -> Usuario {
        try await servidor.actualizarPreferencias(token: token, preferencias, contrasena: contrasena)
    }
    func actualizarAvatar(_ adjunto: Adjunto?) async throws -> Usuario { try await servidor.actualizarAvatar(token: token, adjunto) }
    func datosAvatar(de usuario: Usuario) async throws -> Data? { try await servidor.datosAvatar(token: token, de: usuario) }
    func exportarMisDatos() async throws -> Data { try await servidor.exportarMisDatos(token: token) }

    // MARK: NotificationRepository
    func notificaciones() async throws -> [Notificacion] { try await servidor.notificaciones(token: token) }
    func marcarLeidas(_ ids: [Int64]) async throws { try await servidor.marcarLeidas(token: token, ids) }

    // MARK: AdminRepository
    func colaModeracion(estado: EstadoReporte?) async throws -> [Reporte] { try await servidor.colaModeracion(token: token, estado: estado) }
    func cambiarEstado(id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) async throws -> Reporte {
        try await servidor.cambiarEstado(token: token, id: id, a: nuevo, riesgo: riesgo, observaciones: observaciones)
    }
    func usuarios() async throws -> [Usuario] { try await servidor.usuarios(token: token) }
    func cambiarRol(idUsuario: Int64, a rol: Rol) async throws -> Usuario { try await servidor.cambiarRol(token: token, idUsuario: idUsuario, a: rol) }
    func cambiarEstadoCuenta(idUsuario: Int64, a estado: EstadoCuenta) async throws -> Usuario {
        try await servidor.cambiarEstadoCuenta(token: token, idUsuario: idUsuario, a: estado)
    }
    func analiticas() async throws -> [String: Int] { try await servidor.analiticas(token: token) }
    func restablecerDemo() async throws { try await servidor.restablecerDemo(token: token) }
}
```

- [ ] **Paso 4: Implementar `App/AppConfig.swift`**

```swift
//
//  AppConfig.swift
//  PrototipoApp
//
//  De dónde salen los datos (Demo o la API del equipo) y los interruptores para las pruebas de
//  interfaz. La fuente se elige con los ajustes ZS_FUENTE_DATOS y ZS_URL_BASE del target.
//

import Foundation

nonisolated struct AppConfig: Sendable, Equatable {
    nonisolated enum Fuente: Sendable, Equatable {
        case demo
        case remote(URL)
    }

    let fuente: Fuente
    let esUITest: Bool
    let reiniciarDemo: Bool
    let evidenciaDePrueba: Bool

    static let porDefecto = AppConfig(fuente: .demo, esUITest: false, reiniciarDemo: false, evidenciaDePrueba: false)

    static func actual(info: [String: Any] = Bundle.main.infoDictionary ?? [:],
                       argumentos: [String] = ProcessInfo.processInfo.arguments) -> AppConfig {
        let esUITest = argumentos.contains("-uiTesting")
        var fuente = Fuente.demo
        if !esUITest, (info["ZSFuenteDatos"] as? String) == "remote",
           let texto = info["ZSURLBase"] as? String, let url = URL(string: texto), esURLPermitida(url) {
            fuente = .remote(url)
        }
        #if DEBUG
        let reiniciar = argumentos.contains("-reiniciarDemo")
        #else
        let reiniciar = false
        #endif
        return AppConfig(fuente: fuente, esUITest: esUITest, reiniciarDemo: reiniciar,
                         evidenciaDePrueba: esUITest && argumentos.contains("-evidenciaDePrueba"))
    }

    /// Solo HTTPS. HTTP únicamente contra la propia Mac (backend del equipo en desarrollo).
    static func esURLPermitida(_ url: URL) -> Bool {
        url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host() ?? ""))
    }
}
```

- [ ] **Paso 5: Implementar `App/Dependencies.swift`**

```swift
//
//  Dependencies.swift
//  PrototipoApp
//
//  Arma todo lo que necesita la app al arrancar: Keychain, carpeta de datos y el backend.
//  En pruebas de interfaz usa otra carpeta y otro servicio del Keychain para no mezclar datos.
//

import Foundation

struct Dependencies {
    let backend: any Backend
    let secretos: any SecretStore
    let archivos: ArchivosEvidencia
    let config: AppConfig

    static func crear(_ config: AppConfig) -> Dependencies {
        let sufijo = config.esUITest ? ".uitest" : ""
        let secretos = KeychainStore(servicio: "Tec-CCM.PrototipoApp-SwiftUI.sesion" + sufijo)
        let carpeta = DemoAlmacen.carpetaPorDefecto(nombre: config.esUITest ? "ZeroScamDemo-UITest" : "ZeroScamDemo")
        if config.reiniciarDemo {
            try? secretos.borrarTodo()
            try? DemoAlmacen(carpeta: carpeta).borrarTodo()
        }
        PrimeraEjecucion.limpiarSiHaceFalta(defaults: .standard, secretos: secretos)
        let archivos = ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia"))
        // BACKEND: R3 agrega aquí el caso `.remote(let base)` con RemoteBackend.
        let hasher = PasswordHasher(iteraciones: config.esUITest ? 1_000 : PasswordHasher.iteracionesRecomendadas)
        let servidor = DemoServer(almacen: DemoAlmacen(carpeta: carpeta), archivos: archivos, hasher: hasher)
        return Dependencies(backend: DemoBackend(servidor: servidor, secretos: secretos),
                            secretos: secretos, archivos: archivos, config: config)
    }
}
```

- [ ] **Paso 6: Claves de configuración.** En `PrototipoApp/Info.plist`, dentro del `<dict>` raíz:

```xml
	<key>ZSFuenteDatos</key>
	<string>$(ZS_FUENTE_DATOS)</string>
	<key>ZSURLBase</key>
	<string>$(ZS_URL_BASE)</string>
```

En `project.pbxproj`, en las configuraciones Debug (`FA58C27730461DCE00D1FB66`) y Release (`FA58C27830461DCE00D1FB66`) del target, agregar dentro de `buildSettings` (orden alfabético, antes de `TARGETED_DEVICE_FAMILY`):

```
				ZS_FUENTE_DATOS = demo;
				ZS_URL_BASE = "";
```

Para probar contra el backend del equipo: `xcodebuild … ZS_FUENTE_DATOS=remote ZS_URL_BASE=http://localhost:3000 build` (requiere R2 y R3).

- [ ] **Paso 7: Pruebas y build** — Run: `UNIT` → `** TEST SUCCEEDED **`; `BUILD` → `** BUILD SUCCEEDED **`;
`plutil -p $HOME/Library/Caches/0fraude-dd/Build/Products/Debug-iphonesimulator/PrototipoApp.app/Info.plist | grep ZS` → `"ZSFuenteDatos" => "demo"`.

- [ ] **Paso 8: Commit**

```bash
git add PrototipoApp/Data/Demo/DemoBackend.swift PrototipoApp/App/AppConfig.swift PrototipoApp/App/Dependencies.swift PrototipoApp/Info.plist PrototipoApp.xcodeproj/project.pbxproj PrototipoAppTests
git commit -m "feat: backend demo detrás de los protocolos y selección de fuente de datos"
```

**Criterios de aceptación:** sin token no hay datos; con token sí; la fuente remota solo se acepta con HTTPS o localhost.
**Dependencias:** D5, D6, D7, S2. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea D9: Stores de la app

**Objetivo:** los objetos `@Observable` que usan las vistas: sesión, reportes, notificaciones y administración, con estados de carga, invalidación por versión y manejo de sesión expirada en un solo lugar.

**Archivos:**
- Crear: `PrototipoApp/Stores/SessionStore.swift`
- Crear: `PrototipoApp/Stores/ReportsStore.swift`
- Crear: `PrototipoApp/Stores/NotificationsStore.swift`
- Crear: `PrototipoApp/Stores/AdminStore.swift`
- Crear: `PrototipoApp/App/NotificadorLocal.swift`
- Test: `PrototipoAppTests/Stores/SessionStoreTests.swift`, `PrototipoAppTests/Stores/ReportsStoreTests.swift`, `PrototipoAppTests/Stores/NotificationsStoreTests.swift`, `PrototipoAppTests/Stores/AdminStoreTests.swift`

**Interfaces:**
- Consume: D2 (`Backend`, `Carga`, `AppError`), D8, S2.
- Produce:
  - `SessionStore(backend:secretos:)`: `estado` (`.restaurando | .sinSesion | .activa(Usuario)`), `usuario`, `desafio`, `aviso`, `correoSugerido`; `restaurar()`, `iniciarSesion(correo:contrasena:)`, `verificarCodigo(_:)`, `cancelarDesafio()`, `registrar(_:)`, `cerrarSesion()`, `expirar(_:)`, `actualizarPerfil(_:)`, `actualizarPreferencias(_:contrasena:)`, `actualizarAvatar(_:)`, `datosAvatar(de:)`, `recargarUsuario()`, `cambiarContrasena(actual:nueva:)`, `eliminarCuenta(contrasena:)`, `exportarDatos() -> URL`.
  - `ReportsStore(backend:archivos:alExpirar:)`: `alertas`, `resultados`, `categorias`, `mios`, `guardados`, `estadisticas` (todas `Carga`), `version`, `archivos`; `cargarAlertas()`, `buscar(_:)`, `cargarCategorias()`, `cargarMios()`, `cargarGuardados()`, `cargarEstadisticas()`, `detalle(id:)`, `crear(_:)`, `actualizar(id:_:)`, `eliminar(id:)`, `marcarGuardado(id:_:)`, `confirmar(id:)`, `comentarios(id:)`, `comentar(id:texto:)`, `eliminarComentario(id:)`, `historial(id:)`, `datosEvidencia(_:)`, `invalidar()`, `reiniciar()`.
  - `NotificationsStore(backend:notificador:alExpirar:)`: `lista`, `sinLeer`; `cargar(avisar:)`, `marcarLeidas(_:)`, `pedirPermiso()`, `reiniciar()`.
  - `AdminStore(backend:alExpirar:)`: `cola`, `usuarios`, `analiticas`; `cargarCola(estado:)`, `cambiarEstado(id:a:riesgo:observaciones:)`, `cargarUsuarios()`, `cambiarRol(idUsuario:a:)`, `cambiarEstadoCuenta(idUsuario:a:)`, `restablecerDemo()`, `reiniciar()`.
  - `NotificadorLocal` (protocolo) y `UNNotificador`.

- [ ] **Paso 1: Pruebas que fallan**

`PrototipoAppTests/Stores/SessionStoreTests.swift`:

```swift
//
//  SessionStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct SessionStoreTests {
    let e: EntornoPrueba
    let secretos: MemorySecretStore
    let session: SessionStore

    init() {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        self.e = e
        self.secretos = secretos
        session = SessionStore(backend: e.backend(secretos), secretos: secretos)
    }

    private func entrar() async throws {
        try await session.iniciarSesion(correo: EntornoPrueba.usuario.correo, contrasena: EntornoPrueba.usuario.contrasena)
    }

    @Test func sinTokenQuedaSinSesion() async {
        await session.restaurar()
        #expect(session.estado == .sinSesion)
    }

    @Test func iniciarSesionGuardaElTokenYActiva() async throws {
        try await session.iniciarSesion(correo: " USUARIO@0fraude.mx ", contrasena: EntornoPrueba.usuario.contrasena)
        #expect(session.usuario?.alias == "usuario_01")
        #expect(try secretos.leer(.accessToken) != nil)
    }

    @Test func laSesionSobreviveAUnNuevoArranque() async throws {
        try await entrar()
        let otraVez = SessionStore(backend: e.backend(secretos), secretos: secretos)
        await otraVez.restaurar()
        #expect(otraVez.usuario?.alias == "usuario_01")
    }

    @Test func tokenInvalidoSeBorraAlRestaurar() async throws {
        try secretos.guardar("inventado", para: .accessToken)
        await session.restaurar()
        #expect(session.estado == .sinSesion)
        #expect(try secretos.leer(.accessToken) == nil)
    }

    @Test func cerrarSesionBorraYRevocaElToken() async throws {
        try await entrar()
        let token = try #require(try secretos.leer(.accessToken))
        await session.cerrarSesion()
        #expect(session.estado == .sinSesion)
        #expect(try secretos.leer(.accessToken) == nil)
        await #expect(throws: AppError.sesionExpirada) { _ = try await e.servidor.usuarioActual(token) }
    }

    @Test func registrarDejaCorreoYAvisoParaLogin() async throws {
        await session.restaurar()
        try await session.registrar(EntornoPrueba.datosNuevos())
        #expect(session.correoSugerido == "prueba@comunidad.test")
        #expect(session.aviso == "Cuenta creada. Inicia sesión para continuar.")
        #expect(session.usuario == nil)
    }

    @Test func dosPasosGuardaElDesafioYDespuesEntra() async throws {
        let token = try await e.nuevaCuenta()
        var p = try await e.servidor.usuarioActual(token).preferencias
        p.dosPasos = true
        _ = try await e.servidor.actualizarPreferencias(token: token, p, contrasena: nil)
        try await session.iniciarSesion(correo: "prueba@comunidad.test", contrasena: "Segura#2026x")
        let desafio = try #require(session.desafio)
        #expect(session.usuario == nil)
        try await session.verificarCodigo(try #require(desafio.codigoDemo))
        #expect(session.usuario?.alias == "prueba_01")
        #expect(session.desafio == nil)
    }

    @Test func expirarDejaAvisoYBorraElToken() async throws {
        try await entrar()
        session.expirar(.sesionExpirada)
        #expect(session.aviso == "Tu sesión expiró. Inicia sesión de nuevo.")
        #expect(session.estado == .sinSesion)
        #expect(try secretos.leer(.accessToken) == nil)
    }

    @Test func unaOperacionConSesionVencidaCierraLaSesion() async throws {
        try await entrar()
        e.reloj.avanzar(7 * 24 * 3_600 + 1)
        await #expect(throws: AppError.sesionExpirada) {
            try await session.cambiarContrasena(actual: "Alerta#2026mx", nueva: "Distinta#2026y")
        }
        #expect(session.estado == .sinSesion)
    }
}
```

`PrototipoAppTests/Stores/ReportsStoreTests.swift`:

```swift
//
//  ReportsStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

final class RegistroExpiraciones {
    var errores: [AppError] = []
}

struct ReportsStoreTests {
    let e: EntornoPrueba
    let secretos: MemorySecretStore
    let expiraciones: RegistroExpiraciones
    let reports: ReportsStore

    init() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        let expiraciones = RegistroExpiraciones()
        self.e = e
        self.secretos = secretos
        self.expiraciones = expiraciones
        reports = ReportsStore(backend: e.backend(secretos), archivos: e.archivos) { expiraciones.errores.append($0) }
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
    }

    @Test func lasAlertasSonLasDosCriticas() async {
        await reports.cargarAlertas()
        #expect(reports.alertas.valor?.map(\.id) == [101, 102])
    }

    @Test func buscarFiltraPorTipo() async {
        await reports.buscar(FiltroBusqueda(tipos: [.llamada]))
        #expect(reports.resultados.valor?.map(\.id) == [105, 112])
    }

    @Test func crearSubeLaVersionYApareceEnMisReportes() async throws {
        let antes = reports.version
        let r = try await reports.crear(DemoServerReportesTests.borrador())
        #expect(reports.version == antes + 1)
        await reports.cargarMios()
        #expect(reports.mios.valor?.contains { $0.id == r.id } == true)
    }

    @Test func sesionVencidaAvisaAlExpirar() async throws {
        try secretos.borrar(.accessToken)
        await reports.cargarMios()
        #expect(reports.mios == .error("Tu sesión expiró. Inicia sesión de nuevo."))
        #expect(expiraciones.errores == [.sesionExpirada])
    }

    @Test func noEncontradoNoCierraLaSesion() async {
        await #expect(throws: AppError.noEncontrado) { _ = try await reports.detalle(id: 99_999) }
        #expect(expiraciones.errores.isEmpty)
    }

    @Test func reiniciarVuelveACargando() async {
        await reports.cargarMios()
        reports.reiniciar()
        #expect(reports.mios == .cargando)
        #expect(reports.version == 0)
    }
}
```

`PrototipoAppTests/Stores/NotificationsStoreTests.swift`:

```swift
//
//  NotificationsStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Synchronization
import Testing
@testable import PrototipoApp

/// `nonisolated`: el protocolo no es de MainActor y el target de pruebas sí lo es por defecto.
nonisolated final class NotificadorPrueba: NotificadorLocal {
    let avisos = Mutex<[String]>([])
    func pedirPermiso() async -> Bool { true }
    func avisar(titulo: String, cuerpo: String) async { avisos.withLock { $0.append(cuerpo) } }
}

struct NotificationsStoreTests {
    let notificador = NotificadorPrueba()
    let store: NotificationsStore

    init() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        store = NotificationsStore(backend: e.backend(secretos), notificador: notificador) { _ in }
    }

    @Test func cuentaLasNoLeidas() async {
        await store.cargar(avisar: false)
        #expect(store.sinLeer == 1)
    }

    @Test func avisaUnaSolaVezSinDetalles() async {
        await store.cargar(avisar: true)
        await store.cargar(avisar: true)
        #expect(notificador.avisos.withLock { $0 } == ["Tienes 1 notificación nueva."])
    }

    @Test func noAvisaSiLaPersonaNoQuiere() async {
        await store.cargar(avisar: false)
        #expect(notificador.avisos.withLock { $0 }.isEmpty)
    }

    @Test func marcarLeidasBajaElContador() async {
        await store.cargar(avisar: false)
        await store.marcarLeidas([502])
        #expect(store.sinLeer == 0)
    }
}
```

`PrototipoAppTests/Stores/AdminStoreTests.swift`:

```swift
//
//  AdminStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct AdminStoreTests {
    @Test func unUsuarioNormalVeElErrorDePermiso() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        try secretos.guardar(try await e.token(EntornoPrueba.usuario), para: .accessToken)
        let admin = AdminStore(backend: e.backend(secretos)) { _ in }
        await admin.cargarCola(estado: nil)
        #expect(admin.cola == .error("No tienes permiso para hacer esto."))
    }

    @Test func elAdministradorVeLaColaYModera() async throws {
        let e = EntornoPrueba()
        let secretos = MemorySecretStore()
        try secretos.guardar(try await e.token(EntornoPrueba.admin), para: .accessToken)
        let admin = AdminStore(backend: e.backend(secretos)) { _ in }
        await admin.cargarCola(estado: nil)
        #expect(admin.cola.valor?.count == 5)
        let r = try await admin.cambiarEstado(id: 117, a: .enRevision, riesgo: nil, observaciones: "")
        #expect(r.estado == .enRevision)
    }
}
```

- [ ] **Paso 2: Ver que fallan** — Run: `UNIT` → FAIL `cannot find 'SessionStore' in scope`.

- [ ] **Paso 3: Implementar `App/NotificadorLocal.swift`**

```swift
//
//  NotificadorLocal.swift
//  PrototipoApp
//
//  Avisos del sistema (notificaciones locales). El texto nunca incluye el título del reporte:
//  se lee en la pantalla bloqueada.
//

import UserNotifications

nonisolated protocol NotificadorLocal: Sendable {
    func pedirPermiso() async -> Bool
    func avisar(titulo: String, cuerpo: String) async
}

nonisolated struct UNNotificador: NotificadorLocal {
    func pedirPermiso() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func avisar(titulo: String, cuerpo: String) async {
        let contenido = UNMutableNotificationContent()
        contenido.title = titulo
        contenido.body = cuerpo
        let disparo = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString,
                                                                                content: contenido, trigger: disparo))
    }
}
```

- [ ] **Paso 4: Implementar `Stores/SessionStore.swift`**

```swift
//
//  SessionStore.swift
//  PrototipoApp
//
//  ¿Hay alguien con sesión y quién es? Guarda el token en el Keychain (SecretStore) y decide la
//  raíz de la app (antes `AppState.isLoggedIn`). Si el servidor dice que la sesión ya no sirve,
//  la cierra en un solo lugar (`expirar`).
//

import Foundation
import Observation

@Observable
final class SessionStore {
    enum Estado: Equatable {
        case restaurando
        case sinSesion
        case activa(Usuario)
    }

    private(set) var estado: Estado = .restaurando
    private(set) var desafio: DesafioDosPasos?
    /// Mensaje que Login muestra arriba: cuenta creada, sesión expirada, cuenta eliminada.
    var aviso: String?
    /// Correo que Login precarga después de registrarse.
    var correoSugerido = ""

    @ObservationIgnored private let backend: any Backend
    @ObservationIgnored private let secretos: any SecretStore

    init(backend: any Backend, secretos: any SecretStore) {
        self.backend = backend
        self.secretos = secretos
    }

    var usuario: Usuario? {
        if case .activa(let u) = estado { return u }
        return nil
    }

    func restaurar() async {
        guard (try? secretos.leer(.accessToken)) != nil else {
            estado = .sinSesion
            return
        }
        do {
            estado = .activa(try await backend.usuarioActual())
        } catch AppError.sinConexion {
            // Sin red no se sabe si el token sirve: se conserva para el próximo intento.
            aviso = AppError.sinConexion.mensaje()
            estado = .sinSesion
        } catch {
            try? secretos.borrarTodo()
            estado = .sinSesion
        }
    }

    func iniciarSesion(correo: String, contrasena: String) async throws {
        switch try await backend.iniciarSesion(correo: Sanitizador.correo(correo), contrasena: contrasena) {
        case .sesion(let s): try abrir(s)
        case .requiereCodigo(let d): desafio = d
        }
    }

    func verificarCodigo(_ codigo: String) async throws {
        guard let desafio else { throw AppError.codigoInvalido }
        try abrir(try await backend.verificarCodigo(desafio: desafio.id, codigo: codigo))
    }

    func cancelarDesafio() { desafio = nil }

    func registrar(_ datos: RegistroDatos) async throws {
        let u = try await backend.registrar(datos)
        correoSugerido = u.correo
        aviso = "Cuenta creada. Inicia sesión para continuar."
    }

    func cerrarSesion() async {
        try? await backend.cerrarSesion()
        try? secretos.borrarTodo()
        estado = .sinSesion
    }

    /// La llaman todos los stores cuando el servidor responde sesión expirada o cuenta suspendida.
    func expirar(_ error: AppError) {
        try? secretos.borrarTodo()
        aviso = error.mensaje()
        desafio = nil
        estado = .sinSesion
    }

    func actualizarPerfil(_ datos: PerfilDatos) async throws {
        estado = .activa(try await conSesion { try await backend.actualizarPerfil(datos) })
    }

    func actualizarPreferencias(_ p: Preferencias, contrasena: String? = nil) async throws {
        estado = .activa(try await conSesion { try await backend.actualizarPreferencias(p, contrasena: contrasena) })
    }

    func actualizarAvatar(_ adjunto: Adjunto?) async throws {
        estado = .activa(try await conSesion { try await backend.actualizarAvatar(adjunto) })
    }

    func datosAvatar(de usuario: Usuario) async -> Data? {
        try? await backend.datosAvatar(de: usuario)
    }

    func recargarUsuario() async {
        if let u = try? await conSesion({ try await backend.usuarioActual() }) { estado = .activa(u) }
    }

    func cambiarContrasena(actual: String, nueva: String) async throws {
        try await conSesion { try await backend.cambiarContrasena(actual: actual, nueva: nueva) }
    }

    func eliminarCuenta(contrasena: String) async throws {
        try await conSesion { try await backend.eliminarCuenta(contrasena: contrasena) }
        try? secretos.borrarTodo()
        aviso = "Tu cuenta se eliminó. Gracias por ayudar a la comunidad."
        estado = .sinSesion
    }

    /// Escribe "Descargar mis datos" en un archivo temporal protegido para compartirlo.
    func exportarDatos() async throws -> URL {
        let datos = try await conSesion { try await backend.exportarMisDatos() }
        let url = FileManager.default.temporaryDirectory.appending(path: "0fraude-mis-datos.json")
        try datos.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    private func abrir(_ s: SesionActiva) throws {
        try secretos.guardar(s.accessToken, para: .accessToken)
        if let refresh = s.refreshToken { try secretos.guardar(refresh, para: .refreshToken) }
        desafio = nil
        aviso = nil
        estado = .activa(s.usuario)
    }

    private func conSesion<T>(_ operacion: () async throws -> T) async throws -> T {
        do {
            return try await operacion()
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            expirar(error)
            throw error
        }
    }
}
```

- [ ] **Paso 5: Implementar `Stores/ReportsStore.swift`**

```swift
//
//  ReportsStore.swift
//  PrototipoApp
//
//  Listas y acciones de reportes para todas las pestañas. Cada cambio sube `version`, y las
//  vistas recargan con `.task(id: reports.version)`: así una tarjeta borrada en Perfil
//  desaparece también de Buscar sin que las vistas se hablen entre sí.
//

import Foundation
import Observation

@Observable
final class ReportsStore {
    private(set) var alertas: Carga<[Reporte]> = .cargando
    private(set) var resultados: Carga<[Reporte]> = .cargando
    private(set) var categorias: Carga<[ConteoCategoria]> = .cargando
    private(set) var mios: Carga<[Reporte]> = .cargando
    private(set) var guardados: Carga<[Reporte]> = .cargando
    private(set) var estadisticas: Carga<EstadisticasComunidad> = .cargando
    private(set) var version = 0

    /// Carpeta donde el formulario deja la evidencia ya limpia antes de enviar.
    @ObservationIgnored let archivos: ArchivosEvidencia
    @ObservationIgnored private let backend: any Backend
    @ObservationIgnored private let alExpirar: (AppError) -> Void

    init(backend: any Backend, archivos: ArchivosEvidencia, alExpirar: @escaping (AppError) -> Void) {
        self.backend = backend
        self.archivos = archivos
        self.alExpirar = alExpirar
    }

    // MARK: Listas

    /// Las 2 más recientes con riesgo ALTO o MUY ALTO ("Alertas críticas" de Inicio).
    func cargarAlertas() async {
        await cargar(\.alertas) { Array(try await self.backend.feed(FiltroBusqueda(riesgoMinimo: .alto)).prefix(2)) }
    }

    func buscar(_ filtro: FiltroBusqueda) async { await cargar(\.resultados) { try await self.backend.feed(filtro) } }
    func cargarCategorias() async { await cargar(\.categorias) { try await self.backend.categorias() } }
    func cargarMios() async { await cargar(\.mios) { try await self.backend.misReportes() } }
    func cargarGuardados() async { await cargar(\.guardados) { try await self.backend.guardados() } }
    func cargarEstadisticas() async { await cargar(\.estadisticas) { try await self.backend.estadisticas() } }

    // MARK: Un reporte

    func detalle(id: Int64) async throws -> Reporte { try await ejecutar { try await backend.detalle(id: id) } }
    func historial(id: Int64) async throws -> [HistorialEstado] { try await ejecutar { try await backend.historial(id: id) } }
    func comentarios(id: Int64) async throws -> [Comentario] { try await ejecutar { try await backend.comentarios(id: id) } }
    func datosEvidencia(_ e: Evidencia) async throws -> Data { try await ejecutar { try await backend.datosEvidencia(e) } }

    // MARK: Cambios (suben `version`)

    func crear(_ b: ReporteBorrador) async throws -> Reporte { try await cambiar { try await backend.crear(b) } }
    func actualizar(id: Int64, _ b: ReporteBorrador) async throws -> Reporte { try await cambiar { try await backend.actualizar(id: id, b) } }
    func eliminar(id: Int64) async throws { try await cambiar { try await backend.eliminar(id: id) } }
    func marcarGuardado(id: Int64, _ guardado: Bool) async throws { try await cambiar { try await backend.marcarGuardado(id: id, guardado) } }
    func confirmar(id: Int64) async throws -> Reporte { try await cambiar { try await backend.confirmar(id: id) } }
    func comentar(id: Int64, texto: String) async throws -> Comentario { try await cambiar { try await backend.comentar(id: id, texto: texto) } }
    func eliminarComentario(id: Int64) async throws { try await cambiar { try await backend.eliminarComentario(id: id) } }

    /// Para cambios hechos en otro store (moderación) que también afectan estas listas.
    func invalidar() { version += 1 }

    func reiniciar() {
        alertas = .cargando
        resultados = .cargando
        categorias = .cargando
        mios = .cargando
        guardados = .cargando
        estadisticas = .cargando
        version = 0
    }

    // MARK: Ayudantes

    /// Si ya había datos se conservan mientras recarga (sin parpadeo); si falla, se muestra el error.
    private func cargar<T>(_ destino: ReferenceWritableKeyPath<ReportsStore, Carga<T>>,
                           _ operacion: () async throws -> T) async {
        if self[keyPath: destino].valor == nil { self[keyPath: destino] = .cargando }
        do {
            self[keyPath: destino] = .listo(try await ejecutar(operacion))
        } catch {
            self[keyPath: destino] = .error(error.mensajeUsuario)
        }
    }

    private func cambiar<T>(_ operacion: () async throws -> T) async throws -> T {
        let resultado = try await ejecutar(operacion)
        version += 1
        return resultado
    }

    private func ejecutar<T>(_ operacion: () async throws -> T) async throws -> T {
        do {
            return try await operacion()
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            alExpirar(error)
            throw error
        }
    }
}
```

- [ ] **Paso 6: Implementar `Stores/NotificationsStore.swift`**

```swift
//
//  NotificationsStore.swift
//  PrototipoApp
//
//  Notificaciones de la persona (Notificacion_Alerta) y el número de la campana. Si activó
//  "Notificaciones" en Ajustes, avisa con una notificación del sistema solo por lo nuevo.
//

import Foundation
import Observation

@Observable
final class NotificationsStore {
    private(set) var lista: Carga<[Notificacion]> = .cargando

    var sinLeer: Int { lista.valor?.filter { !$0.leida }.count ?? 0 }

    @ObservationIgnored private var ultimaAvisada: Int64 = 0
    @ObservationIgnored private let backend: any Backend
    @ObservationIgnored private let notificador: any NotificadorLocal
    @ObservationIgnored private let alExpirar: (AppError) -> Void

    init(backend: any Backend, notificador: any NotificadorLocal, alExpirar: @escaping (AppError) -> Void) {
        self.backend = backend
        self.notificador = notificador
        self.alExpirar = alExpirar
    }

    func cargar(avisar: Bool) async {
        do {
            let nuevas = try await backend.notificaciones()
            lista = .listo(nuevas)
            let sinAvisar = nuevas.filter { !$0.leida && $0.id > ultimaAvisada }
            if avisar && !sinAvisar.isEmpty {
                let cuerpo = sinAvisar.count == 1 ? "Tienes 1 notificación nueva." : "Tienes \(sinAvisar.count) notificaciones nuevas."
                await notificador.avisar(titulo: "0Fraude", cuerpo: cuerpo)
            }
            ultimaAvisada = max(ultimaAvisada, nuevas.map(\.id).max() ?? 0)
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            alExpirar(error)
        } catch {
            if lista.valor == nil { lista = .error(error.mensajeUsuario) }
        }
    }

    func marcarLeidas(_ ids: [Int64]) async {
        guard !ids.isEmpty else { return }
        try? await backend.marcarLeidas(ids)
        guard var actuales = lista.valor else { return }
        for i in actuales.indices where ids.contains(actuales[i].id) { actuales[i].leida = true }
        lista = .listo(actuales)
    }

    func pedirPermiso() async -> Bool { await notificador.pedirPermiso() }

    func reiniciar() {
        lista = .cargando
        ultimaAvisada = 0
    }
}
```

- [ ] **Paso 7: Implementar `Stores/AdminStore.swift`**

```swift
//
//  AdminStore.swift
//  PrototipoApp
//
//  Cola de moderación (Administrador y Owner) y gestión de usuarios (solo Owner). Los permisos
//  los revisa el servidor; aquí solo se muestran sus respuestas.
//

import Foundation
import Observation

@Observable
final class AdminStore {
    private(set) var cola: Carga<[Reporte]> = .cargando
    private(set) var usuarios: Carga<[Usuario]> = .cargando
    private(set) var analiticas: [String: Int] = [:]

    @ObservationIgnored private let backend: any Backend
    @ObservationIgnored private let alExpirar: (AppError) -> Void

    init(backend: any Backend, alExpirar: @escaping (AppError) -> Void) {
        self.backend = backend
        self.alExpirar = alExpirar
    }

    func cargarCola(estado: EstadoReporte?) async {
        if cola.valor == nil { cola = .cargando }
        do { cola = .listo(try await ejecutar { try await backend.colaModeracion(estado: estado) }) }
        catch { cola = .error(error.mensajeUsuario) }
    }

    func cambiarEstado(id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) async throws -> Reporte {
        try await ejecutar { try await backend.cambiarEstado(id: id, a: nuevo, riesgo: riesgo, observaciones: observaciones) }
    }

    func cargarUsuarios() async {
        if usuarios.valor == nil { usuarios = .cargando }
        do {
            usuarios = .listo(try await ejecutar { try await backend.usuarios() })
            analiticas = (try? await backend.analiticas()) ?? [:]
        } catch {
            usuarios = .error(error.mensajeUsuario)
        }
    }

    func cambiarRol(idUsuario: Int64, a rol: Rol) async throws {
        reemplazar(try await ejecutar { try await backend.cambiarRol(idUsuario: idUsuario, a: rol) })
    }

    func cambiarEstadoCuenta(idUsuario: Int64, a estado: EstadoCuenta) async throws {
        reemplazar(try await ejecutar { try await backend.cambiarEstadoCuenta(idUsuario: idUsuario, a: estado) })
    }

    func restablecerDemo() async throws {
        try await ejecutar { try await backend.restablecerDemo() }
    }

    func reiniciar() {
        cola = .cargando
        usuarios = .cargando
        analiticas = [:]
    }

    private func reemplazar(_ u: Usuario) {
        guard var lista = usuarios.valor, let i = lista.firstIndex(where: { $0.id == u.id }) else { return }
        lista[i] = u
        usuarios = .listo(lista)
    }

    private func ejecutar<T>(_ operacion: () async throws -> T) async throws -> T {
        do {
            return try await operacion()
        } catch let error as AppError where error == .sesionExpirada || error == .cuentaSuspendida {
            alExpirar(error)
            throw error
        }
    }
}
```

- [ ] **Paso 8: Pruebas** — Run: `UNIT` → `** TEST SUCCEEDED **`.

- [ ] **Paso 9: Commit**

```bash
git add PrototipoApp/Stores PrototipoApp/App/NotificadorLocal.swift PrototipoAppTests/Stores
git commit -m "feat: stores de sesión, reportes, notificaciones y administración"
```

**Criterios de aceptación:** la sesión sobrevive a un "reinicio" (nuevo `SessionStore` con el mismo `SecretStore`); una sesión vencida avisa al `SessionStore` desde cualquier store; los avisos del sistema no llevan detalles.
**Dependencias:** D8. **Esfuerzo:** M. **Riesgo:** medio (aislamiento de concurrencia; ver sección 10).

### Tarea D10: Integración — `AppState`, rutas, raíz de la app y escudo de privacidad

**Objetivo:** conectar los stores a la app sin romper ninguna pantalla: `Route` con datos, `RootView` según la sesión, `AuthFlow` con pila propia, modo oscuro forzado y la pantalla que tapa la app en el selector de apps.

**Archivos:**
- Modificar: `PrototipoApp/App/AppState.swift` (todo el archivo)
- Modificar: `PrototipoApp/App/OFraudeApp.swift` (todo el archivo)
- Modificar: `PrototipoApp/Views/Route+Destination.swift` (todo el archivo)
- Modificar: `PrototipoApp/Views/Auth/LoginView.swift:11-71` (sesión real, sin `admin`/`admin`)
- Modificar: `PrototipoApp/Views/Auth/RegisterView.swift:28-43` (enlaces por `AuthRoute`)
- Modificar: `PrototipoApp/Views/Account/SignOutView.swift:26` (`session.cerrarSesion()`)
- Modificar: `PrototipoApp/Views/Tabs/HomeView.swift:28-43,93-122` (categorías con `FiltroBusqueda`, alertas con id)
- Modificar: `PrototipoApp/Views/Tabs/SearchView.swift:70,92-100` (`pendingSearch`, id temporal)
- Modificar: `PrototipoApp/Views/Tabs/ProfileView.swift:129` (id temporal de la semilla)
- Modificar: `PrototipoApp/Views/Reports/ReportDetailView.swift:12-13,96` (`id`, `.report(nil)`)
- Test: `PrototipoAppTests/App/AppStateTests.swift` (reescribir)

**Interfaces:**
- Consume: D9, V1 (`LaunchGateView`, `PrivacyShield`).
- Produce: `Route` (`.reportDetail(Int64)`, `.settings`, `.editProfile`, `.privacy`, `.changePassword`, `.signOut`, `.guide`, `.article`, `.stats`, `.report(ReportePrefill?)`, `.editReport(Int64)`, `.reportSuccess(Int64)`, `.notifications`, `.privacyNotice`, `.deleteAccount`, `.adminQueue`, `.adminReview(Int64)`, `.ownerUsers`); `AppState.pendingSearch: FiltroBusqueda?`, `AppState.resetNavigation()`; `AuthRoute` (`.login`, `.aviso`); `EnvironmentValues.appConfig`; `RegisterView(alCrearCuenta:)`, `ReportDetailView(id:)`.

- [ ] **Paso 1: Reescribir la prueba** — `PrototipoAppTests/App/AppStateTests.swift`:

```swift
//
//  AppStateTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct AppStateTests {
    @Test func pushUsaLaPilaDeLaPestanaVisible() {
        let estado = AppState()
        estado.selectedTab = .search
        estado.push(.reportDetail(101))
        #expect(estado.searchPath == [.reportDetail(101)])
        #expect(estado.homePath.isEmpty)
    }

    @Test func popToTabsVaciaTodasLasPilas() {
        let estado = AppState()
        estado.homePath = [.reportDetail(101)]
        estado.profilePath = [.settings, .privacy]
        estado.popToTabs(selecting: .profile)
        #expect(estado.homePath.isEmpty && estado.profilePath.isEmpty)
        #expect(estado.selectedTab == .profile)
    }

    @Test func resetNavigationDejaTodoComoAlAbrir() {
        let estado = AppState()
        estado.selectedTab = .search
        estado.pendingSearch = FiltroBusqueda(tipos: [.llamada])
        estado.profileSegment = .guardados
        estado.reportPath = [.reportSuccess(5)]
        estado.resetNavigation()
        #expect(estado.selectedTab == .home)
        #expect(estado.pendingSearch == nil)
        #expect(estado.profileSegment == .misReportes)
        #expect(estado.reportPath.isEmpty)
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → FAIL (`.reportDetail` no acepta argumento; no existe `resetNavigation`).

- [ ] **Paso 3: Reescribir `App/AppState.swift`**

```swift
//
//  AppState.swift
//  PrototipoApp
//
//  Estado de navegación de la app. En el original, los saltos entre pestañas se hacían buscando
//  controllers dentro del tab bar (`selectedIndex`, `presetQuery`, `showGuardados()`); en SwiftUI
//  basta con cambiar un valor aquí. Quién tiene sesión ya no vive aquí: está en SessionStore.
//  No importa SwiftUI a propósito, para poder probarlo solo.
//

import Observation

enum AppTab: Hashable {
    case home, search, report, profile
}

enum ProfileSegment {
    case misReportes, guardados
}

/// Pantallas que se empujan en la pila de una pestaña. Las que muestran un reporte llevan su id.
enum Route: Hashable {
    case reportDetail(Int64)
    case settings, editProfile, privacy, changePassword, signOut
    case guide, article, stats
    case report(ReportePrefill?)
    case editReport(Int64)
    case reportSuccess(Int64)
    case notifications, privacyNotice, deleteAccount
    case adminQueue, adminReview(Int64), ownerUsers
}

@Observable
final class AppState {
    var selectedTab: AppTab = .home

    /// Búsqueda que Inicio le deja a Buscar (antes `presetQuery`). Buscar la consume y la vacía.
    var pendingSearch: FiltroBusqueda?

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

    /// Deja la navegación como al abrir la app (al cerrar sesión o cuando expira).
    func resetNavigation() {
        popToTabs(selecting: .home)
        pendingSearch = nil
        profileSegment = .misReportes
    }
}
```

- [ ] **Paso 4: Reescribir `App/OFraudeApp.swift`**

```swift
//
//  OFraudeApp.swift
//  PrototipoApp
//
//  Reemplaza: AppDelegate.swift + SceneDelegate.swift + el storyboard principal (Main.storyboard).
//  Crea los stores una sola vez y los comparte con todas las pantallas por el entorno.
//

import SwiftUI

extension EnvironmentValues {
    /// Modo Demo o Remote y los interruptores de las pruebas de interfaz.
    @Entry var appConfig = AppConfig.porDefecto
}

@main
struct OFraudeApp: App {
    @State private var appState = AppState()
    @State private var session: SessionStore
    @State private var reports: ReportsStore
    @State private var notifications: NotificationsStore
    @State private var admin: AdminStore
    private let config: AppConfig

    init() {
        let dependencias = Dependencies.crear(.actual())
        let session = SessionStore(backend: dependencias.backend, secretos: dependencias.secretos)
        let alExpirar: (AppError) -> Void = { session.expirar($0) }
        config = dependencias.config
        _session = State(initialValue: session)
        _reports = State(initialValue: ReportsStore(backend: dependencias.backend, archivos: dependencias.archivos, alExpirar: alExpirar))
        _notifications = State(initialValue: NotificationsStore(backend: dependencias.backend, notificador: UNNotificador(), alExpirar: alExpirar))
        _admin = State(initialValue: AdminStore(backend: dependencias.backend, alExpirar: alExpirar))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(session)
                .environment(reports)
                .environment(notifications)
                .environment(admin)
                .environment(\.appConfig, config)
        }
    }
}

/// Sin sesión: Registro → Login. Con sesión: las pestañas. Mientras se revisa el token guardado,
/// una pantalla de carga. Al perder la sesión se limpia toda la navegación y las listas.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports
    @Environment(NotificationsStore.self) private var notifications
    @Environment(AdminStore.self) private var admin
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.estado {
            case .restaurando: LaunchGateView()
            case .sinSesion: AuthFlow()
            case .activa: MainTabView()
            }
        }
        // La app es oscura por diseño; sin esto, en modo claro la barra de estado no se lee (U3 lo hace configurable).
        .preferredColorScheme(.dark)
        // Tapa el contenido cuando la app sale de primer plano: iOS guarda esa imagen en el selector de apps.
        .overlay { if scenePhase != .active { PrivacyShield() } }
        .task { await session.restaurar() }
        .onChange(of: session.usuario?.id) { _, nuevo in
            guard nuevo == nil else { return }
            appState.resetNavigation()
            reports.reiniciar()
            notifications.reiniciar()
            admin.reiniciar()
        }
    }
}

enum AuthRoute: Hashable {
    case login, aviso
}

/// Escena `nav-scene` del storyboard: Registro como raíz y Login encima.
struct AuthFlow: View {
    @Environment(SessionStore.self) private var session
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            RegisterView { path.append(.login) }
                .navigationDestination(for: AuthRoute.self) { ruta in
                    switch ruta {
                    case .login: LoginView()
                    case .aviso: EmptyView()   // F1 pone aquí PrivacyNoticeView.
                    }
                }
        }
        // Si se llega aquí por sesión expirada o cuenta eliminada, se muestra Login con el aviso.
        .onAppear { if session.aviso != nil { path = [.login] } }
    }
}
```

- [ ] **Paso 5: Reescribir `Views/Route+Destination.swift`**

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
        case .reportDetail(let id): ReportDetailView(id: id)
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
        // Pantallas que llegan en tareas posteriores (F11, F16, F20, F21, F15, F17).
        case .editReport, .notifications, .privacyNotice, .deleteAccount, .adminQueue, .adminReview, .ownerUsers:
            EmptyView()
        }
    }
}
```

M3 comprueba al final que ya no queda `EmptyView()` en este archivo.

- [ ] **Paso 6: Adaptar las vistas para que compilen** (cambios mínimos; las tareas F las completan):

`LoginView.swift`: quitar `demoEmail`/`demoPassword` (líneas 19–20) y `@Environment(AppState.self)`; agregar `@Environment(SessionStore.self) private var session` y `@State private var error: String?`. El botón llama a la sesión real:

```swift
                if let error {
                    Text(error).ofraude(13, .medium, color: Theme.dangerText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button("INICIAR SESIÓN") { Task { await submit() } }
                    .buttonStyle(OfraudeButtonStyle())
```

```swift
    private func submit() async {
        do {
            try await session.iniciarSesion(correo: email, contrasena: password)
        } catch {
            self.error = error.mensajeUsuario
        }
    }
```

`RegisterView.swift`: agregar `var alCrearCuenta: () -> Void = {}`; "CREAR CUENTA" pasa a `Button("CREAR CUENTA", action: alCrearCuenta).buttonStyle(OfraudeButtonStyle())` (F1 le pone el registro real) y "¿Ya tienes cuenta?" pasa a `NavigationLink(value: AuthRoute.login)`.

`SignOutView.swift:26`: `Button("CERRAR SESIÓN") { Task { await session.cerrarSesion() } }` con `@Environment(SessionStore.self) private var session` en lugar de `AppState`.

`HomeView.swift`: `categoryCard` recibe `tipo: TipoFraude` en lugar de `query:` y hace `appState.pendingSearch = FiltroBusqueda(tipos: [tipo]); appState.selectedTab = .search`; llamadas con `.ofertaFalsa`, `.sorteoFalso`, `.tiendaClonada`. `alertCard` recibe `id: Int64` y usa `NavigationLink(value: Route.reportDetail(id))`; llamadas con `101` y `102`.

`SearchView.swift`: `takePresetQuery()` pasa a:

```swift
    private func takePresetQuery() {
        guard let pendiente = appState.pendingSearch else { return }
        query = pendiente.tipos.first?.categoria ?? pendiente.texto
        appState.pendingSearch = nil
    }
```

con `.onChange(of: appState.pendingSearch) { takePresetQuery() }`, y las tarjetas de categoría usan `Route.reportDetail(101)` (F12 las convierte en filtros).

`ProfileView.swift:129`: `NavigationLink(value: Route.reportDetail(idSemilla(report)))` con, al final del struct:

```swift
    /// Temporal hasta F11: las tarjetas fijas apuntan a los reportes equivalentes de la semilla.
    private func idSemilla(_ report: Report) -> Int64 {
        ["mine-1": 121, "mine-2": 122, "saved-1": 101, "saved-2": 102][report.id] ?? 101
    }
```

`ReportDetailView.swift`: agregar `let id: Int64` (sin usarlo todavía), cambiar "Yo también" a `appState.push(.report(nil))` y el `#Preview` a `ReportDetailView(id: 101)`.

Actualizar los `#Preview` que creaban solo `AppState()` para que también inyecten los stores. Agregar en `OFraudeApp.swift` (sin `#if DEBUG`: los `#Preview` también se compilan en Release y necesitan encontrarlo; fuera de ellos no se usa):

```swift
extension View {
    /// Inyecta stores con el servidor Demo en una carpeta temporal, para los Previews.
    func entornoDePrueba() -> some View {
        let dependencias = Dependencies.crear(AppConfig(fuente: .demo, esUITest: true, reiniciarDemo: false, evidenciaDePrueba: false))
        let session = SessionStore(backend: dependencias.backend, secretos: dependencias.secretos)
        return self
            .environment(AppState())
            .environment(session)
            .environment(ReportsStore(backend: dependencias.backend, archivos: dependencias.archivos) { _ in })
            .environment(NotificationsStore(backend: dependencias.backend, notificador: UNNotificador()) { _ in })
            .environment(AdminStore(backend: dependencias.backend) { _ in })
    }
}
```

y en cada vista reemplazar `.environment(AppState())` del `#Preview` por `.entornoDePrueba()`.

- [ ] **Paso 7: Pruebas, build y recorrido rápido**

Run: `UNIT` → `** TEST SUCCEEDED **`; `BUILD` → `** BUILD SUCCEEDED **`; `UI` → `ArranqueUITests/testArrancaEnRegistro` en verde.

Manual (simulador): abrir la app → Registro; "¿Ya tienes cuenta?" → Login; `usuario@0fraude.mx` / `Alerta#2026mx` → Inicio; cerrar la app desde el selector (mientras está en el selector se ve el escudo, no el contenido) y volver a abrir → entra directo a Inicio (sesión en Keychain); Perfil → engrane → Cerrar sesión → Registro. `admin`/`admin` ya no entra ("Correo o contraseña incorrectos.").

- [ ] **Paso 8: Commit**

```bash
git add PrototipoApp PrototipoAppTests
git commit -m "feat: integración de stores, rutas con datos y sesión persistente"
```

**Criterios de aceptación:** la app compila y navega como antes; la sesión sobrevive al reinicio; `admin`/`admin` ya no funciona; el escudo tapa la app en el selector; la barra de estado se lee con el simulador en modo claro (`xcrun simctl ui "iPhone 17" appearance light`).
**Dependencias:** D9, V1. **Esfuerzo:** M. **Riesgo:** medio (toca muchas vistas a la vez; por eso cada cambio es mínimo).

### 2.8 Capa Remote (API del Equipo ZeroScam)

Se construye en paralelo con las fases 3–6 (no bloquea la demo). Si el backend real nombra algo distinto, solo cambia `Data/Remote/`.

### Tarea R1: Contrato de la API y migración SQL para el equipo

**Objetivo:** entregar al Equipo ZeroScam un contrato exacto (rutas, JSON, errores, permisos) y el SQL que agrega a ZeroScam lo que la app necesita, sin tocar el script original del equipo.

**Archivos:**
- Crear: `docs/api-contrato.md`
- Crear: `database/zeroscam_migracion_0fraude.sql`
- Crear: `database/zeroscam_semilla_catalogos.sql`
- No modificar: `database/zeroscam_base_datos.sql` (es entregable del equipo)

**Interfaces:**
- Consume: D1 (forma JSON de los modelos), D2 (protocolos), D6–D7 (reglas del servidor Demo, que son la especificación).
- Produce: las rutas que R3 implementa en `RemoteBackend`.

- [ ] **Paso 1: Escribir `docs/api-contrato.md`** con este contenido (se puede ampliar con ejemplos, sin cambiar rutas ni nombres):

````markdown
# Contrato de la API de 0Fraude

Equipo ZeroScam · versión 2026-10 · lo implementa el backend NestJS; la app lo consume en `PrototipoApp/Data/Remote/`.
La especificación ejecutable es el servidor Demo de la app (`PrototipoApp/Data/Demo/DemoServer*.swift`): mismas reglas, mismos mensajes.

## Reglas generales

- JSON en `camelCase`. Fechas ISO-8601 en UTC (`2026-10-07T18:30:00.000Z`; con o sin milisegundos).
- Enumeraciones con el texto exacto de MySQL: roles `Usuario|Administrador|Policia|Owner`; estados `RECIBIDO|EN_REVISION|VALIDADO|RECHAZADO|CANALIZADO`; tipos `Oferta Falsa|Sorteo Falso|Tienda Clonada|Marketplace|Llamada|Otro`; riesgo `NO_EVALUADO|BAJO|MEDIO|ALTO|MUY_ALTO`; cuenta `ACTIVO|SUSPENDIDO`; afectado `YO|OTRA_PERSONA`.
- Autenticación: `Authorization: Bearer <accessToken>` (JWT de 15 min). Refresh token de 7 días, de un solo uso, guardado en la tabla `Sesion` solo como SHA-256.
- Errores: cuerpo `{ "message": string | string[] }` (formato por defecto de NestJS) y estos códigos:

| Código | Cuándo | La app muestra |
|---|---|---|
| 400 / 422 | Validación | Los mensajes de `message` |
| 401 en `/auth/login` | Correo o contraseña mal | "Correo o contraseña incorrectos." (nunca decir cuál) |
| 401 en otra ruta | Token vencido o revocado | Intenta `/auth/refresh` una vez; si falla, vuelve a Login |
| 403 | Sin permiso; `message: "CUENTA_SUSPENDIDA"` si la cuenta está suspendida | "No tienes permiso…" / "Tu cuenta está suspendida…" |
| 404 | No existe **o no tienes permiso de verlo** (no confirmar existencia) | "Este contenido ya no está disponible." |
| 409 | Duplicado (correo, alias) o transición de estado inválida | `message` |
| 423 | Cuenta bloqueada por intentos; encabezado `Retry-After` en segundos | "Demasiados intentos…" |
| 429 | Límite de uso (10 reportes/día, 5 comentarios/min); `Retry-After` | `message` |

## Autenticación

| Método y ruta | Cuerpo | Respuesta | Notas |
|---|---|---|---|
| `POST /auth/registro` | `{nombre, apellido, pais, alias, correo, contrasena, aceptaAviso, versionAviso}` | `201 Usuario` | Hash bcrypt/argon2 en el servidor; guarda versión y fecha del aviso aceptado |
| `POST /auth/login` | `{correo, contrasena}` | `200 {accessToken, refreshToken, usuario}` o `200 {requiereCodigo: true, desafio: {id, destino, expira}}` | 5 fallos por correo → 423 con bloqueo de 1 min que se duplica hasta 15 min; mismo tiempo de respuesta si el correo no existe |
| `POST /auth/2fa` | `{desafio, codigo}` | `200 {accessToken, refreshToken, usuario}` | Código de 6 dígitos, 5 min, 3 intentos |
| `POST /auth/refresh` | `{refreshToken}` | `200 {accessToken, refreshToken}` | Rota el refresh token |
| `POST /auth/logout` | `{refreshToken}` | `204` | Revoca la sesión |
| `GET /auth/yo` | — | `200 Usuario` | |
| `PUT /auth/contrasena` | `{actual, nueva}` | `204` | Revoca las demás sesiones |
| `DELETE /auth/cuenta` | `{contrasena}` | `204` | Anonimiza lo público (`Reporte.id_usuario = NULL`), borra lo demás |

## Reportes

| Método y ruta | Cuerpo / consulta | Respuesta | Quién |
|---|---|---|---|
| `GET /reportes` | `?texto=&tipos=Llamada,Otro&riesgoMinimo=ALTO` | `200 [Reporte]` solo VALIDADO y CANALIZADO, más recientes primero | Con sesión |
| `GET /reportes/mios` | — | `200 [Reporte]` todos los estados | Autor |
| `GET /reportes/guardados` | — | `200 [Reporte]` | Con sesión |
| `GET /reportes/{id}` | — | `200 Reporte` | Público, autor o staff; si no, 404 |
| `POST /reportes` | `ReporteEntrada` | `201 Reporte` (estado RECIBIDO + fila inicial en Historial_Estado) | Con sesión; 10 por día |
| `PUT /reportes/{id}` | `ReporteEntrada` + `quitarEvidencias: [id]` | `200 Reporte` | Autor, solo RECIBIDO o EN_REVISION |
| `DELETE /reportes/{id}` | — | `204` | Autor o staff |
| `POST /reportes/{id}/evidencias` | `multipart/form-data`, campo `archivo` (JPEG ≤ 5 MB o PDF ≤ 10 MB) | `201 Evidencia` | Autor; máximo 3 |
| `GET /evidencias/{id}/archivo` | — | bytes | Autor o staff |
| `PUT /reportes/{id}/guardado` | — | `204` (idempotente) | Con sesión |
| `DELETE /reportes/{id}/guardado` | — | `204` | Con sesión |
| `PUT /reportes/{id}/confirmacion` | — | `200 Reporte` (idempotente) | No el autor; solo públicos |
| `GET /reportes/{id}/comentarios` | — | `200 [Comentario]` | Quien puede ver el reporte |
| `POST /reportes/{id}/comentarios` | `{texto}` (2–500) | `201 Comentario` | Solo reportes públicos; 5 por minuto |
| `DELETE /comentarios/{id}` | — | `204` | Autor del comentario o staff |
| `GET /reportes/{id}/historial` | — | `200 [HistorialEstado]` | Autor (ve "Equipo de moderación") o staff (ve el alias) |
| `GET /estadisticas` | — | `200 {personasAyudadas, reportesVerificados, estafasDetenidas, zonasCubiertas}` | Con sesión |
| `GET /estadisticas/categorias` | — | `200 [{tipo, total, riesgoMaximo}]` | Con sesión |

`ReporteEntrada`: `{esAnonimo, afectado, persona: {nombre, contacto, autorizo} | null, ciudad, tipo, tipoOtro, titulo, fechaIncidente, urlOTexto, descripcion}`. Si `urlOTexto` es una URL http/https válida se normaliza y se liga en `Reporte_URL`; si no, va a `texto_sospechoso`.

## Perfil y notificaciones

| Método y ruta | Cuerpo | Respuesta |
|---|---|---|
| `PUT /perfil` | `{nombre, apellido, pais, alias, correo, biografia, contrasenaActual?}` | `200 Usuario` (`contrasenaActual` obligatoria si cambia el correo) |
| `PUT /perfil/preferencias` | `{preferencias, contrasena?}` | `200 Usuario` (`contrasena` obligatoria para apagar 2 pasos) |
| `PUT /perfil/avatar` | `multipart/form-data`, campo `archivo` (JPEG) | `200 Usuario` |
| `DELETE /perfil/avatar` | — | `200 Usuario` |
| `GET /usuarios/{id}/avatar` | — | bytes o 404 (propio, staff o perfil público) |
| `GET /perfil/exportacion` | — | `200` JSON con usuario, reportes, comentarios, guardados, confirmaciones y notificaciones |
| `GET /notificaciones` | — | `200 [Notificacion]` |
| `PUT /notificaciones/leidas` | `{ids: [id]}` | `204` (ignora ids ajenos) |

## Administración

| Método y ruta | Cuerpo / consulta | Respuesta | Quién |
|---|---|---|---|
| `GET /admin/reportes` | `?estado=RECIBIDO` (sin estado = RECIBIDO y EN_REVISION) | `200 [Reporte]` más viejos primero | Administrador, Owner |
| `PUT /admin/reportes/{id}/estado` | `{estado, nivelRiesgo?, observaciones}` | `200 Reporte` | Administrador, Owner; transiciones de `EstadoReporte.siguientes`; nadie modera lo suyo; riesgo obligatorio al validar; motivo (10–500) al rechazar; notifica al autor |
| `GET /admin/usuarios` | — | `200 [Usuario]` | Owner |
| `PUT /admin/usuarios/{id}/rol` | `{rol}` (`Usuario` o `Administrador`) | `200 Usuario` | Owner; no a sí mismo ni a otro Owner |
| `PUT /admin/usuarios/{id}/estado` | `{estadoCuenta}` | `200 Usuario` (suspender revoca sesiones) | Owner |
| `GET /admin/analiticas` | — | `200 {"busqueda": 3, "reporte_enviado": 1, "inicio_sesion": 9}` | Owner |

## Formas JSON

`Usuario`:

```json
{ "id": 3, "rol": "Usuario", "nombre": "Ana", "apellido": "López", "pais": "México", "alias": "usuario_01",
  "correo": "usuario@0fraude.mx", "biografia": "", "avatarRuta": null, "estadoCuenta": "ACTIVO",
  "fechaRegistro": "2026-09-07T00:00:00.000Z",
  "preferencias": { "notificaciones": false, "modoOscuro": true, "dosPasos": false, "perfilPublico": false, "analiticas": true },
  "consentimiento": { "versionAviso": "2026-10", "fecha": "2026-09-07T00:00:00.000Z" } }
```

`Reporte` (lo que **esa** persona puede ver; el servidor quita `personaAfectada` y `evidencias` si no es autor ni staff, y oculta el autor si es anónimo o de perfil privado):

```json
{ "id": 101, "autor": { "idUsuario": 4, "nombre": "tecno_mx" }, "tipo": "Oferta Falsa", "tipoOtro": null,
  "estado": "VALIDADO", "titulo": "Falsa liquidación de tienda de electrónica", "descripcion": "…",
  "fechaIncidente": "2026-10-06T16:00:00.000Z", "nivelRiesgo": "ALTO", "fechaCreacion": "2026-10-06T22:00:00.000Z",
  "esAnonimo": false, "afectado": "YO", "ciudad": "CDMX", "personaAfectada": null,
  "sitio": { "id": 201, "url": "https://liquidacion-electronica-mx.shop", "nivelRiesgoGlobal": "ALTO",
             "estadoCertificado": "HTTPS", "fechaUltimaEvaluacion": "2026-10-06T23:00:00.000Z" },
  "textoSospechoso": null, "evidencias": [], "totalEvidencias": 0,
  "confirmaciones": 1200, "comentarios": 2, "confirmadoPorMi": false, "guardadoPorMi": true, "esMio": false }
```

`Comentario`: `{id, idReporte, autor, esMio, texto, fecha}`. `HistorialEstado`: `{id, idReporte, responsable, anterior, nuevo, observaciones, fecha}`. `Notificacion`: `{id, idReporte, mensaje, leida, fecha}`. `Evidencia`: `{id, rutaArchivo, tipoArchivo, fechaCarga}`.

`confirmaciones` = `COUNT(*)` de `Reporte_Confirmacion`. (El modo Demo suma además un conteo histórico de la semilla.)

## Cambios al esquema

Ver `database/zeroscam_migracion_0fraude.sql` (columnas y tablas nuevas) y `database/zeroscam_semilla_catalogos.sql` (Rol, Estado, TipoFraude).
````

- [ ] **Paso 2: Escribir `database/zeroscam_migracion_0fraude.sql`**

```sql
-- 0Fraude · Migración propuesta por la app (Equipo ZeroScam), versión 2026-10.
-- Se aplica sobre la base creada con zeroscam_base_datos.sql. Revisar con el equipo antes de correrla.
USE ZeroScam;

-- 1. Usuario: alias público, biografía, avatar, preferencias, consentimiento (LFPDPPP) y bloqueo por intentos
ALTER TABLE Usuario
    ADD COLUMN alias VARCHAR(20) NULL UNIQUE AFTER apellido,
    ADD COLUMN biografia VARCHAR(300) NOT NULL DEFAULT '' AFTER pais,
    ADD COLUMN avatar_ruta VARCHAR(500) NULL,
    ADD COLUMN preferencias JSON NULL,
    ADD COLUMN aviso_version VARCHAR(20) NULL COMMENT 'Versión del aviso de privacidad aceptada',
    ADD COLUMN aviso_fecha TIMESTAMP NULL,
    ADD COLUMN intentos_fallidos INT NOT NULL DEFAULT 0,
    ADD COLUMN bloqueado_hasta TIMESTAMP NULL;

-- 2. Reporte: campos del formulario de la app
ALTER TABLE Reporte
    ADD COLUMN titulo VARCHAR(120) NOT NULL DEFAULT '' AFTER id_estado,
    ADD COLUMN es_anonimo BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN afectado VARCHAR(20) NOT NULL DEFAULT 'YO' COMMENT 'YO, OTRA_PERSONA',
    ADD COLUMN ciudad VARCHAR(60) NOT NULL DEFAULT '',
    ADD COLUMN tipo_otro VARCHAR(50) NULL,
    ADD COLUMN texto_sospechoso VARCHAR(2048) NULL;

-- 3. Reporte.id_usuario admite NULL para anonimizar al borrar la cuenta.
-- MySQL llama Reporte_ibfk_1 a la primera llave foránea sin nombre; confirmar con SHOW CREATE TABLE Reporte;
ALTER TABLE Reporte DROP FOREIGN KEY Reporte_ibfk_1;
ALTER TABLE Reporte MODIFY id_usuario BIGINT NULL;
ALTER TABLE Reporte ADD CONSTRAINT fk_reporte_usuario
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario) ON DELETE SET NULL;

-- 4. Tablas nuevas
CREATE TABLE PersonaAfectada (
    id_reporte BIGINT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    contacto VARCHAR(150) NOT NULL,
    autorizo BOOLEAN NOT NULL COMMENT 'El reportante confirma la autorización de la persona',
    FOREIGN KEY (id_reporte) REFERENCES Reporte(id_reporte) ON DELETE CASCADE
);

CREATE TABLE Comentario (
    id_comentario BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_reporte BIGINT NOT NULL,
    id_usuario BIGINT NULL,
    texto VARCHAR(500) NOT NULL,
    fecha TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_reporte) REFERENCES Reporte(id_reporte) ON DELETE CASCADE,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario) ON DELETE SET NULL,
    INDEX idx_comentario_reporte (id_reporte)
);

CREATE TABLE Reporte_Guardado (
    id_usuario BIGINT NOT NULL,
    id_reporte BIGINT NOT NULL,
    fecha TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_usuario, id_reporte),
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario) ON DELETE CASCADE,
    FOREIGN KEY (id_reporte) REFERENCES Reporte(id_reporte) ON DELETE CASCADE
);

CREATE TABLE Reporte_Confirmacion (
    id_usuario BIGINT NOT NULL,
    id_reporte BIGINT NOT NULL,
    fecha TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_usuario, id_reporte),
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario) ON DELETE CASCADE,
    FOREIGN KEY (id_reporte) REFERENCES Reporte(id_reporte) ON DELETE CASCADE
);

CREATE TABLE Sesion (
    id_sesion BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_usuario BIGINT NOT NULL,
    refresh_token_hash CHAR(64) NOT NULL UNIQUE COMMENT 'SHA-256 en hexadecimal; nunca el token en claro',
    creada TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expira TIMESTAMP NOT NULL,
    revocada BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario) ON DELETE CASCADE
);

CREATE TABLE Desafio_DosPasos (
    id_desafio CHAR(43) PRIMARY KEY,
    id_usuario BIGINT NOT NULL,
    codigo_hash CHAR(64) NOT NULL,
    expira TIMESTAMP NOT NULL,
    intentos INT NOT NULL DEFAULT 0,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario) ON DELETE CASCADE
);
```

- [ ] **Paso 3: Escribir `database/zeroscam_semilla_catalogos.sql`**

```sql
-- 0Fraude · Catálogos que la app espera (Equipo ZeroScam). Los textos son los rawValue de Model/Catalogos.swift.
USE ZeroScam;

INSERT INTO Rol (nombre_rol, descripcion) VALUES
    ('Usuario', 'Reporta, comenta y guarda reportes'),
    ('Administrador', 'Modera reportes y asigna nivel de riesgo'),
    ('Policia', 'Recibe reportes canalizados (sin interfaz en la app)'),
    ('Owner', 'Administra usuarios y roles');

INSERT INTO Estado (nombre_estado, descripcion, es_final, orden) VALUES
    ('RECIBIDO', 'El reporte llegó y espera revisión', FALSE, 1),
    ('EN_REVISION', 'Un administrador lo está revisando', FALSE, 2),
    ('VALIDADO', 'Se confirmó y es visible para la comunidad', FALSE, 3),
    ('RECHAZADO', 'No procede; se explica el motivo', TRUE, 4),
    ('CANALIZADO', 'Se envió a las autoridades', TRUE, 5);

INSERT INTO TipoFraude (nombre_tipo, descripcion) VALUES
    ('Oferta Falsa', 'Descuentos irreales y liquidaciones que nunca llegan.'),
    ('Sorteo Falso', 'Concursos y premios falsos que piden tus datos o dinero.'),
    ('Tienda Clonada', 'Sitios web que imitan marcas conocidas para robar tu pago.'),
    ('Marketplace', 'Vendedores falsos en redes que cobran y no entregan.'),
    ('Llamada', 'Llamadas y mensajes que se hacen pasar por bancos o autoridades.'),
    ('Otro', 'Phishing, empleos y préstamos falsos, y otros engaños.');
```

- [ ] **Paso 4: Verificar el SQL en una base de prueba** (lo corre Alex; pide su contraseña de MySQL, que no se comparte). Sugerirle escribir en el prompt:

```text
! cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI/database" && for f in zeroscam_base_datos.sql zeroscam_migracion_0fraude.sql zeroscam_semilla_catalogos.sql; do sed 's/ZeroScam;/ZeroScam_prueba;/' "$f"; done | mysql -u root -p && mysql -u root -p -e "USE ZeroScam_prueba; SHOW TABLES; SELECT COUNT(*) FROM Estado;"
```

Expected: 16 tablas (10 originales + 6 nuevas) y `COUNT(*) = 5`. Si `DROP FOREIGN KEY Reporte_ibfk_1` falla, correr `SHOW CREATE TABLE Reporte;` y usar el nombre real. Al terminar: `! mysql -u root -p -e "DROP DATABASE ZeroScam_prueba;"`.

- [ ] **Paso 5: Commit**

```bash
git add docs/api-contrato.md database/zeroscam_migracion_0fraude.sql database/zeroscam_semilla_catalogos.sql
git commit -m "docs: contrato de la API y migración SQL propuesta para el equipo"
```

**Criterios de aceptación:** cada método de los 5 protocolos tiene una ruta en el contrato; el SQL corre limpio en `ZeroScam_prueba`; `zeroscam_base_datos.sql` sin cambios (`git diff --stat database/zeroscam_base_datos.sql` vacío).
**Dependencias:** D2, D6, D7. **Esfuerzo:** M. **Riesgo:** bajo (el nombre de la llave foránea se confirma en el paso 4).

### Tarea R2: Cliente HTTP con refresh y ATS

**Objetivo:** un `actor APIClient` que pone el Bearer, reintenta una vez tras renovar el token (una sola renovación aunque fallen varias peticiones a la vez), traduce los errores de NestJS y solo permite HTTPS (HTTP únicamente a la propia Mac).

**Archivos:**
- Crear: `PrototipoApp/Data/Remote/APIClient.swift`
- Crear: `PrototipoApp/Data/Remote/DTOs.swift`
- Modificar: `PrototipoApp/Info.plist` (`NSAppTransportSecurity` → `NSAllowsLocalNetworking`)
- Test: `PrototipoAppTests/Remote/URLProtocolStub.swift`, `PrototipoAppTests/Remote/APIClientTests.swift`

**Interfaces:**
- Consume: D2, S2, D3 (`Codificacion`).
- Produce: `Endpoint` (`metodo`, `ruta`, `consulta`, `cuerpo`, `tipoContenido`, `requiereSesion`); `actor APIClient(base:sesion:secretos:)` con `pedir<T>(_:como:) -> T`, `ejecutar(_:)`, `pedirDatos(_:) -> Data`, `nonisolated static error(de:datos:ruta:) -> AppError`; DTOs `TokensDTO`, `ErrorDTO`, `LoginRespuestaDTO`, `RegistroDTO`, `ReporteEntradaDTO`, `PerfilDTO`, `PreferenciasDTO`, `EstadoDTO`, `IdsDTO`, `RolDTO`, `EstadoCuentaDTO`, `Multipart`.

- [ ] **Paso 1: Stub de red para pruebas** — `PrototipoAppTests/Remote/URLProtocolStub.swift`:

```swift
//
//  URLProtocolStub.swift
//  PrototipoAppTests
//
//  Responde peticiones sin red. Cada prueba usa un host propio para no mezclarse con otras que
//  corren en paralelo.
//

import Foundation
import Synchronization

nonisolated final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated struct Respuesta: Sendable {
        let estado: Int
        var cuerpo = Data()
        var encabezados: [String: String] = [:]
    }

    /// Respuestas en orden por "MÉTODO host/ruta"; `sinRed` contiene hosts que fallan como sin conexión.
    nonisolated(unsafe) private static var respuestas: [String: [Respuesta]] = [:]
    private static let candado = Mutex<[URLRequest]>([])
    nonisolated(unsafe) private static var sinRed: Set<String> = []
    private static let cola = NSLock()

    static func preparar(_ clave: String, _ lista: [Respuesta]) {
        cola.withLock { respuestas[clave] = lista }
    }

    static func cortarRed(host: String) {
        cola.withLock { _ = sinRed.insert(host) }
    }

    static func peticiones(host: String) -> [URLRequest] {
        candado.withLock { $0.filter { $0.url?.host() == host } }
    }

    static func sesion() -> URLSession {
        let configuracion = URLSessionConfiguration.ephemeral
        configuracion.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuracion)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.candado.withLock { $0.append(request) }
        let host = request.url?.host() ?? ""
        let clave = "\(request.httpMethod ?? "GET") \(host)\(request.url?.path() ?? "")"
        let respuesta: Respuesta? = Self.cola.withLock {
            if Self.sinRed.contains(host) { return nil }
            guard var lista = Self.respuestas[clave], !lista.isEmpty else { return Respuesta(estado: 404) }
            let primera = lista.removeFirst()
            Self.respuestas[clave] = lista
            return primera
        }
        guard let respuesta, let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: respuesta.estado, httpVersion: nil, headerFields: respuesta.encabezados)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: respuesta.cuerpo)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Lee el cuerpo de una petición interceptada (URLProtocol lo entrega como stream).
nonisolated func cuerpo(de peticion: URLRequest) -> Data {
    if let datos = peticion.httpBody { return datos }
    guard let stream = peticion.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var datos = Data()
    var bufer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let leidos = stream.read(&bufer, maxLength: bufer.count)
        guard leidos > 0 else { break }
        datos.append(bufer, count: leidos)
    }
    return datos
}
```

- [ ] **Paso 2: Pruebas que fallan** — `PrototipoAppTests/Remote/APIClientTests.swift`:

```swift
//
//  APIClientTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct APIClientTests {
    let host = "\(UUID().uuidString.lowercased()).test"
    var base: URL { URL(string: "https://\(host)")! }
    let secretos = MemorySecretStore()

    private func cliente() -> APIClient { APIClient(base: base, sesion: URLProtocolStub.sesion(), secretos: secretos) }
    private func clave(_ metodo: String, _ ruta: String) -> String { "\(metodo) \(host)\(ruta)" }

    @Test func agregaElBearer() async throws {
        try secretos.guardar("abc", para: .accessToken)
        URLProtocolStub.preparar(clave("GET", "/reportes/mios"), [.init(estado: 200, cuerpo: Data("[]".utf8))])
        let lista: [Reporte] = try await cliente().pedir(Endpoint(ruta: "/reportes/mios"))
        #expect(lista.isEmpty)
        #expect(URLProtocolStub.peticiones(host: host).first?.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func tras401RenuevaYReintentaUnaVez() async throws {
        try secretos.guardar("viejo", para: .accessToken)
        try secretos.guardar("refresh", para: .refreshToken)
        URLProtocolStub.preparar(clave("GET", "/reportes/mios"), [.init(estado: 401), .init(estado: 200, cuerpo: Data("[]".utf8))])
        URLProtocolStub.preparar(clave("POST", "/auth/refresh"), [.init(estado: 200, cuerpo: Data(#"{"accessToken":"nuevo"}"#.utf8))])
        let _: [Reporte] = try await cliente().pedir(Endpoint(ruta: "/reportes/mios"))
        let peticiones = URLProtocolStub.peticiones(host: host)
        #expect(peticiones.count == 3)
        #expect(peticiones.last?.value(forHTTPHeaderField: "Authorization") == "Bearer nuevo")
        #expect(try secretos.leer(.accessToken) == "nuevo")
    }

    @Test func refreshRechazadoBorraLosTokens() async throws {
        try secretos.guardar("viejo", para: .accessToken)
        try secretos.guardar("refresh", para: .refreshToken)
        URLProtocolStub.preparar(clave("GET", "/reportes/mios"), [.init(estado: 401)])
        URLProtocolStub.preparar(clave("POST", "/auth/refresh"), [.init(estado: 401)])
        await #expect(throws: AppError.sesionExpirada) { let _: [Reporte] = try await cliente().pedir(Endpoint(ruta: "/reportes/mios")) }
        #expect(try secretos.leer(.accessToken) == nil)
    }

    @Test func sinRedConservaLosTokens() async throws {
        try secretos.guardar("abc", para: .accessToken)
        URLProtocolStub.cortarRed(host: host)
        await #expect(throws: AppError.sinConexion) { let _: [Reporte] = try await cliente().pedir(Endpoint(ruta: "/reportes")) }
        #expect(try secretos.leer(.accessToken) == "abc")
    }

    @Test func traduceLosMensajesDeNest() async throws {
        URLProtocolStub.preparar(clave("POST", "/auth/registro"),
                                 [.init(estado: 400, cuerpo: Data(#"{"message":["correo must be an email","alias too short"]}"#.utf8))])
        await #expect(throws: AppError.validacion(["correo must be an email\nalias too short"])) {
            try await cliente().ejecutar(Endpoint(metodo: "POST", ruta: "/auth/registro", cuerpo: Data("{}".utf8), requiereSesion: false))
        }
    }

    @Test func loginIncorrectoNoIntentaRenovar() async throws {
        URLProtocolStub.preparar(clave("POST", "/auth/login"), [.init(estado: 401)])
        await #expect(throws: AppError.credencialesInvalidas) {
            try await cliente().ejecutar(Endpoint(metodo: "POST", ruta: "/auth/login", cuerpo: Data("{}".utf8), requiereSesion: false))
        }
        #expect(URLProtocolStub.peticiones(host: host).count == 1)
    }

    @Test func bloqueoUsaRetryAfter() {
        let r = HTTPURLResponse(url: URL(string: "https://x.test")!, statusCode: 423, httpVersion: nil, headerFields: ["Retry-After": "120"])!
        guard case .cuentaBloqueada(let hasta) = APIClient.error(de: r, datos: Data(), ruta: "/auth/login") else {
            Issue.record("Debía ser bloqueo"); return
        }
        #expect(hasta.timeIntervalSinceNow > 100)
    }
}
```

- [ ] **Paso 3: Ver que fallan** — Run: `UNIT` → FAIL `cannot find 'APIClient' in scope`.

- [ ] **Paso 4: Implementar `Data/Remote/DTOs.swift`**

```swift
//
//  DTOs.swift
//  PrototipoApp
//
//  Cuerpos que viajan a la API y que no son exactamente un modelo de Model/. Los nombres son
//  los de docs/api-contrato.md. BACKEND: si el equipo usa otros nombres, se cambian solo aquí.
//

import Foundation

nonisolated struct TokensDTO: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
}

/// `{ "message": "texto" }` o `{ "message": ["uno", "dos"] }`, como responde NestJS.
nonisolated struct ErrorDTO: Decodable, Sendable {
    let texto: String

    private enum Claves: String, CodingKey { case message }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        if let uno = try? c.decode(String.self, forKey: .message) {
            texto = uno
        } else {
            texto = try c.decode([String].self, forKey: .message).joined(separator: "\n")
        }
    }
}

nonisolated struct LoginRespuestaDTO: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let usuario: Usuario?
    let requiereCodigo: Bool?
    let desafio: DesafioDosPasos?
}

nonisolated struct RegistroDTO: Encodable, Sendable {
    let nombre, apellido, pais, alias, correo, contrasena: String
    let aceptaAviso: Bool
    let versionAviso: String

    init(_ d: RegistroDatos) {
        nombre = d.nombre
        apellido = d.apellido
        pais = d.pais
        alias = d.alias
        correo = d.correo
        contrasena = d.contrasena
        aceptaAviso = d.aceptaAviso
        versionAviso = Consentimiento.versionAvisoVigente
    }
}

nonisolated struct ReporteEntradaDTO: Encodable, Sendable {
    let esAnonimo: Bool
    let afectado: Afectado
    let persona: PersonaAfectada?
    let ciudad: String
    let tipo: TipoFraude
    let tipoOtro: String?
    let titulo: String
    let fechaIncidente: Date
    let urlOTexto: String
    let descripcion: String
    let quitarEvidencias: [Int64]

    init(_ b: ReporteBorrador) {
        esAnonimo = b.esAnonimo
        afectado = b.afectado
        persona = b.afectado == .otraPersona ? b.persona : nil
        ciudad = b.ciudad
        tipo = b.tipo
        tipoOtro = b.tipo == .otro ? b.tipoOtro : nil
        titulo = b.titulo
        fechaIncidente = b.fechaIncidente
        urlOTexto = b.urlOTexto
        descripcion = b.descripcion
        quitarEvidencias = b.quitarEvidencias.sorted()
    }
}

nonisolated struct PerfilDTO: Encodable, Sendable {
    let nombre, apellido, pais, alias, correo, biografia: String
    let contrasenaActual: String?

    init(_ p: PerfilDatos) {
        nombre = p.nombre
        apellido = p.apellido
        pais = p.pais
        alias = p.alias
        correo = p.correo
        biografia = p.biografia
        contrasenaActual = p.contrasenaActual
    }
}

nonisolated struct PreferenciasDTO: Encodable, Sendable {
    let preferencias: Preferencias
    let contrasena: String?
}

nonisolated struct EstadoDTO: Encodable, Sendable {
    let estado: EstadoReporte
    let nivelRiesgo: NivelRiesgo?
    let observaciones: String
}

nonisolated struct IdsDTO: Encodable, Sendable { let ids: [Int64] }
nonisolated struct RolDTO: Encodable, Sendable { let rol: Rol }
nonisolated struct EstadoCuentaDTO: Encodable, Sendable { let estadoCuenta: EstadoCuenta }

/// Cuerpo `multipart/form-data` con un solo archivo en el campo `archivo`.
nonisolated enum Multipart {
    static func cuerpo(archivo: Data, nombre: String, tipo: String, limite: String) -> Data {
        var datos = Data()
        datos.append(Data("--\(limite)\r\n".utf8))
        datos.append(Data("Content-Disposition: form-data; name=\"archivo\"; filename=\"\(nombre)\"\r\n".utf8))
        datos.append(Data("Content-Type: \(tipo)\r\n\r\n".utf8))
        datos.append(archivo)
        datos.append(Data("\r\n--\(limite)--\r\n".utf8))
        return datos
    }
}
```

- [ ] **Paso 5: Implementar `Data/Remote/APIClient.swift`**

```swift
//
//  APIClient.swift
//  PrototipoApp
//
//  Cliente HTTP del backend NestJS del Equipo ZeroScam. Mismo patrón que `src/lib/api.ts` del
//  demo del profesor (Frontendwebautenticado): Bearer en cada petición; si responde 401 se pide
//  un access token nuevo con el refresh token y se reintenta una sola vez. Si el servidor
//  rechaza el refresh, la sesión terminó; si ni siquiera respondió, los tokens se conservan.
//

import Foundation

nonisolated struct Endpoint: Sendable {
    var metodo = "GET"
    var ruta: String
    var consulta: [URLQueryItem] = []
    var cuerpo: Data?
    var tipoContenido = "application/json"
    var requiereSesion = true
}

actor APIClient {
    private let base: URL
    private let sesion: URLSession
    private let secretos: any SecretStore
    private var refrescando: Task<Void, Error>?

    init(base: URL, sesion: URLSession = .shared, secretos: any SecretStore) {
        self.base = base
        self.sesion = sesion
        self.secretos = secretos
    }

    func pedir<T: Decodable & Sendable>(_ endpoint: Endpoint, como: T.Type = T.self) async throws -> T {
        let datos = try await conReintento(endpoint)
        do {
            return try Codificacion.decoder().decode(T.self, from: datos)
        } catch {
            throw AppError.servidor("Respuesta inesperada del servidor.")
        }
    }

    func ejecutar(_ endpoint: Endpoint) async throws {
        _ = try await conReintento(endpoint)
    }

    func pedirDatos(_ endpoint: Endpoint) async throws -> Data {
        try await conReintento(endpoint)
    }

    private func conReintento(_ endpoint: Endpoint, reintento: Bool = false) async throws -> Data {
        let (datos, respuesta) = try await enviar(endpoint)
        switch respuesta.statusCode {
        case 200..<300:
            return datos
        case 401 where endpoint.requiereSesion && !reintento:
            try await refrescar()
            return try await conReintento(endpoint, reintento: true)
        default:
            throw Self.error(de: respuesta, datos: datos, ruta: endpoint.ruta)
        }
    }

    private func enviar(_ e: Endpoint) async throws -> (Data, HTTPURLResponse) {
        guard var componentes = URLComponents(url: base.appending(path: e.ruta), resolvingAgainstBaseURL: false) else {
            throw AppError.sinConexion
        }
        if !e.consulta.isEmpty { componentes.queryItems = e.consulta }
        guard let url = componentes.url else { throw AppError.sinConexion }
        var peticion = URLRequest(url: url)
        peticion.httpMethod = e.metodo
        peticion.httpBody = e.cuerpo
        peticion.timeoutInterval = 20
        peticion.setValue("application/json", forHTTPHeaderField: "Accept")
        if e.cuerpo != nil { peticion.setValue(e.tipoContenido, forHTTPHeaderField: "Content-Type") }
        if e.requiereSesion, let token = try? secretos.leer(.accessToken) {
            peticion.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (datos, respuesta) = try await sesion.data(for: peticion)
            guard let http = respuesta as? HTTPURLResponse else { throw AppError.sinConexion }
            return (datos, http)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.sinConexion
        }
    }

    /// Una sola renovación aunque fallen varias peticiones a la vez (como `refreshing ??=` en api.ts).
    private func refrescar() async throws {
        if let refrescando { return try await refrescando.value }
        let tarea = Task { try await self.pedirAccessToken() }
        refrescando = tarea
        defer { refrescando = nil }
        try await tarea.value
    }

    private func pedirAccessToken() async throws {
        guard let refresh = try? secretos.leer(.refreshToken) else { throw AppError.sesionExpirada }
        let cuerpo = try Codificacion.encoder().encode(["refreshToken": refresh])
        let (datos, respuesta) = try await enviar(Endpoint(metodo: "POST", ruta: "/auth/refresh", cuerpo: cuerpo, requiereSesion: false))
        guard (200..<300).contains(respuesta.statusCode) else {
            try? secretos.borrarTodo()
            throw AppError.sesionExpirada
        }
        let tokens = try Codificacion.decoder().decode(TokensDTO.self, from: datos)
        try secretos.guardar(tokens.accessToken, para: .accessToken)
        if let nuevo = tokens.refreshToken { try secretos.guardar(nuevo, para: .refreshToken) }
    }

    /// Códigos de docs/api-contrato.md → errores que la app sabe mostrar.
    nonisolated static func error(de r: HTTPURLResponse, datos: Data, ruta: String) -> AppError {
        let mensaje = (try? Codificacion.decoder().decode(ErrorDTO.self, from: datos))?.texto
        switch r.statusCode {
        case 400, 422:
            return .validacion([mensaje ?? "Revisa los datos enviados."])
        case 401:
            if ruta.hasPrefix("/auth/2fa") { return .codigoInvalido }
            return ruta.hasPrefix("/auth/login") ? .credencialesInvalidas : .sesionExpirada
        case 403:
            // BACKEND: acordar con el equipo el texto exacto para cuenta suspendida.
            return mensaje == "CUENTA_SUSPENDIDA" ? .cuentaSuspendida : .sinPermiso
        case 404:
            return .noEncontrado
        case 409:
            return .conflicto(mensaje ?? "Ya existe un registro con esos datos.")
        case 423, 429:
            let segundos = r.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 60
            if r.statusCode == 423 { return .cuentaBloqueada(hasta: Date().addingTimeInterval(segundos)) }
            return .limiteExcedido(mensaje ?? "Demasiadas solicitudes. Intenta más tarde.")
        default:
            return .servidor("El servidor tuvo un problema. Intenta más tarde.")
        }
    }
}
```

- [ ] **Paso 6: ATS.** En `PrototipoApp/Info.plist`:

```xml
	<key>NSAppTransportSecurity</key>
	<dict>
		<!-- Solo HTTPS. Excepción: HTTP hacia la propia Mac (localhost) para el backend del equipo en desarrollo. -->
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
```

No se agrega `NSAllowsArbitraryLoads` ni excepciones por dominio. (La práctica ActividadTabla451 sí necesitó una excepción porque su servidor tiene un certificado autofirmado; aquí no se repite.)

- [ ] **Paso 7: Pruebas** — Run: `UNIT` → `** TEST SUCCEEDED **`.

- [ ] **Paso 8: Commit**

```bash
git add PrototipoApp/Data/Remote PrototipoApp/Info.plist PrototipoAppTests/Remote
git commit -m "feat: cliente HTTP con Bearer, refresh y reintento; ATS solo HTTPS"
```

**Criterios de aceptación:** 7 pruebas en verde; `plutil -p` del Info.plist compilado muestra `NSAllowsLocalNetworking => 1` y no muestra `NSAllowsArbitraryLoads`.
**Dependencias:** D2, D3, S2. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea R3: `RemoteBackend`

**Objetivo:** implementar los 5 protocolos contra las rutas del contrato y permitir arrancar la app en modo Remote.

**Archivos:**
- Crear: `PrototipoApp/Data/Remote/RemoteBackend.swift`
- Modificar: `PrototipoApp/App/Dependencies.swift` (caso `.remote`)
- Test: `PrototipoAppTests/Remote/RemoteBackendTests.swift`

**Interfaces:**
- Consume: R1 (rutas), R2 (`APIClient`, DTOs), S6 (`ArchivosEvidencia.datos(de:)`).
- Produce: `nonisolated struct RemoteBackend: Backend` con `init(cliente:secretos:archivos:)`.

- [ ] **Paso 1: Pruebas que fallan** — `PrototipoAppTests/Remote/RemoteBackendTests.swift`:

```swift
//
//  RemoteBackendTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct RemoteBackendTests {
    let host = "\(UUID().uuidString.lowercased()).test"
    let secretos = MemorySecretStore()
    let archivos = ArchivosEvidencia(carpeta: FileManager.default.temporaryDirectory.appending(path: "zs-remote-\(UUID().uuidString)"))

    private var backend: RemoteBackend {
        RemoteBackend(cliente: APIClient(base: URL(string: "https://\(host)")!, sesion: URLProtocolStub.sesion(), secretos: secretos),
                      secretos: secretos, archivos: archivos)
    }
    private func clave(_ metodo: String, _ ruta: String) -> String { "\(metodo) \(host)\(ruta)" }

    static let reporteJSON = #"""
    {"id":101,"autor":{"idUsuario":4,"nombre":"tecno_mx"},"tipo":"Oferta Falsa","estado":"VALIDADO",
     "titulo":"Falsa liquidación de tienda de electrónica","descripcion":"Texto","fechaIncidente":"2026-10-06T16:00:00.000Z",
     "nivelRiesgo":"ALTO","fechaCreacion":"2026-10-06T22:00:00Z","esAnonimo":false,"afectado":"YO","ciudad":"CDMX",
     "sitio":{"id":201,"url":"https://liquidacion-electronica-mx.shop","nivelRiesgoGlobal":"ALTO","estadoCertificado":"HTTPS"},
     "evidencias":[],"totalEvidencias":0,"confirmaciones":1200,"comentarios":2,"confirmadoPorMi":false,"guardadoPorMi":true,"esMio":false}
    """#

    @Test func leeUnReporteConLaFormaDelContrato() async throws {
        URLProtocolStub.preparar(clave("GET", "/reportes"), [.init(estado: 200, cuerpo: Data("[\(Self.reporteJSON)]".utf8))])
        let feed = try await backend.feed(FiltroBusqueda(texto: "tienda", tipos: [.ofertaFalsa], riesgoMinimo: .alto))
        #expect(feed.first?.titulo == "Falsa liquidación de tienda de electrónica")
        #expect(feed.first?.sitio?.nivelRiesgoGlobal == .alto)
        let url = try #require(URLProtocolStub.peticiones(host: host).first?.url)
        let consulta = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(consulta.contains(URLQueryItem(name: "texto", value: "tienda")))
        #expect(consulta.contains(URLQueryItem(name: "tipos", value: "Oferta Falsa")))
        #expect(consulta.contains(URLQueryItem(name: "riesgoMinimo", value: "ALTO")))
    }

    @Test func loginConDosPasosDevuelveElDesafio() async throws {
        URLProtocolStub.preparar(clave("POST", "/auth/login"), [.init(estado: 200, cuerpo: Data(
            #"{"requiereCodigo":true,"desafio":{"id":"d1","destino":"u•••@0fraude.mx","expira":"2026-10-07T12:05:00Z"}}"#.utf8))])
        guard case .requiereCodigo(let d) = try await backend.iniciarSesion(correo: "u@0fraude.mx", contrasena: "x") else {
            Issue.record("Debía pedir código"); return
        }
        #expect(d.id == "d1")
        #expect(d.codigoDemo == nil)
    }

    @Test func crearMandaElCuerpoDelContrato() async throws {
        try secretos.guardar("abc", para: .accessToken)
        URLProtocolStub.preparar(clave("POST", "/reportes"), [.init(estado: 201, cuerpo: Data(Self.reporteJSON.utf8))])
        var b = ReporteBorrador()
        b.titulo = "Tienda falsa de consolas"
        b.ciudad = "CDMX"
        _ = try await backend.crear(b)
        let peticion = try #require(URLProtocolStub.peticiones(host: host).first)
        let json = try #require(try JSONSerialization.jsonObject(with: cuerpo(de: peticion)) as? [String: Any])
        #expect(json["titulo"] as? String == "Tienda falsa de consolas")
        #expect(json["tipo"] as? String == "Oferta Falsa")
        #expect(json["persona"] == nil || json["persona"] is NSNull)
    }

    @Test func guardarUsaPutYQuitarUsaDelete() async throws {
        try secretos.guardar("abc", para: .accessToken)
        URLProtocolStub.preparar(clave("PUT", "/reportes/101/guardado"), [.init(estado: 204)])
        URLProtocolStub.preparar(clave("DELETE", "/reportes/101/guardado"), [.init(estado: 204)])
        try await backend.marcarGuardado(id: 101, true)
        try await backend.marcarGuardado(id: 101, false)
        #expect(URLProtocolStub.peticiones(host: host).map(\.httpMethod) == ["PUT", "DELETE"])
    }

    @Test func restablecerNoExisteEnRemote() async {
        await #expect(throws: AppError.sinPermiso) { try await backend.restablecerDemo() }
    }
}
```

- [ ] **Paso 2: Ver que fallan** — Run: `UNIT` → FAIL `cannot find 'RemoteBackend' in scope`.

- [ ] **Paso 3: Implementar `Data/Remote/RemoteBackend.swift`**

```swift
//
//  RemoteBackend.swift
//  PrototipoApp
//
//  Los 5 protocolos contra la API del Equipo ZeroScam (docs/api-contrato.md). Las respuestas
//  tienen la misma forma JSON que los modelos de Model/, así que casi todo es una línea.
//  BACKEND: si una ruta cambia en el servidor real, se ajusta aquí y en el contrato.
//

import Foundation

nonisolated struct RemoteBackend: Backend {
    let cliente: APIClient
    let secretos: any SecretStore
    let archivos: ArchivosEvidencia

    private func json(_ valor: some Encodable) throws -> Data { try Codificacion.encoder().encode(valor) }

    private func subir(_ adjunto: Adjunto, a ruta: String, metodo: String = "POST") async throws -> Data {
        let limite = "zs-\(UUID().uuidString)"
        let cuerpo = Multipart.cuerpo(archivo: try archivos.datos(de: adjunto), nombre: adjunto.nombreArchivo,
                                      tipo: adjunto.tipoArchivo, limite: limite)
        return try await cliente.pedirDatos(Endpoint(metodo: metodo, ruta: ruta, cuerpo: cuerpo,
                                                     tipoContenido: "multipart/form-data; boundary=\(limite)"))
    }

    // MARK: AuthRepository

    func registrar(_ datos: RegistroDatos) async throws -> Usuario {
        try await cliente.pedir(Endpoint(metodo: "POST", ruta: "/auth/registro", cuerpo: json(RegistroDTO(datos)), requiereSesion: false))
    }

    func iniciarSesion(correo: String, contrasena: String) async throws -> ResultadoLogin {
        let r: LoginRespuestaDTO = try await cliente.pedir(Endpoint(metodo: "POST", ruta: "/auth/login",
                                                                    cuerpo: json(["correo": correo, "contrasena": contrasena]),
                                                                    requiereSesion: false))
        if r.requiereCodigo == true, let desafio = r.desafio { return .requiereCodigo(desafio) }
        guard let access = r.accessToken, let usuario = r.usuario else { throw AppError.servidor("Respuesta inesperada del servidor.") }
        return .sesion(SesionActiva(accessToken: access, refreshToken: r.refreshToken, usuario: usuario))
    }

    func verificarCodigo(desafio: String, codigo: String) async throws -> SesionActiva {
        let r: LoginRespuestaDTO = try await cliente.pedir(Endpoint(metodo: "POST", ruta: "/auth/2fa",
                                                                    cuerpo: json(["desafio": desafio, "codigo": codigo]),
                                                                    requiereSesion: false))
        guard let access = r.accessToken, let usuario = r.usuario else { throw AppError.codigoInvalido }
        return SesionActiva(accessToken: access, refreshToken: r.refreshToken, usuario: usuario)
    }

    func usuarioActual() async throws -> Usuario { try await cliente.pedir(Endpoint(ruta: "/auth/yo")) }

    func cerrarSesion() async throws {
        let refresh = (try? secretos.leer(.refreshToken)) ?? ""
        try await cliente.ejecutar(Endpoint(metodo: "POST", ruta: "/auth/logout", cuerpo: json(["refreshToken": refresh])))
    }

    func cambiarContrasena(actual: String, nueva: String) async throws {
        try await cliente.ejecutar(Endpoint(metodo: "PUT", ruta: "/auth/contrasena", cuerpo: json(["actual": actual, "nueva": nueva])))
    }

    func eliminarCuenta(contrasena: String) async throws {
        try await cliente.ejecutar(Endpoint(metodo: "DELETE", ruta: "/auth/cuenta", cuerpo: json(["contrasena": contrasena])))
    }

    // MARK: ReportRepository

    func feed(_ filtro: FiltroBusqueda) async throws -> [Reporte] {
        var consulta: [URLQueryItem] = []
        if !filtro.texto.isEmpty { consulta.append(URLQueryItem(name: "texto", value: filtro.texto)) }
        if !filtro.tipos.isEmpty {
            consulta.append(URLQueryItem(name: "tipos", value: filtro.tipos.map(\.rawValue).sorted().joined(separator: ",")))
        }
        if let minimo = filtro.riesgoMinimo { consulta.append(URLQueryItem(name: "riesgoMinimo", value: minimo.rawValue)) }
        return try await cliente.pedir(Endpoint(ruta: "/reportes", consulta: consulta))
    }

    func misReportes() async throws -> [Reporte] { try await cliente.pedir(Endpoint(ruta: "/reportes/mios")) }
    func guardados() async throws -> [Reporte] { try await cliente.pedir(Endpoint(ruta: "/reportes/guardados")) }
    func detalle(id: Int64) async throws -> Reporte { try await cliente.pedir(Endpoint(ruta: "/reportes/\(id)")) }

    func crear(_ borrador: ReporteBorrador) async throws -> Reporte {
        let creado: Reporte = try await cliente.pedir(Endpoint(metodo: "POST", ruta: "/reportes", cuerpo: json(ReporteEntradaDTO(borrador))))
        guard !borrador.adjuntos.isEmpty else { return creado }
        do {
            for adjunto in borrador.adjuntos { _ = try await subir(adjunto, a: "/reportes/\(creado.id)/evidencias") }
        } catch {
            throw AppError.conflicto("Tu reporte se envió, pero la evidencia no se pudo subir. Agrégala editando el reporte.")
        }
        return try await detalle(id: creado.id)
    }

    func actualizar(id: Int64, _ borrador: ReporteBorrador) async throws -> Reporte {
        _ = try await cliente.pedirDatos(Endpoint(metodo: "PUT", ruta: "/reportes/\(id)", cuerpo: json(ReporteEntradaDTO(borrador))))
        for adjunto in borrador.adjuntos { _ = try await subir(adjunto, a: "/reportes/\(id)/evidencias") }
        return try await detalle(id: id)
    }

    func eliminar(id: Int64) async throws { try await cliente.ejecutar(Endpoint(metodo: "DELETE", ruta: "/reportes/\(id)")) }

    func marcarGuardado(id: Int64, _ guardado: Bool) async throws {
        try await cliente.ejecutar(Endpoint(metodo: guardado ? "PUT" : "DELETE", ruta: "/reportes/\(id)/guardado"))
    }

    func confirmar(id: Int64) async throws -> Reporte {
        try await cliente.pedir(Endpoint(metodo: "PUT", ruta: "/reportes/\(id)/confirmacion"))
    }

    func comentarios(id: Int64) async throws -> [Comentario] { try await cliente.pedir(Endpoint(ruta: "/reportes/\(id)/comentarios")) }

    func comentar(id: Int64, texto: String) async throws -> Comentario {
        try await cliente.pedir(Endpoint(metodo: "POST", ruta: "/reportes/\(id)/comentarios", cuerpo: json(["texto": texto])))
    }

    func eliminarComentario(id: Int64) async throws { try await cliente.ejecutar(Endpoint(metodo: "DELETE", ruta: "/comentarios/\(id)")) }
    func historial(id: Int64) async throws -> [HistorialEstado] { try await cliente.pedir(Endpoint(ruta: "/reportes/\(id)/historial")) }
    func estadisticas() async throws -> EstadisticasComunidad { try await cliente.pedir(Endpoint(ruta: "/estadisticas")) }
    func categorias() async throws -> [ConteoCategoria] { try await cliente.pedir(Endpoint(ruta: "/estadisticas/categorias")) }
    func datosEvidencia(_ evidencia: Evidencia) async throws -> Data {
        try await cliente.pedirDatos(Endpoint(ruta: "/evidencias/\(evidencia.id)/archivo"))
    }

    // MARK: ProfileRepository

    func actualizarPerfil(_ datos: PerfilDatos) async throws -> Usuario {
        try await cliente.pedir(Endpoint(metodo: "PUT", ruta: "/perfil", cuerpo: json(PerfilDTO(datos))))
    }

    func actualizarPreferencias(_ preferencias: Preferencias, contrasena: String?) async throws -> Usuario {
        try await cliente.pedir(Endpoint(metodo: "PUT", ruta: "/perfil/preferencias",
                                         cuerpo: json(PreferenciasDTO(preferencias: preferencias, contrasena: contrasena))))
    }

    func actualizarAvatar(_ adjunto: Adjunto?) async throws -> Usuario {
        guard let adjunto else { return try await cliente.pedir(Endpoint(metodo: "DELETE", ruta: "/perfil/avatar")) }
        return try Codificacion.decoder().decode(Usuario.self, from: try await subir(adjunto, a: "/perfil/avatar", metodo: "PUT"))
    }

    func datosAvatar(de usuario: Usuario) async throws -> Data? {
        guard usuario.avatarRuta != nil else { return nil }
        do { return try await cliente.pedirDatos(Endpoint(ruta: "/usuarios/\(usuario.id)/avatar")) }
        catch AppError.noEncontrado { return nil }
    }

    func exportarMisDatos() async throws -> Data { try await cliente.pedirDatos(Endpoint(ruta: "/perfil/exportacion")) }

    // MARK: NotificationRepository

    func notificaciones() async throws -> [Notificacion] { try await cliente.pedir(Endpoint(ruta: "/notificaciones")) }
    func marcarLeidas(_ ids: [Int64]) async throws {
        try await cliente.ejecutar(Endpoint(metodo: "PUT", ruta: "/notificaciones/leidas", cuerpo: json(IdsDTO(ids: ids))))
    }

    // MARK: AdminRepository

    func colaModeracion(estado: EstadoReporte?) async throws -> [Reporte] {
        try await cliente.pedir(Endpoint(ruta: "/admin/reportes", consulta: estado.map { [URLQueryItem(name: "estado", value: $0.rawValue)] } ?? []))
    }

    func cambiarEstado(id: Int64, a nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) async throws -> Reporte {
        try await cliente.pedir(Endpoint(metodo: "PUT", ruta: "/admin/reportes/\(id)/estado",
                                         cuerpo: json(EstadoDTO(estado: nuevo, nivelRiesgo: riesgo, observaciones: observaciones))))
    }

    func usuarios() async throws -> [Usuario] { try await cliente.pedir(Endpoint(ruta: "/admin/usuarios")) }

    func cambiarRol(idUsuario: Int64, a rol: Rol) async throws -> Usuario {
        try await cliente.pedir(Endpoint(metodo: "PUT", ruta: "/admin/usuarios/\(idUsuario)/rol", cuerpo: json(RolDTO(rol: rol))))
    }

    func cambiarEstadoCuenta(idUsuario: Int64, a estado: EstadoCuenta) async throws -> Usuario {
        try await cliente.pedir(Endpoint(metodo: "PUT", ruta: "/admin/usuarios/\(idUsuario)/estado", cuerpo: json(EstadoCuentaDTO(estadoCuenta: estado))))
    }

    func analiticas() async throws -> [String: Int] { try await cliente.pedir(Endpoint(ruta: "/admin/analiticas")) }

    /// Solo existe en el modo Demo.
    func restablecerDemo() async throws { throw AppError.sinPermiso }
}
```

- [ ] **Paso 4: Conectar en `App/Dependencies.swift`.** Reemplazar el comentario `// BACKEND: R3 agrega aquí…` y las 3 líneas siguientes por:

```swift
        switch config.fuente {
        case .demo:
            let hasher = PasswordHasher(iteraciones: config.esUITest ? 1_000 : PasswordHasher.iteracionesRecomendadas)
            let servidor = DemoServer(almacen: DemoAlmacen(carpeta: carpeta), archivos: archivos, hasher: hasher)
            return Dependencies(backend: DemoBackend(servidor: servidor, secretos: secretos),
                                secretos: secretos, archivos: archivos, config: config)
        case .remote(let base):
            let cliente = APIClient(base: base, secretos: secretos)
            return Dependencies(backend: RemoteBackend(cliente: cliente, secretos: secretos, archivos: archivos),
                                secretos: secretos, archivos: archivos, config: config)
        }
```

- [ ] **Paso 5: Pruebas y build en ambos modos**

Run: `UNIT` → `** TEST SUCCEEDED **`.
Run: `xcodebuild -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd ZS_FUENTE_DATOS=remote ZS_URL_BASE=http://localhost:3000 build 2>&1 | tail -3` → `** BUILD SUCCEEDED **`. Si el backend del equipo ya corre en `localhost:3000`, abrir la app: Registro y Login deben llegar al servidor (si no corre, Login muestra "No se pudo conectar con el servidor. Revisa tu conexión.", sin crash).

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Data/Remote/RemoteBackend.swift PrototipoApp/App/Dependencies.swift PrototipoAppTests/Remote/RemoteBackendTests.swift
git commit -m "feat: backend remoto según el contrato de la API"
```

**Criterios de aceptación:** las rutas, métodos y cuerpos coinciden con `docs/api-contrato.md`; sin backend, la app en modo Remote muestra error de conexión y no se cae.
**Dependencias:** R1, R2, S6. **Esfuerzo:** L. **Riesgo:** medio (sin servidor real para probar; se cubre con el stub).

---

## 3. Funcionalidad

Una tarea por cada `// TODO` del original y por cada pantalla nueva. Cada tarea de interfaz empieza escribiendo su prueba XCUITest (falla), luego implementa y la ve pasar. Los ayudantes de XCUITest (`XCUIApplication.zeroScam()`, `entrar()`, `tocar(en:)`, `reemplazar(_:)`, `capturar(_:_:)`) se crean en Q1. Los componentes (`BotonAccion`, `LabeledSecureField`, `CargaView`, `AvisoBanner`, `CasillaVerificacion`, `ChipFiltro`, `Etiqueta`, `.ofraudeCampo()`) se crean en V1.

| `// TODO` o stub del original | Tarea |
|---|---|
| Crear cuenta | F1 |
| Login `admin`/`admin`, sesión | F2, F3 |
| Detalle fijo | F5 |
| Guardar, compartir | F6 |
| "Yo también" | F7 |
| Publicar comentario | F8 |
| Enviar reporte | F9 |
| Agregar/quitar evidencia | F10 |
| Editar (menú de Perfil), Eliminar y quitar guardado persistentes | F11 |
| Búsqueda, chips, categorías | F12 |
| Estadísticas fijas | F13 |
| Guía con un solo artículo | F14 |
| Estados del reporte (RECIBIDO…CANALIZADO), roles | F15, F17 |
| Notificaciones (switch de Ajustes) | F16 |
| Guardar en Editar perfil, "Cambiar Avatar" | F18 |
| Guardar en Cambiar contraseña | F19 |
| Switches de Seguridad y privacidad | F20 |
| Derechos ARCO (exportar, eliminar cuenta) | F21 |
| Switch Modo oscuro | U3 |

### Tarea F1: Registro real y aviso de privacidad

**Objetivo:** que "CREAR CUENTA" cree una cuenta válida (nombre, apellido, país, alias, correo, contraseña segura y aceptación del aviso) y lleve a Login con el correo escrito.

**Archivos:**
- Modificar: `PrototipoApp/Views/Auth/RegisterView.swift` (todo el archivo)
- Crear: `PrototipoApp/Views/Account/PrivacyNoticeView.swift`
- Modificar: `PrototipoApp/App/OFraudeApp.swift` (`AuthFlow`: `.aviso` → `PrivacyNoticeView()`)
- Modificar: `PrototipoApp/Views/Route+Destination.swift` (`.privacyNotice` → `PrivacyNoticeView()`)
- Test: `PrototipoAppUITests/AutenticacionUITests.swift` (crear)

**Interfaces:**
- Consume: D10 (`AuthRoute`, `SessionStore.registrar`), S3 (`Validador.registro`, `Validador.paises`, `Sanitizador`), V1.
- Produce: `RegisterView(alCrearCuenta:)` con identificadores `registro.nombre`, `registro.apellido`, `registro.alias`, `registro.correo`, `registro.pais`, `registro.contrasena`, `registro.confirmacion`, `registro.aviso`, `registro.leerAviso`, `registro.crear`, `registro.irLogin`; `PrivacyNoticeView`.

- [ ] **Paso 0: Revisar el texto del aviso con la skill `lfpdppp-compliance`** (está instalada) antes de escribir `PrivacyNoticeView`: que cubra responsable, datos, finalidades primarias y secundarias, transferencias, derechos ARCO y cómo ejercerlos, revocación del consentimiento, medidas de seguridad y cambios al aviso, citando la LFPDPPP publicada en el DOF el 20 de marzo de 2025 (sin artículos de la ley de 2010).

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppUITests/AutenticacionUITests.swift`:

```swift
//
//  AutenticacionUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class AutenticacionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testRegistroValidaYLlevaALogin() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        let crear = app.buttons["registro.crear"]
        XCTAssertTrue(crear.waitForExistence(timeout: 10))
        capturar(app, "01-registro")

        app.textFields["registro.nombre"].escribir("Lucía")
        app.textFields["registro.apellido"].escribir("Torres")
        app.textFields["registro.alias"].escribir("lucia_t")
        app.textFields["registro.correo"].escribir("correo-malo")
        app.secureTextFields["registro.contrasena"].escribir("password123")
        app.secureTextFields["registro.confirmacion"].escribir("password123")
        XCTAssertFalse(crear.isEnabled)
        XCTAssertTrue(app.staticTexts["Escribe un correo válido, por ejemplo nombre@dominio.com."].exists)
        XCTAssertTrue(app.staticTexts["Esa contraseña es muy común; elige otra."].exists)
        capturar(app, "02-registro-errores")

        app.textFields["registro.correo"].reemplazar("lucia@comunidad.test")
        app.secureTextFields["registro.contrasena"].reemplazar("Fraude0-Cero")
        app.secureTextFields["registro.confirmacion"].reemplazar("Fraude0-Cero")
        app.buttons["registro.aviso"].tocar(en: app)
        XCTAssertTrue(crear.isEnabled)
        crear.tocar(en: app)

        XCTAssertTrue(app.elemento(contiene: "Cuenta creada. Inicia sesión para continuar.").waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["login.correo"].value as? String, "lucia@comunidad.test")
    }

    @MainActor
    func testElAvisoDePrivacidadSeAbreDesdeRegistro() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.buttons["registro.leerAviso"].tocar(en: app)
        XCTAssertTrue(app.staticTexts["Aviso de privacidad"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (o solo esta clase: `-only-testing:PrototipoAppUITests/AutenticacionUITests`) → FAIL: no existe `registro.crear`.

- [ ] **Paso 3: Reescribir `Views/Auth/RegisterView.swift`**

```swift
//
//  RegisterView.swift
//  PrototipoApp
//
//  Reemplaza: escena `reg-vc` / RegisterViewController. Es la pantalla de arranque.
//  Crea la cuenta de verdad: valida cada campo al salir de él, pide aceptar el aviso de
//  privacidad y al terminar lleva a Login con el correo escrito (el segue original Registro → Login).
//

import SwiftUI

struct RegisterView: View {
    var alCrearCuenta: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @State private var datos = RegistroDatos()
    @State private var tocados: Set<Campo> = []
    @State private var errorServidor: String?
    @FocusState private var foco: Campo?

    /// Lo que se valida y se envía: sin espacios sobrantes ni caracteres invisibles.
    private var limpio: RegistroDatos {
        var d = datos
        d.nombre = Sanitizador.texto(d.nombre, maximo: 50)
        d.apellido = Sanitizador.texto(d.apellido, maximo: 50)
        d.alias = Sanitizador.alias(d.alias)
        d.correo = Sanitizador.correo(d.correo)
        return d
    }

    private var errores: [ErrorCampo] { Validador.registro(limpio) }

    /// El error de un campo se muestra hasta que la persona sale de él (no mientras escribe).
    private func error(_ campo: Campo) -> String? {
        tocados.contains(campo) ? errores.mensaje(para: campo) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Únete a la comunidad y ayuda a prevenir fraudes.")
                    .ofraude(14, color: Theme.textMuted)

                HStack(alignment: .top, spacing: 12) {
                    LabeledTextField(label: "NOMBRE", placeholder: "Ana", text: $datos.nombre, contenido: .givenName,
                                     error: error(.nombre), maximo: 50, foco: $foco, campo: .nombre, identificador: "registro.nombre")
                    LabeledTextField(label: "APELLIDO", placeholder: "López", text: $datos.apellido, contenido: .familyName,
                                     error: error(.apellido), maximo: 50, foco: $foco, campo: .apellido, identificador: "registro.apellido")
                }
                LabeledTextField(label: "NOMBRE DE USUARIO", placeholder: "usuario_01", text: $datos.alias, contenido: .nickname,
                                 error: error(.alias), maximo: 20, foco: $foco, campo: .alias, identificador: "registro.alias")
                LabeledTextField(label: "CORREO ELECTRÓNICO", placeholder: "tucorreo@ejemplo.com", text: $datos.correo,
                                 keyboard: .emailAddress, contenido: .username, error: error(.correo), maximo: 150,
                                 foco: $foco, campo: .correo, identificador: "registro.correo")

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("PAÍS")
                    Picker("País", selection: $datos.pais) {
                        ForEach(Validador.paises, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.textLight)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .ofraudeCampo()
                    .accessibilityIdentifier("registro.pais")
                }

                LabeledSecureField(label: "CONTRASEÑA", placeholder: "••••••••", text: $datos.contrasena, contenido: .newPassword,
                                   error: error(.contrasena), foco: $foco, campo: .contrasena, identificador: "registro.contrasena")
                Text("Mínimo 10 caracteres, con letras y números. Una frase larga es más segura.")
                    .ofraude(12, color: Theme.textMuted)
                LabeledSecureField(label: "CONFIRMAR CONTRASEÑA", placeholder: "••••••••", text: $datos.confirmacion,
                                   contenido: .newPassword, error: error(.confirmacion), foco: $foco, campo: .confirmacion,
                                   identificador: "registro.confirmacion")

                CasillaVerificacion(texto: "He leído y acepto el aviso de privacidad.", marcado: $datos.aceptaAviso,
                                    identificador: "registro.aviso")
                NavigationLink(value: AuthRoute.aviso) {
                    Text("Leer el aviso de privacidad ›").ofraude(13, .semibold, color: Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("registro.leerAviso")

                if let errorServidor { AvisoBanner(texto: errorServidor, tono: .error) }

                BotonAccion(titulo: "CREAR CUENTA", habilitado: errores.isEmpty, identificador: "registro.crear") {
                    await crear()
                }
                if !errores.isEmpty {
                    Text("Completa los campos para crear tu cuenta.")
                        .ofraude(12, color: Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }

                NavigationLink(value: AuthRoute.login) {
                    Text("¿Ya tienes cuenta? Inicia sesión")
                        .ofraude(14, color: Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("registro.irLogin")
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Crear cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: foco) { anterior, _ in
            if let anterior { tocados.insert(anterior) }
        }
    }

    private func crear() async {
        errorServidor = nil
        do {
            try await session.registrar(limpio)
            datos = RegistroDatos()
            tocados = []
            alCrearCuenta()
        } catch {
            errorServidor = error.mensajeUsuario
        }
    }
}

#Preview {
    NavigationStack { RegisterView() }
        .entornoDePrueba()
}
```

- [ ] **Paso 4: Crear `Views/Account/PrivacyNoticeView.swift`** con el texto revisado en el paso 0. Estructura y contenido base:

```swift
//
//  PrivacyNoticeView.swift
//  PrototipoApp
//
//  Aviso de privacidad integral (LFPDPPP, DOF 20-03-2025). Se abre desde Registro (antes de
//  aceptar) y desde Seguridad y privacidad. Si cambia el texto, se sube la versión.
//

import SwiftUI

struct PrivacyNoticeView: View {
    private struct Seccion: Identifiable {
        let titulo: String
        let texto: String
        var id: String { titulo }
    }

    private let secciones = [
        Seccion(titulo: "Quién es responsable",
                texto: "0Fraude es un prototipo académico del Equipo ZeroScam. El equipo es responsable del tratamiento de tus datos personales en esta app."),
        Seccion(titulo: "Qué datos usamos",
                texto: "Identificación y contacto: nombre, apellido, país, nombre de usuario y correo. Autenticación: tu contraseña, que solo guardamos como un hash con sal (nadie puede leerla). Contenido de tus reportes: descripción, ciudad, enlaces y evidencia; a las fotos les quitamos la ubicación antes de guardarlas. Datos de una persona afectada, solo si nos dices que te autorizó a compartirlos. Uso anónimo de la app (contadores sin identificarte), solo si lo permites."),
        Seccion(titulo: "Para qué los usamos",
                texto: "Finalidades necesarias: crear y proteger tu cuenta, recibir y moderar reportes, publicar alertas validadas sin tus datos personales y avisarte cuando cambie el estado de tus reportes. Finalidades que puedes rechazar: mostrar tu nombre de usuario en público y las analíticas anónimas (Seguridad y privacidad)."),
        Seccion(titulo: "Con quién los compartimos",
                texto: "No vendemos ni rentamos tus datos. Un reporte CANALIZADO puede enviarse a la autoridad competente; tus datos de cuenta solo se entregarían por requerimiento legal. Este prototipo no hace transferencias reales."),
        Seccion(titulo: "Tus derechos ARCO",
                texto: "Acceso: Seguridad y privacidad › Descargar mis datos. Rectificación: Editar perfil. Cancelación: Seguridad y privacidad › Eliminar mi cuenta. Oposición: los switches de Perfil público, Analíticas y Notificaciones. Eliminar tu cuenta también revoca tu consentimiento."),
        Seccion(titulo: "Cómo los protegemos",
                texto: "Contraseñas con hash y sal, sesión guardada en el llavero cifrado del teléfono, archivos cifrados por iOS, evidencia sin metadatos de ubicación, límite de intentos de inicio de sesión y permisos revisados en el servidor."),
        Seccion(titulo: "Cuánto tiempo los guardamos",
                texto: "Mientras tu cuenta exista. Si la eliminas, borramos tus datos y tus reportes no validados; los reportes ya validados se quedan para alertar a la comunidad, pero sin ningún dato tuyo."),
        Seccion(titulo: "Cambios a este aviso",
                texto: "Si cambia, te pediremos aceptarlo de nuevo. Marco legal: Ley Federal de Protección de Datos Personales en Posesión de los Particulares, publicada en el Diario Oficial de la Federación el 20 de marzo de 2025."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Aviso de privacidad").ofraude(26, .bold, color: Theme.textLight)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: "Versión \(Consentimiento.versionAvisoVigente)").ofraude(12, .medium, color: Theme.accent)
                ForEach(secciones) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.titulo).ofraude(17, .bold, color: Theme.textLight).accessibilityAddTraits(.isHeader)
                        Text(s.texto).ofraude(14, color: Theme.textMuted)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
        }
        .ofraudeScreen()
        .navigationTitle("Aviso de privacidad")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { PrivacyNoticeView() }
}
```

- [ ] **Paso 5: Conectar el aviso.** En `AuthFlow` (`OFraudeApp.swift`) cambiar `case .aviso: EmptyView()   // F1 pone aquí PrivacyNoticeView.` por `case .aviso: PrivacyNoticeView()`. En `Route+Destination.swift` sacar `.privacyNotice` del `case` agrupado y agregar `case .privacyNotice: PrivacyNoticeView()`.

- [ ] **Paso 6: Pruebas** — Run: `UI` (clase `AutenticacionUITests`) → los 2 tests en verde. `BUILD` en verde.

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: registro con validación y aviso de privacidad"
```

**Criterios de aceptación:** no se puede crear una cuenta con correo inválido, contraseña común o débil, contraseñas distintas o sin aceptar el aviso; la cuenta creada aparece en Login con aviso verde y correo escrito.
**Dependencias:** D10, V1, S3. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea F2: Login real, límite de intentos y verificación en dos pasos

**Objetivo:** iniciar sesión contra el backend con contraseña oculta, mostrar el bloqueo con cuenta regresiva, pedir el código si la cuenta tiene dos pasos y mostrar los avisos de sesión expirada o cuenta creada.

**Archivos:**
- Modificar: `PrototipoApp/Views/Auth/LoginView.swift` (todo el archivo)
- Crear: `PrototipoApp/Views/Auth/CodigoDosPasosView.swift`
- Test: `PrototipoAppUITests/AutenticacionUITests.swift` (agregar pruebas)

**Interfaces:**
- Consume: D9 (`SessionStore.iniciarSesion`, `desafio`, `verificarCodigo`, `cancelarDesafio`, `aviso`, `correoSugerido`), D10 (`appConfig`), V1, S3 (`Validador.codigo`).
- Produce: identificadores `login.correo`, `login.contrasena`, `login.entrar`, `login.error`, `login.aviso`, `login.irRegistro`, `codigo.campo`, `codigo.demo`, `codigo.verificar`.

- [ ] **Paso 1: Pruebas que fallan** — agregar a `AutenticacionUITests`:

```swift
    @MainActor
    func testLoginIncorrectoYBloqueo() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.buttons["registro.irLogin"].tocar(en: app)
        let correo = app.textFields["login.correo"]
        XCTAssertTrue(correo.waitForExistence(timeout: 5))
        correo.escribir("usuario@0fraude.mx")
        for intento in 1...5 {
            app.secureTextFields["login.contrasena"].escribir("incorrecta\(intento)")
            app.buttons["login.entrar"].tap()
            _ = app.staticTexts["login.error"].waitForExistence(timeout: 5)
        }
        XCTAssertTrue(app.staticTexts["login.error"].label.hasPrefix("Demasiados intentos"))
        XCTAssertFalse(app.buttons["login.entrar"].isEnabled)
        capturar(app, "03-login-bloqueado")
    }

    @MainActor
    func testLoginCorrectoPersisteSesion() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.terminate()
        let otraVez = XCUIApplication.zeroScam(reiniciar: false)
        otraVez.launch()
        XCTAssertTrue(otraVez.tabBars.buttons["Inicio"].waitForExistence(timeout: 10))
    }
```

- [ ] **Paso 2: Ver que fallan** — Run: `UI` (clase `AutenticacionUITests`) → FAIL: no existe `login.entrar`.

- [ ] **Paso 3: Reescribir `Views/Auth/LoginView.swift`**

```swift
//
//  LoginView.swift
//  PrototipoApp
//
//  Reemplaza: escena `login-vc` / LoginViewController (archivo ViewController.swift).
//  Ya no hay credenciales en el código: valida contra el backend. Tras 5 fallos el servidor
//  bloquea el correo y aquí se muestra la cuenta regresiva. Si la cuenta tiene verificación en
//  dos pasos, se pide el código en una hoja.
//

import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appConfig) private var config

    @State private var correo = ""
    @State private var contrasena = ""
    @State private var error: String?
    @State private var bloqueadoHasta: Date?
    @FocusState private var foco: Campo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Estos 3 textos van centrados en el storyboard (textAlignment="center").
                Text("0FRAUDE").ofraude(28, .bold, color: Theme.accent)
                    .frame(maxWidth: .infinity)
                Text("Bienvenido de nuevo").ofraude(22, .bold, color: Theme.textLight)
                    .frame(maxWidth: .infinity)
                Text("Inicia sesión para seguir protegiendo a tu comunidad.")
                    .ofraude(14, color: Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if let aviso = session.aviso {
                    AvisoBanner(texto: aviso).accessibilityIdentifier("login.aviso")
                }

                VStack(alignment: .leading, spacing: 18) {
                    LabeledTextField(label: "CORREO ELECTRÓNICO", placeholder: "tucorreo@ejemplo.com", text: $correo,
                                     keyboard: .emailAddress, contenido: .username, maximo: 150,
                                     foco: $foco, campo: .correo, identificador: "login.correo")
                        .submitLabel(.next)
                        .onSubmit { foco = .contrasena }
                    LabeledSecureField(label: "CONTRASEÑA", placeholder: "••••••••", text: $contrasena, contenido: .password,
                                       foco: $foco, campo: .contrasena, identificador: "login.contrasena")
                        .submitLabel(.go)
                        .onSubmit { Task { await entrar() } }
                }

                if let error {
                    Text(error).ofraude(13, .medium, color: Theme.dangerText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("login.error")
                }

                // Se redibuja cada segundo para la cuenta regresiva del bloqueo.
                TimelineView(.periodic(from: .now, by: 1)) { contexto in
                    let restante = Int(((bloqueadoHasta ?? .distantPast).timeIntervalSince(contexto.date)).rounded(.up))
                    BotonAccion(titulo: restante > 0 ? "ESPERA \(restante) S" : "INICIAR SESIÓN",
                                habilitado: restante <= 0 && !correo.isEmpty && !contrasena.isEmpty,
                                identificador: "login.entrar") {
                        await entrar()
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("¿No tienes cuenta? Crear cuenta")
                        .ofraude(14, color: Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("login.irRegistro")
            }
            .padding(.horizontal, 28)
            .padding(.top, 90)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: desafio) { d in
            CodigoDosPasosView(desafio: d, mostrarCodigoDemo: config.fuente == .demo)
        }
        .onAppear { if correo.isEmpty { correo = session.correoSugerido } }
    }

    private var desafio: Binding<DesafioDosPasos?> {
        Binding(get: { session.desafio }, set: { if $0 == nil { session.cancelarDesafio() } })
    }

    private func entrar() async {
        error = nil
        foco = nil
        do {
            try await session.iniciarSesion(correo: correo, contrasena: contrasena)
        } catch let e as AppError {
            if case .cuentaBloqueada(let hasta) = e { bloqueadoHasta = hasta }
            error = e.mensaje()
        } catch {
            self.error = error.mensajeUsuario
        }
        // La contraseña no se queda en memoria de la pantalla después de un intento.
        contrasena = ""
    }
}

#Preview {
    NavigationStack { LoginView() }
        .entornoDePrueba()
}
```

- [ ] **Paso 4: Crear `Views/Auth/CodigoDosPasosView.swift`**

```swift
//
//  CodigoDosPasosView.swift
//  PrototipoApp
//
//  Segundo paso del login. En modo Demo no se envía ningún correo: el código "enviado" se
//  muestra en un aviso para poder presentarlo. Vence en 5 minutos y admite 3 intentos.
//

import SwiftUI

struct CodigoDosPasosView: View {
    let desafio: DesafioDosPasos
    let mostrarCodigoDemo: Bool

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var codigo = ""
    @State private var error: String?
    @FocusState private var foco: Campo?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Verificación en dos pasos").ofraude(22, .bold, color: Theme.textLight)
                Text(verbatim: "Escribe el código de 6 dígitos que enviamos a \(desafio.destino). Vence en 5 minutos.")
                    .ofraude(14, color: Theme.textMuted)
                if mostrarCodigoDemo, let demo = desafio.codigoDemo {
                    AvisoBanner(texto: "Modo demo: el correo con tu código diría «\(demo)».")
                        .accessibilityIdentifier("codigo.demo")
                }
                OfraudeTextField(placeholder: "000000", text: $codigo, keyboard: .numberPad, contenido: .oneTimeCode,
                                 maximo: 6, foco: $foco, campo: .codigo, identificador: "codigo.campo")
                FieldError(mensaje: error)
                BotonAccion(titulo: "VERIFICAR", habilitado: Validador.codigo(codigo).isEmpty, identificador: "codigo.verificar") {
                    await verificar()
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .ofraudeScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        session.cancelarDesafio()
                        dismiss()
                    }
                }
            }
            .onAppear { foco = .codigo }
        }
        .presentationDetents([.medium, .large])
    }

    private func verificar() async {
        do {
            try await session.verificarCodigo(codigo)
        } catch {
            self.error = error.mensajeUsuario
            codigo = ""
        }
    }
}
```

- [ ] **Paso 5: Pruebas** — Run: `UI` (clase `AutenticacionUITests`) → 4 tests en verde. Manual: activar 2 pasos en la cuenta (llega en F20) y comprobar la hoja del código; mientras F20 no exista, queda cubierto por `SessionStoreTests/dosPasosGuardaElDesafioYDespuesEntra`.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Views/Auth PrototipoAppUITests
git commit -m "feat: login real con bloqueo por intentos y verificación en dos pasos"
```

**Criterios de aceptación:** contraseña oculta con botón para mostrarla; 5 fallos bloquean con cuenta regresiva; la sesión sobrevive al reinicio; el mensaje de error no revela si el correo existe.
**Dependencias:** D10, V1. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea F3: Cerrar sesión de verdad

**Objetivo:** "CERRAR SESIÓN" revoca el token en el servidor, lo borra del Keychain y vuelve a Registro limpio; "CANCELAR" regresa.

**Archivos:**
- Modificar: `PrototipoApp/Views/Account/SignOutView.swift` (todo el cuerpo)
- Modificar: `PrototipoApp/Views/Tabs/ProfileView.swift:24-26` (identificador `perfil.ajustes`, etiqueta de accesibilidad)
- Modificar: `PrototipoApp/Views/Account/SettingsView.swift:56-60` (identificador `ajustes.cerrarSesion`)
- Test: `PrototipoAppUITests/AutenticacionUITests.swift`; `PrototipoAppUITests/Soporte/Ayudantes.swift` (agregar `salir()`)

**Interfaces:**
- Consume: D9 (`SessionStore.cerrarSesion`), V1.
- Produce: identificadores `perfil.ajustes`, `ajustes.cerrarSesion`, `salir.confirmar`, `salir.cancelar`; ayudante `XCUIApplication.salir()`.

- [ ] **Paso 1: Prueba que falla** — agregar a `AutenticacionUITests`:

```swift
    @MainActor
    func testCerrarSesion() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.ajustes"].tap()
        app.buttons["ajustes.cerrarSesion"].tocar(en: app)
        app.buttons["salir.cancelar"].tap()
        XCTAssertTrue(app.buttons["ajustes.cerrarSesion"].waitForExistence(timeout: 5))
        app.buttons["ajustes.cerrarSesion"].tocar(en: app)
        app.buttons["salir.confirmar"].tap()
        XCTAssertTrue(app.buttons["registro.crear"].waitForExistence(timeout: 10))
        app.terminate()
        let otraVez = XCUIApplication.zeroScam(reiniciar: false)
        otraVez.launch()
        XCTAssertTrue(otraVez.buttons["registro.crear"].waitForExistence(timeout: 10))
    }
```

Agregar a `PrototipoAppUITests/Soporte/Ayudantes.swift`, dentro de `extension XCUIApplication`:

```swift
    /// Perfil → Ajustes → Cerrar sesión → confirmar (desde cualquier pantalla).
    func salir() {
        volverALaRaiz()
        tabBars.buttons["Perfil"].tap()
        buttons["perfil.ajustes"].tap()
        buttons["ajustes.cerrarSesion"].tocar(en: self)
        buttons["salir.confirmar"].tap()
        XCTAssertTrue(buttons["registro.crear"].waitForExistence(timeout: 10))
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` → FAIL: no existe `perfil.ajustes`.

- [ ] **Paso 3: `SignOutView.swift`** — botones:

```swift
            BotonAccion(titulo: "CERRAR SESIÓN", estilo: OfraudeButtonStyle(background: Theme.danger),
                        identificador: "salir.confirmar") {
                // Revoca el token en el servidor y lo borra del Keychain; RootView vuelve a Registro.
                await session.cerrarSesion()
            }

            Button("CANCELAR") { dismiss() }
                .buttonStyle(OfraudeButtonStyle(background: .clear, foreground: Theme.textLight))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.defaultBorder, lineWidth: 1))
                .accessibilityIdentifier("salir.cancelar")
```

y actualizar el comentario de cabecera: "«Cerrar sesión» revoca la sesión y vuelve a Registro (antes `popToRootViewController`)".

- [ ] **Paso 4: Identificadores.** En `ProfileView`, al `NavigationLink(value: Route.settings)` agregar `.accessibilityLabel("Ajustes").accessibilityIdentifier("perfil.ajustes")`. En `SettingsView`, al `NavigationLink(value: Route.signOut)` agregar `.accessibilityIdentifier("ajustes.cerrarSesion")`.

- [ ] **Paso 5: Pruebas** — Run: `UI` → `testCerrarSesion` en verde.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Views PrototipoAppUITests
git commit -m "feat: cerrar sesión revoca el token"
```

**Criterios de aceptación:** tras cerrar sesión y relanzar, la app arranca en Registro.
**Dependencias:** D10, V1. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea F4: Inicio con datos reales

**Objetivo:** saludo con el nombre, avatar, y "Alertas críticas" calculadas (los 2 reportes públicos más recientes de riesgo alto), con estados de carga, vacío y error.

**Archivos:**
- Modificar: `PrototipoApp/Views/Tabs/HomeView.swift` (welcomeRow, alertas, identificadores)
- Crear: `PrototipoApp/Views/Shared/AvatarView.swift`
- Test: `PrototipoAppUITests/NavegacionUITests.swift` (crear)

**Interfaces:**
- Consume: D9 (`ReportsStore.alertas`, `cargarAlertas`, `version`; `SessionStore.usuario`, `datosAvatar(de:)`), V1 (`CargaView`).
- Produce: `AvatarView(usuario:tamano:fondo:)`; identificadores `inicio.reportar`, `inicio.categoria.<tipo>` (`ofertaFalsa`, `sorteoFalso`, `tiendaClonada`), `inicio.alerta.<id>`, `inicio.guia`, `inicio.estadisticas`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppUITests/NavegacionUITests.swift`:

```swift
//
//  NavegacionUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class NavegacionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testInicioMuestraLasAlertasYAbreSuDetalle() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        XCTAssertTrue(app.elemento(contiene: "Hola, Ana.").waitForExistence(timeout: 5))
        let alerta = app.buttons["inicio.alerta.102"]
        XCTAssertTrue(alerta.waitForExistence(timeout: 5))
        capturar(app, "04-inicio")
        alerta.tocar(en: app)
        XCTAssertTrue(app.elemento(contiene: "Sorteo falso de iPhone 17").waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
    }

    @MainActor
    func testBotonReportarAbrePestana() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.reportar"].tap()
        XCTAssertTrue(app.staticTexts["Emitir Reporte"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `NavegacionUITests`) → FAIL: no aparece "Hola, Ana.". (`elemento(contiene:)` busca en cualquier elemento porque las tarjetas combinan sus textos para VoiceOver.)

- [ ] **Paso 3: Crear `Views/Shared/AvatarView.swift`**

```swift
//
//  AvatarView.swift
//  PrototipoApp
//
//  Foto de perfil (si hay y si quien mira tiene permiso) o el ícono de persona del storyboard.
//

import SwiftUI

struct AvatarView: View {
    let usuario: Usuario?
    var tamano: CGFloat = 48
    var fondo: Color = Theme.avatarBackground

    @Environment(SessionStore.self) private var session
    @State private var imagen: UIImage?

    var body: some View {
        Group {
            if let imagen {
                Image(uiImage: imagen).resizable().scaledToFill()
            } else {
                Symbol("person.fill", size: tamano * 0.42, color: Theme.textPrimary)
            }
        }
        .frame(width: tamano, height: tamano)
        .background(fondo, in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: usuario?.avatarRuta) {
            guard let usuario, usuario.avatarRuta != nil, let datos = await session.datosAvatar(de: usuario) else {
                imagen = nil
                return
            }
            imagen = UIImage(data: datos)
        }
    }
}
```

- [ ] **Paso 4: `HomeView.swift`.** Agregar `@Environment(SessionStore.self) private var session` y `@Environment(ReportsStore.self) private var reports`. Cambios:

```swift
    private var welcomeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Hola, \(session.usuario?.nombre ?? "").").ofraude(20, .bold, color: Theme.textPrimary)
                Text("Tu vigilancia mantiene la comunidad segura.").ofraude(16, color: Theme.textSlate)
            }
            Spacer()
            AvatarView(usuario: session.usuario)
        }
        .accessibilityElement(children: .combine)
    }
```

Sección de alertas (reemplaza las dos llamadas fijas a `alertCard`):

```swift
                    Hairline(color: Theme.danger)
                    Text("ALERTAS CRÍTICAS").ofraude(18, .bold, color: Theme.danger).accessibilityAddTraits(.isHeader)
                    CargaView(carga: reports.alertas, esVacio: \.isEmpty,
                              vacio: EstadoVacio(icono: "checkmark.shield", titulo: "Sin alertas críticas",
                                                 mensaje: "Por ahora no hay reportes validados de riesgo alto."),
                              reintentar: { await reports.cargarAlertas() }) { alertas in
                        ForEach(alertas) { alertCard($0) }
                    }
```

```swift
    private func alertCard(_ r: Reporte) -> some View {
        NavigationLink(value: Route.reportDetail(r.id)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(r.titulo).ofraude(15, .semibold, color: Theme.textPrimary)
                Text(r.descripcion).ofraude(14, color: Theme.textSlate).lineLimit(2)
                Text(verbatim: "\(Formato.relativo(r.fechaCreacion)) · VER DETALLES ›").ofraude(12, .bold, color: Theme.textSlate)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ofraudeCard(radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el detalle del reporte")
        .accessibilityIdentifier("inicio.alerta.\(r.id)")
    }
```

Recarga: al final del `body`, `.task(id: reports.version) { await reports.cargarAlertas() }`. Identificadores: el banner naranja `.accessibilityIdentifier("inicio.reportar")`; `categoryCard` agrega `.accessibilityIdentifier("inicio.categoria.\(tipo)")` (por ejemplo `inicio.categoria.ofertaFalsa`). `linkCard` recibe el identificador de su botón:

```swift
    private func linkCard(_ title: String, _ text: String, button: String, route: Route, id: String) -> some View {
        VStack(spacing: 8) {
            Text(title).ofraude(18, .bold, color: Theme.textPrimary).accessibilityAddTraits(.isHeader)
            Text(text).ofraude(14, color: Theme.textSlate).multilineTextAlignment(.center)
            NavigationLink(value: route) {
                Text(button)
            }
            .buttonStyle(OfraudeButtonStyle(background: Theme.background, foreground: Theme.textPrimary,
                                            size: 14, weight: .semibold, radius: 4, height: 36, fullWidth: false))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.defaultBorder, lineWidth: 1))
            .accessibilityIdentifier(id)
        }
        .padding(25)
        .frame(maxWidth: .infinity)
        .ofraudeCard(radius: 4)
    }
```

con las llamadas `linkCard(…, route: .guide, id: "inicio.guia")` y `linkCard(…, route: .stats, id: "inicio.estadisticas")`. El sello de la barra superior queda decorativo con `.accessibilityHidden(true)` (F16 lo cambia por la campana).

- [ ] **Paso 5: Pruebas** — Run: `UI` (clase `NavegacionUITests`) → 2 tests en verde.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Views PrototipoAppUITests
git commit -m "feat: inicio con saludo, avatar y alertas críticas calculadas"
```

**Criterios de aceptación:** las alertas cambian si un Administrador valida un reporte de riesgo alto (se ve después de F15); sin red o con error aparece "Reintentar".
**Dependencias:** D10, V1. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea F5: Detalle dinámico según la tarjeta

**Objetivo:** el detalle muestra el reporte que se abrió: tipo, severidad o estado, título, autor visible, ciudad, fecha, descripción, sitio "desactivado", persona afectada (solo autor y staff), historial (autor y staff) y modus operandi del tipo.

**Archivos:**
- Modificar: `PrototipoApp/Views/Reports/ReportDetailView.swift` (todo el archivo)
- Crear: `PrototipoApp/Views/Reports/ReportDetailSections.swift`
- Modificar: `PrototipoApp/Theme/Components.swift` (agregar `Etiqueta`)
- Test: `PrototipoAppUITests/DetalleUITests.swift` (crear)

**Interfaces:**
- Consume: D9 (`ReportsStore.detalle`, `historial`, `version`), S4 (`URLTools.desactivar`, `esPosibleHomografo`), V1 (`CargaView`, colores de `Theme+Dominio.swift`).
- Produce: `ReportDetailView(id:)`; `SitioSospechosoView(reporte:)`, `EstadoReporteView(reporte:historial:)`, `PersonaAfectadaView(persona:)`; `Etiqueta(texto:color:fondo:)`; identificadores `detalle.titulo`, `detalle.sitio`, `detalle.estado`, `detalle.moderar`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppUITests/DetalleUITests.swift`:

```swift
//
//  DetalleUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class DetalleUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testElDetalleEsElDeLaTarjetaYElEnlaceVaDesactivado() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.alerta.101"].tocar(en: app)
        XCTAssertTrue(app.staticTexts["detalle.titulo"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detalle.titulo"].label, "Alerta: Falsa liquidación de tienda de electrónica")
        XCTAssertEqual(app.staticTexts["detalle.sitio"].label, "hxxps://liquidacion-electronica-mx[.]shop")
        XCTAssertTrue(app.elemento(contiene: "Reportado por tecno_mx").exists)
        capturar(app, "05-detalle")
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `DetalleUITests`) → FAIL: no existe `detalle.titulo`.

- [ ] **Paso 3: Agregar `Etiqueta` a `Theme/Components.swift`** (sección Layout):

```swift
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
```

- [ ] **Paso 4: Crear `Views/Reports/ReportDetailSections.swift`**

```swift
//
//  ReportDetailSections.swift
//  PrototipoApp
//
//  Piezas del detalle que también usa la revisión de moderación: el sitio reportado,
//  el estado con su historial y la persona afectada.
//

import SwiftUI

/// El enlace o dato reportado, "desactivado": nunca se puede abrir desde la app.
struct SitioSospechosoView: View {
    let reporte: Reporte
    @State private var copiado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Symbol("exclamationmark.triangle.fill", size: 14, color: Theme.danger)
                Text("NO ABRAS ESTE ENLACE").ofraude(12, .bold, color: Theme.dangerText)
            }
            if let sitio = reporte.sitio {
                Text(verbatim: URLTools.desactivar(sitio.url))
                    .ofraude(15, .semibold, color: Theme.textLight)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("detalle.sitio")
                Text(verbatim: "\(sitio.estadoCertificado ?? "SIN DATOS") · Riesgo del sitio: \(sitio.nivelRiesgoGlobal.titulo)")
                    .ofraude(12, color: Theme.textMuted)
                if URLTools.esPosibleHomografo(sitio.url) {
                    Text("Este dominio usa caracteres que imitan a otros (posible homógrafo).")
                        .ofraude(12, .semibold, color: Theme.accent)
                }
                Button {
                    UIPasteboard.general.string = URLTools.desactivar(sitio.url)
                    copiado = true
                } label: {
                    Text(copiado ? "Copiado" : "Copiar enlace desactivado").ofraude(13, .semibold, color: Theme.accent)
                }
                .buttonStyle(.plain)
            } else if let texto = reporte.textoSospechoso {
                Text(texto).ofraude(15, .semibold, color: Theme.textLight).textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8, fill: Theme.field)
    }
}

/// Estado actual y la historia de cambios (solo autor y staff).
struct EstadoReporteView: View {
    let reporte: Reporte
    let historial: [HistorialEstado]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ESTADO").ofraude(12, .bold, color: Theme.textMuted)
                Etiqueta(texto: reporte.estado.titulo, color: reporte.estado.color, fondo: reporte.estado.color.opacity(0.2))
                    .accessibilityIdentifier("detalle.estado")
            }
            ForEach(historial) { h in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(h.nuevo.titulo) · \(Formato.relativo(h.fecha)) · \(h.responsable)")
                        .ofraude(12, .semibold, color: Theme.textLight)
                    if let observaciones = h.observaciones {
                        Text(observaciones).ofraude(12, color: Theme.textMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8)
    }
}

/// Datos de un tercero: nunca públicos.
struct PersonaAfectadaView: View {
    let persona: PersonaAfectada

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Symbol("lock.fill", size: 12, color: Theme.textMuted)
                Text("PERSONA AFECTADA (PRIVADO)").ofraude(12, .bold, color: Theme.textMuted)
            }
            Text(persona.nombre).ofraude(15, .semibold, color: Theme.textLight)
            Text(persona.contacto).ofraude(13, color: Theme.textMuted)
            Text("Solo tú y el equipo de moderación ven estos datos.").ofraude(12, color: Theme.textSubtle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8, fill: Theme.field)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Paso 5: Reescribir `Views/Reports/ReportDetailView.swift`**

```swift
//
//  ReportDetailView.swift
//  PrototipoApp
//
//  Reemplaza: escena `reportdetail-vc` / ReportDetailViewController.
//  Antes el contenido era fijo; ahora muestra el reporte de la tarjeta que se tocó. Lo que la
//  persona no debe ver (autor anónimo, persona afectada, evidencia) ya viene filtrado del servidor.
//

import SwiftUI

struct ReportDetailView: View {
    let id: Int64

    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports
    @State private var carga: Carga<Reporte> = .cargando
    @State private var historial: [HistorialEstado] = []
    @State private var comment = ""

    private var esStaff: Bool { session.usuario?.rol.esStaff == true }

    var body: some View {
        ScrollView {
            CargaView(carga: carga, reintentar: cargar) { reporte in
                contenido(reporte)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Reporte")
        .navigationBarTitleDisplayMode(.inline)
        // Se recarga si algo cambió en otra pantalla (borrado, moderado, comentado).
        .task(id: reports.version) { await cargar() }
    }

    private func cargar() async {
        do {
            let r = try await reports.detalle(id: id)
            carga = .listo(r)
            if r.esMio || esStaff { historial = (try? await reports.historial(id: id)) ?? [] }
        } catch {
            carga = .error(error.mensajeUsuario)
        }
    }

    private func contenido(_ r: Reporte) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            encabezado(r)

            Text(verbatim: r.nivelRiesgo >= .alto ? "Alerta: \(r.titulo)" : r.titulo)
                .ofraude(28, .bold, color: Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("detalle.titulo")

            autor(r)

            if r.esMio || esStaff { EstadoReporteView(reporte: r, historial: historial) }

            Text(r.descripcion).ofraude(16, color: Theme.textPrimary)

            if r.sitio != nil || r.textoSospechoso != nil { SitioSospechosoView(reporte: r) }
            if let persona = r.personaAfectada { PersonaAfectadaView(persona: persona) }

            Text("Modus Operandi").ofraude(24, .bold, color: Theme.textPrimary).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(r.tipo.modusOperandi, id: \.self) { paso in
                    Text(paso).ofraude(16, color: Theme.textPrimary)
                }
            }

            meTooCard
            commentRow
            Hairline()
            Text("Comentarios de la comunidad (42)").ofraude(20, .bold, color: .white)
            commentCard("Usuario · hace 15 min",
                        "Casi compro ahí, los precios se veían muy reales. Por suerte busqué reseñas antes.")

            if esStaff {
                NavigationLink(value: Route.adminReview(r.id)) { Text("MODERAR REPORTE") }
                    .buttonStyle(OfraudeButtonStyle(background: Theme.card, foreground: Theme.accent, size: 15,
                                                    weight: .semibold, radius: 8, height: 48))
                    .accessibilityIdentifier("detalle.moderar")
            }
        }
    }

    private func encabezado(_ r: Reporte) -> some View {
        HStack(spacing: 8) {
            Etiqueta(texto: r.tipoVisible, color: Theme.textPrimary.opacity(0.8), fondo: Theme.textPrimary.opacity(0.1))
            if r.estado.esPublico {
                Etiqueta(texto: "SEVERIDAD \(r.nivelRiesgo.titulo)", color: r.nivelRiesgo.color, fondo: r.nivelRiesgo.color.opacity(0.2))
            } else {
                Etiqueta(texto: r.estado.titulo, color: r.estado.color, fondo: r.estado.color.opacity(0.2))
            }
            Spacer()
        }
    }

    private func autor(_ r: Reporte) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
                .frame(width: 40, height: 40)
                .overlay(Symbol(r.esAnonimo ? "theatermasks.fill" : "person.fill", size: 18, color: Theme.textSlate))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Reportado por \(r.autor.nombre)").ofraude(14, .semibold, color: Theme.textPrimary)
                Text(verbatim: "\(Formato.relativo(r.fechaCreacion)) · \(r.ciudad) · ocurrió el \(Formato.fechaCorta(r.fechaIncidente))")
                    .ofraude(12, color: Theme.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // meTooCard, commentRow y commentCard se conservan como estaban (F7 y F8 los reemplazan).
}

#Preview {
    NavigationStack { ReportDetailView(id: 101) }
        .entornoDePrueba()
}
```

Mantener en el archivo, sin cambios, las propiedades privadas `meTooCard`, `commentRow` y `commentCard(_:_:)` de la versión actual (con "Yo también" → `appState.push(.report(nil))`).

- [ ] **Paso 6: Pruebas** — Run: `UI` (clase `DetalleUITests`) → verde. Manual: abrir la alerta 102 y una categoría de Buscar; cada una muestra su propio contenido.

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: detalle dinámico con sitio desactivado, estado e historial"
```

**Criterios de aceptación:** el título, el autor y el sitio corresponden a la tarjeta; el enlace nunca es tocable; un reporte que ya no existe muestra "Este contenido ya no está disponible." con "Reintentar".
**Dependencias:** D10, V1, S4. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea F6: Guardar y compartir

**Objetivo:** el marcador guarda o quita de Guardados (persistente) y compartir envía un texto con el enlace desactivado y sin datos personales.

**Archivos:**
- Crear: `PrototipoApp/Model/Reporte+Compartir.swift`
- Modificar: `PrototipoApp/Views/Reports/ReportDetailView.swift` (`encabezado`, estado `errorAccion`)
- Test: `PrototipoAppTests/Model/CompartirTests.swift`, `PrototipoAppUITests/DetalleUITests.swift`

**Interfaces:**
- Consume: F5, D9 (`ReportsStore.marcarGuardado`), S4.
- Produce: `Reporte.textoParaCompartir: String`; identificadores `detalle.guardar`, `detalle.compartir`.

- [ ] **Paso 1: Prueba unitaria que falla** — `PrototipoAppTests/Model/CompartirTests.swift`:

```swift
//
//  CompartirTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct CompartirTests {
    @Test func elEnlaceSeComparteDesactivadoYSinAutor() {
        var r = Reporte.ejemplo(url: "https://n1ke-outlet-mexico.com/pago")
        r.autor = AutorVisible(idUsuario: 4, nombre: "tecno_mx")
        let texto = r.textoParaCompartir
        #expect(texto.contains("hxxps://n1ke-outlet-mexico[.]com/pago"))
        #expect(!texto.contains("https://"))
        #expect(!texto.contains("tecno_mx"))
        #expect(texto.hasPrefix("Alerta de 0Fraude: Tienda clonada de tenis deportivos"))
    }

    @Test func sinURLComparteElDatoReportado() {
        let r = Reporte.ejemplo(tipo: .llamada, url: nil, texto: "+52 55 8765 4321")
        #expect(r.textoParaCompartir.contains("Dato reportado: +52 55 8765 4321"))
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → FAIL `value of type 'Reporte' has no member 'textoParaCompartir'`.

- [ ] **Paso 3: Crear `Model/Reporte+Compartir.swift`**

```swift
//
//  Reporte+Compartir.swift
//  PrototipoApp
//
//  Texto para compartir una alerta. El enlace va "desactivado" (hxxps, [.]) para que nadie lo
//  abra por accidente desde WhatsApp, y no incluye a quien reportó.
//

import Foundation

nonisolated extension Reporte {
    var textoParaCompartir: String {
        var lineas = ["Alerta de 0Fraude: \(titulo)", "Tipo: \(tipoVisible) · Riesgo: \(nivelRiesgo.titulo)"]
        if let url = sitio?.url {
            lineas.append("Sitio reportado (no lo abras): \(URLTools.desactivar(url))")
        } else if let textoSospechoso {
            lineas.append("Dato reportado: \(textoSospechoso)")
        }
        lineas.append("Reportado en \(ciudad).")
        lineas.append("Consulta más alertas en la app 0Fraude.")
        return lineas.joined(separator: "\n")
    }
}
```

- [ ] **Paso 4: Botones en `encabezado(_:)`** (después del `Spacer()`), más el estado `@State private var errorAccion: String?` y la alerta:

```swift
            if r.estado.esPublico || r.esMio {
                Button { Task { await alternarGuardado(r) } } label: {
                    Symbol(r.guardadoPorMi ? "bookmark.fill" : "bookmark", size: 24,
                           color: r.guardadoPorMi ? Theme.accent : Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(r.guardadoPorMi ? "Quitar de guardados" : "Guardar reporte")
                .accessibilityIdentifier("detalle.guardar")
            }
            if r.estado.esPublico {
                ShareLink(item: r.textoParaCompartir, subject: Text("Alerta de 0Fraude"), preview: SharePreview(r.titulo)) {
                    Symbol("square.and.arrow.up", size: 24, color: Theme.textPrimary)
                }
                .accessibilityLabel("Compartir alerta")
                .accessibilityIdentifier("detalle.compartir")
            }
```

```swift
    /// Cambia el marcador al instante y lo confirma con el servidor; si falla, lo regresa.
    private func alternarGuardado(_ r: Reporte) async {
        var cambiado = r
        cambiado.guardadoPorMi.toggle()
        carga = .listo(cambiado)
        do {
            try await reports.marcarGuardado(id: r.id, cambiado.guardadoPorMi)
        } catch {
            carga = .listo(r)
            errorAccion = error.mensajeUsuario
        }
    }
```

En el `body`, después de `.task(id:)`:

```swift
        .alert("No se pudo completar", isPresented: Binding(get: { errorAccion != nil }, set: { if !$0 { errorAccion = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorAccion ?? "")
        }
```

- [ ] **Paso 5: Prueba de interfaz** — agregar a `DetalleUITests`:

```swift
    @MainActor
    func testGuardarYQuitarPersiste() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.alerta.101"].tocar(en: app)
        let guardar = app.buttons["detalle.guardar"]
        XCTAssertTrue(guardar.waitForExistence(timeout: 5))
        XCTAssertEqual(guardar.label, "Quitar de guardados")
        guardar.tap()
        XCTAssertTrue(app.buttons["Guardar reporte"].waitForExistence(timeout: 5))
        app.terminate()
        let otraVez = XCUIApplication.zeroScam(reiniciar: false)
        otraVez.launch()
        otraVez.buttons["inicio.alerta.101"].tocar(en: otraVez)
        XCTAssertTrue(otraVez.buttons["Guardar reporte"].waitForExistence(timeout: 5))
    }
```

- [ ] **Paso 6: Pruebas** — Run: `UNIT` y `UI` (clase `DetalleUITests`) → verde. Manual: tocar compartir abre la hoja de iOS en español con el texto desactivado.

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp PrototipoAppTests PrototipoAppUITests
git commit -m "feat: guardar y compartir alertas con el enlace desactivado"
```

**Criterios de aceptación:** guardar persiste tras reiniciar; el texto compartido no contiene `https://` ni datos de quien reportó.
**Dependencias:** F5. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea F7: "Yo también"

**Objetivo:** confirmar un reporte público ajeno (una vez por persona, el contador sube) y ofrecer reportar el caso propio con el tipo y el enlace ya llenos.

**Archivos:**
- Modificar: `PrototipoApp/Views/Reports/ReportDetailView.swift` (reemplazar `meTooCard`)
- Test: `PrototipoAppUITests/DetalleUITests.swift`

**Interfaces:**
- Consume: F5, D9 (`ReportsStore.confirmar`), D10 (`Route.report(ReportePrefill?)`).
- Produce: identificadores `detalle.yoTambien`, `detalle.confirmaciones`. F9 lee el `ReportePrefill`.

- [ ] **Paso 1: Prueba que falla** — agregar a `DetalleUITests`:

```swift
    @MainActor
    func testYoTambienSumaUnaVezYOfreceReportar() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.alerta.101"].tocar(en: app)
        let contador = app.staticTexts["detalle.confirmaciones"]
        contador.tocar(en: app)
        XCTAssertEqual(contador.label, "1.2k personas lo confirmaron.")
        app.buttons["detalle.yoTambien"].tap()
        XCTAssertTrue(app.buttons["Sí, reportar mi caso"].waitForExistence(timeout: 5))
        app.buttons["Solo confirmar"].tap()
        XCTAssertFalse(app.buttons["detalle.yoTambien"].isEnabled)
        XCTAssertEqual(app.buttons["detalle.yoTambien"].label, "Confirmado")
    }
```

(1,200 + 1 se sigue mostrando "1.2k": el formato corto redondea; el cambio se nota en el botón.)

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `DetalleUITests`) → FAIL: no existe `detalle.confirmaciones`.

- [ ] **Paso 3: Reemplazar `meTooCard`** por una función que recibe el reporte, más el estado `@State private var preguntarReporte: Reporte?`:

```swift
    private func tarjetaYoTambien(_ r: Reporte) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("¿Has recibido esto?").ofraude(16, .bold, color: Theme.textPrimary)
                Text(verbatim: "\(Formato.conteoCorto(r.confirmaciones)) personas lo confirmaron.")
                    .ofraude(14, color: Theme.textPrimary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("detalle.confirmaciones")
            }
            Spacer(minLength: 0)
            BotonAccion(titulo: r.confirmadoPorMi ? "Confirmado" : "Yo también",
                        estilo: OfraudeButtonStyle(foreground: Theme.background, size: 14, weight: .bold,
                                                   radius: 4, height: 40, fullWidth: false),
                        habilitado: !r.confirmadoPorMi, identificador: "detalle.yoTambien") {
                await yoTambien(r)
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8)
    }

    private func yoTambien(_ r: Reporte) async {
        do {
            carga = .listo(try await reports.confirmar(id: r.id))
            preguntarReporte = r
        } catch {
            errorAccion = error.mensajeUsuario
        }
    }
```

En `contenido(_:)`, reemplazar `meTooCard` por `if r.estado.esPublico && !r.esMio { tarjetaYoTambien(r) }`. En el `body`:

```swift
        .confirmationDialog("¿Quieres reportar tu caso?", isPresented: Binding(get: { preguntarReporte != nil },
                                                                             set: { if !$0 { preguntarReporte = nil } }),
                            titleVisibility: .visible, presenting: preguntarReporte) { r in
            Button("Sí, reportar mi caso") {
                appState.push(.report(ReportePrefill(tipo: r.tipo, tipoOtro: r.tipoOtro,
                                                     urlOTexto: r.sitio?.url ?? r.textoSospechoso ?? "")))
            }
            Button("Solo confirmar", role: .cancel) {}
        } message: { _ in
            Text("Tu confirmación ya cuenta. Si te pasó a ti, un reporte propio con tus datos ayuda más.")
        }
```

- [ ] **Paso 4: Pruebas** — Run: `UI` (clase `DetalleUITests`) → verde.

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp/Views/Reports/ReportDetailView.swift PrototipoAppUITests
git commit -m "feat: yo también confirma una vez y ofrece reportar el caso propio"
```

**Criterios de aceptación:** una persona suma una sola confirmación; no aparece en reportes propios ni no públicos; "Sí, reportar mi caso" abre Reportar con tipo y enlace llenos (se comprueba en F9).
**Dependencias:** F5, V1. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea F8: Comentarios

**Objetivo:** publicar comentarios (2–500 caracteres, sin caracteres invisibles, máximo 5 por minuto), verlos con autor según su privacidad y borrar los propios (staff: cualquiera) con confirmación.

**Archivos:**
- Crear: `PrototipoApp/Views/Reports/ComentariosView.swift`
- Modificar: `PrototipoApp/Views/Reports/ReportDetailView.swift` (quitar `commentRow`, `commentCard`, el título fijo "(42)" y la tarjeta fija; usar `ComentariosView`)
- Test: `PrototipoAppUITests/DetalleUITests.swift`

**Interfaces:**
- Consume: F5, D9 (`ReportsStore.comentarios`, `comentar`, `eliminarComentario`), V1, S3.
- Produce: `ComentariosView(reporte:puedeModerar:)`; identificadores `detalle.comentario`, `detalle.publicar`.

- [ ] **Paso 1: Prueba que falla** — agregar a `DetalleUITests`:

```swift
    @MainActor
    func testComentarPublicaYSePuedeBorrar() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.alerta.102"].tocar(en: app)
        let campo = app.textFields["detalle.comentario"]
        campo.tocar(en: app)
        campo.typeText("A mí también me escribió esa cuenta.")
        app.buttons["detalle.publicar"].tap()
        let nuevo = app.elemento(contiene: "A mí también me escribió esa cuenta.")
        XCTAssertTrue(nuevo.waitForExistence(timeout: 5))
        nuevo.press(forDuration: 1.0)
        app.buttons["Eliminar comentario"].tap()
        app.alerts.buttons["Eliminar"].tap()
        XCTAssertTrue(nuevo.waitForNonExistence(timeout: 5))
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `DetalleUITests`) → FAIL: no existe `detalle.publicar`.

- [ ] **Paso 3: Crear `Views/Reports/ComentariosView.swift`**

```swift
//
//  ComentariosView.swift
//  PrototipoApp
//
//  Comentarios de un reporte público (antes "publicar comentario" era un TODO y la lista era
//  fija). El servidor limpia el texto, limita a 5 por minuto y decide quién puede borrar.
//

import SwiftUI

struct ComentariosView: View {
    let reporte: Reporte
    let puedeModerar: Bool

    @Environment(ReportsStore.self) private var reports
    @State private var carga: Carga<[Comentario]> = .cargando
    @State private var texto = ""
    @State private var error: String?
    @State private var paraBorrar: Comentario?
    @FocusState private var foco: Campo?

    private var limpio: String { Sanitizador.texto(texto, maximo: 500, multilinea: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                OfraudeTextField(placeholder: "Escribe un comentario...", text: $texto, maximo: 500,
                                 foco: $foco, campo: .comentario, identificador: "detalle.comentario")
                    .submitLabel(.send)
                    .onSubmit { Task { await publicar() } }
                BotonAccion(titulo: "Publicar comentario", icono: "arrow.up",
                            estilo: OfraudeButtonStyle(radius: 8, height: 48, fullWidth: false),
                            habilitado: Validador.comentario(limpio).isEmpty, identificador: "detalle.publicar") {
                    await publicar()
                }
            }
            FieldError(mensaje: error)
            Hairline()
            Text(verbatim: "Comentarios de la comunidad (\(carga.valor?.count ?? reporte.comentarios))")
                .ofraude(20, .bold, color: Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            CargaView(carga: carga, esVacio: \.isEmpty,
                      vacio: EstadoVacio(icono: "bubble.left", titulo: "Sin comentarios", mensaje: "Sé la primera persona en comentar."),
                      reintentar: cargar) { lista in
                ForEach(lista) { tarjeta($0) }
            }
        }
        .task(id: reporte.id) { await cargar() }
        .alert("¿Eliminar comentario?", isPresented: Binding(get: { paraBorrar != nil }, set: { if !$0 { paraBorrar = nil } }),
               presenting: paraBorrar) { c in
            Button("Eliminar", role: .destructive) { Task { await borrar(c) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("No se puede deshacer.")
        }
    }

    private func tarjeta(_ c: Comentario) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(c.autor) · \(Formato.relativo(c.fecha).lowercased())").ofraude(13, .bold, color: Theme.textPrimary)
            Text(c.texto).ofraude(14, color: Theme.textPrimary)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if c.esMio || puedeModerar {
                Button("Eliminar comentario", systemImage: "trash", role: .destructive) { paraBorrar = c }
            }
        }
        .accessibilityAction(named: "Eliminar comentario") {
            if c.esMio || puedeModerar { paraBorrar = c }
        }
    }

    private func cargar() async {
        do { carga = .listo(try await reports.comentarios(id: reporte.id)) }
        catch { carga = .error(error.mensajeUsuario) }
    }

    private func publicar() async {
        guard Validador.comentario(limpio).isEmpty else { return }
        error = nil
        do {
            _ = try await reports.comentar(id: reporte.id, texto: limpio)
            texto = ""
            foco = nil
            await cargar()
        } catch {
            self.error = error.mensajeUsuario
        }
    }

    private func borrar(_ c: Comentario) async {
        do {
            try await reports.eliminarComentario(id: c.id)
            await cargar()
        } catch {
            self.error = error.mensajeUsuario
        }
    }
}
```

- [ ] **Paso 4: Usarlo en el detalle.** En `contenido(_:)` reemplazar `commentRow`, `Hairline()`, el título "(42)" y `commentCard(…)` por:

```swift
            if r.estado.esPublico {
                ComentariosView(reporte: r, puedeModerar: esStaff)
            } else {
                Text("Los comentarios se abren cuando el reporte se valida.").ofraude(13, color: Theme.textMuted)
            }
```

y borrar `commentRow`, `commentCard(_:_:)` y `@State private var comment`.

- [ ] **Paso 5: Pruebas** — Run: `UI` (clase `DetalleUITests`) → verde.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Views/Reports PrototipoAppUITests
git commit -m "feat: comentarios reales con límite y borrado con confirmación"
```

**Criterios de aceptación:** el comentario aparece y sobrevive al reinicio; un comentario de 1 carácter no se puede publicar; borrar pide confirmación; VoiceOver ofrece la acción "Eliminar comentario".
**Dependencias:** F5, V1. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea F9: Formulario de reporte y envío real

**Objetivo:** que "ENVIAR REPORTE" valide y guarde un reporte completo (anónimo, a quién le ocurrió, persona afectada con autorización, ciudad, tipo, "Otro" especificado, título, fecha, URL o texto, descripción) y muestre el folio; el mismo formulario sirve para "Yo también" (prellenado) y para editar.

**Archivos:**
- Modificar: `PrototipoApp/Views/Tabs/ReportView.swift` (todo el archivo)
- Modificar: `PrototipoApp/Views/Reports/ReportSuccessView.swift` (todo el archivo)
- Modificar: `PrototipoApp/Views/Route+Destination.swift` (`.report`, `.reportSuccess`, `.editReport`)
- Test: `PrototipoAppUITests/FlujoReporteUITests.swift` (crear)

**Interfaces:**
- Consume: D9 (`ReportsStore.crear`, `actualizar`, `detalle`), D10 (`Route.report(ReportePrefill?)`, `.editReport(Int64)`, `.reportSuccess(Int64)`), S3 (`Validador.reporte`, `ReporteBorrador.limpio`), V1.
- Produce: `ReportView(modo:)` con `ReportView.Modo` = `.nuevo(ReportePrefill?)` | `.editar(Int64)`; `ReportSuccessView(id:)`; identificadores `reporte.anonimo`, `reporte.afectado.yo`, `reporte.afectado.otraPersona`, `reporte.persona.nombre`, `reporte.persona.contacto`, `reporte.persona.autorizo`, `reporte.ciudad`, `reporte.tipo.<tipo>`, `reporte.tipoOtro`, `reporte.titulo`, `reporte.fecha`, `reporte.url`, `reporte.descripcion`, `reporte.enviar`, `reporte.error`, `exito.folio`, `exito.continuar`, `exito.misReportes`.

- [ ] **Paso 1: Pruebas que fallan** — `PrototipoAppUITests/FlujoReporteUITests.swift`:

```swift
//
//  FlujoReporteUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class FlujoReporteUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testEnviarReporteMuestraFolioYContinuarVaciaLasPilas() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Reportar"].tap()
        app.llenarReporte(titulo: "Prueba UI: tienda falsa de consolas")
        capturar(app, "06-reportar")
        app.buttons["reporte.enviar"].tocar(en: app)
        XCTAssertTrue(app.staticTexts["exito.folio"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["exito.folio"].label.contains("RECIBIDO"))
        capturar(app, "07-exito")
        app.buttons["exito.continuar"].tap()
        XCTAssertTrue(app.buttons["inicio.reportar"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testElFormularioNoAceptaUnEnlacePeligroso() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Reportar"].tap()
        app.llenarReporte(titulo: "Prueba UI: enlace peligroso", enlace: "javascript:alert(1)")
        XCTAssertTrue(app.elemento(contiene: "Solo se aceptan enlaces http:// o https:// válidos.").exists)
        XCTAssertFalse(app.buttons["reporte.enviar"].isEnabled)
    }

    @MainActor
    func testYoTambienPrellenaTipoYEnlace() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.alerta.101"].tocar(en: app)
        app.buttons["detalle.yoTambien"].tocar(en: app)
        app.buttons["Sí, reportar mi caso"].tap()
        let enlace = app.textFields["reporte.url"]
        enlace.tocar(en: app)
        XCTAssertEqual(enlace.value as? String, "https://liquidacion-electronica-mx.shop")
        XCTAssertTrue(app.buttons["reporte.tipo.ofertaFalsa"].isSelected)
    }
}
```

Agregar a `PrototipoAppUITests/Soporte/Ayudantes.swift`, dentro de `extension XCUIApplication`:

```swift
    /// Llena los campos obligatorios de Reportar (tipo Tienda Clonada).
    func llenarReporte(titulo: String, enlace: String = "https://consolas-baratas.store") {
        textFields["reporte.ciudad"].tocar(en: self)
        textFields["reporte.ciudad"].typeText("CDMX")
        buttons["reporte.tipo.tiendaClonada"].tocar(en: self)
        textFields["reporte.titulo"].tocar(en: self)
        textFields["reporte.titulo"].typeText(titulo)
        textFields["reporte.url"].tocar(en: self)
        textFields["reporte.url"].typeText(enlace)
        textViews["reporte.descripcion"].tocar(en: self)
        textViews["reporte.descripcion"].typeText("Ofrecen consolas a mitad de precio, piden transferencia y no entregan.")
        buttons["Listo"].firstMatch.tap()
    }
```

- [ ] **Paso 2: Ver que fallan** — Run: `UI` (clase `FlujoReporteUITests`) → FAIL: no existe `reporte.ciudad`.

- [ ] **Paso 3: Reescribir `Views/Tabs/ReportView.swift`**

```swift
//
//  ReportView.swift
//  PrototipoApp
//
//  Reemplaza: escena `report-vc` / ReportViewController.
//  Antes "Enviar" solo abría la pantalla de éxito; ahora valida y guarda el reporte. La misma
//  pantalla sirve para un reporte nuevo (pestaña Reportar), para "Yo también" (llega con tipo y
//  enlace) y para editar uno propio que aún no se ha validado.
//  - La selección (borde naranja) sigue siendo la del original (antes `select(_:in:)`).
//  - Los errores de un campo aparecen al salir de él; el botón se habilita cuando todo es válido.
//

import SwiftUI

struct ReportView: View {
    enum Modo: Hashable {
        case nuevo(ReportePrefill?)
        case editar(Int64)
    }

    var modo: Modo = .nuevo(nil)

    @Environment(AppState.self) private var appState
    @Environment(ReportsStore.self) private var reports
    @Environment(\.dismiss) private var dismiss

    @State private var borrador = ReporteBorrador()
    @State private var existentes: [Evidencia] = []
    @State private var preparado = false
    @State private var tocados: Set<Campo> = []
    @State private var errorEnvio: String?
    @FocusState private var foco: Campo?

    private let fraudRows: [[TipoFraude]] = [[.ofertaFalsa, .sorteoFalso], [.tiendaClonada, .marketplace], [.llamada, .otro]]

    private var esEdicion: Bool {
        if case .editar = modo { return true }
        return false
    }

    private var errores: [ErrorCampo] {
        var lista = Validador.reporte(borrador.limpio, ahora: Date())
        let total = existentes.filter { !borrador.quitarEvidencias.contains($0.id) }.count + borrador.adjuntos.count
        if total > 3 { lista.append(ErrorCampo(campo: .adjuntos, mensaje: "Máximo 3 archivos de evidencia.")) }
        return lista
    }

    private func error(_ campo: Campo) -> String? {
        tocados.contains(campo) ? errores.mensaje(para: campo) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(esEdicion ? "Editar Reporte" : "Emitir Reporte").ofraude(28, .bold, color: Theme.textPrimary)
                Text("Ayuda a la comunidad reportando actividades sospechosas o fraudulentas.")
                    .ofraude(16, color: Theme.textMuted)

                anonymousCard

                Text("¿A quién le ocurrió el fraude?").ofraude(18, .semibold, color: Theme.textPrimary)
                HStack(spacing: 16) {
                    ForEach(Afectado.allCases, id: \.self) { opcion in
                        choiceButton(opcion.titulo, isSelected: borrador.afectado == opcion,
                                     identificador: "reporte.afectado.\(opcion)") { borrador.afectado = opcion }
                    }
                }

                lugarYPersona

                Text("Tipo de Fraude").ofraude(18, .semibold, color: Theme.textPrimary)
                ForEach(fraudRows, id: \.self) { fila in
                    HStack(spacing: 16) {
                        ForEach(fila) { tipo in
                            choiceButton(tipo.rawValue, isSelected: borrador.tipo == tipo,
                                         identificador: "reporte.tipo.\(tipo)") { borrador.tipo = tipo }
                        }
                    }
                }
                // Antes "(OPCIONAL)" se veía siempre; ahora solo cuando se elige "Otro", y es obligatorio.
                if borrador.tipo == .otro {
                    LabeledTextField(label: "ESPECIFICA EL TIPO", placeholder: "Ej: Fraude piramidal, préstamo falso...",
                                     text: $borrador.tipoOtro, error: error(.tipoOtro), maximo: 50,
                                     foco: $foco, campo: .tipoOtro, identificador: "reporte.tipoOtro")
                }

                LabeledTextField(label: "TÍTULO DEL REPORTE", placeholder: "Ej: Tienda falsa de consolas en Instagram",
                                 text: $borrador.titulo, error: error(.titulo), maximo: 120,
                                 foco: $foco, campo: .titulo, identificador: "reporte.titulo")

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("FECHA DEL INCIDENTE")
                    DatePicker("Fecha del incidente", selection: $borrador.fechaIncidente,
                               in: Date().addingTimeInterval(-365 * 86_400)...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .tint(Theme.accent)
                        .environment(\.locale, Formato.locale)
                        .accessibilityIdentifier("reporte.fecha")
                    FieldError(mensaje: error(.fecha))
                }

                LabeledTextField(label: "URL O TEXTO SOSPECHOSO", placeholder: "Ej: http://sitio-falso.com",
                                 text: $borrador.urlOTexto, keyboard: .URL, error: error(.urlOTexto), maximo: 2048,
                                 foco: $foco, campo: .urlOTexto, identificador: "reporte.url")
                Text("Pega el enlace tal cual: se guarda desactivado para que nadie lo abra por accidente.")
                    .ofraude(12, color: Theme.textMuted)

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("DESCRIPCIÓN DEL INCIDENTE")
                    OfraudeTextEditor(placeholder: "Describe cómo ocurrió el intento de fraude...", text: $borrador.descripcion,
                                      maximo: 2000, error: error(.descripcion), foco: $foco, campo: .descripcion,
                                      identificador: "reporte.descripcion")
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("EVIDENCIA (OPCIONAL)")
                    evidenceBox
                }

                if let errorEnvio {
                    AvisoBanner(texto: errorEnvio, tono: .error).accessibilityIdentifier("reporte.error")
                }

                BotonAccion(titulo: esEdicion ? "GUARDAR CAMBIOS" : "ENVIAR REPORTE",
                            estilo: OfraudeButtonStyle(foreground: Theme.background, size: 15, weight: .bold, radius: 4, height: 56),
                            habilitado: errores.isEmpty, identificador: "reporte.enviar") {
                    await enviar()
                }
                if !errores.isEmpty {
                    Text("Completa los campos marcados para enviar.")
                        .ofraude(12, color: Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle(esEdicion ? "Editar reporte" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { foco = nil }
            }
        }
        .onChange(of: foco) { anterior, _ in
            if let anterior { tocados.insert(anterior) }
        }
        // La casilla no tiene foco de teclado: se marca como tocada al cambiarla o al cambiar "A quién".
        .onChange(of: borrador.persona.autorizo) { tocados.insert(.personaAutorizo) }
        .onChange(of: borrador.afectado) { tocados.insert(.personaAutorizo) }
        .task { await preparar() }
    }

    private var anonymousCard: some View {
        Toggle(isOn: $borrador.esAnonimo) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reportar de forma anónima").ofraude(15, .semibold, color: Theme.textPrimary)
                Text("Tu nombre no se compartirá con la comunidad. El equipo de moderación sí sabe quién reportó.")
                    .ofraude(13, color: Theme.textMuted)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .ofraudeCard(radius: 8)
        .accessibilityIdentifier("reporte.anonimo")
    }

    /// "A mí": solo la ciudad. "A otra persona": nombre, contacto, ciudad y su autorización.
    private var lugarYPersona: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(borrador.afectado == .otraPersona ? "DATOS DE LA PERSONA AFECTADA" : "¿DÓNDE OCURRIÓ?")
            if borrador.afectado == .otraPersona {
                OfraudeTextField(placeholder: "Nombre completo", text: $borrador.persona.nombre, contenido: .name,
                                 error: error(.personaNombre) != nil, maximo: 100,
                                 foco: $foco, campo: .personaNombre, identificador: "reporte.persona.nombre")
                FieldError(mensaje: error(.personaNombre))
                OfraudeTextField(placeholder: "Teléfono o correo de contacto", text: $borrador.persona.contacto,
                                 error: error(.personaContacto) != nil, maximo: 150,
                                 foco: $foco, campo: .personaContacto, identificador: "reporte.persona.contacto")
                FieldError(mensaje: error(.personaContacto))
            }
            OfraudeTextField(placeholder: "Ciudad", text: $borrador.ciudad, contenido: .addressCity,
                             error: error(.ciudad) != nil, maximo: 60,
                             foco: $foco, campo: .ciudad, identificador: "reporte.ciudad")
            FieldError(mensaje: error(.ciudad))
            if borrador.afectado == .otraPersona {
                CasillaVerificacion(texto: "Esta persona me autorizó a compartir sus datos con el equipo de moderación.",
                                    marcado: $borrador.persona.autorizo, identificador: "reporte.persona.autorizo")
                FieldError(mensaje: error(.personaAutorizo))
                Text("Sus datos nunca se publican.").ofraude(12, color: Theme.textMuted)
            }
        }
    }

    private func choiceButton(_ title: String, isSelected: Bool, identificador: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .ofraude(14, .bold, color: Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(isSelected ? Theme.selected : Theme.card, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identificador)
    }

    // `evidenceBox` se conserva igual hasta F10.

    private func preparar() async {
        guard !preparado else { return }
        preparado = true
        switch modo {
        case .nuevo(let prefill?):
            borrador.tipo = prefill.tipo
            borrador.tipoOtro = prefill.tipoOtro ?? ""
            borrador.urlOTexto = prefill.urlOTexto
        case .nuevo(nil):
            break
        case .editar(let id):
            do {
                let r = try await reports.detalle(id: id)
                borrador = ReporteBorrador(desde: r)
                existentes = r.evidencias
            } catch {
                errorEnvio = error.mensajeUsuario
            }
        }
    }

    private func enviar() async {
        errorEnvio = nil
        foco = nil
        do {
            switch modo {
            case .nuevo:
                let reporte = try await reports.crear(borrador.limpio)
                borrador = ReporteBorrador()
                tocados = []
                appState.push(.reportSuccess(reporte.id))
            case .editar(let id):
                _ = try await reports.actualizar(id: id, borrador.limpio)
                dismiss()
            }
        } catch {
            errorEnvio = error.mensajeUsuario
        }
    }
}

#Preview {
    NavigationStack { ReportView() }
        .entornoDePrueba()
}
```

- [ ] **Paso 4: Reescribir `Views/Reports/ReportSuccessView.swift`**

```swift
//
//  ReportSuccessView.swift
//  PrototipoApp
//
//  Reemplaza: escena `reportsuccess-vc` / ReportSuccessViewController.
//  Muestra el folio y el estado inicial. "Continuar" vuelve a Inicio con todas las pilas vacías
//  (antes `selectedIndex = 0` + `popToViewController(tabBarController)`); "Ver mis reportes" va a Perfil.
//

import SwiftUI

struct ReportSuccessView: View {
    let id: Int64

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 14) {
            Symbol("checkmark.circle.fill", size: 28, color: Theme.success)
                .frame(width: 56, height: 56)
                .background(Theme.success.opacity(0.2), in: Circle())
                .accessibilityHidden(true)

            Text("¡Reporte enviado con éxito!").ofraude(22, .bold, color: Theme.textLight)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: "Folio \(Formato.folio(id)) · Estado: \(EstadoReporte.recibido.titulo)")
                .ofraude(14, .semibold, color: Theme.accent)
                .accessibilityIdentifier("exito.folio")
            Text("Gracias por ayudar a mantener segura a la comunidad. Te avisaremos cuando el equipo de moderación lo revise.")
                .ofraude(14, color: Theme.textMuted)
                .multilineTextAlignment(.center)

            Button("CONTINUAR") { appState.popToTabs(selecting: .home) }
                .buttonStyle(OfraudeButtonStyle())
                .accessibilityIdentifier("exito.continuar")
            Button("VER MIS REPORTES") {
                appState.profileSegment = .misReportes
                appState.popToTabs(selecting: .profile)
            }
            .buttonStyle(OfraudeButtonStyle(background: .clear, foreground: Theme.textLight))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
            .accessibilityIdentifier("exito.misReportes")
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
        .ofraudeScreen()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { ReportSuccessView(id: 1_024) }
        .entornoDePrueba()
}
```

- [ ] **Paso 5: Rutas.** En `Route+Destination.swift`: `case .report(let prefill): ReportView(modo: .nuevo(prefill))`, `case .reportSuccess(let id): ReportSuccessView(id: id)`, y sacar `.editReport` del grupo para poner `case .editReport(let id): ReportView(modo: .editar(id))`.

- [ ] **Paso 6: Pruebas** — Run: `UI` (clase `FlujoReporteUITests`) → 3 tests en verde; `UNIT` en verde.

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: formulario de reporte con validación, envío real y folio"
```

**Criterios de aceptación:** no se puede enviar sin ciudad, título (10–120), descripción (20–2000) o con un enlace no http/https; "A otra persona" exige nombre, contacto válido y autorización; el reporte nuevo queda RECIBIDO con folio; el formulario se limpia al enviar; "Yo también" llega prellenado.
**Dependencias:** D10, V1, S3, F7 (para la prueba de prellenado). **Esfuerzo:** L. **Riesgo:** medio (formulario largo; teclado y desplazamiento se revisan en V3).

### Tarea F10: Evidencia (galería, cámara y PDF)

**Objetivo:** agregar hasta 3 archivos de evidencia, quitarlos, verlos en grande, y guardarlos sin metadatos de ubicación y cifrados por iOS.

**Archivos:**
- Crear: `PrototipoApp/Views/Reports/EvidenceEditor.swift` (`EvidenceEditor`, `MiniaturaEvidencia`, `VisorEvidencia`, `VistaPDF`)
- Crear: `PrototipoApp/Views/Shared/CameraPicker.swift`
- Modificar: `PrototipoApp/Views/Tabs/ReportView.swift` (reemplazar `evidenceBox` por `EvidenceEditor`)
- Modificar: `PrototipoApp/Views/Reports/ReportDetailView.swift` (galería)
- Modificar: `PrototipoApp/App/Dependencies.swift` (borrar temporales al arrancar)
- Modificar: `PrototipoApp.xcodeproj/project.pbxproj` (`INFOPLIST_KEY_NSCameraUsageDescription` en Debug y Release del target)
- Test: `PrototipoAppUITests/FlujoReporteUITests.swift`

**Interfaces:**
- Consume: S6 (`ProcesadorEvidencia.limpiarImagen`, `validarPDF`, `ErrorEvidencia`; `ArchivosEvidencia.guardarTemporal`, `datos(de:)`, `borrarTemporal(_:)`, `limpiarTemporales()`), D9 (`ReportsStore.archivos`, `datosEvidencia`), D10 (`appConfig.evidenciaDePrueba`).
- Produce: `EvidenceEditor(adjuntos:existentes:quitar:)`; `MiniaturaEvidencia(fuente:quitar:)` con `MiniaturaEvidencia.Fuente` = `.guardada(Evidencia)` | `.nueva(Adjunto)`; `CameraPicker(alTomar:)`; identificador `reporte.evidencia.agregar`.

- [ ] **Paso 1: Prueba que falla** — agregar a `FlujoReporteUITests`:

```swift
    @MainActor
    func testEvidenciaSeAgregaYSeQuita() {
        let app = XCUIApplication.zeroScam(extra: ["-evidenciaDePrueba"])
        app.launch()
        app.entrar()
        app.tabBars.buttons["Reportar"].tap()
        for _ in 1...3 {
            app.buttons["reporte.evidencia.agregar"].tocar(en: app)
            app.buttons["Imagen de prueba"].tap()
            _ = app.buttons["Foto de evidencia"].firstMatch.waitForExistence(timeout: 10)
        }
        XCTAssertEqual(app.buttons.matching(identifier: "Foto de evidencia").count, 3)
        XCTAssertFalse(app.buttons["reporte.evidencia.agregar"].exists)
        app.buttons["Quitar evidencia"].firstMatch.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "Foto de evidencia").count, 2)
        XCTAssertTrue(app.buttons["reporte.evidencia.agregar"].exists)
    }
```

(`matching(identifier:)` también compara con la etiqueta de accesibilidad cuando el elemento no tiene identificador.)

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `FlujoReporteUITests`) → FAIL: no existe `reporte.evidencia.agregar`.

- [ ] **Paso 3: Crear `Views/Shared/CameraPicker.swift`** (mismo patrón que la práctica `IS Modulo Avril Swift/Camera`)

```swift
//
//  CameraPicker.swift
//  PrototipoApp
//
//  Cámara del sistema (UIImagePickerController), igual que en la práctica Camera. Solo se ofrece
//  si el dispositivo tiene cámara: el simulador no tiene.
//

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    let alTomar: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controlador = UIImagePickerController()
        controlador.sourceType = .camera
        controlador.delegate = context.coordinator
        return controlador
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinador { Coordinador(self) }

    final class Coordinador: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let padre: CameraPicker

        init(_ padre: CameraPicker) { self.padre = padre }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let imagen = info[.originalImage] as? UIImage, let datos = imagen.jpegData(compressionQuality: 0.9) {
                padre.alTomar(datos)
            }
            padre.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            padre.dismiss()
        }
    }
}
```

- [ ] **Paso 4: Crear `Views/Reports/EvidenceEditor.swift`**

```swift
//
//  EvidenceEditor.swift
//  PrototipoApp
//
//  Evidencia del reporte (antes un botón vacío, TODO del original): fotos de la galería, cámara
//  (solo en dispositivo real) o un PDF. Toda imagen se vuelve a codificar sin metadatos (se borra
//  la ubicación GPS) y se guarda cifrada por iOS antes de enviarse.
//

import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct EvidenceEditor: View {
    @Binding var adjuntos: [Adjunto]
    let existentes: [Evidencia]
    @Binding var quitar: Set<Int64>

    @Environment(ReportsStore.self) private var reports
    @Environment(\.appConfig) private var config
    @State private var seleccion: [PhotosPickerItem] = []
    @State private var mostrarFotos = false
    @State private var mostrarCamara = false
    @State private var mostrarArchivos = false
    @State private var procesando = false
    @State private var error: String?

    private var visibles: [Evidencia] { existentes.filter { !quitar.contains($0.id) } }
    private var restantes: Int { max(0, 3 - visibles.count - adjuntos.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !visibles.isEmpty || !adjuntos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(visibles) { e in
                        MiniaturaEvidencia(fuente: .guardada(e)) { quitar.insert(e.id) }
                    }
                    ForEach(adjuntos) { a in
                        MiniaturaEvidencia(fuente: .nueva(a)) {
                            adjuntos.removeAll { $0.id == a.id }
                            try? reports.archivos.borrarTemporal(a)
                        }
                    }
                }
            }
            if restantes > 0 {
                Menu {
                    Button("Elegir de la galería", systemImage: "photo.on.rectangle") { mostrarFotos = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Tomar foto", systemImage: "camera") { mostrarCamara = true }
                    }
                    Button("Elegir un PDF", systemImage: "doc") { mostrarArchivos = true }
                    #if DEBUG
                    if config.evidenciaDePrueba {
                        Button("Imagen de prueba") { Task { await agregarImagen(Self.imagenDePrueba()) } }
                    }
                    #endif
                } label: {
                    VStack(spacing: 8) {
                        Symbol("photo.badge.plus", size: 24, color: Theme.textSlate)
                        Text(verbatim: "Agregar evidencia (quedan \(restantes))").ofraude(13, color: Theme.textSlate)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .ofraudeCard(radius: 8)
                }
                .accessibilityLabel("Agregar evidencia")
                .accessibilityIdentifier("reporte.evidencia.agregar")
            }
            if procesando {
                ProgressView("Quitando metadatos…").tint(Theme.accent)
            }
            FieldError(mensaje: error)
            Text("Máximo 3 archivos. Quitamos la ubicación de las fotos antes de guardarlas.")
                .ofraude(12, color: Theme.textMuted)
        }
        .photosPicker(isPresented: $mostrarFotos, selection: $seleccion, maxSelectionCount: max(restantes, 1), matching: .images)
        .onChange(of: seleccion) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await agregarFotos(items)
                seleccion = []
            }
        }
        .fullScreenCover(isPresented: $mostrarCamara) {
            CameraPicker { datos in Task { await agregarImagen(datos) } }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $mostrarArchivos, allowedContentTypes: [.pdf]) { resultado in
            Task { await agregarPDF(resultado) }
        }
    }

    private func agregarFotos(_ items: [PhotosPickerItem]) async {
        for item in items.prefix(restantes) {
            guard let datos = try? await item.loadTransferable(type: Data.self) else {
                error = "No se pudo leer una de las fotos."
                continue
            }
            await agregarImagen(datos)
        }
    }

    private func agregarImagen(_ datos: Data) async {
        procesando = true
        defer { procesando = false }
        do {
            // Fuera del hilo principal: reducir y recodificar una foto grande tarda.
            let limpia = try await Task.detached(priority: .userInitiated) {
                try ProcesadorEvidencia.limpiarImagen(datos)
            }.value
            adjuntos.append(try reports.archivos.guardarTemporal(limpia, tipo: "image/jpeg"))
            error = nil
        } catch ErrorEvidencia.muyGrande {
            error = "La imagen pesa demasiado (máximo 5 MB después de reducirla)."
        } catch {
            self.error = "Ese archivo no es una imagen válida."
        }
    }

    private func agregarPDF(_ resultado: Result<URL, Error>) async {
        guard case .success(let url) = resultado else { return }
        guard url.startAccessingSecurityScopedResource() else {
            error = "No se pudo abrir el archivo."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let datos = try Data(contentsOf: url)
            try ProcesadorEvidencia.validarPDF(datos)
            adjuntos.append(try reports.archivos.guardarTemporal(datos, tipo: "application/pdf"))
            error = nil
        } catch ErrorEvidencia.muyGrande {
            error = "El PDF pesa más de 10 MB."
        } catch {
            self.error = "Ese archivo no es un PDF válido."
        }
    }

    #if DEBUG
    /// Solo para XCUITest: el selector de fotos corre fuera de la app y no se puede automatizar.
    static func imagenDePrueba() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).jpegData(withCompressionQuality: 0.9) { contexto in
            UIColor.orange.setFill()
            contexto.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
    }
    #endif
}

/// Miniatura tocable (abre el visor) con botón opcional para quitarla.
struct MiniaturaEvidencia: View {
    enum Fuente: Hashable {
        case guardada(Evidencia)
        case nueva(Adjunto)
    }

    let fuente: Fuente
    var quitar: (() -> Void)?

    @Environment(ReportsStore.self) private var reports
    @State private var imagen: UIImage?
    @State private var verCompleta = false

    private var esPDF: Bool {
        switch fuente {
        case .guardada(let e): return e.esPDF
        case .nueva(let a): return a.esPDF
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button { verCompleta = true } label: {
                Group {
                    if esPDF {
                        Symbol("doc.richtext", size: 32, color: Theme.textSlate)
                    } else if let imagen {
                        Image(uiImage: imagen).resizable().scaledToFill()
                    } else {
                        ProgressView().tint(Theme.accent)
                    }
                }
                .frame(width: 96, height: 96)
                .clipped()
                .ofraudeCard(radius: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(esPDF ? "Evidencia PDF" : "Foto de evidencia")

            if let quitar {
                Button(action: quitar) { Symbol("xmark.circle.fill", size: 22, color: Theme.dangerText) }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel("Quitar evidencia")
            }
        }
        .task { if !esPDF { imagen = (await MiniaturaEvidencia.datos(de: fuente, reports: reports)).flatMap(UIImage.init(data:)) } }
        .sheet(isPresented: $verCompleta) { VisorEvidencia(fuente: fuente) }
    }

    static func datos(de fuente: Fuente, reports: ReportsStore) async -> Data? {
        switch fuente {
        case .guardada(let e): return try? await reports.datosEvidencia(e)
        case .nueva(let a): return try? reports.archivos.datos(de: a)
        }
    }
}

/// Evidencia a pantalla completa. Los PDF se muestran con PDFKit, que no ejecuta JavaScript.
struct VisorEvidencia: View {
    let fuente: MiniaturaEvidencia.Fuente

    @Environment(ReportsStore.self) private var reports
    @Environment(\.dismiss) private var dismiss
    @State private var datos: Data?

    var body: some View {
        NavigationStack {
            Group {
                if let datos, case .guardada(let e) = fuente, e.esPDF {
                    VistaPDF(datos: datos)
                } else if let datos, case .nueva(let a) = fuente, a.esPDF {
                    VistaPDF(datos: datos)
                } else if let datos, let imagen = UIImage(data: datos) {
                    Image(uiImage: imagen).resizable().scaledToFit()
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ofraudeScreen()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
            .task { datos = await MiniaturaEvidencia.datos(de: fuente, reports: reports) }
        }
    }
}

struct VistaPDF: UIViewRepresentable {
    let datos: Data

    func makeUIView(context: Context) -> PDFView {
        let vista = PDFView()
        vista.autoScales = true
        vista.document = PDFDocument(data: datos)
        return vista
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
```

- [ ] **Paso 5: Usarlo.** En `ReportView`, reemplazar el bloque "EVIDENCIA (OPCIONAL)" (etiqueta + `evidenceBox`) por `EvidenceEditor(adjuntos: $borrador.adjuntos, existentes: existentes, quitar: $borrador.quitarEvidencias)` precedido de `FieldLabel("EVIDENCIA (OPCIONAL)")`, y borrar `evidenceBox`. En `ReportDetailView.contenido(_:)`, después de `PersonaAfectadaView`:

```swift
            if !r.evidencias.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Evidencia").ofraude(20, .bold, color: Theme.textPrimary).accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(r.evidencias) { MiniaturaEvidencia(fuente: .guardada($0)) }
                    }
                }
            } else if r.totalEvidencias > 0 {
                Text(verbatim: "Incluye \(r.totalEvidencias) archivo(s) de evidencia revisados por moderación.")
                    .ofraude(13, color: Theme.textMuted)
            }
```

- [ ] **Paso 6: Temporales y permiso de cámara.** En `Dependencies.crear`, después de crear `archivos`: `try? archivos.limpiarTemporales()` (evidencia elegida y nunca enviada no se queda en disco). En `project.pbxproj`, en Debug y Release del target, agregar:

```
				INFOPLIST_KEY_NSCameraUsageDescription = "Se necesita la cámara para tomar evidencia del fraude";
```

- [ ] **Paso 7: Pruebas** — Run: `UI` (clase `FlujoReporteUITests`) → verde. Manual en el simulador: "Elegir de la galería" con una foto de ejemplo; aparece la miniatura; enviar; en el detalle (como autor) se ve la evidencia; como otra cuenta, solo "Incluye 1 archivo(s)…". En un iPhone real (si Alex tiene uno conectado): "Tomar foto".

- [ ] **Paso 8: Commit**

```bash
git add PrototipoApp PrototipoApp.xcodeproj/project.pbxproj PrototipoAppUITests
git commit -m "feat: evidencia con galería, cámara y PDF sin metadatos de ubicación"
```

**Criterios de aceptación:** máximo 3 archivos; quitar funciona antes y después de enviar (al editar); las fotos guardadas no tienen GPS (lo prueba S6); la evidencia solo la ven autor y staff.
**Dependencias:** F9, F5, S6. **Esfuerzo:** M. **Riesgo:** medio (PhotosPicker no se automatiza; ver sección 10).

### Tarea F11: Perfil — Mis reportes, Guardados, editar y eliminar

**Objetivo:** Perfil muestra el alias, el avatar, los reportes propios con su estado y los guardados reales; "Editar" abre el formulario (solo antes de validar), "Eliminar" pide confirmación y borra de verdad; quitar de guardados persiste; Ajustes muestra el conteo real.

**Archivos:**
- Modificar: `PrototipoApp/Views/Tabs/ProfileView.swift` (todo el archivo)
- Modificar: `PrototipoApp/Views/Account/SettingsView.swift:44-50` (conteo e identificador `ajustes.guardados`)
- Borrar: `PrototipoApp/Model/Report.swift`
- Test: `PrototipoAppUITests/PerfilUITests.swift` (crear)

**Interfaces:**
- Consume: D9 (`ReportsStore.mios`, `guardados`, `cargarMios`, `cargarGuardados`, `eliminar`, `marcarGuardado`), F4 (`AvatarView`), F9 (`Route.editReport` → `ReportView(modo: .editar)`).
- Produce: identificadores `perfil.editar`, `perfil.enviados`, `perfil.segmento.misReportes`, `perfil.segmento.guardados`, `perfil.tarjeta.<id>`, `perfil.opciones.<id>`, `perfil.quitarGuardado.<id>`, `ajustes.guardados`.

- [ ] **Paso 1: Pruebas que fallan** — `PrototipoAppUITests/PerfilUITests.swift`:

```swift
//
//  PerfilUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class PerfilUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testMisReportesYGuardadosVienenDeLosDatos() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        XCTAssertTrue(app.elemento(contiene: "Descuento falso de laptop en tienda clonada").waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["perfil.enviados"].label.contains("3"))
        capturar(app, "08-perfil")
        app.buttons["perfil.segmento.guardados"].tap()
        XCTAssertTrue(app.buttons["perfil.quitarGuardado.101"].waitForExistence(timeout: 5))
        app.buttons["perfil.quitarGuardado.101"].tap()
        XCTAssertTrue(app.buttons["perfil.quitarGuardado.101"].waitForNonExistence(timeout: 5))
        app.terminate()
        let otraVez = XCUIApplication.zeroScam(reiniciar: false)
        otraVez.launch()
        otraVez.tabBars.buttons["Perfil"].tap()
        otraVez.buttons["perfil.segmento.guardados"].tap()
        XCTAssertTrue(otraVez.buttons["perfil.quitarGuardado.102"].waitForExistence(timeout: 5))
        XCTAssertFalse(otraVez.buttons["perfil.quitarGuardado.101"].exists)
    }

    @MainActor
    func testEditarSoloAntesDeValidar() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.opciones.122"].tocar(en: app)
        app.buttons["Editar"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Este reporte ya fue revisado y no se puede editar."].waitForExistence(timeout: 5))
        app.alerts.buttons["Aceptar"].tap()
        app.buttons["perfil.opciones.123"].tocar(en: app)
        app.buttons["Editar"].tap()
        let titulo = app.textFields["reporte.titulo"]
        XCTAssertTrue(titulo.waitForExistence(timeout: 5))
        titulo.reemplazar("Llamada de supuesto banco pidiendo el código SMS")
        app.buttons["Listo"].firstMatch.tap()
        app.buttons["reporte.enviar"].tocar(en: app)
        XCTAssertTrue(app.elemento(contiene: "Llamada de supuesto banco pidiendo el código SMS").waitForExistence(timeout: 5))
    }

    @MainActor
    func testEliminarPideConfirmacion() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.opciones.123"].tocar(en: app)
        app.buttons["Eliminar"].tap()
        app.alerts.buttons["Cancelar"].tap()
        XCTAssertTrue(app.buttons["perfil.tarjeta.123"].exists)
        app.buttons["perfil.opciones.123"].tocar(en: app)
        app.buttons["Eliminar"].tap()
        app.alerts.buttons["Eliminar"].tap()
        XCTAssertTrue(app.buttons["perfil.tarjeta.123"].waitForNonExistence(timeout: 5))
    }
}
```

- [ ] **Paso 2: Ver que fallan** — Run: `UI` (clase `PerfilUITests`) → FAIL: no existe `perfil.quitarGuardado.101`.

- [ ] **Paso 3: Reescribir `Views/Tabs/ProfileView.swift`**

```swift
//
//  ProfileView.swift
//  PrototipoApp
//
//  Reemplaza: escena `profile-vc` / ProfileViewController.
//  - Mis reportes y Guardados vienen del backend (antes tarjetas fijas que reaparecían).
//  - El menú Editar / Eliminar / Cancelar es un `confirmationDialog`; Editar solo antes de que se
//    valide el reporte y Eliminar pide confirmación porque no se puede deshacer.
//  - El aro del avatar es un `strokeBorder` negro, como en el original.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports

    @State private var optionsFor: Reporte?
    @State private var paraEliminar: Reporte?
    @State private var aviso: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(background: Theme.card, titleSize: 16, titleColor: Theme.textPrimary) {
                NavigationLink(value: Route.settings) {
                    Symbol("gearshape.fill", size: 24, color: Theme.textPrimary)
                }
                .accessibilityLabel("Ajustes")
                .accessibilityIdentifier("perfil.ajustes")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    avatar
                    Text(verbatim: session.usuario.map { "@\($0.alias)" } ?? "")
                        .ofraude(28, .bold, color: Theme.textPrimary)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 16) {
                        statCard("REPORTES ENVIADOS", reports.mios.valor.map { "\($0.count)" } ?? "–", labelColor: Theme.textSlate)
                            .accessibilityIdentifier("perfil.enviados")
                        statCard("PERSONAS AYUDADAS",
                                 reports.mios.valor.map { Formato.miles($0.reduce(0) { $0 + $1.confirmaciones }) } ?? "–",
                                 labelColor: Theme.accent)
                    }

                    NavigationLink(value: Route.editProfile) { Text("EDITAR PERFIL") }
                        .buttonStyle(OfraudeButtonStyle(background: Theme.card, size: 15, weight: .semibold, radius: 0, height: 48))
                        .accessibilityIdentifier("perfil.editar")

                    segments

                    if appState.profileSegment == .misReportes {
                        CargaView(carga: reports.mios, esVacio: \.isEmpty,
                                  vacio: EstadoVacio(icono: "megaphone", titulo: "Aún no has reportado",
                                                     mensaje: "Cuando envíes un reporte aparecerá aquí con su estado."),
                                  reintentar: { await reports.cargarMios() }) { lista in
                            ForEach(lista) { r in
                                reportCard(r, titleSize: 20,
                                           header: "\(r.estado.titulo) · \(Formato.relativo(r.fechaCreacion).uppercased())",
                                           headerColor: r.estado.color, icon: "ellipsis.circle", iconColor: Theme.textSlate,
                                           iconLabel: "Opciones del reporte", iconId: "perfil.opciones.\(r.id)") {
                                    optionsFor = r
                                }
                            }
                        }
                    } else {
                        CargaView(carga: reports.guardados, esVacio: \.isEmpty,
                                  vacio: EstadoVacio(icono: "bookmark", titulo: "Sin guardados",
                                                     mensaje: "Toca el marcador de un reporte para guardarlo aquí."),
                                  reintentar: { await reports.cargarGuardados() }) { lista in
                            ForEach(lista) { r in
                                reportCard(r, titleSize: 18,
                                           header: "\(r.nivelRiesgo.titulo) · \(Formato.relativo(r.fechaCreacion))",
                                           headerColor: r.nivelRiesgo.color, icon: "bookmark.fill", iconColor: Theme.accent,
                                           iconLabel: "Quitar de guardados", iconId: "perfil.quitarGuardado.\(r.id)") {
                                    Task { await quitarGuardado(r) }
                                }
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
        .task(id: reports.version) {
            await reports.cargarMios()
            await reports.cargarGuardados()
        }
        .confirmationDialog(optionsFor?.titulo ?? "", isPresented: Binding(get: { optionsFor != nil }, set: { if !$0 { optionsFor = nil } }),
                            titleVisibility: .visible, presenting: optionsFor) { r in
            Button("Editar") {
                if r.estado.permiteEdicion {
                    appState.push(.editReport(r.id))
                } else {
                    aviso = "Este reporte ya fue revisado y no se puede editar."
                }
            }
            Button("Eliminar", role: .destructive) { paraEliminar = r }
            Button("Cancelar", role: .cancel) { }
        }
        .alert("¿Eliminar este reporte?", isPresented: Binding(get: { paraEliminar != nil }, set: { if !$0 { paraEliminar = nil } }),
               presenting: paraEliminar) { r in
            Button("Eliminar", role: .destructive) { Task { await eliminar(r) } }
            Button("Cancelar", role: .cancel) { }
        } message: { r in
            Text(r.estado.esPublico ? "Dejará de ser visible para la comunidad. No se puede deshacer."
                                    : "Se borrará junto con su evidencia. No se puede deshacer.")
        }
        .alert("Aviso", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("Aceptar", role: .cancel) { }
        } message: {
            Text(aviso ?? "")
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(usuario: session.usuario, tamano: 128, fondo: Theme.card)
                .overlay(Circle().strokeBorder(Theme.defaultBorder, lineWidth: 4))
            NavigationLink(value: Route.editProfile) {
                Symbol("pencil", size: 16, color: Theme.background)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent, in: Circle())
            }
            .accessibilityLabel("Cambiar foto de perfil")
            // El storyboard mete la insignia 2 pt hacia dentro del borde del avatar.
            .padding(.bottom, 2)
            .padding(.trailing, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func statCard(_ title: String, _ value: String, labelColor: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).ofraude(12, color: labelColor)
            Text(value).ofraude(22, .bold, color: Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 90)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var segments: some View {
        HStack(spacing: 24) {
            segmentButton("MIS REPORTES", .misReportes, id: "perfil.segmento.misReportes")
            segmentButton("GUARDADOS", .guardados, id: "perfil.segmento.guardados")
            Spacer(minLength: 0)
        }
    }

    private func segmentButton(_ title: String, _ segment: ProfileSegment, id: String) -> some View {
        Button {
            appState.profileSegment = segment
        } label: {
            Text(title).ofraude(15, .semibold, color: appState.profileSegment == segment ? Theme.textPrimary : Theme.textSlate)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(appState.profileSegment == segment ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    /// Tarjeta tocable (abre el detalle) con un botón de 24 pt arriba a la derecha.
    private func reportCard(_ r: Reporte, titleSize: CGFloat, header: String, headerColor: Color, icon: String,
                            iconColor: Color, iconLabel: String, iconId: String, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: Route.reportDetail(r.id)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(header).ofraude(12, .bold, color: headerColor)
                    Text(r.titulo).ofraude(titleSize, .semibold, color: Theme.textPrimary)
                    Text(r.descripcion).ofraude(16, color: Theme.textSlate).lineLimit(2)
                    if r.estado.esPublico {
                        HStack(spacing: 12) {
                            Label(Formato.conteoCorto(r.confirmaciones), systemImage: "person.2.fill")
                            Label("\(r.comentarios)", systemImage: "bubble.left.fill")
                        }
                        .ofraudeFont(13, .semibold)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("\(r.confirmaciones) confirmaciones, \(r.comentarios) comentarios")
                    }
                }
                .padding(.leading, 21)
                .padding(.trailing, 45)
                .padding(.vertical, 21)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("perfil.tarjeta.\(r.id)")

            Button(action: action) {
                Symbol(icon, size: 24, color: iconColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(iconLabel)
            .accessibilityIdentifier(iconId)
            .padding(.top, 21)
            .padding(.trailing, 21)
        }
    }

    private func quitarGuardado(_ r: Reporte) async {
        do { try await reports.marcarGuardado(id: r.id, false) }
        catch { aviso = error.mensajeUsuario }
    }

    private func eliminar(_ r: Reporte) async {
        do { try await reports.eliminar(id: r.id) }
        catch { aviso = error.mensajeUsuario }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .entornoDePrueba()
}
```

- [ ] **Paso 4: Ajustes.** En `SettingsView` agregar `@Environment(ReportsStore.self) private var reports`; la fila pasa a `rowLabel("Reportes Guardados  (\(reports.guardados.valor?.count ?? 0))", height: 47)` con `.accessibilityIdentifier("ajustes.guardados")` en el botón, y al final del `body` `.task { await reports.cargarGuardados() }`.

- [ ] **Paso 5: Borrar el modelo viejo.** `git rm PrototipoApp/Model/Report.swift`. Comprobar: `grep -rn "Report\.sample\|: Report)" PrototipoApp` sin resultados.

- [ ] **Paso 6: Pruebas** — Run: `UI` (clase `PerfilUITests`) → 3 tests en verde; `BUILD` en verde.

- [ ] **Paso 7: Commit**

```bash
git add -A PrototipoApp PrototipoAppUITests
git commit -m "feat: perfil con mis reportes, guardados, editar y eliminar reales"
```

**Criterios de aceptación:** los números de Perfil y de Ajustes salen de los datos; eliminar y quitar guardado sobreviven al reinicio; Editar en un reporte validado explica por qué no se puede.
**Dependencias:** F9, F4, V1. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea F12: Búsqueda con filtros reales

**Objetivo:** buscar por texto (sin importar acentos ni mayúsculas), por chips, por categoría y por riesgo mínimo; las categorías muestran conteos y riesgo reales; estados de carga, vacío y error.

**Archivos:**
- Modificar: `PrototipoApp/Views/Tabs/SearchView.swift` (todo el archivo)
- Test: `PrototipoAppUITests/BusquedaUITests.swift` (crear), `PrototipoAppUITests/NavegacionUITests.swift`

**Interfaces:**
- Consume: D9 (`ReportsStore.buscar`, `resultados`, `cargarCategorias`, `categorias`, `version`), D10 (`AppState.pendingSearch`), V1 (`ChipFiltro`, `ChipEtiqueta`, `CargaView`).
- Produce: identificadores `buscar.campo`, `buscar.chip.<n>` (0–3), `buscar.riesgo`, `buscar.limpiar`, `buscar.categoria.<tipo>`, `buscar.resultado.<id>`.

- [ ] **Paso 1: Pruebas que fallan** — `PrototipoAppUITests/BusquedaUITests.swift`:

```swift
//
//  BusquedaUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class BusquedaUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testBuscarPorTextoChipYRiesgo() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Buscar"].tap()
        app.textFields["buscar.campo"].escribir("BANCO")
        XCTAssertTrue(app.buttons["buscar.resultado.108"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["buscar.resultado.101"].exists)
        capturar(app, "09-buscar")
        app.buttons["buscar.limpiar"].tap()
        app.buttons["buscar.chip.2"].tap()   // #SorteoFalso
        XCTAssertTrue(app.buttons["buscar.resultado.102"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["buscar.resultado.114"].exists)
        app.buttons["buscar.riesgo"].tap()
        app.buttons["ALTO o más"].tap()
        XCTAssertTrue(app.buttons["buscar.resultado.114"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testSinResultadosMuestraElEstadoVacio() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Buscar"].tap()
        app.textFields["buscar.campo"].escribir("zzzz")
        XCTAssertTrue(app.elemento(contiene: "Sin resultados").waitForExistence(timeout: 5))
    }
}
```

Y en `NavegacionUITests`:

```swift
    @MainActor
    func testCategoriaDeInicioFiltraBuscar() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.categoria.ofertaFalsa"].tocar(en: app)
        XCTAssertTrue(app.buttons["buscar.resultado.101"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["buscar.resultado.105"].exists)
    }
```

- [ ] **Paso 2: Ver que fallan** — Run: `UI` (clase `BusquedaUITests`) → FAIL: no existe `buscar.resultado.108`.

- [ ] **Paso 3: Reescribir `Views/Tabs/SearchView.swift`**

```swift
//
//  SearchView.swift
//  PrototipoApp
//
//  Reemplaza: escena `search-vc` / SearchViewController.
//  Antes nada filtraba y las categorías abrían un detalle fijo. Ahora el texto, los chips, las
//  categorías y el riesgo arman un `FiltroBusqueda` que se manda al backend (solo reportes
//  validados). Recibe la búsqueda que deja Inicio en `AppState.pendingSearch`.
//

import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(ReportsStore.self) private var reports
    @State private var filtro = FiltroBusqueda()

    /// Los 4 chips del storyboard, ahora tocables.
    private enum Chip: Int, CaseIterable {
        case descuentos, tiendaClonada, sorteoFalso, mercadoLibre

        var titulo: String {
            switch self {
            case .descuentos: "#Descuentos"
            case .tiendaClonada: "#TiendaClonada"
            case .sorteoFalso: "#SorteoFalso"
            case .mercadoLibre: "#MercadoLibre"
            }
        }

        func activo(en f: FiltroBusqueda) -> Bool {
            switch self {
            case .descuentos: FiltroBusqueda.normalizar(f.texto) == "descuento"
            case .tiendaClonada: f.tipos == [.tiendaClonada]
            case .sorteoFalso: f.tipos == [.sorteoFalso]
            case .mercadoLibre: FiltroBusqueda.normalizar(f.texto) == "mercado libre"
            }
        }

        func alternar(_ f: inout FiltroBusqueda) {
            let estaba = activo(en: f)
            switch self {
            case .descuentos: f.texto = estaba ? "" : "descuento"
            case .tiendaClonada: f.tipos = estaba ? [] : [.tiendaClonada]
            case .sorteoFalso: f.tipos = estaba ? [] : [.sorteoFalso]
            case .mercadoLibre: f.texto = estaba ? "" : "mercado libre"
            }
        }
    }

    private struct Clave: Hashable {
        let filtro: FiltroBusqueda
        let version: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(background: Theme.card) {
                Symbol("checkmark.seal.fill", size: 24, color: Theme.accent).accessibilityHidden(true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Buscar Reportes").ofraude(24, .bold, color: Theme.textPrimary)
                    OfraudeTextField(placeholder: "Ej. WhatsApp, Banco, Phishing...", text: $filtro.texto, maximo: 100,
                                     identificador: "buscar.campo")
                        .submitLabel(.search)

                    // Cada fila del storyboard tiene 2 chips que llenan el ancho ("fillProportionally").
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach([[Chip.descuentos, .tiendaClonada], [.sorteoFalso, .mercadoLibre]], id: \.self) { fila in
                            HStack(spacing: 8) {
                                ForEach(Array(fila.enumerated()), id: \.offset) { index, chip in
                                    ChipFiltro(titulo: chip.titulo, activo: chip.activo(en: filtro),
                                               identificador: "buscar.chip.\(chip.rawValue)") { chip.alternar(&filtro) }
                                    if index < fila.count - 1 { Spacer(minLength: 8) }
                                }
                            }
                        }
                    }

                    Menu {
                        Button("Todos los riesgos") { filtro.riesgoMinimo = nil }
                        ForEach(NivelRiesgo.asignables, id: \.self) { nivel in
                            Button("\(nivel.titulo) o más") { filtro.riesgoMinimo = nivel }
                        }
                    } label: {
                        ChipEtiqueta(titulo: "Riesgo: \(filtro.riesgoMinimo.map { "\($0.titulo) o más" } ?? "todos") ▾",
                                     activo: filtro.riesgoMinimo != nil)
                    }
                    .accessibilityIdentifier("buscar.riesgo")

                    if filtro.estaVacio { categorias } else { resultados }
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
        .onAppear(perform: tomarPendiente)
        .onChange(of: appState.pendingSearch) { tomarPendiente() }
        // Espera 300 ms a que la persona deje de escribir; `.task(id:)` cancela la búsqueda anterior.
        .task(id: Clave(filtro: filtro, version: reports.version)) {
            if filtro.estaVacio {
                await reports.cargarCategorias()
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await reports.buscar(filtro)
        }
    }

    private var categorias: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("CATEGORÍAS PRINCIPALES").ofraude(18, .bold, color: Theme.textPrimary).accessibilityAddTraits(.isHeader)
            CargaView(carga: reports.categorias, reintentar: { await reports.cargarCategorias() }) { lista in
                ForEach(lista) { c in
                    Button { filtro = FiltroBusqueda(tipos: [c.tipo]) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: c.total == 0 ? "SIN REPORTES" : "\(c.riesgoMaximo.titulo) · \(c.total) reporte\(c.total == 1 ? "" : "s")")
                                .ofraude(12, .bold, color: c.total == 0 ? Theme.textSlate : c.riesgoMaximo.color)
                            Text(c.tipo.categoria).ofraude(20, .bold, color: Theme.textPrimary)
                            Text(c.tipo.resumen).ofraude(14, color: Theme.textSlate)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ofraudeCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Muestra los reportes de esta categoría")
                    .accessibilityIdentifier("buscar.categoria.\(c.tipo)")
                }
            }
        }
    }

    private var resultados: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(verbatim: "RESULTADOS\(reports.resultados.valor.map { " (\($0.count))" } ?? "")")
                    .ofraude(18, .bold, color: Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { filtro = FiltroBusqueda() } label: {
                    Text("Limpiar filtros").ofraude(13, .semibold, color: Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("buscar.limpiar")
            }
            CargaView(carga: reports.resultados, esVacio: \.isEmpty,
                      vacio: EstadoVacio(icono: "magnifyingglass", titulo: "Sin resultados",
                                         mensaje: "No encontramos reportes validados con esos filtros."),
                      reintentar: { await reports.buscar(filtro) }) { lista in
                ForEach(lista) { r in
                    NavigationLink(value: Route.reportDetail(r.id)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: "\(r.nivelRiesgo.titulo) · \(Formato.relativo(r.fechaCreacion))")
                                .ofraude(12, .bold, color: r.nivelRiesgo.color)
                            Text(r.titulo).ofraude(20, .bold, color: Theme.textPrimary)
                            Text(r.descripcion).ofraude(14, color: Theme.textSlate).lineLimit(2)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ofraudeCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("buscar.resultado.\(r.id)")
                }
            }
        }
    }

    private func tomarPendiente() {
        guard let pendiente = appState.pendingSearch else { return }
        filtro = pendiente
        appState.pendingSearch = nil
    }
}

#Preview {
    NavigationStack { SearchView() }
        .entornoDePrueba()
}
```

- [ ] **Paso 4: Pruebas** — Run: `UI` (clases `BusquedaUITests` y `NavegacionUITests`) → verde.

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp/Views/Tabs/SearchView.swift PrototipoAppUITests
git commit -m "feat: búsqueda con texto, chips, categorías y riesgo"
```

**Criterios de aceptación:** "BANCO", "banco" y "Banco" dan lo mismo; las categorías de Inicio llegan filtradas; sin resultados muestra el estado vacío con "Limpiar filtros".
**Dependencias:** D10, V1. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea F13: Estadísticas de la comunidad calculadas

**Objetivo:** las 4 cifras salen de los reportes públicos: personas ayudadas (confirmaciones + guardados), reportes verificados, estafas detenidas (canalizados) y zonas cubiertas (ciudades distintas).

**Archivos:**
- Modificar: `PrototipoApp/Views/Learn/CommunityStatsView.swift` (todo el archivo)
- Test: `PrototipoAppUITests/NavegacionUITests.swift`

**Interfaces:**
- Consume: D9 (`ReportsStore.estadisticas`, `cargarEstadisticas`), D6 (regla del cálculo, probada en `estadisticasSeCalculanDeLosPublicos`).
- Produce: nada nuevo.

- [ ] **Paso 1: Prueba que falla** — agregar a `NavegacionUITests`:

```swift
    @MainActor
    func testEstadisticasSeCalculan() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.estadisticas"].tocar(en: app)
        let verificados = app.elemento(contiene: "REPORTES VERIFICADOS")
        XCTAssertTrue(verificados.waitForExistence(timeout: 5))
        XCTAssertTrue(verificados.label.contains("17"))
        XCTAssertTrue(app.elemento(contiene: "ESTAFAS DETENIDAS").label.contains("4"))
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` → FAIL (las cifras actuales son fijas: 1,204 y 892).

- [ ] **Paso 3: Reescribir `Views/Learn/CommunityStatsView.swift`**

```swift
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
                Text("El impacto colectivo de 0Fraude en números, calculado con los reportes validados de la comunidad.")
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
```

- [ ] **Paso 4: Pruebas** — Run: `UI` → verde.

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp/Views/Learn/CommunityStatsView.swift PrototipoAppUITests
git commit -m "feat: estadísticas calculadas con los reportes públicos"
```

**Criterios de aceptación:** con la semilla: 5,362 / 17 / 4 / 10; al validar un reporte (F15) las cifras cambian.
**Dependencias:** D10, V1. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea F14: Guía con tres artículos

**Objetivo:** cada capítulo de la Guía abre su propio artículo (antes los tres abrían el mismo).

**Archivos:**
- Crear: `PrototipoApp/Model/Articulo.swift`
- Modificar: `PrototipoApp/App/AppState.swift` (`case article` → `case article(Articulo)`)
- Modificar: `PrototipoApp/Views/Route+Destination.swift` (`.article(let a): ArticleView(articulo: a)`)
- Modificar: `PrototipoApp/Views/Learn/SecurityGuideView.swift` (cada capítulo con su artículo)
- Modificar: `PrototipoApp/Views/Learn/ArticleView.swift` (todo el archivo)
- Test: `PrototipoAppTests/Model/ArticuloTests.swift`, `PrototipoAppUITests/NavegacionUITests.swift`

**Interfaces:**
- Consume: D10.
- Produce: `enum Articulo: String, Hashable, CaseIterable` (`ofertasFalsas`, `contrasenas`, `respuesta`) con `etiqueta`, `titulo`, `intro`, `puntos`, `recuerda`; `ArticleView(articulo:)`; identificadores `guia.capitulo.<n>` (1–3).

- [ ] **Paso 1: Pruebas que fallan** — `PrototipoAppTests/Model/ArticuloTests.swift`:

```swift
//
//  ArticuloTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct ArticuloTests {
    @Test func tresArticulosDistintosConCuatroPuntos() {
        #expect(Set(Articulo.allCases.map(\.titulo)).count == 3)
        #expect(Articulo.allCases.allSatisfy { $0.puntos.count == 4 && !$0.recuerda.isEmpty })
    }
}
```

Y en `NavegacionUITests`:

```swift
    @MainActor
    func testCadaCapituloAbreSuArticulo() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.guia"].tocar(en: app)
        app.buttons["guia.capitulo.2"].tocar(en: app)
        XCTAssertTrue(app.staticTexts["Protegiendo tus contraseñas"].waitForExistence(timeout: 5))
    }
```

- [ ] **Paso 2: Ver que fallan** — Run: `UNIT` → FAIL `cannot find 'Articulo' in scope`.

- [ ] **Paso 3: Crear `Model/Articulo.swift`**

```swift
//
//  Articulo.swift
//  PrototipoApp
//
//  Los tres artículos de la Guía de seguridad. El primero conserva el texto del artículo
//  original del storyboard.
//

import Foundation

nonisolated enum Articulo: String, Hashable, CaseIterable, Sendable {
    case ofertasFalsas, contrasenas, respuesta

    var etiqueta: String {
        switch self {
        case .ofertasFalsas: "CAPÍTULO 01 · MANUAL OPERATIVO"
        case .contrasenas: "CAPÍTULO 02 · PROTOCOLO"
        case .respuesta: "CAPÍTULO 03 · MANUAL DE RESPUESTA"
        }
    }

    var titulo: String {
        switch self {
        case .ofertasFalsas: "Cómo identificar ofertas falsas"
        case .contrasenas: "Protegiendo tus contraseñas"
        case .respuesta: "Qué hacer tras un fraude"
        }
    }

    var intro: String {
        switch self {
        case .ofertasFalsas:
            "Los estafadores cambian de táctica constantemente, pero casi siempre buscan generar urgencia, miedo o una oportunidad demasiado buena para dejarla pasar. Reconocer esas señales a tiempo es tu primera línea de defensa."
        case .contrasenas:
            "La reutilización de contraseñas es el vector de ataque más común: cuando se filtra un sitio, los atacantes prueban esa misma contraseña en tu correo, tu banco y tus redes."
        case .respuesta:
            "Actuar en las primeras horas reduce el daño. Sigue estos pasos en orden y guarda todo lo que pueda servir como evidencia."
        }
    }

    var puntos: [String] {
        switch self {
        case .ofertasFalsas: [
            "Compara el precio con otras tiendas: un descuento de 70 % o más en productos nuevos casi siempre es falso.",
            "Revisa el dominio letra por letra: «n1ke-outlet» o «mercadolibre-ofertas.store» no son las tiendas oficiales.",
            "Desconfía de los contadores de «solo por hoy» y de las existencias que «se agotan» mientras miras.",
            "Paga con métodos que tengan protección al comprador; evita transferencias y depósitos en tiendas de conveniencia.",
        ]
        case .contrasenas: [
            "Usa una contraseña distinta en cada servicio; un gestor de contraseñas las recuerda por ti.",
            "Prefiere frases largas (más de 12 caracteres) a palabras cortas con símbolos.",
            "Activa la verificación en dos pasos en tu correo y tu banco: aunque roben tu contraseña, no podrán entrar.",
            "Nunca compartas códigos de verificación: ningún banco ni tienda te los pedirá por llamada o mensaje.",
        ]
        case .respuesta: [
            "Llama a tu banco para bloquear la tarjeta o la cuenta y pide la aclaración del cargo.",
            "Cambia las contraseñas de las cuentas afectadas y cierra las sesiones abiertas.",
            "Guarda capturas, correos, números y enlaces del fraude antes de que desaparezcan.",
            "Denuncia ante la autoridad que corresponda y repórtalo en 0Fraude para alertar a otros.",
        ]
        }
    }

    var recuerda: String {
        switch self {
        case .ofertasFalsas:
            "Ninguna institución legítima te pedirá tu contraseña completa o el código de tu tarjeta por teléfono, SMS o WhatsApp."
        case .contrasenas:
            "0Fraude guarda tu contraseña como un hash con sal: ni el equipo puede leerla."
        case .respuesta:
            "Al reportar en 0Fraude puedes adjuntar tus capturas: la app les quita la ubicación antes de guardarlas."
        }
    }
}
```

- [ ] **Paso 4: Ruta y vistas.** En `AppState.swift`: `case guide, article(Articulo), stats`. En `Route+Destination.swift`: `case .article(let articulo): ArticleView(articulo: articulo)`. En `SecurityGuideView`, `chapter(...)` recibe `articulo: Articulo` y `numero: Int`, usa `NavigationLink(value: Route.article(articulo))` y `.accessibilityIdentifier("guia.capitulo.\(numero)")`; las 3 llamadas pasan `.ofertasFalsas`/1, `.contrasenas`/2, `.respuesta`/3. `ArticleView`:

```swift
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
```

- [ ] **Paso 5: Pruebas** — Run: `UNIT` y `UI` (clase `NavegacionUITests`) → verde.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp PrototipoAppTests PrototipoAppUITests
git commit -m "feat: cada capítulo de la guía abre su propio artículo"
```

**Criterios de aceptación:** 3 artículos distintos; el primero conserva el texto original.
**Dependencias:** D10. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea F15: Moderación — estados del reporte (Administrador y Owner)

**Objetivo:** una cola de reportes por estado y una pantalla de revisión donde el staff mueve un reporte por RECIBIDO → EN_REVISION → VALIDADO/RECHAZADO → CANALIZADO, asigna el nivel de riesgo, escribe observaciones (obligatorias al rechazar) y el autor recibe la notificación.

**Archivos:**
- Crear: `PrototipoApp/Views/Admin/AdminQueueView.swift`
- Crear: `PrototipoApp/Views/Admin/AdminReviewView.swift`
- Modificar: `PrototipoApp/Views/Account/SettingsView.swift` (sección ADMINISTRACIÓN)
- Modificar: `PrototipoApp/Views/Route+Destination.swift` (`.adminQueue`, `.adminReview`)
- Test: `PrototipoAppUITests/ModeracionUITests.swift` (crear)

**Interfaces:**
- Consume: D9 (`AdminStore.cola`, `cargarCola`, `cambiarEstado`; `ReportsStore.detalle`, `historial`, `invalidar`), D7 (reglas), F5 (`SitioSospechosoView`, `EstadoReporteView`, `PersonaAfectadaView`), F10 (`MiniaturaEvidencia`), S3 (`Validador.moderacion`), V1.
- Produce: `AdminQueueView`, `AdminReviewView(id:)`; identificadores `ajustes.moderacion`, `moderacion.filtro.<titulo>`, `moderacion.reporte.<id>`, `revision.estado.<RAW>`, `revision.riesgo.<RAW>`, `revision.observaciones`, `revision.aplicar`; botón de confirmación "Cambiar estado".

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppUITests/ModeracionUITests.swift`:

```swift
//
//  ModeracionUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class ModeracionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testModerarValidaYElReporteSePublica() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar("admin@0fraude.mx", "Revisa#2026zs")
        app.moderar(id: 123, a: "EN_REVISION")
        app.moderar(id: 123, a: "VALIDADO", riesgo: "ALTO")
        capturar(app, "10-moderacion")
        app.salir()
        app.entrar()
        app.tabBars.buttons["Buscar"].tap()
        app.textFields["buscar.campo"].escribir("supuesto banco")
        XCTAssertTrue(app.buttons["buscar.resultado.123"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRechazarExigeMotivo() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar("admin@0fraude.mx", "Revisa#2026zs")
        app.abrirModeracion()
        app.buttons["moderacion.reporte.117"].tocar(en: app)
        app.buttons["revision.estado.RECHAZADO"].tocar(en: app)
        XCTAssertFalse(app.buttons["revision.aplicar"].isEnabled)
        app.textViews["revision.observaciones"].tocar(en: app)
        app.textViews["revision.observaciones"].typeText("El enlace ya no existe y no hay captura.")
        XCTAssertTrue(app.buttons["revision.aplicar"].isEnabled)
    }

    @MainActor
    func testUnUsuarioNoVeAdministracion() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.ajustes"].tap()
        XCTAssertFalse(app.buttons["ajustes.moderacion"].exists)
    }
}
```

Agregar a `PrototipoAppUITests/Soporte/Ayudantes.swift`, dentro de `extension XCUIApplication`:

```swift
    func abrirModeracion() {
        volverALaRaiz()
        tabBars.buttons["Perfil"].tap()
        buttons["perfil.ajustes"].tap()
        buttons["ajustes.moderacion"].tocar(en: self)
    }

    /// Lleva un reporte de la cola a otro estado (y riesgo, si se valida), confirmando el cambio.
    func moderar(id: Int64, a estado: String, riesgo: String? = nil) {
        if !buttons["moderacion.reporte.\(id)"].exists { abrirModeracion() }
        buttons["moderacion.filtro.TODOS"].tocar(en: self)
        buttons["moderacion.reporte.\(id)"].tocar(en: self)
        buttons["revision.estado.\(estado)"].tocar(en: self)
        if let riesgo { buttons["revision.riesgo.\(riesgo)"].tocar(en: self) }
        buttons["revision.aplicar"].tocar(en: self)
        buttons["Cambiar estado"].tap()
        XCTAssertTrue(buttons["moderacion.reporte.\(id)"].waitForExistence(timeout: 5))
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `ModeracionUITests`) → FAIL: no existe `ajustes.moderacion`.

- [ ] **Paso 3: Crear `Views/Admin/AdminQueueView.swift`**

```swift
//
//  AdminQueueView.swift
//  PrototipoApp
//
//  Cola de moderación (Administrador y Owner): los reportes por estado, los más viejos primero.
//  El servidor decide si quien la pide tiene permiso; aquí solo se muestra su respuesta.
//

import SwiftUI

struct AdminQueueView: View {
    @Environment(AdminStore.self) private var admin
    @Environment(ReportsStore.self) private var reports
    @State private var estado: EstadoReporte?
    @State private var todos = false

    private struct Filtro: Identifiable {
        let titulo: String
        let estado: EstadoReporte?
        let todos: Bool
        var id: String { titulo }
    }

    private let filtros = [
        Filtro(titulo: "PENDIENTES", estado: nil, todos: false),
        Filtro(titulo: "TODOS", estado: nil, todos: true),
    ] + EstadoReporte.allCases.map { Filtro(titulo: $0.titulo, estado: $0, todos: false) }

    private struct Clave: Hashable {
        let estado: EstadoReporte?
        let todos: Bool
        let version: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filtros) { f in
                            ChipFiltro(titulo: f.titulo, activo: estado == f.estado && todos == f.todos,
                                       identificador: "moderacion.filtro.\(f.titulo)") {
                                estado = f.estado
                                todos = f.todos
                            }
                        }
                    }
                }
                CargaView(carga: admin.cola, esVacio: \.isEmpty,
                          vacio: EstadoVacio(icono: "tray", titulo: "Nada por revisar", mensaje: "No hay reportes en este estado."),
                          reintentar: { await cargar() }) { lista in
                    ForEach(lista) { r in
                        NavigationLink(value: Route.adminReview(r.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Etiqueta(texto: r.estado.titulo, color: r.estado.color, fondo: r.estado.color.opacity(0.2))
                                    Spacer()
                                    Text(Formato.folio(r.id)).ofraude(12, color: Theme.textMuted)
                                }
                                Text(r.titulo).ofraude(17, .semibold, color: Theme.textPrimary)
                                Text(verbatim: "\(r.tipoVisible) · \(r.ciudad) · \(Formato.relativo(r.fechaCreacion)) · \(r.autor.nombre)")
                                    .ofraude(12, color: Theme.textSlate)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ofraudeCard(radius: 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("moderacion.reporte.\(r.id)")
                    }
                }
            }
            .padding(16)
        }
        .ofraudeScreen()
        .navigationTitle("Moderación")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Clave(estado: estado, todos: todos, version: reports.version)) { await cargar() }
    }

    /// "TODOS" pide cada estado; "PENDIENTES" (nil) son RECIBIDO y EN_REVISION.
    private func cargar() async {
        if todos {
            await admin.cargarColaCompleta()
        } else {
            await admin.cargarCola(estado: estado)
        }
    }
}
```

Agregar a `AdminStore` (D9) el método que usa "TODOS":

```swift
    /// Todos los estados, más viejos primero (para la demo y para el filtro "TODOS").
    func cargarColaCompleta() async {
        if cola.valor == nil { cola = .cargando }
        do {
            var todos: [Reporte] = []
            for estado in EstadoReporte.allCases {
                todos += try await ejecutar { try await backend.colaModeracion(estado: estado) }
            }
            cola = .listo(todos.sorted { $0.fechaCreacion < $1.fechaCreacion })
        } catch {
            cola = .error(error.mensajeUsuario)
        }
    }
```

- [ ] **Paso 4: Crear `Views/Admin/AdminReviewView.swift`**

```swift
//
//  AdminReviewView.swift
//  PrototipoApp
//
//  Revisión de un reporte: todo lo que el staff puede ver (persona afectada, evidencia,
//  historial) y el cambio de estado. Solo se ofrecen las transiciones válidas; el servidor las
//  vuelve a revisar, impide moderar lo propio y avisa al autor.
//

import SwiftUI

struct AdminReviewView: View {
    let id: Int64

    @Environment(AdminStore.self) private var admin
    @Environment(ReportsStore.self) private var reports
    @Environment(\.dismiss) private var dismiss
    @State private var carga: Carga<Reporte> = .cargando
    @State private var historial: [HistorialEstado] = []
    @State private var nuevo: EstadoReporte?
    @State private var riesgo: NivelRiesgo?
    @State private var observaciones = ""
    @State private var confirmar = false
    @State private var error: String?

    private var limpias: String { Sanitizador.texto(observaciones, maximo: 500, multilinea: true) }

    private var errores: [ErrorCampo] {
        guard let nuevo else { return [ErrorCampo(campo: .observaciones, mensaje: "Elige el nuevo estado.")] }
        return Validador.moderacion(nuevo: nuevo, riesgo: riesgo, observaciones: limpias)
    }

    var body: some View {
        ScrollView {
            CargaView(carga: carga, reintentar: cargar) { r in
                VStack(alignment: .leading, spacing: 20) {
                    Text(r.titulo).ofraude(22, .bold, color: Theme.textPrimary).accessibilityAddTraits(.isHeader)
                    Text(verbatim: "\(Formato.folio(r.id)) · \(r.tipoVisible) · \(r.ciudad) · Autor: \(r.autor.nombre)")
                        .ofraude(13, color: Theme.textSlate)
                    Text(r.descripcion).ofraude(15, color: Theme.textPrimary)
                    if r.sitio != nil || r.textoSospechoso != nil { SitioSospechosoView(reporte: r) }
                    if let persona = r.personaAfectada { PersonaAfectadaView(persona: persona) }
                    if !r.evidencias.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(r.evidencias) { MiniaturaEvidencia(fuente: .guardada($0)) }
                        }
                    }
                    EstadoReporteView(reporte: r, historial: historial)
                    if r.estado.siguientes.isEmpty {
                        AvisoBanner(texto: "Este reporte está en un estado final (\(r.estado.titulo)); ya no cambia.")
                    } else {
                        formulario(r)
                    }
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Revisión")
        .navigationBarTitleDisplayMode(.inline)
        .task { await cargar() }
        .confirmationDialog(nuevo.map { "¿Cambiar a \($0.titulo)?" } ?? "", isPresented: $confirmar, titleVisibility: .visible) {
            Button("Cambiar estado") { Task { await aplicar() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(nuevo == .validado ? "Será visible para toda la comunidad y se avisará al autor."
                 : nuevo == .canalizado ? "Se marcará como enviado a las autoridades y se avisará al autor."
                 : "Se avisará al autor.")
        }
    }

    private func formulario(_ r: Reporte) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CAMBIAR ESTADO").ofraude(13, .bold, color: Theme.accent)
            HStack(spacing: 8) {
                ForEach(r.estado.siguientes, id: \.self) { e in
                    ChipFiltro(titulo: e.titulo, activo: nuevo == e, identificador: "revision.estado.\(e.rawValue)") { nuevo = e }
                }
            }
            if nuevo == .validado {
                Text("NIVEL DE RIESGO").ofraude(13, .bold, color: Theme.accent)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(NivelRiesgo.asignables, id: \.self) { n in
                        ChipFiltro(titulo: n.titulo, activo: riesgo == n, identificador: "revision.riesgo.\(n.rawValue)") { riesgo = n }
                    }
                }
            }
            FieldLabel(nuevo == .rechazado ? "MOTIVO DEL RECHAZO (OBLIGATORIO)" : "OBSERVACIONES (OPCIONAL)")
            OfraudeTextEditor(placeholder: "Qué revisaste y por qué...", text: $observaciones, maximo: 500, altura: 100,
                              identificador: "revision.observaciones")
            if nuevo != nil { ResumenErrores(errores: errores.mensajes) }
            if let error { AvisoBanner(texto: error, tono: .error) }
            BotonAccion(titulo: "APLICAR CAMBIO", habilitado: errores.isEmpty, identificador: "revision.aplicar") {
                confirmar = true
            }
        }
        .padding(16)
        .ofraudeCard(radius: 8)
    }

    private func cargar() async {
        do {
            carga = .listo(try await reports.detalle(id: id))
            historial = (try? await reports.historial(id: id)) ?? []
        } catch {
            carga = .error(error.mensajeUsuario)
        }
    }

    private func aplicar() async {
        guard let nuevo else { return }
        do {
            _ = try await admin.cambiarEstado(id: id, a: nuevo, riesgo: riesgo, observaciones: limpias)
            reports.invalidar()
            dismiss()
        } catch {
            self.error = error.mensajeUsuario
        }
    }
}
```

- [ ] **Paso 5: Ajustes y rutas.** En `SettingsView` agregar `@Environment(SessionStore.self) private var session` y, antes del botón CERRAR SESIÓN:

```swift
                if session.usuario?.rol.esStaff == true {
                    section("ADMINISTRACIÓN") {
                        NavigationLink(value: Route.adminQueue) { rowLabel("Revisión de reportes", height: 47) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ajustes.moderacion")
                    }
                }
```

En `Route+Destination.swift`: `case .adminQueue: AdminQueueView()` y `case .adminReview(let id): AdminReviewView(id: id)` (fuera del grupo `EmptyView()`).

- [ ] **Paso 6: Pruebas** — Run: `UI` (clase `ModeracionUITests`) → 3 tests en verde; `UNIT` en verde.

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: cola de moderación y cambio de estado con historial y riesgo"
```

**Criterios de aceptación:** solo staff ve ADMINISTRACIÓN; solo se ofrecen transiciones válidas; validar exige riesgo; rechazar exige motivo; el reporte validado aparece en Buscar e Inicio (si es de riesgo alto); el autor ve "Equipo de moderación" en su historial.
**Dependencias:** F5, F10, D9, V1. **Esfuerzo:** L. **Riesgo:** medio.

### Tarea F16: Notificaciones

**Objetivo:** campana con contador en Inicio, lista de notificaciones (tocar marca como leída y abre el reporte), "Marcar leídas", y el switch Notificaciones de Ajustes que pide permiso y activa avisos del sistema sin detalles.

**Archivos:**
- Crear: `PrototipoApp/Views/Account/NotificationsView.swift`
- Modificar: `PrototipoApp/Views/Tabs/HomeView.swift` (campana en lugar del sello)
- Modificar: `PrototipoApp/Views/Tabs/MainTabView.swift` (carga al entrar y al volver a primer plano)
- Modificar: `PrototipoApp/Views/Account/SettingsView.swift` (switch real)
- Modificar: `PrototipoApp/App/NotificadorLocal.swift` (delegado para mostrar avisos con la app abierta)
- Modificar: `PrototipoApp/App/OFraudeApp.swift` (asignar el delegado)
- Modificar: `PrototipoApp/Views/Route+Destination.swift` (`.notifications`)
- Test: `PrototipoAppUITests/NotificacionesUITests.swift` (crear)

**Interfaces:**
- Consume: D9 (`NotificationsStore.lista`, `sinLeer`, `cargar(avisar:)`, `marcarLeidas`, `pedirPermiso`; `SessionStore.actualizarPreferencias`).
- Produce: `NotificationsView`; `DelegadoNotificaciones.compartido`; identificadores `inicio.notificaciones`, `notificaciones.fila.<id>`, `notificaciones.marcarLeidas`, `ajustes.notificaciones`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppUITests/NotificacionesUITests.swift`:

```swift
//
//  NotificacionesUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class NotificacionesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testLaCampanaCuentaYAbreElReporte() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        let campana = app.buttons["inicio.notificaciones"]
        XCTAssertTrue(campana.waitForExistence(timeout: 5))
        esperar(campana, etiqueta: "Notificaciones, 1 sin leer")
        campana.tap()
        capturar(app, "11-notificaciones")
        app.buttons["notificaciones.fila.502"].tap()
        XCTAssertTrue(app.elemento(contiene: "Descuento falso de laptop").waitForExistence(timeout: 5))
        app.volverALaRaiz()
        esperar(app.buttons["inicio.notificaciones"], etiqueta: "Notificaciones")
    }

    @MainActor
    func testElAutorRecibeLaNotificacionDeModeracion() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar("admin@0fraude.mx", "Revisa#2026zs")
        app.moderar(id: 123, a: "EN_REVISION")
        app.salir()
        app.entrar()
        esperar(app.buttons["inicio.notificaciones"], etiqueta: "Notificaciones, 2 sin leer")
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `NotificacionesUITests`) → FAIL: no existe `inicio.notificaciones`.

- [ ] **Paso 3: Crear `Views/Account/NotificationsView.swift`**

```swift
//
//  NotificationsView.swift
//  PrototipoApp
//
//  Notificaciones de la persona (tabla Notificacion_Alerta): cambios de estado de sus reportes y
//  comentarios nuevos. Tocar una la marca como leída y abre el reporte.
//

import SwiftUI

struct NotificationsView: View {
    @Environment(NotificationsStore.self) private var notifications
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CargaView(carga: notifications.lista, esVacio: \.isEmpty,
                          vacio: EstadoVacio(icono: "bell.slash", titulo: "Sin notificaciones",
                                             mensaje: "Aquí verás cuando cambie el estado de tus reportes o alguien los comente."),
                          reintentar: { await notifications.cargar(avisar: false) }) { lista in
                    ForEach(lista) { fila($0) }
                }
            }
            .padding(16)
        }
        .ofraudeScreen()
        .navigationTitle("Notificaciones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Marcar leídas") {
                    Task { await notifications.marcarLeidas(notifications.lista.valor?.filter { !$0.leida }.map(\.id) ?? []) }
                }
                .disabled(notifications.sinLeer == 0)
                .accessibilityIdentifier("notificaciones.marcarLeidas")
            }
        }
        .task { await notifications.cargar(avisar: false) }
    }

    private func fila(_ n: Notificacion) -> some View {
        Button {
            Task { await notifications.marcarLeidas([n.id]) }
            if let idReporte = n.idReporte { appState.push(.reportDetail(idReporte)) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(n.leida ? Color.clear : Theme.accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.mensaje).ofraude(14, n.leida ? .regular : .semibold, color: Theme.textPrimary)
                    Text(Formato.relativo(n.fecha)).ofraude(12, color: Theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ofraudeCard(radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(n.leida ? "Leída" : "Sin leer")
        .accessibilityIdentifier("notificaciones.fila.\(n.id)")
    }
}
```

- [ ] **Paso 4: Campana en `HomeView`.** Agregar `@Environment(NotificationsStore.self) private var notifications` y reemplazar el sello de la `TopBar`:

```swift
            TopBar(background: Theme.background) {
                NavigationLink(value: Route.notifications) {
                    Symbol("bell.fill", size: 24, color: Theme.accent)
                        .overlay(alignment: .topTrailing) {
                            if notifications.sinLeer > 0 {
                                Text(verbatim: "\(notifications.sinLeer)")
                                    .ofraude(10, .bold, color: Theme.background)
                                    .padding(4)
                                    .background(Theme.dangerText, in: Circle())
                                    .offset(x: 8, y: -8)
                            }
                        }
                }
                .accessibilityLabel(notifications.sinLeer > 0 ? "Notificaciones, \(notifications.sinLeer) sin leer" : "Notificaciones")
                .accessibilityIdentifier("inicio.notificaciones")
            }
```

- [ ] **Paso 5: Cargar al entrar y al volver.** En `MainTabView` agregar `@Environment(NotificationsStore.self) private var notifications`, `@Environment(SessionStore.self) private var session`, `@Environment(ReportsStore.self) private var reports`, `@Environment(\.scenePhase) private var scenePhase` y al `TabView`:

```swift
        .task(id: reports.version) { await cargarNotificaciones() }
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { Task { await cargarNotificaciones() } }
        }
```

```swift
    private func cargarNotificaciones() async {
        await notifications.cargar(avisar: session.usuario?.preferencias.notificaciones == true)
    }
```

- [ ] **Paso 6: Avisos con la app abierta.** Al final de `App/NotificadorLocal.swift`:

```swift
/// Muestra el aviso aunque la app esté en primer plano (por defecto iOS lo oculta).
final class DelegadoNotificaciones: NSObject, UNUserNotificationCenterDelegate {
    static let compartido = DelegadoNotificaciones()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
```

Y en `OFraudeApp.init()`, al final: `UNUserNotificationCenter.current().delegate = DelegadoNotificaciones.compartido` (agregar `import UserNotifications`).

- [ ] **Paso 7: Switch en `SettingsView`.** Agregar `@Environment(NotificationsStore.self) private var notifications` y `@State private var aviso: String?`; quitar `@State private var notifications = false`; el switch:

```swift
                    toggleRow("Notificaciones", isOn: Binding(
                        get: { session.usuario?.preferencias.notificaciones ?? false },
                        set: { nuevo in Task { await cambiarNotificaciones(nuevo) } }), id: "ajustes.notificaciones")
```

```swift
    /// Encender pide permiso a iOS; si la persona lo niega, el switch se queda apagado y se explica por qué.
    private func cambiarNotificaciones(_ activar: Bool) async {
        if activar, !(await notifications.pedirPermiso()) {
            aviso = "Activa las notificaciones de 0Fraude en Ajustes de iOS para recibir avisos."
            return
        }
        guard var p = session.usuario?.preferencias else { return }
        p.notificaciones = activar
        do { try await session.actualizarPreferencias(p) } catch { aviso = error.mensajeUsuario }
    }
```

`toggleRow` recibe `id: String` y agrega `.accessibilityIdentifier(id)`; agregar el `.alert("Aviso", …)` con `aviso` igual que en `ProfileView`.

- [ ] **Paso 8: Ruta.** `case .notifications: NotificationsView()` en `Route+Destination.swift`.

- [ ] **Paso 9: Pruebas** — Run: `UI` (clase `NotificacionesUITests`) → verde. Manual: activar Notificaciones (aparece el permiso de iOS en español), cerrar sesión, entrar como Administrador y mover un reporte de `usuario@0fraude.mx`, cerrar sesión y entrar como usuario: aparece el aviso del sistema "Tienes 1 notificación nueva." sin el título del reporte.

- [ ] **Paso 10: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: notificaciones con campana, lista y avisos del sistema sin detalles"
```

**Criterios de aceptación:** el número de la campana coincide con las no leídas; el aviso del sistema no revela el contenido; negar el permiso deja el switch apagado con explicación.
**Dependencias:** F4, F15 (para la segunda prueba), D9. **Esfuerzo:** M. **Riesgo:** medio (el diálogo de permiso del sistema no se automatiza; se revisa a mano).

### Tarea F17: Owner — usuarios, roles, analíticas y restablecer la demo

**Objetivo:** el Owner ve todas las cuentas, promueve o degrada Administradores, suspende o reactiva cuentas (con confirmación), ve las analíticas anónimas y puede restablecer los datos de la demo.

**Archivos:**
- Crear: `PrototipoApp/Views/Admin/OwnerUsersView.swift`
- Modificar: `PrototipoApp/Views/Account/SettingsView.swift` (fila "Usuarios y roles" en ADMINISTRACIÓN)
- Modificar: `PrototipoApp/Views/Route+Destination.swift` (`.ownerUsers`)
- Test: `PrototipoAppUITests/ModeracionUITests.swift`

**Interfaces:**
- Consume: D9 (`AdminStore.usuarios`, `analiticas`, `cargarUsuarios`, `cambiarRol`, `cambiarEstadoCuenta`, `restablecerDemo`; `SessionStore.expirar`), D10 (`appConfig`).
- Produce: `OwnerUsersView`; identificadores `ajustes.usuarios`, `usuarios.fila.<alias>`, `usuarios.restablecer`.

- [ ] **Paso 1: Prueba que falla** — agregar a `ModeracionUITests`:

```swift
    @MainActor
    func testOwnerSuspendeYLaCuentaNoEntra() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar("owner@0fraude.mx", "Equipo#2026zs")
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.ajustes"].tap()
        app.buttons["ajustes.usuarios"].tocar(en: app)
        app.buttons["usuarios.fila.usuario_01"].tocar(en: app)
        app.buttons["Suspender cuenta"].tap()
        capturar(app, "12-usuarios")
        app.salir()
        app.buttons["registro.irLogin"].tap()
        app.textFields["login.correo"].escribir("usuario@0fraude.mx")
        app.secureTextFields["login.contrasena"].escribir("Alerta#2026mx")
        app.buttons["login.entrar"].tap()
        XCTAssertTrue(app.staticTexts["Tu cuenta está suspendida. Escríbenos para revisarla."].waitForExistence(timeout: 5))
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` → FAIL: no existe `ajustes.usuarios`.

- [ ] **Paso 3: Crear `Views/Admin/OwnerUsersView.swift`**

```swift
//
//  OwnerUsersView.swift
//  PrototipoApp
//
//  Solo Owner: cuentas, roles (Usuario ↔ Administrador), suspensión, analíticas anónimas y
//  "restablecer datos de demostración". El Owner no puede tocarse a sí mismo ni crear otro Owner.
//

import SwiftUI

struct OwnerUsersView: View {
    @Environment(AdminStore.self) private var admin
    @Environment(SessionStore.self) private var session
    @Environment(\.appConfig) private var config
    @State private var seleccionado: Usuario?
    @State private var confirmarRestablecer = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CargaView(carga: admin.usuarios, reintentar: { await admin.cargarUsuarios() }) { lista in
                    ForEach(lista) { fila($0) }
                }
                if let error { AvisoBanner(texto: error, tono: .error) }

                VStack(alignment: .leading, spacing: 6) {
                    Text("USO ANÓNIMO").ofraude(13, .bold, color: Theme.accent).accessibilityAddTraits(.isHeader)
                    Text(verbatim: "Inicios de sesión: \(admin.analiticas["inicio_sesion"] ?? 0)").ofraude(14, color: Theme.textLight)
                    Text(verbatim: "Búsquedas: \(admin.analiticas["busqueda"] ?? 0)").ofraude(14, color: Theme.textLight)
                    Text(verbatim: "Reportes enviados: \(admin.analiticas["reporte_enviado"] ?? 0)").ofraude(14, color: Theme.textLight)
                    Text("Solo cuenta a quienes lo permiten en Seguridad y privacidad, y no guarda quién hizo qué.")
                        .ofraude(12, color: Theme.textMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard(radius: 8)

                if config.fuente == .demo {
                    BotonAccion(titulo: "RESTABLECER DATOS DE DEMOSTRACIÓN",
                                estilo: OfraudeButtonStyle(background: Theme.card, foreground: Theme.dangerText, size: 14,
                                                           weight: .semibold, radius: 8, height: 48),
                                identificador: "usuarios.restablecer") {
                        confirmarRestablecer = true
                    }
                }
            }
            .padding(16)
        }
        .ofraudeScreen()
        .navigationTitle("Usuarios y roles")
        .navigationBarTitleDisplayMode(.inline)
        .task { await admin.cargarUsuarios() }
        .confirmationDialog(seleccionado.map { "@\($0.alias)" } ?? "",
                            isPresented: Binding(get: { seleccionado != nil }, set: { if !$0 { seleccionado = nil } }),
                            titleVisibility: .visible, presenting: seleccionado) { u in
            if u.rol == .usuario {
                Button("Hacer Administrador") { Task { await cambiarRol(u, a: .administrador) } }
            } else if u.rol == .administrador {
                Button("Quitar rol de Administrador") { Task { await cambiarRol(u, a: .usuario) } }
            }
            if u.estadoCuenta == .activo {
                Button("Suspender cuenta", role: .destructive) { Task { await cambiarEstado(u, a: .suspendido) } }
            } else {
                Button("Reactivar cuenta") { Task { await cambiarEstado(u, a: .activo) } }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Suspender cierra todas sus sesiones al instante.")
        }
        .alert("¿Restablecer los datos de demostración?", isPresented: $confirmarRestablecer) {
            Button("Restablecer", role: .destructive) { Task { await restablecer() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borran las cuentas, reportes y archivos creados durante la demo y se vuelve a los datos iniciales. Se cerrará tu sesión.")
        }
    }

    private func fila(_ u: Usuario) -> some View {
        Button { seleccionado = u } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "@\(u.alias)").ofraude(15, .semibold, color: Theme.textPrimary)
                    Text(u.correo).ofraude(12, color: Theme.textMuted)
                }
                Spacer()
                if u.estadoCuenta == .suspendido {
                    Etiqueta(texto: "SUSPENDIDA", color: Theme.dangerText, fondo: Theme.danger.opacity(0.2))
                }
                Etiqueta(texto: u.rol.titulo.uppercased(), color: Theme.accent, fondo: Theme.accent.opacity(0.15))
            }
            .padding(14)
            .ofraudeCard(radius: 8)
        }
        .buttonStyle(.plain)
        .disabled(u.id == session.usuario?.id || u.rol == .owner)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("usuarios.fila.\(u.alias)")
    }

    private func cambiarRol(_ u: Usuario, a rol: Rol) async {
        do { try await admin.cambiarRol(idUsuario: u.id, a: rol) } catch { self.error = error.mensajeUsuario }
    }

    private func cambiarEstado(_ u: Usuario, a estado: EstadoCuenta) async {
        do { try await admin.cambiarEstadoCuenta(idUsuario: u.id, a: estado) } catch { self.error = error.mensajeUsuario }
    }

    private func restablecer() async {
        do {
            try await admin.restablecerDemo()
            session.expirar(.servidor("Datos de demostración restablecidos. Inicia sesión de nuevo."))
        } catch {
            self.error = error.mensajeUsuario
        }
    }
}
```

- [ ] **Paso 4: Ajustes y ruta.** Dentro de la sección ADMINISTRACIÓN (F15), después de la fila de moderación:

```swift
                        if session.usuario?.rol == .owner {
                            Hairline()
                            NavigationLink(value: Route.ownerUsers) { rowLabel("Usuarios y roles", height: 46) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("ajustes.usuarios")
                        }
```

`case .ownerUsers: OwnerUsersView()` en `Route+Destination.swift`.

- [ ] **Paso 5: Pruebas** — Run: `UI` → verde. Manual: "Hacer Administrador" a `usuario_01`, salir, entrar como usuario: aparece ADMINISTRACIÓN → Revisión de reportes. Restablecer: tras confirmar se vuelve a Login con el aviso y la semilla está de vuelta.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: gestión de usuarios y roles del Owner y restablecer la demo"
```

**Criterios de aceptación:** solo el Owner ve "Usuarios y roles"; suspender impide entrar y cierra sesiones activas; restablecer vuelve a la semilla.
**Dependencias:** F15, D9. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea F18: Editar perfil y avatar

**Objetivo:** "GUARDAR CAMBIOS" guarda nombre, apellido, país, alias, correo (pidiendo la contraseña si cambia) y biografía, con validación; "Cambiar Avatar" elige una foto (sin metadatos, 512 px) o la quita.

**Archivos:**
- Modificar: `PrototipoApp/Views/Account/EditProfileView.swift` (todo el archivo)
- Crear: `PrototipoApp/Views/Shared/ConfirmarContrasenaView.swift`
- Test: `PrototipoAppUITests/PerfilUITests.swift`

**Interfaces:**
- Consume: D9 (`SessionStore.usuario`, `actualizarPerfil`, `actualizarAvatar`; `ReportsStore.archivos`), F4 (`AvatarView`), S3 (`Validador.perfil`), S6 (`ProcesadorEvidencia.limpiarImagen(_:ladoMaximo:)`), V1.
- Produce: `ConfirmarContrasenaView(titulo:mensaje:boton:accion:)`; identificadores `perfil.nombre`, `perfil.apellido`, `perfil.alias`, `perfil.correo`, `perfil.biografia`, `perfil.avatar`, `perfil.quitarAvatar`, `perfil.guardar`, `confirmar.contrasena`, `confirmar.boton`.

- [ ] **Paso 1: Prueba que falla** — agregar a `PerfilUITests`:

```swift
    @MainActor
    func testEditarPerfilValidaYGuarda() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.editar"].tocar(en: app)
        let alias = app.textFields["perfil.alias"]
        XCTAssertTrue(alias.waitForExistence(timeout: 5))
        alias.reemplazar("tecno_mx")
        app.buttons["perfil.guardar"].tocar(en: app)
        XCTAssertTrue(app.elemento(contiene: "Ese nombre de usuario ya está en uso.").waitForExistence(timeout: 5))
        alias.reemplazar("ana_lopez")
        app.buttons["perfil.guardar"].tocar(en: app)
        XCTAssertTrue(app.elemento(contiene: "@ana_lopez").waitForExistence(timeout: 5))
    }

    @MainActor
    func testCambiarCorreoPideContrasena() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.editar"].tocar(en: app)
        app.textFields["perfil.correo"].reemplazar("ana.nueva@comunidad.test")
        app.buttons["perfil.guardar"].tocar(en: app)
        let campo = app.secureTextFields["confirmar.contrasena"]
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.escribir("Alerta#2026mx")
        app.buttons["confirmar.boton"].tap()
        XCTAssertTrue(app.buttons["perfil.editar"].waitForExistence(timeout: 5))
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `PerfilUITests`) → FAIL: no existe `perfil.alias`.

- [ ] **Paso 3: Crear `Views/Shared/ConfirmarContrasenaView.swift`**

```swift
//
//  ConfirmarContrasenaView.swift
//  PrototipoApp
//
//  Pide la contraseña actual antes de un cambio delicado (cambiar el correo, apagar la
//  verificación en dos pasos). Así, alguien con el teléfono desbloqueado no puede hacerlo solo.
//

import SwiftUI

struct ConfirmarContrasenaView: View {
    let titulo: String
    let mensaje: String
    let boton: String
    let accion: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contrasena = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(titulo).ofraude(22, .bold, color: Theme.textLight)
                Text(mensaje).ofraude(14, color: Theme.textMuted)
                LabeledSecureField(label: "CONTRASEÑA ACTUAL", placeholder: "••••••••", text: $contrasena,
                                   contenido: .password, identificador: "confirmar.contrasena")
                FieldError(mensaje: error)
                BotonAccion(titulo: boton, habilitado: !contrasena.isEmpty, identificador: "confirmar.boton") {
                    do {
                        try await accion(contrasena)
                        dismiss()
                    } catch {
                        self.error = error.mensajeUsuario
                        contrasena = ""
                    }
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .ofraudeScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Paso 4: Reescribir `Views/Account/EditProfileView.swift`**

```swift
//
//  EditProfileView.swift
//  PrototipoApp
//
//  Reemplaza: escena `editprofile-vc` / EditProfileViewController. Antes "Guardar cambios" solo
//  regresaba y "Cambiar Avatar" era texto. Ahora guarda con validación (derecho de
//  rectificación), pide la contraseña si cambia el correo y la foto se guarda sin metadatos.
//

import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ReportsStore.self) private var reports
    @Environment(\.dismiss) private var dismiss

    @State private var datos = PerfilDatos(desde: Usuario.vacio)
    @State private var cargado = false
    @State private var tocados: Set<Campo> = []
    @State private var pedirContrasena = false
    @State private var error: String?
    @State private var foto: PhotosPickerItem?
    @State private var procesandoFoto = false
    @FocusState private var foco: Campo?

    private var original: Usuario? { session.usuario }

    private var limpio: PerfilDatos {
        var d = datos
        d.nombre = Sanitizador.texto(d.nombre, maximo: 50)
        d.apellido = Sanitizador.texto(d.apellido, maximo: 50)
        d.alias = Sanitizador.alias(d.alias)
        d.correo = Sanitizador.correo(d.correo)
        d.biografia = Sanitizador.texto(d.biografia, maximo: 300, multilinea: true)
        return d
    }

    /// La contraseña para cambiar el correo se pide en una hoja aparte, así que no bloquea el botón.
    private var errores: [ErrorCampo] {
        Validador.perfil(limpio, correoOriginal: original?.correo ?? "").filter { $0.campo != .contrasenaActual }
    }

    private func errorDe(_ campo: Campo) -> String? { tocados.contains(campo) ? errores.mensaje(para: campo) : nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AvatarView(usuario: original, tamano: 128)
                    .overlay(Circle().strokeBorder(Theme.defaultBorder, lineWidth: 4))
                    .overlay { if procesandoFoto { ProgressView().tint(Theme.accent) } }

                HStack(spacing: 20) {
                    PhotosPicker(selection: $foto, matching: .images) {
                        Text("Cambiar Avatar").ofraude(15, color: Theme.accent)
                    }
                    .accessibilityIdentifier("perfil.avatar")
                    if original?.avatarRuta != nil {
                        Button { Task { await quitarAvatar() } } label: {
                            Text("Quitar foto").ofraude(15, color: Theme.dangerText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("perfil.quitarAvatar")
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    LabeledTextField(label: "NOMBRE", placeholder: "", text: $datos.nombre, contenido: .givenName,
                                     error: errorDe(.nombre), maximo: 50, foco: $foco, campo: .nombre, identificador: "perfil.nombre")
                    LabeledTextField(label: "APELLIDO", placeholder: "", text: $datos.apellido, contenido: .familyName,
                                     error: errorDe(.apellido), maximo: 50, foco: $foco, campo: .apellido, identificador: "perfil.apellido")
                }
                LabeledTextField(label: "NOMBRE DE USUARIO", placeholder: "", text: $datos.alias, contenido: .nickname,
                                 error: errorDe(.alias), maximo: 20, foco: $foco, campo: .alias, identificador: "perfil.alias")
                LabeledTextField(label: "CORREO ELECTRÓNICO (PRIVADO)", placeholder: "", text: $datos.correo,
                                 keyboard: .emailAddress, contenido: .emailAddress, error: errorDe(.correo), maximo: 150,
                                 foco: $foco, campo: .correo, identificador: "perfil.correo")

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("PAÍS")
                    Picker("País", selection: $datos.pais) {
                        ForEach(Validador.paises, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.textLight)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .ofraudeCampo()
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("BIOGRAFÍA / ESPECIALIDAD")
                    OfraudeTextEditor(placeholder: "Breve descripción de tus áreas de investigación...", text: $datos.biografia,
                                      maximo: 300, error: errorDe(.biografia), foco: $foco, campo: .biografia,
                                      identificador: "perfil.biografia")
                }

                if let error { AvisoBanner(texto: error, tono: .error) }

                BotonAccion(titulo: "GUARDAR CAMBIOS", estilo: OfraudeButtonStyle(size: 15, weight: .semibold, radius: 4),
                            habilitado: errores.isEmpty, identificador: "perfil.guardar") {
                    if limpio.correo != original?.correo { pedirContrasena = true } else { await guardar(contrasena: nil) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Editar perfil")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !cargado, let original else { return }
            datos = PerfilDatos(desde: original)
            cargado = true
        }
        .onChange(of: foco) { anterior, _ in
            if let anterior { tocados.insert(anterior) }
        }
        .onChange(of: foto) { _, item in
            guard let item else { return }
            Task { await cambiarAvatar(item) }
        }
        .sheet(isPresented: $pedirContrasena) {
            ConfirmarContrasenaView(titulo: "Confirma tu contraseña",
                                    mensaje: "Para cambiar tu correo necesitamos confirmar que eres tú.",
                                    boton: "CONFIRMAR Y GUARDAR") { contrasena in
                try await guardarOLanzar(contrasena: contrasena)
            }
        }
    }

    private func guardar(contrasena: String?) async {
        do { try await guardarOLanzar(contrasena: contrasena) } catch { self.error = error.mensajeUsuario }
    }

    private func guardarOLanzar(contrasena: String?) async throws {
        error = nil
        var d = limpio
        d.contrasenaActual = contrasena
        try await session.actualizarPerfil(d)
        dismiss()
    }

    private func cambiarAvatar(_ item: PhotosPickerItem) async {
        procesandoFoto = true
        defer { procesandoFoto = false; foto = nil }
        do {
            guard let datos = try await item.loadTransferable(type: Data.self) else { return }
            let limpia = try await Task.detached(priority: .userInitiated) {
                try ProcesadorEvidencia.limpiarImagen(datos, ladoMaximo: 512)
            }.value
            try await session.actualizarAvatar(try reports.archivos.guardarTemporal(limpia, tipo: "image/jpeg"))
        } catch {
            self.error = "No se pudo usar esa imagen."
        }
    }

    private func quitarAvatar() async {
        do { try await session.actualizarAvatar(nil) } catch { self.error = error.mensajeUsuario }
    }
}

#Preview {
    NavigationStack { EditProfileView() }
        .entornoDePrueba()
}
```

(`Usuario.vacio` lo agregó S3 en `Model/Usuario.swift`.)

- [ ] **Paso 5: Pruebas** — Run: `UI` (clase `PerfilUITests`) → verde. Manual: "Cambiar Avatar" con una foto de la galería; aparece en Perfil e Inicio; "Quitar foto" vuelve al ícono.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: editar perfil con validación, avatar sin metadatos y confirmación de correo"
```

**Criterios de aceptación:** los cambios persisten; alias repetido o correo inválido no se guardan; cambiar el correo exige la contraseña.
**Dependencias:** F4, D9, S3, S6, V1. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea F19: Cambiar contraseña

**Objetivo:** "GUARDAR CONTRASEÑA" exige la actual, aplica la política a la nueva, confirma, guarda el hash nuevo y cierra las sesiones en otros dispositivos.

**Archivos:**
- Modificar: `PrototipoApp/Views/Account/ChangePasswordView.swift` (todo el archivo)
- Modificar: `PrototipoApp/Views/Account/PrivacyView.swift:21` (identificador `privacidad.cambiarContrasena`)
- Modificar: `PrototipoApp/Views/Account/SettingsView.swift:25` (identificador `ajustes.privacidad`)
- Test: `PrototipoAppUITests/PrivacidadUITests.swift` (crear)

**Interfaces:**
- Consume: D9 (`SessionStore.cambiarContrasena`), S3 (`Validador.contrasenaNueva`), V1 (`LabeledSecureField`, `ResumenErrores`).
- Produce: identificadores `ajustes.privacidad`, `privacidad.cambiarContrasena`, `contrasena.actual`, `contrasena.nueva`, `contrasena.confirmacion`, `contrasena.guardar`; ayudante `XCUIApplication.abrirPrivacidad()`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppUITests/PrivacidadUITests.swift`:

```swift
//
//  PrivacidadUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class PrivacidadUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testCambiarContrasena() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.abrirPrivacidad()
        app.buttons["privacidad.cambiarContrasena"].tap()
        app.secureTextFields["contrasena.actual"].escribir("NoEsLaMia123")
        app.secureTextFields["contrasena.nueva"].escribir("NuevaFrase#2026")
        app.secureTextFields["contrasena.confirmacion"].escribir("NuevaFrase#2026")
        app.buttons["contrasena.guardar"].tocar(en: app)
        XCTAssertTrue(app.elemento(contiene: "La contraseña actual no es correcta.").waitForExistence(timeout: 5))
        app.secureTextFields["contrasena.actual"].reemplazar("Alerta#2026mx")
        app.buttons["contrasena.guardar"].tocar(en: app)
        app.alerts.buttons["Aceptar"].tap()
        app.salir()
        app.entrar("usuario@0fraude.mx", "NuevaFrase#2026")
    }
}
```

Agregar a `Ayudantes.swift`:

```swift
    func abrirPrivacidad() {
        volverALaRaiz()
        tabBars.buttons["Perfil"].tap()
        buttons["perfil.ajustes"].tap()
        buttons["ajustes.privacidad"].tap()
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `PrivacidadUITests`) → FAIL: no existe `ajustes.privacidad`.

- [ ] **Paso 3: Reescribir `Views/Account/ChangePasswordView.swift`**

```swift
//
//  ChangePasswordView.swift
//  PrototipoApp
//
//  Reemplaza: escena `changepw-vc` / ChangePasswordViewController. Antes "Guardar" solo
//  regresaba. Ahora verifica la contraseña actual en el servidor, aplica la política a la nueva
//  y cierra las sesiones abiertas en otros dispositivos.
//

import SwiftUI

struct ChangePasswordView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var actual = ""
    @State private var nueva = ""
    @State private var confirmacion = ""
    @State private var tocados: Set<Campo> = []
    @State private var error: String?
    @State private var listo = false
    @FocusState private var foco: Campo?

    private var errores: [ErrorCampo] {
        guard let u = session.usuario else { return [] }
        var lista = Validador.contrasenaNueva(nueva, confirmacion: confirmacion, alias: u.alias, correo: u.correo)
        if actual.isEmpty { lista.append(ErrorCampo(campo: .contrasenaActual, mensaje: "Escribe tu contraseña actual.")) }
        if !actual.isEmpty && actual == nueva {
            lista.append(ErrorCampo(campo: .contrasena, mensaje: "La nueva contraseña debe ser distinta de la actual."))
        }
        return lista
    }

    private func errorDe(_ campo: Campo) -> String? { tocados.contains(campo) ? errores.mensaje(para: campo) : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Actualiza tu clave de acceso para mantener tu cuenta segura.")
                    .ofraude(14, color: Theme.textMuted)

                LabeledSecureField(label: "CONTRASEÑA ACTUAL", placeholder: "••••••••", text: $actual, contenido: .password,
                                   error: errorDe(.contrasenaActual), foco: $foco, campo: .contrasenaActual,
                                   identificador: "contrasena.actual")
                LabeledSecureField(label: "NUEVA CONTRASEÑA", placeholder: "••••••••", text: $nueva, contenido: .newPassword,
                                   error: errorDe(.contrasena), foco: $foco, campo: .contrasena, identificador: "contrasena.nueva")
                LabeledSecureField(label: "CONFIRMAR NUEVA CONTRASEÑA", placeholder: "••••••••", text: $confirmacion,
                                   contenido: .newPassword, error: errorDe(.confirmacion), foco: $foco, campo: .confirmacion,
                                   identificador: "contrasena.confirmacion")
                ResumenErrores(errores: ["Mínimo 10 caracteres, con letras y números.",
                                         "No uses tu usuario, tu correo ni una contraseña común."], tono: .info)

                if let error { AvisoBanner(texto: error, tono: .error) }

                BotonAccion(titulo: "GUARDAR CONTRASEÑA", habilitado: errores.isEmpty, identificador: "contrasena.guardar") {
                    await guardar()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Cambiar contraseña")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: foco) { anterior, _ in
            if let anterior { tocados.insert(anterior) }
        }
        .alert("Contraseña actualizada", isPresented: $listo) {
            Button("Aceptar") { dismiss() }
        } message: {
            Text("Cerramos tus sesiones en otros dispositivos.")
        }
    }

    private func guardar() async {
        error = nil
        do {
            try await session.cambiarContrasena(actual: actual, nueva: nueva)
            actual = ""
            nueva = ""
            confirmacion = ""
            listo = true
        } catch {
            self.error = error.mensajeUsuario
        }
    }
}

#Preview {
    NavigationStack { ChangePasswordView() }
        .entornoDePrueba()
}
```

`ResumenErrores` con `tono: .info` muestra las reglas en gris antes de que haya errores (mismo componente que la práctica 452).

- [ ] **Paso 4: Identificadores.** `SettingsView`: `.accessibilityIdentifier("ajustes.privacidad")` al enlace "Seguridad y Privacidad". `PrivacyView`: `.accessibilityIdentifier("privacidad.cambiarContrasena")` al enlace CAMBIAR CONTRASEÑA.

- [ ] **Paso 5: Pruebas** — Run: `UI` (clase `PrivacidadUITests`) → verde.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Views/Account PrototipoAppUITests
git commit -m "feat: cambiar contraseña con verificación y cierre de otras sesiones"
```

**Criterios de aceptación:** la contraseña vieja deja de servir y la nueva sí; una actual incorrecta no cambia nada.
**Dependencias:** D9, V1, S3. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea F20: Seguridad y privacidad — switches reales y aviso

**Objetivo:** los tres switches guardan y tienen efecto: verificación en dos pasos (activa el código al iniciar sesión; apagarla pide la contraseña), Perfil público (muestra u oculta el alias en reportes y comentarios) y Analíticas anónimas (cuenta o no los eventos); más el enlace al aviso de privacidad.

**Archivos:**
- Modificar: `PrototipoApp/Views/Account/PrivacyView.swift` (todo el archivo)
- Test: `PrototipoAppUITests/PrivacidadUITests.swift`

**Interfaces:**
- Consume: D9 (`SessionStore.usuario`, `actualizarPreferencias(_:contrasena:)`), F1 (`PrivacyNoticeView`), F18 (`ConfirmarContrasenaView`), V1.
- Produce: identificadores `privacidad.dosPasos`, `privacidad.perfilPublico`, `privacidad.analiticas`, `privacidad.aviso`; ayudante `XCUIElement.alternar()`. F21 agrega filas a la sección "TUS DATOS".

- [ ] **Paso 1: Prueba que falla** — agregar a `PrivacidadUITests`:

```swift
    @MainActor
    func testDosPasosPideCodigoAlEntrar() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.abrirPrivacidad()
        let interruptor = app.switches["privacidad.dosPasos"]
        interruptor.alternar()
        esperar(interruptor, valor: "1")   // el switch refleja la cuenta: "1" = ya se guardó
        app.salir()
        app.buttons["registro.irLogin"].tap()
        app.textFields["login.correo"].escribir("usuario@0fraude.mx")
        app.secureTextFields["login.contrasena"].escribir("Alerta#2026mx")
        app.buttons["login.entrar"].tap()
        let demo = app.descendants(matching: .any)["codigo.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        let codigo = demo.label.filter(\.isNumber)
        app.textFields["codigo.campo"].escribir(codigo)
        app.buttons["codigo.verificar"].tap()
        XCTAssertTrue(app.tabBars.buttons["Inicio"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testApagarDosPasosPideContrasena() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.abrirPrivacidad()
        let interruptor = app.switches["privacidad.dosPasos"]
        interruptor.alternar()
        esperar(interruptor, valor: "1")
        interruptor.alternar()
        XCTAssertTrue(app.secureTextFields["confirmar.contrasena"].waitForExistence(timeout: 5))
        app.secureTextFields["confirmar.contrasena"].escribir("Alerta#2026mx")
        app.buttons["confirmar.boton"].tap()
        esperar(interruptor, valor: "0")
    }
```

Agregar a `Ayudantes.swift`:

```swift
@MainActor
extension XCUIElement {
    /// Toca el interruptor (lado derecho del renglón) de un `Toggle`.
    func alternar() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `PrivacidadUITests`) → FAIL: no existe `privacidad.dosPasos`.

- [ ] **Paso 3: Reescribir `Views/Account/PrivacyView.swift`**

```swift
//
//  PrivacyView.swift
//  PrototipoApp
//
//  Reemplaza: escena `privacy-vc` / PrivacyViewController. Los switches ya no son decorativos:
//  - Autenticación en 2 pasos: pide un código al iniciar sesión; apagarla exige la contraseña.
//  - Perfil público: decide si la comunidad ve tu alias en reportes y comentarios.
//  - Analíticas anónimas: cuenta (o no) eventos sin identificarte.
//  También es la puerta a los derechos ARCO (aviso, exportar, eliminar cuenta).
//

import SwiftUI

struct PrivacyView: View {
    @Environment(SessionStore.self) private var session
    @State private var pedirContrasena = false
    @State private var error: String?

    private var preferencias: Preferencias { session.usuario?.preferencias ?? Preferencias() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                section("SEGURIDAD") {
                    NavigationLink(value: Route.changePassword) {
                        Text("CAMBIAR CONTRASEÑA")
                            .ofraude(15, .semibold, color: Theme.textLight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacidad.cambiarContrasena")
                    Hairline()
                    toggleRow("Autenticación en 2 pasos", "Te pediremos un código al iniciar sesión",
                              isOn: Binding(get: { preferencias.dosPasos }, set: { nuevo in
                                  if nuevo { Task { await cambiar { $0.dosPasos = true } } } else { pedirContrasena = true }
                              }), id: "privacidad.dosPasos")
                }

                section("PRIVACIDAD") {
                    toggleRow("Perfil Público", "Mostrar tu nombre de usuario en tus reportes y comentarios",
                              isOn: Binding(get: { preferencias.perfilPublico },
                                            set: { nuevo in Task { await cambiar { $0.perfilPublico = nuevo } } }),
                              id: "privacidad.perfilPublico")
                    Hairline()
                    toggleRow("Analíticas Anónimas", "Contadores de uso sin datos personales",
                              isOn: Binding(get: { preferencias.analiticas },
                                            set: { nuevo in Task { await cambiar { $0.analiticas = nuevo } } }),
                              id: "privacidad.analiticas")
                }

                section("TUS DATOS") {
                    NavigationLink(value: Route.privacyNotice) {
                        Text("AVISO DE PRIVACIDAD")
                            .ofraude(15, .semibold, color: Theme.textLight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacidad.aviso")
                }

                if let error { AvisoBanner(texto: error, tono: .error) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 20)
        }
        .ofraudeScreen()
        .navigationTitle("Seguridad y privacidad")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pedirContrasena) {
            ConfirmarContrasenaView(titulo: "Apagar la verificación en dos pasos",
                                    mensaje: "Tu cuenta quedará protegida solo con la contraseña. Confirma que eres tú.",
                                    boton: "APAGAR") { contrasena in
                var p = preferencias
                p.dosPasos = false
                try await session.actualizarPreferencias(p, contrasena: contrasena)
            }
        }
    }

    private func cambiar(_ ajuste: (inout Preferencias) -> Void) async {
        var p = preferencias
        ajuste(&p)
        do {
            try await session.actualizarPreferencias(p)
            error = nil
        } catch {
            self.error = error.mensajeUsuario
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).ofraude(18, .bold, color: Theme.accent).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ofraudeCard(borderWidth: 2)
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).ofraude(14, .semibold, color: Theme.textLight)
                Text(subtitle).ofraude(13, color: Theme.textSubtle)
            }
        }
        .tint(Theme.accent)
        .accessibilityIdentifier(id)
    }
}

#Preview {
    NavigationStack { PrivacyView() }
        .entornoDePrueba()
}
```

El estado inicial de los switches ya no es el del storyboard (2 pasos encendido, Perfil público apagado, Analíticas encendido): ahora refleja la cuenta. Las cuentas nuevas arrancan con 2 pasos apagado; se anota en `docs/CAMBIOS-vs-original.md` (M1).

- [ ] **Paso 4: Pruebas** — Run: `UI` (clase `PrivacidadUITests`) → verde. Manual: con Perfil público apagado, un comentario propio se ve como "Miembro de la comunidad" desde otra cuenta (probado también en `DemoServerVistaTests`).

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp/Views/Account/PrivacyView.swift PrototipoAppUITests
git commit -m "feat: switches de seguridad y privacidad con efecto real"
```

**Criterios de aceptación:** cada switch persiste y cambia el comportamiento descrito; apagar 2 pasos sin contraseña no es posible.
**Dependencias:** F1, F18, D9. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea F21: Derechos ARCO — descargar mis datos y eliminar cuenta

**Objetivo:** "Descargar mis datos" genera un JSON con todo lo de la persona y lo comparte; "Eliminar mi cuenta" explica qué pasa, pide contraseña y escribir ELIMINAR, y deja la app en Login con el aviso.

**Archivos:**
- Crear: `PrototipoApp/Views/Account/DeleteAccountView.swift`
- Modificar: `PrototipoApp/Views/Account/PrivacyView.swift` (sección TUS DATOS)
- Modificar: `PrototipoApp/Stores/SessionStore.swift` (`cerrarSesion` y `expirar` borran el archivo exportado)
- Modificar: `PrototipoApp/Views/Route+Destination.swift` (`.deleteAccount`)
- Test: `PrototipoAppUITests/PrivacidadUITests.swift`

**Interfaces:**
- Consume: D9 (`SessionStore.exportarDatos`, `eliminarCuenta`), D7 (reglas de anonimización), V1.
- Produce: `DeleteAccountView`; identificadores `privacidad.exportar`, `privacidad.compartirDatos`, `privacidad.eliminarCuenta`, `eliminar.contrasena`, `eliminar.confirmacion`, `eliminar.boton`.

- [ ] **Paso 1: Prueba que falla** — agregar a `PrivacidadUITests`:

```swift
    @MainActor
    func testExportarYEliminarCuenta() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.abrirPrivacidad()
        app.buttons["privacidad.exportar"].tocar(en: app)
        XCTAssertTrue(app.buttons["privacidad.compartirDatos"].waitForExistence(timeout: 5))
        app.buttons["privacidad.eliminarCuenta"].tocar(en: app)
        app.secureTextFields["eliminar.contrasena"].escribir("Alerta#2026mx")
        XCTAssertFalse(app.buttons["eliminar.boton"].isEnabled)
        app.textFields["eliminar.confirmacion"].escribir("ELIMINAR")
        app.buttons["eliminar.boton"].tocar(en: app)
        app.alerts.buttons["Eliminar mi cuenta"].tap()
        XCTAssertTrue(app.elemento(contiene: "Tu cuenta se eliminó. Gracias por ayudar a la comunidad.").waitForExistence(timeout: 10))
        app.textFields["login.correo"].escribir("usuario@0fraude.mx")
        app.secureTextFields["login.contrasena"].escribir("Alerta#2026mx")
        app.buttons["login.entrar"].tap()
        XCTAssertTrue(app.staticTexts["Correo o contraseña incorrectos."].waitForExistence(timeout: 5))
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` → FAIL: no existe `privacidad.exportar`.

- [ ] **Paso 3: Sección TUS DATOS en `PrivacyView`.** Agregar `@State private var exportado: URL?` y `@State private var exportando = false`; dentro de `section("TUS DATOS")`, después del aviso:

```swift
                    Hairline()
                    if let exportado {
                        ShareLink(item: exportado) {
                            Text("COMPARTIR MIS DATOS (JSON)").ofraude(15, .semibold, color: Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 52)
                        }
                        .accessibilityIdentifier("privacidad.compartirDatos")
                    } else {
                        Button { Task { await exportar() } } label: {
                            Text(exportando ? "PREPARANDO…" : "DESCARGAR MIS DATOS").ofraude(15, .semibold, color: Theme.textLight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(exportando)
                        .accessibilityIdentifier("privacidad.exportar")
                    }
                    Hairline()
                    NavigationLink(value: Route.deleteAccount) {
                        Text("ELIMINAR MI CUENTA").ofraude(15, .semibold, color: Theme.dangerText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacidad.eliminarCuenta")
```

```swift
    /// Derecho de acceso: todo lo de la persona en un archivo que ella decide a dónde mandar.
    private func exportar() async {
        exportando = true
        defer { exportando = false }
        do { exportado = try await session.exportarDatos() } catch { self.error = error.mensajeUsuario }
    }
```

- [ ] **Paso 4: Crear `Views/Account/DeleteAccountView.swift`**

```swift
//
//  DeleteAccountView.swift
//  PrototipoApp
//
//  Derecho de cancelación. Explica qué se borra y qué se queda anónimo, y pide dos pruebas de
//  intención: la contraseña y escribir ELIMINAR.
//

import SwiftUI

struct DeleteAccountView: View {
    @Environment(SessionStore.self) private var session
    @State private var contrasena = ""
    @State private var confirmacion = ""
    @State private var preguntar = false
    @State private var error: String?

    private var listo: Bool { !contrasena.isEmpty && confirmacion.trimmingCharacters(in: .whitespaces) == "ELIMINAR" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Eliminar mi cuenta").ofraude(24, .bold, color: Theme.textLight).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Qué pasa al eliminarla").ofraude(15, .bold, color: Theme.textLight)
                    Text("• Se borran tu cuenta, tus guardados, tus confirmaciones, tus notificaciones y tus reportes que aún no se validan, con su evidencia.").ofraude(14, color: Theme.textMuted)
                    Text("• Tus reportes ya validados se quedan para alertar a la comunidad, pero sin tu nombre, sin datos de terceros y sin evidencia.").ofraude(14, color: Theme.textMuted)
                    Text("• Tus comentarios se quedan como «Cuenta eliminada».").ofraude(14, color: Theme.textMuted)
                    Text("• No se puede deshacer.").ofraude(14, .semibold, color: Theme.dangerText)
                }
                .padding(16)
                .ofraudeCard(radius: 8)

                LabeledSecureField(label: "CONTRASEÑA", placeholder: "••••••••", text: $contrasena, contenido: .password,
                                   identificador: "eliminar.contrasena")
                LabeledTextField(label: "ESCRIBE ELIMINAR PARA CONFIRMAR", placeholder: "ELIMINAR", text: $confirmacion,
                                 maximo: 20, identificador: "eliminar.confirmacion")
                if let error { AvisoBanner(texto: error, tono: .error) }
                BotonAccion(titulo: "ELIMINAR MI CUENTA", estilo: OfraudeButtonStyle(background: Theme.danger),
                            habilitado: listo, identificador: "eliminar.boton") {
                    preguntar = true
                }
            }
            .padding(24)
        }
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle("Eliminar cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .alert("¿Eliminar tu cuenta para siempre?", isPresented: $preguntar) {
            Button("Eliminar mi cuenta", role: .destructive) { Task { await eliminar() } }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func eliminar() async {
        do {
            try await session.eliminarCuenta(contrasena: contrasena)
        } catch {
            self.error = error.mensajeUsuario
            contrasena = ""
        }
    }
}
```

- [ ] **Paso 5: Limpieza del archivo exportado.** En `SessionStore`, agregar:

```swift
    /// El JSON de "Descargar mis datos" no se queda en el teléfono después de la sesión.
    private func borrarExportacion() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appending(path: "0fraude-mis-datos.json"))
    }
```

y llamarlo en `cerrarSesion()`, `expirar(_:)` y `eliminarCuenta(contrasena:)`. Ruta: `case .deleteAccount: DeleteAccountView()`.

- [ ] **Paso 6: Pruebas** — Run: `UI` (clase `PrivacidadUITests`) → verde; `UNIT` en verde. Comprobar: `grep -n "EmptyView()" PrototipoApp/Views/Route+Destination.swift` sin resultados (todas las rutas tienen pantalla).

- [ ] **Paso 7: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: descargar mis datos y eliminar cuenta (derechos ARCO)"
```

**Criterios de aceptación:** el JSON incluye perfil, reportes, comentarios, guardados y notificaciones, sin hash; tras eliminar, el login con esa cuenta falla y los reportes validados siguen visibles como "Cuenta eliminada".
**Dependencias:** F20, D7, D9. **Esfuerzo:** M. **Riesgo:** bajo.

---

## 4. Seguridad

### 4.1 Controles y dónde vive cada uno

| Control | Qué hace | Dónde | Prueba |
|---|---|---|---|
| Sin credenciales en código | `admin`/`admin` eliminado; cuentas demo sembradas como hash | D10, D4 | AC5 (`grep`), `DemoSeedTests` |
| Hash + sal | PBKDF2-HMAC-SHA256, 600,000 iteraciones (recomendación OWASP para PBKDF2-SHA256), sal de 16 bytes con `SecRandomCopyBytes`, NFC antes de derivar, comparación en tiempo constante | S1 | `PasswordHasherTests` (vectores conocidos) |
| Sesión en Keychain | Token aleatorio de 32 bytes; en el servidor solo su SHA-256, caduca a 7 días; en el teléfono `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | S2, D5 | `SecretStoreTests`, `DemoServerAuthTests` |
| Limpieza tras reinstalar | iOS conserva el Keychain al desinstalar; si falta la marca de instalación se borran los tokens | S2 | `limpiaTokensEnPrimeraEjecucion` |
| Campos de contraseña | `SecureField` con mostrar/ocultar, `textContentType` correcto, la contraseña se vacía tras cada intento | V1, F2 | UI tests de autenticación |
| Política de contraseñas | 10–64 caracteres, letra y número, no común, no contiene usuario ni correo | S3 | `ValidadorTests` |
| Límite de intentos | 5 fallos por correo (exista o no) → 1 min, se duplica hasta 15 min; mensaje genérico; hash señuelo para igualar tiempos | S5, D5 | `LimiteIntentosTests`, `cincoFallosBloquean…` |
| Verificación en dos pasos | Código de 6 dígitos (SHA-256 en el servidor), 5 min, 3 intentos; apagarla pide la contraseña | D5, F2, F20 | `dosPasos…`, UI `testDosPasos…` |
| Autorización en el servidor | Cada operación resuelve usuario y rol desde el token; lo no visible responde 404; nadie modera lo suyo | D5–D7 | ≥ 8 pruebas `sinPermiso`/`noEncontrado` |
| Validación y saneamiento | Recorte, sin caracteres de control ni invisibles/bidi, longitudes del SQL; se repite en el servidor | S3, D5–D7 | `SanitizadorTests`, `ValidadorTests` |
| URLs seguras | Solo http/https; se quitan credenciales `user@`; se detectan homógrafos; se comparten "desactivadas"; nunca se abren | S4, F5, F6 | `URLToolsTests`, `CompartirTests` |
| Evidencia segura | Re-codificación sin EXIF/GPS, máx. 1600 px y 5 MB (PDF 10 MB y firma `%PDF-`), nombres generados (sin rutas del cliente), `FileProtectionType.complete`, fuera de respaldo, acceso con permiso | S6, D6, F10 | `ProcesadorEvidenciaTests`, `ArchivosEvidenciaTests` |
| Privacidad por diseño | Anónimo y perfil privado ocultan autor; persona afectada y evidencia solo para autor y staff; staff ve "Equipo de moderación" al autor | D5, F5 | `DemoServerVistaTests` |
| Límite de abuso | 10 reportes por día, 5 comentarios por minuto | D6 | `limiteDe…` |
| Escudo en el selector de apps | Tapa la app al salir de primer plano | D10 | Q3 manual |
| Avisos sin detalles | La notificación del sistema no incluye el título del reporte | D9, F16 | `avisaUnaSolaVezSinDetalles` |
| Datos personales (LFPDPPP) | Aviso con versión, consentimiento con fecha, ARCO en la app, datos de terceros con autorización | F1, F20, F21 | UI `PrivacidadUITests` |
| Transporte | ATS sin excepciones salvo `NSAllowsLocalNetworking`; Remote solo HTTPS o localhost; 401 → refresh → reintento único | R2, D8 | `APIClientTests`, `AppConfigTests` |
| Markdown inyectado | Datos del usuario en `Text` siempre como `String` | Restricción global | S7 (`grep`) |

### 4.2 Modelo de amenazas (STRIDE)

Activos: credenciales, tokens de sesión, datos personales (propios y de terceros), evidencia, integridad de los estados de los reportes, reputación de quien es reportado.

| Amenaza | Ejemplo en 0Fraude | Mitigación en el prototipo | Riesgo residual (no mitigado) |
|---|---|---|---|
| **S**poofing (suplantación) | Adivinar la contraseña de otra persona; robar su token | Política de contraseñas, límite de intentos con bloqueo, hash señuelo, 2 pasos opcional, token aleatorio en Keychain, caducidad, revocación al cerrar sesión o cambiar contraseña | Sin 2 pasos real (el código demo se muestra en pantalla); sin detección de dispositivos nuevos |
| **T**ampering (alteración) | Editar un reporte ya validado; mover un reporte a un estado inválido; cambiar el JSON del modo Demo | Edición solo en RECIBIDO/EN_REVISION, máquina de estados en el servidor, historial de cambios con responsable | El JSON del modo Demo vive en el teléfono: con acceso al sistema de archivos (jailbreak) se puede alterar. En producción la base está en el servidor |
| **R**epudiation (negar una acción) | "Yo no validé ese reporte" | `Historial_Estado` con responsable, estado anterior y nuevo, fecha y observaciones | Sin bitácora firmada ni inmutable; el Owner puede restablecer la demo |
| **I**nformation disclosure (fuga) | Ver quién hizo un reporte anónimo; ver datos de la persona afectada; leer la contraseña; captura en el selector de apps; aviso en pantalla bloqueada; ubicación GPS en una foto | Vista por usuario en el servidor, 404 para lo no visible, hash sin texto claro, Keychain, escudo de privacidad, avisos sin detalles, fotos sin metadatos, archivos cifrados, export solo de lo propio | El staff sí ve el autor real de un anónimo (está en el aviso); en el simulador la protección de archivos no se aplica; los PDF conservan sus metadatos |
| **D**enial of service | Inundar de reportes o comentarios; bloquear la cuenta de alguien con intentos fallidos | 10 reportes/día, 5 comentarios/min, tamaño máximo de archivos | El bloqueo por correo permite bloquear temporalmente a otra persona (bloqueo de 1 a 15 min, aceptado); sin límite por IP (no aplica en Demo) |
| **E**levation of privilege | Un Usuario que llama a la moderación; un Administrador que se hace Owner | Rol revisado en cada operación del servidor; el Owner solo asigna Usuario/Administrador; nadie se cambia a sí mismo; nadie modera lo propio | La interfaz confía en el rol que devuelve el servidor (correcto); en Demo el "servidor" corre dentro de la app |

Riesgos aceptados para el prototipo (se documentan en `docs/seguridad.md`): el registro dice si un correo ya existe (enumeración en el alta, práctica común); contraseñas de las cuentas demo publicadas en el guion; `confirmacionesPrevias` solo en Demo.

### 4.3 Tareas de seguridad

### Tarea S1: Números aleatorios y hash de contraseñas

**Objetivo:** derivar y verificar contraseñas con PBKDF2-HMAC-SHA256 y sal, y generar tokens y códigos con el generador seguro del sistema.

**Archivos:**
- Crear: `PrototipoApp/Security/Aleatorio.swift`
- Crear: `PrototipoApp/Security/PasswordHasher.swift`
- Test: `PrototipoAppTests/Security/PasswordHasherTests.swift`

**Interfaces:**
- Consume: Q1.
- Produce: `Aleatorio.bytes(_:) -> Data`, `Aleatorio.token() -> String` (32 bytes base64url), `Aleatorio.codigo() -> String` (6 dígitos); `PasswordHasher(iteraciones:)` con `iteracionesRecomendadas = 600_000`, `hash(_:) -> String`, `verificar(_:contra:) -> Bool`, `static pbkdf2(_:sal:iteraciones:longitud:) -> Data`, `static igualesEnTiempoConstante(_:_:) -> Bool`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppTests/Security/PasswordHasherTests.swift`:

```swift
//
//  PasswordHasherTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct PasswordHasherTests {
    let hasher = PasswordHasher(iteraciones: 1_000)

    private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    @Test func vectoresConocidosDePBKDF2SHA256() {
        let sal = Data("salt".utf8)
        #expect(hex(PasswordHasher.pbkdf2("password", sal: sal, iteraciones: 1)) ==
                "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        #expect(hex(PasswordHasher.pbkdf2("password", sal: sal, iteraciones: 4_096)) ==
                "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    @Test func formatoGuardado() {
        let partes = hasher.hash("Segura#2026x").split(separator: "$")
        #expect(partes.count == 4)
        #expect(partes[0] == "pbkdf2_sha256")
        #expect(partes[1] == "1000")
    }

    @Test func mismaContrasenaDistintoHash() {
        #expect(hasher.hash("Segura#2026x") != hasher.hash("Segura#2026x"))
    }

    @Test func verificaSoloLaCorrecta() {
        let guardado = hasher.hash("Segura#2026x")
        #expect(hasher.verificar("Segura#2026x", contra: guardado))
        #expect(!hasher.verificar("segura#2026x", contra: guardado))
        #expect(!hasher.verificar("", contra: guardado))
    }

    @Test func hashesMalformadosNuncaVerifican() {
        for malo in ["", "md5$1$a$b", "pbkdf2_sha256$10$AAAA$AAAA", "pbkdf2_sha256$1000$no-base64$AAAA", "pbkdf2_sha256$1000$AAAA"] {
            #expect(!hasher.verificar("x", contra: malo))
        }
    }

    @Test func normalizaUnicode() {
        let compuesta = "Contraseña#2026"
        let descompuesta = "Contrasen\u{0303}a#2026"
        #expect(hasher.verificar(descompuesta, contra: hasher.hash(compuesta)))
    }

    @Test func comparacionEnTiempoConstante() {
        #expect(PasswordHasher.igualesEnTiempoConstante(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(!PasswordHasher.igualesEnTiempoConstante(Data([1, 2, 3]), Data([1, 2, 4])))
        #expect(!PasswordHasher.igualesEnTiempoConstante(Data([1, 2]), Data([1, 2, 3])))
    }

    @Test func aleatoriosConFormaCorrecta() {
        #expect(Aleatorio.bytes(16).count == 16)
        #expect(Aleatorio.token() != Aleatorio.token())
        #expect(!Aleatorio.token().contains("+") && !Aleatorio.token().contains("/"))
        #expect(Aleatorio.codigo().wholeMatch(of: /[0-9]{6}/) != nil)
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → FAIL `cannot find 'PasswordHasher' in scope`.

- [ ] **Paso 3: Implementar `Security/Aleatorio.swift`**

```swift
//
//  Aleatorio.swift
//  PrototipoApp
//
//  Bytes, tokens y códigos con el generador criptográfico del sistema (nunca `random()`).
//

import Foundation
import Security

nonisolated enum Aleatorio {
    static func bytes(_ cantidad: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: cantidad)
        let estado = SecRandomCopyBytes(kSecRandomDefault, cantidad, &bytes)
        // Si el generador del sistema falla no hay forma segura de seguir (única excepción documentada).
        precondition(estado == errSecSuccess, "SecRandomCopyBytes falló")
        return Data(bytes)
    }

    /// 32 bytes en base64url (sin `+`, `/` ni `=`): token de sesión o id de desafío.
    static func token() -> String {
        bytes(32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Código de 6 dígitos. `Int.random` usa el generador seguro del sistema.
    static func codigo() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}
```

- [ ] **Paso 4: Implementar `Security/PasswordHasher.swift`**

```swift
//
//  PasswordHasher.swift
//  PrototipoApp
//
//  Contraseñas con PBKDF2-HMAC-SHA256 (CommonCrypto) y sal aleatoria. Se guarda
//  "pbkdf2_sha256$<iteraciones>$<sal>$<hash>" (cabe en Usuario.contrasena_hash VARCHAR(255)).
//  Las iteraciones viajan dentro del texto: se pueden subir después sin romper los hashes viejos.
//

import CommonCrypto
import Foundation

nonisolated struct PasswordHasher: Sendable {
    /// Recomendación de OWASP para PBKDF2-HMAC-SHA256.
    static let iteracionesRecomendadas = 600_000

    let iteraciones: Int

    init(iteraciones: Int = PasswordHasher.iteracionesRecomendadas) {
        self.iteraciones = iteraciones
    }

    func hash(_ contrasena: String) -> String {
        let sal = Aleatorio.bytes(16)
        let derivada = Self.pbkdf2(contrasena, sal: sal, iteraciones: iteraciones)
        return "pbkdf2_sha256$\(iteraciones)$\(sal.base64EncodedString())$\(derivada.base64EncodedString())"
    }

    func verificar(_ contrasena: String, contra guardado: String) -> Bool {
        let partes = guardado.split(separator: "$", omittingEmptySubsequences: false)
        guard partes.count == 4, partes[0] == "pbkdf2_sha256",
              let n = Int(partes[1]), n >= 1_000,
              let sal = Data(base64Encoded: String(partes[2])),
              let esperado = Data(base64Encoded: String(partes[3])), !esperado.isEmpty
        else { return false }
        return Self.igualesEnTiempoConstante(Self.pbkdf2(contrasena, sal: sal, iteraciones: n), esperado)
    }

    static func pbkdf2(_ contrasena: String, sal: Data, iteraciones: Int, longitud: Int = 32) -> Data {
        // Misma contraseña escrita con "ñ" compuesta o descompuesta debe dar el mismo hash.
        let normalizada = contrasena.precomposedStringWithCanonicalMapping
        var derivada = [UInt8](repeating: 0, count: longitud)
        let estado = normalizada.withCString { texto in
            sal.withUnsafeBytes { bytesSal in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), texto, strlen(texto),
                                     bytesSal.bindMemory(to: UInt8.self).baseAddress, sal.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iteraciones),
                                     &derivada, longitud)
            }
        }
        guard estado == kCCSuccess else { return Data() }
        return Data(derivada)
    }

    /// Recorre todos los bytes aunque haya diferencia al principio: no filtra información por el tiempo.
    static func igualesEnTiempoConstante(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var diferencia: UInt8 = 0
        for (x, y) in zip(a, b) { diferencia |= x ^ y }
        return diferencia == 0
    }
}
```

(Si `CCKeyDerivationPBKDF` fallara se devuelve `Data()`, que nunca coincide con un hash guardado: falla cerrado.)

- [ ] **Paso 5: Pruebas** — Run: `UNIT` (suite `PasswordHasherTests`) → verde.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Security PrototipoAppTests/Security
git commit -m "feat: hash de contraseñas PBKDF2-SHA256 con sal y aleatorios seguros"
```

**Criterios de aceptación:** los vectores conocidos coinciden; un hash malformado nunca verifica.
**Dependencias:** Q1. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea S2: Keychain y limpieza tras reinstalar

**Objetivo:** guardar y borrar los tokens en el Keychain (con una versión en memoria para pruebas) y borrar tokens huérfanos en la primera ejecución después de reinstalar.

**Archivos:**
- Crear: `PrototipoApp/Security/SecretStore.swift`
- Test: `PrototipoAppTests/Security/SecretStoreTests.swift`

**Interfaces:**
- Consume: Q1 (target de pruebas con app anfitriona: el Keychain del simulador necesita los permisos de la app).
- Produce: `protocol SecretStore` (`leer(_:)`, `guardar(_:para:)`, `borrar(_:)`, `borrarTodo()`), `ClaveSecreta` (`.accessToken`, `.refreshToken`), `KeychainStore(servicio:)`, `MemorySecretStore`, `ErrorKeychain`, `PrimeraEjecucion.limpiarSiHaceFalta(defaults:secretos:)`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppTests/Security/SecretStoreTests.swift`:

```swift
//
//  SecretStoreTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct SecretStoreTests {
    @Test func keychainGuardaLeeYBorra() throws {
        let keychain = KeychainStore(servicio: "zs.pruebas.\(UUID().uuidString)")
        #expect(try keychain.leer(.accessToken) == nil)
        try keychain.guardar("uno", para: .accessToken)
        try keychain.guardar("dos", para: .accessToken)   // reemplaza, no duplica
        #expect(try keychain.leer(.accessToken) == "dos")
        try keychain.borrarTodo()
        #expect(try keychain.leer(.accessToken) == nil)
        try keychain.borrar(.refreshToken)                  // borrar algo que no existe no falla
    }

    @Test func memoriaSeComportaIgual() throws {
        let memoria = MemorySecretStore()
        try memoria.guardar("abc", para: .refreshToken)
        #expect(try memoria.leer(.refreshToken) == "abc")
        try memoria.borrarTodo()
        #expect(try memoria.leer(.refreshToken) == nil)
    }

    @Test func limpiaTokensEnPrimeraEjecucion() throws {
        let defaults = try #require(UserDefaults(suiteName: "zs.pruebas.\(UUID().uuidString)"))
        let secretos = MemorySecretStore()
        try secretos.guardar("de-una-instalacion-anterior", para: .accessToken)
        PrimeraEjecucion.limpiarSiHaceFalta(defaults: defaults, secretos: secretos)
        #expect(try secretos.leer(.accessToken) == nil)
        try secretos.guardar("vigente", para: .accessToken)
        PrimeraEjecucion.limpiarSiHaceFalta(defaults: defaults, secretos: secretos)
        #expect(try secretos.leer(.accessToken) == "vigente")
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → FAIL `cannot find 'KeychainStore' in scope`.

- [ ] **Paso 3: Implementar `Security/SecretStore.swift`**

```swift
//
//  SecretStore.swift
//  PrototipoApp
//
//  Dónde viven los tokens de sesión. En la app, el Keychain: cifrado por iOS, disponible solo
//  con el teléfono desbloqueado y sin viajar en respaldos a otro dispositivo. En pruebas, memoria.
//

import Foundation
import Security
import Synchronization

nonisolated enum ClaveSecreta: String, Sendable, CaseIterable {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
}

nonisolated protocol SecretStore: Sendable {
    func leer(_ clave: ClaveSecreta) throws -> String?
    func guardar(_ valor: String, para clave: ClaveSecreta) throws
    func borrar(_ clave: ClaveSecreta) throws
}

nonisolated extension SecretStore {
    func borrarTodo() throws {
        for clave in ClaveSecreta.allCases { try borrar(clave) }
    }
}

nonisolated struct ErrorKeychain: Error, Equatable {
    let estado: OSStatus
}

nonisolated struct KeychainStore: SecretStore {
    let servicio: String

    private func consulta(_ clave: ClaveSecreta) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servicio,
         kSecAttrAccount as String: clave.rawValue]
    }

    func leer(_ clave: ClaveSecreta) throws -> String? {
        var q = consulta(clave)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: CFTypeRef?
        let estado = SecItemCopyMatching(q as CFDictionary, &resultado)
        if estado == errSecItemNotFound { return nil }
        guard estado == errSecSuccess, let datos = resultado as? Data else { throw ErrorKeychain(estado: estado) }
        return String(decoding: datos, as: UTF8.self)
    }

    func guardar(_ valor: String, para clave: ClaveSecreta) throws {
        try borrar(clave)
        var q = consulta(clave)
        q[kSecValueData as String] = Data(valor.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let estado = SecItemAdd(q as CFDictionary, nil)
        guard estado == errSecSuccess else { throw ErrorKeychain(estado: estado) }
    }

    func borrar(_ clave: ClaveSecreta) throws {
        let estado = SecItemDelete(consulta(clave) as CFDictionary)
        guard estado == errSecSuccess || estado == errSecItemNotFound else { throw ErrorKeychain(estado: estado) }
    }
}

nonisolated final class MemorySecretStore: SecretStore {
    private let valores = Mutex<[ClaveSecreta: String]>([:])

    func leer(_ clave: ClaveSecreta) throws -> String? { valores.withLock { $0[clave] } }
    func guardar(_ valor: String, para clave: ClaveSecreta) throws { valores.withLock { $0[clave] = valor } }
    func borrar(_ clave: ClaveSecreta) throws { valores.withLock { $0[clave] = nil } }
}

nonisolated enum PrimeraEjecucion {
    /// iOS conserva el Keychain al desinstalar la app, pero no UserDefaults. Si falta la marca,
    /// los tokens que haya son de una instalación anterior y se borran.
    static func limpiarSiHaceFalta(defaults: UserDefaults, secretos: any SecretStore) {
        let marca = "zs.instalada"
        guard !defaults.bool(forKey: marca) else { return }
        try? secretos.borrarTodo()
        defaults.set(true, forKey: marca)
    }
}
```

- [ ] **Paso 4: Pruebas** — Run: `UNIT` (suite `SecretStoreTests`) → verde. Si `keychainGuardaLeeYBorra` falla con `ErrorKeychain(estado: -34018)` (`errSecMissingEntitlement`), el target de pruebas no está usando la app como anfitriona: revisar `TEST_HOST` y `BUNDLE_LOADER` de Q1 (sección 10, riesgo R2).

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp/Security/SecretStore.swift PrototipoAppTests/Security/SecretStoreTests.swift
git commit -m "feat: tokens en Keychain y limpieza tras reinstalar"
```

**Criterios de aceptación:** guardar reemplaza; borrar lo inexistente no falla; la primera ejecución borra tokens huérfanos.
**Dependencias:** Q1. **Esfuerzo:** S. **Riesgo:** medio (Keychain en pruebas, ver sección 10).

### Tarea S3: Saneamiento y validación de entradas

**Objetivo:** una sola fuente de reglas para todos los formularios (mismo estilo que la práctica `Demo-RetoSwiftUI452`: reglas con nombre y lista de errores), usada por la interfaz y por el servidor.

**Archivos:**
- Crear: `PrototipoApp/Security/Sanitizador.swift`
- Crear: `PrototipoApp/Security/Validador.swift`
- Test: `PrototipoAppTests/Security/SanitizadorTests.swift`, `PrototipoAppTests/Security/ValidadorTests.swift`

**Interfaces:**
- Consume: D1 (`RegistroDatos`, `PerfilDatos`, `ReporteBorrador`, `EstadoReporte`, `NivelRiesgo`), S4 (`URLTools.pareceURL`, `normalizar`).
- Produce: `Sanitizador.texto(_:maximo:multilinea:)`, `correo(_:)`, `alias(_:)`; `ReporteBorrador.limpio`; `Campo` (enum), `ErrorCampo`, `[ErrorCampo].mensaje(para:)`, `.mensajes`; `Validador.paises`, `contrasenasComunes`, `esCorreoValido(_:)`, `esNombreValido(_:)`, `esAliasValido(_:)`, `esTelefonoValido(_:)`, `registro(_:)`, `contrasenaNueva(_:confirmacion:alias:correo:)`, `reporte(_:ahora:)`, `perfil(_:correoOriginal:)`, `comentario(_:)`, `moderacion(nuevo:riesgo:observaciones:)`, `codigo(_:)`.

- [ ] **Paso 1: Pruebas que fallan** — `PrototipoAppTests/Security/SanitizadorTests.swift`:

```swift
//
//  SanitizadorTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct SanitizadorTests {
    @Test func recortaYColapsaEspacios() {
        #expect(Sanitizador.texto("  hola    mundo  ", maximo: 50) == "hola mundo")
    }

    @Test func quitaCaracteresInvisibles() {
        #expect(Sanitizador.texto("ad\u{200B}min", maximo: 50) == "admin")
        #expect(Sanitizador.texto("abc\u{202E}fdp.exe", maximo: 50) == "abcfdp.exe")
        #expect(Sanitizador.texto("\u{FEFF}hola\u{0007}", maximo: 50) == "hola")
    }

    @Test func multilineaConservaSaltosPeroNoMasDeDos() {
        #expect(Sanitizador.texto("uno\n\n\n\ndos", maximo: 50, multilinea: true) == "uno\n\ndos")
        #expect(Sanitizador.texto("uno\ndos", maximo: 50) == "uno dos")
    }

    @Test func cortaAlMaximo() {
        #expect(Sanitizador.texto(String(repeating: "a", count: 600), maximo: 500).count == 500)
    }

    @Test func correoYAliasEnMinusculas() {
        #expect(Sanitizador.correo("  Ana@Ejemplo.MX ") == "ana@ejemplo.mx")
        #expect(Sanitizador.alias(" Usuario_01 ") == "usuario_01")
    }

    @Test func borradorLimpio() {
        var b = ReporteBorrador()
        b.titulo = "  Tienda   falsa  "
        b.descripcion = "Línea uno\n\n\n\nLínea dos"
        #expect(b.limpio.titulo == "Tienda falsa")
        #expect(b.limpio.descripcion == "Línea uno\n\nLínea dos")
    }
}
```

`PrototipoAppTests/Security/ValidadorTests.swift`:

```swift
//
//  ValidadorTests.swift
//  PrototipoAppTests
//
//  Una prueba por regla (AC3).
//

import Foundation
import Testing
@testable import PrototipoApp

struct ValidadorTests {
    static func registroValido() -> RegistroDatos {
        var d = RegistroDatos()
        d.nombre = "Ana María"
        d.apellido = "López-Ruiz"
        d.alias = "ana_lopez"
        d.correo = "ana@comunidad.test"
        d.contrasena = "Fraude0-Cero"
        d.confirmacion = "Fraude0-Cero"
        d.aceptaAviso = true
        return d
    }

    static func borradorValido() -> ReporteBorrador {
        var b = ReporteBorrador()
        b.ciudad = "CDMX"
        b.titulo = "Tienda falsa de consolas"
        b.descripcion = "Piden transferencia y nunca entregan el producto."
        b.urlOTexto = "https://consolas-baratas.store"
        b.fechaIncidente = Date(timeIntervalSince1970: 1_791_000_000)
        return b
    }

    let ahora = Date(timeIntervalSince1970: 1_791_072_000)

    @Test func registroValidoNoTieneErrores() { #expect(Validador.registro(Self.registroValido()).isEmpty) }

    @Test(arguments: ["", "A", "Ana1", String(repeating: "a", count: 51)])
    func nombreInvalido(_ nombre: String) {
        var d = Self.registroValido(); d.nombre = nombre
        #expect(Validador.registro(d).mensaje(para: .nombre) == "Escribe tu nombre (2 a 50 letras).")
    }

    @Test func apellidoInvalido() {
        var d = Self.registroValido(); d.apellido = ""
        #expect(Validador.registro(d).mensaje(para: .apellido) == "Escribe tu apellido (2 a 50 letras).")
    }

    @Test func paisFueraDeLaLista() {
        var d = Self.registroValido(); d.pais = "Narnia"
        #expect(Validador.registro(d).mensaje(para: .pais) == "Elige un país de la lista.")
    }

    @Test(arguments: ["ab", "con espacio", "MAYUS", "ñandú", String(repeating: "a", count: 21)])
    func aliasInvalido(_ alias: String) {
        var d = Self.registroValido(); d.alias = alias
        #expect(Validador.registro(d).mensaje(para: .alias) != nil)
    }

    @Test(arguments: ["", "ana", "ana@", "ana@dominio", "ana@@dominio.mx", "ana..lopez@dominio.mx", "ana@dominio.mx extra"])
    func correoInvalido(_ correo: String) {
        #expect(!Validador.esCorreoValido(correo))
    }

    @Test func correoValido() { #expect(Validador.esCorreoValido("ana.lopez+0fraude@comunidad.test")) }

    @Test func contrasenaCorta() {
        #expect(Validador.contrasenaNueva("Abc12345", confirmacion: "Abc12345", alias: "x", correo: "x@y.mx")
            .mensaje(para: .contrasena) == "La contraseña debe tener entre 10 y 64 caracteres.")
    }

    @Test func contrasenaSinNumero() {
        #expect(Validador.contrasenaNueva("SoloLetrasAqui", confirmacion: "SoloLetrasAqui", alias: "x", correo: "x@y.mx")
            .mensaje(para: .contrasena) == "Incluye al menos una letra y un número.")
    }

    @Test func contrasenaComun() {
        #expect(Validador.contrasenaNueva("Password123", confirmacion: "Password123", alias: "x", correo: "x@y.mx")
            .mensaje(para: .contrasena) == "Esa contraseña es muy común; elige otra.")
    }

    @Test func contrasenaConElUsuario() {
        #expect(Validador.contrasenaNueva("ana_lopez2026", confirmacion: "ana_lopez2026", alias: "ana_lopez", correo: "z@y.mx")
            .mensaje(para: .contrasena) == "La contraseña no debe contener tu usuario ni tu correo.")
    }

    @Test func confirmacionDistinta() {
        #expect(Validador.contrasenaNueva("Fraude0-Cero", confirmacion: "Fraude0-cero", alias: "x", correo: "x@y.mx")
            .mensaje(para: .confirmacion) == "Las contraseñas no coinciden.")
    }

    @Test func avisoObligatorio() {
        var d = Self.registroValido(); d.aceptaAviso = false
        #expect(Validador.registro(d).mensaje(para: .aviso) == "Acepta el aviso de privacidad para crear tu cuenta.")
    }

    @Test func reporteValido() { #expect(Validador.reporte(Self.borradorValido(), ahora: ahora).isEmpty) }

    @Test func reporteSinCiudadTituloNiDescripcion() {
        var b = Self.borradorValido()
        b.ciudad = ""; b.titulo = "corto"; b.descripcion = "poco"
        let e = Validador.reporte(b, ahora: ahora)
        #expect(e.mensaje(para: .ciudad) == "Indica la ciudad donde ocurrió (2 a 60 caracteres).")
        #expect(e.mensaje(para: .titulo) == "El título debe tener entre 10 y 120 caracteres.")
        #expect(e.mensaje(para: .descripcion) == "Describe lo ocurrido (20 a 2000 caracteres).")
    }

    @Test func otraPersonaExigeDatosYAutorizacion() {
        var b = Self.borradorValido()
        b.afectado = .otraPersona
        let e = Validador.reporte(b, ahora: ahora)
        #expect(e.mensaje(para: .personaNombre) == "Escribe el nombre de la persona afectada.")
        #expect(e.mensaje(para: .personaContacto) == "Escribe un teléfono (8 a 15 dígitos) o un correo válido.")
        #expect(e.mensaje(para: .personaAutorizo) == "Confirma que la persona te autorizó a compartir sus datos.")
        b.persona = PersonaAfectada(nombre: "Rosa Martínez", contacto: "+52 81 5555 0101", autorizo: true)
        #expect(Validador.reporte(b, ahora: ahora).isEmpty)
    }

    @Test func otroExigeEspecificar() {
        var b = Self.borradorValido(); b.tipo = .otro
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .tipoOtro) == "Especifica el tipo de fraude (3 a 50 caracteres).")
    }

    @Test func fechaFuturaOMuyVieja() {
        var b = Self.borradorValido()
        b.fechaIncidente = ahora.addingTimeInterval(3_600)
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .fecha) != nil)
        b.fechaIncidente = ahora.addingTimeInterval(-400 * 86_400)
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .fecha) == "La fecha no puede ser futura ni de hace más de un año.")
    }

    @Test(arguments: ["javascript:alert(1)", "ftp://sitio.com", "http://", "data:text/html,hola"])
    func enlacePeligroso(_ enlace: String) {
        var b = Self.borradorValido(); b.urlOTexto = enlace
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .urlOTexto) == "Solo se aceptan enlaces http:// o https:// válidos.")
    }

    @Test func textoQueNoEsEnlaceSePermite() {
        var b = Self.borradorValido(); b.urlOTexto = "+52 55 8765 4321"
        #expect(Validador.reporte(b, ahora: ahora).isEmpty)
    }

    @Test func masDeTresAdjuntos() {
        var b = Self.borradorValido()
        b.adjuntos = (0..<4).map { _ in Adjunto(id: UUID(), nombreArchivo: "x.jpg", tipoArchivo: "image/jpeg", bytes: 1) }
        #expect(Validador.reporte(b, ahora: ahora).mensaje(para: .adjuntos) == "Máximo 3 archivos de evidencia.")
    }

    @Test func perfilPideContrasenaSiCambiaElCorreo() {
        var p = PerfilDatos(desde: .vacio)
        p.nombre = "Ana"; p.apellido = "López"; p.alias = "ana_lopez"; p.correo = "nuevo@comunidad.test"
        #expect(Validador.perfil(p, correoOriginal: "viejo@comunidad.test").mensaje(para: .contrasenaActual)
                == "Confirma tu contraseña para cambiar el correo.")
        p.biografia = String(repeating: "a", count: 301)
        #expect(Validador.perfil(p, correoOriginal: "nuevo@comunidad.test").mensaje(para: .biografia)
                == "La biografía admite hasta 300 caracteres.")
    }

    @Test func comentarioDeDosA500() {
        #expect(!Validador.comentario("x").isEmpty)
        #expect(Validador.comentario("ok").isEmpty)
        #expect(!Validador.comentario(String(repeating: "a", count: 501)).isEmpty)
    }

    @Test func moderacionExigeRiesgoYMotivo() {
        #expect(Validador.moderacion(nuevo: .validado, riesgo: nil, observaciones: "").mensaje(para: .riesgo)
                == "Asigna un nivel de riesgo para validar.")
        #expect(Validador.moderacion(nuevo: .rechazado, riesgo: nil, observaciones: "no").mensaje(para: .observaciones)
                == "Explica el motivo del rechazo (10 a 500 caracteres).")
        #expect(Validador.moderacion(nuevo: .enRevision, riesgo: nil, observaciones: "").isEmpty)
    }

    @Test func codigoDeSeisDigitos() {
        #expect(Validador.codigo("123456").isEmpty)
        #expect(!Validador.codigo("12345").isEmpty)
        #expect(!Validador.codigo("12345a").isEmpty)
    }

    @Test(arguments: ["+52 55 1234 5678", "5512345678", "(55) 1234-5678"])
    func telefonosValidos(_ t: String) { #expect(Validador.esTelefonoValido(t)) }

    @Test(arguments: ["123", "llámame", "+52 55 1234 5678 9999 0000"])
    func telefonosInvalidos(_ t: String) { #expect(!Validador.esTelefonoValido(t)) }
}
```

Agregar a `Model/Usuario.swift` (la prueba de perfil y Editar perfil en F18 lo usan como valor inicial):

```swift
nonisolated extension Usuario {
    /// Solo para estados iniciales de pantalla y pruebas; nunca se envía.
    static let vacio = Usuario(id: 0, rol: .usuario, nombre: "", apellido: "", pais: "México", alias: "", correo: "",
                               biografia: "", avatarRuta: nil, estadoCuenta: .activo, fechaRegistro: .distantPast,
                               preferencias: Preferencias(),
                               consentimiento: Consentimiento(versionAviso: "2026-10", fecha: .distantPast))
}
```

- [ ] **Paso 2: Ver que fallan** — Run: `UNIT` → FAIL `cannot find 'Sanitizador' in scope`.

- [ ] **Paso 3: Implementar `Security/Sanitizador.swift`**

```swift
//
//  Sanitizador.swift
//  PrototipoApp
//
//  Limpia lo que escribe la persona antes de validarlo y guardarlo: recorta, quita caracteres de
//  control e invisibles (los que se usan para disfrazar texto, como el cambio de dirección
//  "Trojan Source" o espacios de ancho cero en un alias) y corta a la longitud de la columna SQL.
//  Las contraseñas NO pasan por aquí: se respetan tal cual.
//

import Foundation

nonisolated enum Sanitizador {
    private static let invisibles: Set<Unicode.Scalar> = {
        let rangos: [ClosedRange<UInt32>] = [0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF...0xFEFF]
        return Set(rangos.flatMap { $0.compactMap(Unicode.Scalar.init) })
    }()

    static func texto(_ s: String, maximo: Int, multilinea: Bool = false) -> String {
        var escalares = String.UnicodeScalarView()
        for e in s.unicodeScalars {
            if invisibles.contains(e) { continue }
            if e == "\n" { escalares.append(multilinea ? "\n" : " "); continue }
            if e == "\t" || e == "\r" { escalares.append(" "); continue }
            if CharacterSet.controlCharacters.contains(e) { continue }
            escalares.append(e)
        }
        var limpio = String(escalares).replacing(/[ ]{2,}/, with: " ")
        if multilinea {
            limpio = limpio.replacing(/ *\n */, with: "\n").replacing(/\n{3,}/, with: "\n\n")
        }
        return String(limpio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximo))
    }

    static func correo(_ s: String) -> String { texto(s, maximo: 150).lowercased() }
    static func alias(_ s: String) -> String { texto(s, maximo: 20).lowercased() }
}

nonisolated extension ReporteBorrador {
    /// El borrador listo para validar y enviar (la interfaz y el servidor usan el mismo).
    var limpio: ReporteBorrador {
        var b = self
        b.ciudad = Sanitizador.texto(ciudad, maximo: 60)
        b.persona.nombre = Sanitizador.texto(persona.nombre, maximo: 100)
        b.persona.contacto = Sanitizador.texto(persona.contacto, maximo: 150)
        b.tipoOtro = Sanitizador.texto(tipoOtro, maximo: 50)
        b.titulo = Sanitizador.texto(titulo, maximo: 120)
        b.urlOTexto = Sanitizador.texto(urlOTexto, maximo: 2048)
        b.descripcion = Sanitizador.texto(descripcion, maximo: 2000, multilinea: true)
        return b
    }
}
```

- [ ] **Paso 4: Implementar `Security/Validador.swift`**

```swift
//
//  Validador.swift
//  PrototipoApp
//
//  Reglas de todos los formularios, con mensajes en español. Mismo patrón que la práctica
//  Demo-RetoSwiftUI452 (reglas con nombre y una lista de errores), pero cada error dice a qué
//  campo pertenece para mostrarlo debajo. Las usa la interfaz y también el servidor: nunca se
//  confía en lo que valida el cliente.
//

import Foundation

nonisolated enum Campo: String, Sendable, Hashable {
    case nombre, apellido, pais, alias, correo, contrasena, confirmacion, aviso
    case contrasenaActual, ciudad, personaNombre, personaContacto, personaAutorizo
    case tipoOtro, titulo, fecha, urlOTexto, descripcion, adjuntos, biografia
    case comentario, observaciones, riesgo, codigo
}

nonisolated struct ErrorCampo: Sendable, Hashable {
    let campo: Campo
    let mensaje: String
}

nonisolated extension Array where Element == ErrorCampo {
    func mensaje(para campo: Campo) -> String? { first { $0.campo == campo }?.mensaje }
    var mensajes: [String] { map(\.mensaje) }
}

nonisolated enum Validador {
    static let paises = ["México", "Argentina", "Chile", "Colombia", "España", "Estados Unidos", "Perú", "Otro"]

    /// Contraseñas que pasan la longitud y la mezcla de letras y números pero aparecen en todas las filtraciones.
    static let contrasenasComunes: Set<String> = [
        "password123", "password1234", "contrasena123", "contraseña123", "qwerty12345", "qwerty123456",
        "abc123456789", "admin123456", "usuario12345", "mexico12345", "iloveyou123", "123456789abc",
        "1q2w3e4r5t", "1qaz2wsx3edc", "a1234567890", "q1w2e3r4t5", "superman123", "football123",
        "monkey12345", "dragon12345", "letmein12345", "welcome123", "teamo123456", "hola123456",
        "fraude12345", "0fraude123", "0fraude2026", "zeroscam123", "zeroscam2026",
    ]

    // MARK: Reglas sueltas

    static func esCorreoValido(_ s: String) -> Bool {
        s.count <= 150 && !s.contains("..") && s.wholeMatch(of: /[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}/) != nil
    }

    static func esNombreValido(_ s: String) -> Bool {
        s.wholeMatch(of: /\p{L}[\p{L} '\-]{1,49}/) != nil
    }

    static func esAliasValido(_ s: String) -> Bool {
        s.wholeMatch(of: /[a-z0-9_.]{3,20}/) != nil
    }

    static func esTelefonoValido(_ s: String) -> Bool {
        let digitos = s.filter(\.isNumber).count
        return s.wholeMatch(of: /\+?[0-9 ()\-]{8,20}/) != nil && (8...15).contains(digitos)
    }

    // MARK: Formularios

    static func registro(_ d: RegistroDatos) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        if !esNombreValido(d.nombre) { e.append(.init(campo: .nombre, mensaje: "Escribe tu nombre (2 a 50 letras).")) }
        if !esNombreValido(d.apellido) { e.append(.init(campo: .apellido, mensaje: "Escribe tu apellido (2 a 50 letras).")) }
        if !paises.contains(d.pais) { e.append(.init(campo: .pais, mensaje: "Elige un país de la lista.")) }
        if !esAliasValido(d.alias) {
            e.append(.init(campo: .alias, mensaje: "El usuario lleva de 3 a 20 caracteres: minúsculas, números, punto o guion bajo."))
        }
        if !esCorreoValido(d.correo) { e.append(.init(campo: .correo, mensaje: "Escribe un correo válido, por ejemplo nombre@dominio.com.")) }
        e += contrasenaNueva(d.contrasena, confirmacion: d.confirmacion, alias: d.alias, correo: d.correo)
        if !d.aceptaAviso { e.append(.init(campo: .aviso, mensaje: "Acepta el aviso de privacidad para crear tu cuenta.")) }
        return e
    }

    /// Un mensaje por campo (la primera regla que falla), para que el error debajo del campo sea claro.
    static func contrasenaNueva(_ c: String, confirmacion: String, alias: String, correo: String) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        let minusculas = c.lowercased()
        let usuarioCorreo = correo.split(separator: "@").first.map { $0.lowercased() } ?? ""
        if !(10...64).contains(c.count) {
            e.append(.init(campo: .contrasena, mensaje: "La contraseña debe tener entre 10 y 64 caracteres."))
        } else if !c.contains(where: \.isLetter) || !c.contains(where: \.isNumber) {
            e.append(.init(campo: .contrasena, mensaje: "Incluye al menos una letra y un número."))
        } else if contrasenasComunes.contains(minusculas) {
            e.append(.init(campo: .contrasena, mensaje: "Esa contraseña es muy común; elige otra."))
        } else if (alias.count >= 3 && minusculas.contains(alias.lowercased()))
                    || (usuarioCorreo.count >= 3 && minusculas.contains(usuarioCorreo)) {
            e.append(.init(campo: .contrasena, mensaje: "La contraseña no debe contener tu usuario ni tu correo."))
        }
        if c != confirmacion { e.append(.init(campo: .confirmacion, mensaje: "Las contraseñas no coinciden.")) }
        return e
    }

    static func reporte(_ b: ReporteBorrador, ahora: Date) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        if !(2...60).contains(b.ciudad.count) { e.append(.init(campo: .ciudad, mensaje: "Indica la ciudad donde ocurrió (2 a 60 caracteres).")) }
        if b.afectado == .otraPersona {
            if !(2...100).contains(b.persona.nombre.count) {
                e.append(.init(campo: .personaNombre, mensaje: "Escribe el nombre de la persona afectada."))
            }
            if !(esCorreoValido(b.persona.contacto) || esTelefonoValido(b.persona.contacto)) {
                e.append(.init(campo: .personaContacto, mensaje: "Escribe un teléfono (8 a 15 dígitos) o un correo válido."))
            }
            if !b.persona.autorizo {
                e.append(.init(campo: .personaAutorizo, mensaje: "Confirma que la persona te autorizó a compartir sus datos."))
            }
        }
        if b.tipo == .otro && !(3...50).contains(b.tipoOtro.count) {
            e.append(.init(campo: .tipoOtro, mensaje: "Especifica el tipo de fraude (3 a 50 caracteres)."))
        }
        if !(10...120).contains(b.titulo.count) { e.append(.init(campo: .titulo, mensaje: "El título debe tener entre 10 y 120 caracteres.")) }
        if b.fechaIncidente > ahora || b.fechaIncidente < ahora.addingTimeInterval(-365 * 86_400) {
            e.append(.init(campo: .fecha, mensaje: "La fecha no puede ser futura ni de hace más de un año."))
        }
        if b.urlOTexto.count > 2_048 {
            e.append(.init(campo: .urlOTexto, mensaje: "El enlace o texto admite hasta 2048 caracteres."))
        } else if URLTools.pareceURL(b.urlOTexto) && URLTools.normalizar(b.urlOTexto) == nil {
            e.append(.init(campo: .urlOTexto, mensaje: "Solo se aceptan enlaces http:// o https:// válidos."))
        }
        if !(20...2_000).contains(b.descripcion.count) {
            e.append(.init(campo: .descripcion, mensaje: "Describe lo ocurrido (20 a 2000 caracteres)."))
        }
        if b.adjuntos.count > 3 { e.append(.init(campo: .adjuntos, mensaje: "Máximo 3 archivos de evidencia.")) }
        return e
    }

    static func perfil(_ p: PerfilDatos, correoOriginal: String) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        if !esNombreValido(p.nombre) { e.append(.init(campo: .nombre, mensaje: "Escribe tu nombre (2 a 50 letras).")) }
        if !esNombreValido(p.apellido) { e.append(.init(campo: .apellido, mensaje: "Escribe tu apellido (2 a 50 letras).")) }
        if !paises.contains(p.pais) { e.append(.init(campo: .pais, mensaje: "Elige un país de la lista.")) }
        if !esAliasValido(p.alias) {
            e.append(.init(campo: .alias, mensaje: "El usuario lleva de 3 a 20 caracteres: minúsculas, números, punto o guion bajo."))
        }
        if !esCorreoValido(p.correo) { e.append(.init(campo: .correo, mensaje: "Escribe un correo válido, por ejemplo nombre@dominio.com.")) }
        if p.biografia.count > 300 { e.append(.init(campo: .biografia, mensaje: "La biografía admite hasta 300 caracteres.")) }
        if p.correo != correoOriginal && (p.contrasenaActual ?? "").isEmpty {
            e.append(.init(campo: .contrasenaActual, mensaje: "Confirma tu contraseña para cambiar el correo."))
        }
        return e
    }

    static func comentario(_ t: String) -> [ErrorCampo] {
        (2...500).contains(t.count) ? [] : [.init(campo: .comentario, mensaje: "El comentario debe tener entre 2 y 500 caracteres.")]
    }

    static func moderacion(nuevo: EstadoReporte, riesgo: NivelRiesgo?, observaciones: String) -> [ErrorCampo] {
        var e: [ErrorCampo] = []
        if nuevo == .validado && (riesgo == nil || riesgo == .noEvaluado) {
            e.append(.init(campo: .riesgo, mensaje: "Asigna un nivel de riesgo para validar."))
        }
        if nuevo == .rechazado && !(10...500).contains(observaciones.count) {
            e.append(.init(campo: .observaciones, mensaje: "Explica el motivo del rechazo (10 a 500 caracteres)."))
        } else if observaciones.count > 500 {
            e.append(.init(campo: .observaciones, mensaje: "Las observaciones admiten hasta 500 caracteres."))
        }
        return e
    }

    static func codigo(_ c: String) -> [ErrorCampo] {
        c.wholeMatch(of: /[0-9]{6}/) != nil ? [] : [.init(campo: .codigo, mensaje: "El código tiene 6 dígitos.")]
    }
}
```

- [ ] **Paso 5: Pruebas** — Run: `UNIT` (suites `SanitizadorTests`, `ValidadorTests`) → verde.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Security PrototipoApp/Model/Usuario.swift PrototipoAppTests/Security
git commit -m "feat: saneamiento y validación de entradas con mensajes en español"
```

**Criterios de aceptación:** cada regla tiene prueba; los invisibles y bidi desaparecen; las contraseñas no se tocan.
**Dependencias:** D1, S4. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea S4: Herramientas de URL

**Objetivo:** saber si un texto es un enlace, normalizarlo (solo http/https, sin credenciales), "desactivarlo" para mostrarlo y compartirlo, y avisar de dominios homógrafos.

**Archivos:**
- Crear: `PrototipoApp/Security/URLTools.swift`
- Test: `PrototipoAppTests/Security/URLToolsTests.swift`

**Interfaces:**
- Consume: Q1.
- Produce: `URLTools.pareceURL(_:)`, `normalizar(_:) -> String?`, `desactivar(_:) -> String`, `estadoCertificado(_:) -> String` ("HTTPS" | "SIN HTTPS"), `host(de:) -> String?`, `esPosibleHomografo(_:) -> Bool`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppTests/Security/URLToolsTests.swift`:

```swift
//
//  URLToolsTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct URLToolsTests {
    @Test(arguments: ["http://a.com", "https://a.com/x", "www.a.com", "sitio-falso.com", "javascript:alert(1)", "data:text/html,x"])
    func pareceURL(_ s: String) { #expect(URLTools.pareceURL(s)) }

    @Test(arguments: ["", "+52 55 1234 5678", "Perfil Gamer Store", "hola"])
    func noPareceURL(_ s: String) { #expect(!URLTools.pareceURL(s)) }

    @Test func normalizaEsquemaYHost() {
        #expect(URLTools.normalizar("HTTP://Sitio-Falso.COM/Pago") == "http://sitio-falso.com/Pago")
        #expect(URLTools.normalizar("sitio-falso.com") == "https://sitio-falso.com")
        #expect(URLTools.normalizar("www.sitio-falso.com/a") == "https://www.sitio-falso.com/a")
    }

    @Test func normalizarQuitaCredenciales() {
        #expect(URLTools.normalizar("https://banco.com@estafa.com/login") == "https://estafa.com/login")
        #expect(URLTools.host(de: URLTools.normalizar("https://usuario:clave@estafa.com") ?? "") == "estafa.com")
    }

    @Test(arguments: ["javascript:alert(1)", "ftp://a.com", "file:///etc/passwd", "https://localhost", "https://", "http://a .com"])
    func rechazaLoQueNoEsHTTP(_ s: String) { #expect(URLTools.normalizar(s) == nil) }

    @Test func rechazaLoMuyLargo() {
        #expect(URLTools.normalizar("https://a.com/" + String(repeating: "x", count: 2_100)) == nil)
    }

    @Test func desactivaParaCompartir() {
        #expect(URLTools.desactivar("https://sitio-falso.com/pago.html") == "hxxps://sitio-falso[.]com/pago.html")
        #expect(URLTools.desactivar("http://a.b.c") == "hxxp://a[.]b[.]c")
    }

    @Test func detectaHomografo() {
        #expect(URLTools.esPosibleHomografo("https://xn--pple-43d.com"))
        #expect(!URLTools.esPosibleHomografo("https://apple.com"))
    }

    @Test func estadoDelCertificado() {
        #expect(URLTools.estadoCertificado("https://a.com") == "HTTPS")
        #expect(URLTools.estadoCertificado("http://a.com") == "SIN HTTPS")
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → FAIL `cannot find 'URLTools' in scope`.

- [ ] **Paso 3: Implementar `Security/URLTools.swift`**

```swift
//
//  URLTools.swift
//  PrototipoApp
//
//  Los enlaces reportados son peligrosos por definición: la app nunca los abre. Aquí se decide si
//  un texto es un enlace, se normaliza (solo http/https, sin "usuario@" que esconde el host real)
//  y se "desactiva" (hxxps, [.]) para mostrarlo y compartirlo sin que sea tocable.
//

import Foundation

nonisolated enum URLTools {
    private static let esquemasPeligrosos = ["javascript:", "data:", "file:", "vbscript:"]

    static func pareceURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, !t.contains(" ") else { return false }
        if t.contains("://") || t.hasPrefix("www.") { return true }
        if esquemasPeligrosos.contains(where: t.hasPrefix) { return true }
        return t.wholeMatch(of: /[a-z0-9\-]+(\.[a-z0-9\-]+)*\.[a-z]{2,24}(\/\S*)?/) != nil
    }

    static func normalizar(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 2_048, !t.contains(" ") else { return nil }
        if esquemasPeligrosos.contains(where: t.lowercased().hasPrefix) { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard var c = URLComponents(string: t),
              let esquema = c.scheme?.lowercased(), ["http", "https"].contains(esquema),
              let host = c.host?.lowercased(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }
        c.scheme = esquema
        c.host = host
        // "https://banco.com@estafa.com" se ve como banco.com pero va a estafa.com: se quita la parte engañosa.
        c.user = nil
        c.password = nil
        return c.string
    }

    static func host(de url: String) -> String? {
        URLComponents(string: url)?.host
    }

    /// "https://sitio-falso.com/x" → "hxxps://sitio-falso[.]com/x".
    static func desactivar(_ url: String) -> String {
        var t = url
        if t.lowercased().hasPrefix("http") { t = "hxxp" + t.dropFirst(4) }
        guard let inicio = t.range(of: "://")?.upperBound else { return t.replacingOccurrences(of: ".", with: "[.]") }
        let fin = t[inicio...].firstIndex(where: { "/?#".contains($0) }) ?? t.endIndex
        let host = t[inicio..<fin].replacingOccurrences(of: ".", with: "[.]")
        return String(t[..<inicio]) + host + String(t[fin...])
    }

    /// Lo que guarda SitioWeb_URL.estado_certificado. No se consulta la red: solo el esquema.
    static func estadoCertificado(_ url: String) -> String {
        url.lowercased().hasPrefix("https://") ? "HTTPS" : "SIN HTTPS"
    }

    /// Dominios con letras de otros alfabetos (o su forma "xn--") que imitan a uno conocido.
    static func esPosibleHomografo(_ url: String) -> Bool {
        guard let host = host(de: url) else { return false }
        return host.unicodeScalars.contains { !$0.isASCII } || host.split(separator: ".").contains { $0.hasPrefix("xn--") }
    }
}
```

- [ ] **Paso 4: Pruebas** — Run: `UNIT` (suite `URLToolsTests`) → verde.

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp/Security/URLTools.swift PrototipoAppTests/Security/URLToolsTests.swift
git commit -m "feat: normalización y desactivación de enlaces reportados"
```

**Criterios de aceptación:** ningún esquema distinto de http/https pasa; el host real se muestra.
**Dependencias:** Q1. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea S5: Límite de intentos

**Objetivo:** la regla del bloqueo por intentos fallidos, pura y probada, que usa el servidor.

**Archivos:**
- Crear: `PrototipoApp/Security/LimiteIntentos.swift`
- Test: `PrototipoAppTests/Security/LimiteIntentosTests.swift`

**Interfaces:**
- Consume: Q1.
- Produce: `RegistroIntentos(fallidos:bloqueadoHasta:)` (`Codable`), `LimiteIntentos.intentosPermitidos = 5`, `bloqueadoHasta(_:ahora:) -> Date?`, `registrarFallo(_:ahora:)`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppTests/Security/LimiteIntentosTests.swift`:

```swift
//
//  LimiteIntentosTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct LimiteIntentosTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func cuatroFallosNoBloquean() {
        var r = RegistroIntentos()
        for _ in 1...4 { LimiteIntentos.registrarFallo(&r, ahora: t0) }
        #expect(LimiteIntentos.bloqueadoHasta(r, ahora: t0) == nil)
    }

    @Test func elQuintoBloqueaUnMinuto() {
        var r = RegistroIntentos()
        for _ in 1...5 { LimiteIntentos.registrarFallo(&r, ahora: t0) }
        #expect(LimiteIntentos.bloqueadoHasta(r, ahora: t0) == t0.addingTimeInterval(60))
        #expect(LimiteIntentos.bloqueadoHasta(r, ahora: t0.addingTimeInterval(61)) == nil)
    }

    @Test func cadaFalloDespuesDuplicaHastaQuinceMinutos() {
        var r = RegistroIntentos()
        var t = t0
        for _ in 1...5 { LimiteIntentos.registrarFallo(&r, ahora: t) }
        var esperados: [TimeInterval] = [120, 240, 480, 900, 900]
        while let duracion = esperados.first {
            t = (r.bloqueadoHasta ?? t).addingTimeInterval(1)
            LimiteIntentos.registrarFallo(&r, ahora: t)
            #expect(r.bloqueadoHasta == t.addingTimeInterval(duracion))
            esperados.removeFirst()
        }
    }
}
```

(Que `RegistroIntentos` se guarda y se lee bien lo prueba D3 en `DemoAlmacenTests/guardarYCargarConservaLosDatos`.)

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → FAIL `cannot find 'RegistroIntentos' in scope`.

- [ ] **Paso 3: Implementar `Security/LimiteIntentos.swift`**

```swift
//
//  LimiteIntentos.swift
//  PrototipoApp
//
//  Contra adivinar contraseñas: 5 fallos seguidos bloquean ese correo 1 minuto, y cada fallo
//  después del bloqueo duplica el tiempo hasta 15 minutos. Se cuenta por correo exista o no la
//  cuenta, para no revelar cuáles existen. Un acierto lo reinicia (lo hace el servidor).
//

import Foundation

nonisolated struct RegistroIntentos: Codable, Sendable, Hashable {
    var fallidos = 0
    var bloqueadoHasta: Date?
}

nonisolated enum LimiteIntentos {
    static let intentosPermitidos = 5
    static let bloqueoBase: TimeInterval = 60
    static let bloqueoMaximo: TimeInterval = 15 * 60

    static func bloqueadoHasta(_ r: RegistroIntentos, ahora: Date) -> Date? {
        guard let hasta = r.bloqueadoHasta, hasta > ahora else { return nil }
        return hasta
    }

    static func registrarFallo(_ r: inout RegistroIntentos, ahora: Date) {
        r.fallidos += 1
        guard r.fallidos >= intentosPermitidos else { return }
        let exceso = Double(r.fallidos - intentosPermitidos)
        r.bloqueadoHasta = ahora.addingTimeInterval(min(bloqueoBase * pow(2, exceso), bloqueoMaximo))
    }
}
```

- [ ] **Paso 4: Pruebas** — Run: `UNIT` (suite `LimiteIntentosTests`) → verde.

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp/Security/LimiteIntentos.swift PrototipoAppTests/Security/LimiteIntentosTests.swift
git commit -m "feat: límite de intentos con bloqueo creciente"
```

**Criterios de aceptación:** 1, 2, 4, 8, 15, 15 minutos.
**Dependencias:** Q1. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea S6: Evidencia sin metadatos y archivos protegidos

**Objetivo:** re-codificar imágenes sin EXIF/GPS (máx. 1600 px, 5 MB), validar PDFs, y guardar archivos con nombres generados, cifrados por iOS, fuera de respaldos y sin posibilidad de leer rutas arbitrarias.

**Archivos:**
- Crear: `PrototipoApp/Security/ProcesadorEvidencia.swift`
- Crear: `PrototipoApp/Security/ArchivosEvidencia.swift`
- Test: `PrototipoAppTests/Security/ProcesadorEvidenciaTests.swift`, `PrototipoAppTests/Security/ArchivosEvidenciaTests.swift`

**Interfaces:**
- Consume: D1 (`Adjunto`).
- Produce: `ProcesadorEvidencia.limpiarImagen(_:ladoMaximo:) throws -> Data`, `validarPDF(_:) throws`, `ErrorEvidencia` (`.noEsImagen`, `.muyGrande`, `.noEsPDF`, `.nombreInvalido`, `.noExiste`); `ArchivosEvidencia(carpeta:)` con `guardarTemporal(_:tipo:) -> Adjunto`, `datos(de:) -> Data`, `borrarTemporal(_:)`, `confirmar(_:) -> String`, `datos(ruta:) -> Data`, `borrar(ruta:)`, `limpiarTemporales()`, `borrarTodo()`.

- [ ] **Paso 1: Pruebas que fallan**

`PrototipoAppTests/Security/ProcesadorEvidenciaTests.swift`:

```swift
//
//  ProcesadorEvidenciaTests.swift
//  PrototipoAppTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PrototipoApp

struct ProcesadorEvidenciaTests {
    /// JPEG de 2000×1000 con ubicación GPS, fecha y modelo de cámara en sus metadatos.
    static func jpegConGPS() throws -> Data {
        let contexto = try #require(CGContext(data: nil, width: 2_000, height: 1_000, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        contexto.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        contexto.fill(CGRect(x: 0, y: 0, width: 2_000, height: 1_000))
        let imagen = try #require(contexto.makeImage())
        let salida = NSMutableData()
        let destino = try #require(CGImageDestinationCreateWithData(salida, UTType.jpeg.identifier as CFString, 1, nil))
        let metadatos: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 19.43, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 99.13, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:01 10:00:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone 17"],
        ]
        CGImageDestinationAddImage(destino, imagen, metadatos as CFDictionary)
        #expect(CGImageDestinationFinalize(destino))
        return salida as Data
    }

    private static func propiedades(_ datos: Data) throws -> [CFString: Any] {
        let fuente = try #require(CGImageSourceCreateWithData(datos as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(fuente, 0, nil) as? [CFString: Any])
    }

    @Test func quitaUbicacionYDatosDeCamara() throws {
        let original = try Self.jpegConGPS()
        #expect(try Self.propiedades(original)[kCGImagePropertyGPSDictionary] != nil)   // la prueba sí tiene GPS
        let limpia = try ProcesadorEvidencia.limpiarImagen(original)
        let p = try Self.propiedades(limpia)
        #expect(p[kCGImagePropertyGPSDictionary] == nil)
        #expect((p[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect((p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
    }

    @Test func reduceAlLadoMaximo() throws {
        let p = try Self.propiedades(try ProcesadorEvidencia.limpiarImagen(try Self.jpegConGPS()))
        #expect(p[kCGImagePropertyPixelWidth] as? Int == 1_600)
    }

    @Test func rechazaLoQueNoEsImagen() {
        #expect(throws: ErrorEvidencia.noEsImagen) { try ProcesadorEvidencia.limpiarImagen(Data("hola".utf8)) }
    }

    @Test func pdfPorFirmaYTamano() throws {
        try ProcesadorEvidencia.validarPDF(Data("%PDF-1.7\n…".utf8))
        #expect(throws: ErrorEvidencia.noEsPDF) { try ProcesadorEvidencia.validarPDF(Data("<html>".utf8)) }
        #expect(throws: ErrorEvidencia.muyGrande) {
            try ProcesadorEvidencia.validarPDF(Data("%PDF-".utf8) + Data(count: 10 * 1_024 * 1_024))
        }
    }
}
```

`PrototipoAppTests/Security/ArchivosEvidenciaTests.swift`:

```swift
//
//  ArchivosEvidenciaTests.swift
//  PrototipoAppTests
//

import Foundation
import Testing
@testable import PrototipoApp

struct ArchivosEvidenciaTests {
    let archivos = ArchivosEvidencia(carpeta: FileManager.default.temporaryDirectory.appending(path: "zs-ev-\(UUID().uuidString)"))

    @Test func temporalYConfirmado() throws {
        let adjunto = try archivos.guardarTemporal(Data([1, 2, 3]), tipo: "image/jpeg")
        #expect(adjunto.nombreArchivo.hasSuffix(".jpg"))
        #expect(try archivos.datos(de: adjunto) == Data([1, 2, 3]))
        let ruta = try archivos.confirmar(adjunto)
        #expect(try archivos.datos(ruta: ruta) == Data([1, 2, 3]))
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.datos(de: adjunto) }
    }

    @Test func rutasArbitrariasNoSeLeen() {
        for ruta in ["../zeroscam-demo.json", "/etc/passwd", "a/b.jpg", "foto.exe", ""] {
            #expect(throws: ErrorEvidencia.nombreInvalido) { try archivos.datos(ruta: ruta) }
        }
    }

    @Test func fueraDeRespaldos() throws {
        let ruta = try archivos.confirmar(try archivos.guardarTemporal(Data([9]), tipo: "application/pdf"))
        let url = archivos.carpeta.appending(path: ruta)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func limpiarTemporalesBorraLoNoEnviado() throws {
        let adjunto = try archivos.guardarTemporal(Data([1]), tipo: "image/jpeg")
        try archivos.limpiarTemporales()
        #expect(throws: ErrorEvidencia.noExiste) { try archivos.datos(de: adjunto) }
    }
}
```

- [ ] **Paso 2: Ver que fallan** — Run: `UNIT` → FAIL `cannot find 'ProcesadorEvidencia' in scope`.

- [ ] **Paso 3: Implementar `Security/ProcesadorEvidencia.swift`**

```swift
//
//  ProcesadorEvidencia.swift
//  PrototipoApp
//
//  Las fotos traen metadatos: ubicación GPS, fecha y modelo del teléfono. Antes de guardar una
//  evidencia se vuelve a dibujar la imagen (máx. 1600 px) y se codifica a JPEG sin copiar ningún
//  metadato. Los PDF se aceptan solo si empiezan con la firma %PDF- y pesan hasta 10 MB.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ErrorEvidencia: Error, Equatable, Sendable {
    case noEsImagen, muyGrande, noEsPDF, nombreInvalido, noExiste
}

nonisolated enum ProcesadorEvidencia {
    static let ladoMaximo = 1_600
    static let bytesMaximosImagen = 5 * 1_024 * 1_024
    static let bytesMaximosPDF = 10 * 1_024 * 1_024
    /// Lo que se acepta leer antes de procesar (una foto de 48 MP en HEIC cabe).
    static let bytesMaximosEntrada = 40 * 1_024 * 1_024

    static func limpiarImagen(_ datos: Data, ladoMaximo: Int = ladoMaximo) throws -> Data {
        guard datos.count <= bytesMaximosEntrada else { throw ErrorEvidencia.muyGrande }
        guard let fuente = CGImageSourceCreateWithData(datos as CFData, nil), CGImageSourceGetCount(fuente) > 0 else {
            throw ErrorEvidencia.noEsImagen
        }
        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respeta la orientación antes de tirar el EXIF
            kCGImageSourceThumbnailMaxPixelSize: ladoMaximo,
        ]
        guard let imagen = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary) else {
            throw ErrorEvidencia.noEsImagen
        }
        let salida = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(salida, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ErrorEvidencia.noEsImagen
        }
        // Solo la calidad: ningún diccionario de metadatos del original.
        CGImageDestinationAddImage(destino, imagen, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { throw ErrorEvidencia.noEsImagen }
        let resultado = salida as Data
        guard resultado.count <= bytesMaximosImagen else { throw ErrorEvidencia.muyGrande }
        return resultado
    }

    static func validarPDF(_ datos: Data) throws {
        guard datos.starts(with: Data("%PDF-".utf8)) else { throw ErrorEvidencia.noEsPDF }
        guard datos.count <= bytesMaximosPDF else { throw ErrorEvidencia.muyGrande }
    }
}
```

- [ ] **Paso 4: Implementar `Security/ArchivosEvidencia.swift`**

```swift
//
//  ArchivosEvidencia.swift
//  PrototipoApp
//
//  Archivos de evidencia y avatares en disco. Los nombres los genera la app (UUID + extensión):
//  nadie puede pedir "../" ni otra ruta. Se escriben cifrados por iOS (`.complete`) y fuera del
//  respaldo. Lo elegido y no enviado espera en "pendiente/" y se borra al arrancar.
//

import Foundation

nonisolated struct ArchivosEvidencia: Sendable {
    let carpeta: URL

    var temporal: URL { carpeta.appending(path: "pendiente", directoryHint: .isDirectory) }

    private static func extensionPara(_ tipo: String) -> String? {
        switch tipo {
        case "image/jpeg": "jpg"
        case "application/pdf": "pdf"
        default: nil
        }
    }

    /// Solo nombres como "3F2504E0-4F89-11D3-9A0C-0305E82C3301.jpg".
    private static func nombreValido(_ nombre: String) -> Bool {
        nombre.wholeMatch(of: /[A-F0-9\-]{36}\.(jpg|pdf)/) != nil
    }

    func guardarTemporal(_ datos: Data, tipo: String) throws -> Adjunto {
        guard let ext = Self.extensionPara(tipo) else { throw ErrorEvidencia.nombreInvalido }
        let id = UUID()
        let nombre = "\(id.uuidString).\(ext)"
        try escribir(datos, en: temporal.appending(path: nombre))
        return Adjunto(id: id, nombreArchivo: nombre, tipoArchivo: tipo, bytes: datos.count)
    }

    func datos(de adjunto: Adjunto) throws -> Data {
        guard Self.nombreValido(adjunto.nombreArchivo) else { throw ErrorEvidencia.nombreInvalido }
        return try leer(temporal.appending(path: adjunto.nombreArchivo))
    }

    func borrarTemporal(_ adjunto: Adjunto) throws {
        guard Self.nombreValido(adjunto.nombreArchivo) else { throw ErrorEvidencia.nombreInvalido }
        try? FileManager.default.removeItem(at: temporal.appending(path: adjunto.nombreArchivo))
    }

    /// Mueve el archivo de "pendiente/" a la carpeta definitiva y devuelve su ruta (solo el nombre).
    func confirmar(_ adjunto: Adjunto) throws -> String {
        guard Self.nombreValido(adjunto.nombreArchivo) else { throw ErrorEvidencia.nombreInvalido }
        let origen = temporal.appending(path: adjunto.nombreArchivo)
        guard FileManager.default.fileExists(atPath: origen.path()) else { throw ErrorEvidencia.noExiste }
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let destino = carpeta.appending(path: adjunto.nombreArchivo)
        try FileManager.default.moveItem(at: origen, to: destino)
        try excluirDeRespaldo(destino)
        return adjunto.nombreArchivo
    }

    func datos(ruta: String) throws -> Data {
        guard Self.nombreValido(ruta) else { throw ErrorEvidencia.nombreInvalido }
        return try leer(carpeta.appending(path: ruta))
    }

    func borrar(ruta: String) throws {
        guard Self.nombreValido(ruta) else { throw ErrorEvidencia.nombreInvalido }
        try? FileManager.default.removeItem(at: carpeta.appending(path: ruta))
    }

    func limpiarTemporales() throws {
        guard FileManager.default.fileExists(atPath: temporal.path()) else { return }
        try FileManager.default.removeItem(at: temporal)
    }

    func borrarTodo() throws {
        guard FileManager.default.fileExists(atPath: carpeta.path()) else { return }
        try FileManager.default.removeItem(at: carpeta)
    }

    private func escribir(_ datos: Data, en url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datos.write(to: url, options: [.atomic, .completeFileProtection])
        try excluirDeRespaldo(url)
    }

    private func leer(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path()) else { throw ErrorEvidencia.noExiste }
        return try Data(contentsOf: url)
    }

    private func excluirDeRespaldo(_ url: URL) throws {
        var u = url
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        try u.setResourceValues(valores)
    }
}
```

- [ ] **Paso 5: Pruebas** — Run: `UNIT` (suites `ProcesadorEvidenciaTests`, `ArchivosEvidenciaTests`) → verde.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Security PrototipoAppTests/Security
git commit -m "feat: evidencia sin metadatos y archivos protegidos sin rutas arbitrarias"
```

**Criterios de aceptación:** una foto con GPS sale sin GPS ni modelo de cámara; ninguna ruta inventada se lee.
**Dependencias:** D1. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea S7: Modelo de amenazas y auditoría final de seguridad

**Objetivo:** dejar documentado lo que se protege, cómo y lo que queda fuera, y comprobar con búsquedas que no se coló nada inseguro.

**Archivos:**
- Crear: `docs/seguridad.md`

**Interfaces:**
- Consume: todo lo anterior.
- Produce: `docs/seguridad.md` (lo enlaza el README de M1).

- [ ] **Paso 1: Escribir `docs/seguridad.md`** con: (1) la tabla de controles de 4.1 con enlaces a archivos; (2) la tabla STRIDE de 4.2; (3) riesgos aceptados; (4) qué cambia cuando se use el backend real (hash bcrypt/argon2 en el servidor, JWT de 15 min, refresh rotado, límite por IP, bitácora); (5) privacidad y LFPDPPP: datos, finalidades, ARCO en la app; (6) cómo reproducir cada control en la demo (por ejemplo, "5 intentos fallidos con usuario@0fraude.mx").

- [ ] **Paso 2: Auditoría por búsqueda** — cada comando debe dar 0 resultados:

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI"
grep -rn -e '"admin"' -e 'Alerta#2026' -e 'Revisa#2026' -e 'Equipo#2026' PrototipoApp          # credenciales
grep -rn -e 'print(' -e 'NSLog(' PrototipoApp                                                   # logs
grep -rn -e 'try!' -e 'fatalError(' PrototipoApp                                                # crashes
grep -rn 'NSAllowsArbitraryLoads' PrototipoApp                                                  # ATS abierto
grep -rn -e 'openURL' -e 'Link(' PrototipoApp/Views                                             # abrir enlaces
grep -rn 'LocalizedStringKey(' PrototipoApp                                                     # Markdown inyectable
grep -rn 'precondition(' PrototipoApp | grep -v 'Security/Aleatorio.swift'                       # solo la excepción documentada
```

- [ ] **Paso 3: Revisión con la skill `lfpdppp-compliance`** sobre `PrivacyNoticeView`, `PrivacyView` y `DeleteAccountView`; anotar en `docs/seguridad.md` lo que señale y lo que se decide no hacer en el prototipo.

- [ ] **Paso 4: Commit**

```bash
git add docs/seguridad.md
git commit -m "docs: modelo de amenazas STRIDE y controles de seguridad"
```

**Criterios de aceptación:** las 7 búsquedas sin resultados; `docs/seguridad.md` cubre cada fila de STRIDE con su mitigación y su riesgo residual.
**Dependencias:** F21, R2. **Esfuerzo:** M. **Riesgo:** bajo.

---

## 5. Validación y estados de UI

### 5.1 Reglas por campo (resumen; el código y las pruebas están en S3)

| Formulario | Campo | Regla | Mensaje |
|---|---|---|---|
| Registro / Editar perfil | Nombre, apellido | 2–50 letras, espacios, apóstrofo o guion | "Escribe tu nombre (2 a 50 letras)." / "Escribe tu apellido (2 a 50 letras)." |
| | País | De la lista | "Elige un país de la lista." |
| | Usuario (alias) | 3–20: `a-z 0-9 _ .`; único | "El usuario lleva de 3 a 20 caracteres: minúsculas, números, punto o guion bajo." / "Ese nombre de usuario ya está en uso." |
| | Correo | Formato, ≤ 150, sin `..`; único | "Escribe un correo válido, por ejemplo nombre@dominio.com." / "Ese correo ya tiene una cuenta. Inicia sesión." |
| | Contraseña (nueva) | 10–64, letra y número, no común, sin usuario ni correo | 4 mensajes de S3 |
| | Confirmación | Igual a la contraseña | "Las contraseñas no coinciden." |
| | Aviso | Marcado | "Acepta el aviso de privacidad para crear tu cuenta." |
| | Biografía | ≤ 300 | "La biografía admite hasta 300 caracteres." |
| Login | Correo y contraseña | No vacíos (sin revelar la política) | Botón deshabilitado; error del servidor genérico |
| Dos pasos | Código | 6 dígitos | "El código tiene 6 dígitos." |
| Reportar | Ciudad | 2–60 | "Indica la ciudad donde ocurrió (2 a 60 caracteres)." |
| | Persona afectada | Nombre 2–100, contacto teléfono o correo, autorización | 3 mensajes de S3 |
| | Tipo "Otro" | 3–50 | "Especifica el tipo de fraude (3 a 50 caracteres)." |
| | Título | 10–120 | "El título debe tener entre 10 y 120 caracteres." |
| | Fecha | No futura, ≤ 1 año | "La fecha no puede ser futura ni de hace más de un año." |
| | URL o texto | Si parece enlace: solo http/https válido; ≤ 2048 | "Solo se aceptan enlaces http:// o https:// válidos." |
| | Descripción | 20–2000 | "Describe lo ocurrido (20 a 2000 caracteres)." |
| | Evidencia | ≤ 3; JPEG ≤ 5 MB, PDF ≤ 10 MB | "Máximo 3 archivos de evidencia." / mensajes de F10 |
| Comentario | Texto | 2–500 | "El comentario debe tener entre 2 y 500 caracteres." |
| Moderación | Riesgo / motivo | Riesgo al validar; motivo 10–500 al rechazar | 2 mensajes de S3 |

Comportamiento común: el error de un campo aparece **al salir del campo** (no mientras se escribe); el campo con error tiene borde rojo y el mensaje debajo; el botón principal está deshabilitado mientras haya errores y debajo dice qué falta; el servidor repite la validación y sus mensajes salen en un `AvisoBanner` rojo.

### 5.2 Estados de cada lista

| Lista | Cargando | Vacío | Error |
|---|---|---|---|
| Inicio · Alertas críticas | `ProgressView` | "Sin alertas críticas" | "Reintentar" |
| Buscar · Categorías / Resultados | sí | "Sin resultados" + "Limpiar filtros" | "Reintentar" |
| Perfil · Mis reportes / Guardados | sí | "Aún no has reportado" / "Sin guardados" | "Reintentar" |
| Detalle / Comentarios | sí | "Sin comentarios" | "Este contenido ya no está disponible." / "Reintentar" |
| Notificaciones | sí | "Sin notificaciones" | "Reintentar" |
| Estadísticas | sí | — | "Reintentar" |
| Moderación / Usuarios | sí | "Nada por revisar" | "Reintentar" (incluye "No tienes permiso…") |

### 5.3 Confirmaciones en acciones destructivas

| Acción | Confirmación | Tarea |
|---|---|---|
| Eliminar reporte | Alerta con texto distinto si es público | F11 |
| Eliminar comentario | Alerta "No se puede deshacer." | F8 |
| Eliminar cuenta | Contraseña + escribir ELIMINAR + alerta | F21 |
| Suspender cuenta (Owner) | Diálogo con botón destructivo | F17 |
| Restablecer datos demo | Alerta | F17 |
| Cerrar sesión | Pantalla propia (Cerrar sesión / Cancelar) | F3 |
| Cambiar estado de un reporte | Diálogo "¿Cambiar a …?" | F15 |
| Quitar de guardados, quitar evidencia antes de enviar | Sin confirmación (se puede deshacer al instante) | F11, F10 |

### Tarea V1: Componentes de formulario y de estado

**Objetivo:** las piezas compartidas que usan todas las pantallas nuevas: campos con error, campo de contraseña con mostrar/ocultar, editor con contador, casilla, botón que no se toca dos veces, avisos, chips, y la vista de cargando/vacío/error.

**Archivos:**
- Modificar: `PrototipoApp/Theme/Components.swift` (`OfraudeTextField`, `LabeledTextField`; nuevos `ofraudeFont`, `ofraudeCampo`, `enfoque`, `identificador`)
- Crear: `PrototipoApp/Theme/Formularios.swift`
- Crear: `PrototipoApp/Theme/EstadosVista.swift`
- Crear: `PrototipoApp/Theme/Theme+Dominio.swift`

**Interfaces:**
- Consume: D2 (`Carga`), S3 (`Campo`), D1 (`NivelRiesgo`, `EstadoReporte`).
- Produce: `View.ofraudeFont(_:_:)`, `View.ofraudeCampo(error:)`, `View.enfoque(_:_:)`, `View.identificador(_:)`; `OfraudeTextField(placeholder:text:keyboard:contenido:error:maximo:foco:campo:identificador:)`; `LabeledTextField(label:placeholder:text:keyboard:contenido:error:maximo:foco:campo:identificador:)`; `FieldError(mensaje:)`; `OfraudeSecureField(placeholder:text:contenido:error:foco:campo:identificador:)`; `LabeledSecureField(label:placeholder:text:contenido:error:foco:campo:identificador:)`; `OfraudeTextEditor(placeholder:text:maximo:altura:error:foco:campo:identificador:)`; `CasillaVerificacion(texto:marcado:identificador:)`; `BotonAccion(titulo:icono:estilo:habilitado:identificador:accion:)`; `ResumenErrores(errores:tono:)`; `AvisoBanner(texto:tono:)` con `AvisoBanner.Tono` (`.info`, `.exito`, `.error`); `ChipEtiqueta(titulo:activo:)`; `ChipFiltro(titulo:activo:identificador:accion:)`; `EstadoVacio(icono:titulo:mensaje:)`; `CargaView(carga:esVacio:vacio:reintentar:contenido:)`; `EstadoVacioView(estado:)`; `ErrorEstadoView(mensaje:reintentar:)`; `LaunchGateView`; `PrivacyShield`; `NivelRiesgo.color`, `EstadoReporte.color`.

- [ ] **Paso 1: `Theme/Components.swift`** — reemplazar `OfraudeTextField` y `LabeledTextField`, y agregar al final:

```swift
/// Campo de texto con el estilo de 0Fraude (antes `applyOfraudeStyle()`): fondo, borde de 1 pt,
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
            FieldLabel(label)
            OfraudeTextField(placeholder: placeholder, text: $text, keyboard: keyboard, contenido: contenido,
                             error: error != nil, maximo: maximo, foco: foco, campo: campo, identificador: identificador)
            FieldError(mensaje: error)
        }
    }
}
```

```swift
extension View {
    /// Fuente del sistema con el tamaño y peso del storyboard. U1 la hace crecer con Dynamic Type.
    func ofraudeFont(_ tamano: CGFloat, _ peso: Font.Weight = .regular) -> some View {
        font(.system(size: tamano, weight: peso))
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

    /// Identificador para XCUITest (sin efecto visible).
    @ViewBuilder func identificador(_ id: String?) -> some View {
        if let id { accessibilityIdentifier(id) } else { self }
    }
}
```

- [ ] **Paso 2: Crear `Theme/Formularios.swift`**

```swift
//
//  Formularios.swift
//  PrototipoApp
//
//  Piezas de formulario que se repiten en Registro, Login, Reportar, Perfil y Moderación:
//  errores bajo el campo, contraseñas ocultas, editor con contador, casilla, botón que no se
//  puede tocar dos veces, avisos y chips.
//

import SwiftUI

/// Mensaje de error bajo un campo. Rojo claro (`dangerText`) porque el rojo de marca no llega
/// al contraste mínimo como texto pequeño sobre el fondo azul.
struct FieldError: View {
    let mensaje: String?

    var body: some View {
        if let mensaje {
            Text(mensaje)
                .ofraude(12, .medium, color: Theme.dangerText)
                .accessibilityLabel("Error: \(mensaje)")
                .transition(.opacity)
        }
    }
}

/// Contraseña oculta por defecto, con botón de ojo para verla. El estado visible no se guarda.
struct OfraudeSecureField: View {
    let placeholder: String
    @Binding var text: String
    var contenido: UITextContentType = .password
    var error = false
    var foco: FocusState<Campo?>.Binding? = nil
    var campo: Campo? = nil
    var identificador: String? = nil

    @State private var visible = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if visible {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.textMuted))
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.textMuted))
                }
            }
            .textContentType(contenido)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .ofraudeFont(15)
            .foregroundStyle(Theme.textLight)
            .tint(Theme.accent)
            .enfoque(foco, campo)
            .identificador(identificador)

            Button {
                visible.toggle()
                // Al cambiar entre SecureField y TextField se pierde el foco; se devuelve.
                if let foco, let campo { foco.wrappedValue = campo }
            } label: {
                Symbol(visible ? "eye.slash" : "eye", size: 18, color: Theme.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(visible ? "Ocultar contraseña" : "Mostrar contraseña")
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 48)
        .ofraudeCampo(error: error)
    }
}

struct LabeledSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var contenido: UITextContentType = .password
    var error: String? = nil
    var foco: FocusState<Campo?>.Binding? = nil
    var campo: Campo? = nil
    var identificador: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(label)
            OfraudeSecureField(placeholder: placeholder, text: $text, contenido: contenido, error: error != nil,
                               foco: foco, campo: campo, identificador: identificador)
            FieldError(mensaje: error)
        }
    }
}

/// Texto largo con placeholder encima (como el `UITextView` del original) y contador de caracteres.
struct OfraudeTextEditor: View {
    let placeholder: String
    @Binding var text: String
    let maximo: Int
    var altura: CGFloat = 120
    var error: String? = nil
    var foco: FocusState<Campo?>.Binding? = nil
    var campo: Campo? = nil
    var identificador: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .ofraudeFont(16)
                .foregroundStyle(Theme.textLight)
                .tint(Theme.accent)
                .scrollContentBackground(.hidden)
                .enfoque(foco, campo)
                .identificador(identificador)
                .accessibilityLabel(placeholder)
                .padding(4)
                .frame(minHeight: altura)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .ofraude(16, color: Theme.textMuted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .ofraudeCard()
                .overlay { if error != nil { Rectangle().strokeBorder(Theme.danger, lineWidth: 1) } }
            HStack(alignment: .top) {
                FieldError(mensaje: error)
                Spacer(minLength: 8)
                Text(verbatim: "\(text.count)/\(maximo)")
                    .ofraude(11, color: Theme.textMuted)
                    .accessibilityLabel("\(text.count) de \(maximo) caracteres")
            }
        }
        .onChange(of: text) { _, nuevo in
            if nuevo.count > maximo { text = String(nuevo.prefix(maximo)) }
        }
    }
}

/// Casilla para aceptar algo (aviso de privacidad, autorización de un tercero).
struct CasillaVerificacion: View {
    let texto: String
    @Binding var marcado: Bool
    var identificador: String? = nil

    var body: some View {
        Button { marcado.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Symbol(marcado ? "checkmark.square.fill" : "square", size: 22, color: marcado ? Theme.accent : Theme.textMuted)
                Text(texto).ofraude(13, color: Theme.textLight).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(marcado ? .isSelected : [])
        .accessibilityValue(marcado ? "Marcado" : "Sin marcar")
        .identificador(identificador)
    }
}

/// Botón de una acción que tarda: muestra un indicador mientras trabaja y no se puede tocar dos
/// veces (evita reportes o comentarios duplicados).
struct BotonAccion: View {
    let titulo: String
    var icono: String? = nil
    var estilo = OfraudeButtonStyle()
    var habilitado = true
    var identificador: String? = nil
    let accion: () async -> Void

    @State private var trabajando = false

    var body: some View {
        Button {
            guard !trabajando else { return }
            trabajando = true
            Task {
                await accion()
                trabajando = false
            }
        } label: {
            ZStack {
                Group {
                    if let icono { Symbol(icono, size: 20, color: estilo.foreground) } else { Text(titulo) }
                }
                .opacity(trabajando ? 0 : 1)
                if trabajando { ProgressView().tint(estilo.foreground) }
            }
        }
        .buttonStyle(estilo)
        .disabled(!habilitado || trabajando)
        .opacity(habilitado ? 1 : 0.45)
        .accessibilityLabel(titulo)
        .identificador(identificador)
    }
}

/// Aviso en una franja de color (cuenta creada, sesión expirada, error del servidor).
struct AvisoBanner: View {
    enum Tono { case info, exito, error }

    let texto: String
    var tono: Tono = .info

    private var color: Color {
        switch tono {
        case .info: Theme.info
        case .exito: Theme.success
        case .error: Theme.dangerText
        }
    }

    private var icono: String {
        switch tono {
        case .info: "info.circle.fill"
        case .exito: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Symbol(icono, size: 18, color: color).accessibilityHidden(true)
            Text(texto).ofraude(13, .medium, color: Theme.textLight)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Lista de mensajes (mismo patrón que `ResumenErrores` de la práctica Demo-RetoSwiftUI452).
/// `.info` sirve para mostrar reglas antes de que haya errores.
struct ResumenErrores: View {
    let errores: [String]
    var tono: AvisoBanner.Tono = .error

    var body: some View {
        if !errores.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(errores, id: \.self) { e in
                    HStack(alignment: .top, spacing: 6) {
                        Symbol(tono == .error ? "exclamationmark.circle" : "info.circle", size: 13,
                               color: tono == .error ? Theme.dangerText : Theme.textMuted)
                        Text(e).ofraude(13, color: tono == .error ? Theme.dangerText : Theme.textMuted)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// El aspecto de un chip (#Descuentos): el del storyboard, con borde naranja cuando está activo.
struct ChipEtiqueta: View {
    let titulo: String
    let activo: Bool

    var body: some View {
        Text(titulo)
            .ofraude(12, activo ? .semibold : .regular, color: activo ? Theme.accent : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(activo ? Theme.selected : Theme.card)
            .overlay(Rectangle().strokeBorder(activo ? Theme.accent : Theme.defaultBorder, lineWidth: 1))
    }
}

struct ChipFiltro: View {
    let titulo: String
    let activo: Bool
    var identificador: String? = nil
    let accion: () -> Void

    var body: some View {
        Button(action: accion) { ChipEtiqueta(titulo: titulo, activo: activo) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(activo ? .isSelected : [])
            .identificador(identificador)
    }
}

#Preview("Formularios") {
    @Previewable @State var texto = ""
    @Previewable @State var marcado = false
    VStack(alignment: .leading, spacing: 16) {
        LabeledTextField(label: "CORREO", placeholder: "tucorreo@ejemplo.com", text: $texto, error: "Escribe un correo válido.")
        LabeledSecureField(label: "CONTRASEÑA", placeholder: "••••••••", text: $texto)
        CasillaVerificacion(texto: "Acepto el aviso de privacidad.", marcado: $marcado)
        AvisoBanner(texto: "Cuenta creada. Inicia sesión para continuar.", tono: .exito)
        BotonAccion(titulo: "ENVIAR") { try? await Task.sleep(for: .seconds(1)) }
        HStack { ChipFiltro(titulo: "#Descuentos", activo: true) {}; ChipFiltro(titulo: "#SorteoFalso", activo: false) {} }
    }
    .padding()
    .ofraudeScreen()
}
```

- [ ] **Paso 3: Crear `Theme/EstadosVista.swift`**

```swift
//
//  EstadosVista.swift
//  PrototipoApp
//
//  Cargando, vacío y error para cualquier lista (`CargaView`), la pantalla de arranque mientras
//  se revisa la sesión y el escudo que tapa la app en el selector de apps.
//

import SwiftUI

struct EstadoVacio {
    let icono: String
    let titulo: String
    let mensaje: String
}

struct CargaView<Valor, Contenido: View>: View {
    let carga: Carga<Valor>
    var esVacio: (Valor) -> Bool = { _ in false }
    var vacio = EstadoVacio(icono: "tray", titulo: "Sin datos", mensaje: "")
    let reintentar: () async -> Void
    @ViewBuilder let contenido: (Valor) -> Contenido

    var body: some View {
        switch carga {
        case .cargando:
            ProgressView()
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel("Cargando")
        case .error(let mensaje):
            ErrorEstadoView(mensaje: mensaje, reintentar: reintentar)
        case .listo(let valor):
            if esVacio(valor) { EstadoVacioView(estado: vacio) } else { contenido(valor) }
        }
    }
}

struct EstadoVacioView: View {
    let estado: EstadoVacio

    var body: some View {
        VStack(spacing: 8) {
            Symbol(estado.icono, size: 32, color: Theme.textSlate)
            Text(estado.titulo).ofraude(16, .semibold, color: Theme.textLight)
            if !estado.mensaje.isEmpty {
                Text(estado.mensaje).ofraude(13, color: Theme.textMuted).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorEstadoView: View {
    let mensaje: String
    let reintentar: () async -> Void

    var body: some View {
        VStack(spacing: 10) {
            Symbol("exclamationmark.triangle", size: 32, color: Theme.dangerText)
            Text(mensaje).ofraude(14, color: Theme.textLight).multilineTextAlignment(.center)
            BotonAccion(titulo: "REINTENTAR",
                        estilo: OfraudeButtonStyle(background: Theme.card, foreground: Theme.accent, size: 14,
                                                   weight: .semibold, radius: 8, height: 44, fullWidth: false),
                        identificador: "estado.reintentar") {
                await reintentar()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Mientras se revisa el token guardado (un instante al abrir la app).
struct LaunchGateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("0FRAUDE").ofraude(28, .bold, color: Theme.accent)
            ProgressView().tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ofraudeScreen()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("0Fraude, cargando")
    }
}

/// Lo que se ve en el selector de apps: iOS guarda una captura al salir de primer plano.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Symbol("lock.shield.fill", size: 48, color: Theme.accent)
                Text("0FRAUDE").ofraude(24, .bold, color: Theme.textPrimary)
            }
        }
        .accessibilityHidden(true)
    }
}
```

- [ ] **Paso 4: Crear `Theme/Theme+Dominio.swift`**

```swift
//
//  Theme+Dominio.swift
//  PrototipoApp
//
//  Color de cada nivel de riesgo y de cada estado. Riesgo alto en `dangerText`: el rojo de marca
//  como texto pequeño no llega al contraste mínimo sobre el fondo azul.
//

import SwiftUI

extension NivelRiesgo {
    var color: Color {
        switch self {
        case .muyAlto, .alto: Theme.dangerText
        case .medio: Theme.accent
        case .bajo: Theme.info
        case .noEvaluado: Theme.textSlate
        }
    }
}

extension EstadoReporte {
    var color: Color {
        switch self {
        case .recibido: Theme.textSlate
        case .enRevision: Theme.accent
        case .validado: Theme.success
        case .rechazado: Theme.dangerText
        case .canalizado: Theme.info
        }
    }
}
```

- [ ] **Paso 5: Verificar** — Run: `BUILD` → `** BUILD SUCCEEDED **` (las vistas actuales siguen compilando: los parámetros nuevos tienen valor por defecto); `UNIT` en verde. Abrir el `#Preview("Formularios")` en Xcode y revisar a ojo: borde rojo con error, ojo de la contraseña, indicador del botón.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp/Theme
git commit -m "feat: componentes de formulario, estados de carga y colores de dominio"
```

**Criterios de aceptación:** compila sin cambiar ninguna pantalla; el preview muestra cada pieza.
**Dependencias:** D2, S3. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea V2: Pasada de estados y confirmaciones

**Objetivo:** comprobar que cada lista de 5.2 usa `CargaView` y cada acción de 5.3 confirma, y poder mostrar el estado de error en la demo y en pruebas.

**Archivos:**
- Modificar: `PrototipoApp/App/AppConfig.swift` (`simularFallaDeRed`)
- Modificar: `PrototipoApp/Data/Demo/DemoBackend.swift` (lecturas que fallan a propósito en pruebas)
- Modificar: `PrototipoApp/App/Dependencies.swift`
- Test: `PrototipoAppUITests/EstadosUITests.swift` (crear), `PrototipoAppTests/App/AppConfigTests.swift`

**Interfaces:**
- Consume: F4–F17, D8.
- Produce: argumento de arranque `-simularFallaDeRed` (solo DEBUG y `-uiTesting`); `AppConfig.simularFallaDeRed`; `DemoBackend(servidor:secretos:fallarLecturas:)`.

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppUITests/EstadosUITests.swift`:

```swift
//
//  EstadosUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class EstadosUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSinRedSeVeElErrorConReintentar() {
        let app = XCUIApplication.zeroScam(extra: ["-simularFallaDeRed"])
        app.launch()
        app.entrar()
        XCTAssertTrue(app.elemento(contiene: "No se pudo conectar con el servidor").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["estado.reintentar"].firstMatch.exists)
        capturar(app, "13-error-sin-red")
    }

    @MainActor
    func testGuardadosVaciosMuestranElEstadoVacio() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.segmento.guardados"].tap()
        app.buttons["perfil.quitarGuardado.101"].tap()
        app.buttons["perfil.quitarGuardado.102"].tap()
        XCTAssertTrue(app.elemento(contiene: "Sin guardados").waitForExistence(timeout: 5))
    }
}
```

Y en `AppConfigTests`:

```swift
    @Test func laFallaDeRedSoloExisteEnPruebasDeInterfaz() {
        #expect(!AppConfig.actual(info: [:], argumentos: ["-simularFallaDeRed"]).simularFallaDeRed)
        #expect(AppConfig.actual(info: [:], argumentos: ["-uiTesting", "-simularFallaDeRed"]).simularFallaDeRed)
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UNIT` → FAIL `value of type 'AppConfig' has no member 'simularFallaDeRed'`.

- [ ] **Paso 3: Implementar.** En `AppConfig` agregar `let simularFallaDeRed: Bool` y pasarlo en las tres construcciones que existen: `porDefecto` (`false`), `actual(...)` (`esUITest && argumentos.contains("-simularFallaDeRed")`, dentro de `#if DEBUG`; en Release `false`) y `entornoDePrueba()` en `OFraudeApp.swift` (`false`). En `DemoBackend` agregar `var fallarLecturas = false` y un ayudante:

```swift
    /// Solo pruebas de interfaz: las lecturas fallan como si no hubiera red, para ver el estado de error.
    private func leer<T>(_ operacion: () async throws -> T) async throws -> T {
        if fallarLecturas { throw AppError.sinConexion }
        return try await operacion()
    }
```

y envolver con `try await leer { … }` las lecturas `feed`, `misReportes`, `guardados`, `detalle`, `comentarios`, `estadisticas`, `categorias` y `notificaciones` (el inicio de sesión no, para poder entrar). En `Dependencies.crear`: `DemoBackend(servidor: servidor, secretos: secretos, fallarLecturas: config.simularFallaDeRed)`.

- [ ] **Paso 4: Revisión de cobertura** — cada búsqueda debe coincidir con la tabla 5.2/5.3:

```bash
grep -rln "CargaView(" PrototipoApp/Views | sort
grep -rn -e "role: .destructive" PrototipoApp/Views | wc -l
```

Expected: `CargaView` en HomeView, SearchView, ProfileView, ReportDetailView, ComentariosView, NotificationsView, CommunityStatsView, AdminQueueView, AdminReviewView y OwnerUsersView; al menos 7 botones destructivos.

- [ ] **Paso 5: Pruebas** — Run: `UNIT` y `UI` (clase `EstadosUITests`) → verde.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp PrototipoAppTests PrototipoAppUITests
git commit -m "test: estados de error y vacío comprobables en pruebas de interfaz"
```

**Criterios de aceptación:** AC4 cumplido; el error muestra "Reintentar" y al tocarlo vuelve a pedir.
**Dependencias:** F4–F17. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea V3: Teclado

**Objetivo:** en cada formulario, "Siguiente" lleva al siguiente campo, el último envía o cierra, "Listo" cierra el teclado en los editores largos, y el campo con foco nunca queda tapado.

**Archivos:**
- Modificar: `PrototipoApp/Theme/Components.swift` (ayudante `siguiente`)
- Modificar: `RegisterView.swift`, `EditProfileView.swift`, `ChangePasswordView.swift`, `ReportView.swift`, `AdminReviewView.swift` (orden del foco y "Listo")

**Interfaces:**
- Consume: V1 (`enfoque`), F1, F9, F15, F18, F19.
- Produce: `View.siguiente(_ foco: FocusState<Campo?>.Binding, _ campo: Campo?)`.

- [ ] **Paso 1: Ayudante** en `Components.swift`:

```swift
extension View {
    /// Tecla "Siguiente" que pasa al campo indicado; con `nil` la tecla dice "Listo" y cierra el teclado.
    func siguiente(_ foco: FocusState<Campo?>.Binding, _ campo: Campo?) -> some View {
        submitLabel(campo == nil ? .done : .next)
            .onSubmit { foco.wrappedValue = campo }
    }
}
```

- [ ] **Paso 2: Orden del foco** (agregar `.siguiente($foco, …)` a cada campo):
  - Registro: nombre → apellido → alias → correo → contraseña → confirmación → `nil`.
  - Editar perfil: nombre → apellido → alias → correo → biografía (editor: "Listo" en la barra del teclado).
  - Cambiar contraseña: actual → nueva → confirmación → `nil`.
  - Reportar: (persona nombre → contacto →) ciudad → tipoOtro (si aplica) → título → URL → descripción (editor).
  - Moderación: observaciones (editor).
  En las pantallas con `OfraudeTextEditor` (Editar perfil y Moderación; Reportar ya lo tiene desde F9) agregar:

```swift
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { foco = nil }
            }
        }
```

  y `.scrollDismissesKeyboard(.interactively)` en todo `ScrollView` con campos (ya está en Registro, Reportar, Detalle, Buscar, Editar perfil y Moderación; agregar en Cambiar contraseña y Eliminar cuenta).

- [ ] **Paso 3: Verificar** — Run: `BUILD` y `UI` completo → verde (las pruebas de interfaz ya tocan "Listo" en Reportar). Manual (Q3, punto teclado): con el teclado en pantalla del simulador (⌘K), recorrer Registro solo con "Siguiente" hasta el final; en Reportar el campo con foco siempre queda visible.

- [ ] **Paso 4: Commit**

```bash
git add PrototipoApp
git commit -m "feat: orden de foco y tecla siguiente en todos los formularios"
```

**Criterios de aceptación:** se puede llenar Registro y Cambiar contraseña sin tocar la pantalla entre campos.
**Dependencias:** F1, F9, F15, F18, F19. **Esfuerzo:** S. **Riesgo:** bajo.

---

## 6. Pulido de UX y accesibilidad

### 6.1 Ajustes visuales propuestos ("lo mismo pero con algunos ajustes")

La base sigue siendo el storyboard. Estos son los ajustes que el plan aplica (U6 los ejecuta salvo que Alex diga lo contrario); todos se anotan en `docs/CAMBIOS-vs-original.md`:

| # | Ajuste | Por qué | Dónde |
|---|---|---|---|
| 1 | Texto de los botones naranjas en azul marino (en modo oscuro) | Blanco sobre naranja ≈ 2.0:1 no pasa AA; azul marino ≈ 9:1 | `OfraudeButtonStyle` (`Theme.onAccent`) |
| 2 | Errores y riesgo alto en `dangerText` | `danger` como texto chico ≈ 3.9:1 | V1 |
| 3 | Títulos en las barras de las pantallas empujadas | VoiceOver y el botón de regreso dicen dónde estás | Cada tarea; U6 completa Ajustes y Guía |
| 4 | Campana con contador en Inicio en lugar del sello decorativo | Un ícono que parecía botón ahora es útil | F16 |
| 5 | Pie de tarjetas con íconos (confirmaciones y comentarios) | "CONFIRMADO · 340 · 12" no se entendía | F11 |
| 6 | "Hola, Ana." en lugar de "Bienvenido, Usuario." | Lenguaje neutro y personal | F4 |
| 7 | Ícono de la app y color de acento del sistema | `AppIcon.appiconset` no tiene imagen (ícono en blanco) y `AccentColor` está vacío (alertas y selectores salen en azul) | U6 |
| 8 | Bordes negros de tarjetas | Se conservan en oscuro; en claro usan `Theme.border` | U3 |

### Tarea U1: Dynamic Type y alturas que no cortan

**Objetivo:** que el texto crezca con el tamaño elegido en iOS (hasta `accessibility2`) sin cortar botones ni tarjetas.

**Archivos:**
- Modificar: `PrototipoApp/Theme/Components.swift` (`Text.ofraude`, `ofraudeFont`, `OfraudeButtonStyle`, `TopBar`)
- Modificar: `PrototipoApp/App/OFraudeApp.swift` (`RootView`: tope de tamaño)
- Modificar: las vistas con `frame(height:)` fijo (lista exacta con el `grep` del paso 3)
- Test: `PrototipoAppUITests/AccesibilidadUITests.swift` (crear)

**Interfaces:**
- Consume: V1.
- Produce: `Text.ofraude(_:_:color:)` devuelve `some View` (antes `Text`).

- [ ] **Paso 1: Prueba que falla** — `PrototipoAppUITests/AccesibilidadUITests.swift`:

```swift
//
//  AccesibilidadUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class AccesibilidadUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testTextoGrandeYHorizontal() {
        let app = XCUIApplication.zeroScam(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        app.launch()
        app.entrar()
        XCTAssertTrue(app.buttons["inicio.reportar"].isHittable)
        capturar(app, "14-texto-grande")
        app.tabBars.buttons["Reportar"].tap()
        app.buttons["reporte.enviar"].tocar(en: app, intentos: 20)
        XCTAssertTrue(app.buttons["reporte.enviar"].isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.tabBars.buttons["Inicio"].tap()
        XCTAssertTrue(app.buttons["inicio.reportar"].waitForExistence(timeout: 5))
        capturar(app, "15-horizontal")
        XCUIDevice.shared.orientation = .portrait
    }
}
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` (clase `AccesibilidadUITests`) → FAIL (con el tamaño grande los textos fijos no crecen y las alturas fijas cortan; si por casualidad pasa, revisar la captura `14-texto-grande` y seguir).

- [ ] **Paso 3: Fuente escalable.** En `Components.swift`:

```swift
/// Tamaño del storyboard que crece con Dynamic Type (relativo al estilo "body").
private struct FuenteEscalable: ViewModifier {
    @ScaledMetric private var tamano: CGFloat
    private let peso: Font.Weight

    init(_ tamano: CGFloat, peso: Font.Weight) {
        _tamano = ScaledMetric(wrappedValue: tamano, relativeTo: .body)
        self.peso = peso
    }

    func body(content: Content) -> some View {
        content.font(.system(size: tamano, weight: peso))
    }
}

extension Text {
    /// Tamaño, peso y color en una sola llamada (los tres datos del storyboard). Crece con Dynamic Type.
    func ofraude(_ size: CGFloat, _ weight: Font.Weight = .regular, color: Color) -> some View {
        foregroundStyle(color).modifier(FuenteEscalable(size, peso: weight))
    }
}

extension View {
    func ofraudeFont(_ tamano: CGFloat, _ peso: Font.Weight = .regular) -> some View {
        modifier(FuenteEscalable(tamano, peso: peso))
    }
}
```

(reemplazan las versiones anteriores). En `OfraudeButtonStyle.makeBody` cambiar `.font(.system(size: size, weight: weight))` por `.ofraudeFont(size, weight)` y `.frame(height: height)` por `.frame(minHeight: height)`. En `TopBar`, `.frame(height: 64)` por `.frame(minHeight: 64)`.

Run: `grep -rn "frame(height:" PrototipoApp` y cambiar cada resultado a `frame(minHeight:)` salvo los cuadrados de íconos (`frame(width:height:)`, que se quedan). Compilar: si alguna llamada a `.ofraude(...)` dependía de devolver `Text` (por ejemplo `Text + Text`), el compilador la marca; cambiarla a un solo `Text` con interpolación `verbatim`.

- [ ] **Paso 4: Tope.** En `RootView`, después de `.preferredColorScheme(...)`: `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` (más allá el diseño de tarjetas ya no tiene sentido; iOS sigue ofreciendo Zoom).

- [ ] **Paso 5: Pruebas** — Run: `UI` (clase `AccesibilidadUITests`) → verde; mirar `14-texto-grande` y `15-horizontal` al exportar capturas (Q3).

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: texto que crece con Dynamic Type y alturas mínimas en vez de fijas"
```

**Criterios de aceptación:** en `accessibilityXL` los botones principales se alcanzan desplazando y ningún texto queda cortado en Inicio, Reportar, Perfil y Detalle (revisión de capturas).
**Dependencias:** V1 y todas las F (toca sus vistas). **Esfuerzo:** M. **Riesgo:** medio (cambio transversal; por eso va después de las F).

### Tarea U2: VoiceOver

**Objetivo:** que cada control se entienda sin verlo: etiquetas en español en los botones de ícono, encabezados marcados, tarjetas combinadas con su pista, selección anunciada y decoración oculta.

**Archivos:**
- Modificar: las vistas que falten según la revisión del paso 1
- Test: `PrototipoAppUITests/AccesibilidadUITests.swift`

**Interfaces:**
- Consume: F1–F21.
- Produce: nada nuevo.

- [ ] **Paso 1: Revisión** — Run: `grep -rn -B2 -A6 "Symbol(" PrototipoApp/Views | grep -n "Button\|NavigationLink"` y comprobar que cada botón o enlace cuyo contenido es solo un `Symbol` tiene `.accessibilityLabel`. Lista esperada: campana (Inicio), engrane (Perfil), lápiz del avatar (Perfil), guardar y compartir (Detalle), publicar comentario (Detalle), opciones y quitar guardado (Perfil), quitar evidencia (Reportar), ojo (contraseñas). Además: sellos y escudos decorativos con `.accessibilityHidden(true)`; títulos de sección (`CATEGORÍAS COMUNES`, `ALERTAS CRÍTICAS`, `CATEGORÍAS PRINCIPALES`, `Modus Operandi`, `Comentarios…`) con `.accessibilityAddTraits(.isHeader)`; tarjetas tocables con `.accessibilityElement(children: .combine)` y `.accessibilityHint`.

- [ ] **Paso 2: Prueba** — agregar a `AccesibilidadUITests`:

```swift
    @MainActor
    func testLosBotonesDeIconoDicenQueHacen() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        XCTAssertTrue(app.buttons["inicio.notificaciones"].label.hasPrefix("Notificaciones"))
        app.buttons["inicio.alerta.101"].tocar(en: app)
        XCTAssertEqual(app.buttons["detalle.guardar"].label, "Quitar de guardados")
        XCTAssertEqual(app.buttons["detalle.compartir"].label, "Compartir alerta")
        app.buttons["detalle.publicar"].tocar(en: app)
        XCTAssertEqual(app.buttons["detalle.publicar"].label, "Publicar comentario")
        app.volverALaRaiz()
        app.tabBars.buttons["Perfil"].tap()
        XCTAssertEqual(app.buttons["perfil.ajustes"].label, "Ajustes")
        XCTAssertEqual(app.buttons["perfil.opciones.121"].label, "Opciones del reporte")
    }
```

- [ ] **Paso 3: Pruebas** — Run: `UI` (clase `AccesibilidadUITests`) → verde. Manual (Q3): Xcode → Open Developer Tool → Accessibility Inspector → "Run audit" en Inicio, Detalle, Reportar, Perfil y Ajustes; corregir lo que marque como "Element has no description" o "Contrast".

- [ ] **Paso 4: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: etiquetas y estructura para VoiceOver"
```

**Criterios de aceptación:** AC11 (etiquetas) y la auditoría del Accessibility Inspector sin "no description".
**Dependencias:** F1–F21. **Esfuerzo:** M. **Riesgo:** bajo.

### Tarea U3: Modo claro y oscuro

**Objetivo:** que el switch "Modo Oscuro" de Ajustes cambie de verdad la apariencia, con una paleta clara legible.

**Archivos:**
- Modificar: `PrototipoApp/Theme/Theme.swift` (colores adaptables, `onAccent`)
- Modificar: `PrototipoApp/Theme/Components.swift` (`OfraudeButtonStyle.foreground` por defecto `Theme.onAccent`)
- Modificar: `PrototipoApp/App/OFraudeApp.swift` (`preferredColorScheme` según la preferencia)
- Modificar: `PrototipoApp/Views/Account/SettingsView.swift` (switch real)
- Modificar: las vistas con `.white` literal que queden (paso 3)
- Test: `PrototipoAppUITests/AccesibilidadUITests.swift`

**Interfaces:**
- Consume: D9 (`Preferencias.modoOscuro`, `SessionStore.actualizarPreferencias`).
- Produce: `Color(oscuro:claro:)`, `Theme.onAccent`; identificador `ajustes.modoOscuro`.

- [ ] **Paso 1: Prueba que falla** — agregar a `AccesibilidadUITests`:

```swift
    @MainActor
    func testModoClaroSeGuarda() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.ajustes"].tap()
        let interruptor = app.switches["ajustes.modoOscuro"]
        interruptor.alternar()
        esperar(interruptor, valor: "0")
        capturar(app, "16-modo-claro")
        app.terminate()
        let otraVez = XCUIApplication.zeroScam(reiniciar: false)
        otraVez.launch()
        otraVez.tabBars.buttons["Perfil"].tap()
        otraVez.buttons["perfil.ajustes"].tap()
        esperar(otraVez.switches["ajustes.modoOscuro"], valor: "0")
    }
```

- [ ] **Paso 2: Ver que falla** — Run: `UI` → FAIL: no existe `ajustes.modoOscuro`.

- [ ] **Paso 3: Paleta.** En `Theme.swift`:

```swift
extension Color {
    /// El color del storyboard en modo oscuro y su par legible en modo claro.
    init(oscuro: Color, claro: Color) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .light ? UIColor(claro) : UIColor(oscuro) })
    }
}

enum Theme {
    // Fondos
    static let background = Color(oscuro: Color(r: 10, g: 19, b: 48), claro: Color(r: 244, g: 246, b: 251))
    static let card = Color(oscuro: Color(r: 18, g: 32, b: 74), claro: Color(r: 255, g: 255, b: 255))
    static let field = Color(oscuro: Color(r: 15, g: 26, b: 56), claro: Color(r: 236, g: 240, b: 248))
    static let selected = Color(oscuro: Color(r: 26, g: 42, b: 90), claro: Color(r: 255, g: 243, b: 224))
    static let avatarBackground = Color(oscuro: Color(r: 45, g: 53, b: 81), claro: Color(r: 203, g: 213, b: 225))

    // Bordes de campos y botones de selección
    static let border = Color(oscuro: Color(r: 42, g: 55, b: 104), claro: Color(r: 203, g: 213, b: 225))

    // Acentos (en claro, un naranja más oscuro para que el texto naranja sobre blanco pase AA ≈ 4.6:1)
    static let accent = Color(oscuro: Color(r: 245, g: 166, b: 35), claro: Color(r: 176, g: 96, b: 0))
    /// Texto sobre un fondo `accent`.
    static let onAccent = Color(oscuro: Color(r: 10, g: 19, b: 48), claro: Color(r: 255, g: 255, b: 255))
    static let danger = Color(r: 225, g: 29, b: 72)
    static let dangerText = Color(oscuro: Color(r: 255, g: 75, b: 75), claro: Color(r: 190, g: 18, b: 60))
    static let info = Color(oscuro: Color(r: 0, g: 188, b: 212), claro: Color(r: 0, g: 131, b: 143))
    static let success = Color(oscuro: Color(r: 76, g: 175, b: 80), claro: Color(r: 46, g: 125, b: 50))

    // Textos
    static let textPrimary = Color(oscuro: Color(r: 248, g: 249, b: 250), claro: Color(r: 15, g: 23, b: 42))
    static let textLight = Color(oscuro: Color(r: 219, g: 225, b: 255), claro: Color(r: 30, g: 41, b: 59))
    static let textMuted = Color(oscuro: Color(r: 156, g: 163, b: 175), claro: Color(r: 71, g: 85, b: 105))
    static let textSlate = Color(oscuro: Color(r: 148, g: 163, b: 184), claro: Color(r: 71, g: 85, b: 105))
    static let textSection = Color(oscuro: Color(r: 176, g: 179, b: 185), claro: Color(r: 100, g: 116, b: 139))
    static let textSubtle = Color(oscuro: Color(r: 119, g: 136, b: 179), claro: Color(r: 100, g: 116, b: 139))

    /// En UIKit un borde sin color se dibuja negro; se conserva en oscuro. En claro, el borde suave.
    static let defaultBorder = Color(oscuro: .black, claro: Color(r: 203, g: 213, b: 225))
}
```

Run: `grep -rn -e "color: \.white" -e "Color\.white" -e "foregroundStyle(\.white)" -e "foreground: \.white" PrototipoApp` y cambiar cada resultado a `Theme.textPrimary` (o `Theme.onAccent` si es texto sobre naranja). En `OfraudeButtonStyle`: `var foreground: Color = Theme.onAccent`.

- [ ] **Paso 4: Switch y raíz.** En `RootView`: `.preferredColorScheme(session.usuario?.preferencias.modoOscuro == false ? .light : .dark)` (sin sesión, oscuro como el original). En `SettingsView`, quitar `@State private var darkMode = true` y:

```swift
                    toggleRow("Modo Oscuro", isOn: Binding(
                        get: { session.usuario?.preferencias.modoOscuro ?? true },
                        set: { nuevo in Task { await cambiarModo(nuevo) } }), id: "ajustes.modoOscuro")
```

```swift
    private func cambiarModo(_ oscuro: Bool) async {
        guard var p = session.usuario?.preferencias else { return }
        p.modoOscuro = oscuro
        do { try await session.actualizarPreferencias(p) } catch { aviso = error.mensajeUsuario }
    }
```

- [ ] **Paso 5: Pruebas y revisión** — Run: `UI` → verde. Manual: recorrer Inicio, Buscar, Reportar, Perfil, Detalle y Ajustes en claro; con el Accessibility Inspector revisar contraste en Inicio y Reportar.

- [ ] **Paso 6: Commit**

```bash
git add PrototipoApp PrototipoAppUITests
git commit -m "feat: modo claro y oscuro con paleta adaptable"
```

**Criterios de aceptación:** el modo persiste por cuenta; ningún texto blanco sobre fondo claro; botones naranjas legibles en ambos.
**Dependencias:** F1–F21, D9. **Esfuerzo:** L. **Riesgo:** medio. **Plan B (si no hay tiempo):** dejar la app oscura fija (D10 ya lo hace) y convertir el switch en un renglón informativo "Apariencia · Oscuro" (S).

### Tarea U4: Horizontal y ancho legible

**Objetivo:** en horizontal (y en iPad, que el target ya permite) el contenido no se estira de lado a lado.

**Archivos:**
- Modificar: `PrototipoApp/Theme/Components.swift` (`contenidoLegible()`)
- Modificar: las pantallas con `ScrollView` principal (Inicio, Buscar, Reportar, Perfil, Detalle, Ajustes, Privacidad, Registro, Login, Guía, Artículo, Estadísticas, Notificaciones, Moderación)

**Interfaces:**
- Produce: `View.contenidoLegible()`.

- [ ] **Paso 1: Ayudante** en `Components.swift`:

```swift
extension View {
    /// Máximo 640 pt de ancho, centrado: en horizontal o en iPad las líneas no se vuelven eternas.
    func contenidoLegible() -> some View {
        frame(maxWidth: 640).frame(maxWidth: .infinity)
    }
}
```

- [ ] **Paso 2: Aplicarlo** al `VStack` principal dentro de cada `ScrollView` listado (después de sus `.padding`).

- [ ] **Paso 3: Verificar** — Run: `UI` (clase `AccesibilidadUITests`, ya rota a horizontal) → verde; revisar `15-horizontal`. Manual: rotar en Detalle y Reportar.

- [ ] **Paso 4: Commit**

```bash
git add PrototipoApp
git commit -m "feat: ancho legible en horizontal"
```

**Criterios de aceptación:** en horizontal el texto no pasa de 640 pt de ancho y nada se encima.
**Dependencias:** U1. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea U5: Animaciones, transiciones y respuesta háptica

**Objetivo:** cambios suaves en listas y contadores, vibración de éxito al enviar un reporte, y nada de movimiento si la persona activó "Reducir movimiento".

**Archivos:**
- Modificar: `PrototipoApp/Theme/Components.swift` (`animacionSuave`)
- Modificar: `ReportSuccessView.swift`, `ReportDetailView.swift`, `ProfileView.swift`, `LoginView.swift`, `Formularios.swift` (`FieldError`)

**Interfaces:**
- Produce: `View.animacionSuave(_:)`.

- [ ] **Paso 1: Ayudante** en `Components.swift`:

```swift
/// Animación corta que se apaga con "Reducir movimiento" (Ajustes de iOS › Accesibilidad).
private struct AnimacionSuave<Valor: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reducir
    let valor: Valor

    func body(content: Content) -> some View {
        content.animation(reducir ? nil : .snappy, value: valor)
    }
}

extension View {
    func animacionSuave<Valor: Equatable>(_ valor: Valor) -> some View {
        modifier(AnimacionSuave(valor: valor))
    }
}
```

- [ ] **Paso 2: Aplicar.** `ProfileView`: `.animacionSuave(reports.version)` en el `VStack` de tarjetas (al borrar o quitar, la tarjeta se va con animación). `ReportDetailView`: `.symbolEffect(.bounce, value: r.guardadoPorMi)` en el marcador y `.animacionSuave(r.confirmaciones)` en la tarjeta "Yo también". `ReportSuccessView`: `.sensoryFeedback(.success, trigger: id)` y `.symbolEffect(.bounce, value: id)` en la palomita. `LoginView`: `.sensoryFeedback(.error, trigger: error)`. Formularios: `.animacionSuave(error)` en `LabeledTextField`, `LabeledSecureField` y `OfraudeTextEditor` (el mensaje de error aparece con la transición de `FieldError`).

- [ ] **Paso 3: Verificar** — Run: `BUILD` y `UI` completo → verde. Manual: con "Reducir movimiento" activado en el simulador (Ajustes › Accesibilidad › Movimiento), borrar un guardado: desaparece sin animación.

- [ ] **Paso 4: Commit**

```bash
git add PrototipoApp
git commit -m "feat: animaciones suaves que respetan reducir movimiento y respuesta háptica"
```

**Criterios de aceptación:** ninguna animación con "Reducir movimiento"; vibración al enviar.
**Dependencias:** F4–F11. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea U6: Ajustes visuales aprobados, ícono y color de acento

**Objetivo:** aplicar la tabla 6.1 que falte (títulos de Ajustes y Guía, ícono de la app, `AccentColor`) y dejar todo anotado.

**Archivos:**
- Crear: `scripts/generar_icono.swift`
- Crear: `PrototipoApp/Assets.xcassets/AppIcon.appiconset/icono-1024.png` (generado)
- Modificar: `PrototipoApp/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Modificar: `PrototipoApp/Assets.xcassets/AccentColor.colorset/Contents.json`
- Modificar: `PrototipoApp/Views/Account/SettingsView.swift`, `PrototipoApp/Views/Learn/SecurityGuideView.swift` (`navigationTitle`)

**Interfaces:**
- Produce: ícono de 1024 px y color de acento del sistema.

- [ ] **Paso 1: Generar el ícono** — `scripts/generar_icono.swift` (macOS, sin dependencias):

```swift
// Genera el ícono de 0Fraude (1024×1024): fondo azul marino, escudo naranja y un "0".
// Uso: swift scripts/generar_icono.swift PrototipoApp/Assets.xcassets/AppIcon.appiconset/icono-1024.png
import AppKit

let lado: CGFloat = 1_024
let imagen = NSImage(size: NSSize(width: lado, height: lado))
imagen.lockFocus()
NSColor(srgbRed: 10 / 255, green: 19 / 255, blue: 48 / 255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: lado, height: lado).fill()
let naranja = NSColor(srgbRed: 245 / 255, green: 166 / 255, blue: 35 / 255, alpha: 1)
if let escudo = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 640, weight: .regular)) {
    let tintado = NSImage(size: escudo.size, flipped: false) { rect in
        escudo.draw(in: rect)
        naranja.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let tamano = tintado.size
    tintado.draw(in: NSRect(x: (lado - tamano.width) / 2, y: (lado - tamano.height) / 2, width: tamano.width, height: tamano.height))
}
let texto = NSAttributedString(string: "0", attributes: [
    .font: NSFont.systemFont(ofSize: 420, weight: .heavy),
    .foregroundColor: NSColor(srgbRed: 10 / 255, green: 19 / 255, blue: 48 / 255, alpha: 1),
])
let medida = texto.size()
texto.draw(at: NSPoint(x: (lado - medida.width) / 2, y: (lado - medida.height) / 2 - 10))
imagen.unlockFocus()
guard let tiff = imagen.tiffRepresentation, let mapa = NSBitmapImageRep(data: tiff),
      let png = mapa.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
```

Run: `swift scripts/generar_icono.swift PrototipoApp/Assets.xcassets/AppIcon.appiconset/icono-1024.png` y luego `sips -g pixelWidth -g pixelHeight PrototipoApp/Assets.xcassets/AppIcon.appiconset/icono-1024.png` → 1024 × 1024 (en pantallas Retina `NSImage` puede salir a 2048: en ese caso `sips -z 1024 1024 …` para reducirlo).

- [ ] **Paso 2: Catálogo.** En `AppIcon.appiconset/Contents.json`, agregar `"filename" : "icono-1024.png"` a la primera entrada (universal, sin `appearances`). En `AccentColor.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0.137", "green" : "0.651", "red" : "0.961" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Paso 3: Títulos.** `SettingsView`: `.navigationTitle("Ajustes")`; `SecurityGuideView`: `.navigationTitle("Guía de seguridad")`.

- [ ] **Paso 4: Verificar** — Run: `BUILD` → sin `warning:` del catálogo de assets (`grep -c "AppIcon" build.log` sin advertencias); instalar y ver el ícono en la pantalla de inicio del simulador; las alertas del sistema ("Eliminar", "Cancelar") salen en naranja.

- [ ] **Paso 5: Commit**

```bash
git add scripts PrototipoApp
git commit -m "feat: ícono de la app, color de acento y títulos faltantes"
```

**Criterios de aceptación:** ícono visible; tabla 6.1 completa y anotada en `docs/CAMBIOS-vs-original.md` (M1).
**Dependencias:** U3 (usa `onAccent`). **Esfuerzo:** S. **Riesgo:** bajo.

---

## 7. Calidad y pruebas

### 7.1 Estrategia

| Nivel | Herramienta | Qué cubre | Dónde |
|---|---|---|---|
| Unitarias (TDD) | Swift Testing (`import Testing`, `@Test`, `#expect`) en `PrototipoAppTests`, con la app como anfitriona | Modelos, formatos, filtro, validación, saneamiento, URLs, hash, Keychain, límite de intentos, evidencia, servidor Demo (permisos, privacidad, máquina de estados), stores, cliente HTTP y Remote | S1–S6, D1–D9, R2–R3 |
| Interfaz | XCTest/XCUITest en `PrototipoAppUITests` | Los flujos del checklist de 2026-09-27, cada `// TODO` convertido en función, roles, accesibilidad, estados | Cada tarea F, V2, U1–U3, Q2 |
| Manual | Checklist de Q3 | Lo que no se puede automatizar (ver 7.2) | Q3 |

TDD donde aplica: todo lo que no es vista se escribe prueba primero (pasos "prueba que falla → ver que falla → implementar → ver que pasa"). En las vistas, la prueba de interfaz de cada tarea se escribe primero y define los identificadores de accesibilidad.

**Sobre la automatización en esta Mac.** La verificación del 2026-09-27 no pudo tocar el simulador porque `osascript` no tiene permiso de Accesibilidad y no hay `idb` ni `cliclick`. **XCUITest no necesita ese permiso:** corre dentro del simulador con `xcodebuild test`. No hay que habilitar nada en Ajustes del Sistema. Si algún día se quisiera manejar el simulador con AppleScript, el permiso lo concede Alex a mano en Ajustes del Sistema › Privacidad y seguridad › Accesibilidad; el plan no lo activa por su cuenta.

### 7.2 Lo que no se automatiza (y por qué)

| Qué | Por qué no | Cómo se revisa |
|---|---|---|
| Selector de fotos real (PhotosPicker) | Corre en otro proceso; XCUITest no lo controla de forma estable | Q3 manual; en pruebas se usa `-evidenciaDePrueba` |
| Cámara | El simulador no tiene | En un iPhone real, si hay uno (Q3) |
| Diálogo de permiso de notificaciones y el aviso del sistema | Diálogo del sistema; el permiso queda guardado entre corridas | Q3 manual |
| Hoja de compartir | Contenido de otras apps | Q3: revisar el texto en "Copiar" |
| VoiceOver real y contraste | Requiere oír/ver | Accessibility Inspector (Q3) |
| Escudo en el selector de apps | Captura del sistema | Q3 manual |
| Reinstalar con tokens viejos | Borrar e instalar la app | Q3 manual + prueba unitaria S2 |
| Protección de archivos | El simulador no la aplica | Solo en dispositivo; documentado como limitación |

### Tarea Q1: Targets de pruebas y esquema compartido

**Objetivo:** crear `PrototipoAppTests` (unitarias, Swift Testing, con la app como anfitriona) y `PrototipoAppUITests` (XCUITest), un esquema compartido que los corre, los ayudantes de las pruebas de interfaz y una prueba humo de cada tipo.

**Archivos:**
- Modificar: `PrototipoApp.xcodeproj/project.pbxproj` (12 inserciones; ids que empiezan con `0F5C`)
- Crear: `PrototipoApp.xcodeproj/xcshareddata/xcschemes/PrototipoApp.xcscheme`
- Crear: `PrototipoAppTests/App/AppStateTests.swift`
- Crear: `PrototipoAppUITests/ArranqueUITests.swift`
- Crear: `PrototipoAppUITests/Soporte/Ayudantes.swift`

**Interfaces:**
- Consume: P1 (git como respaldo), P2 (mismo `project.pbxproj`, por eso va después).
- Produce: los comandos `UNIT` y `UI` funcionan; ayudantes `XCUIApplication.zeroScam(reiniciar:extra:)`, `entrar(_:_:)`, `volverALaRaiz()`, `elemento(contiene:)`; `XCUIElement.tocar(en:intentos:)`, `escribir(_:)`, `reemplazar(_:)`; `XCTestCase.capturar(_:_:)`, `esperar(_:etiqueta:segundos:)`, `esperar(_:valor:segundos:)`.

Las carpetas `PrototipoAppTests/` y `PrototipoAppUITests/` van junto a `PrototipoApp/` y son carpetas sincronizadas (igual que la app): crear un archivo dentro basta para que entre al target.

- [ ] **Paso 1: Archivos de prueba.** `PrototipoAppTests/App/AppStateTests.swift` (contra el `AppState` actual; D10 lo reescribe):

```swift
//
//  AppStateTests.swift
//  PrototipoAppTests
//

import Testing
@testable import PrototipoApp

struct AppStateTests {
    @Test func pushUsaLaPilaDeLaPestanaVisible() {
        let estado = AppState()
        estado.selectedTab = .search
        estado.push(.settings)
        #expect(estado.searchPath == [.settings])
        #expect(estado.homePath.isEmpty)
    }

    @Test func popToTabsVaciaTodasLasPilas() {
        let estado = AppState()
        estado.homePath = [.reportDetail]
        estado.profilePath = [.settings, .privacy]
        estado.popToTabs(selecting: .profile)
        #expect(estado.homePath.isEmpty && estado.profilePath.isEmpty)
        #expect(estado.selectedTab == .profile)
    }

    @Test func logOutDejaTodoComoAlAbrir() {
        let estado = AppState()
        estado.isLoggedIn = true
        estado.searchQuery = "Ofertas Falsas"
        estado.profileSegment = .guardados
        estado.logOut()
        #expect(!estado.isLoggedIn)
        #expect(estado.searchQuery.isEmpty)
        #expect(estado.profileSegment == .misReportes)
        #expect(estado.selectedTab == .home)
    }
}
```

`PrototipoAppUITests/ArranqueUITests.swift`:

```swift
//
//  ArranqueUITests.swift
//  PrototipoAppUITests
//

import XCTest

final class ArranqueUITests: XCTestCase {
    @MainActor
    func testArrancaEnRegistro() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        XCTAssertTrue(app.buttons["CREAR CUENTA"].waitForExistence(timeout: 10))
    }
}
```

`PrototipoAppUITests/Soporte/Ayudantes.swift`:

```swift
//
//  Ayudantes.swift
//  PrototipoAppUITests
//
//  Atajos de las pruebas de interfaz. La app se abre con -uiTesting (datos demo en otra carpeta,
//  otro servicio de Keychain y hash rápido) y, salvo que se pida lo contrario, -reiniciarDemo
//  (vuelve a la semilla). No necesita el permiso de Accesibilidad de macOS.
//

import XCTest

@MainActor
extension XCUIApplication {
    static func zeroScam(reiniciar: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (reiniciar ? ["-reiniciarDemo"] : []) + extra
        return app
    }

    /// Desde Registro: va a Login, escribe y entra. Por defecto, la cuenta Usuario.
    func entrar(_ correo: String = "usuario@0fraude.mx", _ contrasena: String = "Alerta#2026mx") {
        let irLogin = buttons["registro.irLogin"]
        if irLogin.waitForExistence(timeout: 10) { irLogin.tap() }
        let campo = textFields["login.correo"]
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.reemplazar(correo)
        secureTextFields["login.contrasena"].escribir(contrasena)
        buttons["login.entrar"].tap()
        XCTAssertTrue(tabBars.buttons["Inicio"].waitForExistence(timeout: 15))
    }

    /// Regresa con la flecha de la barra hasta la raíz de la pestaña (ahí se ve el tab bar).
    func volverALaRaiz() {
        var intentos = 0
        while !tabBars.firstMatch.isHittable && navigationBars.buttons.firstMatch.exists && intentos < 8 {
            navigationBars.buttons.firstMatch.tap()
            intentos += 1
        }
    }

    /// Cualquier elemento cuya etiqueta contenga el texto (las tarjetas combinan sus textos para VoiceOver).
    func elemento(contiene texto: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", texto)).firstMatch
    }
}

@MainActor
extension XCUIElement {
    /// Desliza hacia arriba hasta que el elemento se pueda tocar y lo toca.
    func tocar(en app: XCUIApplication, intentos: Int = 8) {
        var n = 0
        while !(exists && isHittable) && n < intentos {
            app.swipeUp()
            n += 1
        }
        tap()
    }

    func escribir(_ texto: String) {
        tap()
        typeText(texto)
    }

    /// Borra lo que haya y escribe el texto nuevo.
    func reemplazar(_ texto: String) {
        tap()
        if let actual = value as? String, !actual.isEmpty, actual != placeholderValue {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: actual.count))
        }
        typeText(texto)
    }
}

@MainActor
extension XCTestCase {
    /// Captura con nombre que se conserva en el .xcresult (Q3 las exporta a docs/capturas).
    func capturar(_ app: XCUIApplication, _ nombre: String) {
        let adjunto = XCTAttachment(screenshot: app.screenshot())
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        add(adjunto)
    }

    func esperar(_ elemento: XCUIElement, etiqueta: String, segundos: TimeInterval = 5) {
        let condicion = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", etiqueta), object: elemento)
        XCTAssertEqual(XCTWaiter.wait(for: [condicion], timeout: segundos), .completed, "Esperaba «\(etiqueta)»")
    }

    func esperar(_ elemento: XCUIElement, valor: String, segundos: TimeInterval = 5) {
        let condicion = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", valor), object: elemento)
        XCTAssertEqual(XCTWaiter.wait(for: [condicion], timeout: segundos), .completed, "Esperaba el valor «\(valor)»")
    }
}
```

- [ ] **Paso 2: `project.pbxproj`.** Xcode ignora la indentación; insertar cada bloque en su sección (las anclas son texto exacto del archivo actual). Antes de empezar, `git status` limpio: si algo sale mal, `git checkout -- PrototipoApp.xcodeproj/project.pbxproj`.

2a. Antes de `/* Begin PBXFileReference section */`, una sección nueva:

```
/* Begin PBXContainerItemProxy section */
		0F5C00000000000000000003 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = FA58C25B30461DCD00D1FB66 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = FA58C26230461DCD00D1FB66;
			remoteInfo = PrototipoApp;
		};
		0F5C00000000000000000004 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = FA58C25B30461DCD00D1FB66 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = FA58C26230461DCD00D1FB66;
			remoteInfo = PrototipoApp;
		};
/* End PBXContainerItemProxy section */

```

2b. Antes de `/* End PBXFileReference section */`:

```
		0F5C00000000000000000001 /* PrototipoAppTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PrototipoAppTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
		0F5C00000000000000000002 /* PrototipoAppUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PrototipoAppUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

2c. Antes de `/* End PBXFileSystemSynchronizedRootGroup section */`:

```
		0F5C00000000000000000007 /* PrototipoAppTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = PrototipoAppTests;
			sourceTree = "<group>";
		};
		0F5C00000000000000000008 /* PrototipoAppUITests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = PrototipoAppUITests;
			sourceTree = "<group>";
		};
```

2d. Antes de `/* End PBXFrameworksBuildPhase section */`:

```
		0F5C0000000000000000000A /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		0F5C0000000000000000000D /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

2e. En el grupo principal, reemplazar

```
				FA58C26530461DCD00D1FB66 /* PrototipoApp */,
				FA58C26430461DCD00D1FB66 /* Products */,
```
por
```
				FA58C26530461DCD00D1FB66 /* PrototipoApp */,
				0F5C00000000000000000007 /* PrototipoAppTests */,
				0F5C00000000000000000008 /* PrototipoAppUITests */,
				FA58C26430461DCD00D1FB66 /* Products */,
```

y en el grupo `Products`, después de `FA58C26330461DCD00D1FB66 /* PrototipoApp.app */,` agregar:

```
				0F5C00000000000000000001 /* PrototipoAppTests.xctest */,
				0F5C00000000000000000002 /* PrototipoAppUITests.xctest */,
```

2f. Antes de `/* End PBXNativeTarget section */`:

```
		0F5C0000000000000000000F /* PrototipoAppTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 0F5C00000000000000000011 /* Build configuration list for PBXNativeTarget "PrototipoAppTests" */;
			buildPhases = (
				0F5C00000000000000000009 /* Sources */,
				0F5C0000000000000000000A /* Frameworks */,
				0F5C0000000000000000000B /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				0F5C00000000000000000005 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				0F5C00000000000000000007 /* PrototipoAppTests */,
			);
			name = PrototipoAppTests;
			packageProductDependencies = (
			);
			productName = PrototipoAppTests;
			productReference = 0F5C00000000000000000001 /* PrototipoAppTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		0F5C00000000000000000010 /* PrototipoAppUITests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 0F5C00000000000000000012 /* Build configuration list for PBXNativeTarget "PrototipoAppUITests" */;
			buildPhases = (
				0F5C0000000000000000000C /* Sources */,
				0F5C0000000000000000000D /* Frameworks */,
				0F5C0000000000000000000E /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				0F5C00000000000000000006 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				0F5C00000000000000000008 /* PrototipoAppUITests */,
			);
			name = PrototipoAppUITests;
			packageProductDependencies = (
			);
			productName = PrototipoAppUITests;
			productReference = 0F5C00000000000000000002 /* PrototipoAppUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		};
```

2g. En `TargetAttributes`, reemplazar

```
					FA58C26230461DCD00D1FB66 = {
						CreatedOnToolsVersion = 26.5;
					};
```
por
```
					FA58C26230461DCD00D1FB66 = {
						CreatedOnToolsVersion = 26.5;
					};
					0F5C0000000000000000000F = {
						CreatedOnToolsVersion = 26.5;
						TestTargetID = FA58C26230461DCD00D1FB66;
					};
					0F5C00000000000000000010 = {
						CreatedOnToolsVersion = 26.5;
						TestTargetID = FA58C26230461DCD00D1FB66;
					};
```

y en `targets = (`, después de `FA58C26230461DCD00D1FB66 /* PrototipoApp */,`:

```
				0F5C0000000000000000000F /* PrototipoAppTests */,
				0F5C00000000000000000010 /* PrototipoAppUITests */,
```

2h. Antes de `/* End PBXResourcesBuildPhase section */`:

```
		0F5C0000000000000000000B /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		0F5C0000000000000000000E /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

2i. Antes de `/* End PBXSourcesBuildPhase section */`:

```
		0F5C00000000000000000009 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		0F5C0000000000000000000C /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

2j. Antes de `/* Begin XCBuildConfiguration section */`, una sección nueva:

```
/* Begin PBXTargetDependency section */
		0F5C00000000000000000005 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = FA58C26230461DCD00D1FB66 /* PrototipoApp */;
			targetProxy = 0F5C00000000000000000003 /* PBXContainerItemProxy */;
		};
		0F5C00000000000000000006 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = FA58C26230461DCD00D1FB66 /* PrototipoApp */;
			targetProxy = 0F5C00000000000000000004 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

```

2k. Antes de `/* End XCBuildConfiguration section */` (Debug y Release de cada target; las de pruebas unitarias usan la app como anfitriona, lo que da acceso al Keychain en el simulador):

```
		0F5C00000000000000000013 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = THFHN8TFG9;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 26.5;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "Tec-CCM.PrototipoAppTests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/PrototipoApp.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PrototipoApp";
			};
			name = Debug;
		};
		0F5C00000000000000000014 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = THFHN8TFG9;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 26.5;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "Tec-CCM.PrototipoAppTests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/PrototipoApp.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PrototipoApp";
			};
			name = Release;
		};
		0F5C00000000000000000015 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = THFHN8TFG9;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 26.5;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "Tec-CCM.PrototipoAppUITests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_TARGET_NAME = PrototipoApp;
			};
			name = Debug;
		};
		0F5C00000000000000000016 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = THFHN8TFG9;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 26.5;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "Tec-CCM.PrototipoAppUITests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_TARGET_NAME = PrototipoApp;
			};
			name = Release;
		};
```

2l. Antes de `/* End XCConfigurationList section */`:

```
		0F5C00000000000000000011 /* Build configuration list for PBXNativeTarget "PrototipoAppTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				0F5C00000000000000000013 /* Debug */,
				0F5C00000000000000000014 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		0F5C00000000000000000012 /* Build configuration list for PBXNativeTarget "PrototipoAppUITests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				0F5C00000000000000000015 /* Debug */,
				0F5C00000000000000000016 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

Comprobar que el archivo sigue siendo válido: `plutil -lint PrototipoApp.xcodeproj/project.pbxproj` → `OK`.

- [ ] **Paso 3: Esquema compartido** — `PrototipoApp.xcodeproj/xcshareddata/xcschemes/PrototipoApp.xcscheme`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2650"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "FA58C26230461DCD00D1FB66"
               BuildableName = "PrototipoApp.app"
               BlueprintName = "PrototipoApp"
               ReferencedContainer = "container:PrototipoApp.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "0F5C0000000000000000000F"
               BuildableName = "PrototipoAppTests.xctest"
               BlueprintName = "PrototipoAppTests"
               ReferencedContainer = "container:PrototipoApp.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "0F5C00000000000000000010"
               BuildableName = "PrototipoAppUITests.xctest"
               BlueprintName = "PrototipoAppUITests"
               ReferencedContainer = "container:PrototipoApp.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "FA58C26230461DCD00D1FB66"
            BuildableName = "PrototipoApp.app"
            BlueprintName = "PrototipoApp"
            ReferencedContainer = "container:PrototipoApp.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "FA58C26230461DCD00D1FB66"
            BuildableName = "PrototipoApp.app"
            BlueprintName = "PrototipoApp"
            ReferencedContainer = "container:PrototipoApp.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Paso 4: Verificar**

Run: `xcodebuild -list` → `Targets:` lista `PrototipoApp`, `PrototipoAppTests`, `PrototipoAppUITests`.
Run: `UNIT` → `** TEST SUCCEEDED **` (3 pruebas de `AppStateTests`).
Run: `UI` → `** TEST SUCCEEDED **` (`ArranqueUITests/testArrancaEnRegistro`).
Run: `BUILD` → `** BUILD SUCCEEDED **`, sin advertencias nuevas.

- [ ] **Paso 5: Commit**

```bash
git add PrototipoApp.xcodeproj PrototipoAppTests PrototipoAppUITests
git commit -m "test: targets de pruebas unitarias y de interfaz con esquema compartido"
```

**Plan B (si el `pbxproj` editado no abre o `xcodebuild` no ve los targets):** `git checkout -- PrototipoApp.xcodeproj`, y pedir a Alex que en Xcode haga File › New › Target… › "Unit Testing Bundle" (nombre `PrototipoAppTests`, Testing System: Swift Testing, Target to be Tested: PrototipoApp) y otra vez con "UI Testing Bundle" (`PrototipoAppUITests`); luego Product › Scheme › Manage Schemes… › marcar "Shared" en PrototipoApp. Toma 2 minutos; después se copian los 3 archivos del paso 1 y se agrega `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` al target de unitarias.

**Criterios de aceptación:** `UNIT` y `UI` corren desde la terminal sin abrir Xcode.
**Dependencias:** P1, P2. **Esfuerzo:** M. **Riesgo:** medio (edición a mano del proyecto; tiene plan B).

### Tarea Q2: Pruebas de interfaz de punta a punta

**Objetivo:** cerrar los flujos del checklist que ninguna tarea F cubrió y los del foco de revisión, y dejar la suite completa en verde con sus capturas.

**Archivos:**
- Modificar: `PrototipoAppUITests/NavegacionUITests.swift`, `FlujoReporteUITests.swift`, `PerfilUITests.swift`

**Interfaces:**
- Consume: todas las tareas F, V2, U1–U3; ayudantes de Q1, F3, F9, F15, F19, F20.
- Produce: suite completa (≈ 40 pruebas de interfaz) y el `.xcresult` que Q3 exporta.

- [ ] **Paso 1: Pruebas nuevas.** En `NavegacionUITests`:

```swift
    @MainActor
    func testAjustesGuardadosAbrePerfilEnLaRaiz() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.ajustes"].tap()
        app.buttons["ajustes.guardados"].tocar(en: app)
        XCTAssertTrue(app.buttons["perfil.quitarGuardado.101"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
    }
```

En `FlujoReporteUITests`:

```swift
    @MainActor
    func testEnviarDosVecesCreaUnSoloReporte() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Reportar"].tap()
        let titulo = "Prueba UI: doble toque en enviar"
        app.llenarReporte(titulo: titulo)
        let enviar = app.buttons["reporte.enviar"]
        enviar.tocar(en: app)
        if enviar.exists && enviar.isHittable { enviar.tap() }
        XCTAssertTrue(app.buttons["exito.misReportes"].waitForExistence(timeout: 10))
        app.buttons["exito.misReportes"].tap()
        let tarjetas = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'perfil.tarjeta.' AND label CONTAINS %@", titulo))
        XCTAssertTrue(tarjetas.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(tarjetas.count, 1)
    }

    @MainActor
    func testReporteSobreviveReinicio() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Reportar"].tap()
        app.llenarReporte(titulo: "Prueba UI: reporte persistente")
        app.buttons["reporte.enviar"].tocar(en: app)
        XCTAssertTrue(app.staticTexts["exito.folio"].waitForExistence(timeout: 10))
        app.terminate()
        let otraVez = XCUIApplication.zeroScam(reiniciar: false)
        otraVez.launch()
        otraVez.tabBars.buttons["Perfil"].tap()
        XCTAssertTrue(otraVez.elemento(contiene: "Prueba UI: reporte persistente").waitForExistence(timeout: 5))
    }

    @MainActor
    func testYoTambienYEnvioVacianLasPilas() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.buttons["inicio.alerta.101"].tocar(en: app)
        app.buttons["detalle.yoTambien"].tocar(en: app)
        app.buttons["Sí, reportar mi caso"].tap()
        app.textFields["reporte.ciudad"].tocar(en: app)
        app.textFields["reporte.ciudad"].typeText("Toluca")
        app.textFields["reporte.titulo"].tocar(en: app)
        app.textFields["reporte.titulo"].typeText("A mí también me ofrecieron esa liquidación")
        app.textViews["reporte.descripcion"].tocar(en: app)
        app.textViews["reporte.descripcion"].typeText("Me llegó el mismo anuncio y casi pago la laptop.")
        app.buttons["Listo"].firstMatch.tap()
        app.buttons["reporte.enviar"].tocar(en: app)
        app.buttons["exito.continuar"].tap()
        XCTAssertTrue(app.buttons["inicio.reportar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        app.tabBars.buttons["Buscar"].tap()
        XCTAssertTrue(app.textFields["buscar.campo"].waitForExistence(timeout: 5))
    }
```

En `PerfilUITests`:

```swift
    @MainActor
    func testListasSeActualizanTrasEliminar() {
        let app = XCUIApplication.zeroScam()
        app.launch()
        app.entrar()
        app.tabBars.buttons["Buscar"].tap()
        app.textFields["buscar.campo"].escribir("2x1")
        XCTAssertTrue(app.buttons["buscar.resultado.122"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Perfil"].tap()
        app.buttons["perfil.opciones.122"].tocar(en: app)
        app.buttons["Eliminar"].tap()
        app.alerts.buttons["Eliminar"].tap()
        app.tabBars.buttons["Buscar"].tap()
        XCTAssertTrue(app.buttons["buscar.resultado.122"].waitForNonExistence(timeout: 5))
    }
```

- [ ] **Paso 2: Correr la suite completa con resultados**

Run: `UI` (escribe `build/ui.xcresult`; tarda varios minutos).
Expected: `** TEST SUCCEEDED **`. Si una prueba falla de forma intermitente por tiempos (animaciones), subir su `timeout`; si falla siempre, es un error real: arreglar la app, no la prueba.

- [ ] **Paso 3: Commit**

```bash
git add PrototipoAppUITests
git commit -m "test: flujos de punta a punta del checklist y del foco de revisión"
```

**Criterios de aceptación:** los 11 flujos de 0.4 tienen prueba en verde (salvo el 10, manual); AC2 y AC9 cumplidos.
**Dependencias:** F1–F21, V2, U1–U3. **Esfuerzo:** L. **Riesgo:** medio (pruebas de interfaz lentas e intermitentes; ver sección 10).

### Tarea Q3: Revisión manual y capturas

**Objetivo:** recorrer lo que no se automatiza, exportar las capturas de las pruebas a `docs/capturas/` y dejar el resultado por escrito.

**Archivos:**
- Crear: `scripts/exportar_capturas.sh`
- Crear: `docs/capturas/*.png` (generadas)
- Crear: `docs/verificacion-2026-10-19.md` (la fecha real de la corrida)

**Interfaces:**
- Consume: Q2 (`build/ui.xcresult`).
- Produce: capturas `01-registro.png` … `16-modo-claro.png`; el documento de verificación que M3 completa.

- [ ] **Paso 1: Script de exportación** — `scripts/exportar_capturas.sh`:

```bash
#!/bin/zsh
# Exporta las capturas de las pruebas de interfaz a docs/capturas con su nombre (01-registro.png, …).
# Uso: scripts/exportar_capturas.sh [build/ui.xcresult]
set -euo pipefail
resultado=${1:-build/ui.xcresult}
salida=docs/capturas
temporal=$(mktemp -d)
xcrun xcresulttool export attachments --path "$resultado" --output-path "$temporal"
python3 -I - "$temporal" "$salida" <<'PY'
import json, os, re, shutil, sys
origen, destino = sys.argv[1], sys.argv[2]
os.makedirs(destino, exist_ok=True)
for prueba in json.load(open(os.path.join(origen, "manifest.json"))):
    for adjunto in prueba.get("attachments", []):
        nombre = re.match(r"(\d{2}-[a-z0-9-]+)", adjunto.get("suggestedHumanReadableName", ""))
        if nombre:
            shutil.copy(os.path.join(origen, adjunto["exportedFileName"]), os.path.join(destino, nombre.group(1) + ".png"))
print("Capturas en", destino)
PY
```

Run: `chmod +x scripts/exportar_capturas.sh && scripts/exportar_capturas.sh` → `ls docs/capturas | wc -l` ≥ 12. (Si `manifest.json` trae otros nombres de campo en esta versión de Xcode, abrirlo y ajustar las dos claves del script.)

- [ ] **Paso 2: Checklist manual** (simulador iPhone 17; anotar ✓/✗ y observaciones en `docs/verificacion-2026-10-19.md`):

1. Registro con teclado en pantalla (⌘K): "Siguiente" recorre todos los campos; tocar fuera cierra el teclado.
2. Reportar: "Elegir de la galería" con una foto de ejemplo del simulador; aparece la miniatura; enviar; en el detalle (autor) se ve; desde otra cuenta solo "Incluye 1 archivo(s)…".
3. Una foto con ubicación (en Fotos del simulador, las de ejemplo traen GPS en algunos casos): tras enviarla, `exiftool` o `mdls` sobre el archivo en `~/Library/Developer/CoreSimulator/Devices/901BB67A-…/data/Containers/Data/Application/*/Library/Application Support/ZeroScamDemo/evidencia/` no muestra coordenadas.
4. Notificaciones: activar el switch → diálogo de iOS en español → permitir; mover un reporte como Administrador; volver como Usuario → aviso del sistema "Tienes 1 notificación nueva." sin título del reporte.
5. Compartir una alerta → "Copiar" → pegar en Notas: dice `hxxps://…[.]…` y no menciona a quien reportó.
6. Selector de apps (deslizar desde abajo y pausar): se ve el escudo, no el contenido.
7. Borrar la app del simulador y reinstalar: arranca en Registro aunque antes hubiera sesión.
8. Accessibility Inspector › Audit en Inicio, Detalle, Reportar, Perfil y Ajustes: sin "no description"; revisar contraste.
9. VoiceOver (Accessibility Inspector › Inspection): la campana dice "Notificaciones, 1 sin leer"; las tarjetas se leen completas.
10. Texto en `accessibility-extra-extra-extra-large` (`xcrun simctl ui "iPhone 17" content_size accessibility-extra-extra-extra-large`): el tope `accessibility2` mantiene todo legible.
11. Modo claro (switch de Ajustes): Inicio, Buscar, Reportar, Perfil, Detalle y Ajustes legibles.
12. Modo Remote sin backend (`ZS_FUENTE_DATOS=remote ZS_URL_BASE=http://localhost:3999`): Login dice "No se pudo conectar con el servidor. Revisa tu conexión." y no se cae.
13. Recorrer el guion de `docs/guion-demo.md` dos veces seguidas sin cierres inesperados (AC10), con cronómetro.

- [ ] **Paso 3: Commit**

```bash
git add scripts/exportar_capturas.sh docs/capturas docs/verificacion-2026-10-19.md
git commit -m "docs: capturas de las pruebas y revisión manual"
```

**Criterios de aceptación:** ≥ 12 capturas; los 13 puntos anotados; cada ✗ tiene una tarea de corrección o queda como limitación en el README.
**Dependencias:** Q2, M2 (para el punto 13). **Esfuerzo:** M. **Riesgo:** bajo.

---

## 8. Documentación y demo

### Tarea M1: README, cambios respecto al original y limitaciones

**Objetivo:** que cualquier integrante del Equipo ZeroScam pueda abrir, correr, probar y entender el proyecto, y saber qué cambió y qué no hace.

**Archivos:**
- Crear: `README.md`
- Modificar: `docs/CAMBIOS-vs-original.md` (sección nueva al final; "OFraude" → "0Fraude" donde es el nombre de la app)
- Modificar: `docs/verificacion-2026-09-26.md` (solo el título: "0Fraude")

**Interfaces:**
- Consume: todo.
- Produce: `README.md`.

- [ ] **Paso 1: `README.md`** con estas secciones y contenido:

````markdown
# 0Fraude

App iOS para reportar y consultar fraudes en línea, hecha por el **Equipo ZeroScam** para el módulo de Integración de Seguridad Informática. Prototipo en SwiftUI (iOS 26.5) migrado del storyboard original (`../PrototipoApp`, que no se modifica).

## Cómo correrla
1. Abrir `PrototipoApp.xcodeproj` en Xcode 26.5 y elegir el simulador iPhone 17.
2. ▶︎ Run. La primera vez arranca en Registro con los datos de demostración.

Cuentas demo: `usuario@0fraude.mx` / `Alerta#2026mx` (Usuario), `admin@0fraude.mx` / `Revisa#2026zs` (Administrador), `owner@0fraude.mx` / `Equipo#2026zs` (Owner).
Para volver a los datos iniciales: Owner › Ajustes › Usuarios y roles › Restablecer datos de demostración.

## Modo Demo y modo Remote
- **Demo (por defecto):** un servidor dentro de la app (`Data/Demo/`) con las mismas reglas que tendrá el backend. Los datos viven en el teléfono.
- **Remote:** la API NestJS del equipo según `docs/api-contrato.md`. `xcodebuild … ZS_FUENTE_DATOS=remote ZS_URL_BASE=http://localhost:3000`.

## Pruebas
- Unitarias: `xcodebuild test -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PrototipoAppTests`
- Interfaz: `… -only-testing:PrototipoAppUITests` (no requiere permisos de Accesibilidad de macOS)
- Capturas: `scripts/exportar_capturas.sh`

## Estructura
`App/` arranque, navegación y configuración · `Model/` tipos del dominio (tablas de ZeroScam) · `Data/` repositorios, servidor Demo y cliente Remote · `Security/` hash, Keychain, validación, URLs, evidencia · `Stores/` estado observable · `Theme/` colores y componentes · `Views/` pantallas.

## Seguridad
Resumen y modelo de amenazas: `docs/seguridad.md`.

## Limitaciones conocidas
- La verificación en dos pasos es simulada en modo Demo (el código se muestra en pantalla).
- No hay notificaciones push reales (APNs); se usan avisos locales.
- En el simulador la protección de archivos de iOS no se aplica; en un iPhone sí.
- Los PDF de evidencia conservan sus metadatos (solo las fotos se limpian).
- En modo Demo el "servidor" corre en el teléfono: alguien con acceso al sistema de archivos podría alterar los datos.
- La capa Remote se probó contra respuestas simuladas; falta probarla contra el backend real del equipo.
- El staff ve quién hizo un reporte anónimo (así lo dice el aviso de privacidad).
- Cifras de "Yo también" de la semilla incluyen un conteo histórico solo de demostración.

## Documentos
`docs/superpowers/specs/` diseño · `docs/superpowers/plans/` planes · `docs/CAMBIOS-vs-original.md` · `docs/guion-demo.md` · `docs/api-contrato.md` · `docs/seguridad.md` · `docs/verificacion-*.md` · `database/` (esquema ZeroScam y migración propuesta).
````

(Completar la lista de limitaciones con los ✗ de Q3.)

- [ ] **Paso 2: `docs/CAMBIOS-vs-original.md`** — agregar al final una sección "## Prototipo completo (octubre 2026)" con: quirks corregidos (tabla 1.4), ajustes visuales (tabla 6.1), pantallas nuevas (Aviso, Notificaciones, Moderación, Revisión, Usuarios, Eliminar cuenta, Código de dos pasos), cambios de comportamiento (Registro lleva a Login con el correo; "Yo también" confirma y pregunta si reportar; los switches reflejan la cuenta y 2 pasos arranca apagado; el detalle depende de la tarjeta; Buscar filtra; las cifras se calculan), y "qué se conserva" (textos, colores, medidas y navegación del storyboard). Cambiar "OFraude" por "0Fraude" donde se refiere a la app (no en nombres de archivo como `OFraudeApp.swift` ni en el nombre visible histórico "OFraude SwiftUI").

- [ ] **Paso 3: Verificar** — `grep -rn "OFraude" README.md docs/*.md | grep -v -e OFraudeApp -e "OFraude SwiftUI"` sin resultados; los enlaces del README apuntan a archivos que existen (`ls` de cada uno).

- [ ] **Paso 4: Commit**

```bash
git add README.md docs/CAMBIOS-vs-original.md docs/verificacion-2026-09-26.md
git commit -m "docs: README, cambios del prototipo y limitaciones"
```

**Criterios de aceptación:** AC12 (parte de README y CAMBIOS).
**Dependencias:** Q3. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea M2: Guion de demo

**Objetivo:** un guion de 5–8 minutos que se pueda seguir sin improvisar, con datos de ejemplo y un plan si algo falla.

**Archivos:**
- Crear: `docs/guion-demo.md`

- [ ] **Paso 1: Escribir `docs/guion-demo.md`** con este contenido:

````markdown
# Guion de demo de 0Fraude (6–7 minutos)

Equipo ZeroScam. Simulador iPhone 17, modo oscuro, volumen bajo.

## Antes de empezar (5 minutos antes)
- [ ] Restablecer los datos: entrar como `owner@0fraude.mx` / `Equipo#2026zs` › Perfil › Ajustes › Usuarios y roles › Restablecer datos de demostración (o lanzar con `-reiniciarDemo` desde Xcode › Edit Scheme › Arguments).
- [ ] Permiso de notificaciones ya concedido (Ajustes de iOS › 0Fraude › Notificaciones).
- [ ] La galería del simulador tiene fotos de ejemplo.
- [ ] Teclado en pantalla activo (⌘K) para que se vea al escribir.
- [ ] Cerrar sesión: la app debe quedar en Registro.

## 1. Registro seguro (0:00–1:00)
1. "0Fraude ayuda a reportar y consultar fraudes en línea. Empezamos creando una cuenta."
2. Escribir correo `lucia@comunidad` (sin dominio) y contraseña `password123` → mostrar los mensajes: correo inválido y "Esa contraseña es muy común".
3. Corregir: nombre Lucía, apellido Torres, usuario `lucia_t`, correo `lucia@comunidad.test`, contraseña `Fraude0-Cero` (mostrar el botón del ojo), aceptar el aviso (abrirlo un segundo).
4. CREAR CUENTA → Login con el correo ya escrito. "La contraseña se guarda como hash PBKDF2 con sal; nadie puede leerla."

## 2. Inicio de sesión y bloqueo (1:00–1:45)
1. Escribir una contraseña equivocada dos veces → "Correo o contraseña incorrectos." "No decimos si el correo existe; a los 5 intentos se bloquea con tiempo creciente."
2. Entrar con `usuario@0fraude.mx` / `Alerta#2026mx`. "La sesión queda en el Keychain: si cierro la app, sigo dentro."

## 3. Comunidad (1:45–3:00)
1. Inicio: "Hola, Ana", campana con 1 notificación, Alertas críticas calculadas.
2. Tocar "Falsa liquidación de tienda de electrónica": tipo, severidad, autor, ciudad, el enlace **desactivado** (`hxxps://…[.]shop`) que no se puede abrir, y el modus operandi.
3. Guardar (marcador) y Compartir: mostrar el texto con el enlace desactivado.
4. "Yo también" → "Solo confirmar". Escribir un comentario y publicarlo.
5. Buscar: escribir "banco" → resultado; chip #SorteoFalso; riesgo "ALTO o más".

## 4. Reportar con evidencia (3:00–4:15)
1. Pestaña Reportar: anónimo encendido, "A otra persona" (mostrar que pide autorización y que sus datos nunca se publican), volver a "A mí".
2. Ciudad CDMX, tipo Tienda Clonada, título "Tienda falsa de consolas en Instagram", URL `https://consolas-baratas.store`, descripción breve.
3. Evidencia › Elegir de la galería: "La foto se guarda sin ubicación GPS."
4. ENVIAR → folio y estado RECIBIDO → VER MIS REPORTES: aparece como RECIBIDO.

## 5. Moderación (4:15–5:30)
1. Cerrar sesión. Entrar como `admin@0fraude.mx` / `Revisa#2026zs`.
2. Ajustes › Revisión de reportes › el reporte nuevo: ve el autor real aunque sea anónimo y la evidencia.
3. EN REVISIÓN → aplicar; luego VALIDADO con riesgo ALTO. "El servidor solo permite transiciones válidas y nadie modera su propio reporte."

## 6. Notificación y privacidad (5:30–6:30)
1. Cerrar sesión y entrar como Usuario: aviso del sistema y la campana con 3 (las dos de la moderación y la que ya tenía). Abrir la notificación → el reporte ya es público.
2. Ajustes › Seguridad y privacidad: verificación en dos pasos, perfil público, analíticas; "Descargar mis datos" (derecho de acceso) y "Eliminar mi cuenta" (cancelación). "Seguimos la LFPDPPP de 2025."

## Cierre (6:30–7:00)
"Todo lo que se ve funciona igual contra la API NestJS del equipo: la app solo cambia de enchufe." Mencionar las pruebas automáticas y `docs/seguridad.md`.

## Si algo falla
- La foto no carga: usar otra foto o saltar la evidencia.
- No aparece el aviso del sistema: mostrar la campana (la notificación está en la app).
- Algo se ve raro: Owner › Restablecer datos de demostración y seguir desde la sección actual.
````

- [ ] **Paso 2: Ensayar** con cronómetro (Q3 punto 13) y ajustar tiempos.

- [ ] **Paso 3: Commit**

```bash
git add docs/guion-demo.md
git commit -m "docs: guion de demo de 7 minutos"
```

**Criterios de aceptación:** dos ensayos dentro de 5–8 minutos.
**Dependencias:** F1–F21. **Esfuerzo:** S. **Riesgo:** bajo.

### Tarea M3: Verificación final y cierre

**Objetivo:** comprobar los 12 criterios de aceptación con evidencia, dejar el documento de verificación y fusionar a `main`.

**Archivos:**
- Modificar: `docs/verificacion-2026-10-19.md` (tabla de criterios)

- [ ] **Paso 1: Comandos finales** (guardar la salida resumida en el documento):

```bash
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI"
xcodebuild -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd clean build 2>&1 | tee build/final.log | tail -3
grep "warning:" build/final.log | grep -v appintentsmetadataprocessor | wc -l        # AC8: 0
xcodebuild test -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd -resultBundlePath build/final.xcresult 2>&1 | tail -5   # AC9
grep -rn "EmptyView()" PrototipoApp/Views/Route+Destination.swift | wc -l               # 0: todas las rutas tienen pantalla
grep -rln "CargaView(" PrototipoApp/Views | wc -l                                       # AC4: ≥ 9
```

- [ ] **Paso 2: Tabla de criterios.** En `docs/verificacion-2026-10-19.md`, una fila por AC1–AC12 con: resultado (✓/✗), evidencia (comando, prueba o captura) y, si es ✗, la limitación anotada en el README. Revisar el apéndice B (cobertura de controles) fila por fila para AC1.

- [ ] **Paso 3: Fusionar.** Con todo en verde, fusionar la rama de la fase a `main`:

```bash
git switch main
git merge --no-ff fase-9-cierre -m "Prototipo completo de 0Fraude"
git log --oneline | head -5
```

(No hay remoto: no se hace `push`.)

- [ ] **Paso 4: Commit del documento** (si no entró en la fusión).

**Criterios de aceptación:** AC1–AC12 con evidencia; `main` contiene el prototipo completo.
**Dependencias:** todas. **Esfuerzo:** S. **Riesgo:** bajo.

---

## 9. Orden, dependencias y esfuerzo

### 9.1 Fases e hitos

Cada fase trabaja en su rama y se fusiona a `main` solo con `BUILD`, `UNIT` y `UI` en verde.

| Fechas (2026) | Fase | Rama | Tareas | Hito verificable |
|---|---|---|---|---|
| Mié 7 – Jue 8 oct | 0. Arranque | `fase-0-base` | P1, P2, Q1 | Git con línea base; "0Fraude" en el ícono; `UNIT` y `UI` corren |
| Jue 8 – Vie 9 | 1. Dominio y seguridad pura | `fase-1-dominio` | D1, S1, S2, S4, S5, S6, S3 | ~70 pruebas unitarias en verde; ninguna vista cambió |
| Vie 9 – Lun 12 | 2. Servidor Demo e integración | `fase-2-datos` | D2, D3, D4, D5, D6, D7, D8, D9, V1, D10 | La app navega con sesión real que sobrevive al reinicio; `admin`/`admin` ya no existe |
| Lun 12 | 3. Autenticación | `fase-3-auth` | F1, F2, F3 | Registro, login con bloqueo y cerrar sesión reales |
| Lun 12 – Mié 14 | 4. Reportes | `fase-4-reportes` | F4–F14 | Todos los `// TODO` de reportes funcionan |
| Mié 14 – Jue 15 | 5. Roles y estados | `fase-5-roles` | F15, F16, F17 | Moderación con historial; notificaciones; Owner |
| Jue 15 – Vie 16 | 6. Cuenta y privacidad | `fase-6-cuenta` | F18, F19, F20, F21 | Perfil, contraseña, switches y ARCO |
| Lun 12 – Jue 15 (en paralelo) | 7. Remote | `fase-7-remote` | R1, R2, R3 | Contrato y SQL entregables al equipo; Remote compila y pasa sus pruebas |
| Vie 16 – Sáb 17 | 8. UX y accesibilidad | `fase-8-ux` | V2, V3, U1, U2, U3, U4, U5, U6 | Dynamic Type, VoiceOver, claro/oscuro, ícono |
| Sáb 17 – Dom 18 | 9. Pruebas y documentos | `fase-9-cierre` | Q2, M2, Q3, S7, M1 | Suite completa en verde; capturas; documentos |
| Lun 19 | Cierre | `fase-9-cierre` → `main` | M3 + ensayo | Criterios AC1–AC12 con evidencia |
| Mar 20 | Entrega | — | Demo | — |

### 9.2 Grafo de dependencias

```mermaid
flowchart TD
    P1 --> P2 --> Q1
    Q1 --> D1 & S1 & S2 & S4 & S5
    D1 --> S6 & D2
    D1 & S4 --> S3
    D1 & S5 --> D3
    D2 & S3 --> V1
    D3 & S1 & S3 & S4 --> D4
    D2 & D4 & S6 --> D5 --> D6 --> D7
    D7 & S2 --> D8 --> D9
    D9 & V1 --> D10
    D10 --> F1 & F2 & F4 & F5 & F9 & F12 & F13 & F14 & F19
    F2 --> F3
    F5 --> F6 & F7 & F8
    F7 --> F9
    F9 --> F10 --> F11
    F4 --> F11 & F18
    F5 & F10 --> F15 --> F17
    F4 & F15 --> F16
    F1 & F18 --> F20 --> F21
    D2 & D3 & S2 --> R2
    D7 --> R1
    R1 & R2 --> R3
    F21 & R2 --> S7
    F17 & F21 --> V2 & V3 & U1
    U1 --> U2 & U4 & U5 & U3 --> U6
    V2 & V3 & U2 & U4 & U5 & U6 --> Q2 --> Q3
    F21 --> M2 --> Q3
    Q3 --> M1 --> M3
    S7 & R3 --> M3
```

### 9.3 Qué va en paralelo (subagentes) y qué no

Recomendación: `superpowers:subagent-driven-development`, un subagente por tarea y un revisor por tarea; las tareas de una misma corriente se hacen en orden. Cada corriente paralela trabaja en su propio *worktree* (`superpowers:using-git-worktrees`, o `isolation: "worktree"`), con su propia carpeta de compilación (`-derivedDataPath $HOME/Library/Caches/0fraude-dd-<corriente>`) y **su propio simulador** para las pruebas de interfaz (iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone 17e; todos están instalados). Quien coordina fusiona a la rama de la fase.

| Fase | Corrientes en paralelo | Secuencial |
|---|---|---|
| 1 | A: D1 → S6 → S3 · B: S1, S5, S4 · C: S2 | S3 espera a D1 y S4 |
| 2 | Columna: D2 → D3 → D4 → D5 → D6 → D7 → D8 → D9 → D10 · Lateral: V1 (tras D2 y S3); R2 (tras D3); R1 (tras D7) | La columna es la ruta crítica: un solo agente |
| 3–6 | 1: F1 → F2 → F3 → F19 · 2: F4 → F13 → F14 · 3: F5 → F6 → F7 → F8 · 4: F9 → F10 → F11 · 5: F12 · luego F15 → F16 → F17 y F18 → F20 → F21 · Remote: R1 → R2 → R3 | F15 espera a F5 y F10; F16 a F4 y F15 |
| 8 | — | U1 primero (toca todas las vistas); luego U2, U3, U4, U5, U6, V2 y V3 uno tras otro para no chocar en los mismos archivos |
| 9 | M2 en paralelo con Q2 | Q3 → S7 → M1 → M3 |

Archivos que varias tareas tocan (conflictos esperables y pequeños): `Route+Destination.swift`, `AppState.swift`, `SettingsView.swift`, `PrototipoAppUITests/Soporte/Ayudantes.swift`. Regla: cada tarea cambia solo sus líneas y quien fusiona resuelve.

### 9.4 Ruta crítica

P1 → P2 → Q1 → D1 → D2 → D3 → D4 → D5 → D6 → D7 → D8 → D9 → D10 → F9 → F10 → F11 → F15 → F16 → U1 → U3 → U6 → Q2 → Q3 → M1 → M3 ≈ **65 h** de trabajo encadenado (con ~6 h efectivas por día y la revisión de Alex al cerrar cada fase, cabe en 11 días hábiles; queda el lunes 19 de colchón).

### 9.5 Esfuerzo por tarea

S ≈ 1 h · M ≈ 2.5 h · L ≈ 5 h (implementación con pruebas; sin la revisión de Alex). Prioridad: **P1** imprescindible para la demo o la seguridad · **P2** importante · **P3** si hay tiempo.

| Tarea | Título | Fase | Esf. | Prio. | Depende de |
|---|---|---|---|---|---|
| P1 | Línea base en git | 0 | S | P1 | — |
| P2 | Nombre "0Fraude" y textos del sistema en español | 0 | S | P1 | P1 |
| Q1 | Targets de pruebas y esquema compartido | 0 | M | P1 | P2 |
| D1 | Modelos del dominio | 1 | M | P1 | Q1 |
| S1 | Aleatorios y hash de contraseñas | 1 | S | P1 | Q1 |
| S2 | Keychain y limpieza tras reinstalar | 1 | S | P1 | Q1 |
| S3 | Saneamiento y validación | 1 | M | P1 | D1, S4 |
| S4 | Herramientas de URL | 1 | S | P1 | Q1 |
| S5 | Límite de intentos | 1 | S | P1 | Q1 |
| S6 | Evidencia sin metadatos y archivos protegidos | 1 | M | P1 | D1 |
| D2 | Contratos: errores, repositorios, carga | 2 | S | P1 | D1 |
| D3 | Base y archivo del modo Demo | 2 | S | P1 | D1, S5 |
| D4 | Datos semilla | 2 | M | P1 | D3, S1, S3, S4 |
| D5 | Servidor Demo: núcleo, sesión, vista | 2 | L | P1 | D2, D4, S6 |
| D6 | Servidor Demo: reportes y comentarios | 2 | L | P1 | D5 |
| D7 | Servidor Demo: cuenta, moderación, Owner | 2 | M | P1 | D6 |
| D8 | DemoBackend, configuración y dependencias | 2 | S | P1 | D7, S2 |
| D9 | Stores | 2 | M | P1 | D8 |
| V1 | Componentes de formulario y de estado | 2 | M | P1 | D2, S3 |
| D10 | Integración: rutas, raíz, escudo | 2 | M | P1 | D9, V1 |
| F1 | Registro real y aviso de privacidad | 3 | M | P1 | D10 |
| F2 | Login, bloqueo y dos pasos | 3 | M | P1 | D10 |
| F3 | Cerrar sesión | 3 | S | P1 | F2 |
| F4 | Inicio con datos | 4 | S | P1 | D10 |
| F5 | Detalle dinámico | 4 | M | P1 | D10 |
| F6 | Guardar y compartir | 4 | S | P1 | F5 |
| F7 | "Yo también" | 4 | S | P1 | F5 |
| F8 | Comentarios | 4 | M | P1 | F5 |
| F9 | Formulario de reporte y envío | 4 | L | P1 | D10, F7 |
| F10 | Evidencia | 4 | M | P1 | F9, F5 |
| F11 | Perfil: mis reportes, guardados, editar, eliminar | 4 | M | P1 | F9, F4 |
| F12 | Búsqueda | 4 | M | P1 | D10 |
| F13 | Estadísticas calculadas | 4 | S | P1 | D10 |
| F14 | Guía con tres artículos | 4 | S | P2 | D10 |
| F15 | Moderación | 5 | L | P1 | F5, F10 |
| F16 | Notificaciones | 5 | M | P1 | F4, F15 |
| F17 | Owner | 5 | M | P2 | F15 |
| F18 | Editar perfil y avatar | 6 | M | P1 | F4 |
| F19 | Cambiar contraseña | 6 | S | P1 | D10 |
| F20 | Switches de privacidad y aviso | 6 | M | P1 | F1, F18 |
| F21 | Exportar datos y eliminar cuenta | 6 | M | P1 | F20 |
| R1 | Contrato de la API y migración SQL | 7 | M | P2 | D7 |
| R2 | Cliente HTTP con refresh y ATS | 7 | M | P2 | D3, S2 |
| R3 | RemoteBackend | 7 | L | P3 | R1, R2 |
| V2 | Pasada de estados y confirmaciones | 8 | S | P2 | F17, F21 |
| V3 | Teclado | 8 | S | P2 | F21 |
| U1 | Dynamic Type y alturas | 8 | M | P2 | F21 |
| U2 | VoiceOver | 8 | M | P2 | U1 |
| U3 | Modo claro y oscuro | 8 | L | P3 | U1 |
| U4 | Horizontal y ancho legible | 8 | S | P3 | U1 |
| U5 | Animaciones y hápticos | 8 | S | P3 | U1 |
| U6 | Ajustes visuales, ícono y acento | 8 | S | P2 | U3 (o plan B de U3) |
| Q2 | Pruebas de interfaz de punta a punta | 9 | L | P1 | V2, V3, U1–U6 |
| Q3 | Revisión manual y capturas | 9 | M | P2 | Q2, M2 |
| S7 | Modelo de amenazas y auditoría final | 9 | M | P2 | F21, R2 |
| M1 | README, cambios y limitaciones | 9 | S | P2 | Q3 |
| M2 | Guion de demo | 9 | S | P1 | F21 |
| M3 | Verificación final y cierre | 9 | S | P1 | todas |

**Totales:** 58 tareas · 24 S + 27 M + 7 L ≈ 24 h + 67.5 h + 35 h = **≈ 126 h** de implementación. Por prioridad: P1 = 42 tareas, P2 = 12, P3 = 4. (Q2 es P1 aunque dependa de tareas P2/P3: si alguna se recorta, Q2 corre sobre lo que exista.)

### 9.6 Línea de corte

Si el viernes 16 de octubre la fase 6 no está cerrada, se recorta en este orden (cada recorte tiene su plan B y se anota en "Limitaciones conocidas"):

1. U5 y U4 (no afectan la demo).
2. U3 → plan B: app oscura fija y el switch se vuelve el renglón informativo "Apariencia · Oscuro".
3. R3 → se entrega contrato, SQL y `APIClient` probado; `RemoteBackend` queda para cuando exista el backend.
4. F17 → se deja solo "Restablecer datos de demostración" para el Owner (S) y el resto se documenta.
5. La parte de PDF de F10 (se queda galería y cámara).

Lo que **no** se recorta: autenticación real, hash, Keychain, validación, moderación, notificaciones dentro de la app, ARCO y el guion.

---

## 10. Riesgos y plan B

| # | Riesgo | Prob. | Impacto | Señal temprana | Plan B |
|---|---|---|---|---|---|
| R1 | Editar `project.pbxproj` a mano rompe el proyecto o los targets no aparecen | Media | Alto | `plutil -lint` falla o `xcodebuild -list` no muestra los targets | `git checkout` del archivo y crear los targets desde Xcode (pasos en Q1, 2 minutos de Alex) |
| R2 | Keychain falla en pruebas unitarias (`-34018`, `errSecMissingEntitlement`) | Media | Medio | `SecretStoreTests` en rojo | Confirmar `TEST_HOST`/`BUNDLE_LOADER`; si persiste, las pruebas usan `MemorySecretStore` y el Keychain real se prueba con la app (Q3) |
| R3 | Aislamiento por defecto `MainActor` + Swift 5: errores de "main actor-isolated … in nonisolated context" | Alta | Medio | Errores de compilación en `Model/`, `Security/`, `Data/` | Regla de `nonisolated` en tipos, extensiones y `static` de actores (Restricciones globales); si un tipo se resiste, moverlo a un archivo propio marcado `nonisolated`; nunca `@unchecked Sendable` en código de la app |
| R4 | PBKDF2 con 600,000 iteraciones es lento | Media | Bajo | Login > 1 s; pruebas lentas | Ya mitigado: `BotonAccion` muestra indicador, las cuentas nuevas en pruebas usan 1,000; en dispositivo real medir; no bajar de 600,000 sin anotarlo |
| R5 | SwiftData (opción descartada) | — | — | — | No se usa: JSON + `actor` evita sus límites con `MainActor` y con `Sendable` (sección 2.3) |
| R6 | PhotosPicker y cámara en el simulador | Alta | Medio | El selector no se automatiza; no hay cámara | `-evidenciaDePrueba` para XCUITest; galería revisada a mano; la cámara solo aparece si existe (en iPhone real) |
| R7 | Conflictos con las 4 pilas: datos viejos en pantallas apiladas, recargas en cascada, `.report` empujado en otra pestaña | Media | Medio | Parpadeos, detalles con datos viejos | `version` + `.task(id:)` recarga conservando datos; detalle con error "ya no está disponible"; pruebas Q2; si hay parpadeo, recargar solo la lista visible |
| R8 | Pruebas de interfaz intermitentes (tiempos, teclado, autollenado de contraseñas "Contraseña segura") | Media | Medio | Fallas que desaparecen al repetir | Esperas explícitas (`esperar`), `tocar(en:)`; si el autollenado de `.newPassword` estorba, en `-uiTesting` no poner `textContentType` en `OfraudeSecureField` (leer `appConfig.esUITest`) |
| R9 | Tiempo: 58 tareas en 13 días | Alta | Alto | Fase 2 termina después del martes 13 | Corrientes en paralelo (9.3) y línea de corte (9.6) |
| R10 | El backend del equipo usa otros nombres o formatos | Alta | Bajo | Diferencias con `docs/api-contrato.md` | Solo se cambian `Data/Remote/DTOs.swift`, `RemoteBackend.swift` y el contrato (marcado `BACKEND:`); vistas y stores no cambian |
| R11 | La protección de archivos no se aplica en el simulador | Cierta | Bajo | — | Documentado; si hay iPhone, comprobar en dispositivo |
| R12 | La persona niega el permiso de notificaciones | Media | Bajo | Switch no se queda encendido | Se explica y la campana sigue funcionando; para la demo se concede antes |
| R13 | El texto de fechas relativas cambia entre versiones de iOS | Baja | Bajo | `FormatoTests` en rojo | Las pruebas comparan con `contains` en minúsculas |
| R14 | El simulador se apaga entre comandos | Alta | Bajo | "Unable to boot" | `xcrun simctl boot "iPhone 17"; open -a Simulator` (`xcodebuild test` también lo arranca) |
| R15 | Corrientes paralelas usan el mismo simulador o la misma carpeta de compilación | Media | Medio | Fallas raras de compilación o pruebas pisadas | Un simulador y un `-derivedDataPath` por corriente (9.3) |
| R16 | `xcresulttool export attachments` cambia el formato de `manifest.json` | Baja | Bajo | El script no copia nada | Abrir el manifest y ajustar las 2 claves del script |
| R17 | Se modifica por error el proyecto original | Baja | Alto | Cambios en `../PrototipoApp` | Nunca trabajar fuera de `PrototipoApp-SwiftUI/`; M3 comprueba `git -C "../PrototipoApp" status --short` vacío (el original tiene su propio repo) |
| R18 | La migración SQL falla por el nombre de la llave foránea | Media | Bajo | Error en `DROP FOREIGN KEY` | `SHOW CREATE TABLE Reporte;` y usar el nombre real (R1 paso 4) |

---

## Apéndice A. Datos semilla

**Usuarios**

| id | Rol | Nombre | Alias | Correo | Perfil público | Acceso |
|---|---|---|---|---|---|---|
| 1 | Owner | Equipo ZeroScam | `owner_zs` | owner@0fraude.mx | Sí | `Equipo#2026zs` |
| 2 | Administrador | Carlos Méndez | `admin_zs` | admin@0fraude.mx | Sí | `Revisa#2026zs` |
| 3 | Usuario | Ana López | `usuario_01` | usuario@0fraude.mx | No | `Alerta#2026mx` |
| 4 | Usuario | Luis Herrera | `tecno_mx` | luis@comunidad.test | Sí | Sin acceso (contraseña aleatoria) |
| 5 | Usuario | Marta Ruiz | `compras_seguras` | marta@comunidad.test | Sí | Sin acceso |
| 6 | Usuario | Sofía Ramírez | `vecina_alerta` | sofia@comunidad.test | No | Sin acceso |

**Reportes** (antigüedad en horas al sembrar; "previas" = conteo histórico de "Yo también")

| id | Autor | Tipo | Estado | Riesgo | Ciudad | Hace | Título | URL o texto | Previas |
|---|---|---|---|---|---|---|---|---|---|
| 101 | tecno_mx | Oferta Falsa | VALIDADO | ALTO | CDMX | 2 h | Falsa liquidación de tienda de electrónica | liquidacion-electronica-mx.shop | 1,200 |
| 102 | compras_seguras | Sorteo Falso | VALIDADO | ALTO | Guadalajara | 5 h | Sorteo falso de iPhone 17 en Instagram | instagram.com/iphone17.sorteo.oficial | 450 |
| 103 | tecno_mx | Tienda Clonada | CANALIZADO | MUY ALTO | Monterrey | 26 h | Tienda clonada de tenis deportivos | n1ke-outlet-mexico.com | 610 |
| 104 | vecina_alerta | Marketplace | VALIDADO | BAJO | Puebla | 30 h | Vendedor de consolas que no entrega | Perfil 'Gamer Store MX' | 85 |
| 105 | compras_seguras | Llamada | VALIDADO | ALTO | CDMX | 50 h | Llamada falsa del SAT pidiendo pago de multa | +52 55 8765 4321 | 390 |
| 106 | vecina_alerta | Oferta Falsa | VALIDADO | MEDIO | Querétaro | 72 h | Cupón falso de supermercado por WhatsApp | cupones-supermercado-mx.info (http) | 270 |
| 107 | tecno_mx | Sorteo Falso | CANALIZADO | ALTO | Mérida | 96 h | Rifa falsa de automóvil en TikTok | tiktok.com/@rifas.autos.mx | 180 |
| 108 | compras_seguras | Otro: Phishing bancario | VALIDADO | MUY ALTO | CDMX | 120 h | Página clonada de banco para 'actualizar datos' | banco-actualiza-datos.com (http) | 520 |
| 109 | vecina_alerta | Marketplace | VALIDADO | MEDIO | Guadalajara | 144 h | Renta de departamento inexistente | Anuncio con depósito por adelantado | 95 |
| 110 | tecno_mx | Otro: Empleo falso | VALIDADO | MEDIO | Tijuana | 168 h | Ofertas de empleo falsas por WhatsApp | +52 664 000 1122 | 140 |
| 111 | compras_seguras | Oferta Falsa | CANALIZADO | ALTO | Monterrey | 216 h | Boletos de concierto en preventa falsa | boletos-preventa-mx.com | 230 |
| 112 | vecina_alerta | Llamada | VALIDADO | ALTO | Puebla | 240 h | Llamada de falso familiar detenido | Extorsión telefónica | 160 |
| 113 | tecno_mx | Tienda Clonada | VALIDADO | ALTO | CDMX | 288 h | Tienda clonada de Mercado Libre | mercadolibre-ofertas.store | 300 |
| 114 | compras_seguras | Sorteo Falso | VALIDADO | BAJO | León | 336 h | Sorteo falso de despensa por aniversario | facebook.com/despensas.gratis.mx | 60 |
| 115 | vecina_alerta | Otro: Préstamo falso | CANALIZADO | ALTO | Oaxaca | 384 h | Préstamo falso con anticipo | prestamos-rapidos-mx.net | 210 |
| 116 | tecno_mx | Oferta Falsa | VALIDADO | MEDIO | Toluca | 480 h | Descuentos de 90% en perfumes por Instagram | instagram.com/perfumes.outlet.90 | 120 |
| 117 | vecina_alerta (anónimo) | Otro: Smishing | RECIBIDO | — | CDMX | 1 h | Mensaje de paquetería para pagar envío | paqueteria-entregas-mx.co (http) | — |
| 118 | compras_seguras | Marketplace | EN REVISIÓN | — | Monterrey | 20 h | Venta de mascotas con depósito (persona afectada: Rosa Martínez) | Perfil 'Criadero Norte' | — |
| 119 | tecno_mx | Otro: Phishing de programa social | RECIBIDO | — | Puebla | 8 h | Supuesta beca del gobierno pide CURP | becas-bienestar-registro.com | — |
| 120 | vecina_alerta | Otro: Cadena | RECHAZADO | — | León | 72 h | Mensaje de cadena sin datos | — | — |
| 121 | usuario_01 | Tienda Clonada | EN REVISIÓN | — | CDMX | 3 h | Descuento falso de laptop en tienda clonada | laptops-liquidacion.store | — |
| 122 | usuario_01 | Oferta Falsa | VALIDADO | MEDIO | CDMX | 30 h | Oferta falsa 2x1 en boletos de concierto por Instagram | instagram.com/boletos2x1.oficial | 340 |
| 123 | usuario_01 | Llamada | RECIBIDO | — | CDMX | 0.5 h | Llamada de supuesto banco pidiendo código | +52 55 1234 5678 | — |

**Además:** comentarios 301–305 (los dos del storyboard en 101), guardados del Usuario: 101 y 102, notificaciones del Usuario: 501 (leída, 122 validado) y 502 (sin leer, 121 en revisión), historial de estados completo de cada reporte. Cifras que salen de esta semilla: personas ayudadas 5,362; reportes verificados 17; estafas detenidas 4; zonas cubiertas 10.

---

## Apéndice B. Cobertura de controles

Cada control visible de la app y quién lo implementa. "Ya funcionaba" = navegación del original que se conserva.

| Pantalla | Control | Qué hace ahora | Tarea | Prueba |
|---|---|---|---|---|
| Registro | Nombre, apellido, usuario, correo, país, contraseña, confirmación | Validan al salir del campo; contraseñas ocultas con ojo | F1, V1 | `testRegistroValidaYLlevaALogin` |
| | Aviso (casilla) y "Leer el aviso" | Obligatorio; abre el aviso | F1 | `testElAvisoDePrivacidadSeAbreDesdeRegistro` |
| | CREAR CUENTA | Crea la cuenta y lleva a Login | F1 | ídem |
| | "¿Ya tienes cuenta?" | Abre Login (ya funcionaba) | D10 | `entrar()` en todas |
| Login | Correo, contraseña (ojo) | Sesión real; bloqueo con cuenta regresiva | F2 | `testLoginIncorrectoYBloqueo` |
| | INICIAR SESIÓN | Entra; pide código si hay 2 pasos | F2 | `testLoginCorrectoPersisteSesion`, `testDosPasosPideCodigoAlEntrar` |
| | "¿No tienes cuenta?" | Regresa a Registro (ya funcionaba) | — | manual |
| Código 2 pasos | Campo, VERIFICAR, Cancelar | Verifica el código; cancela el desafío | F2 | `testDosPasosPideCodigoAlEntrar` |
| Inicio | Campana (antes sello) | Abre Notificaciones, muestra no leídas | F16 | `testLaCampanaCuentaYAbreElReporte` |
| | REPORTAR INCIDENTE | Abre la pestaña Reportar (ya funcionaba) | F4 | `testBotonReportarAbrePestana` |
| | 3 categorías | Abren Buscar ya filtrado | F12 | `testCategoriaDeInicioFiltraBuscar` |
| | Alertas críticas | Abren su propio detalle | F4, F5 | `testInicioMuestraLasAlertasYAbreSuDetalle` |
| | CONSULTAR GUÍA, VER ESTADÍSTICAS | Abren su pantalla | F14, F13 | `testCadaCapituloAbreSuArticulo`, `testEstadisticasSeCalculan` |
| Buscar | Campo | Filtra por texto (sin acentos ni mayúsculas) | F12 | `testBuscarPorTextoChipYRiesgo` |
| | 4 chips | Alternan filtros | F12 | ídem |
| | Riesgo | Filtra por riesgo mínimo | F12 | ídem |
| | Categorías | Filtran por tipo con conteo real | F12 | ídem |
| | Resultados, Limpiar filtros | Abren el detalle; vacían filtros | F12 | ídem, `testSinResultadosMuestraElEstadoVacio` |
| Reportar | Anónimo | Oculta el autor a la comunidad | F9, D5 | `DemoServerVistaTests` |
| | A mí / A otra persona | Muestra u oculta datos de la persona y su autorización | F9 | `otraPersonaExigeDatosYAutorizacion` |
| | Ciudad, tipo, "Otro", título, fecha, URL, descripción | Validan | F9 | `testElFormularioNoAceptaUnEnlacePeligroso` |
| | Evidencia (agregar, quitar, ver) | Galería, cámara, PDF; sin metadatos | F10 | `testEvidenciaSeAgregaYSeQuita` |
| | ENVIAR REPORTE | Guarda y abre Éxito | F9 | `testEnviarReporteMuestraFolio…` |
| Éxito | CONTINUAR, VER MIS REPORTES | Vacían pilas e ir a Inicio o Perfil | F9 | `testYoTambienYEnvioVacianLasPilas` |
| Perfil | Engrane, lápiz del avatar, EDITAR PERFIL | Ajustes; Editar perfil | F3, F11, F18 | `testCerrarSesion`, `testEditarPerfilValidaYGuarda` |
| | MIS REPORTES / GUARDADOS | Segmentos con datos reales | F11 | `testMisReportesYGuardadosVienenDeLosDatos` |
| | Tarjetas | Abren su detalle | F11 | ídem |
| | Opciones: Editar / Eliminar / Cancelar | Editar antes de validar; eliminar con confirmación | F11 | `testEditarSoloAntesDeValidar`, `testEliminarPideConfirmacion` |
| | Quitar de guardados | Persiste | F11 | `testMisReportesYGuardadosVienenDeLosDatos` |
| Ajustes | Editar Perfil, Seguridad y Privacidad, Guía | Navegan (ya funcionaba) | — | varias |
| | Notificaciones | Guarda preferencia y pide permiso | F16 | Q3 manual |
| | Modo Oscuro | Cambia la apariencia | U3 | `testModoClaroSeGuarda` |
| | Idioma | Texto informativo (no es control) | — | — |
| | Reportes Guardados (N) | Conteo real; abre Perfil en Guardados | F11 | `testAjustesGuardadosAbrePerfilEnLaRaiz` |
| | Revisión de reportes / Usuarios y roles | Solo staff / solo Owner | F15, F17 | `testUnUsuarioNoVeAdministracion`, `testOwnerSuspende…` |
| | CERRAR SESIÓN | Abre la confirmación | F3 | `testCerrarSesion` |
| Cerrar sesión | CERRAR SESIÓN / CANCELAR | Revoca y vuelve a Registro / regresa | F3 | `testCerrarSesion` |
| Editar perfil | Cambiar Avatar, Quitar foto | Foto sin metadatos | F18 | Q3 manual |
| | Campos y GUARDAR CAMBIOS | Validan y guardan; correo pide contraseña | F18 | `testEditarPerfilValidaYGuarda`, `testCambiarCorreoPideContrasena` |
| Seguridad y privacidad | CAMBIAR CONTRASEÑA | Abre la pantalla (ya funcionaba) | F19 | `testCambiarContrasena` |
| | 2 pasos, Perfil público, Analíticas | Efecto real; apagar 2 pasos pide contraseña | F20 | `testDosPasos…`, `testApagarDosPasosPideContrasena` |
| | Aviso, Descargar mis datos, Eliminar mi cuenta | Aviso; JSON; cancelación | F20, F21 | `testExportarYEliminarCuenta` |
| Cambiar contraseña | 3 campos y GUARDAR | Verifica, aplica política, cierra otras sesiones | F19 | `testCambiarContrasena` |
| Detalle | Guardar, compartir | Persiste; texto desactivado | F6 | `testGuardarYQuitarPersiste`, `CompartirTests` |
| | Copiar enlace desactivado | Copia `hxxps://…[.]…` | F5 | Q3 manual |
| | Yo también | Confirma una vez y ofrece reportar | F7 | `testYoTambienSumaUnaVezYOfreceReportar` |
| | Comentario y publicar; eliminar comentario | Publica; borra con confirmación | F8 | `testComentarPublicaYSePuedeBorrar` |
| | Evidencia | Visor (autor y staff) | F10 | manual |
| | MODERAR REPORTE | Solo staff | F15 | `testModerarValidaYElReportePublica` |
| Guía | 3 capítulos | Cada uno su artículo | F14 | `testCadaCapituloAbreSuArticulo` |
| Notificaciones | Filas, Marcar leídas | Marcan y abren el reporte | F16 | `testLaCampanaCuentaYAbreElReporte` |
| Moderación | Filtros, reportes | Cola por estado | F15 | `testModerarValidaYElReportePublica` |
| Revisión | Estado, riesgo, observaciones, APLICAR CAMBIO | Máquina de estados con confirmación | F15 | ídem, `testRechazarExigeMotivo` |
| Usuarios | Filas (rol, suspender), Restablecer | Owner | F17 | `testOwnerSuspendeYLaCuentaNoEntra` |
| Eliminar cuenta | Contraseña, ELIMINAR, botón | Cancela la cuenta | F21 | `testExportarYEliminarCuenta` |
| Todas las listas | REINTENTAR | Vuelve a pedir | V1, V2 | `testSinRedSeVeElErrorConReintentar` |

---

## Apéndice C. Cobertura del esquema SQL

| Tabla | Destino en la app | Se crea / cambia en | Se ve en |
|---|---|---|---|
| `Rol` | `enum Rol`; filas en `database/zeroscam_semilla_catalogos.sql` | D1, R1 | Ajustes (staff/Owner), Usuarios (F17) |
| `Estado` | `enum EstadoReporte` (orden, final, transiciones) | D1, R1 | Mis reportes, Detalle, Moderación |
| `TipoFraude` | `enum TipoFraude` | D1, R1 | Reportar, Buscar, Detalle |
| `Usuario` | `Usuario` + `UsuarioFila` (hash) | D1, D5, D7, R1 (columnas nuevas) | Registro, Perfil, Editar perfil, Usuarios |
| `SitioWeb_URL` | `SitioWeb` (`asociarEnlace`, riesgo global al validar) | D6, D7 | Detalle (sitio desactivado) |
| `Reporte` | `Reporte` + `ReporteFila` | D1, D6, R1 (columnas nuevas, `id_usuario` NULL) | Todas las listas y el detalle |
| `Evidencia` | `Evidencia` + `EvidenciaFila` + archivos | D6, S6, F10 | Reportar, Detalle, Revisión |
| `Reporte_URL` | `ReporteFila.idSitio` (1 por reporte en la app) | D6 | Detalle |
| `Historial_Estado` | `HistorialEstado` + `HistorialFila` | D4, D6, D7 | Detalle (autor/staff), Revisión |
| `Notificacion_Alerta` | `Notificacion` + `NotificacionFila` | D6, D7, F16 | Campana, Notificaciones |
| `PersonaAfectada` *(nueva)* | `PersonaAfectada` | D1, R1 | Reportar, Detalle (autor/staff) |
| `Comentario` *(nueva)* | `Comentario` + `ComentarioFila` | D6, R1 | Detalle |
| `Reporte_Guardado` *(nueva)* | `ParUsuarioReporte` en `guardados` | D6, R1 | Perfil › Guardados, Ajustes |
| `Reporte_Confirmacion` *(nueva, propuesta)* | `ParUsuarioReporte` en `confirmaciones` | D6, R1 | "Yo también", estadísticas |
| `Sesion` *(nueva)* | `SesionFila` (SHA-256 del token) | D5, R1 | — (sesión persistente) |
| `Desafio_DosPasos` *(nueva, propuesta)* | `DesafioFila` | D5, R1 | Código de dos pasos |

---

## Apéndice D. Comandos

```bash
# Carpeta de trabajo
cd "/Users/alex/Documents/integracion-seguridad-informatica/IS Modulo Avril Swift/PrototipoApp-SwiftUI"

# BUILD
xcodebuild -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd build 2>&1 | tail -3

# UNIT (todas o una suite)
xcodebuild test -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd -only-testing:PrototipoAppTests 2>&1 | tail -8
xcodebuild test -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd -only-testing:PrototipoAppTests/ValidadorTests 2>&1 | tail -8

# UI (todas o una clase)
xcodebuild test -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd -resultBundlePath build/ui.xcresult -only-testing:PrototipoAppUITests 2>&1 | tail -8
xcodebuild test -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd -only-testing:PrototipoAppUITests/AutenticacionUITests 2>&1 | tail -8

# Modo Remote contra el backend del equipo
xcodebuild -scheme PrototipoApp -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $HOME/Library/Caches/0fraude-dd ZS_FUENTE_DATOS=remote ZS_URL_BASE=http://localhost:3000 build

# Simulador
xcrun simctl boot "iPhone 17"; open -a Simulator
xcrun simctl install "iPhone 17" $HOME/Library/Caches/0fraude-dd/Build/Products/Debug-iphonesimulator/PrototipoApp.app
xcrun simctl launch "iPhone 17" Tec-CCM.PrototipoApp-SwiftUI
xcrun simctl launch "iPhone 17" Tec-CCM.PrototipoApp-SwiftUI -reiniciarDemo        # vuelve a la semilla (solo Debug)
xcrun simctl ui "iPhone 17" appearance light                                       # o dark
xcrun simctl ui "iPhone 17" content_size accessibility-extra-large                 # o large para volver
xcrun simctl io "iPhone 17" screenshot docs/capturas/manual.png

# Capturas de las pruebas
scripts/exportar_capturas.sh build/ui.xcresult

# MySQL (lo corre Alex; pide su contraseña)
! mysql -u root -p -e "SHOW DATABASES;"
```

---

## Auto-revisión del plan (2026-10-07)

Hecha al terminar de escribirlo, contra el pedido del 2026-10-06 y el spec.

| Pregunta | Resultado | Cómo se comprobó |
|---|---|---|
| ¿Cada botón de la app queda cubierto? | Sí. Los controles de las 17 pantallas originales y de las 7 nuevas están en el apéndice B con su tarea y su prueba. Solo "Idioma" queda como texto informativo (no es un control). | Lectura de cada vista en `PrototipoApp/Views/` (sección 0.2) y apéndice B |
| ¿Cada tabla del SQL tiene destino? | Sí. Las 10 tablas de `zeroscam_base_datos.sql` y las 6 nuevas están en el apéndice C con su modelo, su tarea y dónde se ven. | Apéndice C contra el SQL |
| ¿Cada tarea tiene verificación? | Sí, 58 de 58: comando exacto (`BUILD`, `UNIT`, `UI` o `grep`) con el resultado esperado; S7 se verifica con 7 búsquedas que deben dar 0, M2 con dos ensayos cronometrados y M3 con los comandos finales. | Script que recorre cada "### Tarea" buscando criterios, verificación, dependencias, esfuerzo y archivos |
| ¿Faltan tareas o hay repetidas? | 58 tareas, sin duplicados ni huecos en la numeración (P1–P2, Q1–Q3, D1–D10, R1–R3, F1–F21, S1–S7, V1–V3, U1–U6, M1–M3). | Mismo script |
| ¿Quedaron marcadores sin resolver ("TBD", "pendiente de definir")? | No. Los `// BACKEND:` son huecos intencionales para el código real del equipo. | Búsqueda en el texto completo |
| ¿Coinciden las firmas entre tareas? | Sí. El orden de argumentos de los componentes y tipos compartidos (`CargaView`, `BotonAccion`, campos, `Endpoint`, stores, `DemoServer`, etc.) coincide en todas las llamadas; los métodos de `DemoServer`, `DemoBackend`, los stores y las vistas se revisaron a mano. | Script que compara etiquetas de cada llamada con la declaración |
| ¿Los identificadores de las pruebas de interfaz existen en el código de las vistas? | Sí, todos (incluidos los dinámicos como `inicio.alerta.<id>`). | Script que cruza los identificadores de las pruebas con el código de las tareas |
| ¿Están las 10 secciones pedidas? | Sí: 0 auditoría (con build real), 1 terminado y alcance, 2 arquitectura de datos (3 opciones comparadas, semilla, `AppState`, migración), 3 funcionalidad (una tarea por TODO), 4 seguridad (controles y STRIDE), 5 validación y estados, 6 UX y accesibilidad, 7 pruebas (targets, TDD, checklist manual, sin permiso de Accesibilidad), 8 documentación y guion, 9 orden y esfuerzo, 10 riesgos y plan B. | Tabla de contenido |
| ¿Respeta las restricciones? | No toca el proyecto original; no escribe código de producción en esta sesión (solo plan y spec); reutiliza `Theme/`, `Components.swift` y `AppState`; comentarios y documentos en español. | Revisión |

**Cambios respecto al pedido original que Alex debe confirmar** (vienen de decisiones posteriores del 2026-10-07 o de lo que encontré al leer el código):

1. **Git:** el pedido decía "sin git"; después Alex pidió ramas separadas. El plan empieza con `git init` y una rama por fase (P1).
2. **Quirks:** se corrigen `admin`/`admin`, contraseñas visibles y la falta de validación; "0FRAUDE" con cero se queda (es el nombre).
3. **Nombre visible:** "OFraude SwiftUI" → "0Fraude" (P2).
4. **Huecos de esquema extra** propuestos al equipo: `Reporte_Confirmacion`, `Reporte.texto_sospechoso`, `Usuario.avatar_ruta`, `preferencias`, `intentos_fallidos`/`bloqueado_hasta`, `Desafio_DosPasos` (R1).
5. **Ajustes visuales** de la tabla 6.1 (texto azul marino en botones naranjas, campana, ícono nuevo, etc.).
