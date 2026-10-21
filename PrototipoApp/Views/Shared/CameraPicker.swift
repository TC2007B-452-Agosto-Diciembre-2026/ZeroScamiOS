//
//  CameraPicker.swift
//  PrototipoApp
//
//  Cámara del sistema (UIImagePickerController), igual que en la práctica Camera. Solo se ofrece
//  si el dispositivo tiene cámara: el simulador no tiene.
//

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    let alTomar: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controlador = UIImagePickerController()
        controlador.sourceType = .camera
        controlador.delegate = context.coordinator
        return controlador
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinador { Coordinador(self) }

    final class Coordinador: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let padre: CameraPicker

        init(_ padre: CameraPicker) { self.padre = padre }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let imagen = info[.originalImage] as? UIImage, let datos = imagen.jpegData(compressionQuality: 0.9) {
                padre.alTomar(datos)
            }
            padre.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            padre.dismiss()
        }
    }
}
