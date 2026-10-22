//
//  Mutex.swift
//  ZeroScam
//
//  Candado para estado compartido entre hilos, con la misma forma que
//  `Mutex` de la librería Synchronization. Ese tipo pide iOS 18 y la app debe
//  poder instalarse desde iOS 17 (RNF03), así que se usa `OSAllocatedUnfairLock`
//  (disponible desde iOS 16), que hace el mismo trabajo.
//

import os

final class Mutex<Value>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    init(_ valor: Value) {
        lock = OSAllocatedUnfairLock(uncheckedState: valor)
    }

    /// Corre `cuerpo` con el valor protegido; solo un hilo a la vez.
    func withLock<R>(_ cuerpo: (inout Value) throws -> R) rethrows -> R {
        try lock.withLockUnchecked(cuerpo)
    }
}
