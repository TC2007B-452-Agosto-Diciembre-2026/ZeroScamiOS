//
//  AvatarView.swift
//  PrototipoApp
//
//  Foto de perfil (si hay y si quien mira tiene permiso) o el ícono de persona del storyboard.
//

import SwiftUI

struct AvatarView: View {
    let usuario: Usuario?
    var tamano: CGFloat = 48
    var fondo: Color = Theme.avatarBackground

    @Environment(SessionStore.self) private var session
    @State private var imagen: UIImage?

    private struct Clave: Hashable {
        let ruta: String?
        let version: Int
    }

    var body: some View {
        Group {
            if let imagen {
                Image(uiImage: imagen).resizable().scaledToFill()
            } else {
                Symbol("person.fill", size: tamano * 0.42, color: Theme.textPrimary)
            }
        }
        .frame(width: tamano, height: tamano)
        .background(fondo, in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
        // La versión cuenta solo para la foto propia: es la que se acaba de cambiar.
        .task(id: Clave(ruta: usuario?.avatarRuta, version: usuario?.id == session.usuario?.id ? session.versionAvatar : 0)) {
            guard let usuario, usuario.avatarRuta != nil, let datos = await session.datosAvatar(de: usuario) else {
                imagen = nil
                return
            }
            imagen = UIImage(data: datos)
        }
    }
}
