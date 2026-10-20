# Verificación de la migración a SwiftUI

Hecha el 2026-09-27, sobre el simulador iPhone 17.

## Build

`xcodebuild clean build` con el scheme `PrototipoApp`, destino iPhone 17 simulator: **BUILD SUCCEEDED**, 0 errores. Aparece 1 aviso (`appintentsmetadataprocessor: Metadata extraction skipped. No AppIntents.framework dependency found.`) — es un mensaje del propio Xcode, no del código; ninguna de las dos apps usa App Intents. No es una advertencia de compilación real.

## Limitación de esta verificación

No hay forma de automatizar toques en el simulador desde esta sesión: `osascript` no tiene permiso de Accesibilidad (`osascript is not allowed assistive access`), y no están instalados `idb` ni `cliclick`. Siguiendo el plan, no se habilitó ningún permiso del sistema sin preguntar. Por eso:

- Solo se pudo capturar y comparar la pantalla de arranque (Registro), que es la única alcanzable sin tocar la pantalla.
- El resto de las 16 pantallas y los flujos entre ellas **no se recorrieron automáticamente**. Quedan como checklist abajo para que los recorras tú en el simulador o en un dispositivo.

Si en algún momento quieres que lo intente de nuevo con automatización, hay que darle permiso de Accesibilidad a la terminal/osascript en Ajustes del Sistema → Privacidad y Seguridad → Accesibilidad — te lo pido explícitamente si hace falta, no lo activo por mi cuenta.

## Comparación de pantallas

| Pantalla | Resultado |
|---|---|
| Registro | **Igual.** Capturé el original (`Tec-CCM.PrototipoApp`) y la copia (`Tec-CCM.PrototipoApp-SwiftUI`) una al lado de la otra: mismo fondo, mismos 4 campos con etiqueta naranja, mismo botón "CREAR CUENTA" naranja, mismo enlace gris. Coinciden tamaños, colores y posición. |
| Login, Inicio, Buscar, Reportar, Perfil, Ajustes, Editar perfil, Privacidad, Cambiar contraseña, Cerrar sesión, Detalle, Guía, Artículo, Estadísticas, Éxito | **No comprobadas visualmente** (requieren tocar la pantalla para llegar). El código de cada una sigue los mismos textos, colores y medidas que extraje del storyboard (ver el plan), pero no hay una captura que lo confirme. |

Nota sobre la primera captura del original: apareció un aviso de iOS "◀ OFraude SwiftUI" arriba de la pantalla (el "volver a la app anterior" que agrega el sistema al cambiar de app). No es parte de ninguna de las dos apps; se repitió la captura yendo primero al Home del simulador y desapareció.

## Checklist de flujos (para recorrer tú)

- [ ] Registro → "CREAR CUENTA" abre Login; en Login, "¿No tienes cuenta?" regresa a Registro.
- [ ] Login vacío, `Admin`/`admin`, `admin ` (con espacio): muestra "Credenciales inválidas" y no navega. `admin`/`admin` entra a las pestañas.
- [ ] Inicio → cada categoría (Ofertas Falsas, Sorteos Falsos, Tiendas Clonadas) abre Buscar con el texto correcto en el campo; con Buscar ya visitada, tocar otra categoría sustituye el texto; el texto no reaparece al cambiar de pestaña y volver.
- [ ] Inicio → botón naranja "REPORTAR INCIDENTE" abre la pestaña Reportar.
- [ ] Inicio → alerta / Buscar → categoría / Perfil → tarjeta abren el detalle, **sin tab bar visible**, y "atrás" regresa.
- [ ] Perfil: segmentos Mis reportes/Guardados, menú de una tarjeta de Mis reportes (Editar no hace nada, Eliminar la quita, Cancelar cierra), quitar de Guardados.
- [ ] Perfil → engrane → Ajustes → "Reportes Guardados" abre Perfil en Guardados con la pila vacía.
- [ ] Detalle → "Yo también" abre Reportar; ahí, elegir opciones (borde naranja) y "ENVIAR REPORTE" abre Éxito; "CONTINUAR" vuelve a Inicio con todas las pilas vacías (probar también llegando desde Perfil y desde Buscar).
- [ ] Ajustes → Cerrar sesión → "CANCELAR" regresa; "CERRAR SESIÓN" vuelve a Registro; volver a entrar muestra Inicio limpio (sin búsqueda ni segmento anterior).
- [ ] Teclado: en Registro y Reportar se puede llegar a cada campo y botón con el teclado abierto; tocar fuera cierra el teclado.
- [ ] Texto grande y pantalla horizontal: revisar si algo queda cortado (el original usa alturas fijas, así que puede fallar igual en ambas).

## Revisión final de código (2026-09-27)

Un agente fresco revisó todo `Views/`, `App/`, `Theme/` y `Model/` contra el spec, el plan y el storyboard original. No encontró bugs de lógica ni de navegación. Encontró 5 diferencias de fidelidad visual, que verifiqué una por una contra `Main.storyboard` antes de corregirlas (todas confirmadas):

1. **Login:** el título, subtítulo, descripción y el mensaje de error no estaban centrados (sí lo están en el storyboard). Corregido.
2. **Cierre de teclado:** el gesto de "tocar fuera para cerrar teclado" competía con el toque para enfocar el siguiente campo (podía cerrar el teclado justo al cambiar de campo). Corregido cambiando a un gesto no simultáneo, que es el patrón estándar de SwiftUI para este caso. **No pude probarlo en vivo** (sin automatización de toques disponible) — queda en el punto 10 del checklist de abajo.
3. **Guía de seguridad:** el texto de introducción no estaba centrado. Corregido.
4. **Buscar:** los chips (#Descuentos, etc.) no llenaban el ancho de su fila como en el original (`fillProportionally`). Corregido con una aproximación (un espacio entre los dos chips de cada fila) — SwiftUI no tiene un equivalente exacto a `fillProportionally`, así que no es pixel-perfect, pero ya no quedan pegados a la izquierda.
5. **Perfil:** la insignia del lápiz sobre el avatar no tenía el margen de 2 pt hacia adentro que tiene en el original. Corregido.

Ninguna de las 5 correcciones tiene un test automatizado (el proyecto no tiene target de pruebas ni hay automatización de UI disponible en esta sesión). Se verificaron con `xcodebuild BUILD SUCCEEDED` y, para Login/Guía/Buscar/Perfil, comparando los valores exactos del storyboard — no con una captura, porque esas pantallas no son alcanzables sin tocar la pantalla. Sí se volvió a capturar Registro después de los cambios para confirmar que no hubo regresión ahí (no la hay).

## Diferencias conocidas respecto al original (a propósito, ver el plan)

- Bundle id y nombre distintos (`Tec-CCM.PrototipoApp-SwiftUI`, "OFraude SwiftUI") para poder instalar ambas apps a la vez.
- Las pantallas empujadas ocultan el tab bar por completo (en el original lo cubrían al estar empujadas sobre el mismo nav controller).
- La pestaña Reportar ya no muestra la flecha "atrás" hacia Login que tenía el original (era un efecto secundario de cómo estaba armado el storyboard, no una función).
