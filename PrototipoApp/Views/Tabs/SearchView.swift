//
//  SearchView.swift
//  PrototipoApp
//
//  Reemplaza: escena `search-vc` / SearchViewController.
//  Antes nada filtraba y las categorías abrían un detalle fijo. Ahora el texto, los chips, el
//  menú de categoría, las tarjetas de categoría y el riesgo arman un `FiltroBusqueda` que se manda al backend (solo reportes
//  validados). Sin filtros muestra los reportes validados más recientes debajo de las categorías.
//  Recibe la búsqueda que deja Inicio en `AppState.pendingSearch`.
//

import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(ReportsStore.self) private var reports
    @State private var filtro = FiltroBusqueda()
    /// Palabra del chip elegido (#Descuentos, #MercadoLibre). Va aparte de la barra: un chip se
    /// selecciona, no escribe en el campo de búsqueda.
    @State private var etiqueta: String?

    /// Los 4 chips del storyboard, ahora tocables.
    private enum Chip: Int, CaseIterable {
        case descuentos, tiendaClonada, sorteoFalso, mercadoLibre

        var titulo: String {
            switch self {
            case .descuentos: "#Descuentos"
            case .tiendaClonada: "#TiendaClonada"
            case .sorteoFalso: "#SorteoFalso"
            case .mercadoLibre: "#MercadoLibre"
            }
        }

        /// Los chips de palabra buscan ese texto; los de tipo eligen la categoría.
        var palabra: String? {
            switch self {
            case .descuentos: "descuento"
            case .mercadoLibre: "mercado libre"
            case .tiendaClonada, .sorteoFalso: nil
            }
        }

        var tipo: TipoFraude? {
            switch self {
            case .tiendaClonada: .tiendaClonada
            case .sorteoFalso: .sorteoFalso
            case .descuentos, .mercadoLibre: nil
            }
        }
    }

    private func activo(_ chip: Chip) -> Bool {
        if let palabra = chip.palabra { return etiqueta == palabra }
        if let tipo = chip.tipo { return filtro.tipos == [tipo] }
        return false
    }

    private func alternar(_ chip: Chip) {
        let estaba = activo(chip)
        if let palabra = chip.palabra { etiqueta = estaba ? nil : palabra }
        if let tipo = chip.tipo { filtro.tipos = estaba ? [] : [tipo] }
    }

    /// El enlace escrito en la barra, ya normalizado; `nil` si lo escrito no es un enlace http(s).
    private var enlace: String? {
        URLTools.pareceURL(filtro.texto) ? URLTools.normalizar(filtro.texto) : nil
    }

    /// Lo que se manda a buscar: lo escrito en la barra más la palabra del chip elegido. Con un
    /// enlace se busca por su dominio, para encontrar los reportes del mismo sitio aunque la ruta cambie.
    private var filtroEfectivo: FiltroBusqueda {
        var f = filtro
        if let enlace, let dominio = URLTools.host(de: enlace) { f.texto = dominio }
        // La palabra del chip se suma a lo que ya haya (el dominio, si escribieron un enlace).
        if let etiqueta {
            let base = f.texto.trimmingCharacters(in: .whitespacesAndNewlines)
            f.texto = base.isEmpty ? etiqueta : "\(base) \(etiqueta)"
        }
        return f
    }

    private struct Clave: Hashable {
        let filtro: FiltroBusqueda
        let version: Int
    }

    /// Ancho de cada tarjeta de categoría; crece con Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var anchoCategoria: CGFloat = 228

    var body: some View {
        VStack(spacing: 0) {
            TopBar(background: Theme.card) {
                Symbol("checkmark.seal.fill", size: 24, color: Theme.accent).accessibilityHidden(true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    encabezado
                    barraBusqueda
                    if let enlace { DiagnosticoURLView(url: enlace) }
                    filtros
                    if filtroEfectivo.estaVacio { categorias }
                    resultados
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await recargar(filtroEfectivo) }
        }
        .ofraudeScreen()
        .hideKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: tomarPendiente)
        .onChange(of: appState.pendingSearch) { tomarPendiente() }
        // Espera 300 ms a que la persona deje de escribir; `.task(id:)` cancela la búsqueda anterior.
        // Sin filtros también hay reportes: los validados más recientes, junto con las categorías.
        .task(id: Clave(filtro: filtroEfectivo, version: reports.version)) {
            let filtro = filtroEfectivo
            if !filtro.estaVacio {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await recargar(filtro)
        }
    }

    private func recargar(_ filtro: FiltroBusqueda) async {
        guard filtro.estaVacio else { return await reports.buscar(filtro) }
        async let categorias: Void = reports.cargarCategorias()
        async let recientes: Void = reports.buscar(filtro)
        _ = await (categorias, recientes)
    }

    // MARK: Búsqueda y filtros

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Buscar reportes").ofraude(26, .bold, color: Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Reportes validados por la comunidad. Pega un enlace para saber si es confiable.")
                .ofraude(15, color: Theme.textSlate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var barraBusqueda: some View {
        HStack(spacing: 10) {
            Symbol("magnifyingglass", size: 18, color: Theme.textMuted).accessibilityHidden(true)
            TextField("", text: $filtro.texto,
                      prompt: Text("Palabra, sitio o enlace").foregroundStyle(Theme.textMuted))
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .ofraudeFont(15)
                .foregroundStyle(Theme.textLight)
                .tint(Theme.accent)
                .accessibilityLabel("Buscar reportes")
                .accessibilityIdentifier("buscar.campo")
                .onChange(of: filtro.texto) { _, nuevo in
                    if nuevo.count > 300 { filtro.texto = String(nuevo.prefix(300)) }
                }
            if !filtro.texto.isEmpty {
                Button { filtro.texto = "" } label: {
                    Symbol("xmark.circle.fill", size: 18, color: Theme.textMuted)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar búsqueda")
                .accessibilityIdentifier("buscar.borrarTexto")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, filtro.texto.isEmpty ? 14 : 2)
        .frame(minHeight: 54)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
    }

    /// Una sola fila deslizable: categoría y riesgo (menús) y los chips de siempre.
    private var filtros: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Todas las categorías") { filtro.tipos = [] }
                    ForEach(TipoFraude.allCases) { tipo in
                        Button(tipo.categoria) { filtro.tipos = [tipo] }
                    }
                } label: {
                    ChipBusqueda(titulo: filtro.tipos.isEmpty ? "Categoría" : tituloCategoria,
                                 icono: "square.grid.2x2.fill", activo: !filtro.tipos.isEmpty, menu: true)
                }
                .accessibilityLabel("Categoría: \(tituloCategoria)")
                .accessibilityIdentifier("buscar.categoriaFiltro")

                Menu {
                    Button("Todos los riesgos") { filtro.riesgoMinimo = nil }
                    ForEach(NivelRiesgo.asignables, id: \.self) { nivel in
                        Button("\(nivel.titulo) o más") { filtro.riesgoMinimo = nivel }
                    }
                } label: {
                    ChipBusqueda(titulo: filtro.riesgoMinimo.map { "Riesgo \($0.titulo) o más" } ?? "Riesgo",
                                 icono: "exclamationmark.shield.fill", activo: filtro.riesgoMinimo != nil, menu: true)
                }
                .accessibilityLabel("Riesgo: \(filtro.riesgoMinimo.map { "\($0.titulo) o más" } ?? "todos")")
                .accessibilityIdentifier("buscar.riesgo")

                ForEach(Chip.allCases, id: \.self) { chip in
                    Button { alternar(chip) } label: {
                        ChipBusqueda(titulo: chip.titulo, activo: activo(chip))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(activo(chip) ? .isSelected : [])
                    .accessibilityIdentifier("buscar.chip.\(chip.rawValue)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        // La fila llega hasta las orillas de la pantalla, pero empieza alineada con lo demás.
        .padding(.horizontal, -16)
    }

    /// Lo que muestra el menú de categoría: "todas", el nombre de la elegida o cuántas hay.
    private var tituloCategoria: String {
        if filtro.tipos.isEmpty { return "todas" }
        if filtro.tipos.count == 1, let tipo = filtro.tipos.first { return tipo.categoria }
        return "\(filtro.tipos.count) elegidas"
    }

    // MARK: Categorías

    private var categorias: some View {
        VStack(alignment: .leading, spacing: 12) {
            tituloSeccion("CATEGORÍAS")
            CargaView(carga: reports.categorias, reintentar: { await reports.cargarCategorias() }) { lista in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(lista) { tarjetaCategoria($0) }
                    }
                    // Todas las tarjetas con la altura de la más alta.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, -16)
            }
        }
    }

    private func tarjetaCategoria(_ c: ConteoCategoria) -> some View {
        let color = c.total == 0 ? Theme.textSlate : c.riesgoMaximo.color
        return Button {
            filtro = FiltroBusqueda(tipos: [c.tipo])
            etiqueta = nil
        } label: {
            HStack(spacing: 12) {
                Symbol(c.tipo.icono, size: 18, color: color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.tipo.categoria).ofraude(14, .bold, color: Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: c.total == 0 ? "Sin reportes" : "\(c.total) · riesgo \(c.riesgoMaximo.titulo.lowercased())")
                        .ofraude(12, .semibold, color: color)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: anchoCategoria, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(c.total == 0 ? "\(c.tipo.categoria), sin reportes"
                                         : "\(c.tipo.categoria), \(c.total) reporte\(c.total == 1 ? "" : "s"), riesgo máximo \(c.riesgoMaximo.titulo.lowercased())")
        .accessibilityHint("Muestra los reportes de esta categoría")
        .accessibilityIdentifier("buscar.categoria.\(c.tipo)")
    }

    // MARK: Reportes

    private var tituloResultados: String {
        if enlace != nil { return "REPORTES DE ESTE SITIO" }
        return filtroEfectivo.estaVacio ? "REPORTES RECIENTES" : "RESULTADOS"
    }

    private var resultados: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    tituloSeccion(tituloResultados)
                    if let lista = reports.resultados.valor {
                        Text(verbatim: "\(lista.count) reporte\(lista.count == 1 ? "" : "s") validado\(lista.count == 1 ? "" : "s")")
                            .ofraude(13, color: Theme.textSlate)
                    }
                }
                Spacer(minLength: 8)
                BotonActualizar(identificador: "buscar.actualizar") { await recargar(filtroEfectivo) }
            }
            if !filtroEfectivo.estaVacio {
                Button {
                    filtro = FiltroBusqueda()
                    etiqueta = nil
                } label: {
                    HStack(spacing: 6) {
                        Symbol("xmark", size: 11, color: Theme.accent)
                        Text("Limpiar filtros").ofraude(13, .semibold, color: Theme.accent)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("buscar.limpiar")
            }
            CargaView(carga: reports.resultados, esVacio: \.isEmpty, vacio: estadoVacio,
                      reintentar: { await recargar(filtroEfectivo) }) { lista in
                LazyVStack(spacing: 12) {
                    ForEach(lista) { tarjetaReporte($0) }
                }
            }
        }
    }

    private var estadoVacio: EstadoVacio {
        if enlace != nil {
            return EstadoVacio(icono: "checkmark.shield", titulo: "Nadie lo ha reportado",
                               mensaje: "No hay reportes validados de este sitio. Si te pareció un fraude, repórtalo.")
        }
        if filtroEfectivo.estaVacio {
            return EstadoVacio(icono: "tray", titulo: "Aún no hay reportes",
                               mensaje: "Cuando moderación valide reportes de la comunidad, aparecerán aquí.")
        }
        return EstadoVacio(icono: "magnifyingglass", titulo: "Sin resultados",
                           mensaje: "No encontramos reportes validados con esos filtros.")
    }

    private func tarjetaReporte(_ r: Reporte) -> some View {
        NavigationLink(value: Route.reportDetail(r.id)) {
            HStack(spacing: 0) {
                // Franja del color del riesgo: se distingue de un vistazo.
                r.nivelRiesgo.color.frame(width: 5).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            etiquetaRiesgo(r)
                            Spacer(minLength: 8)
                            fecha(r)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            etiquetaRiesgo(r)
                            fecha(r)
                        }
                    }
                    Text(r.titulo).ofraude(17, .bold, color: Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(r.descripcion).ofraude(14, color: Theme.textLight)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    detalles(r)
                    Hairline()
                    HStack(spacing: 14) {
                        dato("person.2.fill", "\(r.confirmaciones)", "confirmaciones")
                        dato("bubble.left.fill", "\(r.comentarios)", "comentarios")
                        Spacer(minLength: 4)
                        HStack(spacing: 4) {
                            Text("Ver detalle").ofraude(13, .semibold, color: Theme.accent)
                            Symbol("chevron.right", size: 11, color: Theme.accent)
                        }
                        .accessibilityHidden(true)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el detalle del reporte")
        .accessibilityIdentifier("buscar.resultado.\(r.id)")
    }

    private func etiquetaRiesgo(_ r: Reporte) -> some View {
        Etiqueta(texto: "RIESGO \(r.nivelRiesgo.titulo)", color: r.nivelRiesgo.color, fondo: r.nivelRiesgo.color.opacity(0.18))
    }

    private func fecha(_ r: Reporte) -> some View {
        Text(verbatim: Formato.relativo(r.fechaCreacion)).ofraude(12, color: Theme.textSlate)
    }

    /// Tipo, ciudad y dominio (desactivado: nunca es un enlace tocable).
    private func detalles(_ r: Reporte) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    dato(r.tipo.icono, r.tipoVisible)
                    if !r.ciudad.isEmpty { dato("mappin.and.ellipse", r.ciudad) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    dato(r.tipo.icono, r.tipoVisible)
                    if !r.ciudad.isEmpty { dato("mappin.and.ellipse", r.ciudad) }
                }
            }
            if let sitio = r.sitio, let host = URLTools.host(de: sitio.url) {
                dato("globe", URLTools.desactivar(host))
            }
        }
    }

    /// Ícono + texto en gris claro. `sufijo` solo se lee en VoiceOver ("3 confirmaciones").
    private func dato(_ icono: String, _ texto: String, _ sufijo: String? = nil) -> some View {
        HStack(spacing: 6) {
            Symbol(icono, size: 13, color: Theme.textSlate).accessibilityHidden(true)
            Text(verbatim: texto).ofraude(13, .medium, color: Theme.textSlate).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sufijo.map { "\(texto) \($0)" } ?? texto)
    }

    private func tituloSeccion(_ texto: String) -> some View {
        Text(verbatim: texto).ofraude(14, .bold, color: Theme.accent)
            .accessibilityAddTraits(.isHeader)
    }

    private func tomarPendiente() {
        guard let pendiente = appState.pendingSearch else { return }
        filtro = pendiente
        etiqueta = nil
        appState.pendingSearch = nil
    }
}

/// Chip redondo de la fila de filtros: naranja cuando está activo, con flecha si abre un menú.
private struct ChipBusqueda: View {
    let titulo: String
    var icono: String? = nil
    let activo: Bool
    var menu = false

    private var color: Color { activo ? Theme.background : Theme.textLight }

    var body: some View {
        HStack(spacing: 6) {
            if let icono { Symbol(icono, size: 13, color: color).accessibilityHidden(true) }
            Text(verbatim: titulo).ofraude(13, .semibold, color: color).lineLimit(1)
            if menu { Symbol("chevron.down", size: 10, color: color).accessibilityHidden(true) }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(activo ? Theme.accent : Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(activo ? Theme.accent : Theme.border, lineWidth: 1))
        .contentShape(Capsule())
    }
}

#Preview {
    NavigationStack { SearchView() }
        .entornoDePrueba()
}
