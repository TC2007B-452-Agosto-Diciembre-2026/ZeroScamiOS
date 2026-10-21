# Completar el prototipo de 0Fraude

Fecha: 2026-10-07 (pedido del 2026-10-06)
Autor: Equipo ZeroScam (Alex) con Claude
Estado: decisiones de alcance aprobadas por Alex en conversación el 2026-10-07. Este documento las deja por escrito; el plan de ejecución está en `docs/superpowers/plans/2026-10-06-completar-prototipo.md`.

## 1. Qué entendí

**Lo que Alex pidió:**

- Pasar de la migración fiel (storyboard → SwiftUI) a un **prototipo completo y presentable**: todo botón visible hace algo real y coherente, los datos sobreviven al cerrar la app, hay validación y estados de error/vacío/carga, y se puede demostrar de punta a punta en el simulador sin crashes.
- Aprovechar el ángulo de **seguridad informática** del módulo.
- La app se llama **0Fraude** (con cero). **ZeroScam** es el nombre del equipo, y por eso la base de datos se llama ZeroScam. No es un conflicto de nombres.
- Fecha límite: **martes 2026-10-20**.
- No tocar el proyecto original `IS Modulo Avril Swift/PrototipoApp/`.
- Trabajo nuevo en ramas de git separadas; `main` queda como base estable (esto cambia la decisión de "sin git" del 2026-09-26).

**Decisiones aprobadas el 2026-10-07:**

| Tema | Decisión |
|---|---|
| Capa de datos | **Enfoque A.** Protocolos de repositorio con dos implementaciones: **Demo** (local, persistente, con datos semilla; funciona como un "servidor dentro de la app") y **Remote** (API NestJS del equipo). Las vistas no saben cuál se usa. |
| Backend | NestJS + JWT (access + refresh) + MySQL ZeroScam, hecho por el equipo, con el mismo patrón del demo del profesor (`Frontendwebautenticado`): `POST /auth/login`, `POST /auth/refresh`, Bearer, 401 → refresh → reintento, errores `{ message }`. La app deja huecos marcados `// BACKEND:` para llenar cuando llegue el código real, y se entrega `docs/api-contrato.md` al equipo. |
| Roles con interfaz | Usuario, Administrador y Owner. Policía existe en la base pero no tiene interfaz. |
| Feed público y búsqueda | Solo reportes en **VALIDADO** y **CANALIZADO**. Cada usuario ve todos los suyos en Mis reportes, en cualquier estado. |
| Huecos del esquema | `Reporte.titulo`, `es_anonimo`, `afectado`, `ciudad`, `tipo_otro`; tablas `PersonaAfectada`, `Comentario`, `Reporte_Guardado`, `Sesion`; `Usuario.alias`, `biografia` y campos de consentimiento; `Reporte.id_usuario` nullable para anonimizar al borrar la cuenta. |
| Privacidad | La ley vigente es la nueva LFPDPPP (DOF 2025-03-20). Se citan principios y obligaciones, no artículos de la ley de 2010. |

**Supuestos míos (Alex puede corregirlos al revisar):**

1. El modo Demo es el que se presenta. Remote se deja implementado contra el contrato y probado con respuestas simuladas, pero no se puede probar contra el backend real hasta que el equipo lo entregue.
2. Se corrigen los quirks inseguros: adiós a `admin`/`admin` en código, contraseñas en `SecureField` con botón mostrar/ocultar, validación en todos los formularios. "0FRAUDE" con cero **se queda**: es el nombre de la app, no un quirk.
3. El nombre visible pasa de "OFraude SwiftUI" a **"0Fraude"**. Los identificadores de Swift conservan la letra (`OFraudeApp`, `OfraudeTextField`) porque un tipo de Swift no puede empezar con un dígito.
4. Huecos extra que encontré al diseñar y que no estaban en la lista aprobada: `Reporte_Confirmacion` (para "Yo también"), `Reporte.texto_sospechoso` (cuando el campo URL trae texto y no un enlace), `Usuario.avatar_ruta`, `Usuario.preferencias`, `Usuario.intentos_fallidos` + `bloqueado_hasta`. Van al contrato marcados como "propuestos".

## 2. Definición de "prototipo completo"

Se considera terminado cuando se cumplen todos estos criterios medibles:

1. **Cada control visible hace algo.** La tabla de cobertura del plan (sección 0.2) lista cada botón, toggle y enlace de las 17 pantallas, y cada uno tiene una tarea que lo implementa o una decisión explícita de convertirlo en texto informativo.
2. **Persistencia.** Crear un reporte, guardar uno, comentar, editar el perfil y cerrar/reabrir la app: todo sigue ahí. La sesión sobrevive al reinicio (Keychain).
3. **Validación.** Ningún formulario acepta datos inválidos; cada regla tiene un mensaje en español y un test unitario.
4. **Estados.** Cada lista tiene estado cargando, vacío y error (con "Reintentar").
5. **Seguridad.** Sin credenciales en código, contraseñas con hash + sal (PBKDF2-SHA256), token en Keychain, bloqueo tras 5 intentos fallidos, autorización por rol verificada en el "servidor" (no solo escondiendo botones), evidencia sin metadatos GPS y con protección de archivo. Modelo de amenazas STRIDE documentado.
6. **Pruebas.** Target de tests unitarios y de UI; `xcodebuild test` en verde. Los flujos del checklist de 2026-09-27 quedan automatizados con XCUITest.
7. **Demo.** Guion de 5–8 minutos que se puede seguir sin improvisar, con cuentas demo documentadas.

## 3. Arquitectura

### 3.1 La idea en una imagen

Hoy cada vista tiene sus datos escritos a mano. El cambio es meter un "enchufe" entre las vistas y los datos:

```
Vistas (SwiftUI)  ──usan──▶  Stores (@Observable: SessionStore, ReportsStore, …)
                                     │ llaman a
                                     ▼
                         Protocolos de repositorio  (el enchufe)
                           ┌─────────┴──────────┐
                           ▼                    ▼
                    DemoServer (actor)     RemoteAPI (URLSession)
                    JSON en disco +        NestJS + MySQL ZeroScam
                    Keychain + archivos    (cuando el equipo lo entregue)
```

Como una lámpara y un enchufe: la lámpara (vista) funciona igual conectada a la batería (Demo) o a la corriente de la casa (Remote). Cambiar de una a otra es una línea en `AppConfig`.

Antes y después en `LoginView.submit()`:

```swift
// Antes
let isCorrect = email == demoEmail && password == demoPassword
if isCorrect { appState.isLoggedIn = true }

// Después
await session.logIn(email: email, password: password)   // SessionStore → AuthRepository
// La vista solo pinta session.loginState (.idle, .cargando, .error(mensaje), .bloqueado(hasta:))
```

### 3.2 Capas y carpetas

```
PrototipoApp/
  App/       OFraudeApp, AppState (solo navegación), AppConfig, Dependencies
  Model/     Tipos del dominio (structs `nonisolated`, Codable) mapeados a las tablas
  Data/      Repositories.swift (protocolos)
             Demo/   DemoServer (actor), DemoDatabase, DemoSeed, DemoFiles
             Remote/ APIClient, Endpoints, DTOs, RemoteRepositories
  Security/  PasswordHasher, SecretStore (Keychain), Validators, Sanitizer,
             LoginThrottle, URLTools (normalizar / "defang"), EvidenceProcessor
  Stores/    SessionStore, ReportsStore, NotificationsStore, AdminStore, LoadState
  Theme/     Theme, Components (+ campos seguros, estados vacío/cargando/error)
  Views/     las 17 pantallas actuales + Admin/, NotificationsView, PrivacyNoticeView,
             DeleteAccountView
```

- `AppState` sigue siendo solo navegación (pestaña, 4 pilas, búsqueda precargada, segmento de Perfil). Pierde `isLoggedIn`: la sesión pasa a `SessionStore`.
- `Route` gana valores asociados (`.reportDetail(Int64)`, `.article(Articulo.ID)`, …) para que el detalle sea dinámico.
- El proyecto compila en modo Swift 5 con aislamiento por defecto `MainActor`; por eso los tipos del dominio y los DTO se declaran `nonisolated` y los repositorios son `Sendable` con métodos `async throws`.

### 3.3 Por qué JSON y no SwiftData en el modo Demo

Se compararon cuatro opciones (detalle en el plan, sección 2.3): en memoria, SwiftData, archivo JSON y API. Se elige **JSON con `Codable`** dentro de un `actor`:

- Los mismos structs sirven para el Demo y para los DTO del Remote; con SwiftData habría que mantener clases `@Model` aparte y traducir.
- Un `actor` serializa los accesos: es lo más parecido a un servidor real y evita carreras.
- El volumen es pequeño (decenas de reportes); no hace falta un motor de consultas.
- Es fácil de inspeccionar y de reiniciar para la demo y los tests.

En memoria queda para los tests; Remote para el backend real.

## 4. Seguridad (resumen; detalle y STRIDE en el plan, fase 4)

- **Contraseñas:** PBKDF2-HMAC-SHA256 (CommonCrypto), 600,000 iteraciones, sal aleatoria de 16 bytes, comparación en tiempo constante. Formato guardado `pbkdf2_sha256$600000$<sal>$<hash>` (cabe en `contrasena_hash VARCHAR(255)`). Las cuentas demo vienen con el hash ya calculado; la contraseña en claro solo aparece en el guion de demo.
- **Sesión:** token aleatorio de 32 bytes; el servidor Demo guarda solo su SHA-256 (tabla `Sesion`) con caducidad de 7 días. La app guarda el token en Keychain con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. En Remote se guardan access y refresh JWT igual.
- **Intentos de login:** 5 fallos por correo → bloqueo de 1 min, que se duplica hasta 15 min. Mensaje genérico "Correo o contraseña incorrectos" para no revelar qué correos existen.
- **Autorización:** cada operación del DemoServer resuelve el usuario a partir del token y revisa su rol. Ocultar botones es comodidad, no seguridad.
- **Entradas:** recorte, quitar caracteres de control, longitudes iguales a las del SQL, correo y URL validados, solo esquemas `http`/`https`, y las URLs se comparten "desactivadas" (`hxxp://sitio-falso[.]com`).
- **Evidencia:** se vuelve a codificar a JPEG (se pierden EXIF y GPS), máximo 1600 px y 5 MB, archivos con `FileProtectionType.complete` y excluidos de respaldo.
- **Privacidad:** aviso de privacidad con consentimiento en el registro, derechos ARCO dentro de la app (ver/exportar, editar, eliminar cuenta, toggles de oposición), datos de terceros (persona afectada) visibles solo para Administrador y Owner, y la app se oculta en el selector de apps.

## 5. Fuera de alcance (y por qué)

- **Backend NestJS y base MySQL en marcha:** los construye el equipo. La app entrega el contrato y la capa Remote.
- **Notificaciones push reales (APNs):** requieren cuenta de desarrollador y servidor. Se usan notificaciones locales.
- **Verificación en dos pasos real (SMS/TOTP):** se simula en Demo con un código de un solo uso que la app "envía" a un aviso interno. Si el tiempo no alcanza, el toggle se convierte en texto "Próximamente" (plan B).
- **Interfaz para el rol Policía, idiomas distintos al español, iPad específico, deep links.**
- **Revisar la reputación real de una URL contra servicios externos:** el riesgo lo asigna un Administrador.

## 6. Riesgos principales

Detalle y plan B en el plan, sección 10. Los cuatro que más preocupan: agregar targets de tests editando `project.pbxproj` a mano, Keychain en tests sin app anfitriona, el tiempo (13 días) frente al alcance, y que el backend del equipo nombre las cosas distinto (se absorbe en `Data/Remote/`).
