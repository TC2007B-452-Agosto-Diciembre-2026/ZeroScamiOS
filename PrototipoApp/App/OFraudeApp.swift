//
//  OFraudeApp.swift
//  PrototipoApp
//
//  Reemplaza: AppDelegate.swift + SceneDelegate.swift + el storyboard principal (Main.storyboard).
//  Crea los stores una sola vez y los comparte con todas las pantallas por el entorno.
//

import SwiftUI
import UserNotifications

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
    @State private var cola: ColaReportes
    @State private var red = MonitorRed()
    private let config: AppConfig

    init() {
        let dependencias = Self.dependenciasDeArranque()
        let session = SessionStore(backend: dependencias.backend, secretos: dependencias.secretos)
        let alExpirar: (AppError) -> Void = { session.expirar($0) }
        config = dependencias.config
        let reports = ReportsStore(backend: dependencias.backend, archivos: dependencias.archivos, alExpirar: alExpirar)
        _session = State(initialValue: session)
        _reports = State(initialValue: reports)
        _cola = State(initialValue: ColaReportes(almacen: dependencias.cola, archivos: dependencias.archivos, reports: reports))
        _notifications = State(initialValue: NotificationsStore(backend: dependencias.backend, notificador: UNNotificador(), alExpirar: alExpirar))
        _admin = State(initialValue: AdminStore(backend: dependencias.backend, alExpirar: alExpirar))
        UNUserNotificationCenter.current().delegate = DelegadoNotificaciones.compartido
    }

    /// Las pruebas unitarias se ejecutan dentro de la app: ahí no se toca el Keychain ni la carpeta
    /// real de datos (`Dependencies.crear` correría PrimeraEjecucion y podría restaurar una sesión).
    private static func dependenciasDeArranque() -> Dependencies {
        let config = AppConfig.actual()
        if !config.esUITest, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return Dependencies.efimeras()
        }
        return Dependencies.crear(config)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(session)
                .environment(reports)
                .environment(notifications)
                .environment(admin)
                .environment(cola)
                .environment(red)
                .environment(\.appConfig, config)
                .task { red.iniciar() }
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
    @Environment(ColaReportes.self) private var cola
    @Environment(MonitorRed.self) private var red
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.estado {
            case .restaurando: LaunchGateView()
            case .sinSesion: AuthFlow()
            case .activa:
                if session.debeAceptarAviso { ReaceptarAvisoView() } else { MainTabView() }
            }
        }
        // La app es oscura por diseño; sin esto, en modo claro la barra de estado no se lee (U3 lo hace configurable).
        .preferredColorScheme(.dark)
        // El texto crece con Dynamic Type hasta accessibility2; más allá las tarjetas ya no se leen
        // mejor e iOS sigue ofreciendo Zoom.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        // Tapa el contenido cuando la app sale de primer plano: iOS guarda esa imagen en el selector de apps.
        .overlay { if scenePhase != .active { PrivacyShield() } }
        .task { await session.restaurar() }
        // Al entrar, al volver a primer plano y cuando regresa la red: confirmar la sesión abierta sin
        // conexión y enviar los reportes que esperaban. (`sinConexion` no va en la clave a propósito:
        // al cambiar cancelaría esta misma tarea a media cola.)
        .task(id: "\(session.usuario?.id ?? -1)|\(red.conectada)|\(scenePhase == .active)") { await sincronizar() }
        .onChange(of: session.usuario?.id, initial: true) { _, nuevo in cola.usar(usuario: nuevo) }
        .onChange(of: session.usuario?.id) { anterior, nuevo in
            // Se limpia al perder la sesión y también si de una persona se pasa directo a otra.
            guard nuevo == nil || anterior != nil else { return }
            appState.resetNavigation()
            reports.reiniciar()
            notifications.reiniciar()
            admin.reiniciar()
        }
    }

    private func sincronizar() async {
        guard session.usuario != nil, red.conectada, scenePhase == .active else { return }
        await session.revalidar()
        guard session.usuario != nil, !session.sinConexion else { return }
        await cola.enviarPendientes()
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
                    case .aviso: PrivacyNoticeView()
                    }
                }
        }
        // Si se llega aquí por sesión expirada o cuenta eliminada, se muestra Login con el aviso.
        .onAppear { if session.aviso != nil { path = [.login] } }
    }
}

extension View {
    /// Inyecta stores con el servidor Demo en una carpeta temporal y secretos en memoria, para los
    /// Previews. No toca el Keychain ni la carpeta de la app. (Sin `#if DEBUG`: los `#Preview` también
    /// se compilan en Release y necesitan encontrarlo; fuera de ellos no se usa.)
    func entornoDePrueba() -> some View {
        let dependencias = Dependencies.efimeras()
        let session = SessionStore(backend: dependencias.backend, secretos: dependencias.secretos)
        let reports = ReportsStore(backend: dependencias.backend, archivos: dependencias.archivos) { _ in }
        return self
            .environment(AppState())
            .environment(session)
            .environment(reports)
            .environment(ColaReportes(almacen: dependencias.cola, archivos: dependencias.archivos, reports: reports))
            .environment(MonitorRed())
            .environment(NotificationsStore(backend: dependencias.backend, notificador: UNNotificador()) { _ in })
            .environment(AdminStore(backend: dependencias.backend) { _ in })
    }
}
