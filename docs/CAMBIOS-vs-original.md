# OFraude en SwiftUI: qué cambió respecto al original

Migración de `PrototipoApp` (storyboard + UIKit) a esta copia (SwiftUI). El original no se tocó.

## Mapa escena → vista

| Storyboard (escena / controller) | SwiftUI |
|---|---|
| `nav-vc` (navigation controller raíz) | `AuthFlow` (`NavigationStack`) en `OFraudeApp.swift` |
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

Cada archivo en `Views/` lleva un comentario de cabecera "Reemplaza: …" con su escena original.

## Qué se conservó igual a propósito

- Todos los textos, colores y medidas son los del storyboard.
- Las credenciales de Login siguen fijas en código: `admin` / `admin`.
- Los campos de contraseña muestran el texto en claro (no son campos seguros), igual que el original.
- Ningún formulario valida nada.
- "0FRAUDE" se sigue escribiendo con cero, no con la letra O.
- Los botones que en el original eran `// TODO` (crear cuenta, enviar reporte, agregar/quitar evidencia, guardar, compartir, publicar comentario, Editar en el menú de Perfil) siguen sin hacer nada.
- El detalle de reporte (`ReportDetailView`) sigue mostrando siempre el mismo contenido fijo, sin importar desde qué tarjeta se abrió — así era en el original.

## Qué cambió y por qué

- **Bundle id y nombre visible.** `Tec-CCM.PrototipoApp-SwiftUI` / "OFraude SwiftUI", en vez del bundle id del original. Con el mismo id, instalar la copia sobrescribiría al original en el simulador y no se podrían comparar.
- **Tab bar oculto en pantallas empujadas.** En el original, los segues "show" se empujaban sobre el navigation controller que contiene al tab bar y lo cubrían por completo. En SwiftUI se logra con `.toolbar(.hidden, for: .tabBar)` en cada destino.
- **`AppState` en vez de buscar controllers dentro del tab bar.** Los saltos que antes hacían `selectedIndex`, `presetQuery` o `showGuardados()` ahora son asignaciones sobre un objeto compartido (`AppState`), con una pila de navegación por pestaña para poder vaciarlas todas desde cualquier pantalla (usado por "Continuar" en Éxito y por "Reportes Guardados" en Ajustes).
- **Sin una `ReportCard` única.** Las tarjetas de Inicio, Buscar y Perfil tienen contenido distinto entre sí; solo Perfil usa un modelo (`Report`), porque ahí se pueden quitar o eliminar tarjetas.
- **El aro del avatar** (Perfil y EditProfile) usa `.overlay(Circle().strokeBorder(...))` en vez de tocar `layer.borderColor` en código, que era la limitación que tenía el storyboard original.

## Quirk del original que no se replicó

La pestaña Reportar del original mostraba una barra de navegación con una flecha "atrás" hacia Login. Era un efecto secundario de que el tab bar estuviera empujado sobre el nav stack de Login, no una función real. En la copia esa barra queda vacía, sin flecha.

## Qué no se pudo comprobar

Ver `docs/verificacion-2026-09-26.md`. En resumen: no hay automatización de toques disponible en esta sesión (sin permiso de Accesibilidad, sin `idb`/`cliclick`), así que solo se comparó visualmente la pantalla de Registro contra el original (coinciden). El resto de los flujos queda como checklist ahí mismo para recorrerlos a mano.

## Cómo ajustar el aspecto

- **Colores:** `Theme/Theme.swift`. Un solo lugar para toda la paleta.
- **Campos, botones, tarjetas, barra superior:** `Theme/Components.swift`.
- Nada de estilo está repetido dentro de las vistas de pantalla; todas usan estas piezas compartidas.
