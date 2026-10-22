# ZeroScam · App iOS

App en SwiftUI de **ZeroScam** para reportar y consultar fraudes digitales (curso TC2007B). La
persona puede reportar un sitio o enlace sospechoso con evidencias, buscar reportes de la
comunidad, verificar si un enlace parece legítimo y leer la guía de seguridad. Administradores y
Owner moderan los reportes desde la misma app.

## Funciones

- **Cuenta:** registro, inicio de sesión con verificación en dos pasos por correo, recuperación
  de contraseña, edición de perfil, privacidad, aviso de privacidad y baja de cuenta.
- **Reportes:** crear un reporte con fotos de la galería o la cámara, ver su detalle, comentarios,
  confirmaciones y el perfil público de quien reporta.
- **Buscar y verificar:** búsqueda con filtros por tipo de fraude y riesgo, y diagnóstico
  preliminar de un enlace (RF07).
- **Aprende:** guía de seguridad, artículos y estadísticas de la comunidad.
- **Moderación:** cola de revisión para Administrador y Owner, y gestión de usuarios para Owner.
- **Sin conexión:** entra con la última sesión guardada y guarda en una cola los reportes que no
  se pudieron enviar, para mandarlos cuando vuelve la red
  ([docs/modo-sin-conexion.md](docs/modo-sin-conexion.md)).

## Requisitos

- macOS con **Xcode 26.5** o más reciente.
- Simulador o dispositivo con **iOS 17 o superior** (iPhone o iPad). Las pruebas se corren en el simulador de iOS 26.5.

## Cómo correrla

1. Clona el repositorio y abre `PrototipoApp.xcodeproj` en Xcode.
2. Elige el scheme **PrototipoApp** y un simulador (por ejemplo, iPhone 17).
3. Presiona **Run** (⌘R).

Desde la terminal:

```bash
xcodebuild -project PrototipoApp.xcodeproj -scheme PrototipoApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

> Si `xcodebuild` dice que requiere Xcode y que el directorio activo es de Command Line Tools,
> apunta la terminal a Xcode con
> `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## Fuente de datos: demo o API

La app elige de dónde salen los datos con dos ajustes de compilación del target `PrototipoApp`
(*Build Settings → User-Defined*), que llegan a `Info.plist` y lee `PrototipoApp/App/AppConfig.swift`:

| Ajuste | Valor | Qué hace |
|---|---|---|
| `ZS_FUENTE_DATOS` | `demo` (por defecto) | Usa la base local de demostración (`PrototipoApp/Data/Demo/`). No necesita servidor. |
| `ZS_FUENTE_DATOS` | `remote` | Usa la API NestJS del equipo en la URL de `ZS_URL_BASE`. |
| `ZS_URL_BASE` | p. ej. `http://192.168.1.50:3000` | URL base de la API, sin barra final. |

Para usar la API, levanta el backend
([ZeroScamBackend](https://github.com/TC2007B-452-Agosto-Diciembre-2026/ZeroScamBackend)); por
defecto escucha en el puerto `3000` y publica su documentación Swagger en `/docs`.

Por seguridad, la app solo acepta **HTTPS**, o **HTTP** únicamente contra `localhost` o una IP
privada de la red local (`10.x`, `172.16–31.x`, `192.168.x`). Cualquier otra URL hace que la app se
quede en modo demo.

Las contraseñas de las cuentas de demostración no están en el repositorio (en
`DemoSeed.swift` solo están sus hashes); pídelas al equipo.

## Pruebas

| Target | Qué prueba |
|---|---|
| `PrototipoAppTests` | Pruebas unitarias (Swift Testing): modelo, seguridad, cliente de la API, modo demo y stores. |
| `PrototipoAppUITests` | Pruebas de interfaz (XCTest): arranque, autenticación, búsqueda y verificación de enlaces. |

Todas las pruebas:

```bash
xcodebuild -project PrototipoApp.xcodeproj -scheme PrototipoApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Solo las unitarias (agrega `-only-testing:PrototipoAppTests`):

```bash
xcodebuild -project PrototipoApp.xcodeproj -scheme PrototipoApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PrototipoAppTests test
```

Las pruebas de interfaz abren la app con el argumento `-uiTesting`, que siempre usa el modo demo.
En compilaciones Debug, `-reiniciarDemo` borra los datos de la demo al arrancar. Si una prueba de
interfaz falla porque un campo "no tiene el foco del teclado", suele ser el simulador: vuelve a
correrla.

## Estructura

```
PrototipoApp/
  App/            Arranque, configuración, dependencias, monitor de red y notificaciones locales
  Model/          Modelos: reporte, usuario, catálogos, filtros, diagnóstico de enlaces, errores
  Data/
    Remote/       Cliente HTTP contra la API NestJS
    Demo/         Servidor y base de datos de demostración
  Stores/         Estado de la app: sesión, reportes, cola sin conexión, notificaciones, admin
  Security/       Hash de contraseñas, Keychain, validación, sanitizado y evidencias
  Theme/          Colores, tipografía y componentes visuales
  Views/
    Auth/         Registro, inicio de sesión, código de dos pasos, recuperar contraseña
    Tabs/         Pestañas: Inicio, Buscar, Reportar y Perfil
    Reports/      Detalle, comentarios, evidencias, verificación de enlaces
    Account/      Ajustes, perfil, privacidad, contraseña, cierre de sesión y baja
    Learn/        Guía de seguridad, artículos y estadísticas
    Admin/        Moderación y gestión de usuarios
    Shared/       Componentes compartidos entre pantallas
PrototipoAppTests/   Pruebas unitarias
PrototipoAppUITests/ Pruebas de interfaz
database/            Esquema SQL de la base ZeroScam
docs/                Documentación del proyecto
```

## Documentación

- [Qué cambió respecto al prototipo original en UIKit](docs/CAMBIOS-vs-original.md)
- [Modo sin conexión](docs/modo-sin-conexion.md)
- [Aviso de privacidad y LFPDPPP](docs/aviso-privacidad-lfpdppp.md)
- [Verificación de la migración a SwiftUI](docs/verificacion-2026-09-26.md)
- [Esquema de la base de datos](database/zeroscam_base_datos.sql)

## Repositorios del proyecto

- [ZeroScamBackend](https://github.com/TC2007B-452-Agosto-Diciembre-2026/ZeroScamBackend): API en NestJS.
- [ZeroScamFrontend](https://github.com/TC2007B-452-Agosto-Diciembre-2026/ZeroScamFrontend): panel de administración en Next.js.
- **ZeroScamiOS** (este repositorio): app para iPhone y iPad.

## Equipo

| Integrante | Área |
|---|---|
| [@SEBASidkk](https://github.com/SEBASidkk) | Cuentas y seguridad |
| [@Jose-Emilio1210](https://github.com/Jose-Emilio1210) | Reportes y comunidad |
| [@Soldsanty1000](https://github.com/Soldsanty1000) | Motor de riesgo y diagnóstico |
| [@alexrodrd](https://github.com/alexrodrd) | Infraestructura y base de la app |
