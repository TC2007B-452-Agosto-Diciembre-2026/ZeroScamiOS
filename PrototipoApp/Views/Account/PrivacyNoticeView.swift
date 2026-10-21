//
//  PrivacyNoticeView.swift
//  PrototipoApp
//
//  Aviso de privacidad integral (LFPDPPP, DOF 20-03-2025; arts. 14, 15, 31, 35 y 36). Se abre
//  desde Registro (antes de aceptar), desde Seguridad y privacidad y desde la pantalla que pide
//  aceptar una versión nueva. Si cambia el texto, se sube `Consentimiento.versionAvisoVigente` y la
//  app pide aceptarlo de nuevo antes de seguir (`ReaceptarAvisoView`).
//
//  Es un apoyo técnico del prototipo, no asesoría legal: antes de publicar la app lo debe validar
//  un abogado con cédula en México.
//

import SwiftUI

/// Identidad, domicilio y contacto del responsable (art. 15-I y art. 29). Se usan en el aviso
/// integral y en el simplificado.
enum ResponsableDatos {
    static let nombre = "0Fraude"
    static let domicilio = "Calle del Puente 222, Col. Ejidos de Huipulco, Alcaldía Tlalpan, C.P. 14380, Ciudad de México (Tecnológico de Monterrey, Campus Ciudad de México)"
    static let correo = "ZeroScam@0fraude.com"
}

struct PrivacyNoticeView: View {
    private struct Seccion: Identifiable {
        let titulo: String
        let texto: String
        var id: String { titulo }
    }

    private let secciones = [
        Seccion(titulo: "Quién es responsable de tus datos",
                texto: "\(ResponsableDatos.nombre), la empresa dueña de ZeroScam, es responsable del tratamiento de tus datos personales. ZeroScam es un prototipo académico del Equipo 2 (TC2007B, Tecnológico de Monterrey). Domicilio: \(ResponsableDatos.domicilio). Correo del departamento de datos personales: \(ResponsableDatos.correo)."),
        Seccion(titulo: "Qué datos tratamos",
                texto: "Identificación y contacto: nombre, apellido, país, nombre de usuario y correo; foto de perfil y biografía solo si las agregas. Autenticación: tu contraseña, que guardamos solo como un hash con sal (nadie puede leerla), los códigos de verificación que te enviamos por correo para entrar en dos pasos o para cambiar o recuperar tu contraseña (caducan en minutos), y el aviso por correo cuando tu contraseña cambia. Reportes y comunidad: descripción, ciudad, enlaces, evidencia (a las fotos les quitamos la ubicación), comentarios, confirmaciones y reportes guardados. Enlaces que analizas en Buscar, ligados a tu cuenta, para avisarte si su riesgo sube. Datos de una persona afectada, solo si nos dices que te autorizó a compartirlos. Tus preferencias y la versión y fecha en que aceptaste este aviso. Uso anónimo de la app (contadores sin identificarte), solo si lo permites.\n\nNo tratamos datos personales sensibles (salud, origen étnico, creencias, opiniones políticas, preferencia sexual, datos biométricos o genéticos) ni datos financieros o patrimoniales. Te pedimos no escribirlos en tus reportes; moderación rechaza los reportes que los expongan."),
        Seccion(titulo: "Para qué los usamos",
                texto: "Finalidades necesarias para darte el servicio: crear tu cuenta y protegerla (incluida la verificación en dos pasos), recibir y moderar reportes, publicar alertas validadas sin tus datos personales, avisarte cuando cambie el estado de tus reportes o suba el riesgo de un enlace que consultaste o reportaste, atender tus derechos ARCO y detectar abusos.\n\nFinalidades que requieren tu consentimiento y puedes negar sin perder el servicio: mostrar tu nombre de usuario y tu foto en público, las analíticas anónimas de uso y las notificaciones. Vienen apagadas o se apagan en Seguridad y privacidad."),
        Seccion(titulo: "Cómo limitar el uso o la divulgación",
                texto: "Puedes publicar reportes como anónimo, mantener tu perfil privado, quitar tu foto, apagar analíticas y notificaciones en Seguridad y privacidad, y no incluir datos personales en tus reportes. Ninguna de estas opciones te quita el servicio."),
        Seccion(titulo: "Con quién los compartimos",
                texto: "No vendemos ni rentamos tus datos. Cuando un reporte se CANALIZA, su contenido se envía a la autoridad competente para la procuración de justicia; tus datos de cuenta solo se entregan por mandato fundado de autoridad (art. 36, fracciones I y V). Fuera de esos casos no transferimos tus datos; si algún día quisiéramos hacerlo, te lo diremos aquí y podrás aceptarlo o rechazarlo antes (art. 35).\n\nUsamos servicios que trabajan por nuestra cuenta: el servicio de correo que entrega tus códigos y avisos. Al analizar un enlace consultamos Google Safe Browsing y los registros públicos de dominios (RDAP): solo se envía el enlace o su dominio, nunca tus datos."),
        Seccion(titulo: "Tus derechos ARCO",
                texto: "Puedes acceder, rectificar, cancelar u oponerte al uso de tus datos. Desde la app: Acceso en Seguridad y privacidad › Descargar mis datos; Rectificación en Editar perfil; Cancelación en Seguridad y privacidad › Eliminar mi cuenta; Oposición con los switches de Perfil público, Analíticas y Notificaciones.\n\nTambién puedes escribir a \(ResponsableDatos.correo) con tu nombre, un medio para responderte, una identificación (tuya o de tu representante), los datos de que se trata y el derecho que quieres ejercer. Es gratuito. Te respondemos en máximo 20 días y, si procede, lo hacemos efectivo en los 15 días siguientes; estos plazos solo se amplían una vez, por un periodo igual, si el caso lo justifica (art. 31). Si consideras que se vulneró tu derecho, puedes acudir a la Secretaría Anticorrupción y Buen Gobierno."),
        Seccion(titulo: "Revocar tu consentimiento",
                texto: "Puedes retirar tu consentimiento cuando quieras, sin efectos hacia atrás. Eliminar tu cuenta lo revoca por completo; apagar un switch en Seguridad y privacidad lo revoca solo para esa finalidad. También puedes pedirlo por correo como una solicitud ARCO. Retirarlo puede impedir que sigamos dándote algunas funciones."),
        Seccion(titulo: "Cómo los protegemos",
                texto: "Contraseñas con hash y sal, sesión guardada en el llavero cifrado del teléfono, archivos cifrados por iOS, evidencia sin metadatos de ubicación, límite de intentos de inicio de sesión y permisos revisados en el servidor. Si ocurriera una vulneración que afecte tus derechos, te avisaríamos sin demora."),
        Seccion(titulo: "Cuánto tiempo los guardamos",
                texto: "Mientras tu cuenta exista. Si la eliminas, borramos tus datos, tu historial de enlaces analizados y tus reportes no validados; los reportes ya validados se quedan para alertar a la comunidad, pero sin ningún dato tuyo."),
        Seccion(titulo: "Menores de edad",
                texto: "ZeroScam está dirigida a personas mayores de 18 años. Si eres menor de edad, usa la app solo con la autorización de tu madre, padre o tutor."),
        Seccion(titulo: "Cambios a este aviso",
                texto: "Si este aviso cambia, al abrir la app te mostraremos qué cambió y te pediremos aceptarlo antes de seguir; guardamos la versión y la fecha en que lo aceptas. La versión vigente siempre está aquí y en Seguridad y privacidad. Marco legal: Ley Federal de Protección de Datos Personales en Posesión de los Particulares, publicada en el Diario Oficial de la Federación el 20 de marzo de 2025."),
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ofraudeScreen()
        .navigationTitle("Aviso de privacidad")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Aviso simplificado (art. 16-II): lo mínimo de las fracciones I a IV del art. 15 y dónde leer el
/// integral. Va en la pantalla que pide aceptar una versión nueva; en Registro solo se ve al abrir
/// "Leer el aviso de privacidad".
struct AvisoSimplificadoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AVISO DE PRIVACIDAD SIMPLIFICADO").ofraude(12, .bold, color: Theme.accent)
            Text("\(ResponsableDatos.nombre) (\(ResponsableDatos.correo)) es responsable de tus datos. Usamos tu nombre, correo, país, nombre de usuario, tus reportes y los enlaces que analizas para crear y proteger tu cuenta, moderar reportes y alertar a la comunidad sin mostrar tus datos. No pedimos datos sensibles ni financieros. Perfil público, analíticas y notificaciones son opcionales: los cambias en Seguridad y privacidad. El aviso integral, con el domicilio del responsable y cómo ejercer tus derechos ARCO, está en el enlace de abajo y en Ajustes › Seguridad y privacidad.")
                .ofraude(12, color: Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ofraudeCard(radius: 8, fill: Theme.field)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("aviso.simplificado")
    }
}

#Preview {
    NavigationStack { PrivacyNoticeView() }
}
