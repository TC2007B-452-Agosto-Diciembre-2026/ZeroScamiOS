//
//  FiltroBusqueda.swift
//  PrototipoApp
//
//  Qué busca la persona en Buscar: texto libre, tipos y riesgo mínimo. La misma regla se usa
//  en el servidor Demo y se documenta para el backend.
//

import Foundation

nonisolated struct FiltroBusqueda: Sendable, Hashable {
    var texto = ""
    var tipos: Set<TipoFraude> = []
    var riesgoMinimo: NivelRiesgo?

    var estaVacio: Bool {
        texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tipos.isEmpty && riesgoMinimo == nil
    }

    /// Todas las palabras del texto deben aparecer (sin importar mayúsculas, acentos ni signos) en el
    /// título, la descripción, el tipo, la ciudad, la URL o el texto sospechoso. Además:
    /// - singular y plural se encuentran entre sí ("tiendas clonadas" halla "Tienda Clonada");
    /// - un teléfono se halla con o sin espacios y guiones ("5587654321" halla "+52 55 8765 4321");
    /// - una marca se halla con o sin espacio ("mercado libre" halla "mercadolibre.com").
    /// Debe seguir idéntico a `matches` de `backend/src/community/community.service.ts`.
    func coincide(_ r: Reporte) -> Bool {
        if !tipos.isEmpty && !tipos.contains(r.tipo) { return false }
        if let riesgoMinimo, r.nivelRiesgo < riesgoMinimo { return false }
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        let palabras = Self.palabras(texto)
        guard !palabras.isEmpty else { return false }   // solo signos ("???"): no hay nada que buscar
        let campos = [r.titulo, r.descripcion, r.tipoVisible, r.ciudad, r.sitio?.url ?? "", r.textoSospechoso ?? ""]
            .map(Self.palabras)
        let pajar = campos.flatMap { $0 }
        let pajarJunto = pajar.joined()
        let digitos = campos.map { $0.joined().filter(\.isNumber) }
        let todas = palabras.allSatisfy { palabra in
            let formas = Self.formas(de: palabra)
            if pajar.contains(where: { p in formas.contains { p.contains($0) } }) { return true }
            // Número de teléfono o folio: se compara solo con sus dígitos, ya sin separadores.
            return palabra.allSatisfy(\.isNumber) && digitos.contains { $0.contains(palabra) }
        }
        if todas { return true }
        // "mercado libre" contra "mercadolibre" (y al revés): se comparan pegados.
        let pegado = palabras.joined()
        if pegado.count >= 5, pajarJunto.contains(pegado) { return true }
        // Teléfono escrito con separadores ("55-8765-4321") contra uno pegado.
        let numero = palabras.joined()
        return numero.count >= 5 && numero.allSatisfy(\.isNumber) && digitos.contains { $0.contains(numero) }
    }

    /// Singular de una palabra sencilla en español: "clonadas" → "clonada". Se prueba junto con la
    /// original, así que una palabra que acaba en "s" por sí sola ("tenis") sigue encontrándose.
    private static func formas(de palabra: String) -> [String] {
        guard palabra.count > 3, palabra.hasSuffix("s"), !palabra.allSatisfy(\.isNumber) else { return [palabra] }
        return [palabra, String(palabra.dropLast())]
    }

    /// Palabras en minúsculas, sin acentos y sin signos: "¡Banco, BBVA!" → ["banco", "bbva"].
    static func palabras(_ s: String) -> [String] {
        normalizar(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func normalizar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Formato.locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
