# Modo sin conexión de la app ZeroScam (iOS)

Fecha: 19 de octubre de 2026.

Cambios:
- App: rama `feat/modo-sin-conexion` de `alexrodrd/0Fraude-SwiftUI`.
- API: rama `feat/idempotency-key-reportes` de `Soldsanty1000/zeroScamBorrador` (PR #3).

## Qué hace

1. **Entrar sin red.** Si al abrir la app el servidor no responde, pero en el teléfono hay token y perfil guardados de una sesión anterior, la app entra con ese perfil y muestra el aviso "Sin conexión".
2. **Primer inicio de sesión.** Siempre necesita al servidor. La contraseña nunca se revisa en el teléfono.
3. **Reportes sin red.** Un reporte que no se pudo enviar por falta de conexión se guarda en una cola del teléfono, y el formulario se vacía con el aviso "Sin conexión: guardamos tu reporte…".
4. **Envío automático.** Al abrir la app, al volver a primer plano y cuando regresa la red, la app:
   - le pregunta al servidor si la sesión sigue viva;
   - si sigue viva, envía la cola en orden.
5. **Inicio y Reportar** muestran:
   - cuántos reportes esperan conexión, con el botón "Enviar";
   - cuántos se enviaron solos;
   - los que el servidor rechazó, con "Reintentar" y "Descartar".

## Controles de seguridad

| Riesgo | Control |
|---|---|
| Un reintento crea el reporte dos veces: la red se cortó después de que el servidor lo guardó | Cada intento lleva la cabecera `Idempotency-Key`. La clave es la misma desde el primer intento y en todos los de la cola. La API regresa el reporte que ya existe (tabla `Reporte_Idempotencia`, 24 h, por usuario). Si la evidencia se subió a medias, solo se suben los archivos que faltan. |
| Alguien lee la cola o el perfil guardado | El perfil va en el Keychain (`WhenUnlockedThisDeviceOnly`), igual que los tokens. La cola es un archivo con `.completeFileProtection` (solo se lee con el teléfono desbloqueado) y fuera del respaldo de iCloud. La evidencia ya va sin metadatos (EXIF/GPS) y se aparta en `evidencia/cola/` con la misma protección. |
| Un reporte se envía con la cuenta de otra persona | Cada reporte de la cola guarda el `id` de su dueño. Solo se muestra y se envía con la sesión de esa persona. |
| Quedan datos de alguien en el teléfono después de salir | Al cerrar sesión o eliminar la cuenta se borran su cola, su evidencia apartada y su perfil guardado. "Cerrar sesión" avisa antes si hay reportes sin enviar. |
| El teléfono se llena de reportes | La cola admite como máximo 10 reportes por persona, que es también el límite diario de la API. |
| Un reporte que el servidor rechaza se reintenta para siempre | Un rechazo (400, 403, 404, 409) se marca y no se reintenta solo. La persona decide si lo reintenta o lo descarta. Los fallos pasajeros (sin red, 401, 429, 5xx) detienen la vuelta y se reintentan después. |
| Un archivo de cola corrupto tumba la app | Se ignora y cuenta como cola vacía. |

## Riesgos residuales (aceptados y documentados)

- **Sesión revocada mientras no hay red.** Si la sesión se cerró en el servidor, o la cuenta se suspendió, el teléfono sigue entrando sin conexión hasta que regresa la red. En ese momento `revalidar()` la cierra. Sin red solo se pueden ver pantallas vacías o con error y guardar reportes en la cola; nada llega al servidor sin un token válido.
- **Envío en segundo plano.** iOS no garantiza que la app corra en segundo plano, así que el envío ocurre al abrirla, al volver a ella o cuando regresa la red con la app abierta.
- **Teléfono sin código de bloqueo.** La protección de archivos y del Keychain depende de que el teléfono tenga código. Sin código, quien tenga el teléfono puede abrir la app sin conexión, como ya podía hacerlo con conexión.

## Cómo se probó

- Pruebas unitarias de la app: 507 pasan, 21 de ellas nuevas.
  - `ColaReportesTests`: disco, dueño, misma clave, corte después de crear sin duplicar, rechazo, descartar, evidencia que sobrevive al arranque, máximo y archivo corrupto.
  - `SessionStoreSinConexionTests`: entrar sin red, primer inicio sin red, revalidar, sesión vencida mientras tanto y cerrar sesión sin red.
- API: `jest` (96 pruebas, 30 nuevas) y una prueba en vivo contra MySQL desechable. La misma clave regresa el mismo reporte, también con 3 peticiones simultáneas.

## Análisis de vulnerabilidades

- **API:** el cambio está en `POST /community/reports` y en una tabla nueva. Hay que volver a pasar ZAP y CodeQL sobre la API.
- **Panel web:** no cambia.
- **App:** hay que revisar en la lista de iOS (7.1.3/7.2.3) lo de almacenamiento local y sesión, y agregar a 7.1.4/7.2.4 el riesgo de sesión revocada sin red.
