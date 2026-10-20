# Aviso de privacidad y LFPDPPP (versión 2026-10c)

Revisión del aviso de privacidad de ZeroScam contra la Ley Federal de Protección de Datos
Personales en Posesión de los Particulares (nueva ley, DOF 20-03-2025, última reforma DOF
14-11-2025). Es un apoyo técnico, **no asesoría legal**: antes de publicar la app, un abogado con
cédula en México debe validarlo.

## Qué faltaba en la versión 2026-10b

| # | Artículo | Hallazgo | Corrección |
|---|----------|----------|------------|
| 1 | 15-I, 29 | Sin domicilio ni contacto del responsable ("se publicará después"); sin persona o departamento de datos personales. | Responsable 0Fraude, domicilio del Tec CCM (Calle del Puente 222, Tlalpan, CDMX) y correo `ZeroScam@0fraude.com` como departamento de datos personales. Viven en `ResponsableDatos`. |
| 2 | 15-II | No declaraba datos que sí se tratan: foto de perfil, biografía, comentarios, confirmaciones, guardados, historial de enlaces analizados (`Consulta_URL`), códigos de dos pasos, versión/fecha de aceptación. | Lista completa y declaración expresa de que no hay datos sensibles ni financieros (arts. 7 y 8). |
| 3 | 15-III | Faltaba la alerta cuando sube el riesgo de un enlace consultado (RF08) y la verificación en dos pasos. No separaba claramente las finalidades que requieren consentimiento. | Finalidades necesarias vs. las que requieren consentimiento (perfil público, analíticas, notificaciones). |
| 4 | 15-IV | No había sección de opciones para limitar uso o divulgación. | Sección nueva: anónimo, perfil privado, quitar foto, switches. |
| 5 | 35, 36 | Decía "no usa proveedores externos", pero el correo de códigos y el análisis de enlaces (Google Safe Browsing, RDAP) sí salen del servidor. Faltaba la cláusula de aceptar o rechazar transferencias. | Encargados declarados (solo se envía el enlace o dominio, nunca datos del titular); transferencia a la autoridad al CANALIZAR con su fundamento (art. 36 I y V); cláusula del art. 35. |
| 6 | 15-V, 28, 31, 34 | ARCO sin medio fuera de la app, sin requisitos de la solicitud ni plazos; autoridad genérica. | Correo, requisitos del art. 28, plazos de 20 + 15 días (ampliables una vez), gratuidad y la Secretaría Anticorrupción y Buen Gobierno (art. 3-XV). |
| 7 | 15-VI, 11 | Prometía "te pediremos aceptarlo de nuevo", pero la app no lo hacía. | `ReaceptarAvisoView`: si la versión aceptada no es la vigente, la app la muestra antes de entrar; registra versión y fecha con `PATCH /account/privacy`. Sin conexión no se pide (no se podría registrar). |
| 8 | 16-II | Registro solo tenía la casilla y un enlace; la ley pide el aviso simplificado (fracciones I a IV + dónde ver el integral) en medios electrónicos. | `AvisoSimplificadoView` en Registro y en la re-aceptación. |
| 9 | — | Sin mención de menores de edad. | Sección "Menores de edad" (dirigida a mayores de 18). |

La casilla de aceptación sigue sin venir marcada y el botón de crear cuenta exige marcarla
(consentimiento expreso).

## Dónde se cumple cada fracción del art. 15

- I. Identidad y domicilio: sección "Quién es responsable de tus datos".
- II. Datos y sensibles: "Qué datos tratamos".
- III. Finalidades: "Para qué los usamos".
- IV. Limitar uso o divulgación: "Cómo limitar el uso o la divulgación".
- V. ARCO: "Tus derechos ARCO" y "Revocar tu consentimiento" (art. 7, último párrafo).
- VI. Cambios: "Cambios a este aviso" + pantalla de re-aceptación.

## Pendiente fuera del código

- Que el correo `ZeroScam@0fraude.com` exista y alguien lo atienda (art. 29).
- Contratos o cláusulas con el proveedor de correo cuando se use uno real (encargado).
- Validación del texto por un abogado.

## Cómo se verificó

- 511 pruebas unitarias de la app (4 nuevas en `AvisoPrivacidadTests`).
- Prueba de interfaz de punta a punta contra el API con `PATCH /account/privacy`: una cuenta con
  la versión 2026-10b ve la pantalla, no puede aceptar sin marcar la casilla, lee el integral,
  acepta y entra; en la base queda `version_aviso = 2026-10c`.
