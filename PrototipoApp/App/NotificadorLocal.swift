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

/// Muestra el aviso aunque la app esté en primer plano (por defecto iOS lo oculta).
final class DelegadoNotificaciones: NSObject, UNUserNotificationCenterDelegate {
    static let compartido = DelegadoNotificaciones()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
