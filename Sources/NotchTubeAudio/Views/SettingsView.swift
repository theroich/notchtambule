//
//  SettingsView.swift
//  NotchTubeAudio
//

import AppKit
import SwiftUI

/// SwiftUI settings window (Scene > Settings, Cmd+,).
struct SettingsView: View {
    let settings: SettingsManager

    @State private var detectionMessage: String?
    @State private var detectionSucceeded = false

    var body: some View {
        Form {
            Section("Descargas") {
                LabeledContent("Carpeta de destino") {
                    HStack(spacing: 8) {
                        Text(settings.downloadDirectory.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: 280, alignment: .trailing)

                        Button("Cambiar…") {
                            chooseDownloadFolder()
                        }

                        Button {
                            FileActions.openFolder(settings.downloadDirectory)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Abrir la carpeta en Finder")
                    }
                }

                LabeledContent("Formato por defecto") {
                    Picker("Formato por defecto", selection: defaultFormatBinding) {
                        ForEach(AudioFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            Section("Herramientas") {
                binaryRow(
                    title: "yt-dlp",
                    path: ytDlpBinding,
                    isAvailable: settings.isYTDLPAvailable
                )

                binaryRow(
                    title: "ffmpeg",
                    path: ffmpegBinding,
                    isAvailable: settings.isFFmpegAvailable
                )

                HStack(spacing: 10) {
                    Button("Autodetectar") {
                        autodetect()
                    }

                    if let detectionMessage {
                        Text(detectionMessage)
                            .font(.caption)
                            .foregroundStyle(detectionSucceeded ? .green : .orange)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }

                Text("Se ejecutan los binarios instalados en el sistema. Instálalos con “brew install yt-dlp ffmpeg”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    // MARK: - Rows

    private func binaryRow(title: String, path: Binding<String>, isAvailable: Bool) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField("", text: path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .labelsHidden()
                    .frame(minWidth: 260)

                Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isAvailable ? .green : .red)
                    .help(isAvailable ? "Ejecutable válido" : "No se encontró un ejecutable en esta ruta")
                    .accessibilityLabel(isAvailable ? "Ejecutable válido" : "Ejecutable no encontrado")

                Button("Elegir…") {
                    chooseExecutable(for: path)
                }
            }
        }
    }

    // MARK: - Bindings

    private var defaultFormatBinding: Binding<AudioFormat> {
        Binding(
            get: { settings.defaultFormat },
            set: { settings.defaultFormat = $0 }
        )
    }

    private var ytDlpBinding: Binding<String> {
        Binding(
            get: { settings.ytDlpPath },
            set: { settings.ytDlpPath = $0 }
        )
    }

    private var ffmpegBinding: Binding<String> {
        Binding(
            get: { settings.ffmpegPath },
            set: { settings.ffmpegPath = $0 }
        )
    }

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

    // MARK: - Panels

    private func chooseDownloadFolder() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Elegir carpeta de descargas"
        panel.prompt = "Elegir"
        panel.message = "Los audios MP3 y WAV se guardarán en esta carpeta."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.downloadDirectory

        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadDirectory = url
        }
    }

    private func chooseExecutable(for path: Binding<String>) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Elegir ejecutable"
        panel.prompt = "Elegir"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        let currentPath = path.wrappedValue
        if !currentPath.isEmpty {
            let directory = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: directory.path) {
                panel.directoryURL = directory
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            path.wrappedValue = url.path
        }
    }

    // MARK: - Actions

    private func autodetect() {
        let foundAll = settings.autodetectBinaries()
        detectionSucceeded = foundAll
        detectionMessage = foundAll
            ? "Rutas actualizadas correctamente."
            : "No se encontró alguno de los binarios. Revisa las rutas."
    }
}
