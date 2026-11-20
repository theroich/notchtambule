//
//  MenuBarContent.swift
//  NotchTubeAudio
//

import AppKit
import SwiftUI

/// Contents of the `MenuBarExtra` status item menu.
struct MenuBarContent: View {
    let environment: AppEnvironment

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(environment.isNotchShowing ? "Ocultar panel del notch" : "Mostrar descargas en el notch") {
            environment.notchController.toggleFromMenu()
        }

        Button("Descargar enlace del portapapeles") {
            environment.detectClipboardNow()
        }

        Divider()

        Button("Abrir carpeta de descargas") {
            environment.openDownloadFolder()
        }

        Button("Configuración…") {
            openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Salir de NotchTubeAudio") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
