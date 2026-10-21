//
//  ReportView.swift
//  PrototipoApp
//
//  Reemplaza: escena `report-vc` / ReportViewController.
//  Antes "Enviar" solo abría la pantalla de éxito; ahora valida y guarda el reporte. La misma
//  pantalla sirve para un reporte nuevo (pestaña Reportar), para "Yo también" (llega con tipo y
//  enlace) y para editar uno propio que aún no se ha validado.
//  - La selección (borde naranja) sigue siendo la del original (antes `select(_:in:)`).
//  - Los errores de un campo aparecen al salir de él; el botón se habilita cuando todo es válido.
//

import SwiftUI

struct ReportView: View {
    enum Modo: Hashable {
        case nuevo(ReportePrefill?)
        case editar(Int64)
    }

    var modo: Modo = .nuevo(nil)

    @Environment(AppState.self) private var appState
    @Environment(ReportsStore.self) private var reports
    @Environment(SessionStore.self) private var session
    @Environment(ColaReportes.self) private var cola
    @Environment(\.dismiss) private var dismiss

    @State private var borrador = ReporteBorrador()
    @State private var existentes: [Evidencia] = []
    @State private var preparado = false
    @State private var tocados: Set<Campo> = []
    @State private var errorEnvio: String?
    /// "Se guardó sin conexión": el formulario ya se vació y el reporte espera en la cola.
    @State private var avisoCola: String?
    @FocusState private var foco: Campo?

    private let fraudRows: [[TipoFraude]] = [[.ofertaFalsa, .sorteoFalso], [.tiendaClonada, .marketplace], [.llamada, .otro]]

    private var esEdicion: Bool {
        if case .editar = modo { return true }
        return false
    }

    private var errores: [ErrorCampo] {
        var lista = Validador.reporte(borrador.limpio, ahora: Date())
        let total = existentes.filter { !borrador.quitarEvidencias.contains($0.id) }.count + borrador.adjuntos.count
        if total > 3 { lista.append(ErrorCampo(campo: .adjuntos, mensaje: "Máximo 3 archivos de evidencia.")) }
        return lista
    }

    private func error(_ campo: Campo) -> String? {
        tocados.contains(campo) ? errores.mensaje(para: campo) : nil
    }

    /// Para los datos de la persona afectada el error aparece mientras se escribe (desde el tercer
    /// carácter), no solo al salir del campo: así se ve de inmediato si el correo o el teléfono van mal.
    private func errorAlEscribir(_ campo: Campo, _ texto: String) -> String? {
        tocados.contains(campo) || texto.count >= 3 ? errores.mensaje(para: campo) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(esEdicion ? "Editar Reporte" : "Emitir Reporte").ofraude(28, .bold, color: Theme.textPrimary)
                Text("Ayuda a la comunidad reportando actividades sospechosas o fraudulentas.")
                    .ofraude(16, color: Theme.textMuted)

                if !esEdicion { EstadoConexionView() }
                // Solo mientras siga esperando: cuando la cola lo envía, EstadoConexionView lo avisa.
                if let avisoCola, cola.porEnviar > 0 {
                    AvisoBanner(texto: avisoCola, tono: .exito).accessibilityIdentifier("reporte.enCola")
                }

                anonymousCard

                Text("¿A quién le ocurrió el fraude?").ofraude(18, .semibold, color: Theme.textPrimary)
                HStack(spacing: 16) {
                    ForEach(Afectado.allCases, id: \.self) { opcion in
                        choiceButton(opcion.titulo, isSelected: borrador.afectado == opcion,
                                     identificador: "reporte.afectado.\(opcion)") { borrador.afectado = opcion }
                    }
                }

                lugarYPersona

                Text("Tipo de Fraude").ofraude(18, .semibold, color: Theme.textPrimary)
                ForEach(fraudRows, id: \.self) { fila in
                    HStack(spacing: 16) {
                        ForEach(fila) { tipo in
                            choiceButton(tipo.rawValue, isSelected: borrador.tipo == tipo,
                                         identificador: "reporte.tipo.\(tipo)") { borrador.tipo = tipo }
                        }
                    }
                }
                // Antes "(OPCIONAL)" se veía siempre; ahora solo cuando se elige "Otro", y es obligatorio.
                if borrador.tipo == .otro {
                    LabeledTextField(label: "ESPECIFICA EL TIPO", placeholder: "Ej: Fraude piramidal, préstamo falso...",
                                     text: $borrador.tipoOtro, error: error(.tipoOtro), maximo: 50,
                                     foco: $foco, campo: .tipoOtro, identificador: "reporte.tipoOtro")
                }

                LabeledTextField(label: "TÍTULO DEL REPORTE", placeholder: "Ej: Tienda falsa de consolas en Instagram",
                                 text: $borrador.titulo, error: error(.titulo), maximo: 120,
                                 foco: $foco, campo: .titulo, identificador: "reporte.titulo")

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("FECHA DEL INCIDENTE")
                    DatePicker("Fecha del incidente", selection: $borrador.fechaIncidente,
                               in: Date().addingTimeInterval(-365 * 86_400)...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .tint(Theme.accent)
                        .environment(\.locale, Formato.locale)
                        .accessibilityIdentifier("reporte.fecha")
                    FieldError(mensaje: error(.fecha))
                }

                LabeledTextField(label: "URL O TEXTO SOSPECHOSO", placeholder: "Pega aquí el enlace o el mensaje",
                                 text: $borrador.urlOTexto, keyboard: .URL, error: error(.urlOTexto), maximo: 2048,
                                 foco: $foco, campo: .urlOTexto, identificador: "reporte.url")
                Text("Pega el enlace tal cual: se guarda desactivado para que nadie lo abra por accidente.")
                    .ofraude(12, color: Theme.textMuted)

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("DESCRIPCIÓN DEL INCIDENTE")
                    OfraudeTextEditor(placeholder: "Describe cómo ocurrió el intento de fraude...", text: $borrador.descripcion,
                                      maximo: 2000, error: error(.descripcion), foco: $foco, campo: .descripcion,
                                      identificador: "reporte.descripcion")
                }

                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("EVIDENCIA (OPCIONAL)")
                    EvidenceEditor(adjuntos: $borrador.adjuntos, existentes: existentes, quitar: $borrador.quitarEvidencias)
                    FieldError(mensaje: errores.mensaje(para: .adjuntos))
                }

                if let errorEnvio {
                    AvisoBanner(texto: errorEnvio, tono: .error).accessibilityIdentifier("reporte.error")
                }

                BotonAccion(titulo: esEdicion ? "GUARDAR CAMBIOS" : "ENVIAR REPORTE",
                            estilo: OfraudeButtonStyle(foreground: Theme.background, size: 15, weight: .bold, radius: 4, height: 56),
                            habilitado: errores.isEmpty, identificador: "reporte.enviar") {
                    await enviar()
                }
                if !errores.isEmpty {
                    Text("Completa los campos marcados para enviar.")
                        .ofraude(12, color: Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .navigationTitle(esEdicion ? "Editar reporte" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { foco = nil }
            }
        }
        .onChange(of: foco) { anterior, _ in
            if let anterior { tocados.insert(anterior) }
        }
        // La casilla no tiene foco de teclado: se marca como tocada al cambiarla o al cambiar "A quién".
        .onChange(of: borrador.persona.autorizo) { tocados.insert(.personaAutorizo) }
        .onChange(of: borrador.afectado) { tocados.insert(.personaAutorizo) }
        .task { await preparar() }
    }

    private var anonymousCard: some View {
        Toggle(isOn: $borrador.esAnonimo) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reportar de forma anónima").ofraude(15, .semibold, color: Theme.textPrimary)
                Text("Tu nombre no se compartirá con la comunidad. El equipo de moderación sí sabe quién reportó.")
                    .ofraude(13, color: Theme.textMuted)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .ofraudeCard(radius: 8)
        .accessibilityIdentifier("reporte.anonimo")
    }

    /// "A mí": solo la ciudad. "A otra persona": nombre, contacto, ciudad y su autorización.
    private var lugarYPersona: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(borrador.afectado == .otraPersona ? "DATOS DE LA PERSONA AFECTADA" : "¿DÓNDE OCURRIÓ?")
            if borrador.afectado == .otraPersona {
                OfraudeTextField(placeholder: "Nombre completo", text: $borrador.persona.nombre, contenido: .name,
                                 error: errorAlEscribir(.personaNombre, borrador.persona.nombre) != nil, maximo: 100,
                                 foco: $foco, campo: .personaNombre, identificador: "reporte.persona.nombre")
                FieldError(mensaje: errorAlEscribir(.personaNombre, borrador.persona.nombre))
                // Teclado de correo: trae @, punto y números a la mano, y no pone mayúsculas.
                OfraudeTextField(placeholder: "Teléfono o correo de contacto", text: $borrador.persona.contacto,
                                 keyboard: .emailAddress,
                                 error: errorAlEscribir(.personaContacto, borrador.persona.contacto) != nil, maximo: 150,
                                 foco: $foco, campo: .personaContacto, identificador: "reporte.persona.contacto")
                FieldError(mensaje: errorAlEscribir(.personaContacto, borrador.persona.contacto))
            }
            OfraudeTextField(placeholder: "Ciudad", text: $borrador.ciudad, contenido: .addressCity,
                             error: error(.ciudad) != nil, maximo: 60,
                             foco: $foco, campo: .ciudad, identificador: "reporte.ciudad")
            FieldError(mensaje: error(.ciudad))
            if borrador.afectado == .otraPersona {
                CasillaVerificacion(texto: "Esta persona me autorizó a compartir sus datos con el equipo de moderación.",
                                    marcado: $borrador.persona.autorizo, identificador: "reporte.persona.autorizo")
                FieldError(mensaje: error(.personaAutorizo))
                Text("Sus datos nunca se publican.").ofraude(12, color: Theme.textMuted)
            }
        }
    }

    private func choiceButton(_ title: String, isSelected: Bool, identificador: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .ofraude(14, .bold, color: Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(isSelected ? Theme.selected : Theme.card, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identificador)
    }

    private func preparar() async {
        guard !preparado else { return }
        preparado = true
        switch modo {
        case .nuevo(let prefill?):
            borrador.tipo = prefill.tipo
            borrador.tipoOtro = prefill.tipoOtro ?? ""
            borrador.urlOTexto = prefill.urlOTexto
        case .nuevo(nil):
            break
        case .editar(let id):
            do {
                let r = try await reports.detalle(id: id)
                borrador = ReporteBorrador(desde: r)
                existentes = r.evidencias
            } catch {
                errorEnvio = error.mensajeUsuario
            }
        }
    }

    static let mensajeEnCola = "Sin conexión: guardamos tu reporte en el teléfono. Se enviará solo cuando regrese la red."

    private func enviar() async {
        errorEnvio = nil
        avisoCola = nil
        foco = nil
        do {
            switch modo {
            case .nuevo:
                let limpio = borrador.limpio
                // La misma clave viaja en este intento y, si se corta la red, en los de la cola.
                let clave = UUID()
                let reporte: Reporte
                do {
                    reporte = try await reports.crear(limpio, clave: clave.uuidString)
                } catch AppError.sinConexion {
                    try cola.agregar(limpio, clave: clave)
                    borrador = ReporteBorrador()
                    tocados = []
                    avisoCola = Self.mensajeEnCola
                    return
                }
                borrador = ReporteBorrador()
                tocados = []
                appState.push(.reportSuccess(reporte.id))
            case .editar(let id):
                _ = try await reports.actualizar(id: id, borrador.limpio)
                dismiss()
            }
        } catch {
            errorEnvio = error.mensajeUsuario
        }
    }
}

#Preview {
    NavigationStack { ReportView() }
        .entornoDePrueba()
}
