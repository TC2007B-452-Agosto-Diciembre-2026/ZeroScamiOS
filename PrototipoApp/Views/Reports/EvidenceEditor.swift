//
//  EvidenceEditor.swift
//  PrototipoApp
//
//  Evidencia del reporte (antes un botón vacío, TODO del original): fotos de la galería, cámara
//  (solo en dispositivo real) o un PDF. Toda imagen se vuelve a codificar sin metadatos (se borra
//  la ubicación GPS) y se guarda cifrada por iOS antes de enviarse.
//

import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct EvidenceEditor: View {
    @Binding var adjuntos: [Adjunto]
    let existentes: [Evidencia]
    @Binding var quitar: Set<Int64>

    @Environment(ReportsStore.self) private var reports
    @Environment(\.appConfig) private var config
    @State private var seleccion: [PhotosPickerItem] = []
    @State private var mostrarFotos = false
    @State private var mostrarCamara = false
    @State private var mostrarArchivos = false
    @State private var procesando = false
    @State private var error: String?

    private var visibles: [Evidencia] { existentes.filter { !quitar.contains($0.id) } }
    private var restantes: Int { max(0, 3 - visibles.count - adjuntos.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !visibles.isEmpty || !adjuntos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(visibles) { e in
                        MiniaturaEvidencia(fuente: .guardada(e)) { quitar.insert(e.id) }
                    }
                    ForEach(adjuntos) { a in
                        MiniaturaEvidencia(fuente: .nueva(a)) {
                            adjuntos.removeAll { $0.id == a.id }
                            try? reports.archivos.borrarTemporal(a)
                        }
                    }
                }
            }
            if restantes > 0 {
                Menu {
                    Button("Elegir de la galería", systemImage: "photo.on.rectangle") { mostrarFotos = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Tomar foto", systemImage: "camera") { mostrarCamara = true }
                    }
                    Button("Elegir un PDF", systemImage: "doc") { mostrarArchivos = true }
                    #if DEBUG
                    if config.evidenciaDePrueba {
                        Button("Imagen de prueba") { Task { await agregarImagen(Self.imagenDePrueba()) } }
                    }
                    #endif
                } label: {
                    VStack(spacing: 8) {
                        Symbol("photo.badge.plus", size: 24, color: Theme.textSlate)
                        Text(verbatim: "Agregar evidencia (quedan \(restantes))").ofraude(13, color: Theme.textSlate)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .ofraudeCard(radius: 8)
                }
                .accessibilityLabel("Agregar evidencia")
                .accessibilityIdentifier("reporte.evidencia.agregar")
            }
            if procesando {
                ProgressView("Quitando metadatos…").tint(Theme.accent)
            }
            FieldError(mensaje: error)
            Text("Máximo 3 archivos. Quitamos la ubicación de las fotos antes de guardarlas.")
                .ofraude(12, color: Theme.textMuted)
        }
        .photosPicker(isPresented: $mostrarFotos, selection: $seleccion, maxSelectionCount: max(restantes, 1), matching: .images)
        .onChange(of: seleccion) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await agregarFotos(items)
                seleccion = []
            }
        }
        .fullScreenCover(isPresented: $mostrarCamara) {
            CameraPicker { datos in Task { await agregarImagen(datos) } }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $mostrarArchivos, allowedContentTypes: [.pdf]) { resultado in
            Task { await agregarPDF(resultado) }
        }
    }

    private func agregarFotos(_ items: [PhotosPickerItem]) async {
        for item in items.prefix(restantes) {
            guard let datos = try? await item.loadTransferable(type: Data.self) else {
                error = "No se pudo leer una de las fotos."
                continue
            }
            await agregarImagen(datos)
        }
    }

    private func agregarImagen(_ datos: Data) async {
        procesando = true
        defer { procesando = false }
        do {
            // Fuera del hilo principal: reducir y recodificar una foto grande tarda.
            let limpia = try await Task.detached(priority: .userInitiated) {
                try ProcesadorEvidencia.limpiarImagen(datos)
            }.value
            adjuntos.append(try reports.archivos.guardarTemporal(limpia, tipo: "image/jpeg"))
            error = nil
        } catch ErrorEvidencia.muyGrande {
            error = "La imagen pesa demasiado (máximo 5 MB después de reducirla)."
        } catch {
            self.error = "Ese archivo no es una imagen válida."
        }
    }

    private func agregarPDF(_ resultado: Result<URL, Error>) async {
        guard case .success(let url) = resultado else { return }
        guard url.startAccessingSecurityScopedResource() else {
            error = "No se pudo abrir el archivo."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let datos = try Data(contentsOf: url)
            try ProcesadorEvidencia.validarPDF(datos)
            adjuntos.append(try reports.archivos.guardarTemporal(datos, tipo: "application/pdf"))
            error = nil
        } catch ErrorEvidencia.muyGrande {
            error = "El PDF pesa más de 10 MB."
        } catch {
            self.error = "Ese archivo no es un PDF válido."
        }
    }

    #if DEBUG
    /// Solo para XCUITest: el selector de fotos corre fuera de la app y no se puede automatizar.
    static func imagenDePrueba() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).jpegData(withCompressionQuality: 0.9) { contexto in
            UIColor.orange.setFill()
            contexto.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
    }
    #endif
}

/// Miniatura tocable (abre el visor) con botón opcional para quitarla.
struct MiniaturaEvidencia: View {
    enum Fuente: Hashable {
        case guardada(Evidencia)
        case nueva(Adjunto)
    }

    let fuente: Fuente
    var quitar: (() -> Void)?

    @Environment(ReportsStore.self) private var reports
    @State private var imagen: UIImage?
    @State private var verCompleta = false

    private var esPDF: Bool {
        switch fuente {
        case .guardada(let e): return e.esPDF
        case .nueva(let a): return a.esPDF
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button { verCompleta = true } label: {
                Group {
                    if esPDF {
                        Symbol("doc.richtext", size: 32, color: Theme.textSlate)
                    } else if let imagen {
                        Image(uiImage: imagen).resizable().scaledToFill()
                    } else {
                        ProgressView().tint(Theme.accent)
                    }
                }
                .frame(width: 96, height: 96)
                .clipped()
                .ofraudeCard(radius: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(esPDF ? "Evidencia PDF" : "Foto de evidencia")

            if let quitar {
                Button(action: quitar) { Symbol("xmark.circle.fill", size: 22, color: Theme.dangerText) }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel("Quitar evidencia")
            }
        }
        .task { if !esPDF { imagen = (await MiniaturaEvidencia.datos(de: fuente, reports: reports)).flatMap(UIImage.init(data:)) } }
        .sheet(isPresented: $verCompleta) { VisorEvidencia(fuente: fuente) }
    }

    static func datos(de fuente: Fuente, reports: ReportsStore) async -> Data? {
        switch fuente {
        case .guardada(let e): return try? await reports.datosEvidencia(e)
        case .nueva(let a): return try? reports.archivos.datos(de: a)
        }
    }
}

/// Evidencia a pantalla completa. Los PDF se muestran con PDFKit, que no ejecuta JavaScript.
struct VisorEvidencia: View {
    let fuente: MiniaturaEvidencia.Fuente

    @Environment(ReportsStore.self) private var reports
    @Environment(\.dismiss) private var dismiss
    @State private var datos: Data?

    var body: some View {
        NavigationStack {
            Group {
                if let datos, case .guardada(let e) = fuente, e.esPDF {
                    VistaPDF(datos: datos)
                } else if let datos, case .nueva(let a) = fuente, a.esPDF {
                    VistaPDF(datos: datos)
                } else if let datos, let imagen = UIImage(data: datos) {
                    Image(uiImage: imagen).resizable().scaledToFit()
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ofraudeScreen()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
            .task { datos = await MiniaturaEvidencia.datos(de: fuente, reports: reports) }
        }
    }
}

struct VistaPDF: UIViewRepresentable {
    let datos: Data

    func makeUIView(context: Context) -> PDFView {
        let vista = PDFView()
        vista.autoScales = true
        vista.document = PDFDocument(data: datos)
        return vista
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Sin cambios: el PDF es de solo lectura y se carga una sola vez en makeUIView.
    }
}
