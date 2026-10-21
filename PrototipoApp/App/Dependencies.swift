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
    /// Reportes hechos sin conexión que esperan a la red.
    let cola: AlmacenCola
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
        // Evidencia elegida y nunca enviada no se queda en disco (la de la cola vive en "cola/").
        try? archivos.limpiarTemporales()
        let cola = AlmacenCola(archivo: carpeta.appending(path: "cola-reportes.json"))
        if case .remote(let base) = config.fuente {
            // API NestJS del equipo: los datos viven en el servidor; aquí solo la evidencia por enviar.
            return Dependencies(backend: RemoteBackend(base: base, secretos: secretos, archivos: archivos),
                                secretos: secretos, archivos: archivos, cola: cola, config: config)
        }
        let hasher = PasswordHasher(iteraciones: config.esUITest ? 1_000 : PasswordHasher.iteracionesRecomendadas)
        let servidor = DemoServer(almacen: DemoAlmacen(carpeta: carpeta), archivos: archivos, hasher: hasher)
        return Dependencies(backend: DemoBackend(servidor: servidor, secretos: secretos),
                            secretos: secretos, archivos: archivos, cola: cola, config: config)
    }

    /// Dependencias aisladas para Previews y pruebas de stores: carpeta temporal nueva, secretos en
    /// memoria y hash rápido. No toca el Keychain ni la carpeta de la app (ni la de pruebas de interfaz).
    static func efimeras() -> Dependencies {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "zs-efimero-\(UUID().uuidString)", directoryHint: .isDirectory)
        let secretos = MemorySecretStore()
        let archivos = ArchivosEvidencia(carpeta: carpeta.appending(path: "evidencia"))
        let servidor = DemoServer(almacen: DemoAlmacen(carpeta: carpeta), archivos: archivos,
                                  hasher: PasswordHasher(iteraciones: 1_000))
        return Dependencies(backend: DemoBackend(servidor: servidor, secretos: secretos),
                            secretos: secretos, archivos: archivos,
                            cola: AlmacenCola(archivo: carpeta.appending(path: "cola-reportes.json")), config: .porDefecto)
    }
}
