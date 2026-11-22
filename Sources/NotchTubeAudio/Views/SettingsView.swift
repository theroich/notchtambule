//
//  SettingsView.swift
//  NotchTubeAudio
//

import AppKit
import SwiftUI

/// SwiftUI settings window (Scene > Settings, Cmd+,).
struct SettingsView: View {
    let settings: SettingsManager

    var body: some View {
        Form {
            YouTubeAudioSettingsView(settings: settings)

            Section("Comportamiento") {
                Toggle("Escuchar el portapapeles automáticamente", isOn: monitoringBinding)

                Text("Al copiar un enlace de YouTube se mostrará el aviso en el notch. Los enlaces repetidos no reabren el aviso.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Ocultar el aviso tras") {
                    HStack(spacing: 10) {
                        Slider(
                            value: promptDurationBinding,
                            in: SettingsManager.minimumPromptDuration...SettingsManager.maximumPromptDuration,
                            step: 1
                        )
                        .frame(width: 190)

                        Text("\(Int(settings.promptAutoDismissSeconds)) s")
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Text("El aviso permanece abierto mientras el cursor esté sobre el notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
    }

    // MARK: - Bindings

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { settings.isClipboardMonitoringEnabled },
            set: { settings.isClipboardMonitoringEnabled = $0 }
        )
    }

    private var promptDurationBinding: Binding<Double> {
        Binding(
            get: { settings.promptAutoDismissSeconds },
            set: { settings.promptAutoDismissSeconds = $0 }
        )
    }
}
